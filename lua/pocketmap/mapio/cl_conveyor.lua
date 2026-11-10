-- Conveyors carry the miniature walker without moving real Source entities.
local IO = PocketMap.MapIO

local function setup(state, record)
	local current = IO.State(state, record)
	if current.conveyor then return current.conveyor end
	local conveyor = { direction = IO.Direction(record), speed = IO.Number(record.entity, "speed", 100) }
	current.conveyor = conveyor
	return conveyor
end

IO.Register("func_conveyor", {
	setspeed = function(state, record, value)
		local speed = tonumber(value)
		if speed then setup(state, record).speed = speed end
	end,
	start = function(state, record) IO.State(state, record).enabled = true end,
	stop = function(state, record) IO.State(state, record).enabled = false end,
})

IO.OnStep(function(session, state, dt)
	if session.noclip then return end
	for _, record in ipairs(IO.OfClass(state.world, "func_conveyor")) do
		local conveyor = setup(state, record)
		local lo, hi = IO.Bounds(record, state)
		local move = session.move
		local touching = lo and IO.Overlaps(session, record)
			and move.origin.z >= hi.z - 8 and move.origin.z <= hi.z + 8
		if touching and IO.Enabled(state, record) and conveyor.speed ~= 0 then
			local nextPos = move.origin + conveyor.direction * conveyor.speed * dt
			if session.TraceHull then
				local tr = session:TraceHull(move.origin, nextPos, Vector(-16, -16, 0), Vector(16, 16, 72))
				move.origin = move.origin + (nextPos - move.origin) * tr.Fraction
			else
				move.origin = nextPos
			end
			if not state.touching[record] then IO.Fire(state, record, "OnStartTouch", record, record) end
		else
			if state.touching[record] then IO.Fire(state, record, "OnEndTouch", record, record) end
		end
		state.touching[record] = touching and IO.Enabled(state, record) and conveyor.speed ~= 0 or nil
	end
end)
