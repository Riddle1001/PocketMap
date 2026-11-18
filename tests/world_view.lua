-- Run from the PocketMap root: lua tests/world_view.lua
local vec={}vec.__index=vec
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__div(a,b)return Vector(a.x/b,a.y/b,a.z/b)end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec:Dot(b)return self.x*b.x+self.y*b.y+self.z*b.z end
function vec:DistToSqr(b)local d=self-b return d:Dot(d)end
function vec:Normalize()local n=math.sqrt(self:Dot(self));self.x,self.y,self.z=self.x/n,self.y/n,self.z/n end
function Angle(p,y,r)return {p=p,y=y,r=r}end
function FrameNumber()return 1 end
local angle={}
function angle:Forward()return Vector(1,0,0)end
function angle:Right()return Vector(0,-1,0)end
function angle:Up()return Vector(0,0,1)end
local eye=Vector(101,202,303)
function EyePos()return eye end
function EyeAngles()return angle end
function Matrix()return {source=true}end
function CreateMaterial()return {}end
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
dofile('lua/pocketmap/cl_visibility.lua')
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
fail=false
local owned=camera
PocketMap.Scene={View=function(m)if m==mini then return owned end end}
mini.skyObjects={true};mini.skyBackdrop={}
local skyDraws=0
PocketMap.Sky.Draw3D=function(m,_,wholeView)
    assert(m==mini and wholeView,'the owned view must draw the whole 3D sky without a block stencil')
    skyDraws=skyDraws+1
end
PocketMap.Sky.DrawBackdrop=function()error('owned view tried to mask its already drawn sky')end
eye=Vector(999,888,777)
mini:Draw()
assert(skyDraws==1 and cameraArgs[1].x==1100 and cameraArgs[1].y==200,
    'owned source view inherited stale engine eye coordinates')
mini:Draw('translucent')
assert(skyDraws==1,'transparency redrew the sky and cleared the opaque scene depth')
PocketMap.Flashlight={IsOn=function()return true end}
assert(mini:RequiresEngineView()=='flashlight','projected shadows require the native view')
PocketMap.Flashlight.IsOn=function()return false end
PocketMap.Effects.RequiresEngineView=function(m,_,view)
    assert(m==mini and view.origin.x==1 and view.origin.y==2,'glow eligibility ignored the owned camera')
    return true
end
assert(mini:RequiresEngineView()=='glow')
local quality={world_source_camera=true,world_depth_repair=false}
PocketMap.Settings={Enabled=function(_,key)return quality[key]~=false end,
    MinimalPreview=function(m)return quality.minimal_preview==true and not m:EyeInside()end,
    Compat=function(_,_,cv)return cv:GetBool()end}
local flashDraw=render.RenderFlashlights
render.RenderFlashlights=function()end
local worldProjection
local worldMeshDraw=part.mesh.Draw
part.mesh.Draw=function()
	if source then worldProjection=cameraArgs end
	worldMeshDraw()
end
local waterSource
PocketMap.Water.Draw=function(m,beginSource)
	waterSource=beginSource~=nil
	if not beginSource then return end
	assert(beginSource(m),'water could not enter the world projection')
	assert(cameraArgs[1]:DistToSqr(worldProjection[1])==0,'water camera origin differs from the world')
	for i=2,9 do assert(cameraArgs[i]==worldProjection[i],'water projection differs from the world') end
	cam.End3D()
end
draws={}
mini:Draw('opaque')
assert(#draws==1 and draws[1].source and draws[1].color,'ordinary source world must not redraw depth when alignment is deferred')
assert(waterSource,'water must use the source camera after drawing the opaque source world')
assert(range[1]==0 and range[2]==1,'single-pass source world must use unbiased ordinary depth')
PocketMap.Flashlight.IsOn=function()return true end
render.RenderFlashlights=flashDraw
draws={}
mini:Draw('opaque')
assert(#draws==3 and not draws[2].color and draws[3].flash,'active flashlight must automatically restore its precise depth pass')
assert(waterSource,'flashlight alignment must retain the source camera for water')
PocketMap.Flashlight.IsOn=function()return false end
render.RenderFlashlights=function()end
quality.world_source_camera=false
draws={}
mini:Draw('opaque')
assert(#draws==1 and not draws[1].source and draws[1].matrix==mini.matrix,'earlier miniature-space world path must remain selectable')
assert(not waterSource,'water must keep the miniature projection when the world uses it')
local outside=true
mini.EyeInside=function()return not outside end
quality.minimal_preview=true
mini.waterPlanes={true}
local extras=0
local extra=function()extras=extras+1 end
PocketMap.Props.Draw=extra
PocketMap.Detail.Draw=extra
PocketMap.MapIO.Draw=extra
PocketMap.Effects.Draw=extra
PocketMap.Water.Draw=extra
PocketMap.Water.Calibrate=extra
PocketMap.Sky.Draw3D=extra
PocketMap.Sky.DrawBackdrop=extra
PocketMap.Scene.View=function()end
mini.skyBackdrop=nil
local previewMaterial={}
local bound,lightmaps,mode=nil,0,0
PocketMap.Materials.ForPreview=function()return previewMaterial end
render.SetMaterial=function(m)bound=m end
render.SetLightmapTexture=function()lightmaps=lightmaps+1 end
render.SetLightingMode=function(m)mode=m end
draws={}
mini:Draw('opaque')
mini:Draw('translucent')
assert(#draws==1 and bound==previewMaterial and extras==0 and lightmaps==0 and mode==0,
    'outside preview must draw only the opaque fullbright world, once, and restore lighting state')
assert(not mini:RequiresEngineView(),'preview retained a flashlight or glow fallback')
mini:DrawScene({lightmap=mini.lightmapTexture})
assert(#draws==2 and extras==0,'secondary scene draw bypassed the minimal preview')
fail=true
assert(not pcall(Mini.Draw,mini,'opaque') and mode==0 and #matrices==0,
    'failed preview leaked fullbright or its model matrix')
fail=false
mini.skyObjects={}
outside=false
mini:Draw('opaque')
assert(extras>0 and lightmaps>0,'entering failed to restore selected features and baked lighting')
local before=extras
outside=true
mini:Draw('opaque')
assert(extras==before,'leaving failed to restore the minimal preview')
quality.minimal_preview=false
mini:Draw('opaque')
assert(extras>before,'disabling the option failed to restore the ordinary outside preview')
print('world view: source reflections, shared flashlight depth, projection and error cleanup passed')
