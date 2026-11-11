-- Drawing a loaded map. The engine draws a block in two passes (opaque, translucent), and the views that use the stencil (the
-- sky behind the map, the 3D skybox, the flashlight) can't be split, so they are all drawn in the translucent call.

if not PocketMap.Mini then return end

local Mini = PocketMap.Mini
local Water = PocketMap.Water
local Sky = PocketMap.Sky
local Detail = PocketMap.Detail
local Props = PocketMap.Props

local FLASHLIGHT_STRENGTH = 0.6
local FLASHLIGHT_SIZE = 0.9
local WORLD_FRUSTUM_FOV_PAD = 6
local cvWorldFrustumCache = CreateClientConVar( "pocketmap_world_frustum_cache", "1", true, false,
	"Reuse visible world meshes while the rendered view and miniature are unchanged" )
local cvWaterSceneCull = CreateClientConVar( "pocketmap_water_scene_cull", "1", true, false,
	"Cull world meshes outside the water reflection and refraction cameras" )

local beamTexture

---The beam texture of the flashlight, the cookie the engine projects.
local function getBeamTexture()
	if beamTexture == nil then
		local material = Material( "effects/flashlight001" )
		beamTexture = not material:IsError() and material:GetTexture( "$basetexture" ) or false
	end
	return beamTexture or nil
end

local function activeFlashlightBeam()
	if FLASHLIGHT_STRENGTH <= 0 or not LocalPlayer():FlashlightIsOn() then return nil end
	return getBeamTexture()
end

---Mark every pixel the map draws with 1, to limit the flashlight spot to those.
local function beginStencil()
	render.ClearStencil()
	render.SetStencilEnable( true )
	render.SetStencilWriteMask( 255 )
	render.SetStencilTestMask( 255 )
	render.SetStencilReferenceValue( 1 )
	render.SetStencilCompareFunction( STENCIL_ALWAYS )
	render.SetStencilPassOperation( STENCIL_REPLACE )
	render.SetStencilFailOperation( STENCIL_KEEP )
	render.SetStencilZFailOperation( STENCIL_KEEP )
end

---Multiplied in as dst * ( 1 + beam ): it brightens what is lit instead of adding white.
local function drawFlashlightSpot( beam )
	render.SetStencilCompareFunction( STENCIL_EQUAL )
	render.SetStencilPassOperation( STENCIL_KEEP )

	local size = ScrH() * FLASHLIGHT_SIZE
	cam.Start2D()
		render.OverrideBlend( true, BLEND_DST_COLOR, BLEND_ONE, BLENDFUNC_ADD )
		render.SetColorModulation( FLASHLIGHT_STRENGTH, FLASHLIGHT_STRENGTH, FLASHLIGHT_STRENGTH )
		render.DrawTextureToScreenRect( beam, ScrW() / 2 - size / 2, ScrH() / 2 - size / 2, size, size )
		render.SetColorModulation( 1, 1, 1 )
		render.OverrideBlend( false )
	cam.End2D()
end

---Without an atlas the map is drawn fullbright.
local function drawOptions( mini )
	local options = mini.drawOptions
	if options and options.lightmap == mini.lightmapTexture then return options end

	options = { light = false, lightmap = mini.lightmapTexture, fullbright = mini.lightmapTexture == nil }
	mini.drawOptions = options
	return options
end

-- The water pass supplies its own camera. Other render targets use the
-- primary-view checks before enabling world frustum culling.
local function worldView( mini )
	if not mini.scale or mini.scale <= 0 then return nil end
	local waterView = Water.pass and cvWaterSceneCull:GetBool() and Water.sceneView
	if Water.pass and not waterView then return nil end
	if not Water.pass and render.GetRenderTarget and render.GetRenderTarget() then return nil end
	local view = waterView or render.GetViewSetup()
	if not view or not view.origin or not view.angles or view.ortho or view.offcenter or view.subrect then return nil end
	if not waterView then
		if EyePos():DistToSqr( view.origin ) > 1 then return nil end
		local angles = EyeAngles()
		if angles:Forward():Dot( view.angles:Forward() ) < 0.999
			or angles:Up():Dot( view.angles:Up() ) < 0.999 then return nil end
	end

	local fov, width, height = view.fov, view.width, view.height
	if not fov or fov <= 1 or fov * 0.5 + WORLD_FRUSTUM_FOV_PAD >= 90
		or not width or not height or width <= 0 or height <= 0 then return nil end
	local aspect = width / height
	if view.aspect and view.aspect > 0 then aspect = math.min( aspect, view.aspect ) end
	local tangent = math.tan( math.rad( fov * 0.5 + WORLD_FRUSTUM_FOV_PAD ) )
	-- Source projections sometimes use a 4:3 reference horizontal FOV. The
	-- extra width and height conservatively cover both FOV conventions.
	local halfWidth = tangent * math.max( 1, ( width / height ) / ( 4 / 3 ) )
	local halfHeight = math.max( tangent, halfWidth / aspect )
	local localAngles = mini.ent:WorldToLocalAngles( view.angles )
	return {
		origin = mini.ent:WorldToLocal( view.origin ),
		forward = localAngles:Forward(), right = localAngles:Right(), up = localAngles:Up(),
		halfWidth = halfWidth, halfHeight = halfHeight,
		widthRadius = math.sqrt( 1 + halfWidth * halfWidth ),
		heightRadius = math.sqrt( 1 + halfHeight * halfHeight ),
	}
end

-- BSP clusters only represent visibility for an eye inside the miniature's
-- source map. Invalid VIS, sky views, or unknown cameras fail open.
local function worldPVS( mini, view )
	if Water.pass or not view or not mini.bsp or not mini:EyeInside() then return nil end
	local frozen = PocketMap.PVSFreeze.Get( mini )
	if frozen then return frozen end
	local bsp = mini.bsp
	local eye = ( view.origin - mini.boxCenter ) / mini.scale + mini.mapCenter
	local cluster = bsp:ClusterFromPoint( eye )
	if not cluster or cluster < 0 then return nil end
	local vis = bsp:GetVisibility()
	if not vis or not vis.VisData or not vis.VisData[cluster] or bsp:IsVisibilityCorrupted() then return nil end
	if mini.worldPVSBSP ~= bsp or mini.worldPVSCluster ~= cluster then
		mini.worldPVSBSP, mini.worldPVSCluster = bsp, cluster
		mini.worldPVS = bsp:PVSForOrigin( eye )
	end
	return mini.worldPVS
end

local function worldPartVisible( part, view )
	if not view then return true end
	local center, radius = part.blockCenter, part.blockRadius
	if center and radius then
		local dx, dy, dz = center.x - view.origin.x, center.y - view.origin.y, center.z - view.origin.z
		local forward, right, up = view.forward, view.right, view.up
		local depth = dx * forward.x + dy * forward.y + dz * forward.z
		if depth + radius < 0 then return false end
		if math.abs( dx * right.x + dy * right.y + dz * right.z ) > depth * view.halfWidth + radius * view.widthRadius then return false end
		if math.abs( dx * up.x + dy * up.y + dz * up.z ) > depth * view.halfHeight + radius * view.heightRadius then return false end
	end
	return true
end

-- The BSP PVS only changes when the eye enters another visibility cluster.
-- Filter the material-ordered draw list once per PVS; the camera frustum is
-- still tested every draw, so turning or moving within a cluster stays exact.
local function worldPVSCandidates( mini, meshes, pvs, translucent )
	if not pvs then return meshes end
	local cache = mini.worldPVSCandidates
	local key = translucent and "translucent" or "opaque"
	local entry = cache and cache[key]
	if entry and entry.source == meshes and entry.pvs == pvs then return entry.parts end

	local parts = {}
	for i = 1, #meshes do
		local part = meshes[i]
		local clusters = part.worldClusters
		local visible = not clusters
		if clusters then
			for j = 1, #clusters do
				if pvs[clusters[j]] then visible = true break end
			end
		end
		if visible then parts[#parts + 1] = part end
	end
	cache = cache or {}
	cache[key] = { source = meshes, pvs = pvs, parts = parts }
	mini.worldPVSCandidates = cache
	return parts
end

-- The world meshes and their bounds are immutable after loading. Within the
-- same render view and PVS, avoid retesting hundreds of bounds every frame.
local function worldFrustumParts( mini, meshes, pvs, translucent, view )
	if not view or not cvWorldFrustumCache:GetBool() then return nil end
	local key = translucent and "translucent" or "opaque"
	if Water.pass then key = Water.pass .. "_" .. key end
	local cache = mini.worldFrustumParts and mini.worldFrustumParts[key]
	if cache and cache.source == meshes and cache.pvs == pvs then
		local old = cache.view
		local a, b = old.origin, view.origin
		local f, g = old.forward, view.forward
		local r, s = old.right, view.right
		local u, v = old.up, view.up
		if a.x == b.x and a.y == b.y and a.z == b.z
			and f.x == g.x and f.y == g.y and f.z == g.z
			and r.x == s.x and r.y == s.y and r.z == s.z
			and u.x == v.x and u.y == v.y and u.z == v.z
			and old.halfWidth == view.halfWidth and old.halfHeight == view.halfHeight then
			return cache.parts
		end
	end
	local candidates = worldPVSCandidates( mini, meshes, pvs, translucent )
	local parts = cache and cache.parts or {}
	local count = 0
	for i = 1, #candidates do
		local part = candidates[i]
		if worldPartVisible( part, view ) then
			count = count + 1
			parts[count] = part
		end
	end
	for i = count + 1, #parts do parts[i] = nil end
	mini.worldFrustumParts = mini.worldFrustumParts or {}
	mini.worldFrustumParts[key] = { source = meshes, pvs = pvs, view = view, parts = parts }
	return parts
end

---The reflection and refraction of the water are a second and third draw of the map, so they only get the opaque world:
---no props, plants or glass, which is most of the cost of a draw.
local function drawWorld( mini, options, translucent )
	local objects = mini.objects
	local meshes = translucent and objects.translucentMeshes or objects.opaqueMeshes
	local batched = meshes and options.lightmap and not options.lightOnly and not options.ignoreZ
	if batched and #meshes == 0 then return end
	if not batched and #objects == 0 then return end

	cam.PushModelMatrix( mini.matrix )
	local ok, err = pcall( function()
	if batched then
		-- One matrix and lightmap binding for all material slices of the static world.
		-- The ordering of the meshes within each pass stays the same as MeshBuilder's.
		local view = worldView( mini )
		local pvs = worldPVS( mini, view )
		local visible = worldFrustumParts( mini, meshes, pvs, translucent, view )
		local candidates = visible or worldPVSCandidates( mini, meshes, pvs, translucent )
		if translucent then render.OverrideDepthEnable( true, false ) end
		render.SetLightmapTexture( options.lightmap )
		local lastMaterial
		local drawn = 0
		for i = 1, #candidates do
			local part = candidates[i]
			if visible or worldPartVisible( part, view ) then
				if part.material ~= lastMaterial then
					render.SetMaterial( PocketMap.Materials.ForScale(part.material, mini.scale) )
					lastMaterial = part.material
				end
				part.mesh:Draw()
				drawn = drawn + 1
			end
		end
		if not translucent then
			mini.worldMeshesDrawn = drawn
			mini.worldMeshesTotal = #meshes
			mini.worldPVSActive = pvs ~= nil
		end
		if translucent then render.OverrideDepthEnable( false ) end
	else
		-- Older loaded miniatures and maps without a lightmap use NikNaks' original drawing path.
		local drawOptions = PocketMap.Materials.DrawOptions(options, mini.scale)
		for i = 1, #objects do
			if translucent then objects[i]:DrawTranslucent( nil, drawOptions )
			else objects[i]:DrawOpaque( nil, drawOptions ) end
		end
	end
	end )
	cam.PopModelMatrix()
	if not ok then error( err, 0 ) end
end

---@param pass "opaque"|"translucent"|nil # nil draws both halves
local function drawContents( mini, options, pass )
	local lite = Water.pass ~= nil
	local doOpaque, doTranslucent = pass ~= "translucent", pass ~= "opaque" and not lite

	if doOpaque then
		drawWorld( mini, options, false )
		PocketMap.MapIO.Draw(mini, PocketMap.Materials.DrawOptions(options, mini.scale), false)
		Water.Draw( mini )

		if not lite then
			if not Detail.Blends( mini ) then Detail.Draw( mini ) end
			Props.Draw( mini, "opaque" )
		end
	end

	if doTranslucent then
		Props.Draw( mini, "translucent" )

		-- A blended sprite sheet must not write depth, or the sprites would cut out what is behind them
		if Detail.Blends( mini ) then
			render.OverrideDepthEnable( true, false )
			Detail.Draw( mini )
			render.OverrideDepthEnable( true, true )
		end

		drawWorld( mini, options, true )
		PocketMap.MapIO.Draw(mini, PocketMap.Materials.DrawOptions(options, mini.scale), true)
		local view = worldView( mini )
		PocketMap.Effects.Draw( mini, worldPVS( mini, view ), view, worldPartVisible )
		render.OverrideDepthEnable( true, true )
	end
end

function Mini:WaterDrawOptions()
	return drawOptions( self )
end

---The whole tiny map, both halves and no sky, in the current 3D view. The refraction and the reflection of the water use it.
function Mini:DrawScene( options )
	self:UpdateMatrix()
	render.OverrideDepthEnable( true, true )
	drawContents( self, options, nil )
	render.OverrideDepthEnable( false )
end

---@param pass "opaque"|"translucent"|nil
function Mini:Draw( pass )
	if self.state == "removed" or not self.scaleVec then return end
	if #self.objects == 0 and #self.propGroups == 0 and #self.detailMeshes == 0 then return end

	self:UpdateMatrix()

	local onScreen = not render.GetRenderTarget()
	if self.waterPlanes and #self.waterPlanes > 0 and onScreen then Water.Calibrate() end

	local options = drawOptions( self )
	local flashlight = activeFlashlightBeam()
	local sky = #self.skyObjects > 0 and onScreen and self:EyeInside()
	local backdrop = self.skyBackdrop ~= nil and onScreen

	local usesStencil = flashlight or sky or backdrop
	if usesStencil and pass == "opaque" then return end
	if usesStencil then
		pass = nil
		beginStencil()
	end

	if backdrop then Sky.DrawBackdrop( self ) end
	if sky then Sky.Draw3D( self, options ) end

	render.OverrideDepthEnable( true, true )
	drawContents( self, options, pass )
	render.OverrideDepthEnable( false )

	if flashlight then drawFlashlightSpot( flashlight ) end
	if usesStencil then render.SetStencilEnable( false ) end
end
