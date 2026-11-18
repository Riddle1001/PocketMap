-- Run from the PocketMap root: lua tests/flashlight.lua
local hooks, denied = {}, false
hook = {
	Add = function(event, _, callback) hooks[event] = callback end,
	Run = function(event) assert(event == "PlayerSwitchFlashlight") if denied then return false end end,
}
function IsValid(v) return type(v) == "table" and not v.removed end
EF_DIMLIGHT = 4
PocketMap = {}
dofile("lua/pocketmap/sv_flashlight.lua")
local Server = PocketMap.FlashlightServer
local ply = { native = true, alive = true, allowed = true, nw = {}, sounds = 0 }
function ply:FlashlightIsOn() return self.native end
function ply:SetNWBool(k, v) self.nw[k] = v end
function ply:RemoveEffects(flag) assert(flag == EF_DIMLIGHT) self.native = false end
function ply:Alive() return self.alive end
function ply:CanUseFlashlight() return self.allowed end
function ply:Flashlight(on) self.native = on end
function ply:EmitSound() self.sounds = self.sounds + 1 end
local command = { impulse = 100 }
function command:GetImpulse() return self.impulse end
function command:SetImpulse(v) self.impulse = v end
local function toggle()
	command.impulse = 100
	hooks.StartCommand(ply, command)
end
Server.Start(ply)
assert(not ply.native and ply.nw.PocketMap_FlashlightOn and ply.nw.PocketMap_FlashlightActive, "two lamps active on entry")
Server.Start(ply)
assert(Server.players[ply], "repeated walk packet discarded saved state")
toggle()
assert(command.impulse == 0 and not Server.players[ply] and not ply.nw.PocketMap_FlashlightOn, "F did not switch the miniature lamp off")
denied = true
toggle()
assert(not Server.players[ply], "gamemode's flashlight veto was bypassed")
denied, ply.allowed = false, false
toggle()
assert(not Server.players[ply], "AllowFlashlight(false) was bypassed")
ply.allowed = true
toggle()
Server.Stop(ply)
assert(ply.native and not ply.nw.PocketMap_FlashlightActive and Server.players[ply] == nil, "native comparison/exit did not restore the latest toggle")
Server.Stop(ply)
Server.Start(ply)
ply.alive = false
ply.native = false
Server.Stop(ply)
assert(not ply.native, "death switched on the real body's flashlight")

function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
local function bitAnd(a,b)
	local result, power = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then result = result + power end
		a, b, power = math.floor(a/2), math.floor(b/2), power*2
	end
	return result
end
bit = { band = bitAnd }
local cvars = {r_flashlightlinear=100,r_flashlightquadratic=12,r_flashlightconstant=0.2}
function GetConVar(name) local n=cvars[name] if n then return {GetFloat=function()return n end} end end
util = { CRC = function(s) return s end }
local created = {}
function CreateMaterial(name, shader, values)
	local m = { name=name, shader=shader, values=values }
	function m:SetTexture(k,v) self[k]=v end
	function m:SetMatrix(k,v) self[k]=v end
	created[#created+1] = m
	return m
end
dofile("lua/pocketmap/cl_flashlight.lua")
local F = PocketMap.Flashlight
local lamp = {}
for _, name in ipairs({"FOV","NearZ","FarZ","ConstantAttenuation","LinearAttenuation","QuadraticAttenuation","EnableShadows","ShadowDepthBias","ShadowSlopeScaleDepthBias"}) do
	lamp["Set"..name] = function(self,v)self[name]=v end
end
local function close(a,b) assert(math.abs(a-b)<0.000001, tostring(a).." ~= "..tostring(b)) end
for _, scale in ipairs({0.001,0.01462155,0.1,1}) do
	F.Configure(lamp, scale, 4)
	local distance=300*scale
	close(lamp.ConstantAttenuation+lamp.LinearAttenuation/distance+lamp.QuadraticAttenuation/distance^2, 0.2+100/300+12/300^2)
	close(lamp.FarZ/scale,750)
	close(lamp.NearZ/scale,4)
end
local texture={GetName=function()return "fence/mask"end}
local transform={}
local material={}
function material:GetName()return "fence/test"end
function material:GetInt(k)return k=="$flags" and 8448 or 0 end
function material:GetFloat()return 0.4 end
function material:GetTexture()return texture end
function material:GetMatrix()return transform end
local depth=F.DepthMaterial(material)
assert(depth.shader=="DepthWrite" and depth.values["$alphatest"]==1 and depth.values["$nocull"]==1, "cutout became an opaque shadow rectangle")
assert(depth["$basetexture"]==texture and depth["$basetexturetransform"]==transform and depth.values["$alphatestreference"]==0.4, "shadow mask or transform lost")
assert(F.DepthMaterial(material)==depth and #created==1, "shadow materials rebuilt every frame")
local removed=0
F.projector={Remove=function(self)self.removed=true removed=removed+1 end}
F.Stop() F.Stop()
assert(removed==1 and not F.projector and not F.mini, "projector leaked after exit")

local opaqueA, opaqueB = {}, {}
for _, m in ipairs({opaqueA, opaqueB}) do
	function m:GetName() return self == opaqueA and "opaque/a" or "opaque/b" end
	function m:GetInt() return 0 end
	function m:GetTexture() return nil end
end
assert(F.DepthMaterial(opaqueA) == F.DepthMaterial(opaqueB), "opaque surfaces did not share a depth material")
assert(F.DepthMaterial(opaqueA) ~= depth, "cutout lost its separate mask")

local uploaded, destroyed, inputVertices = 0, 0, 0
local function builder()
	local groups = {}
	return {
		AddFace = function(_, face, options)
			inputVertices = inputVertices + #face:GenerateVertexTriangleData()
			groups[options.material] = true
		end,
		Build = function()
			uploaded = uploaded + 1
			local parts = {}
			for material in pairs(groups) do parts[#parts+1] = {material=material} end
			return {GetMeshes=function()return parts end,Destroy=function()destroyed=destroyed+1 end}
		end,
	}
end
NikNaks = {MeshBuilder=setmetatable({BlendsWithBackground=function(m)return m.translucent end},{__call=builder})}
local vertices = {}
for i=1,6 do vertices[i]={} end
local face = {GenerateVertexTriangleData=function()return vertices end}
local mini = {}
local co = coroutine.create(function()
	for i=1,2100 do F.AddWorldShadowFace(mini,face,i%2==0 and opaqueA or opaqueB) end
	F.AddWorldShadowFace(mini,face,material)
	F.AddWorldShadowFace(mini,face,{translucent=true})
	F.FlushWorldShadows(mini)
end)
repeat local ok,err=coroutine.resume(co) assert(ok,err) until coroutine.status(co)=="dead"
assert(inputVertices==2101*6, "batch dropped opaque/cutout triangles or added translucent casters")
assert(uploaded==2 and #mini.worldShadowMeshes==3, "depth batches retained the color material splits")
F.FreeWorldShadows(mini) F.FreeWorldShadows(mini)
assert(destroyed==2 and not mini.worldShadowMeshes and not mini.worldShadowBuilder, "shadow geometry leaked on removal")

local matrices, meshDraws, bindings, dynamicDraws = 0, 0, 0, 0
cam = {PushModelMatrix=function()matrices=matrices+1 end,PopModelMatrix=function()matrices=matrices-1 end}
render = {SetMaterial=function()bindings=bindings+1 end}
PocketMap.MapIO = {DrawDepth=function()dynamicDraws=dynamicDraws+1 end}
PocketMap.Props = {DrawDepth=function()dynamicDraws=dynamicDraws+1 end}
local shadowPart={material=F.DepthMaterial(opaqueA),mesh={Draw=function()meshDraws=meshDraws+1 end}}
mini={state="ready",scaleVec={},matrix={},UpdateMatrix=function()end,
	objects={opaqueMeshes={{material=opaqueA,mesh=shadowPart.mesh}}},worldShadowMeshes={shadowPart,shadowPart}}
F.DrawDepth(mini, 123)
assert(meshDraws==2 and bindings==1 and dynamicDraws==2 and matrices==0, "batched depth skipped casters or dynamic geometry")
mini.worldShadowMeshes=nil
F.DrawDepth(mini,123)
assert(meshDraws==3 and dynamicDraws==4 and matrices==0, "legacy miniature depth fallback broke")
mini.worldShadowMeshes={{material=shadowPart.material,mesh={Draw=function()error("shadow draw fixture")end}}}
assert(not pcall(F.DrawDepth,mini,123) and matrices==0, "failed shadow draw leaked its matrix")

-- Exercise the real loader slice as well as the batching API: shadow vertices
-- must be consumed before the face cache is cleared, and sky slices stay out.
PocketMap.Mini = {}
PocketMap.Water = {}
function CreateClientConVar()return {} end
dofile("lua/pocketmap/cl_loader.lua")
local function upvalue(fn, name)
	for i=1,100 do local k,v=debug.getupvalue(fn,i) if k==name then return v end end
	error("Missing loader stage: "..name)
end
local buildSlice=upvalue(upvalue(upvalue(PocketMap.Loader.Run,"buildWorldMeshes"),"buildMaterialGroups"),"buildSlice")
for _,v in ipairs(vertices) do v.pos={x=1,y=2,z=3} end
local cleared=0
face.ClearMeshData=function()cleared=cleared+1 end
local faces={}
for i=1,20 do faces[i]=face end
local shadowMini={}
co=coroutine.create(function()
	buildSlice(faces,1,#faces,{material=opaqueA},shadowMini)
	assert(shadowMini.worldShadowVertices==120, "loader omitted static shadow faces")
	F.FlushWorldShadows(shadowMini)
	buildSlice(faces,1,#faces,{material=opaqueA})
end)
repeat local ok,err=coroutine.resume(co) assert(ok,err) until coroutine.status(co)=="dead"
assert(cleared==40 and #shadowMini.worldShadowMeshes==1 and not shadowMini.worldShadowBuilder, "loader slice/face-cache lifecycle broke")
F.FreeWorldShadows(shadowMini)

local poseTrace=upvalue(F.Pose,"poseTrace")
local traceCalls=0
local traceSession={command=1,io={world={}},TraceHull=function()
	traceCalls=traceCalls+1 return {Hit=false,Fraction=1}
end}
local start,finish=Vector(),Vector(10,20,30)
local result=poseTrace(traceSession,1,start,finish,123)
assert(poseTrace(traceSession,1,start,finish,123)==result and traceCalls==1,"identical pose probe was repeated")
poseTrace(traceSession,2,start,finish,123)
assert(traceCalls==2,"independent probes shared a cache slot")
traceSession.command=2 poseTrace(traceSession,1,start,finish,123)
traceSession.io.drawRevision=1 poseTrace(traceSession,1,start,finish,123)
traceSession.io.world={} poseTrace(traceSession,1,start,finish,123)
traceSession.physics={} poseTrace(traceSession,1,start,finish,123)
poseTrace(traceSession,1,start,finish,124)
assert(traceCalls==7,"movement, I/O, collision or mask change reused a stale probe")
F.Stop()
assert(not F.poseTraces,"pose trace cache survived flashlight cleanup")
print("PASS flashlight: native handoff, F toggle, permissions, death, distance-invariant beam, cutout shadows, cached materials, cleanup")
