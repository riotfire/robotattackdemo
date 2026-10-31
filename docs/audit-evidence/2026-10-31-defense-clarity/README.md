# Defense clarity and spotter calls — October 31, 2026

Changes requested after playtesting:

- The toolshed has no BUILD tab or crafted-defense pegs. Its buy method also refuses BUILD-branch purchases. All five crafted-defense upgrades are available under Improve defenses at the stables.
- The stables offers direct building of all three defenses (12 / 6 / 8 Al per copy). There is no Learn menu, learning fee or prerequisite to build a copy. Legacy saved unlock levels/flags remain internal compatibility data; a successful build records its type for the existing upgrade prerequisite chain.
- Empty pickup pads, ground text and destination rings are removed. Unfinished stock is hidden and has no interaction prompt. Completed stock appears solid with its name, READY and pickup controls. Workbench assistance replaces assistance beside the hidden stock. The initial tutorial trail only leads to the workbench and disappears while jobs or ready stock exist.
- Siren, raid and enemy-debut warnings are brief spoken-style sightings using actual active-lane landmarks. Wave numbers, directions, boss names and battle-plan details are not piled into the warning banner. Examples: “They're coming in by the barn!” and “Spotted by the house and tool shed!”

Validation on Godot 4.7.2/macOS:

- Full GUT suite: 241/241 tests passed.
- Focused defense suite after the unfinished-stock interaction guard: 19/19 passed.
- Main smoke: 141/141 checks, seed 42.
- Full authored opening/stables/catwalk-defense flow: 96/96 checks, seed 7.
- Rendered Metal/Forward+ views at 1600 × 900 verified direct Build choices, the upgrade submenu, removal of the shed BUILD tab, no ground pads or early pickup models, a named ready item and a short landmark callout. See the six PNGs in this folder.
- Whitespace checks passed.

New coverage checks fresh-profile building without an unlock fee, hidden/non-interactable unfinished stock, named ready stock, refusal of shed defense purchases, local-only workshop upgrades and spotter text for one, two, repeated, empty and multiple lanes. Existing save, capacity, queue, relocation, refund and combat tests remain passing. The pre-existing sandbox certificate and ladder-test scene-tree diagnostics are unchanged.

`preview.tscn` renders the six views using `/tmp/defense-cleanup-preview-profile.json` and saves images to `/tmp/defense-cleanup-*.png`. No normal-speed human playtest or Windows/Linux execution was performed.
