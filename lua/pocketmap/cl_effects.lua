-- Source effects simulate in BSP units. Use an equivalent source camera so
-- SpriteCard billboards keep the native size, animation, orientation and depth.
if not PocketMap.Mini then return end
PocketMap.Effects = PocketMap.Effects or {}
local Effects, IO = PocketMap.Effects, PocketMap.MapIO
local ZERO, DOWN = Vector(), Vector(0, 0, 1024)
local precached = {}

-- C_FireSmoke::Start selects these native systems using height / 36.
function Effects.FireSystem(entity)
    local sizes = { "tiny", "small", "medium", "large" }
    local size = math.Clamp(math.floor(IO.Number(entity, "firesize", 64) / 36) + 1, 1, 4)
    return "env_fire_" .. sizes[size] .. (bit.band(IO.Number(entity, "spawnflags", 0), 2) == 0 and "_smoke" or "")
end

local function stop(effect)
    if IsValid(effect.particle) then effect.particle:StopEmission(false, true) end
    if IsValid(effect.emitter) then effect.emitter:Finish() end
    effect.particle, effect.emitter, effect.lastUpdate, effect.pending = nil, nil, nil, nil
end

function Effects.Destroy(mini)
    for _, effect in ipairs(mini.effects or {}) do stop(effect) end
    mini.effects, mini.effectTrace, mini.effectsView = nil, nil, nil
end

local function setActive(session, record, active)
    IO.State(session, record).effectActive = active
end
IO.Register("env_fire", {
    startfire = function(s, r) if IO.State(s, r).enabled then setActive(s, r, true) end end,
    extinguish = function(s, r) setActive(s, r, false) end,
    extinguishtemporarily = function(s, r) setActive(s, r, false) end,
})
IO.Register("env_smokestack", {
    turnon = function(s, r) setActive(s, r, true) end,
    turnoff = function(s, r) setActive(s, r, false) end,
})

function Effects.Build(mini, entities)
    Effects.Destroy(mini)
    local effects = {}
    for _, entity in pairs(entities) do
        local class, origin = PocketMap.Entities.Class(entity), IO.Vector(IO.Value(entity, "origin"))
        local effect
        if origin and class == "env_fire" and IO.Number(entity, "firetype", 0) == 0 then
            effect = { kind = "fire", system = Effects.FireSystem(entity),
                active = bit.band(IO.Number(entity, "spawnflags", 0), 4) ~= 0,
                drop = bit.band(IO.Number(entity, "spawnflags", 0), 16) == 0,
                radius = math.max(64, IO.Number(entity, "firesize", 64) * 4) }
        elseif origin and class == "env_smokestack" then
            local value = IsColor(entity.rendercolor) and entity.rendercolor or IO.Value(entity, "rendercolor")
            local color = IsColor(value) and Vector(value.r, value.g, value.b) or IO.Vector(value) or Vector(255, 255, 255)
            local length, speed = math.max(1, IO.Number(entity, "JetLength", 180)), math.max(1, IO.Number(entity, "Speed", 30))
            local wind = math.rad(IO.Number(entity, "WindAngle", 0))
            local material = IO.Value(entity, "SmokeMaterial") or "particle/SmokeStack"
            effect = { kind = "smoke", active = IO.Number(entity, "InitialState", 0) ~= 0,
                material = material:gsub("%.vmt$", ""), color = color,
                alpha = math.Clamp(IO.Number(entity, "renderamt", 255), 0, 255),
                length = length, speed = speed, lifetime = length / speed,
                rate = math.max(0, IO.Number(entity, "Rate", 80)),
                startSize = math.max(0, IO.Number(entity, "StartSize", 10)), endSize = math.max(0, IO.Number(entity, "EndSize", 15)),
                spread = IO.Number(entity, "SpreadSpeed", 15), baseSpread = IO.Number(entity, "BaseSpread", 20),
                roll = math.rad(IO.Number(entity, "roll", 8)), twist = math.rad(IO.Number(entity, "twist", 0)),
                wind = Vector(math.cos(wind), math.sin(wind), 0) * IO.Number(entity, "WindSpeed", 0),
                radius = length + math.max(IO.Number(entity, "BaseSpread", 20), IO.Number(entity, "EndSize", 15)) * 2 }
        end
        if effect then
            effect.origin, effect.angles, effect.entity = origin, IO.Angle(IO.Value(entity, "angles")), entity
            effect.record = mini.mapIO and mini.mapIO.byEntity[entity]
            effect.blockCenter, effect.blockRadius = mini:BlockPosition(origin), effect.radius * mini.scale
            local leaf = mini.bsp:PointInLeaf(0, origin)
            effect.cluster = leaf and leaf.cluster >= 0 and leaf.cluster or nil
            effects[#effects + 1] = effect
        end
    end
    mini.effects = effects
end

local function isActive(mini, effect)
    local walk = PocketMap.Walk and PocketMap.Walk.session
    local state = walk and walk.mini == mini and walk.io
    local record = state and state.world.byEntity[effect.entity] or effect.record
    local current = state and record and state.records[record]
    if current then
        if not current.enabled then return false end
        if current.effectActive ~= nil then return current.effectActive end
    end
    return (not record or record.enabled) and effect.active
end

local function fireOrigin(mini, effect)
    if not effect.drop then return effect.origin end
    if effect.dropped then return effect.dropped end
    if mini.physics == nil then
        PocketMap.Physics.Prepare(mini, function() end)
        return nil
    end
    local trace = mini.effectTrace or PocketMap.Walk.CollisionSession(mini)
    mini.effectTrace = trace
    local mask = bit.band(MASK_SOLID, bit.bnot(bit.bor(CONTENTS_MONSTER, CONTENTS_GRATE)))
    local hit = trace:TraceHull(effect.origin, effect.origin - DOWN, ZERO, ZERO, mask)
    effect.dropped = Vector(hit.HitPos.x, hit.HitPos.y, hit.HitPos.z)
    return effect.dropped
end

local function drawFire(mini, effect)
    local origin = fireOrigin(mini, effect)
    if not origin then return end
    if not IsValid(effect.particle) then
        if not precached[effect.system] then PrecacheParticleSystem(effect.system) precached[effect.system] = true end
        effect.particle = CreateParticleSystemNoEntity(effect.system, origin, effect.angles)
        if not IsValid(effect.particle) then return end
        effect.particle:SetShouldDraw(false)
    end
    effect.particle:Render()
end

-- env_smokestack predates PCFs. Use its map material and emission parameters
-- with Source's particle emitter, replacing the fixed six decorative sprites.
local function drawSmoke(effect)
    if not IsValid(effect.emitter) then
        effect.emitter = ParticleEmitter(effect.origin)
        if not IsValid(effect.emitter) then return end
        effect.emitter:SetNoDraw(true)
    end
    local now = CurTime()
    local dt = math.Clamp(now - (effect.lastUpdate or now), 0, 0.1)
    if effect.lastFrame ~= FrameNumber() then
        effect.lastUpdate, effect.lastFrame = now, FrameNumber()
        effect.pending = (effect.pending or 0) + dt * effect.rate
        local count = math.floor(effect.pending)
        effect.pending = effect.pending - count
        local right, forward, up = effect.angles:Right(), effect.angles:Forward(), effect.angles:Up()
        for _ = 1, count do
            local angle = math.Rand(0, math.pi * 2)
            local position = effect.origin + (right * math.cos(angle) + forward * math.sin(angle)) * effect.baseSpread
            local p = effect.emitter:Add(effect.material, position)
            if p then
                p:SetVelocity(up * effect.speed + right * math.Rand(-effect.spread, effect.spread) + forward * math.Rand(-effect.spread, effect.spread))
                p:SetGravity(effect.wind)
                p:SetDieTime(effect.lifetime)
                p:SetStartSize(effect.startSize) p:SetEndSize(effect.endSize)
                p:SetStartAlpha(0) p:SetEndAlpha(0)
                p:SetColor(effect.color.x, effect.color.y, effect.color.z)
                p:SetRoll(math.Rand(0, math.pi * 2)) p:SetRollDelta(math.Rand(-effect.roll, effect.roll))
                local lastThink = now
                p:SetThinkFunction(function(particle)
                    local t = particle:GetLifeTime() / effect.lifetime
                    local alpha = (1 - math.cos(t * math.pi * 2)) * 0.5
                    if t > 0.5 then alpha = alpha * alpha end
                    particle:SetStartAlpha(alpha * effect.alpha) particle:SetEndAlpha(alpha * effect.alpha)
                    local time = CurTime()
                    if effect.twist ~= 0 then
                        local position = particle:GetPos() - effect.origin
                        local angle = effect.twist * (time - lastThink)
                        local c, s = math.cos(angle), math.sin(angle)
                        particle:SetPos(effect.origin + Vector(position.x * c + position.y * s, position.y * c - position.x * s, position.z))
                    end
                    lastThink = time
                    particle:SetNextThink(time)
                end)
                p:SetNextThink(now)
            end
        end
    end
    effect.emitter:Draw()
end

function Effects.Draw(mini, pvs, view, partVisible)
    -- Native particle renderers need the regular translucent render context,
    -- outside the block's entity/light/stencil callbacks.
    if render.GetRenderTarget() then return end
    mini.effectsView = { frame = FrameNumber(), pvs = pvs, view = view, partVisible = partVisible,
        eye = EyePos(), angles = EyeAngles(), camera = render.GetViewSetup() }
end

local function renderEffects(mini, setup)
    local visible = {}
    for _, effect in ipairs(mini.effects or {}) do
        if not isActive(mini, effect) then stop(effect)
        elseif (not setup.pvs or not effect.cluster or setup.pvs[effect.cluster])
            and (not setup.view or setup.partVisible(effect, setup.view)) then
            visible[#visible + 1] = effect
        end
    end
    mini.effectsDrawn, mini.effectSpritesDrawn = #visible, 0
    if #visible == 0 then return end
    local camera = setup.camera
    local eye = (mini.ent:WorldToLocal(setup.eye) - mini.boxCenter) / mini.scale + mini.mapCenter
    local angles = mini.ent:WorldToLocalAngles(setup.angles)
    cam.Start3D(eye, angles, camera.fov, camera.x, camera.y, camera.width, camera.height, camera.znear / mini.scale, camera.zfar / mini.scale)
    cam.PushModelMatrix(Matrix())
    render.OverrideDepthEnable(true, false)
    local ok, err = pcall(function()
        for _, effect in ipairs(visible) do
            if effect.kind == "smoke" then drawSmoke(effect) else drawFire(mini, effect) end
        end
    end)
    cam.PopModelMatrix()
    cam.End3D()
    render.OverrideDepthEnable(false)
    if not ok then error(err, 0) end
end

hook.Add("PostDrawTranslucentRenderables", "PocketMap_Effects", function(depth, sky)
    if depth or sky or render.GetRenderTarget() then return end
    for mini in pairs(PocketMap.Active or {}) do
        local setup = mini.effectsView
        if setup and setup.frame == FrameNumber() and mini.state == "ready" then
            mini.effectsView = nil
            renderEffects(mini, setup)
        end
    end
end)

game.AddParticles("particles/fire_01.pcf")
-- Auto-refresh releases old emitters before rebuilding their effect records.
for mini in pairs(PocketMap.Active or {}) do
    if mini.bsp and mini.state == "ready" then Effects.Build(mini, mini.bsp:GetEntities()) end
end
