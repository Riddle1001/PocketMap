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

function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
PocketMap = { Entities = {} }
function PocketMap.Entities.First(v) return type(v) == "table" and getmetatable(v) == nil and v[1] or v end
function PocketMap.Entities.Class(ent) return tostring(ent.classname or ""):lower() end
function PocketMap.Entities.Name(ent) return ent.targetname and ent.targetname:lower() end

dofile("lua/pocketmap/mapio/cl_core.lua")
dofile("lua/pocketmap/mapio/cl_teleport.lua")

local IO = PocketMap.MapIO
local models = { [1] = { mins = Vector(-20, -20, -8), maxs = Vector(20, 20, 80) } }
local function world(entities)
	local mini = { bsp = { GetBModels = function() return models end } }
	IO.Build(mini, entities)
	local state = IO.NewSession(mini)
	local session = { io = state, move = { origin = Vector(-200, 0, 0), velocity = Vector(4, 1, 2), angles = Angle(0, 20, 0) }, yawOffset = 5 }
	return session, state
end

local function advance(session, ticks)
	for _ = 1, ticks or 1 do IO.Step(session, 0.05) end
end

local tests = {}
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

for name, test in pairs(tests) do
	if not arg[1] or arg[1] == name then test() end
end
