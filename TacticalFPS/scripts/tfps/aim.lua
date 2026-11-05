--[[
  Aiming in first person (see DESIGN.md).

   * ADS "Sights": rifles and shotguns put the view on the weapon's own sight camera, moved
     behind the real sight (G.SightCamera). Shots start at the active camera, so they go where
     the sight points.
   * ADS "Zoom": aim lowers FirstPersonFOV (smooth blend, per weapon group), with a small dot.
   * Scoped weapons (Sniper, Hunter): in first person the game zooms the weapon's camera while
     the view stays on the head, so the zoom would be lost. We move the view to the weapon,
     exactly as the game does in third person, and back on release.
   * Reticles: the game's crosshair (Clear HUD's reticle lives inside it) and the HUD's small
     blue crosshair are hidden in first person and always while aiming down the sights; the
     game re-shows them (every equip, aim events), so they are re-checked a few times a second.
]]

local U = require("tfps.util")
local G = require("tfps.gamedefs")
local P = G.P

local A = { busy = false, fovFrom = 90, fovTo = 90, t0 = 0, dur = 0.15, aiming = false,
    aimMode = nil,      -- "sight", "scope" or "zoom" while aiming
    sightBase = {}, sightWritten = {}, sightLoc = nil, hold = false,
    savedVis = nil, hudSaved = nil, scale = nil, reticleAt = 0 }

local function cfg() return TFPS.cfg end

local function weaponOf(p) -- the live Master_Hand_Weapon_C in hand, or nil
    local comp = U.get(p, P.Weapon)
    if not U.valid(comp) then return nil end
    local w = U.get(comp, "ChildActor")
    return U.valid(w) and w or nil
end

local function groupOf(w) return G.WeaponGroup[U.className(w) or ""] or "Rifle" end

-- FOV blend, stepped every frame by A.update while busy.
local function blendTo(p, target, now)
    A.fovFrom = U.get(p, P.FirstPersonFOV, cfg().FOV)
    A.fovTo, A.t0, A.dur = target, now, math.max(cfg().ADS.BlendSeconds, 0.001)
    A.busy = true
end

local function stepBlend(p, now)
    local k = math.min((now - A.t0) / A.dur, 1)
    k = k * k * (3 - 2 * k) -- smoothstep
    U.set(p, P.FirstPersonFOV, A.fovFrom + (A.fovTo - A.fovFrom) * k)
    if k >= 1 then A.busy = false end
end

-- View on the weapon's sight camera (on = true) or back on the player (on = false).
local function viewWeapon(p, w, V, on)
    local pc = U.playerController(p)
    if not pc then return end
    local target = on and w or p
    if U.valid(target) and pcall(function() pc:SetViewTargetWithBlend(target, cfg().ADS.BlendSeconds, 0, 0, false) end) then
        V.viewOnWeapon = on
    end
end

-- Sight fix for a weapon class. With Debug on, Mods\TacticalFPS\sight_tune.txt ("Class X Y Z"
-- per line) overrides it, read on every aim press: used to calibrate new weapons in game.
local function sightFix(cls)
    if U.Verbose then
        local f = io.open(U.Dir .. "sight_tune.txt", "r")
        if f then
            for line in f:lines() do
                local c, x, y, z = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
                if c == cls then
                    f:close()
                    return { X = tonumber(x) or 0, Y = tonumber(y) or 0, Z = tonumber(z) or 0 }
                end
            end
            f:close()
        end
    end
    return G.SightCamera[cls]
end

-- Some sight cameras are turned away from the barrel in the blueprint (both shotguns: yaw 5),
-- so the holo sight sat off the screen centre and the gun looked skewed. While aiming, the
-- camera looks straight down the barrel; its own rotation comes back once the view has left it.
local ZERO_ROT = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }

local function restoreCamera()
    local c = A.camRot
    A.camRot, A.camRestoreAt = nil, nil
    if c and U.valid(c.cam) then
        pcall(function() c.cam:K2_SetRelativeRotation(c.rot, false, {}, false) end)
    end
end

local function straightenCamera(cam)
    local key = U.addr(cam)
    if A.camRot and A.camRot.key ~= key then restoreCamera() end
    if not A.camRot then
        local ok, rot = pcall(function()
            local r = cam.RelativeRotation
            return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
        end)
        if not ok or math.abs(rot.Pitch) + math.abs(rot.Yaw) + math.abs(rot.Roll) < 0.01 then return end
        A.camRot = { cam = cam, key = key, rot = rot }
    end
    A.camRestoreAt = nil
    pcall(function() cam:K2_SetRelativeRotation(ZERO_ROT, false, {}, false) end)
end

-- Aiming down the sights: every hand weapon has its own camera, placed by the game
-- (AimTransform, in weapon-root space) and looking down the barrel. Shots start at the active
-- camera and follow its forward vector, so with the view on that camera the bullets go where
-- the sights point. Only classes checked in game are used (G.SightCamera, with a position fix);
-- the others zoom at the eyes.
local function setSightCamera(w)
    local cls = U.className(w) or ""
    local fix = sightFix(cls)
    local cam = U.get(w, P.WeaponCamera)
    local t = U.get(w, "AimTransform")
    if not (fix and U.valid(cam) and t and t.Translation) then return false end
    local key = tostring(U.addr(w) or 0) .. cls
    local base = A.sightBase[key]
    if not base then -- the game's own value, before we ever write it
        local tr = t.Translation
        base = { X = tr.X, Y = tr.Y, Z = tr.Z }
        A.sightBase[key] = base
    end
    local loc = { X = base.X + (fix.X or 0), Y = base.Y + (fix.Y or 0), Z = base.Z + (fix.Z or 0) }
    local sig = string.format("%.2f %.2f %.2f", loc.X, loc.Y, loc.Z)
    if A.sightWritten[key] ~= sig then
        -- The game's aim timeline lerps the camera from IdleTramsfom to AimTransform: make both the sight.
        local nt = { Rotation = t.Rotation, Translation = loc, Scale3D = { X = 1, Y = 1, Z = 1 } }
        U.set(w, "AimTransform", nt)
        U.set(w, "IdleTramsfom", nt)
        A.sightWritten[key] = sig
    end
    pcall(function() cam:K2_SetRelativeLocation(loc, false, {}, false) end)
    straightenCamera(cam)
    -- The game's aim timeline moves the camera back while it plays: re-applied every frame
    -- while aiming (A.update).
    A.sightLoc, A.hold = loc, true
    local fov = cfg().ADS.ZoomFOV[groupOf(w)] or cfg().FOV
    U.set(w, "CacheFOV", fov)
    pcall(function() cam:SetFieldOfView(fov) end)
    U.log("aim down the sights: " .. cls .. " at " .. sig)
    return true
end

-- Which reticles we hide now: the game's crosshair (and Clear HUD's inside it), the HUD's one.
local function wantHidden(V)
    if not V.isFP then return false, false end
    if A.aimMode == "sight" or A.aimMode == "scope" then return true, true end
    if cfg().Crosshair ~= "Hidden" then return false, false end
    -- zoom aiming: the game's crosshair, made small, is the one centre dot
    if A.aimMode == "zoom" and cfg().AimDot then return false, true end
    return true, true
end

-- The game's on-foot crosshair (WB_CrosshairBase_C). Only its crosshair child is touched, so
-- hit and damage indicators keep working.
local function setCrosshair(p, hide)
    local ch = U.get(p, P.Crosshair)
    if not U.valid(ch) then return end
    local ok, child = pcall(function() return ch:GetCrosshairChild() end)
    if not (ok and U.valid(child)) then return end
    if hide then
        if A.savedVis == nil then
            local okv, v = pcall(function() return child:GetVisibility() end)
            local shown = okv and v ~= G.Slate.Hidden and v ~= G.Slate.Collapsed
            A.savedVis = shown and v or G.Slate.HitTestInvisible
        end
        pcall(function() child:SetVisibility(G.Slate.Hidden) end)
    elseif A.savedVis ~= nil then
        pcall(function() child:SetVisibility(A.savedVis) end)
        A.savedVis = nil
    end
end

-- The HUD's own small blue crosshair (Q1Hud.CHWidget). ctx: any live object in the world.
local function setHudReticle(ctx, hide)
    if not hide and A.hudSaved == nil then return end
    local pc = U.playerController(ctx)
    local ok, hud = pcall(function() return pc:GetHUD() end)
    local w = ok and U.valid(hud) and U.get(hud, P.HudReticle) or nil
    if not U.valid(w) then return end
    if hide then
        if A.hudSaved == nil then
            local okv, v = pcall(function() return w:GetVisibility() end)
            local shown = okv and v ~= G.Slate.Hidden and v ~= G.Slate.Collapsed
            A.hudSaved = shown and v or G.Slate.HitTestInvisible
        end
        pcall(function() w:SetVisibility(G.Slate.Hidden) end)
    else
        pcall(function() w:SetVisibility(A.hudSaved) end)
        A.hudSaved = nil
    end
end

function A.applyReticles(p, V)
    local hideMain, hideHud = wantHidden(V)
    setCrosshair(p, hideMain) -- showing only gives back what we hid ("Game" mode: only while aiming)
    setHudReticle(p, hideHud)
    local mode, scale = cfg().Crosshair, 1.0
    if V.isFP and (mode == "Small" or (mode == "Hidden" and A.aimMode == "zoom")) then scale = cfg().CrosshairScale end
    if scale ~= A.scale then
        local ch = U.get(p, P.Crosshair)
        if U.valid(ch) and pcall(function() ch:SetCrosshairScale(scale) end) then A.scale = scale end
    end
end

-- Called when the possessed pawn is no longer the player (ship, vehicle): the HUD is shared.
function A.restoreHud(ctx)
    setHudReticle(ctx, false)
end

-- view.lua calls this after entering (fp = true) or leaving first person.
function A.onViewChanged(p, fp, V)
    if not fp then
        if V.viewOnWeapon then viewWeapon(p, nil, V, false) end
        A.aiming, A.aimMode, A.busy, A.hold, A.sightLoc = false, nil, false, false, nil
        restoreCamera()
    end
    A.reticleAt = 0 -- reticles on the next update (spreads the work over two frames)
end

-- Called by view.lua when the player dies: drop every aiming state, no engine calls. The saved
-- reticle states stay, so the next update can give them back.
function A.reset()
    A.aiming, A.aimMode, A.busy, A.hold, A.sightLoc, A.scale = false, nil, false, false, nil, nil
    A.sightBase, A.sightWritten = {}, {}
    A.camRot, A.camRestoreAt = nil, nil -- the weapon is rebuilt on respawn
end

-- Post-hook Q1_Character:RMB(Relesed?): aim pressed (false) or released (true). The game's
-- gamepad aim (ALS_Base GPC_Aim) calls the same event.
function A.onRMB(self, released, V)
    if not V.isFP or os.clock() < V.deadUntil then return end
    local p = self:get()
    local w = weaponOf(p)
    if not w then return end
    local group, now = groupOf(w), os.clock()
    if not released:get() then
        A.aiming = true
        if group == "Scoped" then
            viewWeapon(p, w, V, true)
            A.aimMode = "scope"
        elseif cfg().ADS.Mode == "Sights" and setSightCamera(w) then
            viewWeapon(p, w, V, true)
            A.aimMode = "sight"
        else
            blendTo(p, cfg().ADS.ZoomFOV[group] or cfg().FOV, now)
            A.aimMode = "zoom"
        end
    else
        A.aiming, A.aimMode = false, nil
        if V.viewOnWeapon then viewWeapon(p, w, V, false) end
        A.sightLoc, A.hold = nil, false
        -- turned back after the view has blended off the weapon camera (no swing on the way)
        if A.camRot then A.camRestoreAt = now + cfg().ADS.BlendSeconds + 0.1 end
        blendTo(p, cfg().FOV, now)
    end
    A.applyReticles(p, V)
    A.reticleAt = now + 0.05
    V.dirty = true -- the game resets the pose on release; put the weapon back up at once
end

-- Post-hook Master_Hand_Weapon:Play_Equip_Sound. The weapon's init runs >= 0.1 s later and
-- re-adds the crosshair, so check the reticles a little after that.
function A.onEquip()
    A.reticleAt = os.clock() + 0.4
    A.scale = nil -- the new crosshair starts at the game's scale
end

-- Called from view.lua on every player update (every frame while busy).
function A.update(p, now, V)
    if A.busy then stepBlend(p, now) end
    if A.hold then
        local w = V.viewOnWeapon and weaponOf(p)
        local cam = w and U.get(w, P.WeaponCamera)
        if U.valid(cam) and A.sightLoc then
            pcall(function() cam:K2_SetRelativeLocation(A.sightLoc, false, {}, false) end)
        else
            A.sightLoc, A.hold = nil, false
        end
    end
    if A.camRestoreAt and now >= A.camRestoreAt and not A.aiming then restoreCamera() end
    if A.reticleAt and now >= A.reticleAt then
        -- keep checking while in first person: the game re-shows them (aim events, equips)
        A.reticleAt = V.isFP and (now + (A.aiming and 0.05 or 0.25)) or nil
        A.applyReticles(p, V)
    end
end

return A
