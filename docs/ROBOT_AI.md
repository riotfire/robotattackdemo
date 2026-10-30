# Robot AI (M2-A3)

The current melee robots use LimboAI 1.8.1 on Godot 4.7.2. Nibblers, Clankers and Thumpers have a manually ticked `BTPlayer` in their scenes. The Rung Runner inherits the Nibbler scene and keeps its ladder and catwalk movement hooks. The existing Spitter, Roof Lobber and Drone controllers continue to own their ranged movement and attacks; migrating those controllers is separate work.

## Physics order and behavior tree

`Robot._physics_process` handles death and spring-launch/stun recovery first, then ticks the existing `RobotTargeting` and defense targeting once. Sidearm throws can take over the frame. Otherwise `_ai_step` manually updates `data/robots/behaviors/melee.tres`, then hands the requested flat velocity to navigation avoidance. `HeavyRobot._ai_step` still runs the authored Foreman's vent and clod-throw hooks around that call.

The tree publishes perch information, then selects the first applicable task: flee, grab a sack, recover, wind up and strike, begin a new attack/theft, or approach. Tasks are in `scripts/ai/tasks/`. They use the body's explicit state and timers so a spring interruption cannot leave a task holding an obsolete attack timer. `AiState` also continues to drive the stop-motion poses and existing debug tools. Windup/recovery duration and damage go through the existing robot hooks, preserving the opening bosses, shockwaves, defense attacks and Rung Runner catwalk hits.

## Blackboards and targeting

Each robot's blackboard binds `target_kind`, `target_player`, `squad_index` and `ai_state` to its body, and publishes `target_perched` and `perch_stand`. A squad has a parent blackboard containing `squad_leader` and `squad_beats`; leader death updates that scope immediately. Followers use the shared leader for formation, and the first melee attacks retain their three-beat stagger.

`RobotTargeting` remains the single owner of spawn rolls, distractions, shared trio targeting, heist escorts, chase/leash limits and unreachable timers. The tree does not roll another target or tick those clocks a second time. Out-of-reach sidearm throws retain their attack-token limits and give-up holds.

For a perched farmer, `PerchQuery` projects a ground approach outside the wall, at the normal navigation repath interval. A point directly below the farmer inside a wide building can otherwise choose an unreachable roof island. Once the existing give-up timer expires, the robot resumes its silo target. Ranged robots retain their ability to shoot elevated farmers.

## Verification

Run the full GUT suite and the smoke scenes using the commands in README. `tests/unit/test_robot_ai.gd` checks tree assignment, property bindings, squad leadership and rhythm, formation breakup, narrow/wide perches, authored Foreman timing and spring interruption. The main smoke test also exercises tree spawning, squad scopes and unreachable-target return on the real farm.

Desktop LimboAI binaries for macOS, Windows x86_64 and Linux x86_64 are vendored in `addons/limboai/`; other export targets require their matching extension builds. Licensing and logo attribution are listed in CREDITS.
