--[[
  Every SpaceBourne 2 internal name Tactical FPS depends on lives in this file.
  When a game update renames something, this is the only file to fix.
  Names come from the game's Blueprints (UE 4.27, build 2026-10-26). See DESIGN.md.
]]

local G = {}

-- Classes -------------------------------------------------------------------
G.Player       = "/Game/1Data/Q1_Character.Q1_Character_C"
G.ALSBase      = "/Game/Locomotion/Blueprints/CharacterLogic/ALS_Base.ALS_Base_C"
G.HandWeapon   = "/Game/1Data/Weapons/Hand_Weapons/Weapons/Master_Hand_Weapon.Master_Hand_Weapon_C"
G.PlayerClassNames = { Q1_Character_C = true }

-- Enums (byte values) -----------------------------------------------------------
G.ViewMode      = { Third = 0, First = 1 }                       -- ALS_ViewMode
G.RotationMode  = { Velocity = 0, Looking = 1, Aiming = 2 }      -- ALS_RotationMode
G.MovementState = { None = 0, Grounded = 1, InAir = 2, Mantling = 3, Ragdoll = 4 }
G.Slate         = { Visible = 0, Collapsed = 1, Hidden = 2, HitTestInvisible = 3 } -- ESlateVisibility

-- Hooked functions (all Blueprint functions; post-hooks) ------------------------
G.Fn = {
    -- every frame, every ALS character; the only place we get a live player object
    Tick         = G.ALSBase .. ":ReceiveTick",
    -- every view change of the player: our toggle, the game's camera key, ForceToTP (weapon
    -- drawn, dialog, melee, ragdoll, hover), OnRotationModeChanged. Q1_Character overrides
    -- ALS_Base's version (and calls it), so hooking Q1's fires for the player only.
    SetViewMode  = G.Player .. ":BPI_Set_ViewMode",
    -- aim pressed (Relesed? = false) / released (true); Q1_Character overrides ALS_Base's event
    RMB          = G.Player .. ":RMB",
    -- weapon equip; MHW init runs 0.1 s later and re-adds the crosshair (AddCrosshair(5, ...))
    WeaponEquip  = G.HandWeapon .. ":Play_Equip_Sound",
    -- the game's own "switch camera" input, keyboard (_51/_52) and gamepad (_22/_23). The
    -- game toggles the view 0.2 s after the press; HTR also hooks _22 (4-tap mode gesture).
    CameraInputs = {
        G.ALSBase .. ":InpActEvt_X_SwitchCamera_K2Node_EnhancedInputActionEvent_51",
        G.ALSBase .. ":InpActEvt_X_SwitchCamera_K2Node_EnhancedInputActionEvent_52",
        G.ALSBase .. ":InpActEvt_GP_SwitchCamera1_K2Node_EnhancedInputActionEvent_22",
        G.ALSBase .. ":InpActEvt_GP_SwitchCamera1_K2Node_EnhancedInputActionEvent_23",
    },
}

-- Functions we CALL (Blueprint events and engine functions) -------------------------
--   pawn:BPI_Set_ViewMode(1|0)  view mode only. Q1 hides hair/headlight/cyborg parts in first
--                               person and restores head/helmet/hair in third person.
--   pawn:ForceToTP()            NOT used: also resets the view target (would break cutscenes)
--   pawn:ForceToFP(SniperFP)    NOT used: hides the whole body; false = kicks back if a weapon is out
--   pc:SetViewTargetWithBlend(actor, time, 0, 0, false)   pawn (normal) or weapon (sight camera)
--   comp:SetVisibility(bool, false), comp:SetCastHiddenShadow(bool)
--   crosshairWidget:GetCrosshairChild():SetVisibility(G.Slate.*), crosshairWidget:SetCrosshairScale(x)

-- Properties (names exactly as in the Blueprints; some contain '?') -------------------
G.P = {
    -- ALS_Base
    ViewMode = "ViewMode", RotationMode = "RotationMode", MovementState = "MovementState",
    FirstPersonFOV = "FirstPersonFOV",            -- read by the camera every frame (default 90)
    AtDialog = "AtDialog?", Flying = "Flying?", InSpace = "CharacterAtSpace",
    FPWalk = "IsFirstPersonCameraWalkOn",        -- the game's own forced first-person walk areas
    Loading = "GameLoading?", Prisoner = "PrisonerState?", WeaponOut = "CurrentStateWeapon",
    DesiredGait = "DesiredGait",                 -- 0 walk, 1 run, 2 sprint (ALS_Gait)
    Mesh = "Mesh",
    -- Q1_Character
    Head = "Male_Head", Helmet = "Helmet_SM", Hair = "Male_Hair_01", HeadLight = "HeadLight",
    Melee = "MeleeAttackOn?", Weapon = "CurrentWeapon",   -- ChildActorComponent -> .ChildActor
    Crosshair = "CrossHair",                               -- WB_CrosshairBase_C
    UsingScope = "UsingScope", Lean = "LeanDirection",
    -- Master_Hand_Weapon
    WeaponCamera = "Camera",                               -- the weapon's own sight camera
}

-- Weapons whose own sight camera (AimTransform) gives a true sight picture, checked in game on
-- 2026-11-01, with a height fix in cm: the game's camera sits 3 cm above the rifle's sight line
-- (bullets landed 3 degrees above the front post). Other weapons aim by zooming at the eyes.
G.SightCamera = {
    Bullet_Rifle_C = { Z = -3.0 },
    Pulse_Rifle_C  = { Z = -3.0 },
}

-- Weapon class -> aim group (ADS zoom per group, see config.lua)
G.WeaponGroup = {
    Bullet_Pistol_C = "Pistol", Laser_Pistol_C = "Pistol",
    Bullet_Rifle_C = "Rifle", Pulse_Rifle_C = "Rifle",
    SubmarineRifle_C = "SMG", Submachine_Laser_C = "SMG", MiscBeam_C = "SMG",
    Shotgun_Rifle_C = "Shotgun", Shotgun_Laser_C = "Shotgun",
    Hunter_BulletRifle_C = "Scoped", Hunter_LaserRifle_C = "Scoped",
    Sniper_Rifle_C = "Scoped", Sniper_Laser_C = "Scoped",
}

return G
