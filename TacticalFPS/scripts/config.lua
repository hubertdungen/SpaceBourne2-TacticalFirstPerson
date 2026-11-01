--[[
  Tactical First Person for SpaceBourne 2 - settings
  Edit with any text editor, then restart the game. Every line is optional.
]]

return {
    -- false switches the mod off completely.
    Enabled = true,

    -- Switch first / third person on foot with the game's own "switch camera" key or
    -- gamepad button. The mod keeps first person when you draw a weapon.
    UseGameCameraKey = true,
    -- Optional extra key, none by default. A UE4SS key name, optionally with Shift ("Shift+DEL").
    -- The game's own keys (F1, F2, F5, F6, F8, F10, F11, F12) are refused.
    ToggleKey = "",
    -- Start in first person (your last choice is remembered in state.txt).
    StartInFirstPerson = false,

    -- "Full": your body, arms and weapon stay visible; only head, helmet and hair are hidden.
    -- "Hidden": the game's own look, with the whole body hidden.
    Body = "Full",
    HeadShadow = true,  -- your hidden head still casts a shadow
    -- Hold a drawn weapon up in front of you (the game's aiming pose) so you see it in first
    -- person. Sprinting lowers it. false = the game's low hold (seen only when you look down).
    WeaponUp = true,

    FOV = 90,           -- field of view in first person (game default 90)
    NearClip = 5,       -- cm; how close to your eyes things are still drawn (game default 10). 0 = leave it

    -- Aiming in first person.
    ADS = {
        -- "Sights": rifles are aimed along their own sights (shots go where the front post points);
        --           other weapons zoom at your eyes. "Zoom": every weapon zooms at your eyes.
        Mode = "Sights",
        ZoomFOV = { Pistol = 75, SMG = 70, Rifle = 65, Shotgun = 75 }, -- sniper rifles use the game's scope
        BlendSeconds = 0.15,
    },

    -- Crosshair in first person: "Hidden", "Small" or "Game". Hit markers stay.
    Crosshair = "Hidden",
    CrosshairScale = 0.5,
    AimDot = true,      -- small centre dot while zoom-aiming (weapons without usable sights)

    Debug = false,      -- write Mods\TacticalFPS\tfps.log
}
