-- Standalone Lua 5.1 checks. Run from the PocketMap root: lua tests/mapio.lua
local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector) end
function vector.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vector.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vector.__mul(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector(a.x * b, a.y * b, a.z * b)
end
function vector:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
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
function LocalToWorld(pos, _, origin, angles)
	local y = math.rad(angles.y)
	return origin + Vector(pos.x * math.cos(y) - pos.y * math.sin(y), pos.x * math.sin(y) + pos.y * math.cos(y), pos.z)
end
IN_USE = 32
function math.Clamp(n, a, b) return math.max(a, math.min(b, n)) end
function math.Approach(n, target, amount) return n < target and math.min(target, n + amount) or math.max(target, n - amount) end

function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
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
}
local function world(entities)
	local mini = { bsp = { GetBModels = function() return models end } }
	IO.Build(mini, entities)
	local state = IO.NewSession(mini)
	local move = { origin = Vector(-200, 0, 0), velocity = Vector(4, 1, 2), angles = Angle(0, 20, 0), buttons = 0, oldButtons = 0 }
	function move:KeyPressed(key) return self.buttons == key and self.oldButtons ~= key end
	local session = { io = state, move = move, yawOffset = 5 }
	return session, state
end

local function advance(session, ticks)
	for _ = 1, ticks or 1 do IO.Step(session, 0.05) end
end

local tests = {}
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
		{ classname = "func_movelinear", model = "*2", targetname = "elevator", origin = Vector(0, 100, 0), movedir = "0 0 1", movedistance = 100, speed = 100,
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
		{ classname = "func_conveyor", model = "*2", targetname = "belt", origin = Vector(), movedir = "1 0 0", speed = 60,
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

for name, test in pairs(tests) do
	if not arg[1] or arg[1] == name then test() end
end
