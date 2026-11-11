-- A trigger_teleport moves the virtual walker to its info_teleport_destination.
local IO = PocketMap.MapIO

-- One trigger entity can contain several convex brushes. Its bmodel bounds
-- enclose the gaps too (surf_ace uses those gaps for drops into later ramps).
local function triggerBrushes(session, record)
	if record.teleportBrushes ~= nil then return record.teleportBrushes end
	local bsp = session.bsp or (session.mini and session.mini.bsp)
	if not record.model or not bsp or not bsp.GetNodes or not bsp.GetLeafs then return end
	local nodes, leafs = bsp:GetNodes(), bsp:GetLeafs()
	local stack, seen, brushes, added = { record.model.headnode }, {}, {}, {}
	while #stack > 0 do
		local index = table.remove(stack)
		if not seen[index] then
			seen[index] = true
			if index < 0 then
				local leaf = leafs[-1 - index]
				if leaf then
					for _, brush in ipairs(leaf:GetBrushes()) do
						if not added[brush] then
							added[brush] = true
							brushes[#brushes + 1] = brush
						end
					end
				end
			else
				local node = nodes[index]
				if node then
					stack[#stack + 1] = node.children[1]
					stack[#stack + 1] = node.children[2]
				end
			end
		end
	end
	record.teleportBrushes = #brushes > 0 and brushes or false
	return record.teleportBrushes
end

function IO.TeleportOverlaps(session, record)
	local mins, maxs
	if PocketMap.Movement then mins, maxs = PocketMap.Movement.PlayerHull(LocalPlayer(), session.ducking) end
	mins, maxs = mins or Vector(-16, -16, 0), maxs or Vector(16, 16, 72)
	if not IO.Overlaps(session, record, mins, maxs) then return false end
	local brushes = triggerBrushes(session, record)
	if not brushes then return true end
	local origin, angles = IO.Position(session.io, record), IO.Rotation(session.io, record)
	local rotated = angles.p ~= 0 or angles.y ~= 0 or angles.r ~= 0
	local pos = session.move.origin - origin
	for _, brush in ipairs(brushes) do
		local inside = true
		for _, side in ipairs(brush.sides) do
			local plane = side.plane
			local n = plane.normal
			if rotated then n = LocalToWorld(n, Angle(), Vector(), angles) end
			-- Expand each brush plane by the world-aligned player hull, including
			-- BSP bevel planes. Keep the brush origin/rotation in map coordinates.
			local offset = n.x * (n.x < 0 and maxs.x or mins.x)
				+ n.y * (n.y < 0 and maxs.y or mins.y)
				+ n.z * (n.z < 0 and maxs.z or mins.z)
			if n.x * pos.x + n.y * pos.y + n.z * pos.z + offset > plane.dist then
				inside = false
				break
			end
		end
		if inside then return true end
	end
	return false
end

IO.Register("trigger_teleport", {})

local function destination(state, source)
	local name = IO.Value(source.entity, "target")
	if type(name) ~= "string" then return end
	for _, target in ipairs(state.world.names[name:lower()] or {}) do
		if target.class == "info_teleport_destination" or target.class == "info_target" then return target end
	end
end

local function teleport(session, state, source)
	local target = destination(state, source)
	if not target then return end
	local move = session.move
	local before = move.angles.y
	move.origin = target.origin + Vector(0, 0, 2)
	move.velocity = Vector()
	move.angles = Angle(target.angles.p, target.angles.y, 0)
	move.moveAngles = move.angles
	session.yawOffset = session.yawOffset + target.angles.y - before
	session.onground = false
	IO.Fire(state, source, "OnStartTouch", source, source)
	IO.Fire(state, source, "OnTrigger", source, source)
end

IO.OnStep(function(session, state)
	for _, record in ipairs(IO.OfClass(state.world, "trigger_teleport")) do
		local touching = IO.Enabled(state, record) and IO.TeleportOverlaps(session, record)
		if touching and not state.touching[record] then teleport(session, state, record) end
		if not touching and state.touching[record] then IO.Fire(state, record, "OnEndTouch", record, record) end
		state.touching[record] = touching or nil
	end
end)
