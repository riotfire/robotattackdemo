# Opening audit evidence — October 25, 2026

Supports [the first-five-waves plan](../../FIRST_FIVE_WAVES_FUN_PLAN.md). Snapshot: repository HEAD `23b8683` plus the pre-existing uncommitted working tree. No production gameplay files were edited by this audit.

Files:

- `opening_probe.gd` / `.tscn`: reproducible audit fixture, isolated `/tmp` profile per process.
- `schedules.json`: 100 seeds × five wave rosters, budgets, timing, and expected ordinary drops. Wave-five roster/drop fields exclude the separately inserted Foreman; add one robot and its fixed drops when calculating wave-five totals. Copper uses the actual per-enemy Bernoulli drop chance. Aluminium expectations include scaling before stochastic rounding, which preserves that expectation.
- `runtime.json` / `headless.log`: real five-wave observation, seed 7, no attacks or purchases, at fixed 60-Hz simulation steps. The farmer is invulnerable; silo Structure and Grain are floored at 500, cracks are repaired between waves, and all remaining robots are removed after window + 5 seconds. Damage totals beyond 1,000 are counterfactual pressure with this protection, not damage a normal silo can survive. No player win rate or combat time-to-kill can be inferred.
- `rendered.log` / `wave-1.png` through `wave-5.png`: the same observer with an explicitly positioned gameplay camera, 1280×800, Morning/Clear, and 4× time scale. Images are taken about 30 simulated seconds into each wave. Wave five's image precedes the Foreman's scheduled arrival at 32.85 seconds. Runtime outcomes differ from headless because camera/player placement and simulation timing differ. Do not treat shown FPS counters as performance measurements.

The final headless run completes all five observations with no roof fallback or script errors. It reports 13 ObjectDB instances and three resources still in use at shutdown; these are retained transparently in the log. This was not a clean memory-leak test. Earlier discarded fixture runs had an incorrect scene root, causing rooftop enemies to fall back to the ground; those results were replaced. The final fixture instantiates Main directly under the tree root, so normal rooftop lookup works.

Run from the project root with the installed Godot executable:

```sh
/Users/DH_1/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://docs/audit-evidence/2026-10-25-opening/opening_probe.tscn -- --seed=7 --time=morning --weather=clear
```

For graphics:

```sh
/Users/DH_1/Downloads/Godot.app/Contents/MacOS/Godot --path . --windowed --resolution 1280x800 --time-scale 4 res://docs/audit-evidence/2026-10-25-opening/opening_probe.tscn -- --seed=7 --time=morning --weather=clear
```

Output files go to `/tmp/opening-schedules.json`, `/tmp/opening-runtime.json`, and `/tmp/opening-wave-N.png`; archive them before another run. The saved evidence directory contains copies from the inspected runs. Add `--schedule-only` to stop after the schedule audit. These runs write unique disposable profiles and do not open the normal player profile.

Schedule derivation uses the actual director's event builder and consumes lane selection from the wave RNG before building events, matching normal play. Robot AI, targeting, drops actually collected, path travel, and combat execution are not simulated by the schedule table. The complete runtime observer provides the separate travel/pressure evidence.

Expected Copper after waves one and two is 5.25 averaged across the 100 schedules, before collection loss or spending. Wave one is 1.35; wave two averages 3.90. This is an analytical drop expectation, not observed earnings from 100 human runs. An immediate 120-second wave-two bell pays `floor((120 - 3) * 1.2) = 140 Al`. A no-purchase wave one's nine Nibblers yield 22.5 Al in expectation with full collection, before tutorial and bell grants.

Images were inspected individually. The native opening run additionally exposed the current default camera, incoming cards, first melee kill/breakup, cumulative crack labels, and game-over feedback. Development controls and protected observations were used; no unassisted completion is claimed. Audio mix, gamepad feel, human stress ratings, and normal-speed performance still require the playtests specified in the plan.
