extends Node
## Global signal hub (GDD 18.2). Systems emit here; UI and other systems listen.
## Signals carry plain data so they can later be mirrored over the network (GDD 18.8).

@warning_ignore_start("unused_signal")

signal run_started(run_seed: int)
signal player_registered(player: Node3D)
signal player_unregistered(player: Node3D)

signal robot_spawned(robot: Node3D)
signal robot_destroyed(robot: Node3D, killer: Node)
## A robot started charging a shot at a farmer (M2-B7): it lands in about `impact_time` seconds.
## `off_screen` when the shooter is outside the camera's view, for the HUD's incoming-shot pip (M2-H5).
signal robot_shot_incoming(robot: Node3D, farmer: Node3D, impact_time: float, off_screen: bool)

signal silo_damaged(amount: float, at_position: Vector3)
signal crack_opened(crack: Node3D)
signal crack_resized(crack: Node3D)
signal crack_closed(crack: Node3D)

signal wave_phase_changed(phase: int, wave: int)
signal siren_started(wave: int, lanes: PackedInt32Array)
signal wave_started(wave: int)
signal wave_cleared(wave: int)
## The farm's lighting preset changed (GDD 4.6, 11.2): the run's starting time of day, then one step each phase.
signal time_of_day_changed(preset_id: StringName, preset_index: int)
## The run's weather was rolled (GDD 4.6).
signal weather_changed(weather_id: StringName)

signal parts_changed(parts: Dictionary)
signal upgrade_purchased(id: StringName, level: int)
## A wave's robot family was rolled; the siren shows its name card (GDD 10.2).
signal family_revealed(genome: Resource)
signal grain_stolen(amount: float, thief: Node3D)
signal grain_returned(amount: float)
signal jetpack_unlocked
signal game_over(reason: StringName)
## Level 0 "Morning Chores" moved to a new step (TutorialDirector.Step), and ended when the bell started wave 1.
signal tutorial_step_changed(step: int)
signal tutorial_finished

## Short center-screen toast for the HUD.
signal hud_message(text: String, duration: float)

@warning_ignore_restore("unused_signal")
