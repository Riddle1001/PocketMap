-- A walking view fills the screen with the pocket world. Drawing the host BSP
-- first adds a second world renderer whose pixels are subsequently covered.
PocketMap.Scene = {}
local Scene = PocketMap.Scene
local cvScene = CreateClientConVar( "pocketmap_walk_scene", "1", true, false,
	"Render a walking pocket directly, without first rendering the host world" )
local cvColorCorrection = GetConVar( "mat_colorcorrection" )
local coveredSkyView
local hostHasColorCorrection

local function needsNativeColorCorrection( mini )
	if not cvColorCorrection or not cvColorCorrection:GetBool() then return false end
	if hostHasColorCorrection ~= nil then return hostHasColorCorrection end

	local bsp = mini.mapName == game.GetMap() and mini.bsp or NikNaks.Map()
	if not bsp then return false end
	hostHasColorCorrection = false
	for _, entity in pairs( bsp:GetEntities() ) do
		local class = PocketMap.Entities.Class( entity )
		if class == "color_correction" or class == "color_correction_volume" then
			local filename = NikNaks.EntityValue( entity, "filename" )
			if type( filename ) == "string" and filename ~= "" then
				hostHasColorCorrection = true
				break
			end
		end
	end
	return hostHasColorCorrection
end

-- RenderScene runs before EyePos/EyeAngles describe the new frame. All our
-- renderers use this scoped camera instead; nested water/RT views keep theirs.
function Scene.View( mini )
	local view = Scene.current
	if view and view.mini == mini and view.frame == FrameNumber()
		and not PocketMap.Water.pass and not render.GetRenderTarget() then return view end
end

local function drawScene( origin, angles, fov )
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local enabled = cvScene:GetBool()
	if PocketMap.Settings and walk then enabled = PocketMap.Settings.Compat( walk.mini, "direct_scene", cvScene ) end
	if not enabled or Scene.current or not walk or walk.waitingForRespawn
		or PocketMap.Water.pass or render.GetRenderTarget() or not render.RenderHUD then return end
	coveredSkyView = nil
	local mini = walk.mini
	if mini.entityRefresh or mini == Scene.failedMini or mini.state ~= "ready" or not IsValid( mini.ent )
		or mini.ent:IsOutsideBox( origin ) then return end
	local setup = render.GetViewSetup()
	if not setup or setup.ortho or setup.offcenter or setup.subrect or not setup.znear or not setup.zfar
		or setup.width ~= ScrW() or setup.height ~= ScrH() or ( setup.x or 0 ) ~= 0 or ( setup.y or 0 ) ~= 0 then return end

	local view = { mini = mini, frame = FrameNumber(), origin = origin, angles = angles,
		fov = setup.fov or fov, x = 0, y = 0, width = ScrW(), height = ScrH(),
		znear = setup.znear, zfar = setup.zfar, aspect = setup.aspect }
	Scene.current = view
	local in3D, in2D, fallback = false, false, nil
	local ok, err = xpcall( function()
		fallback = mini.RequiresEngineView and mini:RequiresEngineView()
		-- Native postprocessing applies the host's authored LUT after the
		-- world is drawn. Keep it on both sides of a glow's frustum boundary.
		if not fallback and needsNativeColorCorrection( mini ) then fallback = "color correction" end
		if fallback then return end
		render.SetStencilEnable( false )
		render.Clear( 0, 0, 0, 255, true, true )
		cam.Start3D( origin, angles, view.fov, 0, 0, view.width, view.height, view.znear, view.zfar )
		in3D = true
		PocketMap.Sky.DrawCube( mini, origin, { angles = angles, fov = view.fov, w = view.width, h = view.height } )
		render.ClearDepth()
		mini:Draw( "opaque" )
		hook.Run( "PostDrawOpaqueRenderables", false, false, false )
		mini:Draw( "translucent" )
		hook.Run( "PostDrawTranslucentRenderables", false, false, false )
		cam.End3D()
		in3D = false
		cam.Start2D()
		in2D = true
		hook.Run( "RenderScreenspaceEffects" )
		cam.End2D()
		in2D = false
		render.RenderHUD( 0, 0, view.width, view.height )
	end, debug.traceback )
	Scene.current = nil
	if fallback and ok then
		Scene.lastFallback = fallback
		Scene.engineFrames = ( Scene.engineFrames or 0 ) + 1
		-- Glow visibility needs the engine view. The pocket backdrop still
		-- covers the host sky when the camera is inside the loaded block.
		if ( fallback == "glow" or fallback == "color correction" )
			and mini.skyBackdrop and mini.scaleVec and #mini.objects > 0 then
			coveredSkyView = view
		end
		return
	end
	if in2D then cam.End2D() end
	if in3D then cam.End3D() end
	render.SetStencilEnable( false )
	render.OverrideDepthEnable( false )
	render.DepthRange( 0, 1 )
	if not ok then
		Scene.failedMini, Scene.error = mini, tostring( err )
		ErrorNoHalt( "[PocketMap] Direct walking view failed; using the ordinary renderer: " .. Scene.error .. "\n" )
		return
	end
	Scene.frames = ( Scene.frames or 0 ) + 1
	return true
end

local function skipCoveredSky()
	local view = coveredSkyView
	if not view or view.frame ~= FrameNumber() or PocketMap.Water.pass or render.GetRenderTarget() then return end
	local walk = PocketMap.Walk and PocketMap.Walk.session
	local mini = view.mini
	if not walk or walk.mini ~= mini or walk.waitingForRespawn or mini.state ~= "ready" or mini.entityRefresh
		or not mini.skyBackdrop then return end
	local setup = render.GetViewSetup()
	if not setup or setup.ortho or setup.offcenter or setup.subrect or setup.origin ~= view.origin or setup.angles ~= view.angles
		or setup.width ~= view.width or setup.height ~= view.height or ( setup.x or 0 ) ~= 0 or ( setup.y or 0 ) ~= 0
		or setup.fov ~= view.fov then return end
	coveredSkyView = nil
	return true
end

PocketMap.Hooks.Register( "RenderScene", "PocketMap_WalkScene", drawScene )
PocketMap.Hooks.Register( "PreDrawSkyBox", "PocketMap_CoveredHostSky", skipCoveredSky )
