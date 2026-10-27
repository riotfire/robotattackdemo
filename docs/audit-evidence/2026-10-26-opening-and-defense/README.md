# Opening, checkpoints and defense loop — October 26, 2026

Built from the recalibrated playtest simulation report (branch `claude/beautiful-yalow-10a844`, section 6: ship short breaks, phase checkpoints and the authored opening together) and the defense proposal's slices 2-6. See ROADMAP section 4.13.

Results on Godot 4.7.2, headless, fixed 60 fps, each run on its own temp profile:

- Unit suite (GUT): 211 tests. 210 passed on the full run; the one failure was a test expectation that predated the waves 7-9 budget ramp, fixed and re-run (34/34 in `test_difficulty_curve.gd`).
- `tests/smoke/opening_test.tscn` (73 checks): passed on seeds 7, 42 and 1234.
- `tests/smoke/smoke_test.tscn` (135 checks): passed on seeds 7, 42, 1234 and 2024.
- `tests/smoke/tutorial_test.tscn` (67 checks): passed on seed 7.
- Economy probe, 256 seeds, waves 1-6 (authored): full collection about 243 Al / 49 Cu / 8 Au / 8.6 PC; 50% Vac only about 121 / 27 / 6.5 / 7.8. Waves 6-9 average 15, 23, 28 and 47 robots.

Not done: no normal-speed human playtest, no rendered screenshots of the new HUD panels, and the simulator in `tools/playtest_sim` still models the old rules.

## Playtest rework (same day)

After the user's playtest: 90 s intermissions, no quick-buy panel, no free items, free placement of defenses, and an easier opening (ROADMAP section 4.13, "Playtest rework"). Results on Godot 4.7.2, headless, fixed 60 fps:

- Unit suite (GUT): 212/212 passed.
- `tests/smoke/opening_test.tscn` (82 checks): passed on seeds 7, 42 and 1234.
- `tests/smoke/smoke_test.tscn` (136 checks): passed on seeds 7 and 1234.
- `tests/smoke/tutorial_test.tscn` (67 checks): passed on seed 7.
- A windowed render of the placement ghost: green for a barricade on open ground, red with "Too close to the Spring Trap" over an existing copy.

Not done: no normal-speed human playtest of the rework; the economy probe was not re-run for the lighter opening.
