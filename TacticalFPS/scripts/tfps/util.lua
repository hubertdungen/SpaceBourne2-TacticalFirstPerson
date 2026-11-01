--[[
  Shared helpers (trimmed copy of HTR's htr/util.lua; same safety rules):
   * Game objects are only touched inside hook callbacks or right after an engine lookup.
     No object is kept from one frame to the next; only addresses (plain numbers) are kept.
   * Hooks only on Blueprint functions. Never RegisterLoadMapPreHook/PostHook.
   * Never FindAllOf/FindFirstOf in code that runs while playing (~50 ms per scan).
]]

local U = {}

-- Mod folder (UE4SS may report the path as ...\Scripts\ or ...\scripts\).
do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local cut
    for i in src:lower():gmatch("()[\\/]scripts[\\/]") do cut = i end
    U.Dir = cut and src:sub(1, cut) or ".\\Mods\\TacticalFPS\\"
end
U.LogFile = U.Dir .. "tfps.log"
U.Verbose = false

function U.log(...)
    if not U.Verbose then return end
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), table.concat(t, " "), "\n"); f:close() end
end

-- Always printed (UE4SS.log) and logged.
function U.warn(...)
    local msg = table.concat({ ... }, " ")
    print("[TacticalFPS] " .. msg .. "\n")
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), "WARN ", msg, "\n"); f:close() end
end

function U.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

function U.className(o)
    if not U.valid(o) then return nil end
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or nil
end

function U.addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

function U.get(o, prop, default)
    local ok, v = pcall(function() return o[prop] end)
    if ok and v ~= nil then return v end
    return default
end

function U.set(o, prop, value)
    return pcall(function() o[prop] = value end)
end

-- Call a UFunction safely: U.call(obj, "Name", args...) -> ok, result
function U.call(o, fn, ...)
    local args = table.pack(...)
    return pcall(function() return o[fn](o, table.unpack(args, 1, args.n)) end)
end

local GS
function U.gameplayStatics()
    if not U.valid(GS) then GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    return GS
end

-- ctx: any live object in the world (instant engine lookups).
function U.playerPawn(ctx)
    local ok, p = pcall(function() return U.gameplayStatics():GetPlayerPawn(ctx, 0) end)
    return (ok and U.valid(p)) and p or nil
end

function U.playerController(ctx)
    local ok, pc = pcall(function() return U.gameplayStatics():GetPlayerController(ctx, 0) end)
    return (ok and U.valid(pc)) and pc or nil
end

-- Engine console command (e.g. "r.SetNearClipPlane 5"). ctx: a live object in the world.
local KSL
function U.console(cmd, ctx)
    if not U.valid(KSL) then KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    local pc = U.playerController(ctx)
    if not (U.valid(KSL) and pc) then return false end
    return pcall(function() KSL:ExecuteConsoleCommand(ctx, cmd, pc) end)
end

-- On-foot HUD message (the same call HTR 0.4.1 verified on screen).
function U.notify(text, pawn)
    if not U.valid(pawn) then return false end
    return pcall(function() pawn:TMWPerkWarning(FText(text)) end)
end

return U
