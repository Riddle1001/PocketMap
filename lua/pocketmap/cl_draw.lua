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

-- GetViewSetup describes the primary view. It cannot be trusted while drawing
-- water, render targets, or a camera whose projection differs from the player.
-- Unrecognized cameras draw every part, preserving mirrors and alternate views.
local function worldView( mini )
	if Water.pass or ( render.GetRenderTarget and render.GetRenderTarget() ) then return nil end
	if not mini.scale or mini.scale <= 0 then return nil end
	local view = render.GetViewSetup()
	if not view or not view.origin or not view.angles or view.ortho or view.offcenter or view.subrect then return nil end
	if EyePos():DistToSqr( view.origin ) > 1 then return nil end
	local angles = EyeAngles()
	if angles:Forward():Dot( view.angles:Forward() ) < 0.999
		or angles:Up():Dot( view.angles:Up() ) < 0.999 then return nil end

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
	if not view or not mini.bsp or not mini:EyeInside() then return nil end
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

local function worldPartVisible( mini, part, view, pvs )
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
	local clusters = part.worldClusters
	if pvs and clusters then
		for i = 1, #clusters do
			if pvs[clusters[i]] then return true end
		end
		return false
	end
	return true
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
	if batched then
		-- One matrix and lightmap binding for all material slices of the static world.
		-- The ordering of the meshes within each pass stays the same as MeshBuilder's.
		local view = worldView( mini )
		local pvs = worldPVS( mini, view )
		if translucent then render.OverrideDepthEnable( true, false ) end
		render.SetLightmapTexture( options.lightmap )
		local lastMaterial
		local drawn = 0
		for i = 1, #meshes do
			local part = meshes[i]
			if worldPartVisible( mini, part, view, pvs ) then
				if part.material ~= lastMaterial then
					render.SetMaterial( part.material )
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
		for i = 1, #objects do
			if translucent then objects[i]:DrawTranslucent( nil, options )
			else objects[i]:DrawOpaque( nil, options ) end
		end
	end
	cam.PopModelMatrix()
end

---@param pass "opaque"|"translucent"|nil # nil draws both halves
local function drawContents( mini, options, pass )
	local lite = Water.pass ~= nil
	local doOpaque, doTranslucent = pass ~= "translucent", pass ~= "opaque" and not lite

	if doOpaque then
		drawWorld( mini, options, false )
		PocketMap.MapIO.Draw(mini, options, false)
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
		PocketMap.MapIO.Draw(mini, options, true)
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
