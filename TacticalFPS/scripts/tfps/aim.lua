--[[
  Aiming in first person (see DESIGN.md).

   * ADS "Sights": rifles, shotguns and pistols put the view on the weapon's own sight camera,
     moved behind the real sight (G.SightCamera). Shots start at the active camera, so they go
     where the sight points. The game's own aim timeline moves that camera on every aim press
     and release; ours is put back right after it, frame by frame (A.onAimTimeline).
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
    sightBase = {}, sightLoc = nil, sightFov = nil, hold = false,
    sightWeapon = nil,  -- address of the weapon whose sight camera we hold
    leaving = false,    -- released: the view is blending back to the player (A.update ends it)
    leaveUntil = nil,   -- os.clock() safety limit for that
    waiting = false,    -- aim pressed, gun not up yet (weapon switch, or held low): starts once it is
    raiseFrom = 0,      -- os.clock() when the gun started coming up for that aim
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

-- True while the camera manager blends from one view target to another.
local function blending(pc)
    local ok, t = pcall(function() return pc.PlayerCameraManager.PendingViewTarget.Target end)
    return ok and U.valid(t)
end

-- View on the weapon's sight camera (on = true) or back on the player (on = false), blended.
-- V.viewOnWeapon stays true until the view is back on the player (A.update), so view.lua never
-- mistakes our own blend for the game's (it would cut it short).
-- Turning around mid-blend (quick clicks): asked for the target it is leaving, the engine drops
-- the blend and jumps there, and it ignores a target that is already pending. So, all before the
-- frame is drawn: drop the blend, take the other target at once, then blend to ours from the
-- picture shown last frame (outgoing view locked): no jump either way.
local function viewWeapon(p, w, V, on)
    local pc = U.playerController(p)
    if not pc then return end
    local target, other = on and w or p, on and p or w
    if not U.valid(target) then return end
    local mid = blending(pc) and U.valid(other)
    local ok = pcall(function()
        if mid then
            pc:SetViewTargetWithBlend(target, 0, 0, 0, false)
            pc:SetViewTargetWithBlend(other, 0, 0, 0, false)
        end
        pc:SetViewTargetWithBlend(target, cfg().ADS.BlendSeconds, 0, 0, mid)
    end)
    if ok then
        V.viewOnWeapon = true
        A.leaving = not on
        A.leaveUntil = (not on) and (os.clock() + cfg().ADS.BlendSeconds + 1.0) or nil
    end
end

-- Sight fix for a weapon class. With Debug on, Mods\TacticalFPS\sight_tune.txt overrides it, read
-- on every aim press: used to calibrate new weapons in game. One line per class:
-- "Class X Y Z" (offset from the game's camera) or "Class pos X Y Z" (fixed position).
local function sightFix(cls)
    if U.Verbose then
        local f = io.open(U.Dir .. "sight_tune.txt", "r")
        if f then
            for line in f:lines() do
                local c, x, y, z = line:match("^(%S+)%s+pos%s+(%S+)%s+(%S+)%s+(%S+)")
                local abs = c ~= nil
                if not abs then c, x, y, z = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)") end
                if c == cls then
                    f:close()
                    local v = { X = tonumber(x) or 0, Y = tonumber(y) or 0, Z = tonumber(z) or 0 }
                    return abs and { Pos = v } or v
                end
            end
            f:close()
        end
    end
    return G.SightCamera[cls]
end

-- Some sight cameras are turned away from the barrel in the blueprint (both shotguns: yaw 5,
-- pistols: yaw 90), so the sight sat off the screen centre or out of view. While aiming, the
-- camera looks straight down the barrel; its own rotation comes back once the view has left it.
local ZERO_ROT = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }

local function restoreCamera()
    local c = A.camRot
    A.camRot = nil
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
    local loc
    if fix.Pos then -- the game's camera is unusable for this class: a fixed position
        loc = { X = fix.Pos.X, Y = fix.Pos.Y, Z = fix.Pos.Z }
    else
        local base = A.sightBase[key]
        if not base then -- the game's own value, before we ever write it
            local tr = t.Translation
            base = { X = tr.X, Y = tr.Y, Z = tr.Z }
            A.sightBase[key] = base
        end
        loc = { X = base.X + (fix.X or 0), Y = base.Y + (fix.Y or 0), Z = base.Z + (fix.Z or 0) }
    end
    local sig = string.format("%.2f %.2f %.2f", loc.X, loc.Y, loc.Z)
    -- (Writing our place into the weapon's AimTransform/IdleTramsfom does not work: UE4SS
    -- cannot set those structs from Lua, checked in game. Hence the timeline hook.)
    pcall(function() cam:K2_SetRelativeLocation(loc, false, {}, false) end)
    straightenCamera(cam)
    -- The game's aim timeline writes the camera's place and turn on every frame it plays (press
    -- and release): ours goes back right after it (A.onAimTimeline) and on every update until
    -- the view is back on the player (A.update), whatever order things tick in.
    A.sightLoc, A.hold, A.sightWeapon = loc, true, U.addr(w)
    local fov = cfg().ADS.ZoomFOV[groupOf(w)] or cfg().FOV
    U.set(w, "CacheFOV", fov)
    pcall(function() cam:SetFieldOfView(fov) end)
    A.sightFov = fov
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
-- Widgets are only written when their visibility really changes (0.1.7): these checks run up
-- to 20 times a second, and the HUD's widget trees are shared with other mods (Clear HUD).
local function setCrosshair(p, hide)
    local ch = U.get(p, P.Crosshair)
    if not U.valid(ch) then return end
    local ok, child = pcall(function() return ch:GetCrosshairChild() end)
    if not (ok and U.valid(child)) then return end
    if hide then
        local okv, v = pcall(function() return child:GetVisibility() end)
        if A.savedVis == nil then
            local shown = okv and v ~= G.Slate.Hidden and v ~= G.Slate.Collapsed
            A.savedVis = shown and v or G.Slate.HitTestInvisible
        end
        if not (okv and v == G.Slate.Hidden) then pcall(function() child:SetVisibility(G.Slate.Hidden) end) end
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
        local okv, v = pcall(function() return w:GetVisibility() end)
        if A.hudSaved == nil then
            local shown = okv and v ~= G.Slate.Hidden and v ~= G.Slate.Collapsed
            A.hudSaved = shown and v or G.Slate.HitTestInvisible
        end
        if not (okv and v == G.Slate.Hidden) then pcall(function() w:SetVisibility(G.Slate.Hidden) end) end
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
        if V.viewOnWeapon and not A.leaving then viewWeapon(p, weaponOf(p), V, false) end
        A.aiming, A.aimMode, A.busy, A.waiting = false, nil, false, false
        if not A.leaving then -- else A.update hands the camera back once the view is home
            V.viewOnWeapon, A.hold, A.sightLoc, A.sightWeapon = false, false, nil, nil
            restoreCamera()
        end
    end
    A.reticleAt = 0 -- reticles on the next update (spreads the work over two frames)
end

-- Called by view.lua when the player dies: drop every aiming state, no engine calls. The saved
-- reticle states stay, so the next update can give them back.
function A.reset()
    A.aiming, A.aimMode, A.busy, A.hold, A.sightLoc, A.scale = false, nil, false, false, nil, nil
    A.sightBase = {}
    A.camRot, A.leaving, A.leaveUntil, A.sightWeapon, A.waiting = nil, false, nil, nil, false -- the weapon is rebuilt on respawn
end

-- Weapons held low until you aim (cfg LowReady, pistols by default; with WeaponUp off, all).
function A.lowReady(w)
    local mode = cfg().LowReady or "None"
    if mode == "All" or cfg().WeaponUp == false then return true end
    return mode == "Pistols" and groupOf(w) == "Pistol"
end

-- True while the gun must be up (view.lua's weapon pose): aiming, about to, or the view still
-- on its sight on the way back.
function A.wantsGunUp()
    return A.aiming or A.waiting or A.leaving
end

-- The gun points where you look: ALS's aiming pose reached, its straightened sight camera
-- within 3 degrees of the aim (measured in game: within 0.3 degrees in the aiming pose). With no
-- sight camera to measure, a short raise time instead. The sight view starts only then, so it
-- never rides the gun on its way up (or stays at the eyes while you sprint).
local function gunReady(p, w, now)
    if U.get(p, P.RotationMode, 0) ~= G.RotationMode.Aiming then return false end
    local cam = A.sightLoc and U.addr(w) == A.sightWeapon and U.get(w, P.WeaponCamera)
    local pc = U.playerController(p)
    if not (U.valid(cam) and pc) then return now - A.raiseFrom > 0.35 end
    local ok, off = pcall(function()
        local r, c = cam:K2_GetComponentRotation(), pc:GetControlRotation()
        return math.max(math.abs((r.Yaw - c.Yaw + 540) % 360 - 180), math.abs((r.Pitch - c.Pitch + 540) % 360 - 180))
    end)
    return (ok and off < 3) or now - A.raiseFrom > 0.8
end

-- Aiming with weapon w puts the view on a sight (scope or sight camera, placed now if needed).
local function sightView(w)
    if groupOf(w) == "Scoped" then return true end
    return cfg().ADS.Mode == "Sights" and ((A.sightLoc ~= nil and U.addr(w) == A.sightWeapon) or setSightCamera(w))
end

-- Aiming starts with weapon w: on the press, or once the gun is up.
local function startAim(p, w, V, now)
    local group = groupOf(w)
    A.waiting = false
    if group == "Scoped" then
        viewWeapon(p, w, V, true)
        A.aimMode = "scope"
    elseif sightView(w) then
        viewWeapon(p, w, V, true)
        A.aimMode = "sight"
    else
        blendTo(p, cfg().ADS.ZoomFOV[group] or cfg().FOV, now)
        A.aimMode = "zoom"
    end
end

-- Aiming stops: on the release, or when the game drops the aim by itself (A.update). The view
-- blends back to the player; the sight camera stays put and straight until the view has fully
-- left it (A.update), then gets the game's own turn back: no swing.
local function stopAim(p, w, V, now)
    A.aiming, A.aimMode, A.waiting = false, nil, false
    if V.viewOnWeapon and not A.leaving then viewWeapon(p, w, V, false) end
    if not A.leaving then A.sightLoc, A.hold, A.sightWeapon = nil, false, nil; restoreCamera() end
    blendTo(p, cfg().FOV, now)
end

-- Post-hook Q1_Character:RMB(Relesed?): aim pressed (false) or released (true). The game's
-- gamepad aim (ALS_Base GPC_Aim) calls the same event.
function A.onRMB(self, released, V)
    if not V.isFP or os.clock() < V.deadUntil then return end
    local p = self:get()
    local w = weaponOf(p)
    if not w then return end
    local now = os.clock()
    if not released:get() then
        A.aiming = true
        -- Pressed while a weapon is being drawn or put away (the game ignores it), or with the
        -- gun held low (LowReady): view.lua raises it, and the sight view starts once it points
        -- ahead (A.update), so it never rides the gun's swing.
        A.raiseFrom = now
        if U.get(p, P.SwitchingWeapon, false) or (sightView(w) and not gunReady(p, w, now)) then
            A.waiting = true
        else
            startAim(p, w, V, now)
        end
    else
        stopAim(p, w, V, now)
    end
    A.applyReticles(p, V)
    A.reticleAt = now + 0.05
    V.dirty = true -- the game resets the pose on release; put the weapon back up at once
end

-- True while aim.lua needs an update every frame (view.lua polls faster then).
function A.wantsFrames()
    return A.busy or A.hold or A.leaving or A.waiting
end

-- Post-hook Master_Hand_Weapon:Play_Equip_Sound. The weapon's init runs >= 0.1 s later and
-- re-adds the crosshair, so check the reticles a little after that.
function A.onEquip()
    A.reticleAt = os.clock() + 0.4
    A.scale = nil -- the new crosshair starts at the game's scale
end

-- Post-hook Master_Hand_Weapon:Timeline_1__UpdateFunc. The game's aim timeline has just set the
-- sight camera's place, turn and zoom (lerped from the blueprint's IdleTramsfom to AimTransform:
-- on pistols turned 90 degrees and 22 cm aside). Until 0.1.5 our per-update hold and the timeline
-- took turns depending on tick order, so the view flicked sideways while it played (0.25 s on
-- each press and release). Ours goes back here, after the game's, before the frame is drawn.
function A.onAimTimeline(self)
    if not A.sightLoc then return end
    local w = self:get()
    if U.addr(w) ~= A.sightWeapon then return end
    local cam = U.get(w, P.WeaponCamera)
    if U.valid(cam) then
        pcall(function()
            cam:K2_SetRelativeLocationAndRotation(A.sightLoc, ZERO_ROT, false, {}, false)
            if A.sightFov then cam:SetFieldOfView(A.sightFov) end
        end)
    end
end

-- Called from view.lua on every player update (every frame while busy).
function A.update(p, now, V)
    if A.busy then stepBlend(p, now) end
    if A.waiting then
        if not (A.aiming and U.get(p, P.AimHeld, false)) then
            stopAim(p, weaponOf(p), V, now) -- let go before the gun was up
        elseif U.get(p, P.SwitchingWeapon, false) then
            A.raiseFrom = now -- the raise is timed from the end of the switch
        else
            local w = weaponOf(p)
            if w and (not sightView(w) or gunReady(p, w, now)) then
                startAim(p, w, V, now)
                A.applyReticles(p, V)
            end
        end
    elseif A.aiming and V.viewOnWeapon and not A.leaving then
        -- The game can drop the aim without a release: a weapon switch clears RMBDown and the
        -- draw/holster swing would carry the sight view with it; or the game takes the view
        -- itself (ForceToTP). Then aiming stops as on a release.
        local w = weaponOf(p)
        local pc = U.playerController(p)
        local vt = nil
        if pc then pcall(function() vt = pc:GetViewTarget() end) end
        if U.get(p, P.SwitchingWeapon, false) or not U.get(p, P.AimHeld, true) or not w
            or U.addr(w) ~= U.addr(vt) then
            local seen = (U.valid(vt) and U.addr(vt) ~= U.addr(p)) and vt or w
            stopAim(p, seen, V, now)
            A.applyReticles(p, V)
        end
    end
    if A.hold then
        local w = weaponOf(p) -- held from the press, before the view gets there (a gun coming up)
        local cam = w and U.addr(w) == A.sightWeapon and U.get(w, P.WeaponCamera)
        if U.valid(cam) and A.sightLoc then -- place and turn in one engine call
            pcall(function() cam:K2_SetRelativeLocationAndRotation(A.sightLoc, ZERO_ROT, false, {}, false) end)
        else
            A.sightLoc, A.hold, A.sightWeapon = nil, false, nil
        end
    end
    if A.leaving then
        -- Released: done once the view is back on the player with no blend left (or after a
        -- safety second). Only then the weapon camera gets the game's own turn back.
        local pc = U.playerController(p)
        local vt = nil
        if pc then pcall(function() vt = pc:GetViewTarget() end) end
        if (pc and U.addr(vt) == U.addr(p) and not blending(pc)) or now > (A.leaveUntil or 0) then
            A.leaving, A.leaveUntil, A.hold, A.sightLoc, A.sightWeapon = false, nil, false, nil, nil
            V.viewOnWeapon = false
            restoreCamera()
            V.dirty = true -- a gun held low (LowReady) goes down now, the view is home
        end
    end
    if A.reticleAt and now >= A.reticleAt then
        -- keep checking while in first person: the game re-shows them (aim events, equips)
        A.reticleAt = V.isFP and (now + (A.aiming and 0.05 or 0.25)) or nil
        A.applyReticles(p, V)
    end
end

return A
