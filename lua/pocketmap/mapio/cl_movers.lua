-- Linear movers and trains follow their Hammer paths in local miniature space.
local IO = PocketMap.MapIO
local MOVERS = { "func_movelinear", "func_tracktrain", "func_train" }

local function path(state, name)
	if type(name) ~= "string" then return nil end
	for _, record in ipairs(state.world.names[name:lower()] or {}) do
		if record.class == "path_track" or record.class == "path_corner" then return record end
	end
end

local function setup(state, record)
	local current = IO.State(state, record)
	if current.mover then return current.mover end
	local linear = record.class == "func_movelinear"
	local mover = {
		linear = linear, speed = math.max(1, IO.Number(record.entity, "speed", linear and 100 or 64)),
		active = not linear and IO.Number(record.entity, "speed", 0) > 0,
		goal = 0, position = 0, direction = IO.Direction(record),
		distance = IO.Number(record.entity, "movedistance", 100),
		path = linear and nil or path(state, IO.Value(record.entity, "target")),
	}
	current.mover = mover
	return mover
end

local function setGoal(state, record, goal)
	local mover = setup(state, record)
	if not IO.Enabled(state, record) then return end
	mover.goal, mover.active = goal, true
	IO.Fire(state, record, goal == 1 and "OnOpen" or "OnClose", record, record)
end

for _, class in ipairs(MOVERS) do
	IO.DynamicClass(class)
	IO.Register(class, {
		solid = true,
		open = function(state, record) setGoal(state, record, 1) end,
		close = function(state, record) setGoal(state, record, 0) end,
		toggle = function(state, record)
			local mover = setup(state, record)
			if mover.linear then setGoal(state, record, mover.goal == 1 and 0 or 1)
			else mover.active = not mover.active end
		end,
		setposition = function(state, record, value)
			local fraction = tonumber(value)
			if not fraction then return end
			local mover = setup(state, record)
			if not mover.linear then return end
			mover.position, mover.goal = math.Clamp(fraction, 0, 1), math.Clamp(fraction, 0, 1)
			IO.State(state, record).origin = record.origin + mover.direction * mover.distance * mover.position
		end,
		setspeed = function(state, record, value)
			local speed = tonumber(value)
			if speed then setup(state, record).speed = math.max(0, speed) end
		end,
		startforward = function(state, record) setup(state, record).active = true end,
		startbackward = function(state, record)
			local mover = setup(state, record)
			mover.active = true
			if mover.linear then mover.goal = 0 end
		end,
		stop = function(state, record) setup(state, record).active = false end,
		resume = function(state, record) setup(state, record).active = true end,
		teleporttopathtrack = function(state, record, value)
			local target = path(state, value)
			if not target then return end
			local mover = setup(state, record)
			mover.path = path(state, IO.Value(target.entity, "target"))
			IO.State(state, record).origin = target.origin
		end,
	})
end

IO.OnStep(function(session, state, dt)
	for _, class in ipairs(MOVERS) do
		for _, record in ipairs(IO.OfClass(state.world, class)) do
			local mover = setup(state, record)
			if mover.active and IO.Enabled(state, record) and mover.speed > 0 then
				local current = IO.State(state, record)
				if mover.linear then
					local step = dt * mover.speed / math.max(mover.distance, 0.01)
					mover.position = math.Approach(mover.position, mover.goal, step)
					current.origin = record.origin + mover.direction * mover.distance * mover.position
					if mover.position == mover.goal then
						mover.active = false
						IO.Fire(state, record, mover.goal == 1 and "OnFullyOpen" or "OnFullyClosed", record, record)
					end
				elseif mover.path then
					local difference = mover.path.origin - current.origin
					local distance = difference:Length()
					if distance <= dt * mover.speed then
						current.origin = mover.path.origin
						IO.Fire(state, mover.path, "OnPass", record, record)
						IO.Fire(state, mover.path, "OnTrigger", record, record)
						mover.path = path(state, IO.Value(mover.path.entity, "target"))
						if not mover.path then mover.active = false IO.Fire(state, record, "OnStop", record, record) end
					elseif distance > 0 then
						current.origin = current.origin + difference * (dt * mover.speed / distance)
					end
				else
					mover.active = false
				end
			end
		end
	end
end)
