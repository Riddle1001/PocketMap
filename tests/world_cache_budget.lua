local vec={}vec.__index=vec
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)end
function vec:DistToSqr(b)return (self.x-b.x)^2+(self.y-b.y)^2+(self.z-b.z)^2 end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__unm(a)return Vector(-a.x,-a.y,-a.z)end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec.__div(a,b)return a*(1/b)end
function vec:Dot(b)return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:Cross(b)return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x)end
function vec:GetNormalized()return self/math.sqrt(self:Dot(self))end
local frame,now=100,0
function FrameNumber()return frame end
function SysTime()now=now+.0002 return now end
local think
PocketMap={Settings={Enabled=function(m,key)return m.settings[key]end},Hooks={Register=function(_,_,fn)think=fn end},Active={}}
dofile('lua/pocketmap/cl_worldcache.lua')
local active,obsolete=0,0
local mini={settings={world_cache=true,defer_world_cache=true}}
local move={origin=Vector(0,0,0)}
PocketMap.Active[mini]=true;PocketMap.Walk={session={mini=mini,move=move}}
mini.worldVisibilityCache={
	{used=frame,co=coroutine.create(function()while true do active=active+1 coroutine.yield()end end)},
	{used=frame-20,co=coroutine.create(function()while true do obsolete=obsolete+1 coroutine.yield()end end)},
}
think()
assert(active==0,'initial movement settle interval must not compile transient visibility')
now=.2;frame=frame+1;mini.worldVisibilityCache[1].used=frame
think()
assert(active>0 and obsolete==0,'only the recently requested visibility set may spend the build budget')
local previous=active
move.origin=Vector(10,0,0);now=.3;frame=frame+1;mini.worldVisibilityCache[1].used=frame
think()
assert(active==previous,'moving between visibility regions must defer background compilation')
now=.5;frame=frame+1;mini.worldVisibilityCache[1].used=frame
think()
assert(active>previous and obsolete==0,'settled views must resume the current visibility build')
previous=active;mini.settings.world_cache=false
now=.8;think()
assert(active==previous,'disabled caching must not leave a background compiler running')
mini.settings.world_cache=true;mini.settings.defer_world_cache=false
move.origin=Vector(20,0,0);mini.worldVisibilityCache[1].used=frame
think()
assert(active>previous,'manual eager compilation must remain available')
previous=active;mini.settings.defer_world_cache=true
PocketMap.PVSFreeze={Get=function()return {}end}
move.origin=Vector(30,0,0)
think()
assert(active>previous,'frozen visibility must still compile while the camera moves during diagnostics')
print('PASS world cache: motion deferral, settled resume, active-view priority and disabled-cache cleanup')

local wireframe=false
function GetConVar()return {GetBool=function()return wireframe end}end
bit={band=function(flags)return flags end}
PocketMap.Visibility={OpaqueWorldFace=function()return true end}
local cache=PocketMap.WorldCache
local face={GetNormal=function()return Vector(-1,0,0)end,
    GetVertexs=function()return {Vector(10,-5,-5),Vector(10,-5,5),Vector(10,5,5),Vector(10,5,-5)}end}
local parts={}
for i=1,48 do parts[i]={}end
local entry={parts=parts,faces={[face]={GetInt=function()return 0 end}}}
mini.scale=1
mini.bsp={SurfaceTraceLine=function()return {Hit=true,Face=face}end}
local view={mapOrigin=Vector(),forward=Vector(1,0,0),right=Vector(0,1,0),up=Vector(0,0,1),znear=1}
local behind={worldCenter=Vector(20,0,0),worldExtents=Vector(1,1,1)}
local crossing={worldCenter=Vector(20,9,0),worldExtents=Vector(1,2,1)}
local inFront={worldCenter=Vector(9,0,0),worldExtents=Vector(1,1,1)}
assert(not cache.Occluders(mini,entry,view),'new views must draw immediately')
frame=frame+2
local shadows=assert(cache.Occluders(mini,entry,view))
assert(cache.Occluded(behind,shadows) and not cache.Occluded(crossing,shadows) and not cache.Occluded(inFront,shadows))
assert(not cache.Occluded({},shadows),'unknown mesh bounds must remain visible')
view.mapOrigin=Vector(0,13,0)
assert(not cache.Occluders(mini,entry,view),'camera movement must expose the batch immediately')
frame=frame+2
assert(not cache.Occluded(behind,assert(cache.Occluders(mini,entry,view))),'a view around the wall must retain the batch')
view.mapOrigin,view.znear=Vector(),11
assert(not cache.Occluders(mini,entry,view))
frame=frame+2
assert(not cache.Occluders(mini,entry,view),'near-clipped wall must not act as a blocker')
view.znear=1
wireframe=true
assert(not cache.Occluders(mini,entry,view),'wireframe must preserve hidden geometry for debugging')
print('PASS world occlusion: full bounds, frame-local visibility, near plane and fail-open guards')
