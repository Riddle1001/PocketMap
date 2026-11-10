-- A trigger_teleport moves the virtual walker to its info_teleport_destination.
local IO = PocketMap.MapIO

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
		local touching = IO.Enabled(state, record) and IO.Overlaps(session, record)
		if touching and not state.touching[record] then teleport(session, state, record) end
		if not touching and state.touching[record] then IO.Fire(state, record, "OnEndTouch", record, record) end
		state.touching[record] = touching or nil
	end
end)
