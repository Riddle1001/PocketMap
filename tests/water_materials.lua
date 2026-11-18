-- Run from PocketMap root: lua tests/water_materials.lua
local file=assert(io.open('lua/pocketmap/cl_water.lua','r'))
local source=file:read('*a') file:close()
local function loadFunction(name,marker,env)
    local first=assert(source:find('local function '..name..'(',1,true))
    local last=assert(source:find(marker,first,true))
    local chunk=assert(loadstring(source:sub(first,last-1)..'\nreturn '..name))
    setfenv(chunk,setmetatable(env,{__index=_G}))
    return chunk()
end
local valid={IsError=function()return false end}
-- GMod can report false from IsError even for an undefined variable's texture.
local invalid={IsError=function()return false end}
local function material(cheap,reflect,refract)
    local values={['$forcecheap']=cheap,['$forceexpensive']=1-cheap,['$fogstart']=8,['$fogend']=128}
    local textures={['$reflecttexture']=reflect,['$refracttexture']=refract,['$envmap']=valid}
    return {GetName=function()return tostring(textures)end,GetShader=function()return 'Water'end,
        IsError=function()return false end,GetVector=function()end,
        GetKeyValues=function()return {['$reflecttexture']=textures['$reflecttexture']~=invalid and textures['$reflecttexture'] or nil,
            ['$refracttexture']=textures['$refracttexture']~=invalid and textures['$refracttexture'] or nil,['$envmap']=valid}end,
        GetInt=function(_,k)return values[k]end,SetInt=function(_,k,v)values[k]=v end,
        GetFloat=function(_,k)return values[k]end,SetFloat=function(_,k,v)values[k]=v end,
        GetTexture=function(_,k)return textures[k]end,SetTexture=function(_,k,v)textures[k]=v end}
end
local copies=0
local env={Water={materialCopies={}},MATERIAL_MODE_VERSION=6,REFRACTION_WARP_LIMIT=.08,REFLECTION_WARP_LIMIT=.35,
    util={CRC=function(s)return s end},PocketMap={Materials={}}}
local authored={proxies={TextureScroll={textureScrollVar='$bumptransform',textureScrollRate='.05',textureScrollAngle='45'}}}
env.PocketMap.Materials.ReadVMT=function()return authored end
env.PocketMap.Materials.Copy=function(original,name,overrides)
    copies=copies+1
    local reflection=original:GetTexture('$reflecttexture')
    if overrides['$reflecttexture']=='' then reflection=nil end
    local copy=material(overrides['$forcecheap'],reflection,original:GetTexture('$refracttexture'))
    copy.scroll=overrides['$scroll1']
    copy:SetFloat('$fogstart',overrides['$fogstart']) copy:SetFloat('$fogend',overrides['$fogend'])
    copy:SetFloat('$refractamount',overrides['$refractamount'])
    copy:SetFloat('$reflectamount',overrides['$reflectamount'])
    assert(name:find('WaterScene_v6_',1,true),'hot reload must use a new shader snapshot')
    return copy
end
env.materialFog=function()return {},120,8,128 end
env.materialMode=loadFunction('materialMode','local function cheapScroll',env)
env.cheapScroll=loadFunction('cheapScroll','local function sceneMaterial',env)
env.sceneMaterial=loadFunction('sceneMaterial','local function ensurePlaneMode',env)
local ensure=loadFunction('ensurePlaneMode','---@param key string',env)
local bind=loadFunction('bind','local function unbind',env)
local mini={scale=.01}
local cheapSource=material(1,valid,valid)
local cheap={sourceMaterial=cheapSource,material=material(0,valid,valid),isolatedMaterial=true}
ensure(mini,cheap)
assert(cheap.cheap and not cheap.reflectScene and not cheap.refractScene)
assert(cheap.material:GetInt('$forcecheap')==1 and cheap.material:GetInt('$forceexpensive')==0)
assert(cheap.material:GetTexture('$envmap')==valid and cheap.material:GetFloat('$fogend')==1.28)
assert(cheap.material.scroll=='[0.0353553391 0.0353553391 0]','cheap scroll lost authored speed or direction')
assert(not bind(cheap,{}) and cheap.material:GetTexture('$refracttexture')==valid)
local count=copies ensure(mini,cheap) assert(copies==count,'unchanged planes must reuse material policy')
mini.scale=.02 ensure(mini,cheap) assert(copies==count+1 and cheap.material:GetFloat('$fogend')==2.56)
local sourceMaterial=material(0,invalid,valid)
local plane={sourceMaterial=sourceMaterial,material=sourceMaterial,reflectRT={},refractRT={},fogStart=.16,fogEnd=2.56}
ensure(mini,plane)
assert(not plane.cheap and not plane.reflectScene and plane.refractScene)
bind(plane,{})
assert(plane.material:GetTexture('$reflecttexture')==invalid,'undefined reflection must stay on the cubemap path')
assert(plane.material:GetTexture('$refracttexture')==plane.refractRT)
assert(sourceMaterial:GetTexture('$refracttexture')==valid and sourceMaterial:GetFloat('$fogend')==128,
    'native materials must stay untouched')
local combined={sourceMaterial=material(0,valid,valid),reflectRT={},refractRT={},fogStart=.16,fogEnd=2.56}
combined.sourceMaterial:SetFloat('$refractamount',.5)
combined.sourceMaterial:SetFloat('$reflectamount',-1)
ensure(mini,combined)
assert(combined.fallbackMaterial:GetInt('$forcecheap')==1 and combined.cubemapMaterial,
    'missing animated cubemap variations')
bind(combined,{},combined.cubemapMaterial)
assert(combined.cubemapMaterial:GetTexture('$reflecttexture')==nil
    and combined.cubemapMaterial:GetTexture('$refracttexture')==combined.refractRT,
    'cubemap refraction variant bound a planar reflection')
assert(combined.material:GetFloat('$refractamount')==.08 and combined.material:GetFloat('$reflectamount')==-.35,
    'projection warp must be capped in either direction')
assert(combined.sourceMaterial:GetFloat('$refractamount')==.5 and combined.sourceMaterial:GetFloat('$reflectamount')==-1,
    'projection limits must leave the source material intact')
local sky={sourceMaterial=material(0,valid,valid)}
sky.sourceMaterial:SetInt('$reflectskyboxonly',1)
sky.sourceMaterial:SetFloat('$refractamount',.02)
ensure(mini,sky)
assert(sky.skyOnly and not sky.cubemapMaterial and sky.material:GetFloat('$refractamount')==.02,
    'sky-only water must retain its live sky option and gentle authored warp')
local fallback=material(0,nil,invalid)
local isCheap,reflect,refract=env.materialMode(fallback)
assert(isCheap and not reflect and not refract,'undefined scene textures must not schedule views')
local reflections,refractions=0,0
env.render={}
env.renderReflection=function()reflections=reflections+1 end
env.renderRefraction=function()refractions=refractions+1 end
local renderPlane=loadFunction('renderPlane','local WATER_MAX_TILT',env)
renderPlane(mini,plane,0,{},nil,{reflection=false,refraction=true})
assert(reflections==0 and refractions==1,'refraction-only water must skip reflection')
renderPlane(mini,plane,0,{},nil,{reflection=true,refraction=true})
assert(reflections==1 and refractions==2,'mixed materials must render the union of their passes')
print('water materials: native cheap water, cubemaps, optional scenes, isolated copies and hot reload passed')
