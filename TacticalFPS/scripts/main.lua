--[[
  Tactical First Person for SpaceBourne 2 (UE4SS Lua mod).
  Entry point: loads settings, wires hooks and the optional key, nothing else.
    config.lua         user settings
    tfps/gamedefs.lua  every game-internal name (the only file to fix after a game patch)
    tfps/view.lua      first / third person switching
    tfps/aim.lua       aiming (ADS) and crosshair
    tfps/hooks.lua     lazy hook registration (from HTR)
    tfps/util.lua      helpers (from HTR)
]]

local VERSION = "0.1.1"

local U = require("tfps.util")

-- Settings -------------------------------------------------------------------
local okCfg, cfg = pcall(require, "config")
if not okCfg or type(cfg) ~= "table" then
    U.warn("config.lua could not be read (" .. tostring(cfg) .. "); using defaults")
    cfg = {}
end
local function default(tbl, key, val) if tbl[key] == nil then tbl[key] = val end end
default(cfg, "Enabled", true); default(cfg, "ToggleKey", ""); default(cfg, "StartInFirstPerson", false)
default(cfg, "UseGameCameraKey", true); default(cfg, "Body", "Full"); default(cfg, "HeadShadow", true); default(cfg, "WeaponUp", true)
default(cfg, "FOV", 90); default(cfg, "NearClip", 5); default(cfg, "Crosshair", "Hidden"); default(cfg, "CrosshairScale", 0.5); default(cfg, "AimDot", true)
default(cfg, "PollSeconds", 0.1); default(cfg, "Debug", false)
cfg.ADS = cfg.ADS or {}
default(cfg.ADS, "Mode", "Sights"); default(cfg.ADS, "BlendSeconds", 0.15)
default(cfg.ADS, "ZoomFOV", { Pistol = 75, SMG = 70, Rifle = 65, Shotgun = 75 })
cfg.FOV = math.max(60, math.min(120, tonumber(cfg.FOV) or 90))
cfg.NearClip = math.max(0, math.min(10, tonumber(cfg.NearClip) or 0))

U.Verbose = cfg.Debug == true
TFPS = { version = VERSION, cfg = cfg }

if cfg.Enabled ~= true then
    print("[TacticalFPS] " .. VERSION .. " installed but disabled (Enabled = false in config.lua)\n")
    return
end

-- Remembered choice --------------------------------------------------------------
local STATE = U.Dir .. "state.txt"
local function loadWantFP()
    local f = io.open(STATE, "r")
    if f then
        local v = (f:read("a") or ""):match("firstperson=(%a+)")
        f:close()
        if v then return v == "on" end
    end
    return cfg.StartInFirstPerson == true
end

local H = require("tfps.hooks")
local G = require("tfps.gamedefs")
local V = require("tfps.view")
local A = require("tfps.aim")

V.wantFP = loadWantFP()

local function saveState()
    local f = io.open(STATE, "w")
    if f then f:write("firstperson=" .. (V.wantFP and "on" or "off") .. "\n"); f:close() end
end
V.persist = saveState

local function toggle() -- game thread
    V.toggle()
    saveState()
    U.warn("first person " .. (V.wantFP and "ON" or "OFF"))
end

U.warn(string.format("=== Tactical First Person %s loaded, first person %s ===", VERSION, V.wantFP and "on" or "off"))

-- Hooks -------------------------------------------------------------------
H.add(G.Fn.Tick, function(self) V.onTick(self, A) end, "player tick")
H.add(G.Fn.SetViewMode, V.onSetViewMode, "view change")
H.add(G.Fn.RMB, function(self, released) A.onRMB(self, released, V) end, "aim")
H.add(G.Fn.WeaponEquip, A.onEquip, "weapon equip")
for i, path in ipairs(G.Fn.Reloads) do H.add(path, V.onReload, "reload " .. i) end
if cfg.UseGameCameraKey then
    -- The game's camera key / button switches the view itself; the mod follows its choice.
    for i, path in ipairs(G.Fn.CameraInputs) do H.add(path, V.onGameCameraKey, "game camera input " .. i) end
elseif cfg.ToggleKey == "" then
    U.warn("UseGameCameraKey = false and no ToggleKey: first person can only start from state.txt / StartInFirstPerson")
end

-- Classes load late: look for them about once a second (a miss costs ~37 ms, see hooks.lua).
local lastStatus, profileAt = "", os.clock() + 30
LoopAsync(1000, function()
    ExecuteInGameThread(function()
        local t0 = os.clock()
        local ok, err = pcall(H.poll, t0)
        if not ok then U.warn("poll: " .. tostring(err)) end
        if U.Verbose and t0 > profileAt then
            profileAt = t0 + 30
            local prof = H.profile()
            if prof ~= "" then U.log("profile 30 s: " .. prof) end
        end
        local on, off = H.status()
        local s = string.format("hooks active %d, waiting %d", on, off)
        if s ~= lastStatus then lastStatus = s; U.log(s) end
    end)
    return false
end)

-- Key -------------------------------------------------------------------------------
-- Optional mod hotkey. Off by default (""): the realism-set key plan (revision 2c) gives
-- Tactical FPS no key; the game's own camera key switches (UseGameCameraKey).
-- If set: a UE4SS key name, optionally with Shift ("Shift+DEL", "NUM_FIVE"...).
--  * Shift is the only modifier: on foot Ctrl opens the map and Alt crouches.
--  * Never F1, F2, F5, F6, F8, F10, F11, F12, plain or with Shift: the game reacts to them
--    (orders, quick save, quick load, bug report, fullscreen, Steam screenshot).
--    F3/F4 plain = fleet orders in ships.
--  * UE4SS matches modifiers exactly (verified in game for HTR 0.4.4): a plain bind does not
--    fire on Shift+<key>, so no extra guard is needed.
local KEY_ALIAS = { INSERT = "INS", DELETE = "DEL", PAGEDOWN = "PAGE_DOWN", PAGEUP = "PAGE_UP", ESC = "ESCAPE" }
local NEVER = { F1 = 1, F2 = 1, F5 = 1, F6 = 1, F8 = 1, F10 = 1, F11 = 1, F12 = 1 }
local NOT_PLAIN = { F3 = 1, F4 = 1 }
local OTHER_MODS = {
    F7 = "HTR mode", F9 = "HTR ships", F3 = "Stealth ally orders", F4 = "Stealth suppressor",
    DEL = "Engineering Turrets", ["SHIFT+F7"] = "HTR gear bonus", ["SHIFT+F9"] = "Faction Power",
    ["SHIFT+F3"] = "HTR slow perks", ["SHIFT+F4"] = "Stealth on/off", ["SHIFT+DEL"] = "Gear Any Level",
}

-- "Shift+DEL" -> "DEL", true. Returns nil, reason when the key cannot be used.
local function parseKey(spec)
    if type(spec) ~= "string" or spec == "" then return nil, "empty" end
    local shift, key = false, nil
    for part in spec:upper():gsub("%s", ""):gmatch("[^+]+") do
        if part == "SHIFT" then
            shift = true
        elseif part == "CTRL" or part == "CONTROL" or part == "ALT" then
            return nil, "Ctrl and Alt are game actions on foot (map, crouch); use Shift"
        else
            key = KEY_ALIAS[part] or part
        end
    end
    if not (key and Key and Key[key]) then return nil, "unknown key" end
    if NEVER[key] then return nil, "the game reacts to " .. key end
    if not shift and NOT_PLAIN[key] then return nil, "the game uses " .. key .. " in ships" end
    return key, shift
end

local keySpec = cfg.ToggleKey
local key, shift = parseKey(keySpec)
if not key and keySpec ~= "" then
    U.warn(string.format("ToggleKey '%s' not usable (%s); no mod hotkey", tostring(keySpec), tostring(shift)))
end
if key then -- ToggleKey = "" means no key
    local other = OTHER_MODS[(shift and "SHIFT+" or "") .. key]
    if other then U.warn("ToggleKey " .. keySpec .. " is also " .. other) end
    if not shift then
        RegisterKeyBind(Key[key], function() ExecuteInGameThread(toggle) end)
    elseif ModifierKey then
        RegisterKeyBind(Key[key], { ModifierKey.SHIFT }, function() ExecuteInGameThread(toggle) end)
    else
        U.warn("this UE4SS has no ModifierKey; ToggleKey " .. keySpec .. " not bound")
    end
end
