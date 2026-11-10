-- Hammer inputs and outputs for the virtual map. Everything lives on the miniature;
-- nothing is sent to the server or dispatched to entities in the actual map.
PocketMap.MapIO = {}
local IO = PocketMap.MapIO
local Entities = PocketMap.Entities

IO.classes = {}
IO.steps = {}

function IO.Value(entity, name)
	local value = entity[name]
	if value == nil then
		for key, other in pairs(entity) do
			if type(key) == "string" and key:lower() == name:lower() then value = other break end
		end
	end
	return Entities.First(value)
end

function IO.Number(entity, name, default)
	return tonumber(IO.Value(entity, name)) or default
end

function IO.Vector(value)
	if isvector(value) then return Vector(value.x, value.y, value.z) end
	if type(value) ~= "string" then return nil end
	local x, y, z = value:match("^%s*([%+%-%.%deE]+)%s+([%+%-%.%deE]+)%s+([%+%-%.%deE]+)")
	if not (tonumber(x) and tonumber(y) and tonumber(z)) then return nil end
	return Vector(tonumber(x), tonumber(y), tonumber(z))
end

function IO.Angle(value)
	if isangle(value) then return Angle(value.p, value.y, value.r) end
	local vec = IO.Vector(value)
	return vec and Angle(vec.x, vec.y, vec.z) or Angle()
end

function IO.Register(class, handlers)
	IO.classes[class] = handlers
end

function IO.OnStep(callback)
	IO.steps[#IO.steps + 1] = callback
end

local function outputs(entity)
	local result = {}
	for key, value in pairs(entity) do
		if type(key) == "string" and key:sub(1, 2):lower() == "on" then
			local list = type(value) == "table" and value or { value }
			for _, raw in ipairs(list) do
				if type(raw) == "string" then
					local target, input, parameter, delay, limit = raw:gsub("\27", ","):match("^([^,]*),([^,]*),([^,]*),([^,]*),?([^,]*)")
					if target and input then
						result[key:lower()] = result[key:lower()] or {}
						local events = result[key:lower()]
						events[#events + 1] = { target = string.Trim(target):lower(), input = string.Trim(input):lower(), parameter = parameter, delay = math.max(0, tonumber(delay) or 0), remaining = tonumber(limit) or -1 }
					end
				end
			end
		end
	end
	return result
end

function IO.Build(mini, entities)
	local world = { entities = {}, names = {}, byClass = {}, byEntity = {} }
	local models = mini.bsp:GetBModels()
	for _, entity in pairs(entities) do
		local model = IO.Value(entity, "model")
		local index = type(model) == "string" and tonumber(model:match("^%*(%d+)$"))
		local record = {
			entity = entity, class = Entities.Class(entity), name = Entities.Name(entity),
			origin = IO.Vector(IO.Value(entity, "origin")) or Vector(),
			angles = IO.Angle(IO.Value(entity, "angles")), model = index and models[index], modelIndex = index,
			outputs = outputs(entity), enabled = IO.Number(entity, "StartDisabled", 0) ~= 1,
		}
		world.entities[#world.entities + 1] = record
		world.byEntity[entity] = record
		world.byClass[record.class] = world.byClass[record.class] or {}
		world.byClass[record.class][#world.byClass[record.class] + 1] = record
		if record.name then
			world.names[record.name] = world.names[record.name] or {}
			table.insert(world.names[record.name], record)
		end
	end
	mini.mapIO = world
	return world
end

function IO.OfClass(world, class)
	return world.byClass[class] or {}
end

function IO.NewSession(mini)
	return { world = mini.mapIO, touching = {}, time = 0, queue = {}, counts = {}, records = {} }
end

-- A BSP entity is immutable; only a walking session owns its current state.
function IO.State(session, record)
	local state = session.records[record]
	if not state then
		state = { enabled = record.enabled, origin = record.origin, angles = record.angles }
		session.records[record] = state
	end
	return state
end

function IO.Enabled(session, record)
	return IO.State(session, record).enabled
end

function IO.Input(session, target, input, parameter, activator, caller)
	if not target then return end
	input = input:lower()
	local current = IO.State(session, target)
	if input == "enable" then current.enabled = true return end
	if input == "disable" then current.enabled = false return end
	if input == "toggle" then current.enabled = not current.enabled return end
	local handlers = IO.classes[target.class]
	local handler = handlers and handlers[input]
	if handler then handler(session, target, parameter, activator, caller) end
end

function IO.Fire(session, source, name, activator, caller)
	local events = source.outputs[name:lower()]
	if not events then return end
	for _, event in ipairs(events) do
		local remaining = session.counts[event] or event.remaining
		if remaining ~= 0 then
			if remaining > 0 then session.counts[event] = remaining - 1 end
			session.queue[#session.queue + 1] = { at = session.time + event.delay, event = event, source = source, activator = activator, caller = caller or source }
		end
	end
end

local function dispatch(session, queued)
	local event = queued.event
	local name = event.target
	local targets
	if name == "!self" then targets = { queued.source }
	elseif name == "!caller" then targets = { queued.caller }
	elseif name == "!activator" then targets = { queued.activator }
	else targets = session.world.names[name] end
	for _, target in ipairs(targets or {}) do
		IO.Input(session, target, event.input, event.parameter, queued.activator, queued.caller)
	end
end

-- Hull / bmodel overlap is shared by triggers, buttons and movers.
function IO.Bounds(record, state)
	if record.model then
		local offset = state and IO.State(state, record).origin or record.origin
		return record.model.mins + offset, record.model.maxs + offset
	end
	return nil
end

function IO.Overlaps(session, record, mins, maxs)
	local lo, hi = IO.Bounds(record, session.io)
	if not lo then return false end
	local pos = session.move.origin
	mins, maxs = mins or Vector(-16, -16, 0), maxs or Vector(16, 16, 72)
	return pos.x + maxs.x >= lo.x and pos.x + mins.x <= hi.x
		and pos.y + maxs.y >= lo.y and pos.y + mins.y <= hi.y
		and pos.z + maxs.z >= lo.z and pos.z + mins.z <= hi.z
end

function IO.Step(session, dt)
	local state = session.io
	if not state or not state.world then return end
	state.time = state.time + dt
	for _, callback in ipairs(IO.steps) do callback(session, state, dt) end
	-- An output can enqueue more outputs; bound chains of zero-delay relays.
	local i, processed = 1, 0
	while i <= #state.queue and processed < 128 do
		local entry = table.remove(state.queue, i)
		if entry.at <= state.time then
			dispatch(state, entry)
			processed = processed + 1
		else
			table.insert(state.queue, i, entry)
			i = i + 1
		end
	end
end
