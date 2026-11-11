-- Standalone Lua 5.1 checks. Run from the PocketMap root: lua tests/mapio.lua
local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector) end
function vector.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vector.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vector.__unm(a) return Vector(-a.x, -a.y, -a.z) end
function vector.__div(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
function vector.__mul(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector(a.x * b, a.y * b, a.z * b)
end
function vector:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function vector:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function vector:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function vector:Cross(b) return Vector(self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x) end
function vector:DistToSqr(b) return (self - b):Length() ^ 2 end
function vector:GetNormalized() local len = self:Length() return len == 0 and Vector() or self * (1 / len) end
function isvector(v) return getmetatable(v) == vector end

local angle = {}
angle.__index = angle
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, angle) end
function isangle(v) return getmetatable(v) == angle end
function angle:Forward()
	local p, y = math.rad(self.p), math.rad(self.y)
	return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function angle:Right()
	local y = math.rad(self.y)
	return Vector(-math.sin(y), math.cos(y), 0)
end
function angle:Up() return Vector(0, 0, 1) end
function LocalToWorld(pos, _, origin, angles)
	local y = math.rad(angles.y)
	return origin + Vector(pos.x * math.cos(y) - pos.y * math.sin(y), pos.x * math.sin(y) + pos.y * math.cos(y), pos.z)
end
IN_USE = 32
function math.Clamp(n, a, b) return math.max(a, math.min(b, n)) end
function math.Approach(n, target, amount) return n < target and math.min(target, n + amount) or math.max(target, n - amount) end

function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateClientConVar() return { GetBool = function() return true end } end
hook = { Add = function() end }
function ClientsideModel() return nil end
function IsValid(value) return value ~= nil and value ~= false end
PocketMap = { Entities = {} }
function PocketMap.Entities.First(v) return type(v) == "table" and getmetatable(v) == nil and v[1] or v end
function PocketMap.Entities.Class(ent) return tostring(ent.classname or ""):lower() end
function PocketMap.Entities.Name(ent) return ent.targetname and ent.targetname:lower() end

dofile("lua/pocketmap/mapio/cl_core.lua")
dofile("lua/pocketmap/mapio/cl_teleport.lua")
dofile("lua/pocketmap/mapio/cl_doors.lua")
dofile("lua/pocketmap/mapio/cl_buttons.lua")
dofile("lua/pocketmap/mapio/cl_movers.lua")
dofile("lua/pocketmap/mapio/cl_conveyor.lua")

local IO = PocketMap.MapIO
local models = {
	[1] = { mins = Vector(-20, -20, -8), maxs = Vector(20, 20, 80) },
	[2] = { mins = Vector(-40, -8, 0), maxs = Vector(40, 8, 80) },
	[3] = { mins = Vector(-2.49, -64, -62), maxs = Vector(2.51, 64, 62) },
}
local function world(entities)
	local mini = { bsp = { GetBModels = function() return models end } }
	IO.Build(mini, entities)
	local state = IO.NewSession(mini)
	local move = { origin = Vector(-200, 0, 0), velocity = Vector(4, 1, 2), angles = Angle(0, 20, 0), buttons = 0, oldButtons = 0 }
	function move:KeyPressed(key) return self.buttons == key and self.oldButtons ~= key end
	local session = { io = state, move = move, yawOffset = 5, mini = mini }
	return session, state
end

local function advance(session, ticks)
	for _ = 1, ticks or 1 do IO.Step(session, 0.05) end
end

local tests = {}
function tests.movedir_angles()
	local session, state = world({
		{ classname = "func_door", targetname = "vertical", model = "*3", origin = Vector(0, 0, 0),
			movedir = "-90 0 0", lip = 5, speed = 75, wait = -1, spawnflags = 32 },
		{ classname = "func_door", targetname = "horizontal", model = "*2", origin = Vector(200, 0, 0),
			movedir = "0 90 0", lip = 8, speed = 75 },
	})
	local vertical, horizontal = state.world.names.vertical[1], state.world.names.horizontal[1]
	local up = IO.Direction(vertical)
	local right = IO.Direction(horizontal)
	assert(math.abs(up.z - 1) < 0.00001 and math.abs(up.x) < 0.00001, "movedir -90 pitch should point upward")
	assert(math.abs(right.y - 1) < 0.00001 and math.abs(right.x) < 0.00001, "movedir 90 yaw should point along +Y")
	assert(IO.Travel(vertical, up) == 124, "vertical door travel must use height rather than thickness")
	IO.Input(state, vertical, "Open")
	advance(session, 10)
	assert(math.abs(IO.Position(state, vertical).z - 37.5) < 0.001, "vertical door failed to translate along +Z")
	advance(session, 30)
	assert(math.abs(IO.Position(state, vertical).z - 119) < 0.001, "vertical door failed to reach full height")
	IO.Input(state, horizontal, "Open")
	advance(session, 30)
	assert(IO.Position(state, horizontal).y > 0, "horizontal door failed to follow Hammer yaw")
	print("PASS movedir angles: pitch/yaw direction, vertical travel, door translation")
end

function tests.hot_reload()
	local original = IO.classes.func_button
	local steps, draws, version = #IO.steps, #IO.draws, IO.registrationVersion
	dofile("lua/pocketmap/mapio/cl_core.lua")
	assert(PocketMap.MapIO == IO and IO.classes.func_button == original, "core refresh cleared registered handlers")
	assert(#IO.steps == steps and #IO.draws == draws, "core refresh changed callback counts")
	dofile("lua/pocketmap/mapio/cl_buttons.lua")
	dofile("lua/pocketmap/mapio/cl_doors.lua")
	dofile("lua/pocketmap/mapio/cl_teleport.lua")
	assert(#IO.steps == steps and #IO.draws == draws, "handler refresh duplicated callbacks")
	assert(IO.registrationVersion > version, "handler refresh did not register its new revision")
	print("PASS hot reload: handlers preserved, callbacks replaced")
end

function tests.session_reload()
	local mini = { bsp = {
		GetBModels = function() return models end,
		GetEntities = function() return { { classname = "func_door", model = "*2" } } end,
	} }
	local state = IO.NewSession(mini)
	assert(state.world and #state.world.solids == 1, "stale miniature did not rebuild Map I/O")
	mini.mapIO = {}
	assert(#IO.NewSession(mini).world.solids == 1, "partial Map I/O world did not rebuild")
	local hit = { Fraction = 1 }
	IO.Trace({ io = { } }, Vector(), Vector(100, 0, 0), Vector(), Vector(), hit)
	assert(hit.Fraction == 1, "missing world modified collision result")
	print("PASS session reload: stale miniature, missing world trace")
end

function tests.late_registration()
	local entities = { { classname = "func_late_use", model = "*1" } }
	local mini = { bsp = {
		GetBModels = function() return models end,
		GetEntities = function() return entities end,
	} }
	IO.Build(mini, entities)
	assert(#mini.mapIO.solids == 0 and #mini.mapIO.useTargets == 0, "late class unexpectedly registered")
	IO.Register("func_late_use", { solid = true, use = function() end })
	local state = IO.NewSession(mini)
	assert(#state.world.solids == 1 and #state.world.useTargets == 1, "late handler did not rebuild interaction targets")
	assert(state.world.registrationVersion == IO.registrationVersion, "registry revision was not stored")
	print("PASS late registration: existing miniature rebuilt for added handlers")
end

function tests.teleport()
	local session, state = world({
		{ classname = "trigger_teleport", origin = Vector(), model = "*1", target = "Exit", OnTrigger = table.concat({ "relay", "Enable", "", "0", "-1" }, string.char(27)) },
		{ classname = "info_teleport_destination", targetname = "Exit", origin = Vector(100, 30, 20), angles = Angle(0, 140, 0) },
		{ classname = "logic_relay", targetname = "relay", StartDisabled = 1 },
	})
	session.move.origin = Vector(-100, 0, 0)
	advance(session, 1)
	assert(session.move.origin.x == -100, "teleport occurred outside trigger")
	session.move.origin = Vector(0, 0, 0)
	advance(session, 1)
	assert(session.move.origin.x == 100 and session.move.origin.z == 22, "destination incorrect")
	assert(session.move.velocity:Length() == 0 and session.yawOffset == 125, "velocity or yaw not reset")
	assert(IO.Enabled(state, state.world.names.relay[1]), "Source output not dispatched")
	assert(not IO.Enabled(IO.NewSession({ mapIO = state.world }), state.world.names.relay[1]), "State leaked to next walk")
	session.move.origin = Vector(0, 0, 0)
	advance(session, 1)
	assert(session.move.origin.x == 0, "teleport retriggered while touching")
	session.move.origin = Vector(-100, 0, 0)
	advance(session, 1)
	session.move.origin = Vector(0, 0, 0)
	advance(session, 1)
	assert(session.move.origin.x == 100, "teleport failed on re-entry")
	print("PASS teleport: trigger, destination, yaw, velocity, outputs, re-entry")
end

local function boxBrush(lo, hi)
	local sides = {}
	for _, axis in ipairs({ "x", "y", "z" }) do
		for _, sign in ipairs({ -1, 1 }) do
			local n = Vector()
			n[axis] = sign
			sides[#sides + 1] = { plane = { normal = n, dist = sign < 0 and -lo[axis] or hi[axis] } }
		end
	end
	return { sides = sides }
end

local function triggerWorld(brushes, lo, hi, origin, angles)
	local model = { mins = lo, maxs = hi, headnode = 0 }
	local bsp = {
		GetBModels = function() return { [1] = model } end,
		GetNodes = function() return { [0] = { children = { -1, -2 } } } end,
		GetLeafs = function() return {
			[0] = { GetBrushes = function() return brushes end },
			[1] = { GetBrushes = function() return { brushes[1] } end },
		} end,
	}
	local mini = { bsp = bsp }
	IO.Build(mini, {
		{ classname = "trigger_teleport", model = "*1", origin = origin, angles = angles, target = "exit" },
		{ classname = "info_teleport_destination", targetname = "exit", origin = Vector(10000, 0, 0) },
	})
	return { mini = mini, io = IO.NewSession(mini), yawOffset = 0,
		move = { origin = Vector(), velocity = Vector(), angles = Angle(), buttons = 0, oldButtons = 0,
			KeyPressed = function() return false end } }
end

function tests.surf_ace_drop()
	-- surf_ace bmodel *5, Hammer 1578: four reset brushes around the drop.
	local brushes = {
		boxBrush(Vector(-1632, -768, -16), Vector(-1120, 768, 16)),
		boxBrush(Vector(-64, -768, -16), Vector(1632, 768, 0)),
		boxBrush(Vector(-1120, 512, -16), Vector(-96, 768, 16)),
		boxBrush(Vector(-1120, -768, -16), Vector(-96, -512, 16)),
	}
	local session = triggerWorld(brushes, Vector(-1632, -768, -16), Vector(1632, 768, 16), Vector(3616, -128, -272), Angle())
	local trigger = IO.OfClass(session.io.world, "trigger_teleport")[1]
	session.move.origin = Vector(3104, -128, -272)
	assert(IO.Overlaps(session, trigger), "drop fixture must reproduce the old bounding-box reset")
	advance(session)
	assert(session.move.origin.x == 3104, "surf_ace drop opening incorrectly reset the walker")
	assert(#trigger.teleportBrushes == 4, "leaf traversal failed to deduplicate trigger brushes")
	session.move.origin = Vector(3700, -128, -272)
	advance(session)
	assert(session.move.origin.x == 10000, "solid part of surf_ace reset trigger stopped working")
	local other = { mini = session.mini, io = IO.NewSession(session.mini), move = { origin = Vector(3104, -128, -272) } }
	assert(not IO.TeleportOverlaps(other, trigger), "cached geometry changed between walking sessions")
	print("PASS surf_ace drop: opening preserved, reset brushes active, leaf deduplication, session reuse")
end

function tests.teleport_shape_and_hull()
	local brush = boxBrush(Vector(-100, -100, 0), Vector(100, 100, 100))
	brush.sides[#brush.sides + 1] = { plane = { normal = Vector(1, 0, 1):GetNormalized(), dist = 0 } }
	local session = triggerWorld({ brush }, Vector(-100, -100, 0), Vector(100, 100, 100), Vector(200, 300, 0), Angle(0, 90, 0))
	local trigger = IO.OfClass(session.io.world, "trigger_teleport")[1]
	session.move.origin = Vector(200, 350, 20)
	assert(IO.Overlaps(session, trigger) and not IO.TeleportOverlaps(session, trigger), "rotated slope triggered in its empty bounding-box corner")
	session.move.origin = Vector(200, 220, 20)
	assert(IO.TeleportOverlaps(session, trigger), "rotated sloping brush failed to detect a real touch")

	local ceiling = boxBrush(Vector(-100, -100, 60), Vector(100, 100, 80))
	session = triggerWorld({ ceiling }, Vector(-100, -100, 60), Vector(100, 100, 80), Vector(), Angle())
	trigger = IO.OfClass(session.io.world, "trigger_teleport")[1]
	local oldMovement, oldLocalPlayer = PocketMap.Movement, LocalPlayer
	LocalPlayer = function() return {} end
	PocketMap.Movement = { PlayerHull = function(_, ducking)
		return Vector(-16, -16, 0), Vector(16, 16, ducking and 36 or 72)
	end }
	assert(IO.TeleportOverlaps(session, trigger), "standing hull missed trigger at head height")
	session.ducking = true
	assert(not IO.TeleportOverlaps(session, trigger), "crouched hull triggered at standing head height")
	PocketMap.Movement, LocalPlayer = oldMovement, oldLocalPlayer
	print("PASS teleport shape and hull: rotated planes, empty corners, standing and crouched hulls")
end

function tests.doors()
	local session, state = world({
		{ classname = "func_door", targetname = "slide", origin = Vector(), model = "*2", angles = Angle(), speed = 80, wait = 0.2,
			OnFullyOpen = "relay,Enable,,0,-1" },
		{ classname = "func_door_rotating", targetname = "hinge", origin = Vector(100, 0, 0), model = "*1",
			spawnflags = 32, distance = 90, speed = 90 },
		{ classname = "prop_door_rotating", targetname = "prop", origin = Vector(200, 0, 0), model = "models/door.mdl", speed = 90 },
		{ classname = "logic_relay", targetname = "relay", StartDisabled = 1 },
	})
	local slide, hinge, prop = state.world.names.slide[1], state.world.names.hinge[1], state.world.names.prop[1]
	assert(state.world.dynamicModels[2] == slide and state.world.dynamicModels[1] == hinge, "moving brushes missing")
	local hit = { Fraction = 1 }
	IO.Trace(session, Vector(-100, 0, 20), Vector(100, 0, 20), Vector(-16, -16, 0), Vector(16, 16, 72), hit)
	assert(hit.Fraction < 1 and hit.Entity == slide, "closed door failed swept collision")
	IO.Input(state, slide, "Open")
	advance(session, 12)
	assert(IO.Position(state, slide).x > 0, "sliding door did not travel")
	advance(session, 8)
	assert(IO.Enabled(state, state.world.names.relay[1]), "door output not fired")
	advance(session, 30)
	assert(IO.Position(state, slide).x == 0, "door did not auto-close")
	IO.Input(state, hinge, "Open")
	advance(session, 20)
	assert(IO.Rotation(state, hinge).y == 90, "hinged door did not rotate")
	advance(session, 60)
	assert(IO.Rotation(state, hinge).y == 90, "toggle door incorrectly auto-closed")
	IO.Input(state, hinge, "Toggle")
	advance(session, 20)
	assert(IO.Rotation(state, hinge).y == 0, "toggle door did not close")
	IO.Input(state, prop, "Open")
	advance(session, 20)
	assert(IO.Rotation(state, prop).y == 90, "prop door did not rotate")
	session.move.origin, session.move.angles = Vector(140, 0, 0), Angle()
	session.move.buttons, session.move.oldButtons = IN_USE, 0
	advance(session, 1)
	assert(IO.Rotation(state, prop).y < 90, "use key failed to close door")
	session.move.buttons = 0
	assert(not IO.Enabled(IO.NewSession({ mapIO = state.world }), state.world.names.relay[1]), "door IO leaked")
	print("PASS doors: slide, rotation, prop, outputs, auto-close, toggle, isolation")
end

function tests.buttons()
	local session, state = world({
		{ classname = "func_button", targetname = "switch", model = "*2", origin = Vector(0, 100, 0),
			speed = 80, lip = 4, wait = 0.2, OnPressed = "relay,Enable,,0,-1" },
		{ classname = "func_rot_button", targetname = "rot", model = "*1", origin = Vector(100, 100, 0),
			distance = 90, speed = 90, wait = -1 },
		{ classname = "logic_relay", targetname = "relay", StartDisabled = 1 },
	})
	local button, rot = state.world.names.switch[1], state.world.names.rot[1]
	IO.Input(state, button, "Lock")
	IO.Input(state, button, "Press")
	advance(session, 5)
	assert(IO.Position(state, button).x == 0, "locked button moved")
	IO.Input(state, button, "Unlock")
	IO.Input(state, button, "Press")
	advance(session, 8)
	assert(IO.Position(state, button).x > 0, "button did not translate")
	assert(IO.Enabled(state, state.world.names.relay[1]), "button output did not fire")
	advance(session, 45)
	assert(IO.Position(state, button).x == 0, "button did not return")
	IO.Input(state, rot, "Press")
	advance(session, 22)
	assert(IO.Rotation(state, rot).y == 90, "rotating button did not turn")
	advance(session, 40)
	assert(IO.Rotation(state, rot).y == 90, "wait -1 should hold position")
	session.move.origin, session.move.angles = Vector(-100, 100, 0), Angle()
	session.move.buttons, session.move.oldButtons = IN_USE, 0
	advance(session, 1)
	assert(IO.Position(state, button).x > 0, "use key failed to press button")
	session.move.buttons = 0
	print("PASS buttons: locked, press, outputs, return, rotation, hold")
end

function tests.movers()
	local session, state = world({
		{ classname = "func_movelinear", model = "*2", targetname = "elevator", origin = Vector(0, 100, 0), movedir = "-90 0 0", movedistance = 100, speed = 100,
			OnFullyOpen = "relay,Enable,,0,-1" },
		{ classname = "func_tracktrain", model = "*1", targetname = "train", origin = Vector(200, 0, 0), target = "A", speed = 100 },
		{ classname = "path_track", targetname = "A", origin = Vector(250, 0, 0), target = "B", OnPass = "relay,Enable,,0,-1" },
		{ classname = "path_track", targetname = "B", origin = Vector(250, 100, 0) },
		{ classname = "logic_relay", targetname = "relay", StartDisabled = 1 },
	})
	local elevator, train = state.world.names.elevator[1], state.world.names.train[1]
	IO.Input(state, elevator, "Open")
	advance(session, 22)
	assert(IO.Position(state, elevator).z == 100, "linear mover did not reach goal")
	assert(IO.Enabled(state, state.world.names.relay[1]), "mover Hammer output missing")
	IO.Input(state, elevator, "Close")
	advance(session, 22)
	assert(IO.Position(state, elevator).z == 0, "linear mover failed to close")
	advance(session, 40)
	assert(IO.Position(state, train).x == 250 and IO.Position(state, train).y == 100, "train path did not reach final node")
	IO.Input(state, train, "TeleportToPathTrack", "A")
	assert(IO.Position(state, train).x == 250 and IO.Position(state, train).y == 0, "train path teleport failed")
	print("PASS movers: linear travel, close, outputs, tracktrain path, teleport")
end

function tests.conveyor()
	local session, state = world({
		{ classname = "func_conveyor", model = "*2", targetname = "belt", origin = Vector(), movedir = "0 0 0", speed = 60,
			OnStartTouch = "relay,Enable,,0,-1" },
		{ classname = "logic_relay", targetname = "relay", StartDisabled = 1 },
	})
	local belt = state.world.names.belt[1]
	session.move.origin = Vector(0, 0, 80)
	advance(session, 1)
	assert(session.move.origin.x == 3, "conveyor did not carry walker")
	assert(IO.Enabled(state, state.world.names.relay[1]), "conveyor touch output missing")
	IO.Input(state, belt, "SetSpeed", "120")
	advance(session, 1)
	assert(session.move.origin.x == 9, "conveyor speed input ignored")
	IO.Input(state, belt, "Stop")
	advance(session, 1)
	assert(session.move.origin.x == 9, "stopped conveyor kept moving")
	IO.Input(state, belt, "Start")
	advance(session, 1)
	assert(session.move.origin.x == 15, "conveyor failed to restart")
	session.move.origin = Vector(1000, 0, 80)
	advance(session, 1)
	assert(session.move.origin.x == 1000, "conveyor moved walker off belt")
	print("PASS conveyor: surface contact, speed, outputs, stop, restart, leave")
end

function tests.spatial_trace()
	local session, state = world({
		{ classname = "func_door", model = "*2", targetname = "moving", origin = Vector() },
		{ classname = "func_door", model = "*1", targetname = "far", origin = Vector(3000, 3000, 0) },
	})
	local door = state.world.names.moving[1]
	local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
	local function trace(x1, x2)
		local result = { Fraction = 1 }
		IO.Trace(session, Vector(x1, 0, 40), Vector(x2, 0, 40), mins, maxs, result)
		return result
	end
	local function traceY(y1, y2, x)
		local result = { Fraction = 1 }
		IO.Trace(session, Vector(x or 0, y1, 40), Vector(x or 0, y2, 40), mins, maxs, result)
		return result
	end

	session.command = 1
	assert(trace(-100, 100).Entity == door, "original brush was missing from the spatial index")
	assert(trace(500, 600).Fraction == 1, "distant brush caused a false collision")

	IO.State(state, door).origin = Vector(1024, 0, 0)
	IO.PoseChanged(state, door)
	session.command = 2
	assert(trace(-100, 100).Fraction == 1, "moved brush remained in its previous cells")
	assert(trace(900, 1100).Entity == door, "moved brush was missing from its new cells")

	IO.State(state, door).angles = Angle(0, 90, 0)
	IO.PoseChanged(state, door)
	session.command = 3
	assert(traceY(-70, -30, 1024).Entity == door, "rotated brush was missing from the spatial index")
	print("PASS spatial trace: nearby collision, distant rejection, moved and rotated brushes")
end

for name, test in pairs(tests) do
	if not arg[1] or arg[1] == name then test() end
end
