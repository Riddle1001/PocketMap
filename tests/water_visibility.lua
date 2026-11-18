local f=assert(io.open('lua/pocketmap/cl_water.lua','r'))
local source=f:read('*a');f:close()
local first=assert(source:find('local function reflectionLeaves(',1,true))
local last=assert(source:find('local function reflectionPVS(',first,true))
local env={preparePlanePVS=function()end,PocketMap={}}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(source:sub(first,last-1)..' return compileReflectionPVS'))
setfenv(chunk,env);local compile=chunk()
local bad=false
local leaves={
 {cluster=1,CreatePVS=function()return {[1]=true,[4]=true,__map={}}end},
 {cluster=2,CreatePVS=function()return {[2]=true,[8]=true}end},
}
local mini={bsp={GetVisibility=function()return {VisData={[1]={},[2]={}}}end,
 IsVisibilityCorrupted=function()return bad end,GetLeafs=function()return leaves end}}
local function run(planes)
 local rec={planes=planes}
 local co=coroutine.create(function()compile(mini,rec)end)
 local yields=0
 repeat assert(coroutine.resume(co))
  if coroutine.status(co)~='dead' then
   assert(rec.reflectionPVS==nil,'partial visibility must never be published')
   yields=yields+1
  end
 until coroutine.status(co)=='dead'
 return rec.reflectionPVS,yields
end
local pvs,yields=run({{pvsClusters={1}},{pvsClusters={2,1}}})
assert(pvs[1] and pvs[2] and pvs[4] and pvs[8] and not pvs.__map and yields==2,
 'all disconnected water clusters must be unioned once')
assert(run({{pvsClusters={1}},{}})==nil,'an unknown patch must fail open')
assert(run({{pvsClusters={99}}})==nil,'an unknown cluster must fail open')
bad=true
assert(run({{pvsClusters={1}}})==nil,'corrupt VIS must fail open')
local water={pass='reflection',sceneView={mini=mini,pvs=pvs}}
env.Water=water
env.cvReflectionPVS={GetBool=function()return true end}
first=assert(source:find('function Water.ReflectionPVS(',1,true))
last=assert(source:find('PocketMap.Hooks.Register( "Think", "PocketMap_WaterVisibility"',first,true))
chunk=assert(loadstring(source:sub(first,last-1)))setfenv(chunk,env)chunk()
assert(water.ReflectionPVS(mini)==pvs and water.ReflectionPVS({})==nil)
water.pass='refraction'
assert(water.ReflectionPVS(mini)==nil,'the set must never leak into another pass')
f=assert(io.open('lua/pocketmap/cl_draw.lua','r'));source=f:read('*a');f:close()
first=assert(source:find('local function worldPVSCandidates(',1,true))
last=assert(source:find('-- The world meshes and their bounds are immutable',first,true))
chunk=assert(loadstring(source:sub(first,last-1)..' return worldPVSCandidates'))
setfenv(chunk,env);local candidates=chunk()
local meshes={{worldClusters={1}},{worldClusters={2}},{}}
local a,b={[1]=true},{[2]=true}
water.pass=nil
local main=candidates(mini,meshes,a,false)
water.pass='refraction'
local refract=candidates(mini,meshes,b,false)
water.pass=nil
assert(candidates(mini,meshes,a,false)==main and main~=refract,
 'nested views must not continually evict main-view candidate lists')
local function bound(z)
 return {blockCenter={x=0,y=0,z=z},blockRadius=100,blockExtents={x=100,y=1,z=1}}
end
local above,below,crossing,unknown=bound(10),bound(-10),bound(0),{}
local geometry={above,below,crossing,unknown}
local function view(distance)return {boxClip=true,clip={normal={x=0,y=0,z=-1},distance=distance}}end
water.pass='refraction'
local clipped=candidates(mini,geometry,nil,false,view(0))
assert(#clipped==3 and clipped[1]==below and clipped[2]==crossing and clipped[3]==unknown)
assert(candidates(mini,geometry,nil,false,view(0))==clipped,'moving cameras must reuse static clip candidates')
local lower=candidates(mini,geometry,nil,false,view(5))
assert(#lower==2 and lower[1]==below and lower[2]==unknown,'different heights must retain distinct lists')
assert(candidates(mini,geometry,nil,false,view(0))==clipped,'alternating heights must not evict each other')
assert(candidates(mini,geometry,nil,false,{boxClip=false,clip=view(0).clip})==geometry)
local old=candidates(mini,geometry,a,false)
mini.worldPVSCandidates.refraction_opaque.clips=nil
assert(#candidates(mini,geometry,a,false,view(0))==3,'pre-reload cache entries must be upgraded safely')
local changed=candidates(mini,geometry,b,false,view(0))
assert(changed~=clipped and changed~=old,'PVS changes must invalidate plane candidates')
for i=1,20 do candidates(mini,geometry,b,false,view(i))end
assert(#mini.worldPVSCandidates.refraction_opaque.clips<=16,'clip cache storage must stay bounded')
print('water visibility: complete unions, clip cache reuse/migration, bounded storage and unknown fallbacks passed')
