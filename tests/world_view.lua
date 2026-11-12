-- Run from the PocketMap root: lua tests/world_view.lua
local vec={}vec.__index=vec
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__div(a,b)return Vector(a.x/b,a.y/b,a.z/b)end
function vec:Dot(b)return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:DistToSqr(b)local d=self-b return d:Dot(d)end
local angle={}
function angle:Forward()return Vector(1,0,0)end
function angle:Right()return Vector(0,-1,0)end
function angle:Up()return Vector(0,0,1)end
local eye=Vector(101,202,303)
function EyePos()return eye end
function EyeAngles()return angle end
function Matrix()return {source=true}end
function CreateClientConVar()return {GetBool=function()return false end}end
local noop=function()end
local Mini={}
PocketMap={Mini=Mini,Water={Draw=noop},Sky={},Detail={Blends=function()return false end,Draw=noop},
	Props={Draw=noop},Effects={Draw=noop},MapIO={Draw=noop},PVSFreeze={Get=noop},Materials={}}
function PocketMap.Materials.ForScale(material)return material end
function PocketMap.Materials.DrawOptions(options)return options end
local source,matrices,draws,flashlight,writing,alphaWriting,fail=false,{},{},false,true,true,false
local range={0,1}
local camera={origin=eye,angles=angle,fov=106,width=1600,height=900,x=0,y=0,znear=.07,zfar=10000}
render={GetRenderTarget=noop,GetViewSetup=function()return camera end,SetLightmapTexture=noop,SetMaterial=noop,
	OverrideDepthEnable=noop,SetStencilEnable=noop,
	DepthRange=function(a,b)range={a,b}end,
	OverrideColorWriteEnable=function(on,value)writing=not on or value end,
	OverrideAlphaWriteEnable=function(on,value)alphaWriting=not on or value end,
	RenderFlashlights=function(fn)flashlight=true fn()flashlight=false end}
local cameraArgs
cam={Start3D=function(...)
	assert(not source,'nested source camera')source=true cameraArgs={...}
end,End3D=function()assert(source)source=false end,
	PushModelMatrix=function(m)matrices[#matrices+1]=m end,
	PopModelMatrix=function()assert(#matrices>0)matrices[#matrices]=nil end}
local mini={state='ready',scale=.01,scaleVec=Vector(.01,.01,.01),matrix={},mapCenter=Vector(1000,0,0),boxCenter=Vector(),
	lightmapTexture={},propGroups={},detailMeshes={},skyObjects={}}
mini.ent={WorldToLocal=function(_,p)return p-Vector(100,200,300)end,WorldToLocalAngles=function(_,a)return a end}
function mini:UpdateMatrix()end
function mini:EyeInside()return true end
local part={material={},mesh={Draw=function()
	if fail then error('draw failure fixture')end
	draws[#draws+1]={source=source,matrix=matrices[#matrices],flash=flashlight,color=writing,alpha=alphaWriting}
end}}
mini.objects={true,opaqueMeshes={part},translucentMeshes={}}
setmetatable(mini,{__index=Mini})
PocketMap.Walk={session={mini=mini}}
dofile('lua/pocketmap/cl_draw.lua')
mini:Draw('opaque')
assert(#draws==3,'world color, depth or flashlight pass was skipped')
assert(draws[1].source and draws[1].color,'world reflections did not use source coordinates')
assert(not draws[2].source and not draws[2].color and not draws[2].alpha and draws[2].matrix==mini.matrix,'depth was not restored in the flashlight coordinate space')
assert(draws[3].flash and not draws[3].source and draws[3].color and draws[3].matrix==mini.matrix,'flashlight receiver lost its original projection')
assert(cameraArgs[1].x==1100 and cameraArgs[1].y==200 and cameraArgs[1].z==300,'source camera origin drifted')
assert(cameraArgs[3]==106 and math.abs(cameraArgs[8]-7)<1e-7 and cameraArgs[9]==1000000,'source camera changed projection')
assert(not source and #matrices==0 and range[1]==0 and range[2]==1 and writing and alphaWriting,'draw leaked render state')
fail=true
local ok=pcall(Mini.Draw,mini,'opaque')
assert(not ok and not source and #matrices==0 and range[1]==0 and range[2]==1,'failed mesh leaked its camera or depth range')
print('world view: source reflections, shared flashlight depth, projection and error cleanup passed')
