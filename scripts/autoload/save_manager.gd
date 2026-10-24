extends Node
## Profile save and load (GDD 14.1, 18.4): JSON at user://profile.json with a schema version and
## migrations. Everything persists: parts, pegboard levels, unlocks, records and the Robot Almanac.
## Autosaves at every intermission start, after every purchase and on game over.
## Settings live separately in user://settings.cfg.
## Pass `-- --profile=user://other.json` to use another profile (tests use their own).

const SCHEMA_VERSION := 1
const DEFAULT_PROFILE_PATH := "user://profile.json"
const SETTINGS_PATH := "user://settings.cfg"

var profile_path: String = DEFAULT_PROFILE_PATH
var records: Dictionary = {"best_wave": 0, "best_full_harvest_wave": 0, "robots_popped": {}}
## [{code, name, wave, kills}], newest last.
var almanac: Array[Dictionary] = []
## Level 0 "Morning Chores" has been finished (or skipped) once; later runs open on the normal intermission.
var tutorial_completed: bool = false
var settings: Dictionary = {"mouse_sensitivity": 0.0022, "invert_y": false, "reduce_motion": false, "show_fps": false}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			profile_path = arg.trim_prefix("--profile=")
	load_profile()
	load_settings()
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	EventBus.robot_destroyed.connect(_on_robot_destroyed)
	EventBus.game_over.connect(_on_game_over)


## Switches to another profile file. `fresh` wipes it instead of loading it.
func use_profile(path: String, fresh: bool = false) -> void:
	profile_path = path
	if fresh:
		reset_profile()
	else:
		load_profile()


func reset_profile() -> void:
	apply(_default_profile())
	save_profile()


func load_profile() -> void:
	var data := _default_profile()
	if FileAccess.file_exists(profile_path):
		var text := FileAccess.get_file_as_string(profile_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			data = migrate(parsed as Dictionary)
		else:
			push_warning("Profile at %s is unreadable; starting fresh." % profile_path)
	apply(data)


func save_profile() -> bool:
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save profile to %s: %s" % [profile_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dictionary(), "  "))
	return true


func to_dictionary() -> Dictionary:
	var parts := {}
	for key in GameState.PART_KEYS:
		parts[String(key)] = GameState.parts[key]
	var upgrades := {}
	for id in StatService.levels:
		upgrades[String(id)] = StatService.levels[id]
	return {
		"schema_version": SCHEMA_VERSION,
		"parts": parts,
		"upgrades": upgrades,
		"unlocks": {"jetpack": GameState.jetpack_unlocked},
		"records": records.duplicate(true),
		"almanac": almanac.duplicate(true),
		"tutorial_completed": tutorial_completed,
		"cosmetics": {"hat": "straw", "unlocked": ["straw"]},
	}


func apply(data: Dictionary) -> void:
	var parts: Dictionary = data.get("parts", {})
	for key in GameState.PART_KEYS:
		GameState.parts[key] = int(parts.get(String(key), 0))
	EventBus.parts_changed.emit(GameState.parts)
	StatService.set_levels(data.get("upgrades", {}))
	var unlocks: Dictionary = data.get("unlocks", {})
	if bool(unlocks.get("jetpack", false)):
		GameState.jetpack_unlocked = true
	# Profiles from before Level 0 existed belong to someone who has already played.
	var has_played := int((data.get("records", {}) as Dictionary).get("best_wave", 0)) > 0
	tutorial_completed = bool(data.get("tutorial_completed", has_played))
	records = (data.get("records", {}) as Dictionary).duplicate(true)
	for key: String in ["best_wave", "best_full_harvest_wave"]:
		records[key] = int(records.get(key, 0))
	if not records.has("robots_popped"):
		records["robots_popped"] = {}
	almanac.clear()
	for entry: Variant in data.get("almanac", []):
		if entry is Dictionary:
			almanac.append(entry)


## Upgrades an older profile dictionary to SCHEMA_VERSION, one step at a time.
static func migrate(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	var version := int(result.get("schema_version", 0))
	if version < 1:
		# v0 (pre-release) kept parts at the top level and had no unlocks block.
		if not result.has("parts"):
			var parts := {}
			for key: String in ["al", "cu", "au", "pc"]:
				parts[key] = int(result.get(key, 0))
			result["parts"] = parts
		if not result.has("unlocks"):
			result["unlocks"] = {"jetpack": bool(result.get("jetpack", false))}
		version = 1
	result["schema_version"] = version
	return result


## Logs a family the first time it shows up (GDD 14.3).
func log_family(code: String, family_name: String, wave: int) -> void:
	for entry in almanac:
		if entry.get("code") == code:
			return
	almanac.append({"code": code, "name": family_name, "wave": wave, "kills": 0})


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key: String in settings.keys():
		settings[key] = config.get_value("settings", key, settings[key])


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in settings.keys():
		config.set_value("settings", key, settings[key])
	config.save(SETTINGS_PATH)


func _on_upgrade_purchased(_id: StringName, _level: int) -> void:
	save_profile()


func _on_game_over(_reason: StringName) -> void:
	_record_run()
	save_profile()


func _on_wave_phase_changed(phase: int, _wave: int) -> void:
	if phase == WaveDirector.Phase.INTERMISSION:
		_record_run()
		save_profile()


func _on_robot_destroyed(robot: Node3D, killer: Node) -> void:
	if killer == null or not (robot is Robot) or (robot as Robot).archetype == null:
		return
	var popped: Dictionary = records["robots_popped"]
	var id := String((robot as Robot).archetype.id)
	popped[id] = int(popped.get(id, 0)) + 1
	var code := (robot as Robot).family_code
	for entry in almanac:
		if entry.get("code") == code:
			entry["kills"] = int(entry.get("kills", 0)) + 1
			break


func _record_run() -> void:
	records["best_wave"] = maxi(int(records.get("best_wave", 0)), GameState.waves_survived)
	if GameState.start_wave <= 1:
		records["best_full_harvest_wave"] = maxi(int(records.get("best_full_harvest_wave", 0)), GameState.waves_survived)


func _default_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"parts": {"al": 0, "cu": 0, "au": 0, "pc": 0},
		"upgrades": {},
		"unlocks": {"jetpack": false},
		"records": {"best_wave": 0, "best_full_harvest_wave": 0, "robots_popped": {}},
		"almanac": [],
		"tutorial_completed": false,
	}
