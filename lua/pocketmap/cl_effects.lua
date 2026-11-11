-- Map effects that the BSP stores as entities rather than model geometry.
-- Keep their animated sprites in the miniature's translucent render pass.

if not PocketMap.Mini then return end

PocketMap.Effects = PocketMap.Effects or {}
local Effects = PocketMap.Effects
local Entities = PocketMap.Entities

local fireMaterial = Material( "sprites/flamelet1" )
local smokeMaterials = {}
local flameColors = {
	Color( 255, 155, 48, 230 ),
	Color( 255, 193, 71, 220 ),
	Color( 255, 224, 125, 170 ),
}

local function number( value, fallback )
	return tonumber( Entities.First( value ) ) or fallback
end

local function position( entity )
	local origin = Entities.First( entity.origin )
	return isvector( origin ) and origin or nil
end

local function smokeMaterial( name )
	name = type( name ) == "string" and name:gsub( "%.vmt$", "" ) or "particle/SmokeStack"
	if smokeMaterials[name] == nil then
		local material = Material( name )
		smokeMaterials[name] = not material:IsError() and material or false
	end
	return smokeMaterials[name] or nil
end

local function smokeColor( entity )
	local color = Entities.First( entity.rendercolor ) or "200 200 200"
	local r, g, b = tostring( color ):match( "(%d+)%s+(%d+)%s+(%d+)" )
	return Color( tonumber( r ) or 200, tonumber( g ) or 200, tonumber( b ) or 200 )
end

function Effects.Build( mini, entities )
	local effects = {}
	for _, entity in pairs( entities ) do
		local class = Entities.Class( entity )
		local origin = position( entity )
		if origin and class == "env_fire" and bit.band( number( entity.spawnflags, 0 ), 1 ) ~= 0 then
			effects[#effects + 1] = {
				kind = "fire", origin = origin,
				size = math.Clamp( number( entity.firesize, 64 ), 8, 256 ),
			}
		elseif origin and class == "env_smokestack" and number( entity.InitialState, 0 ) ~= 0 then
			local material = smokeMaterial( Entities.First( entity.SmokeMaterial ) )
			if material then
				effects[#effects + 1] = {
					kind = "smoke", origin = origin, material = material,
					length = math.max( 1, number( entity.JetLength, 100 ) ),
					speed = math.max( 1, number( entity.Speed, 20 ) ),
					startSize = math.max( 1, number( entity.StartSize, 8 ) ),
					endSize = math.max( 1, number( entity.EndSize, 24 ) ),
					spread = number( entity.BaseSpread, 0 ),
					alpha = math.Clamp( number( entity.renderamt, 255 ), 0, 255 ),
					color = smokeColor( entity ),
				}
			end
		end
	end

	for _, effect in ipairs( effects ) do
		effect.blockCenter = mini:BlockPosition( effect.origin )
		effect.blockRadius = ( effect.kind == "fire" and effect.size * 2 or effect.length + effect.endSize ) * mini.scale
		local leaf = mini.bsp:PointInLeaf( 0, effect.origin )
		effect.cluster = leaf and leaf.cluster >= 0 and leaf.cluster or nil
	end
	mini.effects = effects
end

local function drawFire( base, scale, up, right, time, effect )
	render.SetMaterial( fireMaterial )
	local size = effect.size * scale
	local sway = math.sin( time * 9 + base.x * 0.03 ) * size * 0.13
	for i = 1, 3 do
		local height = ( i - 1 ) * size * 0.32
		local flicker = 0.83 + math.sin( time * ( 8 + i * 2 ) + base.y * 0.1 ) * 0.15
		local width = size * ( 0.85 - i * 0.15 ) * flicker
		render.DrawSprite( base + up * height + right * sway * ( i - 1 ), width, size * flicker, flameColors[i] )
	end
	return 3
end

local function drawSmoke( base, scale, up, right, forward, time, effect )
	render.SetMaterial( effect.material )
	local count = 6
	local phase = time * effect.speed / effect.length
	for i = 1, count do
		local age = ( phase + i / count ) % 1
		local size = Lerp( age, effect.startSize, effect.endSize ) * scale
		local drift = effect.spread * scale * age * 0.12
		local offset = right * ( math.sin( i * 8 + time * 0.7 ) * drift )
			+ forward * ( math.cos( i * 5 + time * 0.6 ) * drift )
		local alpha = effect.alpha * math.min( 1, age * 5, ( 1 - age ) * 4 )
		local color = effect.color
		render.DrawSprite( base + up * ( effect.length * scale * age ) + offset,
			size, size, Color( color.r, color.g, color.b, alpha ) )
	end
	return count
end

-- The caller supplies the current BSP visibility and camera frustum, when known.
function Effects.Draw( mini, pvs, view, partVisible )
	local effects = mini.effects
	if not effects or #effects == 0 then return end
	local ent = mini.ent
	local scale = mini.scale
	local up, right, forward = ent:GetUp(), ent:GetRight(), ent:GetForward()
	local time = CurTime()
	local drawn, sprites = 0, 0

	for _, effect in ipairs( effects ) do
		if ( not pvs or not effect.cluster or pvs[effect.cluster] )
			and ( not view or partVisible( effect, view ) ) then
			local base = ent:LocalToWorld( effect.blockCenter )
			if effect.kind == "fire" then
				sprites = sprites + drawFire( base, scale, up, right, time, effect )
			else
				sprites = sprites + drawSmoke( base, scale, up, right, forward, time, effect )
			end
			drawn = drawn + 1
		end
	end
	mini.effectsDrawn, mini.effectSpritesDrawn = drawn, sprites
end
