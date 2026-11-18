-- BSP rope keyframes also carry cloth, chains and other authored ribbons.
PocketMap.Ropes = PocketMap.Ropes or {}
local Ropes = PocketMap.Ropes
local IO, Visibility = PocketMap.MapIO, PocketMap.Visibility
local DOWN = Vector( 0, 0, -1 )
local WIND_AXIS = Vector( 1, 0, 0 )
local LEGACY_MATERIALS = { [0] = "cable/cable", "cable/rope", "cable/chain" }
local NODE_COUNTS = { [0] = 10, 4, 2 }
local CLASSES = { "move_rope", "keyframe_rope" }
local MAX_BATCH_QUADS = 512

local function ropePath( rope, start, finish )
	local delta = finish and finish - start or vector_origin
	local distance = delta:Length()
	local length = math.max( 0, math.floor( distance ) + rope.slack )
	local axis = delta:GetNormalized()
	local sag = DOWN - axis * DOWN:Dot( axis )
	-- Approximate a hanging cable with a quadratic arc. The native spring
	-- rest length includes the Hammer slack offset of -100 world units.
	local drop = math.sqrt( math.max( 0, length ^ 2 - distance ^ 2 ) ) * 0.5
	if rope.dangling then delta, sag = DOWN * length, vector_origin end
	return delta, sag * drop, length * rope.uvScale
end

local function makeRope( mini, job, record, materials )
	local entity = record.entity
	local nextKey = IO.Value( entity, "NextKey" )
	local targets = type( nextKey ) == "string" and mini.mapIO.names[string.Trim( nextKey ):lower()]
	local target = targets and targets[1]
	local dangling = IO.Number( entity, "Dangling", 0 ) == 1
	if not target and not dangling then return end
	local width = IO.Number( entity, "Width", 2 )
	if width <= 0 then return end
	local name = PocketMap.Materials.Name( IO.Value( entity, "RopeMaterial" ) )
	if name == "" then name = LEGACY_MATERIALS[IO.Number( entity, "RopeShader", 0 )] or LEGACY_MATERIALS[0] end
	local material = materials[name]
	if material == nil then
		material = PocketMap.Materials.Load( name )
		materials[name] = material
	end
	if material:IsError() then return end
	local start, finish = record.origin, target and target.origin
	local subdivisions = math.Clamp( math.floor( IO.Number( entity, "Subdiv", 2 ) ), 0, 7 )
	if IO.Number( entity, "Barbed", 0 ) == 1 then subdivisions = 3 end
	local spans = ( NODE_COUNTS[IO.Number( entity, "Type", -1 )] or 5 ) - 1
	-- The engine budgets texture spacing over its physics nodes and inserts
	-- another interval between them. Keep the same UV span with fewer quads.
	local textureSpan = spans * ( subdivisions + 1 ) / ( spans * subdivisions + 1 )
	local rope = {
		start = start, finish = finish, sourceIndex = record.order, targetIndex = target and target.order,
		dangling = dangling, halfWidth = width * 0.5, slack = IO.Number( entity, "Slack", 0 ) - 100,
		subdiv = subdivisions + 3,
		uvScale = textureSpan * 4 / math.Clamp( IO.Number( entity, "TextureScale", 4 ), 0.1, 10 ) / math.max( material:Height(), 1 ),
		scroll = IO.Number( entity, "ScrollSpeed", 0 ),
	}
	rope.delta, rope.sag, rope.repeatV = ropePath( rope, start, finish )
	local length = rope.delta:Length()
	if length < 0.01 and rope.sag:LengthSqr() < 0.01 then return end
	if IO.Number( entity, "NoWind", 0 ) == 0 and IO.Number( entity, "UseWind", 1 ) ~= 0 then
		rope.sway = math.min( length * 0.0125, 9 )
	end
	if not rope.sway and rope.sag:LengthSqr() < 0.01 then rope.subdiv = 1 end
	local last = start + rope.delta
	local pad = rope.halfWidth + rope.sag:Length() + ( rope.sway or 0 ) + 1
	local mins = Vector( math.min( start.x, last.x ) - pad, math.min( start.y, last.y ) - pad, math.min( start.z, last.z ) - pad )
	local maxs = Vector( math.max( start.x, last.x ) + pad, math.max( start.y, last.y ) + pad, math.max( start.z, last.z ) + pad )
	rope.blockCenter = mini:BlockPosition( ( mins + maxs ) * 0.5 )
	rope.blockExtents = ( maxs - mins ) * ( mini.scale * 0.5 )
	rope.blockRadius = rope.blockExtents:Length()
	local startLeaf = job.skyArea and mini.bsp:PointInLeaf( 0, start )
	local endLeaf = startLeaf and mini.bsp:PointInLeaf( 0, last )
	local sky = startLeaf and endLeaf and startLeaf.area == job.skyArea and endLeaf.area == job.skyArea
	if not sky then rope.clusters = Visibility.BoundsClusters( mini.bsp, mins, maxs ) end
	return rope, material, sky
end

---Collects linked keyframes and groups their ribbons by material and draw pass.
function Ropes.Build( mini, job )
	mini.ropeBatches = { opaque = {}, translucent = {}, skyOpaque = {}, skyTranslucent = {} }
	local materials, byPass = {}, {}
	for _, class in ipairs( CLASSES ) do
		for i, record in ipairs( mini.mapIO.byClass[class] or {} ) do
			local rope, material, sky = makeRope( mini, job, record, materials )
			if rope then
				local translucent = NikNaks.MeshBuilder.BlendsWithBackground( material )
				local pass = sky and ( translucent and "skyTranslucent" or "skyOpaque" ) or ( translucent and "translucent" or "opaque" )
				byPass[pass] = byPass[pass] or {}
				local batch = byPass[pass][material]
				if not batch then
					batch = { material = material, ropes = {}, visible = {} }
					byPass[pass][material] = batch
					table.insert( mini.ropeBatches[pass], batch )
				end
				table.insert( batch.ropes, rope )
			end
			if i % 16 == 0 then coroutine.yield() end
		end
	end
end

local function addVertex( pos, normal, u, v )
	mesh.Position( pos )
	mesh.Normal( normal )
	mesh.TexCoord( 0, u, v )
	mesh.Color( 255, 255, 255, 255 )
	mesh.AdvanceVertex()
end

local function drawRibbon( rope, eye, now, state )
	local start, delta, sag, repeatV = rope.start, rope.delta, rope.sag, rope.repeatV
	if state then
		local records = state.world.entities
		start = IO.Position( state, records[rope.sourceIndex] )
		local finish = rope.targetIndex and IO.Position( state, records[rope.targetIndex] )
		if start ~= rope.start or finish ~= rope.finish then delta, sag, repeatV = ropePath( rope, start, finish ) end
	end
	local previousLeft, previousRight, previousNormal
	local v = now * rope.scroll % 1
	local sway = rope.sway and WIND_AXIS * ( math.sin( now * 1.05 + rope.start.x * 0.004 ) * rope.sway ) or vector_origin
	for i = 0, rope.subdiv do
		local t = i / rope.subdiv
		local bend = 4 * t * ( 1 - t )
		local wind = rope.dangling and t * t or bend
		local windSlope = rope.dangling and 2 * t or 4 - 8 * t
		local point = start + delta * t + sag * bend + sway * wind
		local axis = delta + sag * ( 4 - 8 * t ) + sway * windSlope
		local side = ( eye - point ):Cross( axis ):GetNormalized()
		local normal = axis:Cross( side ):GetNormalized()
		local left, right = point - side * rope.halfWidth, point + side * rope.halfWidth
		if i > 0 then
			local beforeV, afterV = v + ( i - 1 ) / rope.subdiv * repeatV, v + t * repeatV
			addVertex( previousLeft, previousNormal, 0, beforeV )
			addVertex( previousRight, previousNormal, 1, beforeV )
			addVertex( right, normal, 1, afterV )
			addVertex( left, normal, 0, afterV )
		end
		previousLeft, previousRight, previousNormal = left, right, normal
	end
end

---Draws visible camera-facing ribbons in world or sky room coordinates.
function Ropes.Draw( mini, pass, matrix, view, pvs, visibleInView )
	local batches = mini.ropeBatches and mini.ropeBatches[pass]
	if not batches or #batches == 0 then return end
	local sky = matrix ~= nil
	local water = PocketMap.Water
	local camera = water.pass and water.sceneView or PocketMap.Scene and PocketMap.Scene.View( mini )
	local eye = view and view.mapOrigin or ( mini.ent:WorldToLocal( camera and camera.origin or EyePos() ) - mini.boxCenter ) / mini.scale + mini.mapCenter
	if sky then eye = eye / ( mini.skyScale or 16 ) + mini.skyOrigin end
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local state = walk and walk.mini == mini and walk.io
	local now = CurTime()
	local translucent = pass == "translucent" or pass == "skyTranslucent"
	if translucent then render.OverrideDepthEnable( true, false ) end
	cam.PushModelMatrix( matrix or mini.matrix, true )
	for _, batch in ipairs( batches ) do
		local visible, count = batch.visible, 0
		for _, rope in ipairs( batch.ropes ) do
			local moved = false
			if state then
				local records = state.world.entities
				moved = IO.Position( state, records[rope.sourceIndex] ) ~= rope.start
					or rope.targetIndex and IO.Position( state, records[rope.targetIndex] ) ~= rope.finish
			end
			if moved or sky or Visibility.Visible( rope.clusters, pvs ) and visibleInView( rope, view ) then
				count = count + 1
				visible[count] = rope
			end
		end
		if count > 0 then
			render.SetMaterial( batch.material )
			local first = 1
			while first <= count do
				local last, quads = first, visible[first].subdiv
				while last < count and quads + visible[last + 1].subdiv <= MAX_BATCH_QUADS do
					last = last + 1
					quads = quads + visible[last].subdiv
				end
				mesh.Begin( MATERIAL_QUADS, quads )
				for i = first, last do drawRibbon( visible[i], eye, now, state ) end
				mesh.End()
				first = last + 1
			end
		end
	end
	cam.PopModelMatrix()
	if translucent then render.OverrideDepthEnable( true, true ) end
end
