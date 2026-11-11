PocketMap = PocketMap or {}
PocketMap.Materials = PocketMap.Materials or {}
local Materials = PocketMap.Materials
Materials.scaled = Materials.scaled or {}

local CUBEMAP_COPY_PATTERN = "^maps/[^/]+/(.+)_%-?%d+_%-?%d+_%-?%d+$"

local function vmtExists( name )
	return file.Exists( "materials/" .. name .. ".vmt", "GAME" )
end

---Faces of a map name the cubemap copy of a material, which only exists inside that map's pakfile. The original is the fallback.
---Material() prints an error for a missing .vmt, so the file is checked first.
---@param name string # the texture name of a face
---@return IMaterial material # the engine's error material if nothing was found
---@return number seconds # how long loading took
function Materials.Load( name )
	local took = 0

	if vmtExists( name ) then
		local material, seconds = Material( name )
		took = seconds or 0
		if not material:IsError() then return material, took end
	end

	local original = string.match( name, CUBEMAP_COPY_PATTERN )
	if original and vmtExists( original ) then
		local material, seconds = Material( original )
		took = took + ( seconds or 0 )
		if not material:IsError() then return material, took end
	end

	return Material( "___error" ), took
end

---The debug material of the sky, or the cubemap copy of it that a map saves.
---@param name string?
---@return boolean
function Materials.IsSkyName( name )
	return type( name ) == "string" and string.find( string.lower( name ), "toolsskybox", 1, true ) ~= nil
end

local function materialProxies(name, seen)
	name = name:gsub("^materials/", ""):gsub("%.vmt$", "")
	if seen[name] then return end
	seen[name] = true
	local text = file.Read("materials/" .. name .. ".vmt", "GAME")
	local values = text and util.KeyValuesToTable(text)
	if not values then return end
	local proxies = values.include and materialProxies(values.include, seen)
	return values.proxies or (values.replace and values.replace.proxies)
		or (values.insert and values.insert.proxies) or proxies
end

-- Seamless shaders cache their world-position mapping scale in the material's
-- static command buffer. SetFloat around each draw cannot reliably update it.
-- Give each scale its own snapshot and leave the real map's material untouched.
function Materials.ForScale(material, scale)
	if not scale or scale ~= scale or scale <= 0 or scale == math.huge or scale == 1 then return material end
	local seamless = material:GetFloat("$seamless_scale")
	if not seamless or seamless == 0 then return material end
	local key = material:GetName() .. ":" .. string.format("%.17g:%.17g", scale, seamless)
	local cached = Materials.scaled[key]
	if cached then return cached end
	local values, matrices, textures = {}, {}, {}
	for name, value in pairs(material:GetKeyValues()) do
		if type(value) == "ITexture" then
			values[name], textures[name] = value:GetName(), value
		elseif ismatrix(value) then
			matrices[name] = value
		elseif isvector(value) then
			values[name] = string.format("[%g %g %g]", value.x, value.y, value.z)
		else
			values[name] = value
		end
	end
	values["$seamless_scale"] = seamless / scale
	values.Proxies = materialProxies(material:GetName(), {})
	local shader = material:GetShader():gsub("_DX%d+$", "")
	local copy = CreateMaterial("PocketMap_Scaled_v1_" .. util.CRC(key), shader, values)
	for name, texture in pairs(textures) do copy:SetTexture(name, texture) end
	for name, matrix in pairs(matrices) do copy:SetMatrix(name, matrix) end
	copy:Recompute()
	Materials.scaled[key] = copy
	return copy
end

function Materials.DrawOptions(options, scale)
	return setmetatable({ material = function(material) return Materials.ForScale(material, scale) end }, { __index = options })
end
