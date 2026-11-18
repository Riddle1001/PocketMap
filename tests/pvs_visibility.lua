-- Run from the PocketMap root: lua tests/pvs_visibility.lua
local vec={} vec.__index=vec
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec.__div(a,b)return a*(1/b)end
PocketMap={}
CONTENTS_SOLID=1
bit={band=function(a,b)return a==b and a or 0 end}
dofile('lua/pocketmap/cl_visibility.lua')
local V=PocketMap.Visibility
local pvs={[0]=true,[7]=true}
assert(V.Visible({0},pvs) and not V.Visible({1,2},pvs),'cluster zero or hidden face mishandled')
assert(V.Visible(nil,pvs) and V.Visible(false,pvs) and V.Visible({1},nil),'unknown VIS must remain visible')
assert(V.Key({7,0})==V.Key({0,7}),'membership ordering must not fragment equivalent batches')
local leaves={{cluster=-1,contents=1},{cluster=0},{cluster=7},{cluster=7}}
local boundsCalls=0
local bsp={AABBInLeafs=function(_,_,lo,hi)
	boundsCalls=boundsCalls+1
	assert(lo.x==100 and hi.x==5100 and hi.z==900,'must use transformed/displaced triangles, not base corners')
	return leaves
end}
local face={__id=12,IsWorld=function()return false end,
	GenerateVertexTriangleData=function()return {{pos=Vector(100,0,0)},{pos=Vector(5100,0,0)},{pos=Vector(100,10,900)}}end,
	ClearMeshData=function()end}
local mini={bsp=bsp,worldFaceClusters={}}
local linked=V.FaceClusters(mini,face)
assert(#linked==2 and V.Visible(linked,pvs),'large displacements/brushes must acquire conservative leaf membership')
assert(V.FaceClusters(mini,face)==linked and boundsCalls==1,'static membership must be cached in memory')
mini.worldFaceClusters[13]={1};mini.worldFaceClusters[14]={7,0}
local input={face,{__id=13},{__id=14},face}
local batches=V.FaceBatches(mini,input)
assert(#batches==3 and #batches[3]==2,'glass must split at visibility changes and merge equivalent consecutive memberships')
local n=0
for _,batch in ipairs(batches)do for _,f in ipairs(batch)do n=n+1 assert(f==input[n],'translucent face order changed')end end
leaves={{cluster=-1,contents=0},{cluster=7}}
mini.worldFaceClusters[12]=nil
assert(V.FaceClusters(mini,face)==nil and mini.worldFaceClusters[12]==false,'uncertain leaves must fail open')

local function loadFunction(path,name,nextMarker,env)
	local f=assert(io.open('lua/pocketmap/'..path,'r'));local src=f:read('*a');f:close()
	local first=assert(src:find('local function '..name..'(',1,true))
	local last=assert(src:find(nextMarker,first,true))
	local chunk=assert(loadstring(src:sub(first,last-1)..'\nreturn '..name))
	setfenv(chunk,setmetatable(env,{__index=_G}))return chunk()
end
local cacheVisible=loadFunction('cl_worldcache.lua','visible','local function compile',{})
assert(cacheVisible(face,{[12]={7}},pvs) and not cacheVisible(face,{[12]={1}},pvs),
	'brushes/displacements must receive the same per-face cache filtering as ordinary world faces')
local worldLinks=loadFunction('cl_loader.lua','worldFaceClusters','-- Keep all clusters',{})
local co=coroutine.create(function()return worldLinks({
	GetFaces=function()return {[12]=face,[15]={IsWorld=function()return true end}}end,
	GetLeafFaces=function()return {12,15}end,
	GetLeafs=function()return {{cluster=-1,contents=0,firstleafface=0,numleaffaces=2}}end})end)
local ok, links=coroutine.resume(co)
assert(ok,links)
assert(links[12]==nil and links[15]==false,'separate brush-model leaves must not poison world-space brush membership')

local frozen=pvs
local inside=false
mini.scale=1;mini.boxCenter=Vector();mini.mapCenter=Vector();mini.propGroups={{}}
mini.ent={WorldToLocal=function(_,v)return v end}
mini.EyeInside=function()return inside end
local walk={mini=mini,io={}}
PocketMap.Walk={session=walk};PocketMap.PVSFreeze={Get=function()return frozen end}
local water={};PocketMap.Water=water
local env={PocketMap=PocketMap,Water=water}
local world=loadFunction('cl_draw.lua','worldPVS','local function worldPartVisible',env)
local door=loadFunction('mapio/cl_doors.lua','doorPVS','local function inPVS',env)
local brush=loadFunction('mapio/cl_core.lua','drawPVS','-- A sphere',env)
local view={origin=Vector()}
assert(world(mini,view)==frozen and door(mini,view)==frozen and brush(mini,walk,view)==frozen,
	'frozen visibility must remain pinned after noclipping outside the miniature')
local selectedPVS
env.viewFrustum=function()return view end
env.passGroups=function(_,p)selectedPVS=p return {opaque={},translucent={}}end
env.propOcclusion=function()end
local props=loadFunction('cl_props.lua','drawPass','---@param pass',env)
props(mini,false)
assert(selectedPVS==frozen,'props must retain the frozen selection outside the miniature')
frozen=nil
assert(world(mini,view)==nil and door(mini,view)==nil and brush(mini,walk,view)==nil,
	'unfrozen exterior views must keep conservative visibility')
water.pass='reflection'
water.ReflectionPVS=function()return {[99]=true}end
frozen=pvs
assert(world(mini,view)[99] and door(mini,view)==nil and brush(mini,walk,view)==nil,
	'main-view freezing must not override the separate reflection visibility policy')
assert(world(mini,nil)[99],'reflection policy must not depend on the main frustum')
water.pass=nil
assert(world(mini,nil)==nil,'unknown cameras must remain conservative')
print('PASS PVS: receiver membership, large displacement/brush bounds, ordered glass batches, frozen exterior views and reflection isolation')

local command
Color=function()return {}end
chat={AddText=function()end}
concommand={Add=function(_,fn)command=fn end}
PocketMap.Hooks={Register=function()end}
PocketMap.Walk.EyeOffset=function()return Vector(3,0,42)end
walk.move={origin=Vector(100,0,0)}
mini.state='ready';mini.worldPVSBSP=bsp;mini.worldPVSCluster=7;mini.worldPVS=pvs
bsp.ClusterFromPoint=function(_,p)assert(p.x==103 and p.z==42,'freeze must use the actual animated eye offset')return 7 end
bsp.GetVisibility=function()return {VisData={[7]={PVS=0}}}end
bsp.IsVisibilityCorrupted=function()return false end
bsp.PVSForOrigin=function()error('freezing a warm cluster must reuse its compiled PVS')end
pvs.__map=bsp
dofile('lua/pocketmap/cl_pvs_freeze.lua')
command()
assert(PocketMap.PVSFreeze.state.pvs==pvs and PocketMap.PVSFreeze.state.clusters==2,
	'freeze must retain the warm PVS identity and count only numeric clusters')
assert(PocketMap.PVSFreeze.Get(mini)==pvs,'freeze must survive outside-map bounds')
mini.state='removed'
assert(PocketMap.PVSFreeze.Get(mini)==nil and PocketMap.PVSFreeze.state==nil,'removed miniatures must release frozen state')
print('PASS PVS freeze: rendered eye offset, warm cache reuse, accurate cluster count and lifecycle cleanup')

-- Detail sprites must follow their compiler-assigned leaves, including the
-- conservative fallback for a missing leaf, without losing any sprite quads.
function vec:SetUnpacked(x,y,z)self.x,self.y,self.z=x,y,z end
local noop=function()end
local draws=0
function Mesh()return {Draw=function()draws=draws+1 end}end
mesh={Begin=noop,Position=noop,TexCoord=noop,Color=noop,AdvanceVertex=noop,End=noop}
cam={PushModelMatrix=noop,PopModelMatrix=noop}
render={SetMaterial=noop}
function Material()return {IsError=function()return false end,GetTexture=function()end}end
NikNaks={DETAIL_PROP_TYPE={MODEL=0,SPRITE=1,SHAPE_TRI=2},MeshBuilder={BlendsWithBackground=function()return false end}}
MATERIAL_TRIANGLES=4
PocketMap.Mini={}
local sprite={ul={-1,1},lr={1,-1},texUL={0,0},texLR={1,1}}
local detailBSP={GetDetailPropInfo=function()return {count=3,sprites={[0]=sprite}}end,
	GetDetailMaterial=function()return 'grass'end,GetLeafs=function()return {[0]={cluster=1},[1]={cluster=2}}end,
	GetDetailProp=function(_,i)return {Type=1,Orientation=0,Index=0,Scale=1,Origin=Vector(i*100,0,0),
		Angles={y=0},Lighting={r=128,g=128,b=128,exponent=0},Leaf=i}end}
local detailMini={detailMeshes={},detailSprites=0,detailModels=0,matrix={}}
dofile('lua/pocketmap/cl_detail.lua')
local co=coroutine.create(function()PocketMap.Detail.Build(detailMini,{bsp=detailBSP})end)
repeat local ok,err=coroutine.resume(co)assert(ok,err)until coroutine.status(co)=='dead'
assert(detailMini.detailSprites==3 and #detailMini.detailMeshes==3,'detail visibility partition lost sprites')
PocketMap.Detail.Draw(detailMini,{[1]=true})
assert(draws==2,'detail sprites must filter by their assigned leaf and retain unknown leaves')
draws=0;PocketMap.Detail.Draw(detailMini,{[2]=true})
assert(draws==2,'detail PVS must update after changing clusters')
draws=0;PocketMap.Detail.Draw(detailMini)
assert(draws==3,'all details must remain visible when VIS is unavailable')
print('PASS detail sprites: compiled leaf membership, PVS changes and unknown-leaf fallback')
