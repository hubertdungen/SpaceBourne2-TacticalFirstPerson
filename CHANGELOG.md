# Changelog

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
