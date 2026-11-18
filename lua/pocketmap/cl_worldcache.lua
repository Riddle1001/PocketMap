-- Combine static opaque faces for a visibility set, rather than submitting
-- every spatial slice that happens to contain one visible face. Compilation
-- cooperates with Think; the ordinary meshes remain visible until it finishes.
PocketMap.WorldCache = PocketMap.WorldCache or {}
local Cache = PocketMap.WorldCache
local LIMIT = 3
local BOUNDS_VERSION = 2
local BOUNDS_PAD = Vector( 8, 8, 8 )
local MIN_OCCLUSION_PARTS = 48
local OCCLUSION_SETTLE_FRAMES = 2
local UNSAFE_OCCLUDER_FLAGS = 0x10018424 -- wireframe, decal, ignore-Z, nearer depth, vertex alpha, no-draw
local OCCLUSION_SAMPLES = {
	{ -0.72, 0 }, { 0.72, 0 }, { -0.36, 0 }, { 0.36, 0 }, { 0, 0 },
	{ -0.36, 0.34 }, { 0.36, 0.34 }, { 0, 0.34 }, { -0.72, 0.34 }, { 0.72, 0.34 },
	{ -0.36, -0.34 }, { 0.36, -0.34 }, { 0, -0.34 }, { -0.72, -0.34 }, { 0.72, -0.34 },
}
local occludingMaterials = setmetatable( {}, { __mode = "k" } )

local function free( entry )
	for _, object in ipairs( entry.objects ) do object:Destroy() end
	entry.objects, entry.parts, entry.co = {}, {}, nil
	entry.faces, entry.occlusion = nil, nil
end

function Cache.Destroy( mini )
	for _, entry in ipairs( mini.worldVisibilityCache or {} ) do free( entry ) end
	mini.worldVisibilityCache = nil
end

local function visible( face, clusters, pvs )
	local linked = clusters[face.__id]
	if not linked or #linked == 0 then return true end
	for i = 1, #linked do if pvs[linked[i]] then return true end end
	return false
end

local function staticMaterial( material )
	local safe = occludingMaterials[material]
	if safe == nil then
		local source = PocketMap.Materials.ReadVMT( material:GetName() )
		local proxies = source and source.proxies
		safe = source ~= nil and ( proxies == nil or type( proxies ) == "table" and next( proxies ) == nil )
		occludingMaterials[material] = safe
	end
	return safe
end

local function compile( mini, entry )
	local options = { light = false, lightUV = mini.worldLightUV }
	for _, group in ipairs( mini.worldFaceGroups ) do
		local builder, count = NikNaks.MeshBuilder( true ), 0
		options.material = group.material
		local canBlock = staticMaterial( group.material )
		for i, face in ipairs( group.faces ) do
			if visible( face, mini.worldFaceClusters, entry.pvs ) then
				builder:AddFace( face, options )
				if canBlock and face:IsWorld() and not face:IsDisplacement() then entry.faces[face] = group.material end
				face:ClearMeshData()
				count = count + 1
			end
			if i % 16 == 0 then coroutine.yield() end
		end
		if count > 0 then
			local object = builder:Build()
			entry.objects[#entry.objects + 1] = object
			local center, radius, extents
			local mins, maxs = object:GetBounds()
			if mins then
				center = ( mins + maxs ) * 0.5
				radius = ( maxs - mins ):Length() * 0.5 + 8
				extents = ( maxs - mins ) * 0.5 + BOUNDS_PAD
			end
			for _, part in ipairs( object:GetMeshes() ) do
				if center then
					part.blockCenter = ( center - mini.mapCenter ) * mini.scale + mini.boxCenter
					part.blockRadius = radius * mini.scale
					part.worldCenter, part.worldExtents = center, extents
				end
				entry.parts[#entry.parts + 1] = part
			end
		end
		coroutine.yield()
	end
	entry.ready = true
end

function Cache.Get( mini, pvs )
	if PocketMap.Settings and not PocketMap.Settings.Enabled( mini, "world_cache" ) then return end
	if not pvs or not mini.worldFaceGroups or not mini.worldFaceClusters or not mini.worldLightUV then return end
	local entries = mini.worldVisibilityCache
	if entries and ( entries.source ~= mini.worldFaceGroups or entries.bsp ~= mini.bsp
		or entries.lightUV ~= mini.worldLightUV or entries.settings ~= mini.settings
		or entries.boundsVersion ~= BOUNDS_VERSION ) then Cache.Destroy( mini ) entries = nil end
	if not entries then
		entries = { source = mini.worldFaceGroups, bsp = mini.bsp, lightUV = mini.worldLightUV,
			settings = mini.settings, boundsVersion = BOUNDS_VERSION }
		mini.worldVisibilityCache = entries
	end
	local frame = FrameNumber()
	local key = PocketMap.Visibility.PVSKey( mini, pvs )
	for _, entry in ipairs( entries ) do
		if entry.key == key then
			entry.used = frame
			if entry.ready then return entry.parts, entry end
			return
		end
	end
	if #entries >= LIMIT then
		local oldest = 1
		for i = 2, #entries do if entries[i].used < entries[oldest].used then oldest = i end end
		free( table.remove( entries, oldest ) )
	end
	local entry = { key = key, pvs = pvs, used = frame, objects = {}, parts = {}, faces = {} }
	entry.co = coroutine.create( function() compile( mini, entry ) end )
	entries[#entries + 1] = entry
end

local function wallPolygon( entry, face )
	local material = entry.faces[face]
	if not material or not PocketMap.Visibility.OpaqueWorldFace( face, material )
		or bit.band( material:GetInt( "$flags" ) or 0, UNSAFE_OCCLUDER_FLAGS ) ~= 0
		or ( material:GetInt( "$ignorez" ) or 0 ) ~= 0
		or ( material:GetInt( "$decal" ) or 0 ) ~= 0 then return end
	local vertices = face:GetVertexs()
	if not vertices or #vertices < 3 or #vertices > 12 then return end
	local normal = face:GetNormal():GetNormalized()
	local distance, center = normal:Dot( vertices[1] ), Vector()
	for _, vertex in ipairs( vertices ) do
		if math.abs( normal:Dot( vertex ) - distance ) > 0.02 then return end
		center = center + vertex
	end
	center = center / #vertices
	for i, vertex in ipairs( vertices ) do
		local inward = normal:Cross( vertices[i % #vertices + 1] - vertex ):GetNormalized()
		if inward:Dot( center - vertex ) < 0 then inward = -inward end
		if inward:Dot( center - vertex ) < 1 then return end
		for _, other in ipairs( vertices ) do
			if inward:Dot( other - vertex ) < -0.02 then return end
		end
	end
	return { vertices = vertices, normal = normal, distance = distance, center = center }
end

local function plane( normal, distance )
	return { x = normal.x, y = normal.y, z = normal.z, distance = distance,
		ax = math.abs( normal.x ), ay = math.abs( normal.y ), az = math.abs( normal.z ) }
end

local function wallShadow( polygon, eye, forward, near )
	if polygon.normal:Dot( eye ) - polygon.distance < 2 then return end
	local vertices = polygon.vertices
	for _, vertex in ipairs( vertices ) do
		if ( vertex - eye ):Dot( forward ) < near + 1 then return end
	end
	local shadow = { plane( -polygon.normal, -polygon.distance ) }
	for i, vertex in ipairs( vertices ) do
		local edge = ( vertex - eye ):Cross( vertices[i % #vertices + 1] - eye ):GetNormalized()
		local inside = edge:Dot( polygon.center - eye )
		if math.abs( inside ) < 0.05 then return end
		if inside < 0 then edge = -edge end
		shadow[#shadow + 1] = plane( edge, edge:Dot( eye ) )
	end
	return shadow
end

local function sameVector( a, b )
	return a.x == b.x and a.y == b.y and a.z == b.z
end

-- Find blockers only while the view is settled. A changed eye or near plane
-- immediately returns the full frustum list while new blockers are checked.
function Cache.Occluders( mini, entry, view )
	if not view or not view.znear or view.znear <= 0 or not mini.bsp.SurfaceTraceLine or #entry.parts < MIN_OCCLUSION_PARTS then return end
	local wireframe = GetConVar( "mat_wireframe" )
	if wireframe and wireframe:GetBool() then return end
	local eye, forward, near = view.mapOrigin, view.forward, view.znear / mini.scale
	local context = entry.occlusion or {}
	entry.occlusion = context
	local frame = FrameNumber()
	if not context.eye or not sameVector( eye, context.eye ) or not sameVector( forward, context.forward ) or near ~= context.near then
		context.eye, context.forward, context.near = eye, forward, near
		context.settledAt, context.index = frame + OCCLUSION_SETTLE_FRAMES, 1
		context.shadows, context.tested = nil, nil
		return
	end
	if frame < context.settledAt then return end
	local sample = OCCLUSION_SAMPLES[context.index]
	if sample and context.frame ~= frame then
		context.frame, context.index = frame, context.index + 1
		local ray = ( forward + view.right * sample[1] + view.up * sample[2] ):GetNormalized()
		local hit = mini.bsp:SurfaceTraceLine( eye, eye + ray * 3200 )
		local face = hit and hit.Hit and not hit.HitSky and hit.Face
		context.tested = context.tested or {}
		if face and not context.tested[face] then
			context.tested[face] = true
			local poly = wallPolygon( entry, face )
			local shadow = poly and wallShadow( poly, eye, forward, near )
			if shadow then
				-- Replacing the list invalidates the frustum result for this pose.
				local shadows = {}
				for i, existing in ipairs( context.shadows or {} ) do shadows[i] = existing end
				shadows[#shadows + 1] = shadow
				context.shadows = shadows
			end
		end
	end
	return context.shadows
end

function Cache.Occluded( part, shadows )
	local center, extents = part.worldCenter, part.worldExtents
	if not center or not extents then return false end
	for _, shadow in ipairs( shadows ) do
		local hidden = true
		for _, p in ipairs( shadow ) do
			local low = p.x * center.x + p.y * center.y + p.z * center.z - p.distance
				- p.ax * extents.x - p.ay * extents.y - p.az * extents.z
			if low < 1 then hidden = false break end
		end
		if hidden then return true end
	end
	return false
end

local function canCompile( mini, now )
	if not PocketMap.Settings then return true end
	if not PocketMap.Settings.Enabled( mini, "world_cache" ) then return false end
	if not PocketMap.Settings.Enabled( mini, "defer_world_cache" ) then return true end
	-- A frozen set cannot become transient as its camera moves around.
	if PocketMap.PVSFreeze and PocketMap.PVSFreeze.Get( mini ) then return true end
	local walk = PocketMap.Walk and PocketMap.Walk.session
	if not walk or walk.mini ~= mini or not walk.move then return false end
	local origin = walk.move.origin
	if not mini.worldCacheOrigin or origin:DistToSqr( mini.worldCacheOrigin ) > 0.0625 then
		mini.worldCacheOrigin = Vector( origin.x, origin.y, origin.z )
		mini.worldCacheReadyAt = now + 0.15
	end
	return now >= ( mini.worldCacheReadyAt or 0 )
end

PocketMap.Hooks.Register( "Think", "PocketMap_WorldCache", function()
	local deadline = SysTime() + 0.001
	local frame = FrameNumber()
	for mini in pairs( PocketMap.Active or {} ) do
		if canCompile( mini, SysTime() ) then
		for _, entry in ipairs( mini.worldVisibilityCache or {} ) do
			-- Do not spend the frame budget on visibility sets no view requests.
			if entry.co and not entry.failed and ( entry.used or 0 ) >= frame - 1 then
				repeat
					local ok, err = coroutine.resume( entry.co )
					if not ok then
						free( entry )
						entry.failed = true
						ErrorNoHalt( "[PocketMap] World visibility cache: " .. tostring( err ) .. "\n" )
						break
					end
					if coroutine.status( entry.co ) == "dead" then entry.co = nil break end
				until SysTime() >= deadline
			end
			if SysTime() >= deadline then return end
		end
		end
	end
end )
