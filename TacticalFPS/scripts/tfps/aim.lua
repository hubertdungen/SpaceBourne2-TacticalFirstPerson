--[[
  Aiming in first person (see DESIGN.md).

   * ADS "Zoom": aim lowers FirstPersonFOV (smooth blend, per weapon group). Safe default:
     the game fires from the camera centre, so the shot always goes where you look.
   * Scoped weapons (Sniper, Hunter): in first person the game zooms the weapon's camera while
     the view stays on the head, so the zoom would be lost. We move the view to the weapon,
     exactly as the game does in third person, and back on release.
   * Crosshair: hidden (or scaled) in first person; the weapon re-adds it on every equip.
]]

local U = require("tfps.util")
local G = require("tfps.gamedefs")
local P = G.P

local A = { busy = false, fovFrom = 90, fovTo = 90, t0 = 0, dur = 0.15, crosshairAt = nil, savedVis = nil, aiming = false,
    sightDone = {}, dotOn = false, sightLoc = nil, hold = false }

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

-- Aiming down the sights: every hand weapon has its own camera, placed by the game per class
-- (AimTransform, in weapon-root space) behind the sights and looking down the barrel. Shots
-- start at the active camera and follow its forward vector, so with the view on that camera
-- the bullets go where the sights point. Only classes checked in game are used
-- (G.SightCamera, with a height fix); the others zoom at the eyes.
local function setSightCamera(w)
    local fix = G.SightCamera[U.className(w) or ""]
    local cam = U.get(w, P.WeaponCamera)
    local t = U.get(w, "AimTransform")
    local tr = t and t.Translation
    if not (fix and U.valid(cam) and tr) then return false end
    local loc = { X = tr.X + (fix.X or 0), Y = tr.Y + (fix.Y or 0), Z = tr.Z + (fix.Z or 0) }
    if not A.sightDone[U.addr(w) or 0] then
        -- The game's aim timeline lerps the camera from IdleTramsfom to AimTransform: make both the sight.
        local nt = { Rotation = t.Rotation, Translation = loc, Scale3D = { X = 1, Y = 1, Z = 1 } }
        U.set(w, "AimTransform", nt)
        U.set(w, "IdleTramsfom", nt)
        A.sightDone[U.addr(w) or 0] = true
    end
    pcall(function() cam:K2_SetRelativeLocation(loc, false, {}, false) end)
    -- The game's aim timeline moves the camera back while it plays: re-applied every frame
    -- while aiming (A.update).
    A.sightLoc, A.hold = loc, true
    local fov = cfg().ADS.ZoomFOV[groupOf(w)] or cfg().FOV
    U.set(w, "CacheFOV", fov)
    pcall(function() cam:SetFieldOfView(fov) end)
    return true
end

-- Small centre dot while aiming with a weapon that has no usable sights (zoom aiming), so you
-- never aim blind. Only when the crosshair is otherwise hidden in first person.
local function aimDot(p, on)
    if not (cfg().AimDot and cfg().Crosshair == "Hidden") then return end
    local ch = U.get(p, P.Crosshair)
    if not U.valid(ch) then return end
    pcall(function() ch:SetCrosshairScale(on and cfg().CrosshairScale or 1.0) end)
    local ok, child = pcall(function() return ch:GetCrosshairChild() end)
    if ok and U.valid(child) then
        pcall(function() child:SetVisibility(on and (A.savedVis or G.Slate.HitTestInvisible) or G.Slate.Hidden) end)
    end
end

-- Crosshair widget (WB_CrosshairBase_C). Only its crosshair child is touched, so hit and
-- damage indicators keep working.
local function applyCrosshair(p, fp)
    local mode = cfg().Crosshair
    if mode == "Game" then return end
    local ch = U.get(p, P.Crosshair)
    if not U.valid(ch) then return end
    if mode == "Small" then
        pcall(function() ch:SetCrosshairScale(fp and cfg().CrosshairScale or 1.0) end)
        return
    end
    local ok, child = pcall(function() return ch:GetCrosshairChild() end)
    if not (ok and U.valid(child)) then return end
    if fp then
        if A.savedVis == nil then
            local okv, v = pcall(function() return child:GetVisibility() end)
            A.savedVis = okv and v or G.Slate.HitTestInvisible
        end
        pcall(function() child:SetVisibility(G.Slate.Hidden) end)
    elseif A.savedVis ~= nil then
        pcall(function() child:SetVisibility(A.savedVis) end)
        A.savedVis = nil
    end
end

-- view.lua calls this after entering (fp = true) or leaving first person.
function A.onViewChanged(p, fp, V)
    if not fp then
        if V.viewOnWeapon then viewWeapon(p, nil, V, false) end
        A.aiming, A.busy, A.hold, A.sightLoc = false, false, false, nil
    end
    applyCrosshair(p, fp)
end

-- Post-hook Q1_Character:RMB(Relesed?): aim pressed (false) or released (true).
function A.onRMB(self, released, V)
    if not V.isFP then return end
    local p = self:get()
    local w = weaponOf(p)
    if not w then return end
    local group, now = groupOf(w), os.clock()
    if not released:get() then
        A.aiming = true
        if group == "Scoped" then
            viewWeapon(p, w, V, true)
        elseif cfg().ADS.Mode == "Sights" and setSightCamera(w) then
            U.log("aim down the sights: " .. U.className(w))
            viewWeapon(p, w, V, true)
        else
            blendTo(p, cfg().ADS.ZoomFOV[group] or cfg().FOV, now)
            aimDot(p, true)
            A.dotOn = true
        end
    else
        A.aiming = false
        if V.viewOnWeapon then viewWeapon(p, w, V, false) end
        A.sightLoc, A.hold = nil, false
        if A.dotOn then aimDot(p, false); A.dotOn = false end
        blendTo(p, cfg().FOV, now)
    end
    V.dirty = true -- the game resets the pose on release; put the weapon back up at once
end

-- Post-hook Master_Hand_Weapon:Play_Equip_Sound. The weapon's init runs >= 0.1 s later and
-- re-adds the crosshair, so apply our crosshair setting a little after that.
function A.onEquip()
    U.log("weapon equip")
    A.crosshairAt = os.clock() + 0.4
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
    if A.crosshairAt and now >= A.crosshairAt then
        A.crosshairAt = nil
        applyCrosshair(p, V.isFP)
    end
end

return A
