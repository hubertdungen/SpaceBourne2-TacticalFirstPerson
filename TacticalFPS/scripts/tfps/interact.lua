--[[
  F prompt past squad soldiers (0.1.11).

  The game picks what F interacts with on every tick (Q1_Character: CalculateInteractTrace, then
  BoxTraceSingle from the camera, box 2 x 128 x 32 cm, so 2.56 m wide, channel 4) and takes the first
  actor in that box. A squad soldier next to you is inside the box from its start, so the loot box
  or door right in front of you gets no prompt; and F does nothing on a healthy soldier (the game
  only handles a dead or injured one). Tested 2026-11-14: soldier 70 cm to your right or left,
  standing or crouched, level or looking down at the box: the game picked the soldier (at 0 cm)
  every time; with the soldier away it picked the box.

  Here, in first person, while the game's pick is a healthy squad soldier near you, a narrow box
  (24 cm wide) along the view looks again. If it finds something the game can interact with, in
  the game's own reach, that becomes the F target and gets its prompt, every frame, as the game
  does for its own pick. A soldier right in front of you stays the game's pick.
  Traced at most 5 times a second, and only then: each UE4SS call with an out param keeps a
  registry entry (0.1.9). Loot drops are Master_Drop_Loot_C < Master_Loot_On_Foot_C <
  Master_InteractiveFoot_C (InteractionLenght 0, so the game's reach is 530 cm).
]]

local U = require("tfps.util")
local I = { target = nil }

local SQUAD, FOOT, CHARACTER = "Q1_GroundSquad_C", "Master_InteractiveFoot_C", "Character"
local KSL = nil
local IGN, HIT = {}, {}
local reuse = true -- reuse HIT, emptied before each trace (falls back to a fresh table)
local last = { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, t = -10, pick = nil }
local HALF = { X = 2, Y = 12, Z = 32 }
local RED, GREEN = { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }
local isCache = {}
local nextTrace = 0

local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

-- the actor's class is `name` or derives from it (cached per class)
local function isA(a, name)
    local ok, r = pcall(function()
        local c = a:GetClass()
        local key = name .. ":" .. tostring(c:GetAddress())
        if isCache[key] ~= nil then return isCache[key] end
        local found = false
        for _ = 1, 16 do
            if not valid(c) then break end
            if c:GetFName():ToString() == name then found = true; break end
            c = c:GetSuperStruct()
        end
        isCache[key] = found
        return found
    end)
    return ok and r
end

local function healthySoldier(a)
    if not (valid(a) and isA(a, SQUAD)) then return false end
    local ok, r = pcall(function() return not a.NPCDead and not a.InInjuredMode end)
    return ok and r
end

-- what the game would do with this actor as its pick: a Master_InteractiveFoot within its own
-- reach (InteractionLenght, 530..1500 cm), anything else that is not a character within 530 cm
local function usable(p, t)
    if not valid(t) or isA(t, CHARACTER) then return false end
    local ok, r = pcall(function()
        local f = t.InInteractRadious
        if not (f and f:IsValid()) then return false end
        local reach = 530
        if isA(t, FOOT) then
            if t.DisableInteract then return false end
            reach = math.min(1500, math.max(530, t.InteractionLenght or 530))
        end
        return p:GetDistanceTo(t) <= reach
    end)
    return ok and r
end

local function trace(p, pc)
    if not valid(KSL) then KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not valid(KSL) then return nil end
    local cm = pc.PlayerCameraManager
    local s, r = cm:GetCameraLocation(), cm:GetCameraRotation()
    local cp, sp = math.cos(math.rad(r.Pitch)), math.sin(math.rad(r.Pitch))
    local cy, sy = math.cos(math.rad(r.Yaw)), math.sin(math.rad(r.Yaw))
    local e = { X = s.X + cp * cy * 3400, Y = s.Y + cp * sy * 3400, Z = s.Z + sp * 3400 }
    IGN[1] = p
    local rot = pc:GetControlRotation()
    -- A hit table still holding the last hit gave no new hit in game (ab5dbcd), a fresh one each
    -- time works but UE4SS keeps every out-param table: about 1.6 MB a minute at 5 traces a
    -- second (2026-11-14). So the same table, emptied first; a fresh one if that gives nothing.
    local function run(hit)
        local okc, res = pcall(function()
            return KSL:BoxTraceSingle(p, s, e, HALF, rot, 4, false, IGN, 0, hit, true, RED, GREEN, 0.0)
        end)
        local a = nil
        if okc and res then pcall(function() a = hit.Actor; if a and a.Get then a = a:Get() end end) end
        return okc, res, a
    end
    local okc, res, a
    if reuse then
        for k in pairs(HIT) do HIT[k] = nil end
        okc, res, a = run(HIT)
        if not okc or (res and not valid(a)) then
            reuse = false
            U.log("F past a squad soldier: emptied hit table gave no hit, fresh tables from now on")
        end
    end
    if not reuse then okc, res, a = run({}) end
    if not (okc and res) then return nil end
    return valid(a) and a or nil
end

-- Polled with the view update (first person only): look again when the game picked a soldier.
function I.update(p, pc, now)
    I.p = p
    local pick = nil
    pcall(function() pick = p.InteractingActor end)
    -- our own target there means the game's pick was still the soldier on this tick (I.frame)
    if I.target and valid(pick) and pick:GetAddress() == I.targetAddr then pick = I.soldier end
    if I.target and valid(pick) and pick:GetAddress() ~= I.targetAddr and not healthySoldier(pick) then
        I.target = nil -- the game found something itself
    end
    if now < nextTrace or not pc then return end
    -- trace again only when the view moved or turned, the game's soldier changed, or after 1 s
    local c, r = nil, nil
    pcall(function() local cm = pc.PlayerCameraManager; c, r = cm:GetCameraLocation(), cm:GetCameraRotation() end)
    if not c then return end
    local turned = math.abs(r.Pitch - last.pitch) > 2 or math.abs(((r.Yaw - last.yaw + 180) % 360) - 180) > 2
    local moved = math.abs(c.X - last.x) + math.abs(c.Y - last.y) + math.abs(c.Z - last.z) > 5
    local same = valid(pick) and last.pick == pick:GetAddress()
    if same and not turned and not moved and now < last.t + 1.0 then return end
    last.x, last.y, last.z, last.pitch, last.yaw, last.t = c.X, c.Y, c.Z, r.Pitch, r.Yaw, now
    last.pick = valid(pick) and pick:GetAddress() or nil
    if not healthySoldier(pick) then I.target = nil; return end
    local near = false
    pcall(function() near = p:GetDistanceTo(pick) <= 400 end)
    if not near then I.target = nil; return end
    nextTrace = now + 0.2
    local okt, t = pcall(trace, p, pc)
    if not okt then t = nil end
    local was = I.targetAddr
    if t and usable(p, t) then
        I.target, I.targetAddr, I.soldier = t, t:GetAddress(), pick
    else
        I.target, I.targetAddr = nil, nil
    end
    if I.targetAddr ~= was and U.Verbose then
        U.log("F target past a squad soldier: " .. (I.target and I.target:GetClass():GetFName():ToString() or "none"))
    end
end

-- Every frame while a target is held: the game set its pick again on this tick; ours wins.
function I.frame(p)
    if not valid(p) then I.target = nil; return end
    local t = I.target
    if not valid(t) then I.target = nil; return end
    local pick = nil
    pcall(function() pick = p.InteractingActor end)
    if not healthySoldier(pick) then
        if not (valid(pick) and pick:GetAddress() == I.targetAddr) then I.target = nil end
        return
    end
    I.soldier = pick
    pcall(function() p.InteractingActor = t end)
    pcall(function() t:InInteractRadious(nil) end)
end

function I.reset() I.target = nil end

return I
