-- Hammer inputs and outputs for the virtual map. Everything lives on the miniature;
-- nothing is sent to the server or dispatched to entities in the actual map.
PocketMap.MapIO = PocketMap.MapIO or {}
local IO = PocketMap.MapIO
local Entities = PocketMap.Entities

IO.classes = IO.classes or {}
IO.steps = IO.steps or {}
IO.dynamic = IO.dynamic or {}
IO.draws = IO.draws or {}
IO.registrationVersion = IO.registrationVersion or 0

-- Auto-refresh reloads individual files. Keep existing handlers and replace
-- each file's step/draw callback instead of accumulating duplicate hooks.
local function callbackSources(callbacks)
	local unique, sources = {}, {}
	for _, callback in ipairs(callbacks) do
		local source = debug.getinfo(callback, "S").source
		local index = sources[source]
		if index then
			unique[index] = callback
		else
			unique[#unique + 1] = callback
			sources[source] = #unique
		end
	end
	return unique, sources
end

IO.steps, IO.stepSources = callbackSources(IO.steps)
IO.draws, IO.drawSources = callbackSources(IO.draws)

local function registerCallback(callbacks, sources, callback)
	local source = debug.getinfo(callback, "S").source
	local index = sources[source]
	if index then
		callbacks[index] = callback
	else
		callbacks[#callbacks + 1] = callback
		sources[source] = #callbacks
	end
end

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
	IO.registrationVersion = IO.registrationVersion + 1
end

function IO.OnStep(callback)
	registerCallback(IO.steps, IO.stepSources, callback)
end

function IO.OnDraw(callback)
	registerCallback(IO.draws, IO.drawSources, callback)
end

-- Hammer brush movers use a direction and travel distance, not world coordinates.
function IO.Direction(record)
	-- Hammer stores movedir as pitch/yaw/roll. Pitch -90 points upward;
	-- treating those three values as a vector makes vertical doors immobile.
	local value = IO.Value(record.entity, "movedir")
	if isangle(value) then return value:Forward() end
	local angles = IO.Vector(value)
	if angles then return Angle(angles.x, angles.y, angles.z):Forward() end
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
	local world = { entities = {}, names = {}, byClass = {}, byEntity = {}, dynamicModels = {}, solids = {}, useTargets = {}, registrationVersion = IO.registrationVersion }
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
	-- A miniature may predate a Lua auto-refresh of the Map I/O loader.
	if mini.bsp and (not mini.mapIO or not mini.mapIO.solids or mini.mapIO.registrationVersion ~= IO.registrationVersion) then
		IO.Build(mini, mini.bsp:GetEntities())
	end
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

-- Moving entities notify the collision index when their pose changes. Static
-- doors and brushes then cost nothing to maintain between movement commands.
function IO.PoseChanged(state, record)
	state.traceDirty = state.traceDirty or {}
	state.traceDirty[record] = true
	state.drawRevision = (state.drawRevision or 0) + 1
end

function IO.Input(session, target, input, parameter, activator, caller)
	if not target then return end
	-- Inputs may also arrive between render hooks (e.g. a use event).
	-- Invalidate the shared brush visibility list even without a movement tick.
	session.drawRevision = (session.drawRevision or 0) + 1
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
-- Prop doors have their own model-space bounds. The brush fallback was centered
-- on the wrong Z and much thicker than common door models, leaving invisible
-- collision in the doorway even when the visible door was correctly placed.
local doorModelBounds = IO.doorModelBounds or {}
IO.doorModelBounds = doorModelBounds

local function solidModelBounds(record)
	if record.class ~= "prop_door_rotating" then
		return record.model and record.model.mins, record.model and record.model.maxs
	end
	local path = IO.Value(record.entity, "model")
	if type(path) ~= "string" or not path:lower():find("%.mdl$") then
		return Vector(-24, -24, -8), Vector(24, 24, 80)
	end
	local key = path:lower()
	local bounds = doorModelBounds[key]
	if bounds == nil then
		bounds = false
		local model = ClientsideModel(path, RENDERGROUP_OTHER)
		if IsValid(model) then
			model:SetNoDraw(true)
			local mins, maxs = model:GetModelBounds()
			if mins and maxs and (maxs - mins):LengthSqr() > 1 then
				bounds = { mins = mins, maxs = maxs }
			end
			model:Remove()
		end
		doorModelBounds[key] = bounds
	end
	if bounds then return bounds.mins, bounds.maxs end
	return Vector(-24, -24, -8), Vector(24, 24, 80)
end

function IO.Bounds(record, state)
	local mins, maxs = solidModelBounds(record)
	if not mins then return nil end
	local offset = IO.Position(state, record)
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

-- Index brush bounds once per walking session, then refresh moved brushes as
-- commands advance. Every ground, wall and stair probe shares this index.
local TRACE_CELL_SIZE = 256
local TRACE_AXES = { "x", "y", "z" }
local TRACE_WORLD_AXES = { Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1) }

-- An OBB narrow phase keeps the player hull aligned with the map while the
-- prop door swings. Its AABB is still used for cheap spatial lookup.
local function doorTraceShape(record, state)
	if record.class ~= "prop_door_rotating" then return end
	local mins, maxs = solidModelBounds(record)
	local origin, angles = IO.Position(state, record), IO.Rotation(state, record)
	return {
		center = LocalToWorld((mins + maxs) * 0.5, Angle(), origin, angles),
		half = (maxs - mins) * 0.5,
		axes = { angles:Forward(), -angles:Right(), angles:Up() },
	}
end

local function traceCells(lo, hi)
	return math.floor(lo.x / TRACE_CELL_SIZE), math.floor(hi.x / TRACE_CELL_SIZE),
		math.floor(lo.y / TRACE_CELL_SIZE), math.floor(hi.y / TRACE_CELL_SIZE)
end

local function removeTraceEntry(grid, entry)
	for x = entry.x1, entry.x2 do
		local column = grid.cells[x]
		for y = entry.y1, entry.y2 do
			local cell = column[y]
			for i = #cell, 1, -1 do
				if cell[i] == entry then table.remove(cell, i) break end
			end
			if #cell == 0 then column[y] = nil end
		end
		if not next(column) then grid.cells[x] = nil end
	end
end

local function setTraceBounds(grid, entry, lo, hi)
	local x1, x2, y1, y2 = traceCells(lo, hi)
	if entry.x1 and (entry.x1 ~= x1 or entry.x2 ~= x2 or entry.y1 ~= y1 or entry.y2 ~= y2) then
		removeTraceEntry(grid, entry)
	end
	if entry.x1 ~= x1 or entry.x2 ~= x2 or entry.y1 ~= y1 or entry.y2 ~= y2 then
		for x = x1, x2 do
			local column = grid.cells[x]
			if not column then column = {} grid.cells[x] = column end
			for y = y1, y2 do
				local cell = column[y]
				if not cell then cell = {} column[y] = cell end
				cell[#cell + 1] = entry
			end
		end
	end
	entry.x1, entry.x2, entry.y1, entry.y2 = x1, x2, y1, y2
	entry.lo, entry.hi = lo, hi
end

local function rememberTracePose(entry, origin, angles)
	entry.px, entry.py, entry.pz = origin.x, origin.y, origin.z
	entry.pitch, entry.yaw, entry.roll = angles.p, angles.y, angles.r
end

local function traceGrid(session, state)
	local grid = session.mapIOTraceGrid
	if not grid or grid.world ~= state.world or not grid.byRecord or not grid.hasDoorShapes then
		grid = { world = state.world, cells = {}, entries = {}, byRecord = {}, hasDoorShapes = true }
		for _, record in ipairs(state.world.solids) do
			local handler = IO.classes[record.class]
			if handler and handler.solid and (handler.solid == true or handler.solid(state, record)) then
				local current = state.records[record]
				local origin = current and current.origin or record.origin
				local angles = current and current.angles or record.angles
				local entry = { record = record }
				rememberTracePose(entry, origin, angles)
				local lo, hi = IO.Bounds(record, state)
				if lo then
					setTraceBounds(grid, entry, lo, hi)
					entry.doorShape = doorTraceShape(record, state)
					grid.entries[#grid.entries + 1] = entry
					grid.byRecord[record] = entry
				end
			end
		end
		session.mapIOTraceGrid = grid
		state.traceDirty = nil -- initial bounds already include every current pose
	end
	local dirty = state.traceDirty
	if dirty then
		for record in pairs(dirty) do
			local entry = grid.byRecord[record]
			if entry then
				local current = state.records[record]
				local origin = current and current.origin or record.origin
				local angles = current and current.angles or record.angles
				if origin.x ~= entry.px or origin.y ~= entry.py or origin.z ~= entry.pz
					or angles.p ~= entry.pitch or angles.y ~= entry.yaw or angles.r ~= entry.roll then
					rememberTracePose(entry, origin, angles)
					local lo, hi = IO.Bounds(record, state)
					if lo then
						setTraceBounds(grid, entry, lo, hi)
						entry.doorShape = doorTraceShape(record, state)
					end
				end
			end
		end
		state.traceDirty = nil
	end
	return grid
end

local function traceSolid(record, lo, hi, start, finish, mins, maxs, out)
	local enter, leave, normalAxis, normalSign = 0, 1, nil, nil
	local inside = true
	for _, axis in ipairs(TRACE_AXES) do
		local low, high = lo[axis] - maxs[axis], hi[axis] - mins[axis]
		local a, b = start[axis], finish[axis]
		if a < low or a > high then inside = false end
		if math.abs(b - a) < 0.000001 then
			if a < low or a > high then return end
		else
			local t1, t2 = (low - a) / (b - a), (high - a) / (b - a)
			local sign = -1
			if t1 > t2 then t1, t2, sign = t2, t1, 1 end
			if t1 > enter then
				enter = t1
				normalAxis, normalSign = axis, sign
			end
			leave = math.min(leave, t2)
		end
	end
	if inside then
		out.StartSolid = true
		if finish.x >= lo.x - maxs.x and finish.x <= hi.x - mins.x
			and finish.y >= lo.y - maxs.y and finish.y <= hi.y - mins.y
			and finish.z >= lo.z - maxs.z and finish.z <= hi.z - mins.z then
			out.AllSolid, out.Fraction, out.Entity = true, 0, record
		end
	elseif enter <= leave and enter < out.Fraction and normalAxis then
		out.Fraction = math.max(0, enter - 0.0001)
		out.HitNormal = Vector(normalAxis == "x" and normalSign or 0,
			normalAxis == "y" and normalSign or 0, normalAxis == "z" and normalSign or 0)
		out.Entity = record
		out.Contents = CONTENTS_SOLID or 1
	end
end

-- Swept SAT: exact overlap times for the moving, axis-aligned player box and
-- the rotated door box, including corner contacts. At most 15 separating axes.
local function traceDoor(record, shape, start, finish, mins, maxs, out)
	-- Movement traces pass xyz tables; SAT axes still use actual Vectors.
	local center = Vector(start.x + (mins.x + maxs.x) * 0.5,
		start.y + (mins.y + maxs.y) * 0.5, start.z + (mins.z + maxs.z) * 0.5)
	local delta = center - shape.center
	local motion = Vector(finish.x - start.x, finish.y - start.y, finish.z - start.z)
	local half = Vector((maxs.x - mins.x) * 0.5, (maxs.y - mins.y) * 0.5,
		(maxs.z - mins.z) * 0.5)
	local doorHalf, doorAxes = shape.half, shape.axes
	local enter, leave = -math.huge, math.huge
	local normal, normalSign
	local startsInside, endsInside = true, true
	local function axisOverlap(axis)
		local lenSqr = axis:LengthSqr()
		if lenSqr < 0.00000001 then return true end
		if math.abs(lenSqr - 1) > 0.000001 then axis = axis / math.sqrt(lenSqr) end
		local radius = math.abs(axis.x) * half.x + math.abs(axis.y) * half.y + math.abs(axis.z) * half.z
			+ math.abs(axis:Dot(doorAxes[1])) * doorHalf.x
			+ math.abs(axis:Dot(doorAxes[2])) * doorHalf.y
			+ math.abs(axis:Dot(doorAxes[3])) * doorHalf.z
		local distance = delta:Dot(axis)
		local speed = motion:Dot(axis)
		if math.abs(distance) > radius then startsInside = false end
		if math.abs(distance + speed) > radius then endsInside = false end
		if math.abs(speed) < 0.000001 then return math.abs(distance) <= radius end
		local first, last = (-radius - distance) / speed, (radius - distance) / speed
		if first > last then first, last = last, first end
		if first > enter then enter, normal, normalSign = first, axis, speed > 0 and -1 or 1 end
		leave = math.min(leave, last)
		return enter <= leave
	end
	for i = 1, 3 do
		if not axisOverlap(TRACE_WORLD_AXES[i]) or not axisOverlap(doorAxes[i]) then return end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if not axisOverlap(TRACE_WORLD_AXES[i]:Cross(doorAxes[j])) then return end
		end
	end
	if startsInside then
		out.StartSolid = true
		if endsInside then
			out.AllSolid, out.Fraction, out.Entity = true, 0, record
		end
	elseif enter >= 0 and enter <= leave and enter < out.Fraction and normal then
		out.Fraction = math.max(0, enter - 0.0001)
		out.HitNormal = normal * normalSign
		out.Entity = record
		out.Contents = CONTENTS_SOLID or 1
	end
end

-- The same local BSP coordinates as Session:TraceHull, without spawning actual entities.
function IO.Trace(session, start, finish, mins, maxs, out)
	local state = session.io
	if not state or not state.world or not state.world.solids then return end
	local grid = traceGrid(session, state)
	local loX, hiX = math.min(start.x, finish.x) + mins.x, math.max(start.x, finish.x) + maxs.x
	local loY, hiY = math.min(start.y, finish.y) + mins.y, math.max(start.y, finish.y) + maxs.y
	local x1, x2 = math.floor(loX / TRACE_CELL_SIZE), math.floor(hiX / TRACE_CELL_SIZE)
	local y1, y2 = math.floor(loY / TRACE_CELL_SIZE), math.floor(hiY / TRACE_CELL_SIZE)
	local z1 = math.min(start.z, finish.z) + mins.z
	local z2 = math.max(start.z, finish.z) + maxs.z
	-- One monotonically increasing query marker avoids allocating a seen table
	-- for every ground/step/wall probe spanning multiple hash cells.
	local query = (grid.query or 0) + 1
	grid.query = query
	for x = x1, x2 do
		local column = grid.cells[x]
		if column then
			for y = y1, y2 do
				local cell = column[y]
				if cell then
					for _, entry in ipairs(cell) do
						if entry.query ~= query then
							entry.query = query
							if entry.lo.x <= hiX and entry.hi.x >= loX
								and entry.lo.y <= hiY and entry.hi.y >= loY
								and entry.lo.z <= z2 and entry.hi.z >= z1 then
								if entry.doorShape then
									traceDoor(entry.record, entry.doorShape, start, finish, mins, maxs, out)
								else
									traceSolid(entry.record, entry.lo, entry.hi, start, finish, mins, maxs, out)
								end
							end
						end
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
local function meshPasses(mesh)
	local opaque, translucent = false, false
	for _, part in ipairs(mesh:GetMeshes()) do
		if part.translucent then translucent = true else opaque = true end
	end
	for _, part in ipairs(mesh:GetLightMeshes()) do
		if part.translucent then translucent = true else opaque = true end
	end
	return opaque, translucent
end

local ZERO_ANGLE = Angle()
local PVS_MAX_RADIUS = 2048
local PVS_MAX_LEAFS = 128
local OCCLUSION_MAX_RADIUS = 350
local OCCLUSION_EYE_DISTANCE = 2
local cvBrushOcclusion = CreateClientConVar("pocketmap_mapio_occlusion", "1", true, false,
	"Cull miniature MapIO brushes fully behind static BSP surfaces while the viewer is stationary")

-- Use the same vertices NikNaks puts in its brush meshes: GetVertexs() omits
-- the bmodel transform applied by GenerateVertexTriangleData(). A missing
-- bound leaves the brush visible. Displacements have GPU-smoothed geometry.
local function brushBounds(faces, record)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, face in ipairs(faces) do
		if face:IsDisplacement() then return end
		local vertices = face:GenerateVertexTriangleData()
		if not vertices or #vertices < 3 then return end
		for _, vertex in ipairs(vertices) do
			local point = vertex.pos
			if not point then return end
			minX, minY, minZ = math.min(minX, point.x), math.min(minY, point.y), math.min(minZ, point.z)
			maxX, maxY, maxZ = math.max(maxX, point.x), math.max(maxY, point.y), math.max(maxZ, point.z)
		end
	end
	if minX == math.huge or maxX == math.huge or minX ~= minX or maxX ~= maxX
		or minY ~= minY or maxY ~= maxY or minZ ~= minZ or maxZ ~= maxZ then return end
	local center = Vector((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
	local radius = Vector(maxX - minX, maxY - minY, maxZ - minZ):Length() * 0.5 + 2
	if radius ~= radius or radius >= math.huge then return end
	return WorldToLocal(center, ZERO_ANGLE, record.origin, record.angles), radius
end

function IO.BuildMeshes(mini, job)
	mini.dynamicMeshes = {}
	mini.dynamicOpaque, mini.dynamicTranslucent = {}, {}
	mini.mapIOPassesSource, mini.mapIODrawCache = mini.dynamicMeshes, nil
	mini.mapIOMeshWorld = nil
	for record, faces in pairs(job.dynamicFaces or {}) do
		local localCenter, radius = brushBounds(faces, record)
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
		local mesh = builder:Build()
		local opaque, translucent = meshPasses(mesh)
		local item = {
			record = record, mesh = mesh, inverse = inverse, matrix = Matrix(),
			opaque = opaque, translucent = translucent,
			localCenter = localCenter, radius = radius,
		}
		mini.dynamicMeshes[#mini.dynamicMeshes + 1] = item
		if opaque then mini.dynamicOpaque[#mini.dynamicOpaque + 1] = item end
		if translucent then mini.dynamicTranslucent[#mini.dynamicTranslucent + 1] = item end
		coroutine.yield()
	end
end

-- A new walking session can rebuild its entity records after the miniature's
-- brush meshes were compiled. Rebind by BSP model index so animations use the
-- same records as the active I/O session. This runs only when the world changes.
local function bindMeshRecords(mini, world)
	if not world or mini.mapIOMeshWorld == world then return end
	for _, item in ipairs(mini.dynamicMeshes or {}) do
		local old = item.record
		local current = old and world.dynamicModels[old.modelIndex]
		if current and current.class == old.class and current ~= old then
			item.record = current
			item.stamp, item.matrixPose = nil, nil
			item.visibleView, item.checkedPVS, item.clustersChecked = nil, nil, nil
		end
	end
	mini.mapIOMeshWorld = world
	mini.mapIODrawCache, mini.mapIOOcclusion = nil, nil
end

-- Existing miniatures can survive Lua auto-refresh. Index their compiled
-- meshes on demand instead of scanning every brush in both render passes.
local function passMeshes(mini, translucent)
	if mini.mapIOPassesSource ~= mini.dynamicMeshes or not mini.dynamicOpaque or not mini.dynamicTranslucent then
		local opaque, transparent = {}, {}
		for _, item in ipairs(mini.dynamicMeshes or {}) do
			if item.opaque == nil then item.opaque, item.translucent = meshPasses(item.mesh) end
			if item.opaque then opaque[#opaque + 1] = item end
			if item.translucent then transparent[#transparent + 1] = item end
		end
		mini.dynamicOpaque, mini.dynamicTranslucent = opaque, transparent
		mini.mapIOPassesSource, mini.mapIODrawCache = mini.dynamicMeshes, nil
	end
	return translucent and mini.dynamicTranslucent or mini.dynamicOpaque
end

-- The miniature's transform is constant while its block is still. Keep one
-- stamp for all brush models so their matrices survive repeated render passes.
local function drawStamp(mini)
	if mini.matrixFrame and mini.mapIODrawFrame == mini.matrixFrame then return mini.mapIODrawStamp end
	mini.mapIODrawFrame = mini.matrixFrame
	local pos, ang = mini.ent:GetPos(), mini.ent:GetAngles()
	if not mini.mapIODrawStamp or mini.mapIODrawX ~= pos.x or mini.mapIODrawY ~= pos.y or mini.mapIODrawZ ~= pos.z
		or mini.mapIODrawPitch ~= ang.p or mini.mapIODrawYaw ~= ang.y or mini.mapIODrawRoll ~= ang.r then
		mini.mapIODrawStamp = (mini.mapIODrawStamp or 0) + 1
		mini.mapIODrawX, mini.mapIODrawY, mini.mapIODrawZ = pos.x, pos.y, pos.z
		mini.mapIODrawPitch, mini.mapIODrawYaw, mini.mapIODrawRoll = ang.p, ang.y, ang.r
	end
	return mini.mapIODrawStamp
end

-- Only the primary recorded view has a known camera. Reflection targets and
-- other render views can use a different frustum, so draw everything in them.
local function drawView(mini)
	if PocketMap.Water and PocketMap.Water.pass then return end
	if render.GetRenderTarget and render.GetRenderTarget() then return end
	local water = PocketMap.Water
	local view = water and water.view
	if not view or view.frame ~= FrameNumber() or not view.origin or not view.angles
		or not view.fov or view.fov <= 0 or view.fov >= 170 then return end
	if EyePos():DistToSqr(view.origin) > 1 then return end
	if EyeAngles():Forward():Dot(view.angles:Forward()) < 0.999 then return end
	if view.mapIOFrustum then return view end

	local forward, right, up = view.angles:Forward(), view.angles:Right(), view.angles:Up()
	local aspect = ScrW() / math.max(ScrH(), 1)
	local halfH = math.tan(math.rad(view.fov) * 0.5) * math.max(1, aspect / (4 / 3)) * 1.3
	local halfV = halfH / aspect
	local normals = { forward, forward * halfH + right, forward * halfH - right,
		forward * halfV + up, forward * halfV - up }
	for _, normal in ipairs(normals) do normal:Normalize() end
	view.mapIOFrustum = normals
	return view
end

-- Re-evaluate PVS when the viewer enters another BSP cluster, not each draw.
-- A missing or invalid vis lump is never sufficient evidence to hide a brush.
local function drawPVS(mini, walk, view)
	if not walk or walk.mini ~= mini or not walk.io or not view or not mini.scale or mini.scale <= 0
		or not mini.bsp or not mini:EyeInside() then return end
	local frozen = PocketMap.PVSFreeze.Get(mini)
	if frozen then return frozen end
	local bsp = mini.bsp
	local eye = (mini.ent:WorldToLocal(view.origin) - mini.boxCenter) / mini.scale + mini.mapCenter
	local cluster = bsp:ClusterFromPoint(eye)
	if not cluster or cluster < 0 then return end
	local vis = bsp:GetVisibility()
	if not vis or not vis.VisData or not vis.VisData[cluster] or bsp:IsVisibilityCorrupted() then return end
	if mini.mapIOPVSCluster ~= cluster or mini.mapIOPVSBSP ~= bsp then
		mini.mapIOPVSCluster, mini.mapIOPVSBSP = cluster, bsp
		mini.mapIOPVS = bsp:PVSForOrigin(eye)
	end
	return mini.mapIOPVS
end

-- A sphere encompassing the brush can span several visibility leaves. Cull
-- only if every valid cluster it touches is absent from the current PVS.
local function brushClusters(bsp, item)
	if not item.mapCenter or not item.radius or item.radius > PVS_MAX_RADIUS then return end
	local leaves = bsp:SphereInLeafs(0, item.mapCenter, item.radius + 2)
	if #leaves == 0 or #leaves > PVS_MAX_LEAFS then return end
	local clusters, seen = {}, {}
	for _, leaf in ipairs(leaves) do
		local cluster = leaf and leaf.cluster
		if not cluster then return end
		if cluster < 0 then
			if not leaf.contents or bit.band(leaf.contents, CONTENTS_SOLID) == 0 then return end
		elseif not seen[cluster] then
			seen[cluster] = true
			clusters[#clusters + 1] = cluster
		end
	end
	if #clusters > 0 then return clusters end
end

local function brushVisible(mini, item, view, pvs, poseChanged, stamp)
	if not view or not item.localCenter then return true end
	-- The opaque and translucent hooks often render the same brush and camera.
	if item.visibleView == view and item.visibleStamp == stamp and item.visiblePose == item.pose
		and item.visiblePVS == pvs then
		return item.visibleResult
	end
	local visible = true
	if pvs then
		if not item.clustersChecked then
			item.clusters = brushClusters(mini.bsp, item)
			item.clustersChecked = true
		end
		if item.clusters then
			if item.checkedPVS ~= pvs then
				item.checkedPVS, item.pvsVisible = pvs, false
				for _, cluster in ipairs(item.clusters) do
					if pvs[cluster] then item.pvsVisible = true break end
				end
			end
			if not item.pvsVisible then visible = false end
		end
	end

	if visible then
		if poseChanged or item.worldStamp ~= stamp then
			item.worldCenter = mini.matrix * item.mapCenter
			item.worldStamp = stamp
		end
		local center, origin = item.worldCenter, view.origin
		local dx, dy, dz = center.x - origin.x, center.y - origin.y, center.z - origin.z
		local radius = item.radius * mini.scale
		for _, normal in ipairs(view.mapIOFrustum) do
			if dx * normal.x + dy * normal.y + dz * normal.z < -radius then visible = false break end
		end
	end
	item.visibleView, item.visibleStamp, item.visiblePose, item.visiblePVS, item.visibleResult = view, stamp, item.pose, pvs, visible
	return visible
end

-- Tracing the center and the eight expanded bounds corners rejects only brushes
-- whose entire bounding sphere is well behind the static map. Unknown views,
-- large models and moving cameras retain the original drawing behavior.
local function brushBehindWorld(mini, item, eye)
	if not item.mapCenter or not item.radius or item.radius <= 0 or item.radius > OCCLUSION_MAX_RADIUS then return false end
	local bsp = mini.bsp
	local function blocked(target)
		local trace = bsp:SurfaceTraceLine(eye, target)
		return trace and trace.Hit and not trace.HitSky and trace.Fraction < 0.95
	end
	local center = item.mapCenter
	if not blocked(center) then return false end
	local extent = item.radius + 5
	for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
		if not blocked(center + Vector(x * extent, y * extent, z * extent)) then return false end
	end end end
	return true
end

local function brushOcclusion(mini, pvs, view)
	if not cvBrushOcclusion:GetBool() or not pvs or not view or not mini.bsp.SurfaceTraceLine then return end
	local eye = (mini.ent:WorldToLocal(view.origin) - mini.boxCenter) / mini.scale + mini.mapCenter
	local cache = mini.mapIOOcclusion
	if not cache or cache.meshes ~= mini.dynamicMeshes or cache.bsp ~= mini.bsp then
		cache = { meshes = mini.dynamicMeshes, bsp = mini.bsp, generation = 0 }
		mini.mapIOOcclusion = cache
	end
	if not cache.eye or cache.pvs ~= pvs or cache.eye:DistToSqr(eye) > OCCLUSION_EYE_DISTANCE ^ 2 then
		cache.eye, cache.pvs = eye, pvs
		cache.generation = cache.generation + 1
		cache.queue, cache.nextIndex, cache.count = {}, 1, 0
		cache.nextAt = CurTime() + 0.2
	end
	return cache
end

local function brushKnownHidden(item, cache)
	if not cache or not item.mapCenter or not item.radius or item.radius > OCCLUSION_MAX_RADIUS then return false end
	if item.occlusionCache == cache and item.occlusionGeneration == cache.generation
		and item.occlusionPose == item.pose then return item.occludedByWorld end
	local request = item.occlusionRequest
	if request and request.pending and request.cache == cache and request.generation == cache.generation then
		-- Keep one queued job for an animating door; its latest pose wins.
		request.pose = item.pose
	else
		cache.count = cache.count + 1
		request = { item = item, pose = item.pose, cache = cache, generation = cache.generation, pending = true }
		cache.queue[cache.count] = request
		item.occlusionRequest = request
	end
	return false
end

-- One expensive BSP probe per frame. Pose changes invalidate moving doors,
-- and the view position invalidates cached results when the player walks.
local function traceNextBrush(mini, cache)
	if not cache or cache.frame == FrameNumber() or CurTime() < cache.nextAt then return end
	local index = cache.nextIndex
	if index > cache.count then return end
	cache.frame, cache.nextIndex = FrameNumber(), index + 1
	local queued = cache.queue[index]
	cache.queue[index] = nil
	queued.pending = false
	local item = queued.item
	if item.pose ~= queued.pose then return end
	item.occludedByWorld = brushBehindWorld(mini, item, cache.eye)
	item.occlusionCache, item.occlusionGeneration, item.occlusionPose = cache, cache.generation, item.pose
end


-- Pose, cull and transform once for a matching pair of main-view render
-- passes. Always prepare afresh for mirrors, water and unknown cameras.
local function visibleMeshes(mini, state, view, pvs, stamp, opaque, transparent)
	opaque, transparent = opaque or {}, transparent or {}
	local records = state and state.records
	local occlusion = brushOcclusion(mini, pvs, view)
	-- Reuse the prior main-view lists, retaining their capacity across frames.
	-- Unknown cameras get independent temporary lists.
	for i = #opaque, 1, -1 do opaque[i] = nil end
	for i = #transparent, 1, -1 do transparent[i] = nil end
	for _, item in ipairs(mini.dynamicMeshes or {}) do
		if item.opaque or item.translucent then
			-- Render reads don't need to initialize session state. A single
			-- records lookup replaces two IO.State calls per brush per frame.
			local record = item.record
			local current = records and records[record]
			local origin = current and current.origin or record.origin
			local angles = current and current.angles or record.angles
			local poseChanged = item.x ~= origin.x or item.y ~= origin.y or item.z ~= origin.z
				or item.pitch ~= angles.p or item.yaw ~= angles.y or item.roll ~= angles.r
			if poseChanged then
				item.x, item.y, item.z = origin.x, origin.y, origin.z
				item.pitch, item.yaw, item.roll = angles.p, angles.y, angles.r
				item.pose = (item.pose or 0) + 1
				if item.localCenter then item.mapCenter = LocalToWorld(item.localCenter, ZERO_ANGLE, origin, angles) end
				item.clustersChecked, item.clusters, item.checkedPVS = nil, nil, nil
			end
			if brushVisible(mini, item, view, pvs, poseChanged, stamp) and not brushKnownHidden(item, occlusion) then
				if item.stamp ~= stamp or item.matrixPose ~= item.pose then
					local matrix = item.matrix
					matrix:Set(mini.matrix)
					matrix:Translate(origin)
					matrix:Rotate(angles)
					matrix:Mul(item.inverse)
					item.stamp = stamp
					item.matrixPose = item.pose
				end
				if item.opaque then opaque[#opaque + 1] = item end
				if item.translucent then transparent[#transparent + 1] = item end
			end
		end
	end
	traceNextBrush(mini, occlusion)
	return opaque, transparent
end

function IO.Draw(mini, options, translucent)
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local state = walk and walk.mini == mini and walk.io
	bindMeshRecords(mini, state and state.world or mini.mapIO)
	local pass = passMeshes(mini, translucent)
	if #pass > 0 then
		local view = not (options and (options.ignoreZ or options.lightOnly)) and drawView(mini)
		local stamp = drawStamp(mini)
		local frame = FrameNumber()
		local cache = mini.mapIODrawCache
		local time = state and state.time
		local revision = state and state.drawRevision
		if not view or not cache or cache.frame ~= frame or cache.view ~= view
			or cache.state ~= state or cache.time ~= time or cache.revision ~= revision
			or cache.stamp ~= stamp or cache.source ~= mini.dynamicMeshes then
			local pvs = drawPVS(mini, walk, view)
			if not view then cache = nil end
			local opaque, transparent = visibleMeshes(mini, state, view, pvs, stamp,
				cache and cache.opaque, cache and cache.translucent)
			cache = cache or {}
			cache.frame, cache.view, cache.state, cache.time = frame, view, state, time
			cache.revision, cache.stamp, cache.source = revision, stamp, mini.dynamicMeshes
			cache.opaque, cache.translucent = opaque, transparent
			if view then mini.mapIODrawCache = cache end
		end
		local visible = translucent and cache.translucent or cache.opaque
		for i = 1, #visible do
			local item = visible[i]
			if translucent then item.mesh:DrawTranslucent(item.matrix, options)
			else item.mesh:DrawOpaque(item.matrix, options) end
		end
	end
	for _, callback in ipairs(IO.draws) do callback(mini, state, translucent) end
end

function IO.Destroy(mini)
	for _, item in ipairs(mini.dynamicMeshes or {}) do item.mesh:Destroy() end
	mini.dynamicMeshes = nil
	mini.dynamicOpaque, mini.dynamicTranslucent = nil, nil
	mini.mapIOPassesSource, mini.mapIODrawCache = nil, nil
	mini.mapIOMeshWorld = nil
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
