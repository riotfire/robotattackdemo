# Content tables

The pegboard, the robot archetypes and the robot family genes are edited here as CSV. Two tools turn the tables into the `.tres` files the game loads:

```bash
godot --headless --path . --script res://tools/build_upgrade_catalog.gd
```

```bash
godot --headless --path . --script res://tools/build_robot_data.gd
```

Then run the unit tests (`godot --headless --path . -s addons/gut/gut_cmdln.gd`). `tests/unit/test_content_tables.gd` fails if a `.tres` file no longer matches its table, so don't edit the generated files in the inspector. It also fails if an upgrade modifies a stat that no system reads (see [The orphan-stat rule](#the-orphan-stat-rule)).

| Table (folder) | Generates | Tool |
|---|---|---|
| `upgrades/` | `data/upgrades/<branch>_<name>.tres` | `build_upgrade_catalog.gd` |
| `robots/archetypes/` | `data/robots/archetypes/<id>.tres` | `build_robot_data.gd` |
| `robots/palettes/` | `data/robots/palettes/<id>.tres` | `build_robot_data.gd` |
| `robots/themes/` | `data/robots/themes/<id>.tres` | `build_robot_data.gd` |
| `robots/traits/` | `data/robots/traits/<id>.tres` and the gene library's lists | `build_robot_data.gd` |
| `robots/attacks/` | `data/robots/attacks/<id>.tres` | `build_robot_data.gd` |
| `robots/battle_plans/` | `data/robots/battle_plans/<id>.tres` | `build_robot_data.gd` |

## How the tables work

- **A table is a folder.** The tool reads every `.csv` file in the folder in file-name order, and each file starts with its own header row. You can add rows to an existing file, or a work package can bring its own file (for example `upgrades/stun_gun.csv`) so that parallel branches never edit the same lines.
- **One row is one item:** one pegboard node, one archetype, one palette. Its `id` also names the generated file. If you delete a row, the tool deletes its `.tres` file.
- **Columns are matched by header name**, so their order doesn't matter. An unknown column is an error.
- **A blank cell keeps the script's default.**
- **A row whose first cell starts with `#` is skipped.** Use this to switch a node off without deleting it.
- **Lists inside a cell:** single words are separated by spaces (`tin_can barrel`), and items made of several words are separated by `;` (`al 25; cu 10 2-2`). Cells that contain a comma need double quotes, as in any CSV.
- **Errors name the file and line.** The tools write nothing until every table is clean.
- **Unchanged rows produce identical files.** Each tool keeps the resource ids of the file it replaces, so `git diff data/` shows only what your edit changed.

The folder holds a `.gdignore` file so that the editor doesn't import these CSV files as translations. They don't show in the FileSystem dock, and exported builds don't include them, which is fine because the game only loads the generated `.tres` files.

If you edit a table in a spreadsheet app, import every column as text. Otherwise descriptions such as `+3% run speed` are read as formulas, and numbers can lose their formatting.

## `upgrades/`: the pegboard (GDD 13)

M1 has one file per branch. Keep rows near related nodes rather than appending at the end, so that two branches adding nodes don't touch the same line.

| Column | Meaning | Example |
|---|---|---|
| `id` | `branch.name`. The file name is the id with `_` in place of `.` | `travel.comfy_boots` |
| `branch` | `travel`, `attack`, `repair`, `defend` or `farmhand` | `travel` |
| `board_col`, `board_row` | The node's peg on its branch's board. Two nodes can't share a peg. | `0`, `1` |
| `display_name` | Name shown on the pegboard | `Comfy Boots` |
| `max_level` | Number of levels; 1 means a one-off unlock | `5` |
| `prerequisites` | `<node id> [level]` items; the level defaults to 1 | `travel.comfy_boots 2; travel.jetpack` |
| `cost` | A recipe or explicit parts (see below). Blank means free. | `al_to_pc 15` |
| `effects` | `<stat> <kind> <value>` items (see below) | `player.run_speed add_pct 0.03` |
| `description` | Text shown on the pegboard | `+3% run speed per level.` |

**Cost.** Each part costs base × 1.25^(level − the part's first level), rounded (GDD 12.4). You can give a cost in two ways, and mix them in one cell (`al_cu 12; pc 1 5-5`):

- **A recipe and its base**, named after the GDD 13 "Recipe" column. The other parts' bases are fixed shares of it, and a part that would start above the node's last level is left out.

  | Recipe | GDD 13 | Parts |
  |---|---|---|
  | `al_to_pc <base>` | Al → PC | Al at every level; Cu (0.20 × base) from level 4; Au (0.067 ×) from level 7; one Power Cell at level 9 and two at level 10. Pistol Damage is `al_to_pc 15`. |
  | `al_to_au <base>` | Al → Au | The same, without Power Cells |
  | `al_cu <base>` | Al / Cu, Al → Cu | Al at every level; Cu (0.20 ×) from level 4 |
  | `al_cu_au <base>` | Mixed support | Al at every level; Cu (0.125 × base) at every level; Au (0.04 ×) in the upper half. Used for formerly Copper-only support tracks. |
  | `cu_au <base>` | Legacy Cu / Au | Cu at every level; Au (0.3 ×) in the upper half. Still accepted for custom tables. |

- **Explicit parts:** `<part> <base> [first-last]`, where the part is `al`, `cu`, `au` or `pc`. The levels default to all of the node's levels. For example, `al 60; cu 20` is a one-off price for an unlock, and `al 15; cu 6 3-5; au 2 5-5` is a hand-tuned track.

**Effects.** `StatService` folds every owned modifier of a stat into max((base + flat) × (1 + add_pct) × mul, max).

| Kind | What `<value>` does at each level |
|---|---|
| `flat` | Adds the value each level |
| `add_pct` | Adds the value as a fraction each level (`0.03` is +3%) |
| `mul` | Multiplies by the value each level, compounding |
| `max` | Raises the stat to at least the value once owned; armor tiers keep the best one |
| `flag` | Turns the flag on. The value defaults to 1. |

Instead of a single value, you can give one total per level in brackets, with exactly one number per level: `economy.early_bird add_pct [0.25 0.5 0.75]`, `zipline.any_weapon flag [0 1]`.

### The orphan-stat rule

Every stat key in `effects` must be read by some system. The test counts a key as read when it appears as a quoted string, like `&"player.run_speed"`, in `scripts/`, `scenes/` or `data/`. It skips comments, `StatService`, the upgrade scripts, the generated catalog and these tables. If a node's feature hasn't landed yet, add its stat to `PENDING_STATS` in `test_content_tables.gd` until it does. M2-G1 is done only when that list is empty.

## `robots/archetypes/` (GDD 9.3)

Each column is a `RobotArchetype` property with the same name; [scripts/ai/robot_archetype.gd](../../scripts/ai/robot_archetype.gd) explains each one.

- `robot_type` is `scout`, `grunt` or `heavy`.
- `robot_class` is `melee`, `ranged` or `flight`: the attack grid's columns.
- `distract_triggers` is a space-separated list of `hurt`, `near`, `repairing` and `airborne`.
- `on_unreachable` is `give_up`, `throw` or `relocate`.
- `scene` is a `res://` path.

- `ranged_attack_id` names a row of `robots/attacks/` for ranged and flying robots. Those take their charge, interval and damage from the profile, so `vertical.csv` and `spitter.csv` have no `attack_*` or `damage_*` columns. A melee robot with `on_unreachable` `throw` names the profile it throws at an out-of-reach farmer (`clanker_bolt`, `thumper_clod`; M2-B9).
- `front_guard` is the share of damage blocked from hits in front of the robot (the Clanker's arm guard, 0.5).
- `tells` is a space-separated list of extra parts that show the robot's role: `arm_guard`, `pea_shooter`, `bolt_pouch`, `clod_scoop`.

Every filled cell becomes a line in the `.tres` file, even when it equals the script default, and a blank cell leaves the line out. This matters because the script's defaults are the Nibbler's stats, so a blank cell silently follows any change to those defaults. Fill every behavior cell (`trio_chance_late` is `-1` for a flat trio chance). There is one file per group of archetypes (`melee.csv`, `vertical.csv`, `spitter.csv`), so new archetype work packages each add their own file.

## `robots/attacks/` (M2-B7)

Each column is an `AttackProfile` property with the same name; [scripts/ai/attack_profile.gd](../../scripts/ai/attack_profile.gd) explains each one. `kind` is `straight`, `lob`, `rail` or `bomb`, and picks the telegraph: lobs show a chalk circle, rails a red-yarn aim line, bombs a shadow circle, and every shot charges a glow. `charge_time` can't be under 0.45 s (the tool reports it), and an archetype naming a profile that isn't in the table is an error. `color` is `r g b`.

## `robots/palettes/`, `robots/themes/`, `robots/traits/` (GDD 10)

- **Palettes:** `id` (the file name), `adjective`, `primary`, `secondary` and `trim`. Colors are written `r g b` with values from 0 to 1 (`0.6 0.28 0.15`), or as `#rrggbb`.
- **Themes:** `id`, `theme_word`, and space-separated gene lists in `body_shapes`, `heads`, `eye_styles`, `antennas`, `patterns`, `melee_arms` and `accessories`. The `palettes` column lists palette ids.
- **Traits:** each column is a `RobotTrait` property with the same name. `thieving` is `true` or `false`.

The gene library (`data/robots/gene_library.tres`) lists every theme and every trait in table order: file-name order, then row order. That order affects seeded rolls. The library's other settings, such as farm color and the novelty rules, aren't in a table, so edit them in the inspector.
