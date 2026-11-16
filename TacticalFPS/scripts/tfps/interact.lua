--[[
  F prompt through blockers (0.1.11, widened in 0.1.12).

  The game picks what F interacts with on every tick (Q1_Character: CalculateInteractTrace, then
  BoxTraceSingle from the camera, box 2 x 128 x 32 cm, so 2.56 m wide and 64 cm high, channel 4,
  ignoring only the player) and takes the FIRST thing that box touches. In first person the box
  starts at your eyes, so anything within 1.28 m to either side of you, or 32 cm above or below the
  eye line, is "first" with a hit at 0 cm: a squad soldier beside you (tested 2026-11-14), but just
  as well a wall, a shelf or another crate next to you. If that is not something you can use, the
  game uses nothing: the crate right in front of you gets no prompt and no glow, until you step
  back far enough from what is beside you. (Third person does not have this: its box starts
  behind you.) A soldier beside you took the pick in every test; a pick that is not usable leaves
  nothing for the game to call InInteractRadious on, and that call is what shows the prompt and
  the glow.

  Here, in first person, a narrow box (24 cm wide, same height and channel, along the view) looks
  again. If its first hit is something the game could interact with, in the game's own reach, that
  becomes the F target: it gets the prompt and the glow every frame, as the game does for its own
  pick, and F acts on it. What you look at wins over what only stands near you. Something solid
  right in front of the target still blocks it, and a character (soldier, enemy) in front stays
  the game's choice.

  Traced when the view moved (at most 5 times a second) and once a second otherwise: each UE4SS
  call with an out param keeps a registry entry (0.1.9), so the one hit table is emptied and reused
  (a fresh one each time leaked 1.6 MB a minute, 2026-11-14). Loot drops are Master_Drop_Loot_C <
  Master_Loot_On_Foot_C < Master_InteractiveFoot_C (InteractionLenght 0, so the game's reach is
  530 cm); crates are Master_Loot_Continer_C < Master_InteractiveFoot_C.
]]

local U = require("tfps.util")
local I = { target = nil }

local FOOT, CHARACTER = "Master_InteractiveFoot_C", "Character"
local KSL = nil
local IGN, HIT = {}, {}
local reuse = true -- reuse HIT, emptied before each trace (falls back to a fresh table)
local last = { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, t = -10 }
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
            U.log("F through blockers: emptied hit table gave no hit, fresh tables from now on")
        end
    end
    if not reuse then okc, res, a = run({}) end
    if not (okc and res) then return nil end
    return valid(a) and a or nil
end

-- Polled with the view update (first person only).
function I.update(p, pc, now)
    I.p = p
    if now < nextTrace or not pc then return end
    -- trace again only when the view moved or turned, or after 1 s
    local c, r = nil, nil
    pcall(function() local cm = pc.PlayerCameraManager; c, r = cm:GetCameraLocation(), cm:GetCameraRotation() end)
    if not c then return end
    local turned = math.abs(r.Pitch - last.pitch) > 2 or math.abs(((r.Yaw - last.yaw + 180) % 360) - 180) > 2
    local moved = math.abs(c.X - last.x) + math.abs(c.Y - last.y) + math.abs(c.Z - last.z) > 5
    if not turned and not moved and now < last.t + 1.0 then return end
    last.x, last.y, last.z, last.pitch, last.yaw, last.t = c.X, c.Y, c.Z, r.Pitch, r.Yaw, now
    nextTrace = now + 0.2
    local okt, t = pcall(trace, p, pc)
    if not okt then t = nil end
    local was = I.targetAddr
    if t and usable(p, t) then
        I.target, I.targetAddr = t, t:GetAddress()
    else
        I.target, I.targetAddr = nil, nil
    end
    if I.targetAddr ~= was and U.Verbose then
        U.log("F target through blockers: " .. (I.target and I.target:GetClass():GetFName():ToString() or "none"))
    end
end

-- Every frame while a target is held: the game set its pick again on this tick; ours wins.
function I.frame(p)
    local t = I.target
    if not (valid(p) and valid(t)) then I.target = nil; return end
    pcall(function() p.InteractingActor = t end)
    pcall(function() t:InInteractRadious(nil) end)
end

function I.reset() I.target = nil end

return I
