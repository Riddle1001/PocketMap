-- Run from the PocketMap root: lua tests/materials.lua
local luaType = type
function type(value) return luaType(value) == "table" and value.kind or luaType(value) end
function ismatrix(value) return type(value) == "VMatrix" end
function isvector(value) return type(value) == "Vector" end
local files = {
	["materials/terrain/test.vmt"] = { Patch = { include = "/MATERIALS\\Terrain\\Base.VMT",
		replace = { Proxies = {}, ["$AboveWater"] = 0 } } },
	["materials/terrain/base.vmt"] = { ["$abovewater"] = 1,
		proxies = { AnimatedTexture = { animatedtexturevar = "$detail" } } },
}
file = { Exists = function() return false end, Read = function(name) return files[name] end }
util = { KeyValuesToTable = function(text) return text end, CRC = function(text) return text end }
PocketMap = {}
local function texture(name)
	return { kind = "ITexture", GetName = function() return name end }
end
local base, detail, mask = texture("terrain/base"), texture("detail/grain"), texture("terrain/blend")
local transform = { kind = "VMatrix" }
local source = {
	["$seamless_scale"] = 0.002, ["$detailscale"] = 8, ["$detailblendmode"] = 6,
	["$detailblendfactor"] = 0.7, ["$basetexture"] = base, ["$detail"] = detail,
	["$blendmodulatetexture"] = mask, ["$basetexturetransform"] = transform,
	["$color"] = { kind = "Vector", x = 0.5, y = 0.7, z = 1 }, ["$flags"] = 2097152,
}
local original = {
	GetFloat = function(_, key) return source[key] end,
	GetInt = function(_, key) return source[key] end,
	GetName = function() return "terrain/test" end,
	GetShader = function() return "WorldVertexTransition_DX9" end,
	GetKeyValues = function() return source end,
}
local created = {}
function CreateMaterial(name, shader, values)
	assert(not created[name], "created the same cached material twice")
	local result = { name = name, shader = shader, values = values, textures = {}, matrices = {}, recomputes = 0 }
	function result:SetTexture(key, value) self.textures[key] = value end
	function result:SetMatrix(key, value) self.matrices[key] = value end
	function result:SetVector(key, value) self.values[key] = value end
	function result:Recompute() self.recomputes = self.recomputes + 1 end
	created[name] = result
	return result
end
dofile("lua/pocketmap/cl_materials.lua")
local M = PocketMap.Materials
local patch = M.ReadVMT("terrain/test")
assert(patch["$abovewater"] == 0 and patch.proxies.AnimatedTexture.animatedtexturevar == "$detail",
	"an empty BSP patch block replaced inherited animation or missed an authored override")
source['$halflambert'],source['$phong'],source['$selfillum']=1,1,1
source['$bumpmap'],source['$lightwarptexture']=detail,mask
local foliage=M.Copy(original,'test_foliage_copy',{['$translucent']=0,['$alphatest']=1})
assert(foliage.values['$halflambert']==1 and foliage.values['$phong']==1 and foliage.values['$selfillum']==1,
	'material copy discarded lighting controls')
assert(foliage.textures['$bumpmap']==detail and foliage.textures['$lightwarptexture']==mask,
	'material copy discarded normal map or light warp')
assert(foliage.values['$translucent']==0 and foliage.values['$alphatest']==1 and foliage.values.Proxies,
	'material copy lost alpha overrides or proxies')
local small = M.ForScale(original, 0.01)
assert(small.shader == "WorldVertexTransition" and small.values["$seamless_scale"] == 0.2, "incorrect persistent mapping scale")
assert(small.values["$detail"] == "detail/grain" and small.textures["$detail"] == detail, "detail texture was lost")
assert(small.textures["$blendmodulatetexture"] == mask and small.textures["$basetexture"] == base, "base or blend mask changed")
assert(small.values["$detailscale"] == 8 and small.values["$detailblendmode"] == 6 and small.values["$detailblendfactor"] == 0.7, "detail controls changed")
assert(small.matrices["$basetexturetransform"] == transform and small.values["$color"] == "[0.5 0.7 1]", "transform or tint lost")
assert(small.values["$flags"] == 2097152 and small.values.Proxies.AnimatedTexture.animatedtexturevar == "$detail", "flags or included proxies lost")
assert(source["$seamless_scale"] == 0.002 and source["$detail"] == detail, "shared real-map material changed")
assert(M.ForScale(original, 0.01) == small and small.recomputes == 1, "rebuilt a material during a repeated draw")
local large = M.ForScale(original, 0.02)
assert(large ~= small and large.values["$seamless_scale"] == 0.1 and small.values["$seamless_scale"] == 0.2, "different miniature scales contaminated each other")
local options = { lightmap = "atlas", fullbright = false, translucent = true }
local draw = M.DrawOptions(options, 0.01)
assert(draw.material(original) == small and draw.lightmap == "atlas" and draw.fullbright == false and draw.translucent, "draw lost lighting or pass options")
for _, scale in ipairs({ 0, -1, 1, math.huge, 0 / 0 }) do assert(M.ForScale(original, scale) == original, "unsupported scale changed material") end
source["$seamless_scale"] = 0
assert(M.ForScale(original, 0.01) == original, "ordinary UV-mapped material changed")
source["$seamless_scale"] = 0.004
original.GetShader = function() return "LightmappedGeneric_DX9" end
local other = M.ForScale(original, 0.02)
assert(other.shader == "LightmappedGeneric" and other.values["$seamless_scale"] == 0.2, "fix was restricted to one shader")
dofile("lua/pocketmap/cl_materials.lua")
assert(PocketMap.Materials.ForScale(original, 0.02) == other, "refresh discarded the material cache")
-- Exercise both mesh drawing paths through the shared NikNaks API.
local features={world_normalmaps=false,world_detailtextures=false,world_reflections=false}
PocketMap.Settings={Enabled=function(_,key)return features[key]~=false end}
source['$envmap'],source['$envmapmask']=mask,detail
source['$basetexture2']=mask
local simple=M.ForWorld(original,.02,{})
assert(simple.values['$bumpmap']=='' and not simple.textures['$bumpmap'],'normal maps must be omitted from the compiled variant')
assert(simple.values['$detail']=='' and not simple.textures['$detail'],'detail textures must be omitted without dropping base layers')
assert(simple.values['$envmap']=='' and not simple.textures['$envmap'],'cubemaps must be independently removable')
assert(simple.textures['$basetexture']==base and simple.textures['$basetexture2']==mask
    and simple.textures['$blendmodulatetexture']==mask and simple.values['$flags']==source['$flags'],
    'quality switches must preserve base/blend textures and opacity flags')
assert(simple.values['$seamless_scale']==.2 and simple.matrices['$basetexturetransform']==transform,'quality variant lost texture mapping')
assert(M.ForWorld(original,.02,{})==simple,'feature variants must be cached instead of compiled during repeated draws')
features.world_detailtextures=true
local detailed=M.ForWorld(original,.02,{})
assert(detailed~=simple and detailed.textures['$detail']==detail and detailed.values['$bumpmap']=='','feature switches are not independent')
original.GetShader=function()return 'Refract'end
assert(M.ForWorld(original,1,{})==original,'special refraction shaders must retain their opacity inputs')
original.GetShader=function()return 'LightmappedGeneric'end
assert(source['$bumpmap']==detail and source['$envmap']==mask and source['$detail']==detail,'feature variants changed native map materials')
bit={band=function(a,b)
	local result,p=0,1
	while a>0 and b>0 do
		if a%2==1 and b%2==1 then result=result+p end
		a,b,p=math.floor(a/2),math.floor(b/2),p*2
	end
	return result
end}
source['$flags']=0x2100
local hostCube = texture("engine/defaultcubemap")
local glassSource = { ["$envmap"] = hostCube, ["$normalmap"] = detail, ["$flags"] = 0x200800 }
local glass = {
	GetName = function() return "test/glass" end,
	GetShader = function() return "Refract_DX90" end,
	GetTexture = function(_, key) return glassSource[key] end,
	GetInt = function(_, key) return glassSource[key] end,
	GetVector = function() return nil end,
	GetKeyValues = function() return glassSource end,
}
render = { GetHDREnabled = function() return false end }
local pocketCube = "maps/surf_whiteout/cubemapdefault"
local glassCopy, refractive = M.ForPocketGlass(glass, pocketCube)
assert(refractive and glassCopy.values["$envmap"] == pocketCube and glassCopy.values["$model"] == 1)
assert(glassCopy.textures["$normalmap"] == detail and glassSource["$envmap"] == hostCube)
assert(M.ForPocketGlass(glass, pocketCube) == glassCopy, "glass material was rebuilt")
local noCube = M.ForPocketGlass(glass)
assert(noCube.values["$envmap"] == "" and noCube.values["$envmaptint"] == "[0 0 0]")
local preview=M.ForPreview(original)
assert(preview.shader=='UnlitGeneric' and preview.values['$basetexture']=='terrain/base',
	'preview must use a simple unlit base texture')
assert(preview.values['$bumpmap']==nil and preview.values['$detail']==nil and preview.values['$envmap']==nil
	and preview.values.Proxies==nil and preview.values['$basetexture2']==nil,
	'preview retained lighting, extra texture layers or animated proxies')
assert(preview.values['$alphatest']==1 and preview.values['$nocull']==1
	and preview.matrices['$basetexturetransform']==transform and preview.values['$color']=='[0.5 0.7 1]',
	'preview lost cutout/culling, texture coordinates or tint')
assert(M.ForPreview(original)==preview and M.DrawOptions({preview=true},.02).material(original)==preview,
	'preview must be cached and work through the legacy mesh path')
local special={GetName=function()return 'special/refract'end,GetShader=function()return 'Refract'end,
	GetKeyValues=original.GetKeyValues,GetInt=original.GetInt}
assert(M.ForPreview(special).shader=='UnlitGeneric','special shaders must not retain refraction in the preview')
assert(source['$bumpmap']==detail and source['$envmap']==mask,
	'preview changed an existing material or its native source')
PocketMap.Settings=nil
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
color_white = Color(255, 255, 255, 255)
NikNaks = {}
function Material() return {} end
local bound, draws = nil, 0
render = {
	SetMaterial = function(material) bound = material end,
	SetLightmapTexture = function() end, SetLightingMode = function() end,
	OverrideDepthEnable = function() end,
}
dofile("../NikNaks/lua/niknaks/modules/cl_mesh_builder.lua")
local object = NikNaks.MeshBuilder():Build()
object._meshes = { { material = original, translucent = false, mesh = { Draw = function() draws = draws + 1 end } } }
for _, opts in ipairs({ { lightmap = "atlas" }, { light = false } }) do
	object:DrawOpaque(nil, M.DrawOptions(opts, 0.02))
	assert(bound == other, "mesh path ignored material binding")
	assert(object._meshes[1].material == original, "draw changed the mesh's source material")
end
assert(draws == 2, "a mesh draw path was skipped")
print("PASS materials: generic shader support, detail and blend masks, transforms, proxies, scale isolation, original preservation, caching")
