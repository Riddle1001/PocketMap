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
function LocalToWorld(pos, rotation, origin, angles)
	local y = math.rad(angles.y)
	return origin + Vector(pos.x * math.cos(y) - pos.y * math.sin(y), pos.x * math.sin(y) + pos.y * math.cos(y), pos.z),
		Angle(rotation.p + angles.p, rotation.y + angles.y, rotation.r + angles.r)
end
function WorldToLocal(pos, rotation, origin, angles)
	return LocalToWorld(pos - origin, rotation, Vector(), Angle(-angles.p, -angles.y, -angles.r))
end
IN_USE = 32
function math.Clamp(n, a, b) return math.max(a, math.min(b, n)) end
function math.Approach(n, target, amount) return n < target and math.min(target, n + amount) or math.max(target, n - amount) end

function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateClientConVar() return { GetBool = function() return true end } end
hook = { Add = function() end }
function ClientsideModel() return nil end
function IsValid(value) return value ~= nil and value ~= false end
local player = {}
function LocalPlayer() return player end
bit = { band = function(a, b)
	local result, place = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then result = result + place end
		a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
	end
	return result
end }
NikNaks = { __metatables = { BSP = {} } }
dofile("../NikNaks/lua/niknaks/modules/sh_bsp_entities.lua")
local entityValue = NikNaks.EntityValue
function NikNaks.EntityValue(entity, key)
	local value = entity[key]
	if isvector(value) or isangle(value) then return value end
	return entityValue(entity, key)
end
PocketMap = { Entities = {} }
function PocketMap.Entities.First(v) return type(v) == "table" and getmetatable(v) == nil and v[1] or v end
function PocketMap.Entities.Class(ent) return tostring(ent.classname or ""):lower() end
function PocketMap.Entities.Name(ent) return ent.targetname and ent.targetname:lower() end

dofile("lua/pocketmap/mapio/cl_core.lua")
dofile("lua/pocketmap/mapio/cl_collision.lua")
dofile("lua/pocketmap/mapio/cl_teleport.lua")
dofile("lua/pocketmap/mapio/cl_doors.lua")
dofile("lua/pocketmap/mapio/cl_buttons.lua")
dofile("lua/pocketmap/mapio/cl_movers.lua")
dofile("lua/pocketmap/mapio/cl_conveyor.lua")
dofile("lua/pocketmap/mapio/cl_logic.lua")

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
function tests.rotators()
	local session, state = world({
		{ classname = "func_rotating", model = "*2", targetname = "panel", maxspeed = 100, spawnflags = 1 },
		{ classname = "func_rotating", model = "*3", targetname = "fan", origin = Vector(3000, 0, 0),
			maxspeed = 60, spawnflags = 72 },
		{ classname = "logic_auto", OnMapSpawn = "fan,Start,,0.1,-1" },
		{ classname = "trigger_teleport", model = "*2", targetname = "reset", origin = Vector(1024, 0, 0),
			parentname = "PaNeL", target = "exit", spawnflags = 1 },
		{ classname = "trigger_push", model = "*2", targetname = "breeze", origin = Vector(128, 0, 0),
			parentname = "panel", pushdir = "0 0 0", speed = 300, spawnflags = 1 },
		{ classname = "trigger_multiple", model = "*2", origin = Vector(256, 0, 0),
			parentname = "panel", spawnflags = 1, OnStartTouch = "relay,Enable,,0,-1" },
		{ classname = "logic_relay", targetname = "relay", StartDisabled = 1 },
		{ classname = "info_teleport_destination", targetname = "exit", origin = Vector(4000, 0, 0) },
	})
	local panel, fan, reset = state.world.names.panel[1], state.world.names.fan[1], state.world.names.reset[1]
	assert(state.world.dynamicModels[2] == panel, "rotators must be drawn as movers")
	assert(IO.classes.func_rotating.solid(state, panel) and not IO.classes.func_rotating.solid(state, fan),
		"rotator must respect the non-solid flag")
	advance(session, 2)
	assert(IO.Rotation(state, panel).y == 0 and IO.Rotation(state, fan).p == 0, "startup delay was ignored")
	advance(session, 4)
	assert(IO.Rotation(state, panel).y > 0 and IO.Rotation(state, fan).p > 0, "startup flag or delayed Start failed")
	local initial = IO.Rotation(state, panel).y
	IO.Input(state, panel, "SetSpeed", "0.5")
	advance(session, 2)
	assert(IO.Rotation(state, panel).y == initial + 5, "SetSpeed must interpret a fraction of maxspeed")
	IO.Input(state, panel, "Reverse")
	advance(session, 2)
	assert(IO.Rotation(state, panel).y == initial, "Reverse must retain speed and reverse direction")

	IO.State(state, panel).angles = Angle(0, 90, 0)
	IO.PoseChanged(state, panel)
	IO.Input(state, panel, "Stop")
	local moved = IO.Position(state, reset)
	assert(math.abs(moved.x) < 0.001 and moved.y == 1024 and IO.Rotation(state, reset).y == 90,
		"attached teleport did not rotate around the parent's pivot")
	session.move.origin = Vector(0, 128, 0)
	advance(session)
	assert(session.triggerPush and math.abs(session.triggerPush.y - 300) < 0.001,
		"attached push did not turn with its parent")
	session.move.origin = Vector(0, 256, 0)
	advance(session)
	assert(IO.Enabled(state, state.world.names.relay[1]), "attached touch trigger did not fire at its new position")
	session.move.origin = Vector(0, 1024, 0)
	advance(session)
	assert(session.move.origin.x == 4000, "attached teleport was missed outside its original spatial cell")
	print("PASS rotators: authored axis and speed, start timing, inputs, collision flags and attached triggers")
end

function tests.push()
	local session, state = world({
		{ classname = "trigger_push", targetname = "launch", model = "*2", pushdir = "0 180 0", speed = 1250, spawnflags = 1 },
		{ classname = "trigger_push", targetname = "lift", model = "*2", origin = Vector(0, 200, 0),
			pushdir = "-90 0 0", speed = 1200, spawnflags = 1, StartDisabled = 1 },
		{ classname = "trigger_push", model = "*2", origin = Vector(0, 400, 0), pushdir = "0 90 0", speed = 400, spawnflags = 129 },
	})
	function session:TraceHull() return { Fraction = 1 } end
	local move = session.move
	move.origin, move.velocity = Vector(), Vector()
	advance(session, 2)
	assert(math.abs(session.triggerPush.x + 1250) < 0.001 and move.velocity:LengthSqr() == 0,
		"continuous push must add base velocity without stacking impulses")
	move.origin = Vector(100, 0, 0)
	advance(session, 1)
	local launchSpeed = move.velocity.x
	assert(not session.triggerPush and math.abs(launchSpeed + 1250 * 1.025) < 0.001,
		"exiting a push must convert the base velocity to momentum")
	advance(session, 1)
	assert(move.velocity.x == launchSpeed, "exit momentum was applied twice")

	move.origin, move.velocity, session.onground = Vector(0, 200, 0), Vector(), true
	advance(session, 1)
	assert(not session.triggerPush and session.onground, "disabled push must not detach the player")
	IO.Input(state, state.world.names.lift[1], "Enable")
	advance(session, 1)
	assert(math.abs(session.triggerPush.z - 1200) < 0.001 and not session.onground
		and session.triggerPushLift and move.origin.z == 1, "vertical push must lift a grounded player")
	session.noclip = true
	advance(session, 1)
	assert(not session.triggerPush and move.velocity:LengthSqr() == 0, "noclip must not retain a push")

	session.noclip = false
	move.origin = Vector(0, 400, 0)
	advance(session, 2)
	assert(math.abs(move.velocity.y - 400) < 0.001 and not session.triggerPush, "one-shot push must fire once")
	print("PASS push triggers: authored vector, continuous speed, exit momentum, lift, enabled state, noclip and one-shot")
end

function tests.thin_conveyor()
	local session, state = world({
		{ classname = "func_conveyor", model = "*2", targetname = "belt", movedir = "0 0 0", speed = 200 },
	})
	local belt = state.world.names.belt[1]
	function session:TraceHull() return { Fraction = 1 } end
	session.move.origin, session.onground, session.groundRecord = Vector(0, 0, 80.0625), true, belt
	advance(session, 1)
	assert(session.move.origin.x == 10, "grounded hull just above the belt must be carried")
	session.groundRecord = {}
	advance(session, 1)
	assert(session.move.origin.x == 10, "belt must not carry a player grounded on other geometry")
	print("PASS thin conveyor: grounded trace contact and neighboring ground")
end

function tests.overlap_cache()
	local session,state=world({{classname="trigger_teleport",model="*1",origin=Vector()}})
	local record=IO.OfClass(state.world,"trigger_teleport")[1]
	session.move.origin=Vector()
	local original,calls=IO.Bounds,0
	IO.Bounds=function(...)calls=calls+1 return original(...)end
	assert(IO.Overlaps(session,record) and IO.Overlaps(session,record) and calls==1,"stationary trigger bounds were rebuilt")
	local pose=IO.State(state,record)
	pose.origin=Vector(1000,0,0)
	assert(not IO.Overlaps(session,record) and calls==2,"moved trigger reused stale bounds")
	pose.origin.x=2000
	assert(not IO.Overlaps(session,record) and calls==3,"in-place origin edit reused stale bounds")
	pose.angles.y=90
	assert(not IO.Overlaps(session,record) and calls==4,"in-place rotation edit reused stale bounds")
	local other={io=IO.NewSession(session.mini),move=session.move}
	assert(IO.Overlaps(other,record) and calls==5,"one session's trigger pose leaked into another")
	record.model={mins=Vector(3000,0,0),maxs=Vector(3100,10,10)}
	assert(not IO.Overlaps(other,record) and calls==6,"replaced brush geometry reused stale bounds")
	IO.Bounds=original
	print("PASS overlap cache: static reuse, movement, in-place poses, geometry replacement, session isolation")
end
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
	assert(session.move.origin.x == 100 and session.move.origin.z == 20, "destination incorrect")
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

function tests.teleport_spatial_index()
	local entities = {}
	for i = 1, 80 do
		entities[#entities + 1] = { classname = "trigger_teleport", model = "*1", origin = Vector(i * 1024, 0, 0) }
	end
	local session, state = world(entities)
	session.move.origin = Vector(0, 0, 10)
	local original, checks = IO.TeleportOverlaps, 0
	IO.TeleportOverlaps = function(...)
		checks = checks + 1
		return original(...)
	end
	advance(session, 2)
	assert(checks == 0 and not state.teleportMutable,
		"distant immutable triggers were queried on every movement command")
	local record = IO.OfClass(state.world, "trigger_teleport")[1]
	local pose = IO.State(state, record)
	pose.origin = Vector(0, 0, 0)
	advance(session)
	assert(state.touching[record] and checks == 1, "session moved trigger was missed outside its indexed cell")
	pose.origin.x = 4096
	advance(session)
	assert(not state.touching[record], "moving trigger did not send the touch exit")
	pose.origin.x = 0
	IO.Input(state, record, "Disable")
	advance(session)
	assert(not state.touching[record], "disabled moved trigger reported a touch")
	IO.Input(state, record, "Enable")
	advance(session)
	assert(state.touching[record], "re-enabled moved trigger was not queried")
	IO.TeleportOverlaps = original

	local chained = world({
		{ classname = "trigger_teleport", model = "*1", origin = Vector(), target = "b" },
		{ classname = "trigger_teleport", model = "*1", origin = Vector(1024, 0, 0), target = "end" },
		{ classname = "info_teleport_destination", targetname = "b", origin = Vector(1024, 0, 0) },
		{ classname = "info_teleport_destination", targetname = "end", origin = Vector(2048, 0, 0) },
	})
	chained.move.origin = Vector()
	advance(chained)
	assert(chained.move.origin.x == 2048,
		"teleport into another indexed cell failed to trigger in the same step")
	print("PASS teleport index: distant broad phase, mutable poses, enable/disable, ordered chains")
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
	local model = { mins = lo, maxs = hi, GetBrushes = function() return brushes end }
	local bsp = {
		GetBModels = function() return { [1] = model } end,
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
	local originalLocalToWorld, rotations = LocalToWorld, 0
	LocalToWorld = function(...) rotations = rotations + 1 return originalLocalToWorld(...) end
	-- Warm a new angle, then ensure identical rotations reuse the actual brush
	-- normals even when the player hull is tested every movement step.
	local pose = IO.State(session.io, trigger)
	pose.angles = Angle(0, 135, 0)
	IO.TeleportOverlaps(session, trigger)
	local first = rotations
	assert(first >= #brush.sides, "rotated planes were not prepared")
	IO.TeleportOverlaps(session, trigger)
	assert(rotations == first, "stationary trigger planes were rotated again")
	pose.angles.y = 90
	assert(IO.TeleportOverlaps(session, trigger), "in-place trigger angle change broke collision")
	assert(rotations > first, "in-place trigger angle change retained stale normals")
	local second = rotations
	IO.TeleportOverlaps(session, trigger)
	assert(rotations == second, "updated trigger angle planes were not reused")
	LocalToWorld = originalLocalToWorld

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
	session.onground = true
	function session:TraceHull() return { Fraction = 1 } end
	session.move.origin = Vector(0, 0, 80.0625)
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
