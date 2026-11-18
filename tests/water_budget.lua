-- Run from PocketMap root: lua tests/water_budget.lua
local file = assert(io.open('lua/pocketmap/cl_water.lua', 'r'))
local source = file:read('*a') file:close()
local function loadFunction(name, nextMarker, env)
    local first = assert(source:find('local function ' .. name .. '(', 1, true))
    local last = assert(source:find(nextMarker, first, true))
    local chunk = assert(loadstring(source:sub(first, last - 1) .. '\nreturn ' .. name))
    setfenv(chunk, setmetatable(env, {__index = _G}))
    return chunk()
end
local vec = {} vec.__index = vec
local function Vector(x, y, z)
    if type(x) == 'table' then return Vector(x.x, x.y, x.z) end
    return setmetatable({x=x or 0, y=y or 0, z=z or 0}, vec)
end
function vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vec.__div(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
function vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vec.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function vec:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:DistToSqr(b) local d=self-b return d.x*d.x+d.y*d.y+d.z*d.z end

local cluster, corrupt, reads = 1, false, 0
local pvsByCluster = {{[1]=true}, {[2]=true}}
local bsp = {
    ClusterFromPoint=function() return cluster end,
    GetVisibility=function() return {VisData={[1]={},[2]={}}} end,
    IsVisibilityCorrupted=function() return corrupt end,
    PVSForOrigin=function() reads=reads+1 return pvsByCluster[cluster] end,
}
local pos, angles = Vector(), {Up=function()return Vector(0,0,1)end}
local mini = {bsp=bsp, scale=1, boxCenter=Vector(), mapCenter=Vector(),
    ent={WorldToLocal=function(_,v)return v end, GetPos=function()return pos end, GetAngles=function()return angles end},
    matrix=setmetatable({}, {__mul=function(_,v)return v end})}
local pocket = {Walk={session={mini=mini}}, PVSFreeze={Get=function()end}}
local env = {PocketMap=pocket}
env.effectsPVS = loadFunction('effectsPVS', '---The heights', env)
local view = {origin=Vector(0,0,10), angles={}, fov=90}
assert(env.effectsPVS(mini,view)==pvsByCluster[1])
assert(env.effectsPVS(mini,view)==pvsByCluster[1] and reads==1, 'same-cluster VIS must be reused')
cluster=2
assert(env.effectsPVS(mini,view)==pvsByCluster[2] and reads==2, 'camera crossing must refresh VIS before world drawing')
corrupt=true
assert(env.effectsPVS(mini,view)==nil, 'invalid VIS must draw uncertain water')
corrupt=false
env.visibleInPVS = loadFunction('visibleInPVS', '-- A reflected eye', env)
env.preparePlanePVS=function() error('fixture planes already have VIS') end
env.planeWorldBounds=function() return Vector(),Vector(1,1,0),0 end
env.boxVisible=function()return true end
env.BOX_PAD_SCALE=64
env.isNearer=function(a,b)return a.distanceSqr<b.distanceSqr end
env.ensurePlaneMode=function()end
env.reflectionSky=loadFunction('reflectionSky','local function drawPlanes',env)
env.Vector=Vector
env.waterSurface=loadFunction('waterSurface','---The heights',env)
local tilted=setmetatable({}, {__mul=function(_,v)return Vector(100+.8*v.x+.6*v.z,200+v.y,300-.6*v.x+.8*v.z) end})
local tiltedMini={matrix=tilted,scale=1,boxCenter=Vector(),mapCenter=Vector()}
local surface=env.waterSurface(tiltedMini,-10,Vector(.6,0,.8),Vector(100,200,300))
assert(math.abs((tilted*Vector(250,700,-10)):Dot(surface.normal)-surface.distance)<1e-6
    and math.abs(surface.eyeHeight-10)<1e-6 and surface.localHeight==-10,
    'water clip plane must follow the miniature rotation, independent of receiver bounds')
local heights = loadFunction('visibleHeights', '---Draws the reflection', env)
local hidden={pvsBSP=bsp,pvsClusters={1},reflectScene=true,refractScene=true}
local visible={pvsBSP=bsp,pvsClusters={2},reflectScene=false,refractScene=true}
mini.waterHeights={{z=0,planes={hidden}},{z=0,planes={visible}}}
local found=heights(mini,view,1)
assert(#found==1 and found[1].plane==visible, 'hidden water must not render reflection/refraction scenes')
cluster=-1
assert(#heights(mini,view,1)==2, 'unknown camera cluster must fail open')
cluster=2
visible.pvsClusters=nil
assert(#heights(mini,view,1)==1, 'unknown plane clusters must stay visible')
local reflection={pvsBSP=bsp,pvsClusters={2},reflectScene=true,refractScene=false,reflectEntities=true}
local cheap={pvsBSP=bsp,pvsClusters={2},cheap=true,reflectScene=false,refractScene=false}
mini.waterHeights={{z=0,planes={cheap,visible,reflection}},{z=0,planes={cheap}}}
found=heights(mini,view,1)
assert(#found==1 and found[1].reflection and found[1].refraction and found[1].reflectEntities,
    'shared heights must union visible material passes and skip cheap water')
reflection.pvsClusters={1};reflection.checkedPVS=nil
found=heights(mini,view,1)
assert(#found==1 and not found[1].reflection and found[1].refraction,
    'hidden reflective water must not add a reflection pass')

local frame, quality, renders = 10, 1, 0
env.Water={budgetFrame=frame}
env.cvWater={GetInt=function()return quality end}
env.FrameNumber=function()return frame end
env.CurTime=function()return 1 end
env.SysTime=function()return 1 end
env.Vector=Vector env.Angle=function(a)return a end
env.acquireHeightTargets=function()return true end
env.renderPlane=function(_,_,_,_,pass,required)renders=renders+1;env.lastPass=pass;env.required=required end
env.BUDGETED_REFRESH_SECONDS=1/14
env.turnOffEffects=function(err)error(err)end
env.releaseHeightTargets=function(rec)rec.reflect=nil;rec.valid=false end
env.useFlatTargets=function(plane)plane.cleared=true plane.reflectRT=nil plane.refractRT=nil end
env.showHeightTargets=loadFunction('showHeightTargets','---Draws the reflection',env)
local renderHeight=loadFunction('renderHeight', '---@return boolean ok', env)
local cleanup=loadFunction('clearIdlePlanes', 'PocketMap.Hooks.Register', env)
local plane={rendered=false}
local rec={valid=true,reflect={},planes={plane},camera={origin=view.origin,angles=view.angles,fov=view.fov,pos=pos,rotation=angles,reflection=true,refraction=true}}
mini.waterHeights={rec} mini.waterPlanes={plane}
local entry={rec=rec,plane=plane,zWorld=0,reflection=true,refraction=true}
assert(renderHeight(mini,entry,view,1))
cleanup(mini)
assert(rec.valid and rec.reflect and plane.rendered and rec.lastFrame==frame and renders==0,
    'deferring a visible height must preserve its targets through cleanup')
plane.rendered=false;rec.valid=false;rec.reflect=nil
renderHeight(mini,entry,view,1)
assert(not plane.rendered and renders==0, 'uninitialized deferred targets must not be displayed')
rec.camera.fov=80
renderHeight(mini,entry,view,1)
assert(renders==1 and env.lastPass==nil, 'camera movement must refresh both projected scenes')
quality=2
renderHeight(mini,entry,view,1)
assert(renders==2 and env.lastPass==nil, 'full quality must still render both scenes')
quality=1;env.Water.budgetFrame=nil;rec.nextRefresh=0;rec.nextPass='reflection'
entry.reflection=false
renderHeight(mini,entry,view,1)
assert(renders==3 and env.lastPass==nil and not env.required.reflection,
    'changed material requirements must refresh even with the same camera')
rec.nextRefresh=0;env.Water.budgetFrame=nil;rec.nextPass='reflection'
renderHeight(mini,entry,view,1)
assert(renders==4 and env.lastPass=='refraction', 'single-pass water must never alternate into a disabled pass')
print('water budget: current-camera VIS, safe fallbacks, retained targets, movement and full quality passed')
