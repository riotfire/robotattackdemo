extends Node3D
## Diagnostic only. Exercises the real player components at a fixed 60 physics ticks/s.
## Input is injected before a physics tick; these are simulation timings, not device/display latency.
## Run: Godot --headless --path . --fixed-fps 60 res://tests/tools/input_latency_probe.tscn \
##   -- --profile=/private/tmp/input-latency-profile.json --out=/private/tmp/input-latency.json

const STEP: float = 1.0 / 60.0
const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"aim", &"jump", &"fire", &"melee"]

var _farmer: Farmer
var _events: Array[Dictionary] = []
var _results: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := "/private/tmp/input-latency.json"
	var profile := "/private/tmp/input-latency-profile.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--profile="):
			profile = arg.trim_prefix("--profile=")
	if not profile.begins_with("/private/tmp/") and not profile.begins_with("/tmp/"):
		push_error("This diagnostic requires a disposable profile under /tmp or /private/tmp.")
		get_tree().quit(1)
		return
	SaveManager.use_profile(profile, true)
	# All changes are in this process's memory. The user's settings.cfg is never written.
	SaveManager.settings = SaveManager.settings.duplicate(true)
	SaveManager.settings["mabel_model"] = false
	SaveManager.settings["reduce_motion"] = true
	StopMotionClock.enabled = false
	GameState.jetpack_unlocked = false
	GameState.god_mode = true
	Engine.time_scale = 1.0
	if Engine.physics_ticks_per_second != 60:
		push_error("This diagnostic requires 60 physics ticks per second.")
		get_tree().quit(1)
		return
	_make_floor()
	_farmer = (load("res://scenes/player/farmer.tscn") as PackedScene).instantiate() as Farmer
	add_child(_farmer)
	_farmer.teleport_to(Vector3(0.0, 0.1, 0.0))
	_farmer.camera_rig.yaw = 0.0
	for weapon: Weapon in _farmer.weapons.weapons:
		weapon.fired.connect(_on_fired)
	await _ticks(30)
	_results = {
		"engine": Engine.get_version_info().string,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"nominal_tick_ms": STEP * 1000.0,
		"profile": profile,
		"scope": "Real player code on a generated floor; injected input, not hardware-to-display latency. Poses and hitstop disabled in memory.",
		"movement": await _movement(),
		"turn": await _turn(),
		"jump": await _jump(),
		"attacks": await _attacks(),
	}
	_release_all()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write latency probe output: " + output)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(_results, "  "))
	print("INPUT_LATENCY_PROBE ", JSON.stringify(_results))
	get_tree().quit()


func _make_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	collision.shape = box
	floor_body.add_child(collision)
	add_child(floor_body)
	floor_body.position.y = -0.5


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _release_all() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _reset_ground() -> void:
	_release_all()
	_farmer.teleport_to(Vector3(0.0, 0.01, 0.0))
	_farmer.state = Farmer.State.GROUNDED
	_farmer.movement._knockback = Vector3.ZERO
	await _ticks(4)


func _speed() -> float:
	return Vector2(_farmer.velocity.x, _farmer.velocity.z).length()


func _movement() -> Dictionary:
	await _reset_ground()
	Input.action_press(&"move_forward")
	var acceleration: Array[float] = []
	for i: int in 10:
		await _ticks(1)
		acceleration.append(_speed())
	var run_speed := _speed()
	Input.action_release(&"move_forward")
	var stop_from := _farmer.position
	var stopping: Array[float] = []
	for i: int in 10:
		await _ticks(1)
		stopping.append(_speed())
	var stop_distance := stop_from.distance_to(_farmer.position)
	Input.action_press(&"move_forward")
	await _ticks(10)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	var reversing: Array[float] = []
	for i: int in 16:
		await _ticks(1)
		reversing.append(_farmer.velocity.z)
	Input.action_press(&"aim")
	var aim_change: Array[float] = []
	for i: int in 10:
		await _ticks(1)
		aim_change.append(_speed())
	var aim_speed := _speed()
	_release_all()
	return {
		"ground_acceleration_mps2": _farmer.movement.ground_acceleration,
		"run_speed_mps": run_speed,
		"aim_speed_mps": aim_speed,
		"aim_speed_ratio": aim_speed / run_speed,
		"acceleration_speed_by_tick": acceleration,
		"full_speed_ticks": _first_near(acceleration, run_speed),
		"stopping_speed_by_tick": stopping,
		"stop_ticks": _first_near(stopping, 0.0),
		"stop_distance_m": stop_distance,
		"reversal_z_velocity_by_tick": reversing,
		"full_reversal_ticks": _first_near(reversing, run_speed),
		"aim_change_speed_by_tick": aim_change,
	}


func _turn() -> Dictionary:
	await _reset_ground()
	_farmer.model.rotation.y = PI * 0.5
	_farmer.facing_yaw = 0.0
	Input.action_press(&"move_forward")
	var angles: Array[float] = []
	for i: int in 20:
		await _ticks(1)
		angles.append(rad_to_deg(absf(_farmer.model.rotation.y)))
	_release_all()
	var ticks_to_90 := -1
	for i: int in angles.size():
		if angles[i] <= 9.0:
			ticks_to_90 = i + 1
			break
	return {"initial_degrees": 90.0, "error_degrees_by_tick": angles,
			"ticks_to_90_percent_turn": ticks_to_90, "ms_to_90_percent_turn": ticks_to_90 * STEP * 1000.0}


func _jump() -> Dictionary:
	await _reset_ground()
	var grounded_before := _farmer.is_on_floor()
	var before := _farmer.position.y
	Input.action_press(&"jump")
	await _ticks(1)
	var result := {"grounded_before": grounded_before, "vertical_velocity_after_first_tick": _farmer.velocity.y,
			"height_change_after_first_tick": _farmer.position.y - before, "state_after_first_tick": Farmer.State.keys()[_farmer.state]}
	Input.action_release(&"jump")
	await _ticks(70)
	return result


func _attacks() -> Dictionary:
	await _reset_ground()
	StatService.set_levels({&"attack.wrench": 1, &"attack.pistol": 1})
	var holder := _farmer.weapons
	var wrench := holder.get_weapon(&"wrench") as Wrench
	var pistol := holder.get_weapon(&"pistol") as Pistol
	holder.equip(wrench)
	wrench._cooldown = 0.0
	_events.clear()
	var input_frame := Engine.get_physics_frames() + 1
	Input.action_press(&"fire")
	await _ticks(120)
	Input.action_release(&"fire")
	var held_events := _events.duplicate(true)
	await _ticks(50)
	_events.clear()
	wrench._cooldown = 0.0
	Input.action_press(&"melee")
	await _ticks(1)
	Input.action_release(&"melee")
	await _ticks(31)
	var melee_remaining := wrench._cooldown
	Input.action_press(&"melee")
	await _ticks(1)
	Input.action_release(&"melee")
	await _ticks(50)
	var early_melee_events := _events.duplicate(true)
	Input.action_press(&"melee")
	await _ticks(1)
	Input.action_release(&"melee")
	var ready_melee_events := _events.duplicate(true)
	holder.equip(pistol)
	pistol._cooldown = 0.0
	pistol._reload_left = 0.0
	pistol.ammo = pistol.magazine_now()
	_events.clear()
	var pistol_input_frame := Engine.get_physics_frames() + 1
	Input.action_press(&"fire")
	await _ticks(1)
	Input.action_release(&"fire")
	await _ticks(8)
	var pistol_remaining := pistol._cooldown
	Input.action_press(&"fire")
	await _ticks(1)
	Input.action_release(&"fire")
	await _ticks(30)
	var early_pistol_events := _events.duplicate(true)
	return {"wrench_attack_interval_ms": wrench.attack_interval() * 1000.0,
			"pistol_attack_interval_ms": pistol.attack_interval() * 1000.0,
			"first_wrench_action_expected_physics_frame": input_frame,
			"held_wrench_fired_events": held_events,
			"held_wrench_intervals_ms": _event_intervals(held_events),
			"early_quick_melee_remaining_cooldown_ms": melee_remaining * 1000.0,
			"early_quick_melee_total_fired_events": early_melee_events,
			"quick_melee_after_ready_total_fired_events": ready_melee_events,
			"first_pistol_action_expected_physics_frame": pistol_input_frame,
			"early_pistol_remaining_cooldown_ms": pistol_remaining * 1000.0,
			"early_pistol_total_fired_events": early_pistol_events,
			"early_pistol_intervals_ms": _event_intervals(early_pistol_events)}


func _on_fired(shot: WeaponShot) -> void:
	_events.append({"weapon": shot.weapon.data.id, "physics_frame": Engine.get_physics_frames()})


func _event_intervals(events: Array[Dictionary]) -> Array[float]:
	var result: Array[float] = []
	for i: int in range(1, events.size()):
		result.append((int(events[i].physics_frame) - int(events[i - 1].physics_frame)) * STEP * 1000.0)
	return result


func _first_near(values: Array[float], target: float) -> int:
	for i: int in values.size():
		if absf(values[i] - target) < 0.001:
			return i + 1
	return -1
