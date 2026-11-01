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
   * All work happens in a ReceiveTick post-hook on ALS characters, throttled to PollSeconds;
     it runs about once per frame only while something is pending (dirty, FOV blend).
]]

local U = require("tfps.util")
local G = require("tfps.gamedefs")
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
}

local function cfg() return TFPS.cfg end

-- Weapon up: the game holds a drawn gun low at the hip, below the first-person view. ALS's
-- aiming pose (RotationMode Aiming) holds it at the shoulder, where you see it. Kept while a
-- weapon is out, except when sprinting (ALS cannot sprint while aiming) or in melee.
local function weaponPose(p)
    local up = V.isFP and cfg().WeaponUp and U.get(p, P.WeaponOut, false) and not U.get(p, P.Melee, false)
        and U.get(p, P.DesiredGait, 1) ~= 2
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
local function syncNearClip(p)
    local want = V.isFP and cfg().NearClip > 0
    if want == V.nearOn then return end
    if U.console("r.SetNearClipPlane " .. (want and cfg().NearClip or 10), p) then V.nearOn = want end
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
        if ok and U.valid(vt) and U.addr(vt) ~= U.addr(p) then return "other camera" end
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
    if V.ours then return end
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
            V.wantFP, V.blockedUntil, V.kicks = want, 0, {}
            V.message = want and "First person ON" or "First person OFF"
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
    V.dirty = true
    V.message = V.wantFP and "First person ON" or "First person OFF"
end

-- Post-hook ALS_Base:ReceiveTick. Fires every frame for every ALS character (player and
-- NPCs), so the common path is one clock compare. When due, the ticking actor is only used
-- as a world context to ask the engine for the possessed pawn (instant), so no class checks
-- run per NPC and nothing allocates per NPC per frame.
function V.onTick(self, A)
    local now = os.clock()
    if now < ((V.dirty or A.busy or A.hold) and V.nextFast or V.nextPoll) then return end
    V.nextFast = now + 0.008             -- while something is pending: about once per frame
    V.nextPoll = now + cfg().PollSeconds
    local p = U.playerPawn(self:get())
    if not p then return end
    local a = U.addr(p)
    if a ~= V.playerAddr then
        if a == V.otherAddr then return end
        if not G.PlayerClassNames[U.className(p) or ""] then  -- a ship, a vehicle...
            V.otherAddr, V.dirty = a, false
            return
        end
        V.playerAddr, V.otherAddr, V.dirty = a, nil, true     -- new player pawn (load, respawn, back on foot)
    end
    V.update(p, now, A)
end

local step
function V.update(p, now, A)
    if V.message then U.notify(V.message, p); V.message = nil end
    A.update(p, now, V)
    step(p, now, A)
    syncNearClip(p)
    weaponPose(p)
end

step = function(p, now, A)
    if not V.wantFP then
        if V.isFP then V.leave(p); A.onViewChanged(p, false, V) end
        V.dirty = false
        return
    end
    if now < V.blockedUntil then V.dirty = false; return end
    local why = V.blockReason(p)
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
    else
        hideHead(p)
    end
    V.dirty = false
end

return V
