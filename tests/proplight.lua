-- Run from the PocketMap root: lua tests/proplight.lua
local vec = {} vec.__index = vec
function Vector(x,y,z)
	if type(x) == 'table' then return Vector(x.x,x.y,x.z) end
	return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)
end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__unm(a)return a*-1 end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec.__div(a,b)return a*(1/b)end
function vec.__eq(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
function vec:Dot(b)return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:Length()return math.sqrt(self:Dot(self))end
function vec:GetNormalized()return self/self:Length()end
function vec:Rotate(a)
	local c,s=math.cos(math.rad(a.y)),math.sin(math.rad(a.y))
	self.x,self.y=c*self.x-s*self.y,s*self.x+c*self.y
end
function Angle(p,y,r)return {p=p or 0,y=y or 0,r=r or 0}end
function LocalToWorld(pos,_,origin,angles)local p=Vector(pos)p:Rotate(angles)return origin+p end
function math.Clamp(v,a,b)return math.max(a,math.min(b,v))end
bit={band=function(a,b)assert(b==1)return a%2 end}
local matrix={} matrix.__index=matrix
function Matrix()return setmetatable({pos=Vector(),angles=Angle(),scale=1},matrix)end
function matrix:GetTranslation()return self.pos end
function matrix:GetAngles()return self.angles end
function matrix:GetScale()return Vector(self.scale,self.scale,self.scale)end
function matrix:SetAngles(a)self.angles=a end
function matrix:Set(m)self.pos,self.angles,self.scale=m.pos,m.angles,m.scale end
function matrix:Invert()self.angles=Angle(0,-self.angles.y,0)end
function matrix.__mul(m,v)local p=Vector(v)*m.scale p:Rotate(m.angles)return p+m.pos end
local function close(a,b,message)assert(math.abs(a-b)<1e-7,(message or '')..': '..tostring(a)..' ~= '..tostring(b))end
local tick=0
PocketMap={Mini={},LightStyles={CurrentTick=function()return tick end,
	WeightAtTick=function(styles,style,t)return styles.animated[style] and t%2 or styles.weights[style] or 1 end}}
util={GetModelInfo=function()return {IllumPosition=Vector(14,0,1)}end}
dofile('lua/pocketmap/cl_proplight.lua')
local P=PocketMap.PropLight
local lights={}
local function source(kind,origin,intensity,options)
	local l={type=kind,origin=origin,intensity=intensity,normal=Vector(0,0,-1),style=0,
		radius=0,constant_attn=0,linear_attn=0,quadratic_attn=1,flags=0,
		stopdot=math.cos(math.rad(20)),stopdot2=math.cos(math.rad(40)),exponent=2}
	for k,v in pairs(options or {})do l[k]=v end
	lights[#lights+1]=l return l
end
local warm=source(1,Vector(0,0,56),Vector(1960,430,0))
local blocked=source(1,Vector(100,0,0),Vector(1e8,1e8,1e8))
local off=source(1,Vector(0,0,20),Vector(1e6,0,0),{style=32})
local baked=source(0,Vector(0,0,10),Vector(1e6,0,0),{flags=1})
source(1,Vector(0,0,1000),Vector(1e8,0,0),{radius=100})
local colors={}
for side=1,6 do colors[side]={r=side*0.00001,g=0,b=0} end
local sampled
local leaf={GetAmbientLighting=function()return {true}end,GetIndex=function()return 1 end,
	CalculateAmbientCube=function(_,at)sampled=at return colors end}
local bsp={GetWorldLights=function()return lights end,GetWorldLightsHDR=function()return {} end,
	PointInLeaf=function()return leaf end,SurfaceTraceLine=function(_,_,target)return {Hit=target==blocked.origin}end}
local styles={weights={[32]=0},animated={}}
local mini={lighting='LDR',lightStyleWeights=styles.weights,lightStyles=styles}
local sampler=P.New(mini,bsp,true)
local lit=sampler:Of({Origin=Vector()})
assert(#lit.direct==1 and lit.direct[1]==warm,'blocked/off/baked/out-of-range lights reached prop')
close(lit[1][1],0.00001,'dark ambient was brightened')
assert(lit[1][2]==0 and lit[1][3]==0,'black ambient became gray')
local pos=sampler:Position({Origin=Vector(1,2,3),Angles=Angle(0,90),UniformScale=2},'model')
close(pos.x,1)close(pos.y,30)close(pos.z,5)
assert(sampler:Position({Origin=Vector(),LightOrigin=pos},'model')==pos,'explicit lighting origin ignored')

-- Reproduce the public API's 100-unit normalization and the shader's final
-- irradiance. It must equal native lighting at multiple miniature scales.
for _,scale in ipairs({0.001,0.01462155,0.1,1,2})do
	local m=Matrix()m.pos=Vector(120,-30,45)m.angles=Angle(0,90)m.scale=scale
	local transform=P.Transform(m)
	local rendered=P.ForRender(lit,transform)
	local l=rendered.direct[1]
	local sample=m*Vector()
	local d=(l.pos-sample):Length()
	local norm=l.constantFalloff+100*l.linearFalloff+10000*l.quadraticFalloff
	local attenuation=l.constantFalloff+l.linearFalloff*d+l.quadraticFalloff*d*d
	close(l.color.x*norm/attenuation,1960/56^2,'red irradiance changed with scale')
	close(l.color.y*norm/attenuation,430/56^2,'green irradiance changed with scale')
	close(rendered.cube[1][1],lit[4][1],'ambient cube did not rotate with block')
	assert(P.ForRender(lit,transform)==rendered,'unchanged render lighting was not cached')
end

-- Skylight must be blocked by roofs, use a directional shader light, and
-- point towards the sun after the block rotates. Spots retain native cones.
lights={}
local sun=source(3,Vector(),Vector(1,.8,.5),{normal=Vector(1,0,-1):GetNormalized()})
local spot=source(2,Vector(0,0,100),Vector(100,80,40))
local pulse=source(1,Vector(0,0,50),Vector(100,50,10),{style=1})
styles.animated[1]=true
sampler=P.New(mini,bsp,true)
lit=sampler:Of({Origin=Vector()})
assert(#lit.direct==3,'sun/spot/animated light was dropped')
local m=Matrix()m.angles=Angle(0,90)m.scale=.01
local transform=P.Transform(m)
local first=P.ForRender(lit,transform)
for _,l in ipairs(first.direct)do
	if l.type==2 then
		close(l.dir.y,1/math.sqrt(2))close(l.dir.z,-1/math.sqrt(2))
		assert(-l.dir:Dot(Vector(0,0,1))>0,'sun points away from upward-facing surfaces in the model shader')
	end
	if l.type==3 then close(l.innerAngle,20)close(l.outerAngle,40)close(l.angularFalloff,2)end
end
tick=1
local second=P.ForRender(lit,transform)
assert(first~=second and first.cube==second.cube,'style animation rebuilt static ambient or failed to update')
local changed=false
for i,l in ipairs(first.direct)do if second.direct[i].color.x~=l.color.x then changed=true end end
assert(changed,'animated direct light did not animate')
local beforeReload=P.ForRender(lit,transform)
dofile('lua/pocketmap/cl_proplight.lua')
local afterReload=PocketMap.PropLight.ForRender(lit,transform)
assert(afterReload~=beforeReload and afterReload.system==PocketMap.PropLight,
	'hot reload retained stale light directions in an existing miniature')
bsp.SurfaceTraceLine=function()return {Hit=true,HitSky=false}end
assert(#sampler:Of({Origin=Vector()}).direct==0,'roof or walls failed to block light')
bsp.SurfaceTraceLine=function()return {Hit=true,HitSky=true}end
assert(#sampler:Of({Origin=Vector()}).direct==1,'sky trace did not admit only skylight')
local Current=PocketMap.PropLight
local empty={mini=mini,direct={}}
local other={mini=mini,direct={}}
for side=1,6 do empty[side]={.2,.4,.6};other[side]={.2,.4,.6}end
local a=Current.ForRender(empty,transform)
tick=tick+1
local b=Current.ForRender(empty,transform)
assert(a==b,'empty direct lighting must not invalidate at the lightstyle clock')
assert(Current.ForRender(other,transform).direct==a.direct,'empty native light state must be shared between props')
local directional=false
PocketMap.Settings={Enabled=function(_,key)return key~='directional_prop_ambient' or directional end}
local flat=Current.ForRender(empty,transform)
assert(flat.uniform and flat.cube[1]==flat.cube[6],'averaged ambient must use one local color')
close(flat.uniform[1],.2)close(flat.uniform[2],.4)close(flat.uniform[3],.6)
local f=assert(io.open('lua/pocketmap/cl_props.lua','r'));local src=f:read('*a');f:close()
local first=assert(src:find('local function setModelLight(',1,true))
local last=assert(src:find('local function drawParts(',first,true))
local chunk=assert(loadstring(src:sub(first,last-1)..' return setModelLight'))
local clears,resets,sides=0,0,0
local env=setmetatable({PocketMap=PocketMap,SIDES=6,Props={},render={
	SetLocalModelLights=function()clears=clears+1 end,
	ResetModelLighting=function()resets=resets+1 end,
	SetModelLighting=function()sides=sides+1 end}},{__index=_G})
setfenv(chunk,env)local bind=chunk()
local state={}
bind(state,empty,transform)bind(state,other,transform)
assert(clears==1 and resets==1 and sides==0,'identical flat-lit props must share one light clear and one ambient update')
directional=true
bind(state,empty,transform)
assert(not state.uniform,'switching back to directional ambient must restore per-side lighting state')
local blockedCalls,fullCalls=0,0
bsp.SurfaceTraceBlocked=function() blockedCalls=blockedCalls+1 return true end
bsp.SurfaceTraceLine=function() fullCalls=fullCalls+1 return {Hit=true,HitSky=true} end
local direct=sampler:DirectLights(Vector())
assert(#direct==1 and direct[1]==sun,'fast occlusion admitted blocked lights or lost sunlight')
assert(blockedCalls==2 and fullCalls==1,'non-sun lights must use boolean occlusion; sunlight must use the sky-aware trace')
bsp.SurfaceTraceBlocked=function() return false end
bsp.SurfaceTraceLine=function() return {Hit=true,HitSky=false} end
assert(#sampler:DirectLights(Vector())==2,'unblocked point/spot lights were dropped or roof admitted sunlight')
bsp.SurfaceTraceBlocked=nil
assert(#sampler:DirectLights(Vector())==0,'older NikNaks fallback did not retain full-trace occlusion')

-- A stored ZIP containing one VHV from each lighting variant. LOD 1 is
-- saturated green, so an accidental cross-LOD average is visible here.
local function le(n,count)
	local bytes={}
	for i=1,count or 4 do bytes[i]=string.char(n%256) n=math.floor(n/256) end
	return table.concat(bytes)
end
local function vhv(r,b)
	local function group(lod,offset)
		return le(lod)..le(1)..le(offset)..string.rep("\0",16)
	end
	return le(2)..le(123)..le(4)..le(4)..le(2)..le(2)..string.rep("\0",16)
		..group(1,96)..group(0,100)..string.char(0,255,0,255,b,0,r,255)
end
local function zip(entries)
	local locals,central={},{}
	local offset,size=0,0
	for _,entry in ipairs(entries) do
		local name,data=entry[1],entry[2]
		local sizes=le(7)..le(#data)..le(#data)..le(#name,2)
		local localRecord="PK\3\4"..le(20,2)..string.rep("\0",8)..sizes..le(0,2)..name..data
		local directory="PK\1\2"..le(20,2)..le(20,2)..string.rep("\0",8)..sizes..string.rep("\0",12)..le(offset)..name
		locals[#locals+1],central[#central+1]=localRecord,directory
		offset,size=offset+#localRecord,size+#directory
	end
	return table.concat(locals)..table.concat(central).."PK\5\6"..le(0)..le(#entries,2)..le(#entries,2)..le(size)..le(offset)..le(0,2)
end
util.CRC=function()return "7" end
local archive=zip({{"sp_0.vhv",vhv(96,0)},{"sp_hdr_0.vhv",vhv(0,50)}})
bsp.GetLumpString=function(_,lump)assert(lump==40)return archive end
dofile("lua/pocketmap/cl_pak.lua")
local vertexLights=PocketMap.Pak.StaticPropLights(bsp,false,{[0]={}})
local hdrLights=PocketMap.Pak.StaticPropLights(bsp,true,{[0]={}})
close(vertexLights[0].color[1],(192/255)^2.2,"baked sRGB brightness or strip-group LOD")
close(vertexLights[0].color[2],0)
close(hdrLights[0].color[3],(100/255)^2.2,"HDR must use its own packed static-prop lighting")
file={Open=function(path)return {Seek=function(_,offset)assert(offset==8)end,
	ReadULong=function()return path=="model" and 123 or 456 end,Close=function()end}end}
local static=Current.New(mini,bsp,true,vertexLights)
local authored=Current.ForRender(static:Of({Origin=Vector(),StaticIndex=0},"model"),transform)
assert(authored.uniform==vertexLights[0].color and #authored.direct==0,"baked lighting must replace the approximate direct lights")
assert(not static:Of({Origin=Vector(),StaticIndex=1},"model").baked,"unbaked props must retain sampled lighting")
assert(not static:Of({Origin=Vector(),StaticIndex=0},"different-model").baked,"mismatched model accepted another prop's lighting")
print('Prop lighting: native lights, animation, shared render states and packed static-prop lighting passed')
