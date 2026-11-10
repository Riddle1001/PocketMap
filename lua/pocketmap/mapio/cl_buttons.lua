-- Push buttons move their own brush in the miniature and fire Hammer outputs.
local IO = PocketMap.MapIO
local BUTTONS = { "func_button", "func_rot_button", "momentary_rot_button" }

local function setup(state, record)
	local current = IO.State(state, record)
	if current.button then return current.button end
	local direction = IO.Direction(record)
	local rotating = record.class ~= "func_button"
	local flags = IO.Number(record.entity, "spawnflags", 0)
	local button = {
		position = 0, goal = 0, direction = direction,
		distance = rotating and IO.Number(record.entity, "distance", 90)
			or math.max(0, IO.Travel(record, direction) - IO.Number(record.entity, "lip", 4)),
		speed = math.max(1, IO.Number(record.entity, "speed", 40)),
		wait = IO.Number(record.entity, "wait", 1), locked = IO.Number(record.entity, "locked", 0) == 1,
		touchActivates = math.floor(flags / 256) % 2 == 1,
	}
	current.button = button
	return button
end

local function pose(state, record, button)
	local current = IO.State(state, record)
	if record.class ~= "func_button" then
		current.angles = Angle(record.angles.p, record.angles.y + button.position * button.distance, record.angles.r)
	else
		current.origin = record.origin + button.direction * (button.position * button.distance)
	end
end

local function press(state, record)
	local button = setup(state, record)
	if button.locked then IO.Fire(state, record, "OnUseLocked", record, record) return end
	if not IO.Enabled(state, record) or button.goal ~= 0 or button.position > 0 then return end
	button.goal, button.returnAt = 1, nil
	IO.Fire(state, record, "OnPressed", record, record)
end

local function register(class)
	IO.DynamicClass(class)
	IO.Register(class, {
		solid = true,
		use = function(state, record) press(state, record) end,
		press = function(state, record) press(state, record) end,
		lock = function(state, record) setup(state, record).locked = true end,
		unlock = function(state, record) setup(state, record).locked = false end,
		setposition = function(state, record, value)
			local fraction = tonumber(value)
			if not fraction then return end
			local button = setup(state, record)
			button.position, button.goal = math.Clamp(fraction, 0, 1), math.Clamp(fraction, 0, 1)
			pose(state, record, button)
		end,
	})
end

for _, class in ipairs(BUTTONS) do register(class) end

IO.OnStep(function(session, state, dt)
	for _, class in ipairs(BUTTONS) do
		for _, record in ipairs(IO.OfClass(state.world, class)) do
			local button = setup(state, record)
			if button.position ~= button.goal then
				local step = dt * button.speed / math.max(button.distance, 0.01)
				button.position = math.Approach(button.position, button.goal, step)
				pose(state, record, button)
				if button.position == button.goal then
					IO.Fire(state, record, button.goal == 1 and "OnIn" or "OnOut", record, record)
					if button.goal == 1 and button.wait >= 0 then button.returnAt = state.time + button.wait end
				end
			elseif button.returnAt and state.time >= button.returnAt then
				button.goal, button.returnAt = 0, nil
			end
			if button.touchActivates then
				local touching = IO.Overlaps(session, record)
				if touching and not button.touching then press(state, record) end
				button.touching = touching
			end
		end
	end
end)
