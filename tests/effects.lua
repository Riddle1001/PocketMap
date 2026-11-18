-- Run from the PocketMap root: lua tests/effects.lua
local vec = {} vec.__index = vec
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec) end
function vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vec.__div(a,b) return a*(1/b) end
function vec.__unm(a)return a*-1 end
function vec:Length()return math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z)end
function vec:Dot(v)return self.x*v.x+self.y*v.y+self.z*v.z end
function vec:GetNormalized()return self/self:Length()end
function isvector(v) return getmetatable(v)==vec end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0,
    Right=function()return Vector(0,-1,0)end,Forward=function()return Vector(1,0,0)end,Up=function()return Vector(0,0,1)end} end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255,color=true} end
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
    function p:SetControlPoint(i,pos)self.points=self.points or{}self.points[i]=pos
        self.poseCalls=self.poseCalls or{}self.poseCalls[i]=(self.poseCalls[i]or 0)+1 end
    function p:SetControlPointOrientation(i,f,r,u)self.orientation={i,f,r,u}
        self.orientationCalls=self.orientationCalls or{}self.orientationCalls[i]=(self.orientationCalls[i]or 0)+1 end
    function p:SetControlPointParent(i,parent)self.parents=self.parents or{}self.parents[i]=parent
        self.parentCalls=self.parentCalls or{}self.parentCalls[i]=(self.parentCalls[i]or 0)+1 end
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
local cameraArgs,stack,ignoreZ
render={GetRenderTarget=function()end,GetViewSetup=function()return camera end,OverrideDepthEnable=function()end}
cam={Start3D=function(...)cameraArgs={...}stack=1 end,PushModelMatrix=function()stack=stack+1 end,
    IgnoreZ=function(value)ignoreZ=value end,
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
mini.ent.LocalToWorld=function(_,p)return p+Vector(100,200,300)end
mini.bsp={PointInLeaf=function()return {cluster=1}end}
function mini:BlockPosition(p)return p*self.scale end
for _,e in ipairs({fire,off,smoke})do mini.mapIO.byEntity[e]={enabled=true}end
PocketMap.Active[mini]=true
E.Build(mini,{fire,off,smoke})
local function draw()
    E.Draw(mini,{[1]=true})
    callbacks.PostDrawTranslucentRenderables(false,false)
    assert(stack==0,'unbalanced camera or model matrix')
    assert(not ignoreZ,'effect draw leaked glow depth state')
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
local smokeParticle=emitters[1].parts[1]
smokeParticle.ThinkFunction(smokeParticle)
assert(smokeParticle.NextThink>now and smokeParticle.NextThink<=now+1/30+.000001,'smoke envelope still runs on every rendered frame')
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
frame=frame+1 draw()
assert(p.poseCalls[0]==1 and p.poseCalls[1]==1 and p.orientationCalls[1]==1 and p.parentCalls[1]==1,
    'stationary particle control points were unnecessarily resent')
target.origin.x=525
frame=frame+1 draw()
assert(p.poseCalls[1]==2 and p.points[1].x==525 and p.poseCalls[0]==1,
    'in-place control point position change was missed')
target.angles.y=30
frame=frame+1 draw()
assert(p.poseCalls[1]==3 and p.orientationCalls[1]==3,
    'in-place control point orientation change was missed')
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
assert(p.poseCalls[0]==1 and p.poseCalls[1]==1 and p.parentCalls[1]==1,
    'new particle instance reused stale native control point state')
classes.info_particle_system.destroyimmediately(session,mini.mapIO.byEntity[custom])
frame=11 draw()
assert(p.removed,'DestroyImmediately left particles behind')
E.Destroy(mini)
print('PASS generic particles: manifests, arbitrary systems, control points, parenting, start/stop, immediate destruction')

local bounded={classname='info_particle_system',origin=Vector(20,30,40),effect_name='bounded',start_active=1}
local record={origin=bounded.origin,angles=Angle(),enabled=true}
mini.mapIO={byEntity={[bounded]=record},names={}}
session={world=mini.mapIO,records={}}
PocketMap.Walk.session={mini=mini,io=session}
E.Build(mini,{bounded})
frame=12 draw()
p=particles[#particles]
function p:GetRenderBounds()return Vector(-10,-20,-30),Vector(10,20,30)end
local initial=p.draws
local visible=false
local function cull(part)
    assert(part.blockRadius>=.01*(math.sqrt(10^2+20^2+30^2)+16),'particle bounds were truncated')
    return visible
end
local function boundedDraw()
    frame=frame+1 E.Draw(mini,{[1]=true},{},cull)
    callbacks.PostDrawTranslucentRenderables(false,false)
end
boundedDraw()
assert(p.draws==initial and not p.removed,'offscreen particle rendered or was destroyed')
visible=true boundedDraw()
assert(p.draws==initial+1,'visible particle did not resume drawing')
visible=false IO.State(session,record).origin=Vector(500,600,700) boundedDraw()
assert(p.draws==initial+2,'moving control point was culled using stale bounds')
E.Destroy(mini)
print('PASS effect visibility: native bounds, padded radius, offscreen preservation, visible return, moving-system fallback')

-- Sprite render modes control shader tinting as well as blending. A plain
-- DrawSprite of the native material can ignore color and draw a black square.
local spriteValues, spriteDraws
local texture={GetName=function()return 'glow'end,GetNumAnimationFrames=function()return 4 end}
local spriteSource={GetName=function()return 'test/glow'end,GetShader=function()return 'Sprite_DX9'end,
    GetString=function()return 'vp_parallel'end,
    GetKeyValues=function()return {['$basetexture']='glow',['$spriterendermode']=0}end,
    IsError=function()return false end,Width=function()return 64 end,Height=function()return 32 end}
local spriteMaterial={SetFloat=function(self,k,v)self[k]=v end,SetInt=function(self,k,v)self[k]=v end,
    GetTexture=function()return texture end}
function CreateMaterial(_,shader,values)
    assert(shader=='Sprite') spriteValues=values return spriteMaterial
end
local queryVisibility=1
util={CRC=function(v)return v end,GetPixelVisibleHandle=function()return {}end,
    PixelVisible=function(position,radius)
        assert(stack==0,'pixel query submitted inside the source-coordinate camera')
        assert(math.abs(position.x-100.2)<1e-6 and math.abs(position.y-200.3)<1e-6 and math.abs(position.z-300.4)<1e-6,
            'pixel query used BSP coordinates instead of the miniature world position')
        assert(math.abs(radius-.16)<1e-6,'pixel query did not scale the glow proxy with the miniature')
        return queryVisibility
    end}
PocketMap.Materials={Load=function()return spriteSource end}
PocketMap.Entities.Name=function(e)return e.targetname end
local sprite={classname='env_sprite',origin=Vector(20,30,40),model='glow',scale=.75,
    rendermode=9,rendercolor=Color(254,216,146),HDRColorScale=2,renderamt=200,framerate=10,GlowProxySize=16}
record={origin=sprite.origin,enabled=true}
mini.mapIO={byEntity={[sprite]=record},names={}}
session={world=mini.mapIO,records={}}
PocketMap.Walk.session={mini=mini,io=session}
mini.bsp.SurfaceTraceLine=function()return {Hit=false}end
render.SetMaterial=function(m)assert(m==spriteMaterial)end
spriteDraws=0
local expectedIgnoreZ=true
local failSprite=false
render.DrawQuad=function(a,b,c,d,color)
    assert((ignoreZ==true)==expectedIgnoreZ,'glow halo was depth-clipped or ordinary sprite ignored geometry')
    if failSprite then error('sprite draw failure fixture') end
    local width,height=(a-b):Length(),(b-c):Length()
    assert(width==48 and height==24,'world glow size did not preserve source scale')
    assert(color.r==254 and color.g==216 and color.b==146,'warm entity color was lost')
    spriteDraws=spriteDraws+1
end
E.Build(mini,{sprite})
assert(spriteValues['$spriterendermode']==9 and spriteValues['$ignorevertexcolors']==0,
    'sprite shader ignored native render mode or entity tint')
frame=frame+1 draw()
assert(spriteDraws==1 and spriteMaterial['$hdrcolorscale']==2,'sprite or HDR color scale was lost')
queryVisibility=0
frame=frame+1 draw()
assert(spriteDraws==1,'fully occluded glow was rendered')
queryVisibility=nil
frame=frame+1 draw()
assert(spriteDraws==1,'pending query was treated as visible')
queryVisibility=1
frame=frame+1 draw()
assert(spriteDraws==2,'glow did not recover when the engine query became visible')
local effect=mini.effects[1]
effect.glow=false expectedIgnoreZ=false
frame=frame+1 draw()
assert(spriteDraws==3,'ordinary sprite did not retain depth-tested rendering')
effect.glow=true expectedIgnoreZ=true failSprite=true
frame=frame+1
local failed=pcall(draw)
assert(not failed and stack==0 and not ignoreZ,'failed glow draw leaked camera or depth state')
failSprite=false
local w,h,c=E.SpriteAppearance(effect,2400,1)
assert(w==48 and h==24 and c.a==200 and c.r==63.5,'world glow distance falloff changed its size or ignored native RGB fade')
effect.renderMode=3
w,h=E.SpriteAppearance(effect,400,1)
assert(w==96 and h==48,'ordinary glow lost native screen-size scaling')
local viewA=Angle()
local viewB={Right=function()return Vector(0,-1,0)end,Up=function()return Vector(1,0,0)end,
    Forward=function()return Vector(0,0,-1)end}
local ra,ua=E.SpriteAxes(effect,Vector(),viewA)
local rb,ub=E.SpriteAxes(effect,Vector(),viewB)
assert(ua.z==1 and ub.x==1 and ra.y==-1 and rb.y==-1,
    'billboard used the host camera axes instead of the nested source view')
assert(math.abs(rb:Dot(ub))<1e-6 and math.abs(ub:Dot(viewB:Forward()))<1e-6,
    'glow quad flattened at an oblique view')
effect.orientation='oriented'
rb,ub=E.SpriteAxes(effect,Vector(),viewB)
assert(ub.z==1,'fixed-orientation sprite incorrectly followed the camera')
classes.env_sprite.turnoff(session,record)
frame=frame+1 draw()
assert(spriteDraws==3,'TurnOff did not hide the sprite')
E.Destroy(mini)
print('PASS sprites: render modes, warm tint, HDR scale, source-view orientation, sizing, falloff and inputs')

local glow={glow=true,active=true,cluster=7}
local isolated={effects={glow}}
assert(E.RequiresEngineView(isolated,{[7]=true},{},function()return true end))
assert(not E.RequiresEngineView(isolated,{[8]=true},{},function()return true end))
assert(not E.RequiresEngineView(isolated,{[7]=true},{},function()return false end))
glow.active=false
assert(not E.RequiresEngineView(isolated,nil,nil))
glow.active=true;glow.cluster=nil
assert(E.RequiresEngineView(isolated,{},nil),'uncertain glow bounds must retain the engine view')
glow.record={enabled=false}
assert(not E.RequiresEngineView(isolated,nil,nil))
print('PASS direct-scene eligibility: active glows, PVS, current frustum and unknown fallbacks')

local preview=false
PocketMap.Settings={Enabled=function()return true end,MinimalPreview=function()return preview end}
mini.mapIO={byEntity={[custom]={origin=custom.origin,angles=Angle(),enabled=true}},names={target={target}}}
session={world=mini.mapIO,records={}}
PocketMap.Walk.session={mini=mini,io=session}
E.Build(mini,{custom})
frame=frame+1 draw()
local running=particles[#particles]
local records=mini.effects
local existingCount=#particles
preview=true
frame=frame+1 draw()
assert(running.removed and not mini.effectsView and mini.effects==records and mini.effectsDrawn==0,
    'outside preview must stop native simulation without losing authored effect records')
assert(not E.RequiresEngineView({effects={glow}},nil,nil),'outside preview must not demand native glow queries')
frame=frame+1 draw()
assert(#particles==existingCount,'preview restarted a suspended native effect')
preview=false
frame=frame+1 draw()
assert(#particles==existingCount+1 and not particles[#particles].removed and particles[#particles].draws>0,
    'entering failed to restart the enabled system from its retained record')
E.Destroy(mini)
print('PASS minimal preview effects: no invisible native simulation, retained records and restart on reentry')
