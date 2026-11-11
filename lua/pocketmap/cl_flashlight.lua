-- Source's projected flashlight, positioned and traced in the source BSP.
-- The miniature supplies both the receiving meshes and its shadow-depth mesh.
PocketMap.Flashlight = PocketMap.Flashlight or {}
local Flashlight = PocketMap.Flashlight
if Flashlight.Stop then Flashlight.Stop() end
Flashlight.depthMaterials = Flashlight.depthMaterials or {}

local HULL_MINS, HULL_MAXS = Vector(-4, -4, -4), Vector(4, 4, 4)
local function setting(name, default)
	local cv = GetConVar(name)
	return cv and cv:GetFloat() or default
end

function Flashlight.Stop()
	if IsValid(Flashlight.projector) then Flashlight.projector:Remove() end
	Flashlight.projector, Flashlight.mini, Flashlight.pullback = nil, nil, nil
end

function Flashlight.IsOn()
	local ply = LocalPlayer()
	return IsValid(ply) and ply:GetNWBool("PocketMap_FlashlightActive", false)
		and ply:GetNWBool("PocketMap_FlashlightOn", false)
end

-- Source's flashlight traces use unscaled units. Scaling attenuation by the
-- same factor as distance preserves the shader's constant + linear/d + quad/d².
function Flashlight.Configure(lamp, scale, near)
	lamp:SetFOV(setting("r_flashlightfov", 60))
	lamp:SetNearZ(math.max(0.001, near * scale))
	lamp:SetFarZ(setting("r_flashlightfar", 750) * scale)
	lamp:SetConstantAttenuation(setting("r_flashlightconstant", 0))
	lamp:SetLinearAttenuation(setting("r_flashlightlinear", 100) * scale)
	lamp:SetQuadraticAttenuation(setting("r_flashlightquadratic", 0) * scale * scale)
	lamp:SetEnableShadows(setting("r_flashlightdepthtexture", 1) ~= 0)
	lamp:SetShadowDepthBias(setting("mat_depthbias_shadowmap", 0.001))
	lamp:SetShadowSlopeScaleDepthBias(setting("mat_slopescaledepthbias_shadowmap", 2))
end

-- The stock flashlight hangs below the eye and pulls back at nearby walls.
-- Query the miniature's collision, including props and moving brushes, rather
-- than tracing the real body and the unrelated outer map.
function Flashlight.Pose(session)
	local eye = session.move.origin + PocketMap.Walk.EyeOffset(session)
	local angles = session.move.angles
	local forward, up = angles:Forward(), angles:Up()
	local offset = setting("r_flashlightoffsety", -20)
	if setting("r_swingflashlight", 1) ~= 0 then offset = offset + math.max(0, -12 * forward.z) end
	local origin = eye + up * offset
	local ladder = session.onladder == true
	local mask = bit.band(MASK_SOLID, bit.bnot(CONTENTS_HITBOX))
	if ladder or session:TraceHull(eye, origin, HULL_MINS, HULL_MAXS, mask).Hit then origin = eye end
	local target = eye + forward * setting("r_flashlightfar", 750)
	local direction = (target - origin):GetNormalized()
	-- Keep the view's roll while orthogonalizing the projection basis.
	local lightUp = (up - direction * up:Dot(direction)):GetNormalized()
	local lightAngles = direction:AngleEx(lightUp)
	mask = bit.bor(bit.band(MASK_OPAQUE_AND_NPCS, bit.bnot(CONTENTS_HITBOX)), CONTENTS_WINDOW)
	local trace = session:TraceHull(origin, target, HULL_MINS, HULL_MAXS, mask)
	local distance = origin:Distance(Vector(trace.HitPos.x, trace.HitPos.y, trace.HitPos.z))
	local pullback = Flashlight.pullback or 1
	if distance < 128 then
		local desired = ladder and setting("r_flashlightladderdist", 40) or 128 - distance
		pullback = Lerp(0.2, pullback, desired)
		if not ladder then
			local back = session:TraceHull(origin, origin - direction * (desired - 0.1), HULL_MINS, HULL_MAXS, mask)
			if back.Hit then
				pullback = math.min(pullback, math.max(0, origin:Distance(Vector(back.HitPos.x, back.HitPos.y, back.HitPos.z)) - 0.1))
			end
		end
	else
		pullback = Lerp(0.2, pullback, 0)
	end
	Flashlight.pullback = pullback
	return origin - direction * pullback, lightAngles, setting("r_flashlightnear", 4) + pullback
end

function Flashlight.Update()
	local session = PocketMap.Walk and PocketMap.Walk.session
	local mini = session and session.mini
	if not mini or mini.state ~= "ready" or not IsValid(mini.ent) or not LocalPlayer():Alive()
		or not Flashlight.IsOn() then return Flashlight.Stop() end
	if Flashlight.mini ~= mini then Flashlight.Stop() end
	local lamp = Flashlight.projector
	if not IsValid(lamp) then
		lamp = ProjectedTexture()
		if not IsValid(lamp) then return end
		lamp:SetTexture("effects/flashlight001")
		lamp:SetColor(color_white)
		lamp:SetBrightness(1)
		lamp:SetLightWorld(true)
		lamp:SetNoCull(true)
		Flashlight.projector, Flashlight.mini = lamp, mini
		mini.ent:CreateShadow()
	end
	local origin, angles, near = Flashlight.Pose(session)
	lamp:SetPos(mini.ent:LocalToWorld(mini:BlockPosition(origin)))
	lamp:SetAngles(mini.ent:LocalToWorldAngles(angles))
	Flashlight.Configure(lamp, mini.scale, near)
	lamp:Update()
	mini.ent:MarkShadowAsDirty()
end

-- DepthWrite is essential: ordinary surface shaders omit Source's shadow
-- polygon offset and cause severe self-shadow stripes at miniature scales.
-- Alpha-tested fences and leaves retain their texture mask and UV transform.
function Flashlight.DepthMaterial(material)
	local cache = Flashlight.depthMaterials
	local depth = cache[material]
	if depth then return depth end
	local flags = material:GetInt("$flags") or 0
	local alpha = (material:GetInt("$alphatest") or 0) ~= 0 or bit.band(flags, 256) ~= 0
	local texture = alpha and material:GetTexture("$basetexture")
	local values = { ["$model"] = 1, ["$nocull"] = (material:GetInt("$nocull") or 0) ~= 0 and 1 or 0 }
	if bit.band(flags, 8192) ~= 0 then values["$nocull"] = 1 end
	if texture then
		values["$basetexture"] = texture:GetName()
		values["$alphatest"] = 1
		values["$alphatestreference"] = material:GetFloat("$alphatestreference") or 0.5
	end
	depth = CreateMaterial("PocketMap_Depth_" .. util.CRC(material:GetName()), "DepthWrite", values)
	if texture then
		depth:SetTexture("$basetexture", texture)
		local transform = material:GetMatrix("$basetexturetransform")
		if transform then depth:SetMatrix("$basetexturetransform", transform) end
	end
	cache[material] = depth
	return depth
end

local depthOptions = { light = false, fullbright = false, material = Flashlight.DepthMaterial }

function Flashlight.DrawDepth(mini, flags)
	if not mini or mini.state ~= "ready" or not mini.scaleVec then return end
	mini:UpdateMatrix()
	cam.PushModelMatrix(mini.matrix)
	local ok, err = pcall(function()
		local parts = mini.objects.opaqueMeshes
		if parts then
			for _, part in ipairs(parts) do
				render.SetMaterial(Flashlight.DepthMaterial(part.material))
				part.mesh:Draw()
			end
		else
			for _, object in ipairs(mini.objects) do object:DrawOpaque(nil, depthOptions) end
		end
	end)
	cam.PopModelMatrix()
	if not ok then error(err, 0) end
	-- Shadow casters must not use the main camera's PVS, occlusion or frustum:
	-- an offscreen prop can cast a visible shadow onto an onscreen wall.
	PocketMap.MapIO.DrawDepth(mini, depthOptions, flags)
	PocketMap.Props.DrawDepth(mini, flags)
end

hook.Add("PreRender", "PocketMap_Flashlight", Flashlight.Update)
hook.Add("ShutDown", "PocketMap_Flashlight", Flashlight.Stop)
