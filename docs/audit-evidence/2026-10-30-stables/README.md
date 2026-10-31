# Stables defense workshop — October 30, 2026

Playtest follow-up: defense copies must be assembled and picked up at the stables before deployment. Implemented on top of the melee AI integration and M2-B11 battle-plan changes already present in the current branch.

## Behavior

The stables has a signed workbench, clear approach and pickup pads. Interact at the bench to learn existing recipes at their unchanged prices and queue physical copies. Copies assemble one at a time; finished stock remains inactive until physically picked up. Carrying gives the usual green/red free-placement preview; a valid placement deploys the finished copy immediately with no second payment or assembly. The pickup press must be released before a separate placement press is accepted. Tab and the siren return carried copies to their origin. Queued, ready, carried and deployed copies all count toward capacity; queue, assistance, cancellation, refunds, repair and relocation remain supported.

From wave 2 a gold trail, destination ring and persistent step-by-step lesson guide the first recipe/build/pickup/deployment. The lesson finishes only when a collected kit is successfully deployed, stored through the existing seen-intros save data. Existing recipe unlocks work without migration. The old BUILD board can still unlock recipes and improve defenses; physical copies always come from the stables. Build pressed elsewhere gives directions instead of creating a remote copy.

Workshop menus expose the mouse cursor and restore its prior mode on close. Stable row identities prevent an asynchronous build completion from changing the action under a held confirmation button. Procedural props leave the workshop and pickup approach clear. The farm generator preserves the station on regeneration.

## Validation

Godot 4.7.2 on macOS:

- Full GUT suite: 237/237 tests passed.
- Main smoke: 141/141 checks, seed 7.
- Authored opening, including the full stables workflow and a catwalk trap defeating a climber: 96/96 checks on seeds 7 and 42.
- Tutorial: 67/67 checks, seed 7.
- Rendered Metal/Forward+ preview at 1600 × 900: checked the signed workshop, recipe menu, persistent guide, ready stock and pickup destination. Images are `workshop.png`, `menu.png` and `pickup.png`.
- `git diff --check` passed.

The defense tests cover remote craft/pickup rejection, ready stock staying inactive, capacity accounting, one payment and one assembly, blocked placement, separate pickup/placement presses, returning carried stock on cancellation/siren, queue/refund rules, and the existing defense behaviors. Test scenes use temporary profiles. The rendered preview uses `/tmp/stables-preview-profile.json`; rerun `workshop_preview.tscn` to capture the three screenshots into `/tmp/stables-*.png`.

Existing sandbox certificate and ladder-test scene-tree diagnostics also occur in the earlier baseline; there are no new script errors in the passing logs. No Windows/Linux playtest or normal-speed human playtest was performed.
