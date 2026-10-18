# Robot Attack!

A cute claymation third-person wave-defense shooter. This is the M1 vertical slice from [Robot_Attack_GDD.md](Robot_Attack_GDD.md) (section 21), built on the M0 graybox prototype. Godot 4.7, Forward+, Jolt physics, physics interpolation on, statically typed GDScript.

Open the folder in Godot 4.7 and press Play (main scene: `scenes/main/main.tscn`). The first click captures the mouse; Esc releases it.

## What's in M1

- **Farm:** every building from GDD 4.4 with ladders, hay-bale stairs, the porch trellis and ziplines Z1 (silo dome → barn), Z2 (water tower → silo catwalk) and Z3 (barn → stables). Each run scatters seeded props (hay, crates, fences, scarecrows, a tractor) and rebakes the navmesh around them.
- **Robots:** Nibblers (scouts; about 10% of the wave's spawns steal 20-bushel grain sacks in wave 1, rising 1.5 points each wave to a 40% cap; a Thieving family multiplies that by 1.5, up to 60%), Clanker squads of 3 hitting in a clank-clank-CLANK rhythm, and Thumpers whose slams send a shockwave ring you can jump over. Every Big Haul wave (5, 10, 15…) brings a crowned Foreman. Each wave is one procedural family (3 themes, 9 palettes, 4 traits) with a name card and a 6-character family code.
- **Economy:** parts burst out of robots and magnetize to you; the Scrap Vac collects a share when a wave ends. The tool shed pegboard has 33 upgrades across Travel, Attack, Repair, Defend and Farmhand. The Rivet Pistol is the first purchase (20 Al); you start with the wrench.
- **Persistence:** parts, upgrades, the jetpack, records and the Robot Almanac save to `user://profile.json` (on macOS, `~/Library/Application Support/Godot/app_userdata/Robot Attack!/`). Autosaves happen at each intermission start, after each purchase and on game over.
- **Look:** a clay shader (lumps, thumbprints, subsurface scattering, and a 12 fps surface "boil" driven by `StopMotionClock`). Robot poses step at 12 fps and the farmer's squash and stretch at 24 fps. The barn, water tower, well, windpump, fences, crates and plants are clayified CC0 models (see [CREDITS.md](CREDITS.md)); the ground is tinted felt, the sky a painted backdrop with cotton-ball clouds, and the corn wall hand-cut paper stalks. UI text is Fredoka SemiBold.

## Controls (GDD 5.2)

| Action | Keyboard + mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | Left stick / right stick |
| Jump; hold in the air for the jetpack; hold while aiming to hover (Hover Mode) | Space | A |
| Aim (zoom, walk) / fire | Right mouse / left mouse | LT / RT |
| Wrench bonk | V | R3 |
| Interact: repair (hold), shed pegboard, dinner bell (hold), zipline | E | X |
| Reload | R | X |
| Weapons: tap for the last weapon, hold for the weapon wheel (point at a weapon, let go to equip) | Q (point with the mouse); 1 wrench, 2 pistol (1–6 as more arrive); mouse wheel cycles | Y (point with the right stick) |
| Shoulder swap | Middle mouse | — |
| Pegboard (shed open): move / buy / close | Mouse: hold click on a peg to buy | D-pad or left stick / hold A / B or Start |
| Ladders | Walk into them; W/S climb; Space steps onto a catwalk or lets go | |

Intermissions run 2 minutes for now, long enough to browse the pegboard; the design target is 30 s once the Hub pegboard lands (see [docs/ROADMAP.md](docs/ROADMAP.md), D1). Try other lengths with the console's `intermission <seconds>`. The jetpack unlocks for free after wave 2. The Home porch heals 15 HP/s. Ring the dinner bell by the porch to start a wave early and earn the Early Bird bonus.

## Debug keys (debug builds)

F1 help · F2 ring the bell · F3 give parts · F4 clear robots · F5 next wave · F6 god mode · F7 jetpack · F8 damage silo 100 · `` ` `` console: `wave <n>`, `give <al|cu|au|pc|all> <n>`, `godmode`, `jetpack`, `silo <dmg>`, `grain <n>`, `kill`, `bell`, `buy <upgrade id>`, `intermission <seconds>`, `reset` (wipe the profile).

Pass `-- --seed=1234` for a fixed run seed, or `-- --profile=user://other.json` for a separate profile.

## Tests and tools

Replace `godot` with your Godot 4.7 binary (e.g. `~/Downloads/Godot.app/Contents/MacOS/Godot`).

GUT unit tests (GUT 9.7.1 is vendored in `addons/gut`). They cover difficulty curves, upgrade costs and stat stacking, genome determinism and novelty, factory readability locks, save migration, wave buying, robots sliding round building corners, robots following the navmesh round the Home porch, and the weapon framework (weapon data, switching and the wheel, mod hooks and slots, pooled projectiles):

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

End-to-end smoke test (104 checks) that plays the real game headless on its own throwaway profile. Each run rolls a random seed and prints it; add `-- --seed=<n>` to replay one:

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke/smoke_test.tscn -- --seed=1234
```

Verified on 2026-10-17 (M2-A0): all 93 checks pass on seeds 1–100, 1234, 2024, 31337 and 664607717, and on 6 random seeds. Runs can go in parallel, even from different worktrees, since each run uses its own profile file. The smoke-test farmer has god mode but doesn't defend the silo, so the test reseals the silo between sections. If a run ends early, the test stops with one failure that names the section and the reason.

The genome gallery (`tests/tools/genome_gallery.tscn`, GDD 18.9) lines up four families' robots for art review. Press R to reroll and the arrow keys to orbit.

Generated content. The pegboard, the robot archetypes and the robot family genes are edited as CSV tables in `data/source/` (format: [data/source/README.md](data/source/README.md)). Two tools turn them into the `.tres` files the game loads. Edit a table, regenerate, then run the unit tests: `test_content_tables.gd` fails if a `.tres` no longer matches its table, or if an upgrade modifies a stat that no system reads (the orphan-stat rule).

```bash
godot --headless --path . --script res://tools/build_upgrade_catalog.gd
```

```bash
godot --headless --path . --script res://tools/build_robot_data.gd
```

- `build_upgrade_catalog.gd` writes `data/upgrades/` from `data/source/upgrades/`, one `.tres` per pegboard node.
- `build_robot_data.gd` writes `data/robots/` from `data/source/robots/`: archetypes, palettes, themes, traits and the gene library's theme and trait lists.
- Regenerating unchanged tables rewrites identical files, because both tools keep each file's resource ids. That way `git diff data/` shows only what an edit changed. Removing a row deletes its `.tres` file.

The tables are CSV rather than JSON for three reasons. With one row per node or archetype, a diff shows exactly which item changed. Git merges two branches that add rows in different places without conflicts. And the tables open in any spreadsheet for side-by-side balancing. In JSON, each node would be a multi-line object, and every append would edit the previous line to add a comma, so two branches adding nodes would conflict. CSV's cost is a small cell syntax for lists (costs, effects, prerequisites), described in `data/source/README.md`. Each table is a folder, so a work package can add its own file (for example `data/source/upgrades/stun_gun.csv`) instead of editing shared lines.

The farm is generated too. Re-running the tool overwrites its output, so edit the results in the editor once they settle:

```bash
godot --headless --path . --script res://tools/build_graybox_farm.gd
```

- `build_graybox_farm.gd` writes `scenes/farm/`: farm, silo and navmesh. Add `-- --navmesh-only` to rebake only the navmesh from the saved `farm.tscn`.

Clayify pipeline (GDD 19.4). It rebuilds `assets/models/` from the CC0 sources in `assets/source/`, as listed in `tools/clayify/manifest.json`: it bakes material colors into vertex colors, recolors them to the farm palette, welds, bevels, shades smooth, and stretches buildings onto their gameplay dimensions. Pass output names (e.g. `farm/farm_barn_01.glb`) after the three paths to rebuild only those. Re-run `build_graybox_farm.gd` afterwards if a building model changed:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P tools/clayify/clayify.py -- tools/clayify/manifest.json assets/source assets/models
```
- `setup_input_map.gd` rewrites the default input map in `project.godot`.

## Layout notes

Folders follow GDD 18.3, plus `scripts/player`, `scripts/weapons`, `scripts/ui`, `scripts/ai/genome`, `scripts/systems/upgrades` and `tools/`. `WaveDirector`, `PlayerSpawner`, the HUD and the pegboard live in `main.tscn` next to the farm instance, so regenerating the farm doesn't touch them.

The farmer (`scenes/player/farmer.tscn`) is split into components so work packages don't collide in one file: `Farmer` holds the state chart, health, armor, aiming and the model, and ticks `Movement` (run, jump, jetpack, ladders, ziplines), `Repair`, `Interaction` and the `WeaponHolder` in that order each physics frame. Each weapon is a `Weapon` node under the holder with a `WeaponData` resource in `data/weapons/` (base stats, slot, unlock flag and the stat keys its pegboard tracks modify). Shots go through `begin_shot()` and `deliver_hit()`, which run any installed `WeaponMod`'s `on_fire`, `on_hit` and `on_kill` hooks. Setting a weapon's `projectile_speed` above 0 switches it from hitscan to pooled projectiles (`ProjectilePool`).
