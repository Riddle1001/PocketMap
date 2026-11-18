-- Run from the PocketMap root: lua tests/respawn.lua
local vec = {}
vec.__index = vec
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vec) end
function vec.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vec.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vec.__mul(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function vec.__div(a, b) return a * (1 / b) end
function vec:DistToSqr(b) local d = self - b return d.x ^ 2 + d.y ^ 2 + d.z ^ 2 end
function isvector(v) return getmetatable(v) == vec end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function isangle(a) return type(a) == "table" and a.p ~= nil end
function Color() return {} end
function Matrix() return {} end
function IsValid(value) return type(value) == "table" and value.valid ~= false end
function RealTime() return 10 end
function string.StartWith(s, prefix) return s:sub(1, #prefix) == prefix end
function table.Shuffle() end
local hooks, receivers, messages = {}, {}, {}
hook = {
	Remove = function(event, name) if hooks[event] then hooks[event][name] = nil end end,
	Add = function(event, name, callback) assert(type(callback) == "function") hooks[event] = hooks[event] or {} hooks[event][name] = callback end,
}
surface = { CreateFont = function() end, PlaySound = function() end }
concommand = { Add = function() end }
local incoming, message
net = {
	Receive = function(name, callback) receivers[name] = callback end,
	ReadEntity = function() return incoming end,
	Start = function(name) message = { name = name } end,
	WriteEntity = function(block) message.block = block end,
	WriteBool = function(active) message.active = active end,
	WriteVector = function() end, WriteAngle = function() end,
	SendToServer = function() messages[#messages + 1] = message end,
}
util = { Effect = function() end }
function EffectData() return { SetOrigin = function() end, SetNormal = function() end, SetRadius = function() end } end
vector_up = Vector(0, 0, 1)
game = { GetWorld = function() return {} end, SinglePlayer = function() return false end }
local ply = { alive = false }
function ply:Alive() return self.alive end
function ply:InVehicle() return false end
function ply:EyeAngles() return Angle(0, 30, 0) end
function ply:GetPos() return Vector() end
function LocalPlayer() return ply end
local block = { BoxMins = Vector(), BoxMaxs = Vector(1, 1, 1) }
function block:ClampToBox(v) return v end
function block:LocalToWorld(v) return v end
local mini = { ent = block, state = "ready", scale = 1 }
function mini:BlockPosition(v) return v end
local spawns = {
	{ classname = "info_player_start", origin = Vector(100, 0, 0), angles = Angle(0, 90, 0) },
	{ classname = "info_player_start", origin = Vector(200, 0, 0), angles = Angle(0, 180, 0) },
}
mini.bsp = { GetNodes = function() return {} end, GetLeafs = function() return {} end, GetEntities = function() return spawns end }
local blocked = true
PocketMap = {
	Hooks = { Register = hook.Add },
	GamemodeMovement = { Reset = function() end, Step = function() error("movement advanced during death") end },
	MapIO = { Trace = function(_, start, _, _, _, result) result.StartSolid = blocked or start.x == 100 end },
	Movement = { PlayerHull = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end },
}
local old = { mini = mini, io = { touching = { previous = true }, queue = { "door output" } },
	move = { origin = Vector(900, 0, 0), velocity = Vector(800, 100, -1000) },
	command = 42, inputs = { [43] = true }, ducking = true, noclip = true, steps = { fall = 1000 } }
PocketMap.Walk = { session = old }
dofile("lua/pocketmap/cl_walk.lua")
local Walk = PocketMap.Walk
assert(Walk.session == old, "refresh dropped the active walk")
local cmd = {}
function cmd:ClearMovement() self.movementCleared = true end
function cmd:ClearButtons() self.buttonsCleared = true end
function cmd:CommandNumber() return 0 end
local function move() hooks.CreateMove.PocketMap_Walk(cmd) end
move()
assert(Walk.session == old and old.waitingForRespawn, "death exited the miniature")
assert(cmd.movementCleared and not cmd.buttonsCleared, "death blocked the gamemode's respawn input")
assert(next(old.inputs) == nil, "commands from before death survived")
hooks.SetupMove.PocketMap_Walk(ply, nil, cmd)
assert(not Walk.Respawn(), "dead real player respawned the virtual player early")
ply.alive = true
move()
assert(Walk.session == old, "resumed before the server restored the real player")
incoming = {}
receivers.PocketMap_Respawn()
assert(not old.respawnReady, "another block resumed this walk")
incoming = block
receivers.PocketMap_Respawn()
move()
assert(Walk.session == old, "used an obstructed spawn")
blocked = false
move()
local fresh = Walk.session
assert(fresh ~= old and fresh.mini == mini, "respawn failed to retain the miniature")
assert(fresh.move.origin.x == 200 and fresh.move.origin.z == 2, "did not choose a clear map spawn")
assert(fresh.move.velocity:DistToSqr(Vector()) == 0 and fresh.yawOffset == 150, "respawn did not reset velocity and view direction")
assert(not fresh.ducking and not fresh.noclip and not fresh.steps, "old movement state survived respawn")
assert(fresh.command == 0 and next(fresh.inputs) == nil, "old input survived respawn")
assert(fresh.io == old.io and fresh.io.queue[1] == "door output" and next(fresh.io.touching) == nil, "respawn lost map logic or retained old touches")
assert(messages[#messages].active == true and messages[#messages].block == block, "respawn was not relayed")
dofile("lua/pocketmap/cl_walk.lua")
assert(Walk.session == fresh and type(hooks.CreateMove.PocketMap_Walk) == "function", "refresh failed to retain respawned walk")
mini.entityRefresh = {}
block.valid = false
fresh.inputs, fresh.lastView = {[50]=true}, {origin='last pocket view'}
cmd.movementCleared, cmd.buttonsCleared = false, false
move()
hooks.SetupMove.PocketMap_Walk(ply, nil, cmd)
assert(Walk.session==fresh and next(fresh.inputs)==nil and cmd.movementCleared and cmd.buttonsCleared,
	"network refresh ejected the player, advanced movement, or kept stale input")
assert(Walk.View(90,30000)==fresh.lastView,"network refresh lost the frozen camera")
mini.entityRefresh, block.valid = nil, true
Walk.Leave()
assert(not Walk.session and messages[#messages].active == false, "explicit leave failed")
receivers.PocketMap_Respawn()
assert(not Walk.session, "delayed respawn reopened an explicitly closed walk")
print("PASS respawn: death stays inside, normal respawn input, clear spawn, fresh movement, map state, relay, cancellation, refresh")
