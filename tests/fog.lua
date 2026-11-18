-- Run from the PocketMap root: lua tests/fog.lua
local classes = {}
local IO = {
	Value = function( entity, key ) return entity[key] end,
	Number = function( entity, key, default ) return tonumber( entity[key] ) or default end,
	Vector = function( value ) return value end,
	OfClass = function( world, class ) return world.byClass[class] or {} end,
	Register = function( class, handlers ) classes[class] = handlers end,
	State = function( session, record )
		session.records[record] = session.records[record] or {}
		return session.records[record]
	end,
}
PocketMap = { MapIO = IO }
function Vector( x, y, z ) return { x = x or 0, y = y or 0, z = z or 0 } end
function math.Clamp( value, low, high ) return math.max( low, math.min( value, high ) ) end
function string.Trim( value ) return value:match( "^%s*(.-)%s*$" ) end
bit = { band = function( value, _ ) return value % 2 end }

MATERIAL_FOG_NONE, MATERIAL_FOG_LINEAR = 0, 1
local mode, first, last, height, r, g, b, density = 2, 2, 9, 8, 10, 20, 30, 0.5
render = {
	GetFogMode = function() return mode end,
	GetFogDistances = function() return first, last, height end,
	GetFogColor = function() return r, g, b end,
	GetFogMaxDensity = function() return density end,
	FogMode = function( value ) mode = value end,
	FogStart = function( value ) first = value end,
	FogEnd = function( value ) last = value end,
	SetFogZ = function( value ) height = value end,
	FogColor = function( red, green, blue ) r, g, b = red, green, blue end,
	FogMaxDensity = function( value ) density = value end,
}
dofile( "lua/pocketmap/cl_fog.lua" )
local Fog = PocketMap.Fog
local firstController = { class = "env_fog_controller", entity = { fogenable = 0 } }
local master = { class = "env_fog_controller", entity = {
	spawnflags = 1, fogenable = 1, fogstart = 64, fogend = 512, fogcolor = Vector( 120, 180, 220 ),
} }
local sky = { origin = Vector( 256, 256, 0 ), entity = { fogenable = 1, fogend = 2048 } }
local mini = { skyOrigin = sky.origin, mapIO = {
	byClass = { env_fog_controller = { firstController, master }, sky_camera = { sky } },
	byEntity = { [master.entity] = master },
	names = { clear = { firstController } },
} }
Fog.Read( mini )
assert( mini.worldFogEntity == master.entity and mini.skyFog.finish == 2048 )

local function checkHost()
	assert( mode == 2 and first == 2 and last == 9 and height == 8 )
	assert( r == 10 and g == 20 and b == 30 and density == 0.5 )
end

Fog.DrawWorld( mini, 0.25, nil, function()
	assert( mode == MATERIAL_FOG_LINEAR and first == 16 and last == 128 )
	assert( r == 120 and g == 180 and b == 220 and density == 1 )
	local scale = Fog.SetScale( 1 )
	assert( scale == 0.25 and first == 64 and last == 512 )
	Fog.SetScale( scale )
	Fog.Draw( mini, nil, nil, nil, function() assert( mode == MATERIAL_FOG_NONE ) end )
	assert( mode == MATERIAL_FOG_LINEAR and first == 16 and last == 128 )
end )
checkHost()
assert( not pcall( Fog.DrawWorld, mini, 1, nil, function() error( "draw failure" ) end ) )
checkHost()

local session = { world = mini.mapIO, records = {} }
PocketMap.Walk = { session = { mini = mini, io = session } }
classes.env_fog_controller.setenddist( session, master, "640" )
Fog.DrawWorld( mini, 0.25, nil, function() assert( last == 160 ) end )
assert( mini.worldFog.finish == 512, "fog input mutated baked defaults" )
Fog.Select( session, "clear" )
Fog.DrawWorld( mini, 0.25, nil, function() assert( mode == MATERIAL_FOG_NONE ) end )
checkHost()
print( "PASS fog: master controller, sky camera, scaled views, input isolation and render-state restoration" )
