# Changelog

## 0.1.10 (2026-11-12)

- **Fixed: lean flipping or sticking in first person.** The game counts lean key presses and
  releases, but only while the character is in its aiming stance; first person changes the
  stance as you play (weapon up, sprint, melee, draws), so a press could be lost while its
  release still counted: the lean flipped to the other side and stayed there after you let go.
  The mod now sets the lean from the keys you actually hold (keyboard and gamepad). Tested in
  game: the sequence that left the lean stuck to the right on 0.1.9 now ends straight, and
  leaning right then letting go works every time.

## 0.1.9 (2026-11-08)

- **Fixed: memory kept while aiming.** Each time the mod placed the sight camera it handed the
  engine a fresh scratch table, and the script loader (UE4SS 3.0.1) keeps every such table for
  good: about 1.5 MB a minute of aiming, collected in longer and longer pauses. The mod now
  reuses one table and moves the camera only when it is not already in place. In testing, 18
  minutes of fighting with up to 20 enemies kept the mod's memory flat (under 1.6 MB) at about
  100 fps, with no freeze and no stutter from the mod.

## 0.1.7 (2026-11-08)

- **Steadier in long fights.** The mod's update ran once for every character on screen each
  frame, enemies included; in a long fight with many enemies this left work for the script's
  memory cleaner, and the game stuttered for up to 90 ms at a time, more as the fight went on.
  It now runs once per frame, from the HUD. In testing, 18 minutes of fighting with up to 20
  enemies ran at about 100 fps with no freeze (0.1.6 froze after 3 minutes of the same test).
  The reticle checks now change the HUD only when something needs to change.
- **Silent camera switch:** switching first/third person no longer shows a "First person
  ON/OFF" line, whose HUD beep sounded on every switch.
- **The sight waits for the gun:** the view moves to the sight only once the gun points where
  you look, so it never swings with the gun (aiming while sprinting or right after a draw).
- **New option `LowReady`** (off by default): `"Pistols"` or `"All"` keep those weapons in the
  game's low hold until you aim.

## 0.1.6 (2026-11-06)

- **Fixed: the pistol aim flicker and the camera whip on release.** On every aim press and
  release the game plays a short aim animation that moves the weapon's sight camera to its own
  place (on pistols turned 90 degrees and 22 cm to the side). The mod's straight sight and that
  animation took turns from frame to frame, so the view flicked sideways when you started
  aiming and could swing round when you stopped. The mod now puts its sight back right after
  the game's animation on every frame, and gives the camera back to the game only once the view
  is fully back at your eyes. This also steadies the rifle and shotgun sights at the start of
  aiming.
- **Quick clicks:** aiming and letting go before the view has reached the sight (or pressing
  again on the way back) now turns the view around smoothly instead of snapping.
- **Weapon switch while aiming:** putting a gun away or drawing another one while aiming no
  longer drags the view along with the gun's swing; an aim pressed while a gun is being drawn
  starts once it is up.

## 0.1.5 (2026-11-06)

- **Fixed: a UE4SS crash with many mods** ("Fatal error" in UE4SS.dll, at the main menu or in
  play). Background loops (LoopAsync) run on their own threads without UE4SS's lock, and two
  mods calling ExecuteInGameThread from there at the same moment broke a map UE4SS shares
  between all mods. The mod's once-a-second hook check now runs on the game thread, from the
  player's own tick (new `tfps\gametick.lua`, the same file in every mod of the set). The
  crash is gone only once every mod of the set has this change.

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
