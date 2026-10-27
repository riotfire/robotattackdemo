extends Node
## Profile save and load (GDD 14.1, 18.4): JSON at user://profile.json with a schema version and
## migrations. Everything persists: parts, pegboard levels, unlocks, records and the Robot Almanac.
## Autosaves at every intermission start, after every purchase and on game over.
## Schema v2 (PHASE_CHECKPOINT_PROGRESSION_PLAN.md) adds the phase checkpoint: resume_wave is the first wave
## of the phase the farmer is in, so a loss (or quitting) starts again there with parts and upgrades kept.
## Settings live separately in user://settings.cfg.
## Pass `-- --profile=user://other.json` to use another profile (tests use their own).

const SCHEMA_VERSION := 2
const DEFAULT_PROFILE_PATH := "user://profile.json"
const SETTINGS_PATH := "user://settings.cfg"

var profile_path: String = DEFAULT_PROFILE_PATH
var records: Dictionary = {"best_wave": 0, "best_full_harvest_wave": 0, "robots_popped": {}, "foreman_bounties": [],
		"phase_attempts": {}}
## [{code, name, wave, kills}], newest last.
var almanac: Array[Dictionary] = []
## Level 0 "Morning Chores" has been finished (or skipped) once; later runs open on the normal intermission.
var tutorial_completed: bool = false
## The phase checkpoint: the first wave of the phase the farmer is in. A new run (relaunch, Retry Phase)
## starts at its intermission; "Start over at Phase 1" starts at 1 instead.
var resume_wave: int = 1
## Debut captions already shown on this profile (a robot's first appearance, the first Foreman).
var seen_intros: Array[String] = []
## First-completion milestones already announced (MilestoneRewards ids, e.g. "w9_jetpack").
var granted_rewards: Array[String] = []
## Set just before reloading the scene for a retry or a fresh start; main.gd reads and clears it. Never saved.
var pending_start: Dictionary = {}
var settings: Dictionary = {"mouse_sensitivity": 0.0022, "invert_y": false, "reduce_motion": false, "show_fps": false,
		"rigged_farmer": false}


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
		"resume_wave": resume_wave,
		"seen_intros": seen_intros.duplicate(),
		"granted_rewards": granted_rewards.duplicate(),
		"cosmetics": {"hat": "straw", "unlocked": ["straw"]},
	}


func apply(data: Dictionary) -> void:
	var parts: Dictionary = data.get("parts", {})
	for key in GameState.PART_KEYS:
		GameState.parts[key] = int(parts.get(String(key), 0))
	EventBus.parts_changed.emit(GameState.parts)
	var upgrades: Dictionary = (data.get("upgrades", {}) as Dictionary).duplicate()
	var refunded := RetiredUpgrades.refund(upgrades)
	StatService.set_levels(upgrades)
	if not refunded.is_empty():
		GameState.add_parts(refunded)
	var unlocks: Dictionary = data.get("unlocks", {})
	if bool(unlocks.get("jetpack", false)):
		GameState.jetpack_unlocked = true
	# Profiles from before Level 0 existed belong to someone who has already played.
	var has_played := int((data.get("records", {}) as Dictionary).get("best_wave", 0)) > 0
	tutorial_completed = bool(data.get("tutorial_completed", has_played))
	# Existing profiles already started with a wrench before the first-tool peg was introduced.
	if tutorial_completed and not StatService.has_flag(&"wrench.owned"):
		StatService.grant(&"attack.wrench")
	records = (data.get("records", {}) as Dictionary).duplicate(true)
	for key: String in ["best_wave", "best_full_harvest_wave"]:
		records[key] = int(records.get(key, 0))
	records["furthest_checkpoint"] = maxi(1, int(records.get("furthest_checkpoint",
			floori(float(records["best_wave"]) / 3.0) * 3 + 1)))
	if not records.has("robots_popped"):
		records["robots_popped"] = {}
	var bounties: Array[int] = []
	for wave: Variant in records.get("foreman_bounties", []):
		bounties.append(int(wave))
	records["foreman_bounties"] = bounties
	var attempts := {}
	var saved_attempts: Variant = records.get("phase_attempts", {})
	if saved_attempts is Dictionary:
		for phase: Variant in saved_attempts:
			var entry: Variant = saved_attempts[phase]
			if entry is Dictionary:
				attempts[str(phase)] = {"latest": int(entry.get("latest", 0)), "best": int(entry.get("best", 0))}
	records["phase_attempts"] = attempts
	almanac.clear()
	for entry: Variant in data.get("almanac", []):
		if entry is Dictionary:
			almanac.append(entry)
	resume_wave = maxi(1, int(data.get("resume_wave", 1)))
	seen_intros = _strings(data.get("seen_intros", []))
	granted_rewards = _strings(data.get("granted_rewards", []))
	# A profile that already cleared a milestone's wave settles it now, quietly.
	MilestoneRewards.reconcile(int(records["best_wave"]))


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
	if version < 2:
		# v1 had 5-wave phases and no checkpoint. Continue at the start of the 3-wave phase that holds the
		# next wave to beat; milestones for waves already cleared are settled by MilestoneRewards on load.
		var best := int((result.get("records", {}) as Dictionary).get("best_wave", 0))
		var per_phase := 3
		result["resume_wave"] = floori(float(best) / per_phase) * per_phase + 1
		version = 2
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


func _on_wave_phase_changed(phase: int, wave: int) -> void:
	if phase == WaveDirector.Phase.INTERMISSION:
		_record_run()
		# The intermission before a phase's first wave moves the checkpoint (a cleared Big Haul).
		resume_wave = GameState.phase_first_wave(maxi(1, wave))
		records["furthest_checkpoint"] = maxi(int(records.get("furthest_checkpoint", 1)), resume_wave)
		save_profile()


## True the first time `id` is asked about on this profile; records it.
func first_time(id: String) -> bool:
	if id in seen_intros:
		return false
	seen_intros.append(id)
	return true


## The Foreman of `wave` pays its guaranteed bounty only the first time it falls on this profile
## (PHASE_CHECKPOINT_PROGRESSION_PLAN.md: cheap retries mustn't farm it).
func foreman_bounty_paid(wave: int) -> bool:
	return wave in (records.get("foreman_bounties", []) as Array)


func record_foreman_bounty(wave: int) -> void:
	var paid: Array = records.get("foreman_bounties", [])
	if wave not in paid:
		paid.append(wave)
	records["foreman_bounties"] = paid


## Attempts at `phase`: the latest streak and the fewest it ever took to clear it (0 = never cleared).
func phase_attempts(phase: int) -> Dictionary:
	var all: Dictionary = records.get("phase_attempts", {})
	return all.get(str(phase), {"latest": 0, "best": 0})


func record_phase_attempt(phase: int, attempt: int, cleared: bool) -> void:
	var all: Dictionary = records.get("phase_attempts", {})
	var entry: Dictionary = all.get(str(phase), {"latest": 0, "best": 0})
	entry["latest"] = attempt
	if cleared and (int(entry.get("best", 0)) <= 0 or attempt < int(entry.get("best", 0))):
		entry["best"] = attempt
	all[str(phase)] = entry
	records["phase_attempts"] = all


## Where and how the next run starts, then forgets it: {"wave": int, "retry": bool, "attempt": int}.
func consume_pending_start() -> Dictionary:
	var start := pending_start
	pending_start = {}
	return start


static func _strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			result.append(str(value))
	return result


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
	# A Full Harvest is from wave 1 with no retries (a phase 1 retry starts at wave 1 too).
	if GameState.start_wave <= 1 and not GameState.retried:
		records["best_full_harvest_wave"] = maxi(int(records.get("best_full_harvest_wave", 0)), GameState.waves_survived)


func _default_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"parts": {"al": 0, "cu": 0, "au": 0, "pc": 0},
		"upgrades": {},
		"unlocks": {"jetpack": false},
		"records": {"best_wave": 0, "best_full_harvest_wave": 0, "robots_popped": {}, "foreman_bounties": [],
				"phase_attempts": {}},
		"almanac": [],
		"tutorial_completed": false,
		"resume_wave": 1,
		"seen_intros": [],
		"granted_rewards": [],
	}
