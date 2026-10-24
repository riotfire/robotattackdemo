class_name TimeOfDay
extends Node
## Time of day and weather for a run (GDD 4.6, 11.2, 15.5). At run start it rolls the starting lighting preset,
## the weather and small per-run variations (key-light bearing, cloud layout, wind direction, puddles) from
## the "environment" RngService stream, so any peer rebuilds the same sky from the run seed (GDD 18.8). Each
## completed phase advances the preset one step (Dawn -> Morning -> Noon -> Golden Hour -> Dusk -> Moonlit
## Night -> Dawn). It follows EventBus.wave_phase_changed and never touches the WaveDirector.
## A phase change plays as a short blend stepped at 12 fps, like a lighting cue on a stop-motion set.
## Presets and weathers are data (data/environment); this node only picks and shows them.
## Debug builds: F9 steps the time of day, F10 the weather. `-- --time=<id> --weather=<id>` force both.

## Only TimeOfDay rolls from this stream, once per run, so it never shifts spawn, genome or lane rolls.
const STREAM: StringName = &"environment"

@export var table: EnvironmentTable
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var weather: Weather
## Seconds a phase change takes to blend into the next preset.
@export var transition_time: float = 6.0
## The blend updates this many times a second (stop-motion stepping, GDD 15.4).
@export var transition_fps: float = 12.0

var run_roll: EnvironmentTable.Roll
var preset_index: int = -1
var weather_index: int = -1
## What's on screen now (mid-blend during a transition).
var look: AtmosphereLook

var _from: AtmosphereLook
var _to: AtmosphereLook
var _blend_time: float = 0.0
var _step_time: float = 0.0


func _ready() -> void:
	add_to_group(&"time_of_day")
	set_process(false)
	if not OS.is_debug_build():
		set_process_unhandled_key_input(false)
	EventBus.run_started.connect(_on_run_started)
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)


func current_preset() -> LightingPreset:
	return table.presets[preset_index] if preset_index >= 0 else null


func current_weather() -> WeatherType:
	return table.weathers[weather_index] if weather_index >= 0 else null


func is_transitioning() -> bool:
	return is_processing()


## Rolls this run's sky from the seeded stream. Static, so tests and replays can rebuild it without a scene.
static func roll_for_run(environment_table: EnvironmentTable) -> EnvironmentTable.Roll:
	return environment_table.roll(RngService.stream(STREAM))


func _on_run_started(_run_seed: int) -> void:
	run_roll = roll_for_run(table)
	var forced_time := -1
	var forced_weather := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			forced_time = table.preset_by_id(StringName(arg.trim_prefix("--time=")))
		elif arg.begins_with("--weather="):
			forced_weather = table.weather_by_id(StringName(arg.trim_prefix("--weather=")))
	if forced_time >= 0:
		run_roll.start_index = forced_time
	if forced_weather >= 0:
		run_roll.weather_index = forced_weather
	set_weather_index(run_roll.weather_index)
	show_preset(run_roll.start_index, false)


func _on_wave_phase_changed(_phase: int, wave: int) -> void:
	if run_roll == null:
		return
	var index := table.preset_index(run_roll.start_index, wave, GameState.start_wave)
	if index != preset_index:
		show_preset(index, true)


## Shows preset `index` with the current weather, blending over transition_time when `animate`.
func show_preset(index: int, animate: bool) -> void:
	preset_index = index
	var target := AtmosphereLook.compose(table.presets[index], current_weather(), run_roll)
	if animate and look != null and transition_time > 0.0:
		_from = look
		_to = target
		_blend_time = 0.0
		_step_time = 0.0
		set_process(true)
	else:
		set_process(false)
		_show(target)
	EventBus.time_of_day_changed.emit(table.presets[index].id, index)


## Switches the weather (run start, or the F10 debug key) and re-composes the current preset.
func set_weather_index(index: int) -> void:
	weather_index = index
	var roll := run_roll if run_roll != null else EnvironmentTable.Roll.new()
	weather.set_weather(table.weathers[index], roll.wind_bearing, roll.puddle_seed)
	EventBus.weather_changed.emit(table.weathers[index].id)
	if preset_index >= 0:
		show_preset(preset_index, false)


func _process(delta: float) -> void:
	_blend_time += delta
	_step_time += delta
	var done := _blend_time >= transition_time
	if _step_time < 1.0 / transition_fps and not done:
		return
	_step_time = fmod(_step_time, 1.0 / transition_fps)
	var t := smoothstep(0.0, 1.0, clampf(_blend_time / transition_time, 0.0, 1.0))
	var step := _from.blend(_to, t)
	# The key light swings across the sky; hide its disc mid-swing, like swapping the sun card for the moon.
	step.sun_disc_energy *= absf(1.0 - 2.0 * t)
	_show(step)
	if done:
		set_process(false)


func _show(new_look: AtmosphereLook) -> void:
	look = new_look
	look.apply(world_environment.environment if world_environment != null else null, sun)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or run_roll == null:
		return
	if key.physical_keycode == KEY_F9:
		show_preset((preset_index + 1) % table.presets.size(), true)
		EventBus.hud_message.emit("Time of day: %s" % current_preset().display_name, 2.0)
	elif key.physical_keycode == KEY_F10:
		set_weather_index((weather_index + 1) % table.weathers.size())
		EventBus.hud_message.emit("Weather: %s" % current_weather().display_name, 2.0)
