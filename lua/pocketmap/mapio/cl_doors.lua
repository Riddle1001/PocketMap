-- Brush and prop doors live in each virtual walking session.
local IO = PocketMap.MapIO

local DOORS = { "func_door", "func_door_rotating", "prop_door_rotating" }
local function rotating(record) return record.class ~= "func_door" end

local function setup(state, record)
	local current = IO.State(state, record)
	if current.door then return current.door end
	local flags = IO.Number(record.entity, "spawnflags", 0)
	local direction = IO.Direction(record)
	local distance = rotating(record) and IO.Number(record.entity, "distance", 90)
		or math.max(0, IO.Travel(record, direction) - IO.Number(record.entity, "lip", 8))
	local opened = flags % 2 == 1
	local door = {
		position = opened and 1 or 0, goal = opened and 1 or 0,
		distance = distance, direction = direction,
		speed = math.max(1, IO.Number(record.entity, "speed", rotating(record) and 100 or 100)),
		wait = IO.Number(record.entity, "wait", 4), toggle = math.floor(flags / 32) % 2 == 1,
		useOnly = record.class == "prop_door_rotating" or math.floor(flags / 256) % 2 == 1,
	}
	current.door = door
	if opened then
		if rotating(record) then
			current.angles = Angle(record.angles.p, record.angles.y + distance, record.angles.r)
		else
			current.origin = record.origin + direction * distance
		end
		IO.PoseChanged(state, record)
	end
	return door
end

local function updatePose(state, record, door)
	local current = IO.State(state, record)
	if rotating(record) then
		current.angles = Angle(record.angles.p, record.angles.y + door.position * door.distance, record.angles.r)
	else
		current.origin = record.origin + door.direction * (door.position * door.distance)
	end
	IO.PoseChanged(state, record)
end

local function setGoal(state, record, goal)
	local current = IO.State(state, record)
	if not current.enabled then return end
	local door = setup(state, record)
	if door.goal == goal and (door.position == goal or door.moving) then return end
	if door.position == goal then return end
	door.goal, door.moving, door.closeAt = goal, true, nil
	IO.Fire(state, record, goal == 1 and "OnOpen" or "OnClose", record, record)
end

local function toggle(state, record)
	local door = setup(state, record)
	setGoal(state, record, door.goal == 1 and 0 or 1)
end

local function handlers()
	return {
		solid = true,
		use = function(state, record) toggle(state, record) end,
		open = function(state, record) setGoal(state, record, 1) end,
		close = function(state, record) setGoal(state, record, 0) end,
		toggle = function(state, record) toggle(state, record) end,
		setposition = function(state, record, value)
			local door = setup(state, record)
			local amount = tonumber(value)
			if not amount then return end
			door.position, door.goal, door.moving = math.Clamp(amount, 0, 1), math.Clamp(amount, 0, 1), false
			updatePose(state, record, door)
		end,
	}
end

for _, class in ipairs(DOORS) do
	IO.Register(class, handlers())
	if class ~= "prop_door_rotating" then IO.DynamicClass(class) end
end

IO.OnStep(function(session, state, dt)
	for _, class in ipairs(DOORS) do
		for _, record in ipairs(IO.OfClass(state.world, class)) do
			local door = setup(state, record)
			if door.moving then
				local delta = dt * door.speed / math.max(door.distance, 0.01)
				door.position = math.Clamp(door.position + (door.goal == 1 and delta or -delta), 0, 1)
				updatePose(state, record, door)
				if door.position == door.goal then
					door.moving = false
					IO.Fire(state, record, door.goal == 1 and "OnFullyOpen" or "OnFullyClosed", record, record)
					if door.goal == 1 and door.wait >= 0 and not door.toggle then door.closeAt = state.time + door.wait end
				end
			elseif door.closeAt and state.time >= door.closeAt then
				setGoal(state, record, 0)
			end
			if not door.useOnly and not door.moving and door.goal == 0 then
				local touching = not session.noclip and IO.Overlaps(session, record, Vector(-24, -24, 0), Vector(24, 24, 72))
				if touching and not door.touching then setGoal(state, record, 1) end
				door.touching = touching
			end
		end
	end
end)

-- Prop doors are models rather than brush faces, so draw them with the same
-- miniature placement as other entity props, using the session's current yaw.
local FRUSTUM_PAD = 5
local PVS_MAX_RADIUS = 2048
local PVS_MAX_LEAVES = 128
local OCCLUSION_PAD = 8
local OCCLUSION_RECHECK_DISTANCE = 16
local ZERO_ANGLE = Angle()
local cvDoorOcclusion = CreateClientConVar("pocketmap_door_occlusion", "1", true, false,
	"Skip miniature prop doors fully hidden behind BSP walls; checks are spread over frames.", 0, 1)

-- The render view is allowed to differ from the player's camera. In a nested
-- view or an unfamiliar projection, leave the model visible.
local function doorFrustum(mini)
	if PocketMap.Water and PocketMap.Water.pass then return end
	if render.GetRenderTarget and render.GetRenderTarget() then return end
	local view = render.GetViewSetup()
	if not view or not view.origin or not view.angles or view.ortho or view.offcenter or view.subrect then return end
	if EyePos():DistToSqr(view.origin) > 1 then return end
	if EyeAngles():Forward():Dot(view.angles:Forward()) < 0.999 then return end
	local fov, width, height = view.fov, view.width, view.height
	if not fov or fov <= 1 or fov * 0.5 + FRUSTUM_PAD >= 90
		or not width or not height or width <= 0 or height <= 0 then return end
	local aspect = width / height
	-- Source may report horizontal FOV for a 4:3 reference viewport.
	local halfWidth = math.tan(math.rad(fov * 0.5 + FRUSTUM_PAD)) * math.max(1, aspect / (4 / 3))
	if view.aspect and view.aspect > 0 then aspect = math.min(aspect, view.aspect) end
	local halfHeight = halfWidth / aspect
	local angles = mini.ent:WorldToLocalAngles(view.angles)
	return {
		origin = mini.ent:WorldToLocal(view.origin),
		forward = angles:Forward(), right = angles:Right(), up = angles:Up(),
		halfWidth = halfWidth, halfHeight = halfHeight,
		widthRadius = math.sqrt(1 + halfWidth * halfWidth),
		heightRadius = math.sqrt(1 + halfHeight * halfHeight),
	}
end

local function inFrustum(entry, view)
	if not view or not entry.blockRadius then return true end
	local center, origin = entry.blockCenter, view.origin
	local dx, dy, dz = center.x - origin.x, center.y - origin.y, center.z - origin.z
	local forward, right, up = view.forward, view.right, view.up
	local distance = dx * forward.x + dy * forward.y + dz * forward.z
	local radius = entry.blockRadius
	if distance + radius < 0 then return false end
	if math.abs(dx * right.x + dy * right.y + dz * right.z) > distance * view.halfWidth + radius * view.widthRadius then return false end
	if math.abs(dx * up.x + dy * up.y + dz * up.z) > distance * view.halfHeight + radius * view.heightRadius then return false end
	return true
end

local function doorClusters(bsp, origin, radius)
	if not bsp or not radius or radius > PVS_MAX_RADIUS then return end
	local leaves = bsp:SphereInLeafs(0, origin, radius + 4)
	if not leaves or #leaves == 0 or #leaves > PVS_MAX_LEAVES then return end
	local clusters, seen = {}, {}
	for _, leaf in ipairs(leaves) do
		if not leaf or not leaf.cluster then return end
		if leaf.cluster < 0 then
			if not leaf.contents or bit.band(leaf.contents, 1) == 0 then return end
		elseif not seen[leaf.cluster] then
			seen[leaf.cluster] = true
			clusters[#clusters + 1] = leaf.cluster
		end
	end
	if #clusters > 0 then return clusters end
end

local function doorPVS(mini, view)
	if not view or not mini.bsp or not mini.scale or mini.scale <= 0 or not mini:EyeInside() then return end
	local walk = PocketMap.Walk and PocketMap.Walk.session
	if not walk or walk.mini ~= mini then return end
	local frozen = PocketMap.PVSFreeze.Get(mini)
	if frozen then return frozen end
	-- Match visibility to the rendered eye, including view offsets and camera motion.
	local eye = (view.origin - mini.boxCenter) / mini.scale + mini.mapCenter
	local bsp = mini.bsp
	local cluster = bsp:ClusterFromPoint(eye)
	if not cluster or cluster < 0 then return end
	local vis = bsp:GetVisibility()
	if not vis or not vis.VisData or not vis.VisData[cluster] or bsp:IsVisibilityCorrupted() then return end
	if mini.doorPVSCluster ~= cluster or mini.doorPVSBSP ~= bsp then
		mini.doorPVSCluster, mini.doorPVSBSP = cluster, bsp
		mini.doorPVSData = bsp:PVSForOrigin(eye)
	end
	return mini.doorPVSData
end

local function inPVS(info, pvs)
	if not pvs or not info.clusters then return true end
	if info.checkedPVS ~= pvs then
		info.checkedPVS, info.inPVS = pvs, false
		for _, cluster in ipairs(info.clusters) do
			if pvs[cluster] then info.inPVS = true break end
		end
	end
	return info.inPVS
end

local function modelRadius(model)
	local mins, maxs = model:GetModelRenderBounds()
	if not mins or not maxs then return end
	local x = math.max(math.abs(mins.x), math.abs(maxs.x))
	local y = math.max(math.abs(mins.y), math.abs(maxs.y))
	local z = math.max(math.abs(mins.z), math.abs(maxs.z))
	local radius = math.sqrt(x * x + y * y + z * z) + 8
	if radius < math.huge and radius == radius then return radius end
end

-- Model bounds are resolved outside Draw. On some render passes, the model
-- entity temporarily reports no bounds immediately after SetModel.
hook.Add("Think", "PocketMap_DoorBounds", function()
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local mini = walk and walk.mini
	if not mini or mini.mapIODoorBoundsReady then return end
	local cache = mini.mapIODoorRenderBounds
	if not cache then return end
	if (mini.mapIODoorBoundsAttempts or 0) >= 4 then return end
	if (mini.mapIODoorBoundsNextTry or 0) > CurTime() then return end
	mini.mapIODoorBoundsNextTry = CurTime() + 1
	local missing = false
	for path, value in pairs(cache) do
		if not value then
			local model = ClientsideModel(path, RENDERGROUP_OTHER)
			if IsValid(model) then
				model:SetNoDraw(true)
				local mins, maxs = model:GetModelRenderBounds()
				if mins and maxs then cache[path] = {mins = mins, maxs = maxs}
				else missing = true end
				model:Remove()
			else missing = true end
		end
	end
	for _, entry in ipairs(mini.mapIODoorEntries or {}) do
		entry.renderBounds = cache[entry.path]
	end
	mini.mapIODoorBoundsAttempts = (mini.mapIODoorBoundsAttempts or 0) + 1
	mini.mapIODoorBoundsReady = not missing
end)

-- The model and the BSP leaves around a door's pivot are static until its
-- origin changes. Build this information once, instead of rereading 300+
-- Hammer entities and checking their frusta in every render pass.
local function doorEntries(mini, state, records, model)
	local previous = mini.mapIODoorEntries
	if mini.mapIODoorEntriesSource == records and mini.mapIODoorEntriesModel == model
		and mini.mapIODoorRenderBounds and previous and (not previous[1] or previous[1].blockCenter) then
		return mini.mapIODoorEntries
	end

	local boundsByModel = mini.mapIODoorModelBounds or {}
	local renderBounds = mini.mapIODoorRenderBounds or {}
	local entries = {}
	for _, record in ipairs(records) do
		local path = IO.Value(record.entity, "model")
		if type(path) == "string" and path:lower():find("%.mdl$") then
			local radius = boundsByModel[path]
			if radius == nil then
				model:SetModel(path)
				radius = modelRadius(model) or false
				boundsByModel[path] = radius
			end
			if renderBounds[path] == nil then
				model:SetModel(path)
				local mins, maxs = model:GetModelRenderBounds()
				renderBounds[path] = mins and maxs and {mins = mins, maxs = maxs} or false
			end
			local position = IO.Position(state, record)
			local info = { bsp = mini.bsp, radius = radius,
				origin = Vector(position.x, position.y, position.z),
				clusters = doorClusters(mini.bsp, position, radius or nil) }
			entries[#entries + 1] = { record = record, path = path,
				skin = IO.Number(record.entity, "skin", 0), radius = radius, info = info,
				renderBounds = renderBounds[path],
				blockCenter = mini:BlockPosition(position),
				blockRadius = radius and radius * mini.scale or nil }
		end
	end
	mini.mapIODoorModelBounds = boundsByModel
	mini.mapIODoorRenderBounds = renderBounds
	mini.mapIODoorBoundsReady = false
	mini.mapIODoorEntriesSource, mini.mapIODoorEntriesModel = records, model
	mini.mapIODoorEntries = entries
	mini.mapIODoorCandidateSource = nil
	mini.mapIODoorLastPath, mini.mapIODoorLastScale, mini.mapIODoorLastSkin = nil, nil, nil
	return entries
end

-- Trace the actual model's eight padded corners in source-map coordinates.
-- A single exposed corner keeps the whole door visible. Static BSP faces are
-- used as occluders, so doors opened by map I/O remain fully interactive.
local function doorBehindWorld(mini, state, entry, eye)
	local bounds = entry.renderBounds
	if not bounds or not mini.bsp.SurfaceTraceLine then return false end
	local mins, maxs = bounds.mins, bounds.maxs
	local origin = IO.Position(state, entry.record)
	local rotation = IO.Rotation(state, entry.record)
	local function blocked(corner)
		local target = LocalToWorld(corner, ZERO_ANGLE, origin, rotation)
		local trace = mini.bsp:SurfaceTraceLine(eye, target)
		return trace and trace.Hit and not trace.HitSky and trace.Fraction < 0.96
	end
	-- A narrow opening can expose the door's center while hiding every
	-- corner. Keep the door if any of these representative rays is open.
	if not blocked((mins + maxs) * 0.5) then return false end
	for x = 0, 1 do for y = 0, 1 do for z = 0, 1 do
		local corner = Vector(x == 0 and mins.x - OCCLUSION_PAD or maxs.x + OCCLUSION_PAD,
			y == 0 and mins.y - OCCLUSION_PAD or maxs.y + OCCLUSION_PAD,
			z == 0 and mins.z - OCCLUSION_PAD or maxs.z + OCCLUSION_PAD)
		if not blocked(corner) then return false end
	end end end
	return true
end

-- Compute at most one door each frame, after the eye settles. A moving
-- camera draws unverified doors until a new conservative result is ready.
local function updateDoorOcclusion(mini, state, entries, candidates, pvs, view)
	if not cvDoorOcclusion:GetBool() or not pvs or not view or not state then return nil end
	local eye = (view.origin - mini.boxCenter) / mini.scale + mini.mapCenter
	local cache = mini.mapIODoorOcclusion
	if not cache or cache.entries ~= entries then
		cache = {entries = entries, generation = 0}
		mini.mapIODoorOcclusion = cache
	end
	if not cache.eye or cache.eye:DistToSqr(eye) > OCCLUSION_RECHECK_DISTANCE ^ 2 or cache.pvs ~= pvs then
		cache.eye, cache.pvs, cache.nextIndex = eye, pvs, 1
		cache.generation = cache.generation + 1
		cache.nextAt = CurTime() + 0.25
	end
	if cache.nextIndex <= #candidates and CurTime() >= cache.nextAt and cache.frame ~= FrameNumber() then
		cache.frame = FrameNumber()
		local entry = candidates[cache.nextIndex]
		cache.nextIndex = cache.nextIndex + 1
		local position, rotation = IO.Position(state, entry.record), IO.Rotation(state, entry.record)
		entry.occludedByWorld = doorBehindWorld(mini, state, entry, cache.eye)
		entry.occlusionPosition, entry.occlusionRotation = position, rotation
		entry.occlusionGeneration = cache.generation
	end
	return cache
end

local function knownHidden(entry, state, cache)
	if not cache or entry.occlusionGeneration ~= cache.generation or not entry.occludedByWorld then return false end
	local position, rotation = IO.Position(state, entry.record), IO.Rotation(state, entry.record)
	return entry.occlusionPosition == position and entry.occlusionRotation == rotation
end

-- PVS remains constant while the viewer stays in one BSP cluster. A door
-- rotates around its pivot; a map input changing that pivot invalidates the
-- candidate list via the session's draw revision.
local function doorCandidates(mini, state, entries, pvs)
	local revision = state and state.drawRevision
	if mini.mapIODoorCandidateSource == entries and mini.mapIODoorCandidatePVS == pvs
		and mini.mapIODoorCandidateState == state and mini.mapIODoorCandidateRevision == revision then
		return mini.mapIODoorCandidates
	end

	local candidates = mini.mapIODoorCandidates or {}
	for i = #candidates, 1, -1 do candidates[i] = nil end
	for _, entry in ipairs(entries) do
		local position = IO.Position(state, entry.record)
		local info = entry.info
		if info.bsp ~= mini.bsp or info.origin:DistToSqr(position) > 0 then
			info.bsp = mini.bsp
			info.origin = Vector(position.x, position.y, position.z)
			info.clusters = doorClusters(mini.bsp, position, entry.radius or nil)
			info.checkedPVS = nil
			entry.blockCenter = mini:BlockPosition(position)
		end
		if inPVS(info, pvs) then candidates[#candidates + 1] = entry end
	end
	mini.mapIODoorCandidates = candidates
	mini.mapIODoorCandidateSource, mini.mapIODoorCandidatePVS = entries, pvs
	mini.mapIODoorCandidateState, mini.mapIODoorCandidateRevision = state, revision
	return candidates
end

IO.OnDraw(function(mini, state, translucent)
	if translucent or not mini.mapIO or not ClientsideModel then return end
	local records = IO.OfClass(mini.mapIO, "prop_door_rotating")
	if #records == 0 then return end
	if not IsValid(mini.mapIODoorProp) then
		mini.mapIODoorProp = ClientsideModel("models/error.mdl", RENDERGROUP_OTHER)
		mini.mapIODoorProp:SetNoDraw(true)
	end
	local model = mini.mapIODoorProp
	local frustum = doorFrustum(mini)
	local pvs = doorPVS(mini, frustum)
	local entries = doorEntries(mini, state, records, model)
	local candidates = doorCandidates(mini, state, entries, pvs)
	local occlusion = updateDoorOcclusion(mini, state, entries, candidates, pvs, frustum)
	local lastPath, lastScale, lastSkin = mini.mapIODoorLastPath, mini.mapIODoorLastScale, mini.mapIODoorLastSkin
	local stamp = mini.mapIODrawStamp
	local entPos, entAng = mini.ent:GetPos(), mini.ent:GetAngles()
	local drawn = 0
	local hidden = 0
	for _, entry in ipairs(candidates) do
		local record = entry.record
		local position = IO.Position(state, record)
		if inFrustum(entry, frustum) then
			if knownHidden(entry, state, occlusion) then
				hidden = hidden + 1
			else
			drawn = drawn + 1
			local changed = entry.path ~= lastPath
			if changed then model:SetModel(entry.path) lastPath = entry.path end
			if changed or mini.scale ~= lastScale then model:SetModelScale(mini.scale, 0) lastScale = mini.scale end
			if changed or entry.skin ~= lastSkin then model:SetSkin(entry.skin) lastSkin = entry.skin end

			local rotation = IO.Rotation(state, record)
			if entry.stamp ~= stamp or entry.origin ~= position or entry.rotation ~= rotation then
				entry.wpos, entry.wang = LocalToWorld(mini:BlockPosition(position), rotation, entPos, entAng)
				entry.stamp, entry.origin, entry.rotation = stamp, position, rotation
			end
			model:SetPos(entry.wpos)
			model:SetAngles(entry.wang)
			-- A single ClientsideModel renders many doors each frame. Source caches
			-- its first bone transform unless bones are rebuilt between draws.
			model:SetupBones()
			model:DrawModel()
			end
		end
	end
	mini.mapIODoorLastPath, mini.mapIODoorLastScale, mini.mapIODoorLastSkin = lastPath, lastScale, lastSkin
	mini.mapIODoorsDrawn = drawn
	mini.mapIODoorsOccluded = hidden
end)
