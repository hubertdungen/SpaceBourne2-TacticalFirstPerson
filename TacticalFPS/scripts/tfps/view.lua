--[[
  First / third person on foot (see DESIGN.md).

  How it works:
   * The player picks a view with the game's own camera key (the mod follows the game's
     switch), or an optional mod hotkey; remembered in state.txt: V.wantFP.
   * Entering first person = BPI_Set_ViewMode(1) on the player (the ALS camera then sits at the
     mesh's FP_Camera socket with FirstPersonFOV) + hide head, helmet and hair. The body stays
     visible, so arms and weapon are seen from the eyes ("true first person").
     We do NOT use the game's own toggle (ForceToFP / the camera key): it hides the whole body
     and throws you back to third person as soon as a weapon is out.
   * The game still forces third person by itself (weapon drawn 0.2 s later, dialog, melee,
     ragdoll, hover/jetpack, scope release). Every view change goes through BPI_Set_ViewMode,
     so a post-hook on it marks the state dirty and the next player tick puts first person
     back, as soon as nothing blocks it (V.blockReason).
   * Leaving = BPI_Set_ViewMode(0): Q1_Character restores head/helmet the way the game wants
     them (oxygen, helmet light) and the view target is never touched (cutscene-safe).
   * All work happens in a post-hook on the player's HUD drawing (once per frame), throttled to
     PollSeconds; it runs every frame only while something is pending (dirty, FOV blend, aim).
]]

local U = require("tfps.util")
local G = require("tfps.gamedefs")
local LEAN = require("tfps.lean")
local P = G.P

local V = {
    wantFP = false,       -- the player's choice
    isFP = false,         -- we applied first person and the game has not undone it
    dirty = true,         -- re-check on the next player tick
    ours = false,         -- our own BPI_Set_ViewMode call is running (ignore its hook)
    viewOnWeapon = false, -- aim.lua put the camera on the weapon (scope / sight camera)
    nextPoll = 0, nextFast = 0,
    playerAddr = nil, otherAddr = nil,
    kicks = {}, blockedUntil = 0,
    message = nil,        -- HUD text shown on the next player tick
    keyAt = nil,          -- os.clock() of the last game camera key press
    persist = nil,        -- main.lua: saves wantFP to state.txt
    lastBlock = nil,
    nearOn = false,       -- our near clip plane is set
    poseOurs = false,     -- we put the player in ALS's aiming pose (weapon up)
    deadUntil = 0,        -- os.clock(): no engine calls until then (the player died)
    reloadAt = nil,       -- os.clock() of the last reload (watch the view for a few seconds)
    guardNext = 0,
}

local function cfg() return TFPS.cfg end

-- Weapon up: the game holds a drawn gun low at the hip, below the first-person view. ALS's
-- aiming pose (RotationMode Aiming) holds it at the shoulder, where you see it. Up while aiming
-- (and until the view is back from the sight); at rest up too, unless that weapon is held low
-- until you aim (cfg LowReady: pistols by default). Never while sprinting (ALS cannot sprint
-- while aiming) or in melee.
local function weaponPose(p, A)
    local up = V.isFP and U.get(p, P.WeaponOut, false) and not U.get(p, P.Melee, false)
        and U.get(p, P.DesiredGait, 1) ~= 2
    if up and not A.wantsGunUp() then
        local comp = U.get(p, P.Weapon, nil)
        local w = U.valid(comp) and U.get(comp, "ChildActor", nil)
        up = U.valid(w) and not A.lowReady(w)
    end
    if not up and not V.poseOurs then return end -- not ours to change
    local want = up and G.RotationMode.Aiming or G.RotationMode.Looking
    if U.get(p, P.RotationMode, G.RotationMode.Looking) ~= want then
        U.log("weapon pose -> rotation mode " .. want)
        U.call(p, "BPI_Set_RotationMode", want)
    end
    V.poseOurs = up
end

-- Near clip plane: the game draws nothing closer than 10 cm to the camera, which cuts the
-- collar and the weapon's stock in first person. Lowered only while first person is on.
-- Returns true when it changed the plane (a console command: the engine waits for the renderer).
local function syncNearClip(p)
    local want = V.isFP and cfg().NearClip > 0
    if want == V.nearOn then return false end
    if U.console("r.SetNearClipPlane " .. (want and cfg().NearClip or 10), p) then V.nearOn = want end
    return true
end

-- Debug: name the step when one part of a player update is slow (UE4SS.log "slow hook").
local function timed(name, fn, ...)
    if not U.Verbose then return fn(...) end
    local t0 = os.clock()
    local r = fn(...)
    local ms = (os.clock() - t0) * 1000
    if ms > 3 then U.log(string.format("slow part %s: %.1f ms", name, ms)) end
    return r
end

-- The game's weapon keeps an old sniper-scope rule: 2 s after every reload, if the player's
-- ViewMode is first person, it puts the view on the weapon's own sight camera. In the game that
-- only happens behind a scope. In our first person it threw the view onto the gun held low ("the
-- camera jerks downward after reloading", TheCalcMan), and 0.1.0 then took it for a cutscene and
-- left first person. Now the view goes straight back to the player's eyes.
local function isOwnWeapon(p, vt)
    local comp = U.get(p, P.Weapon, nil)
    local w = U.valid(comp) and U.get(comp, "ChildActor", nil) or nil
    return U.valid(w) and U.addr(w) == U.addr(vt)
end

local function viewBackOnPlayer(p, pc)
    local ok = pcall(function() pc:SetViewTargetWithBlend(p, 0, 0, 0, false) end)
    U.log("the game put the view on the weapon (reload): back on the player " .. tostring(ok))
end

-- Why first person cannot be on right now (nil = it can). Cheap property reads only.
function V.blockReason(p)
    if U.get(p, P.Loading, false) then return "loading" end
    if U.get(p, P.AtDialog, false) then return "dialog" end
    if U.get(p, P.Flying, false) then return "hover/jetpack" end
    if U.get(p, P.InSpace, false) then return "space" end          -- EVA keeps the game's own camera
    if U.get(p, P.FPWalk, false) then return "game walk mode" end   -- the game's forced first-person walk
    if U.get(p, P.Prisoner, false) then return "prisoner" end
    if U.get(p, P.Melee, false) then return "melee" end
    if U.get(p, P.MovementState, 0) == G.MovementState.Ragdoll then return "ragdoll" end
    -- Someone else owns the camera (cutscene, dialog camera, a vehicle...). Never fight it.
    if not V.viewOnWeapon then
        local pc = U.playerController(p)
        local ok, vt = pcall(function() return pc:GetViewTarget() end)
        if ok and U.valid(vt) and U.addr(vt) ~= U.addr(p) then
            if isOwnWeapon(p, vt) then return "weapon camera" end
            return "other camera"
        end
    end
    return nil
end

local HEAD_PARTS = { P.Head, P.Helmet, P.Hair }

-- Hide head parts; re-run while in first person because the game re-shows the helmet
-- (oxygen areas, helmet light). Only calls into the engine when something is visible.
local function hideHead(p)
    for _, name in ipairs(HEAD_PARTS) do
        local comp = U.get(p, name)
        if U.valid(comp) and U.get(comp, "bVisible", true) ~= false then -- unreadable = hide anyway
            pcall(function() comp:SetVisibility(false, false) end)
            if cfg().HeadShadow then pcall(function() comp:SetCastHiddenShadow(true) end) end
        end
    end
end

local function headShadowsOff(p)
    if not cfg().HeadShadow then return end
    for _, name in ipairs(HEAD_PARTS) do
        local comp = U.get(p, name)
        if U.valid(comp) then pcall(function() comp:SetCastHiddenShadow(false) end) end
    end
end

function V.enter(p)
    V.ours = true
    local ok, err = U.call(p, "BPI_Set_ViewMode", G.ViewMode.First)
    V.ours = false
    if not ok then U.warn("BPI_Set_ViewMode(1) failed: " .. tostring(err)); return end
    local mesh = U.get(p, P.Mesh)
    if U.valid(mesh) then
        -- "Hidden" = the game's own look (body hidden).
        pcall(function() mesh:SetVisibility(cfg().Body ~= "Hidden", false) end)
    end
    hideHead(p)
    U.set(p, P.FirstPersonFOV, cfg().FOV)
    V.isFP = true
    U.log("first person on")
end

-- Q1_Character's BPI_Set_ViewMode(0) restores head, helmet and hair the way the game wants
-- them (oxygen, helmet light). Unlike ForceToTP it never touches the view target, so it is
-- safe while a cutscene or dialog camera is active.
function V.leave(p)
    V.ours = true
    local ok, err = U.call(p, "BPI_Set_ViewMode", G.ViewMode.Third)
    V.ours = false
    if not ok then U.warn("BPI_Set_ViewMode(0) failed: " .. tostring(err)) end
    if cfg().Body == "Hidden" then
        local mesh = U.get(p, P.Mesh)
        if U.valid(mesh) then pcall(function() mesh:SetVisibility(true, false) end) end
    end
    headShadowsOff(p)
    V.isFP = false
    U.log("first person off")
end

-- Post-hook on the game's own camera key / button (any of its input events).
-- The game switches the view itself 0.2 s later (and refuses in dialog, while reloading or
-- flying); the next view change decides what the player wants (V.onSetViewMode).
-- The mod never switches on this key itself: both switching would cancel out.
function V.onGameCameraKey()
    V.keyAt = os.clock()
end

-- Post-hook Q1_Character:BPI_Set_ViewMode(NewViewMode). The game changed the view by itself.
function V.onSetViewMode(self, newMode)
    if V.ours or os.clock() < V.deadUntil then return end
    local p = self:get()
    if U.addr(p) ~= V.playerAddr then return end
    local m = newMode:get()
    local now = os.clock()
    V.dirty = true
    -- First view change after the camera key = the player's choice. Going to first person,
    -- the game hides the body (and with a weapon out throws back to third person right away);
    -- the next player tick turns that into our first person.
    if V.keyAt and now - V.keyAt < 0.6 then
        V.keyAt = nil
        local want = (m == G.ViewMode.First)
        if want ~= V.wantFP then
            -- No HUD line: the view change says it, and the game's HUD line beeps on every line
            -- ("tututu" on each camera switch, 2026-11-07).
            V.wantFP, V.blockedUntil, V.kicks = want, 0, {}
            if V.persist then V.persist() end
            U.log("game camera key: first person " .. (want and "on" or "off"))
        end
        -- Off: V.isFP stays true so the next update leaves cleanly (crosshair back).
        if not want then return end
    end
    if m == G.ViewMode.Third and V.isFP then
        V.isFP = false
        V.kicks[#V.kicks + 1] = now
        -- Ping-pong guard: kicked out 4 times in 3 s = something we do not know keeps forcing
        -- third person. Back off for 5 s instead of fighting it every frame.
        while V.kicks[1] and now - V.kicks[1] > 3 do table.remove(V.kicks, 1) end
        if #V.kicks >= 4 then
            V.blockedUntil = now + 5
            V.kicks = {}
            U.warn("the game keeps forcing third person; pausing first person for 5 s")
        end
    end
end

-- Called by main.lua when the optional mod hotkey (ToggleKey) is pressed.
function V.toggle()
    V.wantFP = not V.wantFP
    V.blockedUntil, V.kicks = 0, {}
    V.dirty = true -- no HUD line (it beeps): the view change says it
end

-- Post-hook Q1Hud:ReceiveDrawHUD: once per frame, on foot and in ships (0.1.7; until then
-- ALS_Base:ReceiveTick, once per frame for every ALS character, NPCs included: each call left
-- garbage in this Lua state, and in a long fight its collection held the game thread up to
-- 92 ms). The common path is one clock compare; when due, the HUD is only used as a world
-- context to ask the engine for the possessed pawn.
-- Post-hook ALS_Base:OnDead. When the player dies the game ragdolls, destroys the weapon and may
-- reload the map: objects die mid-frame. The mod then makes no engine call at all for 15 s and
-- forgets its state; it starts again from the new pawn (0.1.2: a crash when killed in first
-- person, an access violation inside a Lua callback).
function V.onDeath(self)
    local ok, a = pcall(function() return self:get():GetAddress() end)
    if not ok or a ~= V.playerAddr then return end
    V.deadUntil = os.clock() + 15
    V.playerAddr, V.otherAddr, V.isFP, V.viewOnWeapon, V.poseOurs = nil, nil, false, false, false
    V.reloadAt, V.keyAt, V.dirty = nil, nil, true
    if V.onDeathHook then V.onDeathHook() end
    U.log("player died: paused for 15 s")
end

-- Post-hook Master_Hand_Weapon:RL / :Reloaded.
function V.onReload()
    V.reloadAt, V.guardNext = os.clock(), 0
end

-- For a few seconds after a reload, check the view every frame: the game's switch to the weapon
-- blends over 0.25 s, so waiting for the 0.1 s poll would still show a dip toward the gun.
local function guardReload(self, now)
    V.guardNext = now + 0.004
    local since = now - V.reloadAt
    if since > 5 then V.reloadAt = nil; return end   -- 2 s in game time; slow motion stretches it
    if since < 1.5 or not V.isFP or V.viewOnWeapon then return end
    local p = U.playerPawn(self:get())
    if not p or U.addr(p) ~= V.playerAddr then return end
    local pc = U.playerController(p)
    local ok, vt = pcall(function() return pc:GetViewTarget() end)
    if ok and U.valid(vt) and U.addr(vt) ~= U.addr(p) and isOwnWeapon(p, vt) then
        viewBackOnPlayer(p, pc)
        V.reloadAt = nil
    end
end

function V.onTick(self, A)
    local now = os.clock()
    if now < V.deadUntil then return end
    if V.reloadAt and now >= V.guardNext then guardReload(self, now) end
    if now < ((V.dirty or A.wantsFrames()) and V.nextFast or V.nextPoll) then return end
    V.nextFast = now + 0.008             -- while something is pending: about once per frame
    V.nextPoll = now + cfg().PollSeconds
    local p = U.playerPawn(self:get())
    if not p then return end
    local a = U.addr(p)
    if a ~= V.playerAddr then
        if a == V.otherAddr then return end
        if not G.PlayerClassNames[U.className(p) or ""] then  -- a ship, a vehicle...
            V.otherAddr, V.dirty = a, false
            A.restoreHud(p) -- the HUD's crosshair is shared with the ship
            return
        end
        V.playerAddr, V.otherAddr, V.dirty = a, nil, true     -- new player pawn (load, respawn, back on foot)
    end
    V.update(p, now, A)
end

local step
function V.update(p, now, A)
    -- Ragdoll (falls, HTR knockouts, the start of a death): the game owns the body and destroys or
    -- holsters the weapon. Touch nothing but plain property reads until it gets up.
    if U.get(p, P.MovementState, 0) == G.MovementState.Ragdoll then
        if A.hold or A.aiming or A.leaving then A.reset() end
        V.viewOnWeapon = false
        if V.isFP then V.isFP, V.dirty = false, true end
        return
    end
    if V.message then U.notify(V.message, p); V.message = nil end
    timed("aim", A.update, p, now, V)
    -- Entering first person, the near clip plane and the weapon pose each cost several ms (the
    -- game's view switch, a render flush, an animation change): one per frame, never all at once.
    if timed("view", step, p, now, A) then V.dirty = true; return end
    if timed("near clip", syncNearClip, p) then V.dirty = true; return end
    timed("pose", weaponPose, p, A)
    if LEAN.held() then LEAN.fix(p) end -- a pose change while a lean key is held keeps the lean right
end

step = function(p, now, A)
    if not V.wantFP then
        if V.isFP then V.leave(p); A.onViewChanged(p, false, V) end
        V.dirty = false
        return
    end
    if now < V.blockedUntil then V.dirty = false; return end
    local why = V.blockReason(p)
    if why == "weapon camera" then
        viewBackOnPlayer(p, U.playerController(p))
        why = nil
    end
    if why ~= V.lastBlock then V.lastBlock = why; U.log("first person blocked by: " .. tostring(why)) end
    if why then
        -- Another camera shows the scene (cutscene...): give the player their head back.
        -- Other blockers are views the game owns and sets itself; leave them alone.
        if why == "other camera" and V.isFP then V.leave(p); A.onViewChanged(p, false, V) end
        V.dirty = false
        return
    end
    if not V.isFP or U.get(p, P.ViewMode, 0) ~= G.ViewMode.First then
        V.enter(p)
        A.onViewChanged(p, true, V)
        V.dirty = false
        return true
    end
    hideHead(p)
    V.dirty = false
end

return V
