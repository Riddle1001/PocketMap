-- Run from PocketMap: lua tests/render_assets.lua
local vec = {} vec.__index = vec
function Vector(x, y, z)
	if type(x) == "table" then return Vector(x.x, x.y, x.z) end
	return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vec)
end
function vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vec.__unm(a) return Vector(-a.x,-a.y,-a.z) end
function vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vec.__div(a,b) return a*(1/b) end
function vec:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:Cross(b) return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function vec:GetNormalized() return self/math.sqrt(self:Dot(self)) end
function vec:DistToSqr(b) return (self-b):Dot(self-b) end
function isvector(value)return getmetatable(value)==vec end
function ismatrix()return false end
local function close(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." != "..tostring(b)) end
local noop = function() end
local material = {GetName=function()return "test/decal"end,IsError=function()return false end,
	GetInt=function()return 0 end,GetFloat=function()return 1 end,
	Width=function()return 32 end,Height=function()return 32 end}
local loaded
function Material(name) loaded=name return material end
file = {Exists=function(path) return path == "materials/test/floor.vmt" end}
PocketMap = {Mini = {}, MapIO = {Register=noop, Value=function(e,k)return e[k]end, Vector=function(v)return v end},
	Entities={Class=function(e)return e.classname end,Name=function(e)return e.targetname end}}
dofile("lua/pocketmap/cl_materials.lua")
assert(PocketMap.Materials.Load("/TEST\\FLOOR.vmt") == material and loaded == "test/floor")
assert(PocketMap.Materials.Load("materials/test/floor") == material and loaded == "test/floor")
local legacyPath = "customs/fr" .. string.char(220) .. "chte/jackfrucht"
assert(not file.Exists("materials/" .. legacyPath .. ".vmt", "GAME"))
assert(PocketMap.Materials.Load(legacyPath) == material and loaded == legacyPath,
	"the engine must get the original path bytes for a packed legacy material")
assert(PocketMap.Materials.Load("test/missing") == material and loaded == "___error",
	"ASCII files rejected by the file API must retain the normal error fallback")
print("PASS material names: normalized ASCII paths and engine-only legacy paths")

local normal = Vector(0,0,1)
local function vertex(x,y) return {pos=Vector(x,y,0),normal=normal,u=x,v=y,u1=(x+64)/128,v1=(y+64)/128} end
local triangles = {vertex(-64,-64),vertex(64,-64),vertex(64,64),vertex(-64,-64),vertex(64,64),vertex(-64,64)}
local built, current, v = {}, nil, nil
function Mesh() local m={Draw=noop,Destroy=noop} built[#built+1]=m return m end
mesh = {Begin=function(m)current=m m.vertices={} end, End=noop,
	Position=function(p)v=v or{} v.pos=p end,Normal=function(n)v=v or{} v.normal=n end,
	TangentS=function(t)v=v or{} v.tangent=t end,TangentT=function(t)v=v or{} v.binormal=t end,
	TexCoord=function(stage,u,w)v=v or{}v["u"..stage],v["v"..stage]=u,w end,
	Color=noop,AdvanceVertex=function()current.vertices[#current.vertices+1]=v v=nil end}
bit = {band=function()return 0 end}
MATERIAL_TRIANGLES = 4
NikNaks = {MeshBuilder={BlendsWithBackground=function()return false end}}
util = {GetModelMeshes=function(path,lod,body,skin)
	assert(path == "model" and body == 0 and skin == 3,"mesh extraction discarded skin family")
	return {{triangles=triangles,material="skin3"}}
end}
dofile("lua/pocketmap/cl_propmesh.lua")
local parts = PocketMap.PropMesh.Build("model",3)
assert(parts and #parts[1].mesh.vertices == 6)
for _,p in ipairs(parts[1].mesh.vertices) do
	assert(p.tangent and p.binormal,"normal-mapped model lost tangent frame")
	close(p.tangent:Dot(p.normal),0) close(p.binormal:Dot(p.normal),0)
end
print("PASS model meshes: skin family and tangent frames")

PocketMap.Materials.Load=function()return material end
local face = {plane={normal=normal},ShouldRender=function()return true end,GetNormal=function()return normal end,
	IsSkyBox=function()return false end,IsSkyBox3D=function()return false end,
	GenerateVertexTriangleData=function()return triangles end,ClearMeshData=noop}
local leaf = {area=0,GetFaces=function()return {face} end}
local overlay={uvPoints={Vector(-8,-8,1),Vector(-8,8,0),Vector(8,8,0),Vector(8,-8,0)},
	basisNormal=normal,origin=Vector(),uMin=0,uMax=1,vMin=0,vMax=1,renderOrder=0,
	GetFaces=function()return {face}end,GetTexInfo=function()return {texdata=0}end}
local bsp = {SurfaceTraceLine=function()return {Hit=true,Face=face,HitPos=Vector(),HitNormal=normal}end,
	AABBInLeafs=function()return {leaf}end,PointInLeaf=function()return leaf end,
	GetOverlays=function()return {overlay}end,GetTexData=function()return {[0]={nameStringTableID="overlay"}}end}
local atlas={}
local mini={matrix={},lightmapTexture=atlas,mapIO={byEntity={}},worldLightUV=function(_,vertices)
	local us,vs={},{} for i,p in ipairs(vertices)do us[i],vs[i]=p.u1,p.v1 end return us,vs
end}
face.__id=1
local otherFace=setmetatable({__id=2,GenerateVertexTriangleData=function()
	local shifted={}
	for _,v in ipairs(triangles)do
		shifted[#shifted+1]={pos=v.pos+Vector(4,0,0),normal=v.normal,u=v.u,v=v.v,u1=v.u1+4/128,v1=v.v1}
	end
	return shifted
end},{__index=face})
overlay.GetFaces=function()return {face,otherFace}end
mini.bsp=bsp;mini.worldFaceClusters={[1]={1},[2]={2}}
dofile("lua/pocketmap/cl_visibility.lua")
dofile("lua/pocketmap/cl_decals.lua")
local co=coroutine.create(function()PocketMap.Decals.Build(mini,{bsp=bsp,skyArea=2,
	entities={{classname="infodecal",origin=Vector(),texture="decal"}}})end)
repeat local ok,err=coroutine.resume(co) assert(ok,err) until coroutine.status(co)=="dead"
assert(#mini.decals==2,"decal or BSP overlay was omitted")
for _,group in ipairs(mini.decals)do
	assert(#group.meshes>0,"projection produced no geometry")
	for _,m in ipairs(group.meshes)do for _,p in ipairs(m.vertices)do
		assert(p.u0>=-1e-6 and p.u0<=1+1e-6 and p.v0>=-1e-6 and p.v0<=1+1e-6,"decal spilled outside receiver footprint")
		close(p.u1,(p.pos.x+64)/128) close(p.v1,(p.pos.y+64)/128)
	end end
end
local stack=0
cam={PushModelMatrix=function()stack=stack+1 end,PopModelMatrix=function()stack=stack-1 end}
local depthMax=1
render={SetLightmapTexture=function(t)assert(t==atlas,"nil/incorrect lightmap bound")end,
	OverrideDepthEnable=noop,SetMaterial=noop,DepthRange=function(first,last)
		assert(first==0,"overlay bias changed the near depth endpoint")
		depthMax=last
	end}
PocketMap.Decals.Draw(mini)
assert(stack==0 and depthMax==1,"overlay draw left render state changed")
local draws=0
for _,group in ipairs(mini.decals)do for _,m in ipairs(group.meshes)do m.Draw=function()
	assert(depthMax<1 and depthMax>0.9999,"overlay did not get a bounded depth bias")
	draws=draws+1
end end end
PocketMap.Decals.Draw(mini,nil,{[1]=true})
assert(draws==2,'visible decal/overlay receivers must remain visible')
draws=0;PocketMap.Decals.Draw(mini,nil,{[2]=true})
assert(draws==1,'an overlay must be filtered per receiver, even when both receivers share its material and origin')
draws=0;PocketMap.Decals.Draw(mini,nil,{[3]=true})
assert(draws==0,'hidden receivers must not leave floating decals')
draws=0;PocketMap.Decals.Draw(mini)
assert(draws==3,'exterior/no-VIS view must still draw all decal receivers')
mini.decals[1].meshes[1].Draw=function()error("draw failed")end
assert(not pcall(PocketMap.Decals.Draw,mini) and depthMax==1 and stack==0,
	"failed decal draw leaked the depth bias or matrix")
mini.lightmapTexture=nil
PocketMap.Decals.Draw(mini)
assert(stack==0,"loading-state decal draw changed render state")
print("PASS decal projection: clipping, receiver lightmaps, per-receiver PVS, exterior views and loading guards")

-- Build real water meshes and drive the refraction draw with a strict render
-- contract, including state restoration if an underwater mesh throws.
function CreateClientConVar()return {GetBool=function()return true end,GetInt=function()return 1 end}end
function istable(v)return type(v)=="table"end
file.Read=function()end
local waterHook
PocketMap.Hooks={Register=function(_,_,fn)waterHook=fn end}
PocketMap.RT={Acquire=function()return {}end,Clear=noop,Release=noop}
local sourceMatrix={}
function Matrix()return sourceMatrix end
dofile("lua/pocketmap/cl_water.lua")
local floats={['$fogstart']=8,['$fogend']=128}
local originalReflect,originalRefract={IsError=function()return false end},{IsError=function()return false end}
local textures={['$reflecttexture']=originalReflect,['$refracttexture']=originalRefract}
local waterMaterial={GetShader=function()return 'Water'end,IsError=function()return false end,
	GetName=function()return 'water'end,GetFloat=function(_,key)return floats[key]end,
	SetFloat=function(_,key,value)floats[key]=value end,GetString=function()return '{10 20 30}'end,
	GetTexture=function(_,key)return textures[key]end,SetTexture=function(_,key,value)textures[key]=value end,
	GetInt=function()return 0 end,SetInt=noop}
waterMaterial.GetKeyValues=function()return {['$forcecheap']=0,['$forceexpensive']=1,
	['$reflecttexture']=originalReflect,['$refracttexture']=originalRefract,
	['$fogstart']=8,['$fogend']=128,['$normalmap']='water/normal'}end
util.CRC=function(v)return v end
function CreateMaterial(name,shader,values)
	assert(shader=='Water' and values['$forcecheap']==0 and values['$forceexpensive']==1,
		'water clone compiled the cheap shader snapshot')
	local ts={['$reflecttexture']=originalReflect,['$refracttexture']=originalRefract}
	return {GetName=function()return name end,GetShader=function()return shader end,
		GetFloat=function(_,k)return values[k]end,SetFloat=function(_,k,v)values[k]=v end,
		GetInt=function(_,k)return values[k]end,SetInt=function(_,k,v)values[k]=v end,
		GetTexture=function(_,k)return ts[k]end,SetTexture=function(_,k,v)ts[k]=v end,
		Recompute=noop}
end
face.IsDisplacement=function()return false end
face.GetVertexs=function()return {Vector(-64,-64,0),Vector(64,-64,0),Vector(64,64,0)}end
leaf.cluster,leaf.contents=1,0
local waterMini={scale=.01,matrix={},bsp=bsp,ent={}}
local W=PocketMap.Water
co=coroutine.create(function()W.Build(waterMini,'water',waterMaterial,{face})end)
repeat local ok,err=coroutine.resume(co)assert(ok,err)until coroutine.status(co)=='dead'
local plane=waterMini.waterPlanes[1]
assert(plane.uvScale==1)
for i,p in ipairs(plane.meshes[1].vertices)do close(p.u0,triangles[i].u)close(p.v0,triangles[i].v)end
plane.meshes[1].Draw=function()
	assert(plane.material~=waterMaterial,'water renderer changed the native map material')
	assert(plane.material:GetTexture('$refracttexture')==plane.refractRT and plane.material:GetTexture('$reflecttexture')==plane.reflectRT)
	assert(plane.material:GetInt('$forcecheap')==0 and plane.material:GetInt('$forceexpensive')==1)
	close(plane.material:GetFloat('$fogstart'),.08)close(plane.material:GetFloat('$fogend'),1.28)
end
W.Draw(waterMini)
assert(textures['$refracttexture']==originalRefract and textures['$reflecttexture']==originalReflect)
assert(floats['$fogstart']==8 and floats['$fogend']==128 and stack==0)

local inSource, fogScale=false,.01
local function beginSource(m)
	assert(m==waterMini and not inSource)
	inSource,fogScale=true,1
	return true,.01
end
cam.End3D=function()assert(inSource)inSource=false end
PocketMap.Fog={SetScale=function(value)fogScale=value end}
local pushMatrix=cam.PushModelMatrix
cam.PushModelMatrix=function(m)
	assert(inSource and m==sourceMatrix,'source water was drawn with the miniature transform')
	pushMatrix(m)
end
local failWater=false
plane.meshes[1].Draw=function()
	close(plane.material:GetFloat('$fogstart'),8)close(plane.material:GetFloat('$fogend'),128)
	assert(plane.material:GetTexture('$refracttexture')==plane.refractRT)
	if failWater then error('water mesh failure fixture') end
end
W.Draw(waterMini,beginSource)
assert(not inSource and fogScale==.01 and stack==0,'source water leaked camera or fog state')
failWater=true
assert(not pcall(W.Draw,waterMini,beginSource),'water mesh failure was swallowed')
assert(not inSource and fogScale==.01 and stack==0,'failed source water leaked camera or fog state')
close(plane.material:GetFloat('$fogstart'),.08)close(plane.material:GetFloat('$fogend'),1.28)
cam.PushModelMatrix=pushMatrix
PocketMap.Fog=nil

local function findFunction(fn,name,visited)
	visited=visited or {}
	if visited[fn]then return end visited[fn]=true
	for i=1,100 do
		local key,value=debug.getupvalue(fn,i)if not key then break end
		if key==name then return value end
		if type(value)=='function'then local result=findFunction(value,name,visited)if result then return result end end
	end
end
local refract=findFunction(waterHook,'renderRefraction')
assert(refract,'water hook no longer renders refraction')
local fog={mode=0,first=3,last=9,z=2,density=.6,r=1,g=2,b=3}
render.GetFogMode=function()return fog.mode end
render.GetFogDistances=function()return fog.first,fog.last,fog.z end
render.GetFogColor=function()return fog.r,fog.g,fog.b end
render.GetFogMaxDensity=function()return fog.density end
render.FogMode=function(v)fog.mode=v end
render.FogStart=function(v)fog.first=v end
render.FogEnd=function(v)fog.last=v end
render.SetFogZ=function(v)fog.z=v end
render.FogMaxDensity=function(v)fog.density=v end
render.FogColor=function(r,g,b)fog.r,fog.g,fog.b=r,g,b end
local targets,clipping,cameras,writeAlpha=0,0,0,true
render.SetWriteDepthToDestAlpha=function(v)writeAlpha=v end
render.PushRenderTarget=function()targets=targets+1 end
render.PopRenderTarget=function()targets=targets-1 end
render.Clear=noop
render.EnableClipping=function(v)local old=clipping clipping=v return old end
render.PushCustomClipPlane=noop render.PopCustomClipPlane=noop
cam.Start3D=function()cameras=cameras+1 end cam.End3D=function()cameras=cameras-1 end
MATERIAL_FOG_LINEAR_BELOW_FOG_Z=2
waterMini.WaterDrawOptions=function()return {}end
local fail=false
waterMini.DrawScene=function()
	assert(W.pass=='refraction' and not writeAlpha and fog.mode==2 and fog.z==5)
	close(fog.first,.08)close(fog.last,1.28)
	if fail then error('underwater draw failure')end
end
local view={origin=Vector(0,0,10),angles={},fov=90,znear=.1,zfar=100}
for _,failure in ipairs({false,true})do
	fail=failure
	local ok=pcall(refract,waterMini,plane,5,view)
	assert(ok~=fail and targets==0 and cameras==0 and clipping==0 and writeAlpha)
	assert(fog.mode==0 and fog.first==3 and fog.last==9 and fog.z==2 and fog.density==.6 and fog.r==1)
end
fail=false
local pushed
render.PushCustomClipPlane=function(normal,distance)pushed={normal=normal,distance=distance}end
local tilted={normal=Vector(.6,0,.8),distance=12,localHeight=3}
waterMini.DrawScene=function()
	local clip=W.ClipPlane(waterMini)
	assert(not pushed,'refraction must keep the shoreline triangles intact')
	close(clip.distance,-3.12)
	assert(clip.normal.z==-1,'refraction must still cull parts above the tilted water plane')
end
refract(waterMini,plane,5,view,{surface=tilted})
function Angle(p,y,r)return {p=p,y=y,r=r}end
view.angles=Angle(0,10,0)
local reflect=findFunction(waterHook,'renderReflection')
waterMini.DrawScene=function()
	assert(W.pass=='reflection' and pushed and pushed.normal.z==1 and pushed.distance==5 and clipping,
		'world reflections must still clip triangles below the surface')
end
reflect(waterMini,plane,5,view)
assert(clipping==0 and targets==0 and cameras==0,'reflection leaked clipping or camera state')
local acquire=findFunction(waterHook,'acquireHeightTargets')
local release=findFunction(waterHook,'releaseHeightTargets')
local alloc, freed = {}, {}
PocketMap.Settings={Enabled=function()return false end}
PocketMap.RT.Acquire=function(w,h,spec)
	local target={w=w,h=h,depth=spec.depth}
	alloc[#alloc+1]=target
	return target
end
PocketMap.RT.Release=function(target)if target then freed[#freed+1]=target end end
function ScrW()return 1600 end
function ScrH()return 900 end
local entry={reflection=true,refraction=false,skyOnly=true,sky2D=true,sky3D=false,rec={planes={plane}}}
assert(acquire(entry.rec,waterMini,entry) and #alloc==1
	and alloc[1].w==455 and alloc[1].h==256 and alloc[1].depth==false,
	'sky-only water must allocate one color target at the viewport aspect ratio')
assert(plane.reflectRT~=alloc[1],'a receiver sampled a target before it was rendered')
local skyDraws=0
PocketMap.Sky={DrawCube=function()skyDraws=skyDraws+1 end}
waterMini.DrawScene=function()error('sky-only reflection drew the map')end
render.ClearDepth=function()error('sky-only 2D reflection touched the depth buffer')end
reflect(waterMini,plane,5,view,entry)
assert(skyDraws==1 and targets==0 and cameras==0)
release(entry.rec)
assert(#freed==1 and plane.reflectRT==plane.flat.reflect,'releasing an effect must restore the receiver input')
entry.reflection,entry.refraction,entry.skyOnly=false,true,false
assert(acquire(entry.rec,waterMini,entry) and #alloc==2 and alloc[2].depth
	and entry.rec.reflect==nil and entry.rec.refract==alloc[2],
	'refraction-only water must allocate one depth target')
release(entry.rec)
W.pass=nil
print('PASS water: native UVs, scoped fog and clipping, sky-only rendering and per-pass targets')
