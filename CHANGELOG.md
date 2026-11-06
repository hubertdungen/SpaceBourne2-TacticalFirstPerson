# Changelog

## 0.1.4 (2026-11-06)

- **Pistols aim through their own sights.** The bullet pistol puts its holo's red dot on the
  screen centre; the laser pistol lines up its front post over the red V. The game's sight
  camera for pistols is turned 90 degrees and sits beside the gun, so until now pistols only
  zoomed. While you aim, the mod puts your eye behind the sight, measured on the guns' 3D
  models, and points it down the barrel. Shots go where the sight points.

## 0.1.3 (2026-11-05)

- **No reticle while you aim.** In first person, aiming (right mouse button or the gamepad aim)
  hides every reticle: the game's crosshair, Clear HUD's reticle (it lives inside the game's
  crosshair) and the HUD's small blue reticle of laser and shotgun weapons. They come back when
  you stop aiming. Pistols and other zoom-aimed weapons keep only the small centre dot.
- **Shotguns aim through their red holo sight**, the laser one ("Pulse Charger") included. The
  game's sight camera for shotguns is turned 5 degrees to the right of the barrel, which put the
  holo off-centre and showed the gun from the side. While you aim, the mod now points it straight
  down the barrel and puts your eye behind the holo (calibrated in game).
- **Smoother switch to first person.** The work done when first person turns on (view, near
  clip, weapon pose) is spread over a few frames. In testing, the longest mod update dropped from
  up to 20 ms to 8 to 11 ms, once per switch to first person, with only a few such spikes in
  eight minutes of play.

## 0.1.2 (2026-11-05)

- **No crash when you die in first person.** When the player dies, the mod now stops touching
  the camera, the view and the weapon for 15 seconds, while the game plays the death and cleans
  up. While your body is ragdolled (falls, knockouts), the mod only reads the game's state and
  changes nothing. Tested in game: two deaths in first person (one aiming down the rifle sights,
  one with the rifle up), each followed by loading the save; no crash, and first person came back
  after each load.

## 0.1.1 (2026-11-01)

Thanks to **TheCalcMan** (Steam) for the report.

- **No more camera drop after reloading.** Two seconds after each reload the game moved the view to
  the gun's own camera (a leftover of its sniper scope), so the view sat at your hip until you
  pressed "switch camera" twice. The view now stays at your eyes, and first person stays on.
- A bigger lean in first person (also asked by TheCalcMan) is being worked on for the next update.

## 0.1.0 (2026-11-01)

- First person on foot with the game's own camera key or gamepad button; it stays on when you
  draw, switch or fire a weapon.
- A drawn weapon is held up in front of you (the game's aiming pose); sprinting lowers it.
- Head, helmet and hair are hidden; look down to see your legs and feet.
- Aiming down the sights with assault and pulse rifles (the shot goes where the front post
  points); other weapons zoom with a small centre dot; sniper and hunter rifles keep the game's
  scope.
- "First person ON/OFF" on the HUD when you switch; your choice is remembered.
- No crosshair in first person (hit markers stay).
- Third person for dialogs, melee, falls, the hover pack, space walks and cutscenes; first person
  comes back afterwards.
- Near clip plane 5 cm in first person (game: 10) so your collar and the gun's stock are not cut.
- On by default.
