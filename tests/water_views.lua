-- Run from PocketMap root: lua tests/water_views.lua
local vec={} vec.__index=vec
local function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec.__div(a,b)return a*(1/b)end
function vec.__eq(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
function vec:Dot(b)return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:DistToSqr(b)local d=self-b return d:Dot(d)end
function vec:Normalize()local n=math.sqrt(self:Dot(self));self.x,self.y,self.z=self.x/n,self.y/n,self.z/n end
local angles={Forward=function()return Vector(1,0,0)end,Right=function()return Vector(0,-1,0)end,Up=function()return Vector(0,0,1)end}
local reflected={Forward=function()return Vector(-1,0,0)end,Right=function()return Vector(0,1,0)end,Up=angles.Up}
local primary={origin=Vector(),angles=angles,fov=90,width=1280,height=720,frame=10}
local nested={origin=Vector(5,0,0),angles=reflected,fov=90,width=640,height=360}
local water={pass='reflection',sceneView=nested,view=primary}
local target={}
local pocket={Water=water,PVSFreeze={Get=function()end}}
local env={PocketMap=pocket,Vector=Vector,Angle=function()return {}end,FRUSTUM_PAD=5,FRUSTUM_FOV_PAD=3,
    cvWaterClipBounds={GetBool=function()return true end},
    EyePos=function()return primary.origin end,EyeAngles=function()return primary.angles end,
    FrameNumber=function()return 10 end,ScrW=function()return 1280 end,ScrH=function()return 720 end,
    render={GetRenderTarget=function()return target end,GetViewSetup=function()return primary end}}
setmetatable(env,{__index=_G})
local function loadFunction(path,name,nextMarker)
    local f=assert(io.open('lua/pocketmap/'..path,'r'));local src=f:read('*a');f:close()
    local first=assert(src:find('local function '..name..'(',1,true))
    local last=assert(src:find(nextMarker,first,true))
    local fn=assert(loadstring(src:sub(first,last-1)..'\nreturn '..name))
    setfenv(fn,env)return fn()
end
local mini={scale=1,boxCenter=Vector(),mapCenter=Vector(),UpdateMatrix=function()return 1 end,
    ent={GetPos=function()return Vector()end,WorldToLocal=function(_,v)return v end,WorldToLocalAngles=function(_,v)return v end}}
pocket.Walk={session={mini=mini}}
local visibility=assert(loadfile('lua/pocketmap/cl_visibility.lua'))
setfenv(visibility,env) visibility()
env.Water=water
do
    local f=assert(io.open('lua/pocketmap/cl_water.lua','r'));local src=f:read('*a');f:close()
    local first=assert(src:find('function Water.ClipPlane(',1,true))
    local last=assert(src:find('local function drawMirroredSky',first,true))
    local fn=assert(loadstring(src:sub(first,last-1)))setfenv(fn,env)fn()
end
local props=loadFunction('cl_props.lua','viewFrustum','-- An opaque')
local doors=loadFunction('mapio/cl_doorprops.lua','doorFrustum','local function inFrustum')
local brushes=loadFunction('mapio/cl_render.lua','drawView','local function drawPVS')
local propVisible=loadFunction('cl_props.lua','visibleInFrustum','-- Only a single opaque')
local doorVisible=loadFunction('mapio/cl_doorprops.lua','inFrustum','local function doorClusters')
for _,get in ipairs({props,doors})do
    local v=get(mini)
    assert(v and v.origin==nested.origin and v.forward.x==-1,'water must use the nested camera, not the primary view')
    assert(v.halfHeight>=math.tan(math.rad(45)),'nested vertical FOV must remain conservative')
    assert(propVisible({lcenter=Vector(-100,0,0),sphereRadius=1},v))
    assert(not propVisible({lcenter=Vector(100,0,0),sphereRadius=1},v))
    assert(doorVisible({blockCenter=Vector(-100,0,0),blockRadius=1},v))
    assert(not doorVisible({blockCenter=Vector(100,0,0),blockRadius=1},v))
end
assert(brushes(mini).origin==nested.origin and brushes(mini).forward.x==-1,'brushes must use the nested frustum')
local doorPVS=loadFunction('mapio/cl_doorprops.lua','doorPVS','local function inPVS')
local brushPVS=loadFunction('mapio/cl_render.lua','drawPVS','-- A sphere')
assert(doorPVS(mini,doors(mini))==nil and brushPVS(mini,pocket.Walk.session,brushes(mini))==nil,
    'reflections must not use VIS from the mirrored eye')
water.pass='refraction'
assert(props(mini).origin==nested.origin and doors(mini).origin==nested.origin and brushes(mini).origin==nested.origin)
nested.clipNormal=Vector(0,0,-1);nested.clipDistance=5
for _,get in ipairs({props,doors})do
    local v=get(mini)
    assert(not propVisible({lcenter=Vector(-100,0,0),sphereRadius=1},v),'fully clipped props must not draw')
    assert(not doorVisible({blockCenter=Vector(-100,0,0),blockRadius=1},v),'fully clipped doors must not draw')
    assert(propVisible({lcenter=Vector(-100,0,-5),sphereRadius=1},v),'straddling props must stay visible')
    assert(doorVisible({blockCenter=Vector(-100,0,-5),blockRadius=1},v),'straddling doors must stay visible')
    assert(propVisible({},v) and doorVisible({},v),'unknown bounds must fail open')
end
env.cvWaterSceneCull={GetBool=function()return true end};env.WORLD_FRUSTUM_FOV_PAD=6
local worldView=loadFunction('cl_draw.lua','worldView','local function worldPVS')
local worldVisible=loadFunction('cl_draw.lua','worldPartVisible','-- The BSP PVS')
local v=worldView(mini)
assert(not worldVisible({blockCenter=Vector(-100,0,0),blockRadius=1},v))
assert(worldVisible({blockCenter=Vector(-100,0,-5),blockRadius=1},v))
-- A very wide, thin surface above water overlaps it only in sphere space.
assert(not worldVisible({blockCenter=Vector(-100,0,0),blockRadius=100,
    blockExtents=Vector(100,1,1)},v),'thin world surfaces must use their real clip support')
assert(worldVisible({blockCenter=Vector(-100,0,-5),blockRadius=100,
    blockExtents=Vector(100,1,1)},v),'boxes crossing the water plane must stay visible')
local propView=props(mini)
assert(not propVisible({lcenter=Vector(-100,0,0),sphereRadius=100,
    boxExtents=Vector(100,1,1)},propView),'thin static props must use their real clip support')
assert(propVisible({lcenter=Vector(-100,0,-5),sphereRadius=100,
    boxExtents=Vector(100,1,1)},propView),'intersecting prop boxes must stay visible')
env.cvPropFrustumCache={GetBool=function()return true end}
local sameView=loadFunction('cl_props.lua','sameCullView','local function visibleInFrustum')
local previous=props(mini)
nested.clipDistance=10
assert(not sameView({stamp=1,frustum=previous},1,nil,props(mini)),
    'different water heights must not reuse clipped prop candidates')
env.cvWorldFrustumCache={GetBool=function()return true end}
env.worldPVSCandidates=function(_,meshes)return meshes end;env.worldPartVisible=worldVisible
local frustumParts=loadFunction('cl_draw.lua','worldFrustumParts','---The reflection')
local meshes={{blockCenter=Vector(-100,0,-7),blockRadius=1}}
nested.clipDistance=5
assert(#frustumParts(mini,meshes,nil,false,worldView(mini))==1)
nested.clipDistance=10
assert(#frustumParts(mini,meshes,nil,false,worldView(mini))==0,
    'different water heights must not reuse clipped world candidates')
nested.clipNormal,nested.clipDistance=nil,nil
water.sceneView=nil
assert(props(mini)==nil and doors(mini)==nil and brushes(mini)==nil,'unknown water cameras must fail open')
water.pass=nil
assert(props(mini)==nil and doors(mini)==nil and brushes(mini)==nil,'unknown render targets must fail open')
target=nil
assert(props(mini).origin==primary.origin and doors(mini).origin==primary.origin and brushes(mini).origin==primary.origin,'primary camera must still work')
water.pass='refraction';water.sceneView={clipNormal=Vector(1,0,0),clipDistance=15}
local translated={ent={GetPos=function()return Vector(10,20,100)end,
    WorldToLocal=function(_,v)return Vector(v.y-20,10-v.x,v.z-100)end}}
local clip=water.ClipPlane(translated)
assert(clip.normal==Vector(0,-1,0) and clip.distance==5,'clip planes must follow translated, rotated miniatures')
water.sceneView=nil
assert(water.ClipPlane(mini)==nil,'unknown clip planes must fail open')
local entityDraws=0
pocket.MapIO={Draw=function()entityDraws=entityDraws+1 end}
pocket.Materials={DrawOptions=function(o)return o end}
env.drawWorld=function()end;env.drawFlashlights=function()end;water.Draw=function()end
env.worldView=worldView;env.worldPVS=function()end
env.Detail={Blends=function()return false end,Draw=function()end};env.Props={Draw=function()end}
local drawContents=loadFunction('cl_draw.lua','drawContents','function Mini:WaterDrawOptions')
water.pass='reflection';water.sceneView={reflectEntities=false}
drawContents(mini,{},'opaque')
assert(entityDraws==0,'world-only reflections must omit map entities')
water.sceneView.reflectEntities=true
drawContents(mini,{},'opaque')
assert(entityDraws==1,'materials requesting entity reflections must keep them')
water.pass='refraction'
drawContents(mini,{},'opaque')
assert(entityDraws==2,'refraction must still draw underwater entities')

-- RenderScene's eye globals still refer to the previous camera. A scoped
-- primary view must reach every culler and the water surface draw itself.
water.pass=nil;target=nil
local owned={origin=Vector(20,30,40),angles=reflected,fov=90,width=1280,height=720,frame=10}
pocket.Scene={View=function()return owned end}
water.view=owned
assert(worldView(mini).origin==owned.origin and worldView(mini).forward.x==-1)
assert(props(mini).origin==owned.origin and props(mini).forward.x==-1)
assert(doors(mini).origin==owned.origin and doors(mini).forward.x==-1)
assert(brushes(mini).origin==owned.origin,'brushes ignored the scoped primary camera')
local waterDrawView=loadFunction('cl_water.lua','drawView','local function drawPlanes')
assert(waterDrawView(mini).origin==owned.origin,'water surfaces fell back to stale engine eye globals')
print('water views: nested cameras, clip bounds, clip cache isolation, reflected VIS safety and fallbacks passed')
