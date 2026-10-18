**Audit evidence — October 18, 2026**

The product assessment is in `../GAME_AUDIT_AND_COMMERCIAL_PLAN.md`. These files preserve the observations behind it. The probe is diagnostic only and does not change the game’s main scene or production scripts.

| File | Purpose |
|---|---|
| `unit-tests.txt` | Successful GUT run: 34 tests, 1,894 assertions |
| `smoke-seed-42.txt` | Passing 93-check smoke run |
| `smoke-seed-1234.txt` | Failing smoke run: 38 of 82 executed checks fail |
| `performance-baseline.txt` | Successful graphical probe output, including environment and scenario counters |
| `performance_probe.gd`, `performance_probe.tscn` | Reproducible diagnostic scenario |

Run from the repository root. Replace the binary path if needed. The existing tests require permission to write their dedicated temporary profiles in Godot’s user-data directory. Run smoke seeds sequentially because the smoke test uses the same temporary profile filename.

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd
```

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/smoke/smoke_test.tscn -- --seed=42 --profile=/private/tmp/robot-attack-audit-smoke.json
```

Repeat the smoke command with `--seed=1234` for the failure case. The smoke fixture itself switches to `user://smoke_test_profile.json`; the command-line profile prevents initial loading of a normal player profile.

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --path . --disable-vsync --resolution 1280x800 res://docs/audit-evidence/performance_probe.tscn -- --profile=/private/tmp/robot-attack-performance-profile.json
```

The probe stops the wave director, fixes the camera and seed, increases objective health, samples the empty farm, spawns 60 mixed robots, and kills them together to stress pickups and effects. It writes a disposable profile under `/private/tmp` and exits automatically. The short samples establish an investigation baseline, not minimum system requirements. Repeat in release exports, collect GPU timings, and use longer gameplay traces before making performance commitments.

The first diagnostic attempt had an invalid `current_scene` parent assignment; that setup was corrected and the successful rerun is the preserved baseline. Initial unit-test save failures were caused by sandbox restrictions; the successful rerun is preserved. Neither failed setup is treated as a production-game defect.
