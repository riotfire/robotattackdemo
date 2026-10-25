# Level 0: Morning Chores

An untimed prologue (`WaveDirector.Phase.TUTORIAL`) that a profile plays once before wave 1. The player collects parts, buys a wrench on the pegboard, hits a dummy, heals, then intercepts a real attacker and repairs any damage it caused. A ground ring and trail show where to go; the normal HUD shows how to act and tracks progress. A short lesson line explains why. The pistol is a later build choice. `-- --tutorial` replays the prologue; `-- --skip-tutorial` skips it. Profiles saved before Level 0 existed that have already played count as finished.

## How it teaches

| Device | What it says | Code |
|---|---|---|
| Floor ring | Shows the destination at ground level without covering an object or leaving the camera view as Pip approaches. | `TutorialMarker` |
| Normal action prompt | Shows the next tutorial action in the same HUD position used for repair, interactions, and movement during waves. A nearby usable object takes priority. | `Hud.set_tutorial_action`, `Hud._update_player` |
| Normal progress and health bars | The existing repair/interaction bar fills while sealing a leak or ringing the bell. The existing HP bar shows porch healing. | `Hud._update_player` |
| Pebble trail | Glowing dots from Pip to the goal along the navmesh, pulsing toward it. | `TutorialTrail` |
| Short lesson line | Explains the immediate cause and effect: parts buy a weapon, hits damage the silo, a repaired crack stops the leak. Changes after the player acts. | `Hud.set_tutorial_lesson` |
| Dummy reaction | The Dummy-Bot visibly wobbles on each wrench hit, then pops and drops parts after the combo. | `TutorialDummy` |
| Shed shutter | A roll-down steel door stays closed throughout Level 0 and during attacks. It opens for the first build choice after wave 1. | `ToolShed` |
| Safe rehearsal | A slow Nibbler heads for the silo. The player can intercept it with the wrench; if it lands one hit, it pauses and opens a small crack. Killing it and repairing the crack completes the same loop used in waves. | `TutorialDirector._begin_practice` |
| Vista | From the 8 m catwalk a camera held out over the rail sweeps to the chicken house, the water tower and the corn lanes while the HUD lesson describes each view. Control returns facing the dinner bell. | `TutorialDirector._start_vista` |
| First build choice | After wave 1, the HUD points to the open shed and names the first play-style options: wrench power, pistol range, repairs/defense, and speed. The prompt clears after a purchase or when the next attack starts. | `Hud._on_wave_phase_changed` |

## Steps

1. **Tractor parts**: six Aluminium bits float together beside the tractor, like a robot drop after it lands. Walking through the cluster banks the 6 Al needed for the wrench. The first-run tractor always appears in the same slot.
2. **Pegboard**: open the shed pegboard, focused on Grandpa's Wrench, and hold Buy on its peg. The purchase equips the wrench.
3. **Dummy-Bot**: at (-18, 0, 17) on hay bales, 75 HP (three wrench hits, the third a x1.5 finisher). It drops 5 Al that fly to Pip, and its spring glove bonks Pip for 20 HP.
4. **Porch**: stand on the Home porch (heal zone) until HP is full.
5. **Practice defense**: intercept one slow Nibbler heading for the intact silo and attack it with the wrench. If it hits, the tutorial pauses it after one strike and opens a 40-Structure crack. Destroy the Nibbler, then repair that crack. Stopping it before the hit moves straight to the catwalk.
6. **Catwalk**: climb the silo ladder to the top. Input freezes for ~4.5 s for the vista; control returns facing the dinner bell.
7. **Dinner bell**: hold Interact. Finishing all chores pays +5 Al (Early Bird); the siren winds up for 3 s and wave 1 starts with the wrench as the only weapon. The bell works from the start for anyone who wants to skip (no bonus). Skipping cleans up practice enemies and lesson cracks.
8. **First intermission**: the shed opens after wave 1. Parts earned from defending the silo can go toward melee, the 20 Al Rivet Pistol, repair/defense, or speed. No branch is required before another, so the next upgrade reflects what the player found difficult or fun.

The bell lesson names both threats: silo damage and grain theft. The first theft in a run gets a short cue to pop the thief; its dropped sack gets a cue to walk over it and return the grain.

## Differences from the design doc

- **Layout:** the spec's coordinates don't match the built farm. Stations use the real positions (silo at the origin, Home porch at (-30, 29), bell at (-21, 32)), so the route is tractor, shed pegboard, dummy, porch, practice defense, silo ladder, bell.
- **Dummy drop:** 5 Al. With the +5 Al lesson reward, this leaves a new player short of the pistol's 20 Al cost until they earn parts by defending wave 1.
- **Not built yet:** the Section 5 signposting for later waves (low-HP porch lantern, shed whistle and compass pip, worn footpaths), and the Hub pegboard dolly (the existing 2D board is used). The returning-player skip prompt is just the normal bell during intermission.
- **Sound:** reuses existing cues (`robot_pop`, `wrench`); the claxon, banjo chord and chime need new audio.

## Files

- `scripts/systems/tutorial/`: `tutorial_director.gd` (step machine), `tutorial_marker.gd`, `tutorial_trail.gd`, `tutorial_dummy.gd`.
- Hooks: `WaveDirector` (`TUTORIAL` phase, `finish_tutorial`), `Silo.open_tutorial_crack`, `ToolShed` (lock and shutter), `DinnerBell`, `Pickup.attract_to`, `Hud.set_tutorial_action` and first intermission prompt, `SaveManager.tutorial_completed`, `Main` (starts it).
- Test: `tests/smoke/tutorial_test.tscn` (also see the unit tests at the end of `tests/unit/test_save_and_waves.gd`).
