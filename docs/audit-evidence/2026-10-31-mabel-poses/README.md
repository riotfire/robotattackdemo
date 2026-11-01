# Mabel animation QA, October 31, 2026

Every pose and transition of the Mabel model, driven through the real farmer scene with real input. Regenerate with:

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --path . --always-on-top --fixed-fps 60 --resolution 1600x900 res://tests/tools/pose_gallery.tscn -- --out=/tmp/pose-gallery
```

Add `--only=jump,ladder` for some scenarios. `--always-on-top` matters on macOS: a covered window is throttled and the run stalls.

| File | Shows |
|---|---|
| `clips*.png` | Every raw clip (the 20 in the glb plus the three built aim clips) at eight evenly spaced times |
| `idle.png`, `walk_run.png`, `aim_strafe.png` | Standing, walking and running at several stick strengths and stopping; aiming in six directions |
| `fire.png`, `reload.png`, `melee.png` | Gun and swing reactions, standing reload and reload on the move |
| `jump.png`, `ledge.png`, `jetpack.png` | Jumps, walking off a ledge, jetpack climb, long fall and landing |
| `ladder.png`, `zipline.png` | Climbing up and down, hanging still, jumping off, mantling; taking hold of the line, riding, firing, jumping off at four points on the line and the line running out |
| `rope.png` | The raw `Swing_on_Rope_to_Ground` clip, 24 evenly spaced frames from the side and from the front |
| `hurt.png`, `death.png` | Hit flinch and flash; the full death |
| `game_*.png` | Full-frame shots through the farmer's own camera |
| `report.txt`, `ticks.csv` | Measured clip speeds, the largest per-tick bone jumps, and one row per 24 fps tick |

## What QA found and what changed (scripts/player/mabel_model.gd)

- Idle was the first frame of the walk, a mid-stride pose, and stopping froze her wherever the stride was. Idle is now the 10 s `Idle_3` loop.
- Clip changes cut hard: run to idle, jump to idle and idle to rope grip were 85-158 degree single-tick jumps. Every change now fades from a snapshot of the pose on screen, which also works for held clips that a normal cross-fade cannot move. The worst non-swing jump is now a run cycle's own motion.
- Feet skated: the walk and run clips cover 1.29 and 4.41 m/s but the code assumed 2.0 and 6.0. Constants are measured and the walk/run handover moved to 2.4 m/s.
- Aiming on the move glided: the shooting-walk clips only shuffle (about 0.3 m/s) while the aim walk is 4 m/s. Aim clips are built at load from the running legs under the aiming torso and arms; backing away plays the legs in reverse.
- The jump played its crouch while she was already rising, then cut to idle at touchdown. It now starts at the push-off, holds the touchdown pose in the air, plays the clip's landing recovery, and ends on standing. Ledges join past the top of the arc (letting go of a zipline plays the rope clip instead, below); drops faster than a plain jump lands use `Fall2`.
- The weapon pointed into the wall on ladders; it is now stowed there.
- The zipline read as aiming a gun with the cable through her face, and as a rigid pole-hang with a plain jump to get off. `Swing_on_Rope_to_Ground` (4.33 s) is now the whole zipline: she takes hold (clip 0.2 s) and is yanked into the swing, easing to the swung-out hang at 0.8 s, where she holds for the ride, legs trailing; letting go plays the clip on from 1.15 s through its tumble to 2.3 s, then the touchdown crouch and the rise to standing at 3.4 s, which hands over to idle. The tumble is paced to the real drop (a ray to the floor gives the time to touchdown; the clip plays 0.8-2x to meet it, and a short drop, like the end of the line, joins it part way), so the crouch starts within a tick of her feet reaching the ground (`ticks.csv`, scenario `zipline`: the last airborne tick leaves the clip's feet 6-9 cm above the floor). A drop longer than the clip holds the pre-landing pose and then braces with `Fall2`; the jetpack or a ladder cancels it; holding the stick on touchdown skips the crouch and runs. The weapon is stowed through the tumble and the first frames of the crouch, where her hands are up by her face. About the arms: the rope clip is a swing on a vertical rope: her hands sit 0.35-0.55 m in front of her and below the top of her head, and no clip has both hands overhead on a horizontal line. After the clip poses her body, both arms are now turned straight up toward the cable (`_pose_zipline_arms`), and she is lowered until her palms are at cable height (read from the zipline's `hang_height`). The weapon is also stowed while she hangs; firing swings the right arm forward and shows the gun while the left hand stays on the line.
- Hits did nothing visible to Mabel (her skin is not the clay shader): there is now a red flash and, when standing, the `Hit_Reaction_1` flinch (once per second at most).
- Reloading plays `Standing_Reload` stretched to the weapon's reload time.
- Death snapped the whole rig 80 degrees; it plays `Dead` now and the jetpack can, which is not part of her rig, is hidden.

Known and left alone: sideways strafing uses the forward aim legs (no strafe clip); the ladder clips climb 0.46 m/s (`Fast_Ladder_Climb`, kept) and 0.25 m/s (`Ladder_Climb`) against a 4 m/s ladder, so the rate (2.2) is a readability compromise; weapons follow the hand's position but not its rotation; `Knock_Down`, `Fall3`, `Stand_Up1`, `Jumping_Down`, `Hop_with_Arms_Raised`, `Run_and_Shoot` and `Attack` are imported but unused because the game has no knock-down, victory or tucked-gun-run state for them yet.

Validation on Godot 4.7.2/macOS: full GUT suite 241/241 tests; main smoke 141/141 checks, seed 42.
