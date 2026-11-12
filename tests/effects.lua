-- Run from the PocketMap root: lua tests/effects.lua
local vec = {} vec.__index = vec
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec) end
function vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vec.__div(a,b) return a*(1/b) end
function vec.__unm(a)return a*-1 end
function isvector(v) return getmetatable(v)==vec end
function Angle() return {Right=function()return Vector(0,-1,0)end,Forward=function()return Vector(1,0,0)end,Up=function()return Vector(0,0,1)end} end
function Color(r,g,b) return {r=r,g=g,b=b,color=true} end
function IsColor(v) return type(v)=='table' and v.color==true end
function IsValid(v) return type(v)=='table' and not v.removed end
function math.Clamp(v,a,b) return math.max(a,math.min(b,v)) end
function math.Rand(a,b) return (a+b)/2 end
function Matrix() return {} end
local function band(a,b)
    local n,p=0,1
    for _=1,32 do if a%2==1 and b%2==1 then n=n+p end a,b,p=math.floor(a/2),math.floor(b/2),p*2 end
    return n
end
bit={band=band,bor=function(a,b)return a+b-band(a,b)end,bnot=function(a)return 4294967295-a end}
MASK_SOLID,CONTENTS_MONSTER,CONTENTS_GRATE=255,2,4
local frame,now=1,10
function CurTime() return now end
function FrameNumber() return frame end
local callbacks,classes,particles,emitters={},{},{},{}
hook={Add=function(event,_,fn) callbacks[event]=fn end}
local particleFiles={}
game={AddParticles=function(path)particleFiles[#particleFiles+1]=path end,GetMap=function()return 'native_map'end}
file={Read=function()return ''end,Exists=function()return true end}
function PrecacheParticleSystem() end
function CreateParticleSystemNoEntity(name,origin)
    local p={name=name,origin=origin,draws=0}
    function p:SetShouldDraw(v) assert(v==false) self.manual=true end
    function p:Render() assert(self.manual) self.draws=self.draws+1 end
    function p:StopEmission(_,remove) self.stopped=true if remove then self.removed=true end end
    function p:StartEmission()self.stopped=false end
    function p:SetControlPoint(i,pos)self.points=self.points or{}self.points[i]=pos end
    function p:SetControlPointOrientation(i,f,r,u)self.orientation={i,f,r,u}end
    function p:SetControlPointParent(i,parent)self.parents=self.parents or{}self.parents[i]=parent end
    particles[#particles+1]=p return p
end
function ParticleEmitter()
    local emitter={parts={}}
    function emitter:SetNoDraw(v) assert(v) end
    function emitter:Finish() self.removed=true end
    function emitter:Draw() end
    function emitter:Add(material,position)
        local p={material=material,position=position}
        for _,name in ipairs({'Velocity','Gravity','DieTime','StartSize','EndSize','StartAlpha','EndAlpha','Roll','RollDelta','NextThink','ThinkFunction'}) do
            p['Set'..name]=function(self,value)self[name]=value end
        end
        function p:SetColor(r,g,b) self.color={r,g,b} end
        function p:GetLifeTime() return 1 end
        self.parts[#self.parts+1]=p return p
    end
    emitters[#emitters+1]=emitter return emitter
end
local camera={fov=106,x=0,y=0,width=1600,height=900,znear=.07,zfar=20000}
local worldEye=Vector(101,202,303)
function EyePos()return worldEye end
function EyeAngles()return Angle()end
local cameraArgs,stack
render={GetRenderTarget=function()end,GetViewSetup=function()return camera end,OverrideDepthEnable=function()end}
cam={Start3D=function(...)cameraArgs={...}stack=1 end,PushModelMatrix=function()stack=stack+1 end,
    PopModelMatrix=function()stack=stack-1 end,End3D=function()stack=stack-1 end}
local IO={}
function IO.Value(e,k) return e[k] end
function IO.Number(e,k,fallback) return tonumber(e[k]) or fallback end
function IO.Vector(v) return isvector(v) and v or nil end
function IO.Angle(v) return v or Angle() end
function IO.Register(name,value)classes[name]=value end
function IO.State(s,r)s.records[r]=s.records[r]or{enabled=r.enabled}return s.records[r]end
function IO.Position(s,r)return IO.State(s,r).origin or r.origin end
function IO.Rotation(s,r)return IO.State(s,r).angles or r.angles end
PocketMap={Mini={},Active={},MapIO=IO,Entities={Class=function(e)return e.classname end},Walk={}}
local traces=0
function PocketMap.Walk.CollisionSession()
    return {TraceHull=function(_,start,finish,mins,maxs,mask)
        traces=traces+1 assert(finish.z==start.z-1024 and mask==249)
        return {HitPos=Vector(start.x,start.y,start.z-13)}
    end}
end
dofile('lua/pocketmap/cl_effects.lua')
local E=PocketMap.Effects
for i,size in ipairs({0,36,72,108,900}) do
    local expected=({'tiny','small','medium','large','large'})[i]
    assert(E.FireSystem({firesize=size,spawnflags=0})=='env_fire_'..expected..'_smoke')
    assert(E.FireSystem({firesize=size,spawnflags=2})=='env_fire_'..expected)
end
local fire={classname='env_fire',origin=Vector(10,20,30),firesize=16,spawnflags=269}
local off={classname='env_fire',origin=Vector(10,20,30),spawnflags=1}
local smoke={classname='env_smokestack',origin=Vector(10,20,30),InitialState=1,rendercolor=Color(42,42,42),Rate=10,roll=0}
local mini={mapName='arbitrary_map',state='ready',physics=false,scale=.01,mapCenter=Vector(),boxCenter=Vector(),mapIO={byEntity={}}}
mini.ent={WorldToLocal=function(_,p)return p-Vector(100,200,300)end,WorldToLocalAngles=function(_,a)return a end}
mini.bsp={PointInLeaf=function()return {cluster=1}end}
function mini:BlockPosition(p)return p*self.scale end
for _,e in ipairs({fire,off,smoke})do mini.mapIO.byEntity[e]={enabled=true}end
PocketMap.Active[mini]=true
E.Build(mini,{fire,off,smoke})
local function draw()
    E.Draw(mini,{[1]=true})
    callbacks.PostDrawTranslucentRenderables(false,false)
    assert(stack==0,'unbalanced camera or model matrix')
end
assert(#particles==0)
E.Draw(mini,{[1]=true})
assert(#particles==0,'native effects rendered inside the block callback')
callbacks.PostDrawTranslucentRenderables(false,false)
assert(#particles==1 and particles[1].name=='env_fire_tiny_smoke','infinite-fuel flag was interpreted as start-on')
assert(particles[1].origin.z==17 and traces==1,'native ground drop was not traced')
assert(cameraArgs[1].x==100 and cameraArgs[1].y==200 and cameraArgs[1].z==300,'particle camera not mapped into source units')
assert(math.abs(cameraArgs[8]-7)<.0001 and cameraArgs[9]==2000000,'particle depth projection not scaled with the geometry')
frame,now=2,10.2 draw()
assert(#emitters[1].parts==1 and emitters[1].parts[1].color[1]==42,'map smoke rate or Color was discarded')
local session={world=mini.mapIO,records={}}
PocketMap.Walk.session={mini=mini,io=session}
classes.env_fire.extinguish(session,mini.mapIO.byEntity[fire])
frame=3 draw()
assert(particles[1].removed,'extinguished fire was still emitting')
classes.env_fire.startfire(session,mini.mapIO.byEntity[fire])
frame=4 draw()
assert(#particles==2 and traces==1,'restarted fire lost its cached placement')
E.Destroy(mini) E.Destroy(mini)
assert(particles[2].removed and emitters[1].removed and mini.effectsView==nil,'effect resources survived miniature cleanup')
print('PASS effects: native fire selection, start flags, source traces/camera/depth, deferred rendering, smoke settings, inputs, cleanup')

local manifest=E.ManifestFiles([[// quoted/unquoted and repeated keys, not a particular map or effect
"particles_manifest" { "file" "particles/a.pcf" file "!particles/b.pcf" file "particles/a.pcf"
file "../lua/unsafe.pcf" file "particles/c.txt" }]])
assert(#manifest==2 and manifest[1]=='particles/a.pcf' and manifest[2]=='particles/b.pcf','manifest entries lost, duplicated or unsafe')
file.Read=function(name)if name=='maps/arbitrary_map_particles.txt'then return 'map {file "particles/custom.pcf"}'end return '' end
E.LoadManifests(mini)E.LoadManifests(mini)
local loaded=0 for _,p in ipairs(particleFiles)do if p=='particles/custom.pcf'then loaded=loaded+1 end end
assert(loaded==1,'particle files loaded repeatedly')
local target={origin=Vector(500,600,700),angles=Angle(),enabled=true}
local custom={classname='info_particle_system',origin=Vector(10,20,30),effect_name='some_other_addons_effect',start_active=1,cpoint1='target',cpoint1_parent=2}
mini.mapIO={byEntity={[custom]={origin=custom.origin,angles=Angle(),enabled=true}},names={target={target}}}
session={world=mini.mapIO,records={}}
PocketMap.Walk.session={mini=mini,io=session}
E.Build(mini,{custom})
frame=5 draw()
local p=particles[#particles]
assert(p.name=='some_other_addons_effect' and p.points[1].x==500 and p.parents[1]==2,'generic system or control points not preserved')
assert(traces==1,'custom particle was given a fire ground trace')
classes.info_particle_system.stop(session,mini.mapIO.byEntity[custom])
frame=6 draw()
assert(p.stopped and not p.removed,'Stop deleted live particles instead of letting them decay')
classes.info_particle_system.start(session,mini.mapIO.byEntity[custom])
frame=7 draw()
assert(not p.stopped,'Start failed to resume particle emission')
local count=#particles
p.removed=true
frame=8 draw()
assert(#particles==count,'a finished one-shot was restarted every frame')
classes.info_particle_system.stop(session,mini.mapIO.byEntity[custom])frame=9 draw()
classes.info_particle_system.start(session,mini.mapIO.byEntity[custom])frame=10 draw()
p=particles[#particles]
assert(#particles==count+1 and not p.removed,'a stopped and destroyed effect could not start again')
classes.info_particle_system.destroyimmediately(session,mini.mapIO.byEntity[custom])
frame=11 draw()
assert(p.removed,'DestroyImmediately left particles behind')
E.Destroy(mini)
print('PASS generic particles: manifests, arbitrary systems, control points, parenting, start/stop, immediate destruction')
