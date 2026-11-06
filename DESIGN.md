# Tactical FPS for SpaceBourne 2: design

Status: 0.1.0 built and tested in game on 2026-11-01 (section 0.6).
Game build researched: 2026-10-26 (UE 4.27.2, UE4SS 3.0.1).

## 0. Feasibility study (2026-11-01): weapons, body, cockpit

Evidence comes from the decompiled Blueprints, the asset list of the game's pak (36,857
packages), the ALS skeleton's sockets and `DefaultEngine.ini`. The game was **not** launched.
Another session was changing the `Mods` folder at the time (the dev console mod was removed
mid-check), so the visual questions are open until one short probe (0.5).

### 0.1 Weapons in first person: looks acceptable; real FP arms are not possible

| Question | Evidence | Verdict |
|---|---|---|
| Weapon meshes | Hand weapons are `SkeletalMeshComponent`s. The master class uses `Rifle1` from the `Scifi_Arsenal_Vol1` pack, which also has `Sci-fi_Rifle_1..3`, `Pistol_2/3`, `Shotgun` and `RocketLauncher` with 4k textures. | Good quality, usable as they are. |
| Where the weapon sits | It is attached to the virtual bone `VB RHS_ik_hand_gun` (or `VB LHS_…`) of the body mesh and posed by the ALS third-person overlay animations (rifle/pistol). | In first person you see the third-person pose from the eyes. At the hip the gun is low in the view. Aiming raises it to the shoulder, but the sights are **not** centred on the screen. |
| First-person arms or animations | None in the pak: no arms mesh, no FP anim Blueprint, no FP montages. The only "Arms" assets are ALS additive run/sprint poses for the M4A1 overlay. `BallisticsVFX/FirstPersonBPExamples` holds only materials and a camera shake. | **Not available.** Real FP arms need new animations and assets cooked into a pak (UE 4.27 editor project, retargeting): weeks of work, out of scope. |
| An existing FP camera | ALS `FP_Camera` socket on the head bone (8.4 cm up, 6.4 cm forward), used by the game's own camera manager. **Every weapon class also has its own sight camera** (`Camera`, with `IdleTramsfom` and `AimTransform` placed per class) that the game uses for sniper scopes (`FPS_Camera` event → view target = weapon). | Usable: the head camera for normal view, the weapon camera as an experimental real-sights ADS. |
| Aim alignment | Shots start at the camera and go along its forward vector (`CalculateTrace`). | No mismatch, even with the sights off-centre. |
| Clipping into the camera | No near-clip override in `DefaultEngine.ini` or in the dumped Blueprints, so the engine default of 10 cm applies. While aiming, the stock and sight come close to the eye. | Parts nearer than 10 cm get cut. Mitigation: `r.SetNearClipPlane` (e.g. 3–5) from Lua; to test. |
| Clipping into walls | The capsule radius is 35 cm. The muzzle arrow is about 30 cm ahead of the weapon root, which sits in a hand held well in front of the chest. | Standing flush against a wall, the barrel goes an estimated 25–40 cm into it. This is very visible in first person (in third person too, but less noticed). Without animations the only cures are tricks: lower or hide the gun when a short trace from the camera hits geometry, or briefly drop the aim. They are acceptable, not polished. |

### 0.2 Visible body in first person: very likely clean, by design of the character

| Question | Evidence | Verdict |
|---|---|---|
| Head | The player's body mesh is **headless** (`SK_CyberpunkGirlHeadless`; suits come from item data, `ArmorData.Mesh`). Head (`Male_Head`), hair (`Male_Hair_01`) and helmet (`Helmet_SM`, static mesh) are separate components. The cyborg hood and parts (`CyborgHelm`, `CybogUst`, `CyborgUst2`) are already hidden by the game in first person. | Hiding the head is clean: no bone tricks, the neck cut is the one the artists made for the separate head. The game's sniper scope already hides head and helmet the same way. |
| Neck and torso when looking down | The camera sits about 8 cm above and 6 cm in front of the head bone, so the neck opening is roughly 10–15 cm below and behind the camera. In first person ALS takes camera **rotation** from the controller and only **location** from the socket, so the camera never rolls with the head. | Looking straight down, the collar may fall inside the 10 cm near-clip distance and show a cut edge for a moment. Fixes: lower near clip; move the camera 2–4 cm forward. The socket is a runtime object (`USkeletalMeshSocket.RelativeLocation`), or use a camera post-hook. Some suits may have high collars or shoulder pads: **check per suit**. |
| Walking, sprinting, crouching | The camera follows the head socket, which moves with the third-person animations (natural head bob). Crouch moves the head down and forward over the body, not into it. | Fine for walking and crouching. Rolls, mantles and hit reactions swing the camera hard, which may cause nausea; the mod can switch to third person during them. |
| The game's own choice | The game's camera key hides the **whole** body in first person and refuses first person with a weapon out. | The developers did not build an armed first person; we add it. |

### 0.3 Visible body in the ship cockpit: possible only as a fake, not recommended now

| Question | Evidence | Verdict |
|---|---|---|
| What the cockpit is | `Q1_Master_Cockpit` (and about 20 ship-specific cockpit Blueprints) is a static cockpit mesh plus a camera and spring arm. The view target is the cockpit actor, and free look is clamped to ±45° yaw and pitch. **There is no pilot mesh and no player body in the cockpit.** | Nothing to show today. A body has to be added. |
| Usable parts | `MasterCockpitCharacter` (capital-ship bridge crew) is a Body+Head skeletal-mesh actor with a seated cockpit pose (`CockpitSitter2_Montage`) and seated idle variants. The player's suit mesh can be set on it, and the head hidden. | A seated body can be faked: spawn this kind of actor under the cockpit camera and line the head socket up with the camera. |
| Limits | Hands would not hold the stick or throttle (no IK, no pilot animations). Every cockpit type needs its own seat offset, tuned in game per ship. The body may clip the cockpit mesh. With ±45° free look you would only see knees and hands at the bottom of the view. | High effort for a static result. |

### 0.4 Effort and recommendation

| Part | Feasible? | Rough effort |
|---|---|---|
| On-foot first person with a visible body and the weapon as held (0.1 + 0.2) | Yes | 1 probe launch, then about 1 day of code and tuning (the skeleton already does most of it), then 1–2 test sessions |
| ADS: FOV zoom (safe) / weapon sight camera (experimental) | Yes / maybe | Half a day + test |
| Wall-clipping trick (lower or hide the gun near walls) | Yes, cosmetic | Half to one day + test |
| Real first-person arms and animations | No (needs pak/asset work) | Weeks; not proposed |
| Pilot body in the cockpit | Only as a static fake | 2–4 days + one test per ship type; not proposed now |

**Recommendation:** build on-foot first person (body visible, head hidden, the weapon as the
game holds it, FOV-zoom ADS) and leave the cockpit out. Do the single probe below first: if
the neck, collar or weapon view looks bad, the answer changes before any more code is written.

### 0.5 The one probe launch that would settle it (about 10 minutes, scripted)

Needs the game to be free (GAME FREE in the shared notes, no other session testing) and the
dev console mod installed. It uses one copied save slot and restores `mods.txt` and the saves
afterwards. There is no `FindAllOf`, no property dump and no relaunch loop. Screenshots go
through `HighResShot 1`.

1. On foot, third person: baseline.
2. `BPI_Set_ViewMode(1)`, hide `Male_Head`, `Helmet_SM` and `Male_Hair_01`: shots looking ahead, 45° down and 80° down.
3. Same, crouched.
4. Rifle drawn (`InpActEvt_C_SwitchWeapon1…_47`), in first person: idle and aiming.
5. Facing a wall at 30 cm with the rifle up.
6. `SetViewTargetWithBlend(weapon)` with the weapon's `Aim(true)`: the weapon sight camera, for rifle and pistol.
7. Repeat 2 and 4 after `r.SetNearClipPlane 4`.
8. If time allows, a second suit (a cyborg or armour item) for the collar check.

### 0.6 In-game test log (2026-11-01, slot TFPSTest from CheckPoint, Rivenox 116 landing pad)

Two single launches. Each time: saves hashed, `TFPSTest` copied from `CheckPoint`, `SB2HOTAS : 0`,
all other set mods on, mod with `Debug = true` and `StartInFirstPerson = true`, dev console. Both
runs closed the game and restored `mods.txt`; the 81 save files were identical afterwards.
Screenshots came from `HighResShot 1`, plus one real screen capture for the HUD.

Run 1 (02:05):
- Without a weapon: first person on load. Head, helmet and hair hidden. Looking ahead, down 45°
  and down 80° (feet and legs visible) and crouched gave clean views, with no neck or collar cut.
- **Bug:** the player tick errored, because `view.lua` called `cfg()` before defining it. The hook
  switched itself off, so first person was not restored after the weapon draw. The other shots
  of this run are third person. Fixed in `fea6a0e`.
- The weapon's own sight camera (pistol), viewed through `SetViewTargetWithBlend`, pointed sideways
  and up with the gun filling a corner. It is unusable, so the `SightCamera` option was dropped.

Run 2 (02:12, after the fix):
- Drawing the pistol (slot 1) and the rifle (slot 2): the game kicks to third person and the mod
  puts first person back at once (`first person on` in the log, view 1 in every state line).
- Aiming: FOV 90 → 75 (pistol) and → 65 (rifle), and back on release.
- **The held weapon is not in view when looking ahead or aiming.** The third-person pose holds it
  low. Looking down 45°, the rifle shows at the bottom; at 80°, rifle and gloved hand cross the
  view. No clipping or cut edges, at near clip 5 or 10.
- Pillar 45 cm ahead: the low-held rifle does not enter it.
- The game's camera key (keyboard events `_52`/`_51`, called from the console) turned first person
  off, then on again with the rifle in hand. "First person ON" showed on the HUD (bottom right),
  and `state.txt` followed.
- Frames over 20 s in first person: 9.9 ms average, max 26 ms, 0 frames over 100 ms. After the
  key in third person: 9.9 ms average, max 23 ms, 0 over 100 ms.
- Mod cost: the player-tick hook ran about 3,000 times per 30 s for 57–81 ms in total, about
  0.02 ms per frame. Two single slow calls (10 ms and 8 ms) came from entering first person, which
  is the game's own view change.

Run 3 (02:28): `WeaponUp` test, after the user asked for the gun to be visible.
- The cheap options, in order: (1) moving the camera lower or back puts it inside the neck, so
  rejected; (3) the weapon sight camera is unusable (run 1); (2) ALS's aiming pose
  (`BPI_Set_RotationMode(2)`) showed the rifle at the bottom right in run 2 (aim near the wall,
  rotation mode 2), with no clipping. So `WeaponUp` keeps rotation mode Aiming in first person
  while a weapon is out, except when sprinting (ALS cannot sprint while aiming) or in melee.
- **The game froze** right at the first weapon draw. The draw command never returned and no mod
  wrote anything after 02:30:45: no crash report, the game thread just stopped. No other mod had
  changed since run 2. The restore closed the game, `mods.txt` was restored and the 81 saves
  were identical.
- Testing stopped there, as agreed (no relaunch). The cause is not confirmed: the new code only
  acts once a weapon is out, but the freeze came inside the draw call itself. `WeaponUp` ships
  **off** and is marked experimental; the released behaviour is run 2's.
- Later found: the user's TeamViewer session ended at 02:30:17 (UserDisconnect in its log), 28 s
  before the freeze. Running the game while the remote session drops is the likely cause.

Run 4 (02:48, `WeaponUp` on, with draw logging and an abort on a frozen console; the app kept the
PC awake):
- No freeze. Both weapon draws returned at once, and the mod set rotation mode Aiming right after
  each one.
- **The weapon is in view:** the pistol is held up in front, with its sight near the centre; the
  rifle shows at the bottom centre-right, also while aiming (FOV 65). Pillar at 45 cm: no
  clipping. Sprint flag (`DesiredGait` 2) → rotation mode 1 (gun lowered), back to 2 after.
- The rifle's own sight camera (`SetViewTargetWithBlend(weapon)`) gives an unusable view too; the
  mod soft-left first person meanwhile, then came back. It is not used by the mod.
- Frames over 20 s in first person with the gun up: 9.3 ms average, max 21 ms, 0 over 100 ms.
- 81 saves identical; `mods.txt` restored. `WeaponUp` is now **on** by default.

Not covered: gamepad button, sniper scope in first person, dialogs, melee, hover pack, space walk,
cutscenes, other suits (collars), the inventory screen.

Runs 5–7 (03:02–03:35, aiming down the sights; run 5 froze with the PC idle and was repeated):
- Run 5: the view moves to the weapon's own camera at its `AimTransform` on aim. Rifle and Pulse
  Rifle show a true sight picture. Bursts at a pillar 3 m away hit the screen centre, 3° above
  the front post (the camera sits about 3 cm high). Classes swapped in with `SetChildActorClass`:
  the shotguns, the SMGs and the laser pistol look plausible; the bullet pistol (its
  `AimTransform` is 22 cm to the side, then wrong with a guessed fix), SubmarineRifle (the
  scope blocks the view) and MiscBeam (gun not visible) do not. Frames while aiming: 9.7 ms
  average, max 24 ms.
- Run 6: the -3 cm fix did not show: the game's aim timeline moves the camera back.
- Run 7: the fix is re-applied every frame while aiming. The front post tip now sits at the
  screen centre, so rounds go where it points. Pistol zoom shows the centre dot over its sight.
- Result: sights only for the checked classes (`G.SightCamera`: Bullet_Rifle, Pulse_Rifle);
  every other weapon zooms at the eyes with the dot.
- Freezes: runs 3 and 5a stopped about 17 s after load with no crash. Both times the user's
  TeamViewer session had ended and the PC was idle. Every run with a live session passed.

Run 8 (03:53, release build):
- Gamepad camera button (`GP_SwitchCamera1` `_23`/`_22`): first person off, then on. OK.
- Hover (`StartHover`): third person while flying, first person back after `StopHover`. OK.
- Melee (`C_Melee_36`): nothing happened, because the save has no melee weapon. Untested.
- Sniper class swap: failed (the hover had holstered the weapon). Untested.

## 1. Verdict

A tactical first-person mode on foot is **feasible from UE4SS Lua, without editing Blueprints or paks**.

- The game kept ALS v4's first-person camera. The camera manager puts the camera at the
  `FP_Camera` socket of the player's mesh whenever the player's `ViewMode` is first person.
  The field of view is a plain variable (`FirstPersonFOV`).
- One Blueprint call switches the view: `pawn:BPI_Set_ViewMode(1)`.
- Hand weapons already shoot from the camera centre along the camera's forward vector.
  The muzzle is never used, so shots go exactly where the player looks. There is nothing to
  fix for aim alignment.
- The game deliberately **refuses first person with a weapon drawn**. Its own toggle throws the
  player back to third person 0.2 s after a weapon comes out. It also hides the whole body,
  so the weapon would float in mid-air. The mod therefore does not use the game's toggle.
  It sets the view mode itself, hides only the head, helmet and hair, and puts first person
  back each time the game forces third person. The game forces third person for dialog,
  melee, ragdoll, hover/jetpack and weapon draw.
- What cannot be done without new animations or assets: weapon sights that line up with the
  screen centre in a real ADS pose, first-person-only arm animations, and a weapon model
  sized for first person. ADS therefore starts as a field-of-view zoom. An experimental
  alternative already exists in the game: every hand weapon has its own sight camera, which
  the game uses for sniper scopes.

## 2. What the game has (from the decompiled Blueprints)

### 2.1 Camera pipeline

| Piece | What it does |
|---|---|
| `Q1Controller_C` → `PlayerCameraManagerClass = ALS_PlayerCameraManager_C` | The camera manager. |
| `ALS_PlayerCameraManager_C:BlueprintUpdateCamera` | If the view target has the tag `ALS_Character` (the player `Q1_Character_C` does), it runs ALS's `CustomCameraBehavior`. Otherwise it uses the engine default, which is the actor's active `CameraComponent`. |
| `CustomCameraBehavior` | Blends the third-person pivot camera and the first-person target with the `Weight_FirstPerson` curve. The curve comes from `ALS_PlayerCameraBehavior` (anim BP) and reads `ViewMode` through `BPI_Get_CurrentStates`. FOV = `Lerp(ThirdPersonFOV, FirstPersonFOV, Weight_FirstPerson)`. |
| `ALS_Base_C:BPI_Get_FP_CameraTarget` | `Mesh.GetSocketLocation('FP_Camera')` |
| `ALS_Base_C:BPI_Get_CameraParameters` | Returns `ThirdPersonFOV`, `FirstPersonFOV` and `RightShoulder`. Defaults: 90, 90, true. `Q1_Character.CameraFov(x)` clamps the third-person FOV to 90..110. |
| `ALS_PlayerCameraBehavior` | Third-person offsets, plus a lean offset from `Q1_Character.LeanDirection` and a camera distance from CVars `C_CameraDistance` and `C_CameraAdjustDistance`. |
| `Q1_Character` components `Camera`, `FPCam`, `SpringArm` | Used only in space (EVA): `CameraToFP` and `CameraTo3P` switch between them when `CharacterAtSpace`. On foot the ALS camera manager ignores them. |

Because the camera is computed from the head socket, the first-person view already bobs with
the walk animation (natural head bob). Any lean the body animation has also moves the camera.

### 2.2 View switching functions (`ALS_Base_C` unless noted)

| Function | Effect |
|---|---|
| `BPI_Set_ViewMode(NewViewMode)` (0 = third, 1 = first) | Calls `OnViewModeChanged`: sets `ViewMode`; in first person it changes `RotationMode` from velocity to looking direction. `Q1_Character` overrides it: first person hides `Male_Hair_01`, `HeadLight` and cyborg helmet parts; third person restores head, helmet and hair from oxygen/light state. It does **not** hide the body, does **not** check weapons and does **not** touch the view target. **The mod uses it both ways.** |
| Game camera key (`InpActEvt_X_SwitchCamera_…_51/_52`, pad `InpActEvt_GP_SwitchCamera1_…_22/_23`) | After a 0.2 s retriggerable delay it toggles. It is skipped in dialog, in the game's FP walk mode, while reloading and while flying. To first person: `BPI_Set_ViewMode(1)`, `Mesh.SetVisibility(false)` (whole body hidden), then **`ForceToTP()` if a weapon is out**. |
| `ForceToTP()` | `BPI_Set_RotationMode(1)` → `BPI_Set_ViewMode(0)` → view target back to the pawn → mesh visible → cyborg parts → `CameraTo3P` in space. Not used by the mod: resetting the view target would break a cutscene or dialog camera. |
| `ForceToFP(SniperFP)` | `true`: sniper scope path (view mode 1, `FPS_Camera` event, body hidden). `false`: the toggle path above (kicks back if armed). Not used by the mod. |
| `ForceFirstPersonCameraAndWalk(Off)` | The game's forced first-person walk (some areas). It sets `IsFirstPersonCameraWalkOn`, walk gait only, no sprint, and hides all widgets. Callers are not in the dumped Blueprints. The mod leaves it alone. |
| `RefreshFPS()` | Called 0.2 s after an overlay change while `CurrentStateWeapon` and first person: `ForceToTP()`. **This is why drawing a weapon throws you out of first person.** |

### 2.3 Where the game forces third person

| Trigger | Where | Mod policy |
|---|---|---|
| Weapon drawn while in first person | overlay change → `RefreshFPS` → `ForceToTP` | Put first person back on the next tick. |
| Game camera key with a weapon out | toggle path → `ForceToTP` | With `UseGameCameraKey` (default), the game's first view change after the key sets the player's choice; then the same re-entry applies. |
| Melee attack | `Q1_Character` melee: `if ViewMode == 1 → ForceToTP` | Stay in third person while `MeleeAttackOn?`, then return. |
| Dialog | `Start_Dialog` → `ForceToTP`, dialog camera | Blocked while `AtDialog?`. |
| Ragdoll / knock-down / death | ragdoll start → `ForceToTP` | Blocked while `MovementState == Ragdoll`. |
| Hover / jetpack | `StartHover` → `ForceToTP` | Blocked while `Flying?`. |
| Sniper scope released (if it started in third person) | `Q1_Character.RMB` | Not affected in first person (see 2.5). |
| `RotationMode` set to velocity direction | `OnRotationModeChanged` → `BPI_Set_ViewMode(0)` | Default rotation mode is looking direction, so this is rare. Same re-entry. |

All of these end in `BPI_Set_ViewMode(0)`, so a single post-hook on it sees every kick.

### 2.4 Player character parts

`Q1_Character` is modular. It has `Mesh` (body), `Male_Head`, `Male_Hair_01`, `Helmet_SM`,
`HeadLight`, `N_Jetpack`, cyborg parts (`CyborgHelm`, `CybogUst`, `CyborgUst2`) and the
space-only cameras. The sniper scope path already hides `Helmet_SM` and `Male_Head`, which
proves hiding them is safe. `HideHelmet(bNewVisibility)` and `OxygenAreaToggle` re-show the
helmet when needed, so the mod re-hides head parts on every poll while in first person.

### 2.5 Weapons and aiming

- **Shots come from the camera.** `Master_Hand_Weapon.CalculateTrace` starts at
  `PlayerCameraManager.GetCameraLocation()` and points along the camera manager's forward vector.
  In first person, bullets come from between the eyes towards the screen centre.
- **Recoil (vanilla):** each shot calls `AddControllerPitchInput(rand[-0.25, 0])`,
  `AddControllerYawInput(rand[-0.1, 0.1])`, a camera shake (`Shoot_Shake_C`, scale 15) and
  `CH_Base.AddRecoil()`, which only animates the crosshair. All of this works in first person.
- **Aim (RMB):** in third person, look rates drop to 0.6 and the shoulder camera is used. In
  first person, `BPI_Set_RotationMode(2)` (aiming) with the same look rates. `Q1_Character`
  overrides `RMB(Relesed?)`.
- **Weapon sight camera.** Every hand weapon has its own `CameraComponent` (`Camera`) and two
  transforms, `IdleTramsfom` and `AimTransform`, set per weapon class. The `Aim(aimOn?)` and
  `AimZoom` events blend that camera from idle to aim (timeline) and its FOV from `StartFOV`
  to `CacheFOV`. The global event `FPS_Camera` makes the weapon call
  `PlayerController.SetViewTargetWithBlend(weapon, 0.25)`, so the screen shows the weapon's
  camera.
- **Sniper and Hunter scope:** RMB stores the current view mode, calls `ForceToFP(true)` if in
  third person, hides the weapon, sets look rates to 0.5, hides helmet and head, and calls
  `Q1Hud.UpdateZoom(true, 70, weapon.Camera, …)` for the scope overlay. **In first person the game
  skips `ForceToFP`, so the view stays on the head and the weapon-camera zoom is not seen.** The
  mod moves the view to the weapon while aiming and back on release.

### 2.6 Crosshair

- On foot it is `WB_CrosshairBase_C` (CompShooterHUD pack). `Q1_Character` creates it at spawn
  and stores it in `CrossHair`.
- The weapon's init calls `CH_Base.AddCrosshair(5, white, 1.0)` on every equip (type 5 is
  `Crosshair_06`; there are 11 types).
- Useful calls: `GetCrosshairChild()` (the crosshair alone, which can be hidden while hit and
  damage indicators keep working), `SetCrosshairScale`, `RemoveCrosshair`, `AddHitIndicator`,
  `DamageIndictitator`.
- `Q1Hud` (`DisableCrosshair?`, `HideCrosshair?`, a drawn crosshair material) handles the ship
  and RTS crosshairs. It is not the on-foot one.

### 2.7 Input actions (Enhanced Input events, hookable)

- Camera: `ALS_Base: InpActEvt_X_SwitchCamera_…_51/_52` (keyboard),
  `InpActEvt_GP_SwitchCamera1_…_22/_23` (pad). `_51` and `_22` go to the same handler, and HTR
  already hooks `_22` for its 4-tap mode gesture.
- Aim: `InpActEvt_C_Aim`, `InpActEvt_GPC_Aim` → `RMB(…)`.
- Lean: `Q1_Character: InpActEvt_C_LeanLeft/Right_…_37…_40`, `GPC_LeanLeft/Right`. They call
  `Set Lean Mode(±1)`, which only works while aiming (`RotationMode == 2`), and set
  `LeanDirection` (0 none, 1 left, 2 right).
- Also present: `C_SniperZoom`, `C_Shoot`, `C_Reload`, `C_Melee`, `C_ToggleWeapons`,
  `C_SwitchWeapon1..3`.

## 3. Can first person be toggled from UE4SS Lua?

Yes. These are plain calls to Blueprint functions. HTR already calls Blueprint functions from Lua,
for example `TMWPerkWarning`.

```lua
pawn:BPI_Set_ViewMode(1)                     -- first person (0 = third)
pawn.Male_Head:SetVisibility(false, false)   -- also Helmet_SM, Male_Hair_01
pawn.FirstPersonFOV = 90
pawn:BPI_Set_ViewMode(0)                     -- back to third person; Q1 restores head/helmet
pc:SetViewTargetWithBlend(weapon, 0.15, 0, 0, false)  -- look through the weapon's sight camera
```

To keep first person while the game forces third person, the mod post-hooks
`Q1_Character_C:BPI_Set_ViewMode` (Q1's override of the ALS function, so it fires for the
player only) and marks the state dirty. The next player tick, a post-hook on
`ALS_Base_C:ReceiveTick`, re-enters first person once nothing blocks it. Re-entry is
deliberately deferred to the next tick: calling back into the same Blueprint's ubergraph from
inside its own call could overwrite its temporaries.

## 4. What breaks, and how the mod handles it

| Area | Problem | Handling | Confidence |
|---|---|---|---|
| Head and helmet clipping | The camera sits at the head socket. | Hide `Male_Head`, `Helmet_SM` and `Male_Hair_01`. `SetCastHiddenShadow(true)` keeps the head shadow. Re-hide while in first person. | High (the scope path does the same) |
| Body seen from inside | With the body visible, looking down may show the inside of the neck or collar, or clip the chest. | `FP_Camera` is in front of the face in ALS. `Body = "Hidden"` is the fallback (game style). | Medium, **test** |
| Weapon visibility | In the game's own first person the body is hidden but the weapon is not, so it would float. | Default `Body = "Full"` keeps arms and weapon attached. | Medium, **test** |
| Aim alignment | None: shots come from the camera centre. | Nothing to do. | High |
| ADS | The ALS aim pose holds the rifle at the shoulder, not at the eye, so sights do not line up with the screen centre. | FOV zoom ADS (default). Weapon sight camera as an experiment. | High (zoom) / unknown (sight camera) |
| Sniper scope in first person | The game zooms the weapon camera, which is not the view in first person. | View moves to the weapon while aiming. | Medium, **test** |
| Animations | Third-person animations seen from the eyes: rolls, mantles, hit reactions and melee can be nauseating. | Melee and ragdoll already force third person. Rolls and mantles: watch in test; option to switch to third person during them later. | Medium |
| Death and ragdoll (0.1.2) | A crash on dying in first person (11-04, access violation inside a Lua callback): the mod kept calling the engine (view target, view mode, weapon camera) while the game tore the pawn and weapon down. | Hook `ALS_Base_C:OnDead`: for the player, no engine calls for 15 s and all state reset. While `MovementState` is ragdoll, plain property reads only. Tested 2026-11-05: two deaths in first person (aiming, rifle up), each followed by a save load; no crash. | High |
| Reticles and shotgun sights (0.1.3) | While aiming, the game's crosshair (Clear HUD's copies live inside it) and the HUD's small blue reticle (`Q1Hud.CHWidget`, a `Test_Crosshair_C` switcher shown for laser and shotgun weapons) stayed on screen. Both shotguns' sight camera has a relative yaw of 5 degrees in the blueprint, so the holo sat off-centre and the gun looked skewed. The switch to first person did all its engine calls in one frame (8 to 20 ms). | Both reticles hidden while aiming down the sights and restored after (checked every 0.05 s while aiming); the HUD one is also given back when a ship is boarded. The shotgun sight camera is straightened while aiming (its rotation comes back after the view blend) and lowered 10.2 cm. The switch to first person is spread over frames (view, near clip, pose). Tested 2026-11-05: mouse and gamepad aim, both shotguns with the holo's aim mark on the screen centre, pistol zoom keeps one dot, longest mod update 8 to 11 ms (the near-clip console command, once per switch). | High |
| Pistol sights (0.1.4) | Both pistols inherit the base weapon's sight camera, built for a gun pointing along Y: turned 90 degrees and 22 cm to the side of the pistol, whose mesh points along X like the rifles. So pistols only zoomed. | The pistol camera gets a fixed position (`G.SightCamera` `Pos`) read from the mesh vertices (section bounding boxes; the shotgun's holo glass comes out 0.1 cm from its in-game calibration): bullet pistol behind the centre of its holo glass (Y 0, Z 13.6), laser pistol 0.4 cm under its front post tip (Z 10.7), both 22.4 cm behind the grip. While aiming it looks down the barrel (rotation 0, held in the same engine call as the position) and gets its own 90 degrees back after. Tested 2026-11-06: holo red dot and front post on the screen centre, mouse and gamepad aim, aiming cost the same as the rifle (0.23 ms per frame). | High |
| Ships and vehicles | Another pawn is possessed. | The mod only acts when the ticking `Q1_Character` is the possessed pawn and the view target is the pawn. | High |
| Space (EVA) | The game uses its own `FPCam`/`Camera` components in space. | Blocked while `CharacterAtSpace`; vanilla behaviour. | High |
| Cutscenes and dialog | Another camera is the view target. | Blocked while `AtDialog?` or the view target is not the pawn. If a cutscene starts while in first person, the head comes back (`BPI_Set_ViewMode(0)`). The mod never changes a view target it did not set. | High |
| Menus and inventory | The inventory preview uses separate display characters (`Master_Visiual_Character_*`), not the player. | Nothing to do; **test** that no headless character appears. | Medium |
| Game's forced FP walk (`ForceFirstPersonCameraAndWalk`) | The game hides widgets and blocks sprint. | Left to the game. | High |
| Gamepad aim assist | `AutoAimComponent` snaps to heads with a gamepad, which is arcade behaviour. | Out of scope for now (open question). | n/a |
| HTR gesture | HTR's 4 quick presses of the pad camera button switch the view 4 times. | The mod follows whatever view the game ends in. Note: the game's 0.2 s retriggerable delay may collapse quick presses into fewer switches. | Medium, **test** |

## 5. Tactical FPS features: what is feasible without editing Blueprints or paks

| Feature | How | Feasible? | Phase |
|---|---|---|---|
| First person on foot, with weapons | `BPI_Set_ViewMode(1)` + head hiding + re-entry | Yes | 1 |
| Configurable FOV | `FirstPersonFOV` | Yes | 1 |
| No crosshair (or small) in first person | `CrossHair:GetCrosshairChild():SetVisibility(Hidden)` after each equip | Yes | 1 |
| ADS zoom | FOV blend on `RMB` | Yes | 2 |
| Scoped weapons in first person | View on the weapon while aiming | Yes, test | 2 |
| Real sights (iron sights / red dots) | The weapon's own `Camera` at `AimTransform` | Maybe: depends on how the transforms look in game | 2 (experimental) |
| Recoil per caliber | Post-hook `SpawnProjectile`, `AddControllerPitchInput` | Yes | 3 |
| Weapon sway / breathing while aiming | Small control-rotation noise per tick, or the camera hook | Yes (control rotation); camera hook needs verification | 3 |
| Head bob | Comes from the animation (camera on the head socket) | Present already; damping needs the camera hook | 3 |
| Lean | The game has it (Q/E-style inputs, only while aiming) | Probably works; whether the first-person camera follows is to test | 2 (test only) |
| Smooth FOV, head-bob damping | Post-hook `ALS_PlayerCameraManager:BlueprintUpdateCamera` and write `NewCameraFOV`/rotation | Unverified: the event is called from native code; check that out-param writes stick | 3 (experimental) |
| Tie-in with HTR (broken arm → more sway, bleeding → blur) | HTR runs in its own Lua state; would need a shared file or a merge into HTR | Possible later | 4 |
| First-person arms and weapon models, real ADS pose | New animations and assets | **No** (needs pak modding) | n/a |
| Weapon collision (gun pushed back near walls) | Needs animation layers | **No** | n/a |

## 6. Configuration

- `scripts/config.lua`: `Enabled = false` by default. The mod then registers nothing at all.
- `UseGameCameraKey = true`: the game's own "switch camera" key and gamepad button switch views.
  This follows the realism-set key plan (revision 2c): every laptop-safe key is used by the set,
  and F11 is the game's fullscreen toggle.
  - The mod does **not** switch on that key itself. The game switches 0.2 s after the press,
    so both switching would cancel out, and the player could end in the game's own first
    person with the body hidden.
  - Instead, the first view change within 0.6 s of the press decides what the player wants
    (`V.onGameCameraKey` / `V.onSetViewMode`). Going to first person, the game hides the body
    and, with a weapon out, throws back to third person. The next player tick turns that into
    the mod's first person: body visible, head hidden, weapon kept.
  - The game still refuses the key in dialog, while reloading and while flying; the mod follows.
  - The choice is remembered in `state.txt`.
- `ToggleKey = ""`: optional extra mod hotkey, off by default.
  - Shift is the only modifier, because on foot Ctrl opens the map and Alt crouches.
  - F1, F2, F5, F6, F8, F10, F11 and F12 are refused, with or without Shift, because the game
    reacts to them anyway (orders, quick save, quick load, bug report, fullscreen, Steam screenshot).
  - Plain F3 and F4 are refused because they are fleet orders in ships.
  - The log warns when the key is one another mod of the set uses.
  - UE4SS matches modifiers exactly: a plain bind does not fire on Shift+key (verified in game
    for HTR 0.4.4).
- `StartInFirstPerson = false`.
- `Body = "Full"` or `"Hidden"`, `HeadShadow`, `FOV = 90`.
- `ADS.Mode = "Zoom"` or `"SightCamera"`, plus `ADS.ZoomFOV` per weapon group and `ADS.BlendSeconds`.
- `Crosshair = "Hidden"`, `"Small"` or `"Game"`.
- `Recoil` and `Experimental.CameraHook` (phase 3, off).
- `PollSeconds = 0.1`, and `Debug.Log` / `Debug.SlowHookMs` (same watchdog as HTR).

## 7. Performance

| Item | Cost / risk | Mitigation |
|---|---|---|
| `ALS_Base:ReceiveTick` post-hook | Fires every frame for every ALS character, and HTR already hooks the same function. | The common path is one `os.clock()` compare and return. When due, the ticking actor is only a world context for `GetPlayerPawn` (instant); no per-NPC class checks or allocations. Work runs at 10 Hz, or about once per frame only while something is pending (dirty state, FOV blend of 0.15 s). |
| Property reads per poll | About 10 reads plus `GetPlayerPawn`, `GetPlayerController` and `GetViewTarget` (all instant). | Target below 0.1 ms per poll. Checked with the watchdog and the 30 s profile. |
| Hook registration | A failed `StaticFindObject` costs ~37 ms. | The same lazy registration as HTR: at most one miss per second, with backoff to 16 s. |
| `FindAllOf` / `FindFirstOf` | ~50 ms each. | Never used. The key press only sets a flag; the next tick applies it. |
| `SetVisibility`, `SetViewTargetWithBlend` | Engine calls. | Only on state changes. Head re-hide only when `bVisible` is true. |
| Ping-pong with the game | If something unknown keeps forcing third person, the mod would re-enter every tick. | 4 kicks in 3 s → back off 5 s and log it. |
| Camera hook (phase 3) | One Lua call per frame on the camera manager. | Off by default. Budget < 0.05 ms per frame, measured before release. |
| Rendering | First person with the body visible renders the same meshes as third person. | None needed. |

## 8. Implementation plan

**Phase 0: probe (dev REPL, no release).** Confirm the facts the design rests on:
`BPI_Set_ViewMode(1)` with a rifle out, where `FP_Camera` sits, hiding head and helmet, the
`ReceiveTick` hook rate, the `BPI_Set_ViewMode` hook firing on kicks, and
`GetCrosshairChild()`. Also look through `weapon.Camera` with `SetViewTargetWithBlend` for a
rifle and a pistol.

**Phase 1: first person on foot (MVP).** Following the game's camera key, re-entry after kicks, blockers, head hiding,
FOV, crosshair, HUD message, `state.txt`. Off by default. Frame-time test.

**Phase 2: aiming.** FOV-zoom ADS per weapon group, scoped weapons in first person, a lean check,
and the sight camera experiment (keep it only if it looks right).

**Phase 3: feel.** Per-caliber recoil (could reuse HTR's caliber table), breathing sway while
aiming (less when crouched, more when tired or wounded), and the camera hook experiment for
smooth FOV and head-bob damping.

**Phase 4: release.** Gamepad check (same camera button path), decide whether it ships alone or inside
HTR, installer support, README, Nexus/Steam text, full test pass with frame times.
Nexus images (publish-checklist.md in the shared notes, "Nexus → Images"):
- Make a 16:9 cover with `side-session-notes\make_cover.py` (ratio 2.2 for banner v2 or v4).
- Upload the cover as the primary (tile) image, plus the original 3:1 banner.
- Commit the cover as `docs/cover.png`.

## 9. In-game test plan

Run each step with `Debug.Log = true`, then read `tfps.log` (warnings, slow hooks, 30 s profile).

| # | Test | Pass |
|---|---|---|
| 1 | Load a save with `Enabled = false` | Log says disabled; no hooks; frame time unchanged. |
| 2 | `Enabled = true`, on foot, no weapon, press the game's camera key | First person with the body visible (not the game's hidden-body view); no head, hair or helmet in view; the camera key again returns to third person with the correct helmet state; `state.txt` follows. Repeat with a rifle drawn: first person is kept after the game's kick. |
| 3 | Draw each weapon type in first person | Stays in first person (at most a brief flicker); arms and weapon visible, not floating. |
| 4 | Look fully up and down; walk, sprint, crouch, jump, roll, mantle | No inside-of-head view; note any body clipping and nausea from rolls and mantles. |
| 5 | Shoot at a wall at 5, 20 and 50 m | Impacts at the screen centre. |
| 6 | Aim each group (pistol, SMG, rifle, shotgun) | Smooth zoom in and out; crosshair hidden; HTR damage unchanged. |
| 7 | Sniper and Hunter aim in first person | Scope overlay with real zoom; on release, back to the head with the weapon visible. |
| 8 | `ADS.Mode = "SightCamera"` | Note what the view looks like per weapon (usable or not). |
| 9 | Lean (game keys) while aiming | Note whether the first-person camera leans. |
| 10 | Melee, dialog, ragdoll (explosion), hover/jetpack | Third person during the action, first person back afterwards; no ping-pong warning. |
| 11 | Enter and leave a ship, a hoverbike, an elevator; load a save; die and respawn | No head hiding on other actors; first person comes back on foot. |
| 12 | Open the inventory and character screen in first person | No headless preview character. |
| 13 | Space walk (EVA) | Vanilla camera, mod idle. |
| 14 | Gamepad camera button; press it while reloading and in dialog; tap it 4 times quickly (HTR gesture) | Button switches like the key; refused while reloading/dialog (mod follows); after the 4 taps HTR's mode changes and the mod ends in the same view as the game. |
| 15 | Frame time: a 60 s firefight in first person vs third person, with HTR also loaded | No new stutter; no slow-hook warnings; profile shows the mod below 1 ms per 30 s on average. |

## 10. Open questions (for the user)

1. **Body:** true first person (body and arms visible, head hidden; recommended), or the game's
   own style (body hidden, weapon may float)?
2. **ADS:** start with FOV zoom (safe), and try the weapon sight camera as an experiment?
3. **Crosshair in first person:** none (recommended for tactical), small, or the game's own?
   Keep the hit markers?
4. **Key:** the game's own camera key and button, with no mod hotkey (key plan revision 2c,
   now the default). OK, or do you want a spare key freed for a mod hotkey?
5. **Packaging:** a separate mod (as built here), or a feature inside HTR (one installer, can use
   HTR's calibers and wounds for recoil and sway)?
6. **Gamepad aim assist:** turn it off in first person for realism?

## 11. Research notes

- Blueprints read: `Q1_Character`, `ALS_Base`, `Master_Hand_Weapon` (already dumped).
  Newly dumped for this design (kept local, never committed): `ALS_PlayerCameraManager`,
  `ALS_PlayerCameraBehavior`, `Q1Controller`, `Q1Hud`, `FPS_Camera`, `WB_CrosshairBase`,
  `E_CrosshairType`, and the ALS interfaces.
- Every name the mod uses is in `scripts/tfps/gamedefs.lua`.
- `sb2dump` must run from a short path. The scratch folder path is too long for Win32, and the
  run fails with "path longer than allowed".
