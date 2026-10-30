# M2-A3: melee behavior-tree integration — October 30, 2026

Environment: macOS, Godot 4.7.2 (`ed1daf0bf`), LimboAI 1.8.1, GUT 9.7.1. The original unfinished prototype was preserved as commit `e1decca` on `claude/mystifying-payne-3179cf` before porting onto current main (`21751c0`).

Validation:

- Before migration: full unit suite 216/216 passed.
- After migration: full unit suite 224/224 passed, including 8 new AI tests. The focused AI suite was also rerun after adding debugger property bindings.
- Main smoke: 141/141 checks on seeds 7, 42 and 1234, headless at fixed 60 fps.
- Authored opening smoke: 92/92 checks on seed 7.
- Tutorial smoke: 67/67 checks on seed 7.
- Updated two stale smoke expectations to the existing current-game tuning: 15 wave-one Nibblers in 10 groups and the first Foreman's 350 HP. No opening data or balance values changed.

AI tests cover scene/tree wiring and property bindings; squad blackboard leadership and leader death; staggered first hits; formation breakup; narrow and wide building perches; authored Foreman telegraph/recovery windows; and spring interruption followed by a fresh windup. The main smoke exercises director-spawned trees, shared squad scopes and unreachable-target return on the real farm. Existing unit coverage also exercises sidearm throws/tokens, defenses, ladders, ranged attacks, weapons and saves.

Raw logs are retained alongside this file. macOS system certificate access emits a startup diagnostic in this sandbox; the unit suite also retains pre-existing scene-tree diagnostics from `test_ladder_climber.gd` seen in the pre-migration baseline. No AI script errors remain in the passing runs. All tests ran in the filesystem sandbox; attempts by existing autoload code to write the default profile are blocked, while test-owned profiles use temporary files.

Not performed: a normal-speed human playtest, a rendered performance capture, or Windows/Linux execution/export. The vendored extension includes macOS and x86_64 Windows/Linux desktop binaries; other export targets need matching LimboAI builds. Ranged/flight controller migration is outside this melee work package.
