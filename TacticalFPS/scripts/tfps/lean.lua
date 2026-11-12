--[[
  Lean fix (0.1.10). The game's lean is a counter (Q1_Character "Set Lean Mode"): a lean key
  press adds -1 or +1 to LeaningValue and its release takes it back, but only while the
  rotation mode is Aiming; in any other mode the counter is reset to 0. First person changes
  the rotation mode while you play (weapon up, sprint, melee, draws), so a press could be
  dropped while its release still counted: the lean flipped to the other side and stayed there
  after you let go. Here the keys' real state is kept, and after every lean key event (and
  while a key is held) the counter is set from it.
]]

local U = require("tfps.util")
local G = require("tfps.gamedefs")
local P = G.P

local L = { left = false, right = false }

-- Lean from the keys held, when the game allows a lean (rotation mode Aiming); else none.
function L.fix(p)
    if not U.valid(p) then return end
    local want = 0
    if U.get(p, P.RotationMode, 0) == G.RotationMode.Aiming then
        want = (L.right and 1 or 0) - (L.left and 1 or 0)
    end
    local dir = (want == -1 and 1) or (want == 1 and 2) or 0 -- LeanDirection: 1 left, 2 right
    if U.get(p, P.LeanValue, 0) ~= want then U.set(p, P.LeanValue, want) end
    if U.get(p, P.Lean, 0) ~= dir then U.set(p, P.Lean, dir) end
end

-- Post-hook on a lean key event: side "left" / "right", down true on press.
function L.onKey(self, side, down)
    L[side] = down
    local ok, p = pcall(function() return self:get() end)
    if ok then L.fix(p) end
end

-- True while a lean key is held (view.lua keeps the lean right while the pose changes).
function L.held()
    return L.left or L.right
end

return L
