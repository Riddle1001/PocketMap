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
				local touching = IO.Overlaps(session, record, Vector(-24, -24, 0), Vector(24, 24, 72))
				if touching and not door.touching then setGoal(state, record, 1) end
				door.touching = touching
			end
		end
	end
end)

-- Prop doors are models rather than brush faces, so draw them with the same
-- miniature placement as other entity props, using the session's current yaw.
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
	for _, record in ipairs(records) do
		local path = IO.Value(record.entity, "model")
		if type(path) == "string" and path:lower():find("%.mdl$") then
			if path ~= lastPath then model:SetModel(path) lastPath = path end
			model:SetModelScale(mini.scale, 0)
			local pos, ang = LocalToWorld(mini:BlockPosition(IO.Position(state, record)), IO.Rotation(state, record), mini.ent:GetPos(), mini.ent:GetAngles())
			model:SetPos(pos)
			model:SetAngles(ang)
			model:SetSkin(IO.Number(record.entity, "skin", 0))
			model:DrawModel()
		end
	end
end)
