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

local function inFrustum(mini, position, radius, view)
	if not view or not radius then return true end
	local delta = mini:BlockPosition(position) - view.origin
	local distance = delta:Dot(view.forward)
	radius = radius * mini.scale
	if distance + radius < 0 then return false end
	if math.abs(delta:Dot(view.right)) > distance * view.halfWidth + radius * view.widthRadius then return false end
	if math.abs(delta:Dot(view.up)) > distance * view.halfHeight + radius * view.heightRadius then return false end
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

IO.OnDraw(function(mini, state, translucent)
	if translucent or not mini.mapIO or not ClientsideModel then return end
	local records = IO.OfClass(mini.mapIO, "prop_door_rotating")
	if #records == 0 then return end
	if not IsValid(mini.mapIODoorProp) then
		mini.mapIODoorProp = ClientsideModel("models/error.mdl", RENDERGROUP_OTHER)
		mini.mapIODoorProp:SetNoDraw(true)
	end
	local model = mini.mapIODoorProp
	local lastPath
	local boundsByModel = mini.mapIODoorModelBounds or {}
	local boundsByDoor = mini.mapIODoorBounds or {}
	mini.mapIODoorModelBounds, mini.mapIODoorBounds = boundsByModel, boundsByDoor
	local frustum = doorFrustum(mini)
	local pvs = doorPVS(mini, frustum)
	local drawn = 0
	for _, record in ipairs(records) do
		local path = IO.Value(record.entity, "model")
		if type(path) == "string" and path:lower():find("%.mdl$") then
			local radius = boundsByModel[path]
			if radius == nil then
				if path ~= lastPath then model:SetModel(path) lastPath = path end
				radius = modelRadius(model) or false
				boundsByModel[path] = radius
			end
			local position = IO.Position(state, record)
			local info = boundsByDoor[record]
			-- Rotating about the pivot needs no new bounds; translation does.
			if not info or not info.origin or info.bsp ~= mini.bsp or info.radius ~= radius
				or info.origin:DistToSqr(position) > 0 then
				info = {
					bsp = mini.bsp, radius = radius,
					origin = Vector(position.x, position.y, position.z),
					clusters = doorClusters(mini.bsp, position, radius or nil),
				}
				boundsByDoor[record] = info
			end
			if inFrustum(mini, position, radius or nil, frustum) and inPVS(info, pvs) then
				drawn = drawn + 1
				if path ~= lastPath then model:SetModel(path) lastPath = path end
				model:SetModelScale(mini.scale, 0)
				local pos, ang = LocalToWorld(mini:BlockPosition(position), IO.Rotation(state, record), mini.ent:GetPos(), mini.ent:GetAngles())
				model:SetPos(pos)
				model:SetAngles(ang)
				model:SetSkin(IO.Number(record.entity, "skin", 0))
				model:DrawModel()
			end
		end
	end
	mini.mapIODoorsDrawn = drawn
end)
