-- Map fog belongs to the pocket's current render pass, never to the host view.
PocketMap.Fog = {}
local Fog = PocketMap.Fog
local IO = PocketMap.MapIO
local MASTER_FOG = 1

local function number( value )
	local n = tonumber( value )
	if n and n == n and math.abs( n ) < math.huge then return n end
end

local function fogColor( value )
	local rgb = IO.Vector( value )
	if not rgb then return end
	return Vector( math.Clamp( rgb.x, 0, 255 ), math.Clamp( rgb.y, 0, 255 ), math.Clamp( rgb.z, 0, 255 ) )
end

local function read( record )
	local entity = record.entity
	local primary = fogColor( IO.Value( entity, "fogcolor" ) ) or Vector()
	local blend = IO.Number( entity, "fogblend", 0 ) ~= 0
	local direction
	if blend then
		direction = IO.Number( entity, "use_angles", 0 ) ~= 0 and -record.angles:Forward()
			or IO.Vector( IO.Value( entity, "fogdir" ) ) or Vector()
		direction:Normalize()
	end
	return {
		enabled = IO.Number( entity, "fogenable", 0 ) ~= 0,
		start = number( IO.Value( entity, "fogstart" ) ) or 0,
		finish = number( IO.Value( entity, "fogend" ) ) or 0,
		density = math.Clamp( number( IO.Value( entity, "fogmaxdensity" ) ) or 1, 0, 1 ),
		primary = primary,
		secondary = fogColor( IO.Value( entity, "fogcolor2" ) ) or primary,
		direction = direction,
	}
end

function Fog.Read( mini )
	local master
	for _, record in ipairs( IO.OfClass( mini.mapIO, "env_fog_controller" ) ) do
		if not master or bit.band( IO.Number( record.entity, "spawnflags", 0 ), MASTER_FOG ) ~= 0 then
			master = record
		end
	end
	mini.worldFogEntity, mini.worldFog = master and master.entity, master and read( master )

	mini.skyFog = nil
	for _, camera in ipairs( IO.OfClass( mini.mapIO, "sky_camera" ) ) do
		if camera.origin == mini.skyOrigin then
			mini.skyFog = read( camera )
			break
		end
	end
end

local function writableFog( state, record )
	local current = IO.State( state, record )
	current.fog = current.fog or read( record )
	return current.fog
end

local function setter( key, parse )
	return function( state, record, value )
		value = parse( value )
		if value ~= nil then writableFog( state, record )[key] = value end
	end
end

IO.Register( "env_fog_controller", {
	turnon = function( state, record ) writableFog( state, record ).enabled = true end,
	turnoff = function( state, record ) writableFog( state, record ).enabled = false end,
	setstartdist = setter( "start", number ),
	setenddist = setter( "finish", number ),
	setmaxdensity = setter( "density", function( value )
		local n = number( value )
		return n and math.Clamp( n, 0, 1 )
	end ),
	setcolor = setter( "primary", fogColor ),
	setcolorsecondary = setter( "secondary", fogColor ),
	setangles = function( state, record, value )
		local config = writableFog( state, record )
		if config.direction then config.direction = -IO.Angle( value ):Forward() end
	end,
} )

function Fog.Select( state, name )
	for _, record in ipairs( state.world.names[string.Trim( name ):lower()] or {} ) do
		if record.class == "env_fog_controller" then
			state.fogController = record
			return
		end
	end
end

local function worldConfig( mini )
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local state = walk and walk.mini == mini and walk.io
	if state then
		local record = state.fogController
		if record then return writableFog( state, record ) end
		record = state.world.byEntity[mini.worldFogEntity]
		local current = record and state.records[record]
		if current and current.fog then return current.fog end
	end
	return mini.worldFog
end

local active, activeScale

-- A nested source-coordinate camera uses the same fog in unscaled BSP units.
function Fog.SetScale( scale )
	if not active then return end
	local previous = activeScale
	if scale ~= previous then
		activeScale = scale
		render.FogStart( active.start * scale )
		render.FogEnd( active.finish * scale )
	end
	return previous
end

local function fogRGB( mini, config, angles )
	local a, b = config.primary, config.secondary
	if not config.direction then return a.x, a.y, a.z end
	local water = PocketMap.Water
	local view = water and water.pass and water.sceneView or PocketMap.Scene and PocketMap.Scene.View( mini )
	local forward = mini.ent:WorldToLocalAngles( angles or view and view.angles or EyeAngles() ):Forward()
	local weight = 0.5 + 0.5 * forward:Dot( config.direction )
	return Lerp( weight, b.x, a.x ), Lerp( weight, b.y, a.y ), Lerp( weight, b.z, a.z )
end

function Fog.Draw( mini, config, scale, angles, draw, ... )
	local mode = render.GetFogMode()
	local enabled = config and config.enabled and config.density > 0
	if not enabled and mode == MATERIAL_FOG_NONE then return draw( ... ) end

	local first, last, height = render.GetFogDistances()
	local r, g, b = render.GetFogColor()
	local density = render.GetFogMaxDensity()
	local parent, parentScale = active, activeScale
	if enabled then
		active, activeScale = config, nil
		render.FogMode( MATERIAL_FOG_LINEAR )
		render.FogColor( fogRGB( mini, config, angles ) )
		render.FogMaxDensity( config.density )
		Fog.SetScale( scale )
	else
		active, activeScale = nil, nil
		render.FogMode( MATERIAL_FOG_NONE )
	end

	local ok, err = pcall( draw, ... )
	active, activeScale = parent, parentScale
	render.FogStart( first )
	render.FogEnd( last )
	render.SetFogZ( height )
	render.FogColor( r, g, b )
	render.FogMaxDensity( density )
	render.FogMode( mode )
	if not ok then error( err, 0 ) end
end

function Fog.DrawWorld( mini, scale, angles, draw, ... )
	return Fog.Draw( mini, worldConfig( mini ), scale, angles, draw, ... )
end
