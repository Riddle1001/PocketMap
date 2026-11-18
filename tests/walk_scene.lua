-- Run from PocketMap: lua tests/walk_scene.lua
local frame, enabled, target, outside, fail = 7, true, nil, false, nil
local camera = {width=1600,height=900,x=0,y=0,fov=106,znear=.1,zfar=30000}
local origin, angles = {}, {}
camera.origin,camera.angles=origin,angles
local callback, depth3D, depth2D, hud, draws, errors = nil, 0, 0, 0, 0, 0
local shouldSkipSky
local gradeEnabled, hostEntities = false, {}
function FrameNumber()return frame end
function ScrW()return 1600 end
function ScrH()return 900 end
function IsValid(e)return e and not e.removed end
function CreateClientConVar()return {GetBool=function()return enabled end}end
function GetConVar(name)
	assert(name=="mat_colorcorrection")
	return {GetBool=function()return gradeEnabled end}
end
game={GetMap=function()return 'host' end}
NikNaks={Map=function()return {GetEntities=function()return hostEntities end}end,
	EntityValue=function(entity,key)return entity[key] end}
function EyePos()return 'stale origin' end
function EyeAngles()return 'stale angles' end
local eyePos,eyeAngles=EyePos,EyeAngles
function ErrorNoHalt()errors=errors+1 end
local noop=function()end
render={GetRenderTarget=function()return target end,GetViewSetup=function()return camera end,
    SetStencilEnable=noop,Clear=noop,ClearDepth=noop,OverrideDepthEnable=noop,DepthRange=noop,
    RenderHUD=function()hud=hud+1 end}
cam={Start3D=function()depth3D=depth3D+1 end,End3D=function()depth3D=depth3D-1 end,
    Start2D=function()depth2D=depth2D+1 end,End2D=function()depth2D=depth2D-1 end}
local calls={}
hook={Run=function(event)
    calls[event]=(calls[event]or 0)+1
    if fail==event then error('effect failure')end
end}
local mini={state='ready',ent={IsOutsideBox=function()return outside end}}
PocketMap={Water={},Walk={session={mini=mini}},Entities={Class=function(entity)return entity.classname end},
    Hooks={Register=function(event,_,fn)
        if event=='RenderScene' then callback=fn
        elseif event=='PreDrawSkyBox' then shouldSkipSky=fn
        else error('unexpected callback '..event) end
    end},
    Sky={DrawCube=function(m,o)
        assert(m==mini and o==origin and PocketMap.Scene.View(m).origin==origin)
    end}}
function mini:Draw(pass)
	assert(pass=='opaque' or pass=='translucent')
	if pass=='translucent' then assert(calls.PostDrawOpaqueRenderables==1,'opaque callbacks ran after transparency')end
    local v=assert(PocketMap.Scene.View(self))
    assert(v.origin==origin and v.angles==angles and v.znear==camera.znear)
    assert(PocketMap.Scene.View({})==nil,'the owned view leaked to another miniature')
    PocketMap.Water.pass='reflection'
    assert(PocketMap.Scene.View(self)==nil,'a nested water camera inherited the main view')
    PocketMap.Water.pass=nil;target={}
    assert(PocketMap.Scene.View(self)==nil,'a render target inherited the main view')
    target=nil
    frame=frame+1
    assert(PocketMap.Scene.View(self)==nil,'a stale frame inherited the main view')
    frame=frame-1
    draws=draws+1
    if fail=='draw' then error('mesh failure')end
end
local function load()calls={};dofile('lua/pocketmap/cl_scene.lua')end
local function draw()return callback(origin,angles,106)end
local function restored()
    assert(depth3D==0 and depth2D==0 and PocketMap.Scene.current==nil,'camera scope leaked')
    assert(EyePos==eyePos and EyeAngles==eyeAngles,'engine eye functions were replaced')
end
load()
assert(draw()==true and draws==2 and hud==1)
assert(calls.PostDrawOpaqueRenderables==1 and calls.PostDrawTranslucentRenderables==1
    and calls.RenderScreenspaceEffects==1,'effects/HUD pipeline was skipped or duplicated')
restored()
mini.RequiresEngineView=function(self)
    assert(PocketMap.Scene.View(self).origin==origin,'eligibility used the stale eye')
    return 'glow'
end
assert(draw()==nil and draws==2 and hud==1 and PocketMap.Scene.lastFallback=='glow')
assert(not shouldSkipSky(),'a pocket without a sky backdrop hid the host sky')
mini.skyBackdrop,mini.scaleVec,mini.objects={},{},{true}
assert(draw()==nil)
target={};assert(not shouldSkipSky(),'host sky suppression leaked into a render target');target=nil
PocketMap.Water.pass='refraction';assert(not shouldSkipSky());PocketMap.Water.pass=nil
camera.angles={};assert(not shouldSkipSky(),'a secondary camera lost its sky');camera.angles=angles
assert(shouldSkipSky() and not shouldSkipSky(),'the main sky skip should apply only once')
assert(draw()==nil)
frame=frame+1;assert(not shouldSkipSky(),'a later frame reused old sky suppression');frame=frame-1
mini.RequiresEngineView=function()return 'flashlight'end
assert(draw()==nil and not shouldSkipSky(),'flashlight fallback must retain native rendering')
restored()
mini.RequiresEngineView=nil
hostEntities={{classname='color_correction',filename='materials/colorcorrection/map.raw'}}
gradeEnabled=true
load()
assert(draw()==nil and PocketMap.Scene.lastFallback=='color correction' and draws==2 and hud==1,
	'a host LUT disappeared when the view no longer needed native glow queries')
assert(shouldSkipSky(),'native color correction redrew a fully covered host sky')
restored()
gradeEnabled=false
assert(draw()==true and draws==4 and hud==2,'disabling native color correction did not restore the direct view')
restored()
gradeEnabled=true
hostEntities={{classname='color_correction_volume'}}
load()
assert(draw()==true and draws==6 and hud==3,'an ungraded host must retain the direct renderer')
restored()
enabled=false;assert(draw()==nil);enabled=true
outside=true;assert(draw()==nil);outside=false
target={};assert(draw()==nil);target=nil
PocketMap.Water.pass='refraction';assert(draw()==nil);PocketMap.Water.pass=nil
PocketMap.Walk.session.waitingForRespawn=true;assert(draw()==nil);PocketMap.Walk.session.waitingForRespawn=nil
camera.ortho=true;assert(draw()==nil);camera.ortho=nil
camera.width=800;assert(draw()==nil);camera.width=1600
mini.state='loading';assert(draw()==nil);mini.state='ready'
assert(draws==6 and hud==3,'an unsupported view took ownership')
for _,fault in ipairs({'draw','RenderScreenspaceEffects'})do
    load();fail=fault
    assert(draw()==nil and PocketMap.Scene.failedMini==mini)
    restored()
    local before=draws
    fail=nil;assert(draw()==nil and draws==before,'a failed renderer did not fall back')
end
assert(errors==2)
print('walking scene: current camera, nested-view isolation, HUD/effects, fallback and error cleanup passed')
