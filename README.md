# Robot Attack!

A cute claymation third-person wave-defense shooter. This is the M1 vertical slice from [Robot_Attack_GDD.md](Robot_Attack_GDD.md) (section 21), built on the M0 graybox prototype. Godot 4.7, Forward+, Jolt physics, physics interpolation on, statically typed GDScript.

Open the folder in Godot 4.7 and press Play (main scene: `scenes/main/main.tscn`). The first click captures the mouse; Esc releases it.

## What's in M1

- **Farm:** every building from GDD 4.4 with ladders, hay-bale stairs, the porch trellis and ziplines Z1 (silo dome → barn), Z2 (water tower → silo catwalk) and Z3 (barn → stables). Each run scatters seeded props (hay, crates, fences, scarecrows, a tractor) and rebakes the navmesh around them.
- **Phases and checkpoints:** a phase is 3 waves: a Lesson, a Twist and a Big Haul with a Foreman (waves 3, 6, 9, ...). Losing (farmer down, silo destroyed, grain gone) offers **Retry Phase N**: the phase's first wave again with a full silo and every part and upgrade kept. **Start over at Phase 1** is the other choice, and quitting and relaunching continues at the checkpoint ([phase plan](docs/PHASE_CHECKPOINT_PROGRESSION_PLAN.md)).
- **The authored opening (waves 1-6):** First Bonks (15 Nibblers in a steady stream of singles and pairs from one lane), Take the High Ground (two **Roof Lobbers** on the tool shed while you only have melee: climb up after them, with Nibblers streaming in below; clearing it unlocks the **Rivet Pistol** and every gun after it), the first Foreman (350 HP, a 1.2 s slam tell, then a glowing x3 back vent that any close hit from behind counts on, so the wrench alone can win; its defeat calls off the adds), Stop That Sack (a Clanker pair, one teaching thief, a Lobber on the barn roof), Up the Ladder (a **Rung Runner** climbs the silo ladder while raids hit the far side: the first wave where a Spring Trap at the ladder top matters) and the second Foreman (900 HP, from the far side, throwing dirt clods at anyone who keeps away). Both Foremen wear plates: shots from more than 6 m do 30% unless they hit the open vent. Arrivals burst out of the crops 45 m out, and a wave ends the moment nothing is left; clearing a wave never hands over an item ([opening plan](docs/FIRST_FIVE_WAVES_FUN_PLAN.md)).
- **Vertical threats:** after the opening about 25% of individual robots are climbers: Roof Lobbers, which climb the barn, chicken house, stables or tool shed and throw arcing shots from the roof, and Rung Runners, which climb the silo ladder (two at a time, clanking) and bash the silo from the first catwalk, so its cracks open up there. Drones join from wave 7 (one on their debut), fly around the silo and fire from above. Shots telegraph with a glowing charge, and lobs mark where they will land with a chalk circle. Only a few robots shoot the farmer at once; the rest shoot the silo, and hits open cracks at the height they land.
- **Sidearms:** from wave 13 ("the robots fight back") some small robots come as pea-shooting Spitters that stand off, shoot at catwalk height and hop between shots, Clankers and Thumpers throw bolts and dirt clods (twice, with a chalk circle) at a farmer they can't reach, and a Clanker's arm guard halves hits from the front, so flank it. Later waves shorten charges, lead straight shots and fire volleys instead of only adding numbers.
- **Defenses (stables only):** between waves, press E / X at the stables workbench and choose **Build**: Spring Trap **12 Al**, Scarecrow Decoy **6 Al**, Scrap Barricade **8 Al**. There is no learning step or unlock fee. **Improve defenses** at the same workbench buys trap, wall, assembly and capacity upgrades; the tool shed has no BUILD board. One copy assembles at a time; stand by the workbench to help. Unfinished stock and empty pickup markers are hidden. Completed items appear with their name, **READY**, and a pickup prompt. Collect one, carry it to a green preview, then E / click deploys it at no further cost. Tab and the siren return carried items to their origin; unfinished assembly pauses during battle. Capacity counts queued, ready, carried and deployed copies. First-use guidance points to the workbench; ready items identify themselves. Placed defenses retain move, repair and dismantle options.
- **Robots:** Nibblers (scouts, usually in trios; in generated waves about 10% of the spawns steal 20-bushel grain sacks at first, rising 1.5 points each wave to a 40% cap; a Thieving family multiplies that by 1.5, up to 60%), Clankers (now and then a trio) and Thumpers whose slams send a shockwave ring you can jump over. Trios hit in a 3-beat rhythm, and a thief trio is a heist crew whose two escorts guard the sack. Each robot has behavior variables (silo focus, distraction triggers, chase time, leash): a "!" pop shows when one turns on the farmer. Every Big Haul wave (3, 6, 9, ...) brings a crowned Foreman; each Foreman wave pays its 2 PC + 1 Au bounty once per profile. Each wave is one procedural family (3 themes, 9 palettes, 4 traits; no traits in the opening) with a name card and a 6-character family code.
- **Level 0 "Morning Chores" (first run):** an untimed prologue that starts with a cluster of floating Aluminium by the tractor. Collect it, buy Grandpa's Wrench on the pegboard, bonk the Dummy-Bot, and heal on the porch. Then stop one slow, real Nibbler. If it hits the silo, finish it and repair that leak. Climb the catwalk to see the robot lanes, then ring the bell for a melee-only wave 1. The practice Nibbler pauses after one hit, giving you time to respond. Details are in [docs/LEVEL_0_MORNING_CHORES.md](docs/LEVEL_0_MORNING_CHORES.md).
- **Economy:** parts burst out of robots and magnetize to you; parts remain through the following intermission and Scrap Vac sweeps leftovers when the next battle starts. Even-wave clears bank 2 Copper, 1 Gold and 1 Power Cell; Foreman rare bounties bank immediately. Upgrade prices retain Aluminium at high ranks and lower scarce-material costs. The tool shed pegboard covers Attack, Defend, Repair, Travel and Farmhand; crafted defenses and their upgrades are at the stables. As parts accumulate, buy the short-range Barn Blaster, long-range rifle, group-clearing grenades, Haymaker Maul or 360-degree Harvest Scythe, the trapper's upgrades at the stables (which use Copper, Gold and Power Cells); later add air dash and ground pound to the jetpack. Springy Soles and Zipline Grip are retired and refunded; every gun fires from a zipline.
- **Silo warnings:** the first hit sounds a distinct alarm when you are away from the silo. A red banner shows its direction, distance and remaining Structure; if cracked grain is still leaking after the attack, an amber repair reminder remains until the leaks are sealed. Repeated hits share an alarm cooldown. Between attacks the silo card names the worst leak with its direction and time to seal, and sealing one plays a relief chime. A climbing warning shows while a Rung Runner is on the silo ladder or catwalk. Below 30% HP a red edge points you to the nearest heal: the porch (15 HP/s) or the new well heal 12 m from the silo (8 HP/s).
- **Persistence:** parts, upgrades, the jetpack, records, the phase checkpoint, first-completion rewards and the Robot Almanac save to `user://profile.json` (on macOS, `~/Library/Application Support/Godot/app_userdata/Robot Attack!/`). Autosaves happen at each intermission start, after each purchase and on game over. Profiles from before 3-wave phases migrate to the checkpoint after their best wave.
- **Look:** a clay shader (lumps, thumbprints, subsurface scattering, and a 12 fps surface "boil" driven by `StopMotionClock`). Robot poses step at 12 fps and the farmer's squash and stretch at 24 fps. The barn, water tower, well, windpump, fences, crates and plants are clayified CC0 models (see [CREDITS.md](CREDITS.md)); the ground is tinted felt, the sky a painted backdrop with cotton-ball clouds, and the corn wall hand-cut paper stalks. UI text is Fredoka SemiBold.
- **Time of day and weather (M2-H1, GDD 4.6):** each run starts at one of six lighting presets (Dawn, Morning, Noon, Golden Hour, Dusk, Moonlit Night) and steps to the next whenever a phase is completed, blending over 6 s in 12 fps steps. It also rolls one weather for the whole run: Clear, Breezy (the corn wall sways), Drizzle (clay droplets, puddles, shinier clay, darker felt) or Morning Fog (shorter sight lines, stronger eye glow; long-range robots get 80% of their range once they exist). Both come from the run seed. Presets and weathers are `.tres` files in `data/environment/`.

## Controls (GDD 5.2)

| Action | Keyboard + mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | Left stick / right stick |
| Jump; hold in the air for the jetpack; hold while aiming to hover (Hover Mode) | Space | A |
| Aim (zoom, walk) / fire | Right mouse / left mouse | LT / RT |
| Equipped melee attack; wrench quick bonk while holding a gun | V | R3 |
| Air dash / ground pound after their shed unlocks | Shift / Ctrl in the air | LB / RB in the air |
| Interact: repair (hold), shed pegboard, dinner bell (hold), zipline, a placed defense's menu, build the ghost | E | X |
| Stables workbench: build / improve; pickup area: collect; carrying: place | E; E or left click to place | X; X or RT to place |
| Carrying a defense: return it to its origin; at the workbench: open its menu | Tab | Back / Select |
| Harvest Report: Retry Phase / Start over at Phase 1 / pegboard | R or Enter / Backspace / P | A / Y / Start |
| Reload | R | X |
| Weapons: tap for the last weapon, hold for the weapon wheel (point at a weapon, let go to equip) | Q (point with the mouse); 1–7 select wrench, pistol, shotgun, rifle, grenades, maul, scythe; mouse wheel cycles | Y (point with the left stick) |
| Shoulder swap | Middle mouse | — |
| Pegboard (shed open): move / buy / pin as goal / close | Mouse: hold click on a peg to buy; P pins | D-pad or left stick / hold A / Y / B or Start |
| Build and defense menus: choose / pick / close | W/S, hold E or click / Esc | D-pad / hold A / B |
| Pause / development menu | Escape | Start |
| Ladders | Walk into them; W/S climb; Space steps onto a catwalk or lets go | |

The pause menu freezes gameplay and includes Restart Phase N, Start over at Phase 1, Continue at the furthest phase, a wave selector, next-wave and bell controls, plus debug tools for parts, god mode, the jetpack, clearing robots, and silo damage. Restart, no parts (wave 1 with zero parts, saved to the profile) and New game (erases the whole profile and replays Level 0; click it twice) are there too.

Intermissions run 90 seconds, siren included: time to walk to the shed and shop, build defenses and get back. Shopping and building never pause the clock. Try other lengths with the console's `intermission <seconds>`. The siren shutters the shed and closes construction. The jetpack's blueprint comes with clearing wave 9 on the profile; then it can be built at the shed for 40 Al and 15 Cu in any run. The Home porch heals 15 HP/s. Ring the dinner bell by the porch to start a wave early; its five-Al base Early Bird bonus is paid only after that wave clears, and only for a wave above your best.

## Debug keys (debug builds)

Escape opens the pause / development menu. F1 help · F2 ring the bell · F3 give parts · F4 clear robots · F5 next wave · F6 god mode · F7 jetpack · F8 damage silo 100 · F9 next time of day · F10 next weather · `` ` `` console: `wave <n>`, `give <al|cu|au|pc|all> <n>`, `godmode`, `jetpack`, `silo <dmg>`, `grain <n>`, `kill`, `bell`, `buy <upgrade id>`, `intermission <seconds>`, `reset` (wipe the profile).

Pass `-- --tutorial` to replay Level 0 on a profile that has finished it, `-- --skip-tutorial` to skip it, `-- --seed=1234` for a fixed run seed, `-- --start-wave=7` to start at a wave instead of the profile's checkpoint, or `-- --profile=user://other.json` for a separate profile. `--time=<preset>` (`dawn`, `morning`, `noon`, `golden_hour`, `dusk`, `moonlit_night`) and `--weather=<type>` (`clear`, `breezy`, `drizzle`, `morning_fog`) force the run's starting time of day and weather.

The existing silo-ladder → dome → barn cable route is retained based on gameplay testing; wave 5 puts a Rung Runner on the silo ladder and a Lobber on the barn roof, so the cable connects two fights. Turrets remain later work; see [the defense proposal](docs/DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md).

## Tests and tools

Replace `godot` with your Godot 4.7 binary (e.g. `~/Downloads/Godot.app/Contents/MacOS/Godot`).

GUT unit tests (GUT 9.7.1 is vendored in `addons/gut`). They cover difficulty curves, upgrade costs and stat stacking, genome determinism and novelty, factory readability locks, save migration, wave buying, robots sliding round building corners, robots following the navmesh round the Home porch, the weapon framework (weapon data, switching and the wheel, mod hooks and slots, pooled projectiles), time of day and weather (phase stepping, seeded rolls, the fog range hook, every preset under every weather), robot explosions (parts fly, land and clean up; quiet exits don't explode; freeze frames and screen shake always recover), the Overcharged trait (x2 Power Cell chance; death blasts chain one fuse at a time through a pack, credit the farmer who started them, hurt farmers in range and skip robots that escape), 3-wave phases and every threshold on a phase start, the checkpoint save and v1 migration, that clearing waves never hands over an item, the jetpack milestone, the authored opening's rosters, the Rung Runner on the real silo ladder and catwalk, springs, decoys and barricades, and every construction rule (free placement against the world, robots and other copies, the catwalk ring, reserve, one job at a time, capacity, refunds that settle once, the siren cutoff, moving, repairing, dismantling):

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

End-to-end smoke test (136 checks) that plays the real game headless on its own throwaway profile. Each run rolls a random seed and prints it; add `-- --seed=<n>` to replay one:

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke/smoke_test.tscn -- --seed=1234
```

After the 2026-10-26 playtest reworks (90 s intermissions, no quick-buy panel, no free items, free placement, an easier opening, the pistol after the first Lobber, plated Foremen, split-pressure waves) the 136-check version passed on seeds 7 and 1234, the 92-check opening test on seeds 7, 42 and 1234, the 214-test unit suite and the 67-check tutorial on seed 7. Earlier that day the 135-check version passed on seeds 7, 42, 1234 and 2024 and the 73-check opening test on seeds 7, 42 and 1234 ([evidence](docs/audit-evidence/2026-10-26-opening-and-defense/README.md)). The 132-check version passed on seed 7 on 2026-10-25 ([climber/economy evidence](docs/audit-evidence/2026-10-25-economy/README.md)). The earlier 115-check version passed on seeds 1, 2, 3, 7, 42, 99, 1234, 2024, 31337 and 664607717 on 2026-10-18 (M2-A0's 93 checks passed on seeds 1–100 and 6 random seeds). Runs can go in parallel, even from different worktrees, since each run uses its own temp profile file. The smoke-test farmer has god mode but doesn't defend the silo, so the test reseals it between sections. If a run ends early, the test stops with one failure that names the section and the reason.

Opening test (96 checks): plays waves 1-7 of the real game with a scripted defender and checks the playtest-simulation package and the defense loop: 90 s intermissions, every authored wave (the wave 2 Lobber before any gun and the pistol it unlocks, live caps, the teaching thief, the plated 350 HP Foreman calling off its adds, the Rung Runner while a raid hits the far side, the 900 HP Foreman's clods at full health), that no wave hands over an item, the checkpoint, and construction (visit the stables, build directly, reserve parts, assemble, physically pick up and carry a copy, cancel or place it, and the siren cutoff) with a catwalk spring throwing a climber off:

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke/opening_test.tscn -- --seed=7
```

Level 0 test: plays the whole prologue headless on a fresh profile (tractor parts, pegboard, Dummy-Bot, porch, melee practice Nibbler, repair after its hit, catwalk, bell) and checks that wave 1 begins with only the wrench:

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke/tutorial_test.tscn -- --seed=7
```

The genome gallery (`tests/tools/genome_gallery.tscn`, GDD 18.9) lines up four families' robots for art review. Press R to reroll and the arrow keys to orbit.

The pickup gallery (`tests/tools/pickup_gallery.tscn`) shows the aluminum gear, copper spring, gold ring and blue power-cell battery at actual size on grass and dirt. N toggles day/night and Space freezes the spin. Add `-- --out=/tmp/pickup-gallery` to save both lighting previews and exit. Robot loot uses small emissive silhouettes, a gentle ground hover, and one cached mesh per resource type with a shared material and no shadow passes.

The rendered first-kill regression (`tests/tools/first_kill_probe.tscn`) runs the real boot warm-up, then destroys two robots with all four loot types. It reports death CPU time, the slowest frame, and pipeline compilation counts; it fails if either kill compiles a new pipeline. Run with graphics enabled (not `--headless` or `--skip-boot`) and `-- --profile=/tmp/first-kill-profile.json`. Loading renders the loot and explosion samples above the farm, with a floor for the scorch decal, so their first-use rendering work finishes before Play.

The explosion gallery (`tests/tools/explosion_gallery.tscn`) pops a Nibbler, Clanker, Thumper and Foreman one by one, grenades a fresh row, then sets off a pack of Overcharged robots to show the chain reaction, for tuning `RobotExplosion` and the death blast with the real camera shake and freeze frames. Space pops the next robot, G throws a grenade, R refills the row, C lines up the Overcharged pack.

The atmosphere gallery (`tests/tools/atmosphere_gallery.tscn`) shows the farm with robot families in the crop rows at 10, 25 and 45 m, for checking that robots stay readable under every preset and weather. F9 and F10 step the time of day and weather, Tab switches the camera, G toggles grayscale. To save every view, preset and weather as PNGs plus color and grayscale contact sheets, run it in a window with an output folder:

```bash
godot --path . res://tests/tools/atmosphere_gallery.tscn -- --out=/tmp/atmosphere
```

The reproducible economy probe uses the real roster generator and catalog to report seeded composition and expected income (including guaranteed rewards), with full-collection and 50%-Vac models. These are economy estimates, not player survival tests:

```bash
godot --headless --path . --script res://tools/economy_probe.gd -- --probe-seeds=256 --probe-last-wave=6
```

Generated content. The pegboard, the robot archetypes and the robot family genes are edited as CSV tables in `data/source/` (format: [data/source/README.md](data/source/README.md)). Two tools turn them into the `.tres` files the game loads. Edit a table, regenerate, then run the unit tests: `test_content_tables.gd` fails if a `.tres` no longer matches its table, or if an upgrade modifies a stat that no system reads (the orphan-stat rule).

```bash
godot --headless --path . --script res://tools/build_upgrade_catalog.gd
```

```bash
godot --headless --path . --script res://tools/build_robot_data.gd
```

```bash
godot --headless --path . --script res://tools/build_opening_waves.gd
```

```bash
godot --headless --path . --script res://tools/build_defense_data.gd
```

- `build_upgrade_catalog.gd` writes `data/upgrades/` from `data/source/upgrades/`, one `.tres` per pegboard node.
- `build_robot_data.gd` writes `data/robots/` from `data/source/robots/`: archetypes, palettes, themes, traits and the gene library's theme and trait lists.
- `build_opening_waves.gd` writes `data/opening/wave_<n>.tres` (the authored waves 1-6) from `data/source/opening/`.
- `build_defense_data.gd` writes `data/defenses/` (spring trap, decoy, barricade) from `data/source/defenses/items/`.
- Regenerating unchanged tables rewrites identical files, because both tools keep each file's resource ids. That way `git diff data/` shows only what an edit changed. Removing a row deletes its `.tres` file.

The tables are CSV rather than JSON for three reasons. With one row per node or archetype, a diff shows exactly which item changed. Git merges two branches that add rows in different places without conflicts. And the tables open in any spreadsheet for side-by-side balancing. In JSON, each node would be a multi-line object, and every append would edit the previous line to add a comma, so two branches adding nodes would conflict. CSV's cost is a small cell syntax for lists (costs, effects, prerequisites), described in `data/source/README.md`. Each table is a folder, so a work package can add its own file (for example `data/source/upgrades/stun_gun.csv`) instead of editing shared lines.

The farm is generated too. Re-running the tool overwrites its output, so edit the results in the editor once they settle:

```bash
godot --headless --path . --script res://tools/build_graybox_farm.gd
```

- `build_graybox_farm.gd` writes `scenes/farm/`: farm, silo and navmesh. Add `-- --navmesh-only` to rebake only the navmesh from the saved `farm.tscn`.

Clayify pipeline (GDD 19.4). It rebuilds `assets/models/` from the CC0 sources in `assets/source/`, as listed in `tools/clayify/manifest.json`: it bakes material colors into vertex colors, recolors them to the farm palette, welds and bevels, then optionally subdivides, displaces and decimates before stretching buildings onto their gameplay dimensions. `max_tris` rejects an asset that exceeds its explicit triangle budget. Pass output names (e.g. `farm/farm_barn_01.glb`) after the three paths to rebuild only those. Re-run `build_graybox_farm.gd` afterwards if a building model changed:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 -P tools/clayify/clayify.py -- tools/clayify/manifest.json assets/source assets/models
```
- `setup_input_map.gd` rewrites the default input map in `project.godot`.

## Layout notes

Folders follow GDD 18.3, plus `scripts/player`, `scripts/weapons`, `scripts/ui`, `scripts/ai/genome`, `scripts/systems/upgrades` and `tools/`. `WaveDirector`, `PlayerSpawner`, the HUD and the pegboard live in `main.tscn` next to the farm instance, so regenerating the farm doesn't touch them. `TimeOfDay` and `Weather` live in `farm.tscn` next to the `WorldEnvironment` and `Sun` they drive; they follow `EventBus` signals, not the `WaveDirector`.

The farmer (`scenes/player/farmer.tscn`) is split into components so work packages don't collide in one file: `Farmer` holds the state chart, health, armor, aiming and the model, and ticks `Movement` (run, jump, jetpack, ladders, ziplines), `Repair`, `Interaction` and the `WeaponHolder` in that order each physics frame. Each weapon is a `Weapon` node under the holder with a `WeaponData` resource in `data/weapons/` (base stats, slot, unlock flag and the stat keys its pegboard tracks modify). Shots go through `begin_shot()` and `deliver_hit()`, which run any installed `WeaponMod`'s `on_fire`, `on_hit` and `on_kill` hooks. Setting a weapon's `projectile_speed` above 0 switches it from hitscan to pooled projectiles (`ProjectilePool`).

Robot AI: melee decisions now run through LimboAI 1.8.1 behavior trees with shared squad blackboards and perch-aware approach points. Existing targeting, sidearm throws, boss hooks and defenses remain in the shared body/controller layer. See [docs/ROBOT_AI.md](docs/ROBOT_AI.md) for the physics order, task layout and tests.

Wave warnings use brief spotter calls tied to the actual lanes: “They're coming in by the barn!” or “Spotted by the house and tool shed!” Wave, family and battle-plan details remain on their HUD cards.
