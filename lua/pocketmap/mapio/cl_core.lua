-- Hammer inputs and outputs for the virtual map. Everything lives on the miniature;
-- nothing is sent to the server or dispatched to entities in the actual map.
PocketMap.MapIO = {}
local IO = PocketMap.MapIO
local Entities = PocketMap.Entities

IO.classes = {}
IO.steps = {}
IO.dynamic = {}
IO.draws = {}

function IO.DynamicClass(class)
	IO.dynamic[class] = true
end

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

function IO.OnDraw(callback)
	IO.draws[#IO.draws + 1] = callback
end

-- Hammer brush movers use a direction and travel distance, not world coordinates.
function IO.Direction(record)
	local value = IO.Vector(IO.Value(record.entity, "movedir"))
	if value and value:Length() > 0 then return value:GetNormalized() end
	local angle = tonumber(IO.Value(record.entity, "angle"))
	if angle == -1 then return Vector(0, 0, 1) end
	if angle == -2 then return Vector(0, 0, -1) end
	if angle then return Angle(0, angle, 0):Forward() end
	return record.angles:Forward()
end

function IO.Travel(record, direction)
	if not record.model then return 0 end
	local size = record.model.maxs - record.model.mins
	return math.abs(direction.x) * size.x + math.abs(direction.y) * size.y + math.abs(direction.z) * size.z
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
	local world = { entities = {}, names = {}, byClass = {}, byEntity = {}, dynamicModels = {}, solids = {}, useTargets = {} }
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
		local handlers = IO.classes[record.class]
		if handlers and handlers.solid then world.solids[#world.solids + 1] = record end
		if handlers and handlers.use then world.useTargets[#world.useTargets + 1] = record end
		world.byEntity[entity] = record
		if index and IO.dynamic[record.class] then world.dynamicModels[index] = record end
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

function IO.Position(session, record)
	return session and IO.State(session, record).origin or record.origin
end

function IO.Rotation(session, record)
	return session and IO.State(session, record).angles or record.angles
end

function IO.Input(session, target, input, parameter, activator, caller)
	if not target then return end
	input = input:lower()
	local current = IO.State(session, target)
	local handlers = IO.classes[target.class]
	local handler = handlers and handlers[input]
	if handler then handler(session, target, parameter, activator, caller) return end
	if input == "enable" then current.enabled = true return end
	if input == "disable" then current.enabled = false return end
	if input == "toggle" then current.enabled = not current.enabled return end
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
	local model = record.model
	if not model and record.class ~= "prop_door_rotating" then return nil end
	local offset = IO.Position(state, record)
	local mins = model and model.mins or Vector(-24, -24, -8)
	local maxs = model and model.maxs or Vector(24, 24, 80)
	local angles = IO.Rotation(state, record)
	if angles.p == 0 and angles.y == 0 and angles.r == 0 then return mins + offset, maxs + offset end
	-- Rotated brush models use their axis-aligned envelope for fast player traces.
	local lo, hi = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	for x = 0, 1 do for y = 0, 1 do for z = 0, 1 do
		local corner = Vector(x == 0 and mins.x or maxs.x, y == 0 and mins.y or maxs.y, z == 0 and mins.z or maxs.z)
		local rotated = LocalToWorld(corner, Angle(), offset, angles)
		lo.x, lo.y, lo.z = math.min(lo.x, rotated.x), math.min(lo.y, rotated.y), math.min(lo.z, rotated.z)
		hi.x, hi.y, hi.z = math.max(hi.x, rotated.x), math.max(hi.y, rotated.y), math.max(hi.z, rotated.z)
	end end end
	return lo, hi
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

-- The same local BSP coordinates as Session:TraceHull, without spawning actual entities.
function IO.Trace(session, start, finish, mins, maxs, out)
	local state = session.io
	if not state then return end
	for _, record in ipairs(state.world.solids) do
		local handler = IO.classes[record.class]
		if handler and handler.solid and (handler.solid == true or handler.solid(state, record)) then
			local lo, hi = IO.Bounds(record, state)
			if lo then
				local low = lo - maxs
				local high = hi - mins
				local enter, leave, normal = 0, 1, nil
				local inside, rejected = true, false
				for _, axis in ipairs({ "x", "y", "z" }) do
					local a, b = start[axis], finish[axis]
					if a < low[axis] or a > high[axis] then inside = false end
					if math.abs(b - a) < 0.000001 then
						if a < low[axis] or a > high[axis] then rejected = true break end
					else
						local t1, t2 = (low[axis] - a) / (b - a), (high[axis] - a) / (b - a)
						local sign = -1
						if t1 > t2 then t1, t2, sign = t2, t1, 1 end
						if t1 > enter then
							enter = t1
							normal = Vector(axis == "x" and sign or 0, axis == "y" and sign or 0, axis == "z" and sign or 0)
						end
						leave = math.min(leave, t2)
					end
				end
				if not rejected then
					if inside then
						out.StartSolid = true
						if finish.x >= low.x and finish.x <= high.x and finish.y >= low.y and finish.y <= high.y and finish.z >= low.z and finish.z <= high.z then
							out.AllSolid, out.Fraction, out.Entity = true, 0, record
						end
					elseif enter <= leave and enter < out.Fraction and normal then
						out.Fraction, out.HitNormal, out.Entity = math.max(0, enter - 0.0001), normal, record
						out.Contents = CONTENTS_SOLID or 1
					end
				end
			end
		end
	end
end

-- Choose a single use target in front of the virtual eye; doors and buttons share E.
function IO.Use(session, state)
	if not session.move:KeyPressed(IN_USE) then return end
	local eye = session.move.origin + Vector(0, 0, 64)
	local forward = session.move.angles:Forward()
	local best, nearest = nil, 96
	for _, record in ipairs(state.world.useTargets) do
		local handler = IO.classes[record.class]
		if handler and handler.use then
			local lo, hi = IO.Bounds(record, state)
			if lo then
				local enter, leave = 0, nearest
				for _, axis in ipairs({ "x", "y", "z" }) do
					local speed = forward[axis]
					if math.abs(speed) < 0.000001 then
						if eye[axis] < lo[axis] or eye[axis] > hi[axis] then leave = -1 break end
					else
						local a, b = (lo[axis] - eye[axis]) / speed, (hi[axis] - eye[axis]) / speed
						if a > b then a, b = b, a end
						enter, leave = math.max(enter, a), math.min(leave, b)
					end
				end
				if enter <= leave and enter < nearest then best, nearest = record, enter end
			end
		end
	end
	if best then IO.classes[best.class].use(state, best, session) end
end

-- Faces and collision of moving brush entities must stay out of the baked static world.
function IO.BuildMeshes(mini, job)
	mini.dynamicMeshes = {}
	for record, faces in pairs(job.dynamicFaces or {}) do
		local builder = NikNaks.MeshBuilder()
		for _, face in ipairs(faces) do
			job.addOptions.material = job.materials[face:GetTexture() or "?"]
			if job.addOptions.material then builder:AddFace(face, job.addOptions) end
			face:ClearMeshData()
		end
		local inverse = Matrix()
		inverse:SetTranslation(record.origin)
		inverse:SetAngles(record.angles)
		inverse:Invert()
		mini.dynamicMeshes[#mini.dynamicMeshes + 1] = { record = record, mesh = builder:Build(), inverse = inverse, matrix = Matrix() }
		coroutine.yield()
	end
end

function IO.Draw(mini, options, translucent)
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local state = walk and walk.mini == mini and walk.io
	for _, item in ipairs(mini.dynamicMeshes or {}) do
		local matrix = item.matrix
		matrix:Set(mini.matrix)
		matrix:Translate(IO.Position(state, item.record))
		matrix:Rotate(IO.Rotation(state, item.record))
		matrix:Multiply(item.inverse)
		if translucent then item.mesh:DrawTranslucent(matrix, options) else item.mesh:DrawOpaque(matrix, options) end
	end
	for _, callback in ipairs(IO.draws) do callback(mini, state, translucent) end
end

function IO.Destroy(mini)
	for _, item in ipairs(mini.dynamicMeshes or {}) do item.mesh:Destroy() end
	mini.dynamicMeshes = nil
	if IsValid and IsValid(mini.mapIODoorProp) then mini.mapIODoorProp:Remove() end
	mini.mapIODoorProp = nil
end

function IO.Step(session, dt)
	local state = session.io
	if not state or not state.world then return end
	state.time = state.time + dt
	IO.Use(session, state)
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
