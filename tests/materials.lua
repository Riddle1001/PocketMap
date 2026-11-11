-- Run from the PocketMap root: lua tests/materials.lua
local luaType = type
function type(value) return luaType(value) == "table" and value.kind or luaType(value) end
function ismatrix(value) return type(value) == "VMatrix" end
function isvector(value) return type(value) == "Vector" end
local files = {
	["materials/terrain/test.vmt"] = { include = "materials/terrain/base.vmt" },
	["materials/terrain/base.vmt"] = { proxies = { AnimatedTexture = { animatedtexturevar = "$detail" } } },
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
	function result:Recompute() self.recomputes = self.recomputes + 1 end
	created[name] = result
	return result
end
dofile("lua/pocketmap/cl_materials.lua")
local M = PocketMap.Materials
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
