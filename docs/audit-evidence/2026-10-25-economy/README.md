# Climber and economy revision — October 25, 2026

The silo ladder, dome and existing barn cable are unchanged. The lower-connector recommendation was removed from the defense proposal.

Implemented changes: from wave 3, roughly 25% individual wall-climbing Roof Lobbers, reserved within the existing threat budget; staged live caps and scarce drones; revised material drops/costs; earned even-wave salvage; directly banked Foreman rare bounty; fixed earned bell rewards; parts retained until the next battle starts. Dedicated silo-ladder attackers and new defensive items remain proposed work.

Validation:

- Full GUT suite: 168/168 tests, 11,889 assertions, exit 0. Includes 32 seeds × 40 waves of roster checks, nested-scene roof ascent, reward conservation/persistence, and pickup phase boundaries.
- Real-game smoke scenario, seed 7: 132 checks passed, exit 0. Uses god mode and a silo/grain floor; this is an assisted mechanics test, not an unassisted survival test. Existing dome-to-barn cable traversal passed.
- Tutorial scenario, seed 7: 67 checks passed, exit 0.
- Economy probe: real main-scene configuration and spawn buying over 256 seeds, waves 1–6; analytical drop expectations without luck/traits. Full collection versus no manual collection plus 50% Scrap Vac. Both assume all enemies killed and waves cleared; the Vac model includes the next battle-start sweep after the final sampled wave. Optional bell income, tutorial rewards, spending and defeat are excluded.
- `git diff --check` passed. Profiles were isolated in process-specific system temporary files; gameplay tests did not use the player's profile.

The engine emitted a macOS CA-certificate warning, and some runs report ObjectDB/resource cleanup warnings at exit. All listed checks completed with exit 0. No normal-speed human balance comparison or performance benchmark was performed. These results do not establish that the six-wave difficulty wall is resolved.

Reproduce the model:

```sh
/Users/DH_1/Downloads/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/economy-probe.log --path . --script res://tools/economy_probe.gd -- --probe-seeds=256 --probe-last-wave=6
```

Files: [model](economy-probe.json), [unit run](unit-tests.txt), [smoke run](smoke-seed-7.txt), [tutorial run](tutorial-seed-7.txt). The first smoke run exposed stale assertions about a 120-second timer, immediate bell payment, clear-time vacuum and randomized starting sky. Assertions now cover the current 90-second timer, earned payment, battle-start sweep and existing Dawn/Clear start. Its nested-scene roof discovery issue was fixed and independently covered by an actual ascent regression.
