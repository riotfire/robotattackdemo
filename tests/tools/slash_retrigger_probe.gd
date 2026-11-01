extends Node
## Isolated animation diagnostic; no rendered gameplay or player profile is changed.
## Instantiates the actual Farmer, Wrench and Mabel scene, disables automatic processing,
## holds the farmer GROUNDED, and manually calls the wrench's normal cooldown/swing path
## at 60 Hz and Mabel.step_pose at 24 Hz. No targets, floor or cooldown resets are used.
## This isolates whether repeated successful swings restart the rig's slash animation.
## Also times step_pose's CPU work; this excludes rendering/GPU cost and input latency.
## Run:
## godot --headless --path . res://tests/tools/slash_retrigger_probe.tscn -- \
##   --profile=/tmp/slash_probe_profile.json --out=/tmp/slash_retrigger_results.json

const FARMER_SCENE: PackedScene = preload("res://scenes/player/farmer.tscn")
const PHYSICS_HZ: float = 60.0
const POSE_HZ: float = 24.0
const BENCHMARK_ITERATIONS: int = 1000

var _out: String = "/tmp/slash_retrigger_results.json"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	StopMotionClock.set_process(false)
	# No upgrades are purchased or persisted. Redirect any incidental autosave as well.
	SaveManager.profile_path = _out.get_base_dir().path_join("slash_probe_profile.json")
	var trials: Array[Dictionary] = []
	for level in [0, 4, 5]:
		trials.append(_retrigger_trial(level))
	var benchmarks: Array[Dictionary] = []
	for scenario in ["idle", "run", "alternating_idle_run"]:
		benchmarks.append(_benchmark(scenario))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write animation probe output: %s" % _out)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({"retrigger_trials": trials, "cpu_benchmarks": benchmarks}, "  "))
	file.close()
	for trial in trials:
		print("SLASH level=%d interval=%.6f shots=%d terminal_rows=%d/%d first_terminal=%.3f" % [
			trial.level, trial.attack_interval, trial.shots.size(), trial.terminal_pose_count,
			trial.poses.size(), trial.first_terminal_at])
	for benchmark in benchmarks:
		print("POSE_CPU %s mean=%.2f us p95=%.2f us max=%.2f us" % [benchmark.scenario,
			benchmark.mean_us, benchmark.p95_us, benchmark.max_us])
	print("ANIMATION_PROBE_OUTPUT %s" % _out)
	get_tree().quit()


func _spawn_farmer(level: int) -> Farmer:
	StatService.set_levels({&"attack.wrench": 1, &"attack.wrench_speed": level})
	var farmer := FARMER_SCENE.instantiate() as Farmer
	get_tree().root.add_child(farmer)
	farmer.process_mode = Node.PROCESS_MODE_DISABLED
	farmer.state = Farmer.State.GROUNDED
	return farmer


func _retrigger_trial(level: int) -> Dictionary:
	var farmer := _spawn_farmer(level)
	var wrench := farmer.weapons.get_weapon(&"wrench") as Wrench
	var model := farmer.get_node("Model/Pose/Mabel") as MabelModel
	var rows: Array[Dictionary] = []
	var shots: Array[float] = []
	var accum := 0.0
	var terminal_count := 0
	var first_terminal := -1.0
	var slash_length := model._player.get_animation(&"Right_Hand_Sword_Slash").length
	# Give the initial attack a real preceding idle pose, including its normal cross-fade.
	model.step_pose(farmer)
	for frame in range(180):
		wrench._physics_process(1.0 / PHYSICS_HZ)
		if wrench.swing():
			shots.append(frame / PHYSICS_HZ)
		accum += 1.0 / PHYSICS_HZ
		while accum + 0.0000001 >= 1.0 / POSE_HZ:
			accum -= 1.0 / POSE_HZ
			model.step_pose(farmer)
			var elapsed := (frame + 1) / PHYSICS_HZ
			var terminal := model._current == &"Right_Hand_Sword_Slash" \
				and model._player.current_animation_position >= slash_length - 0.001
			if terminal:
				terminal_count += 1
				if first_terminal < 0.0:
					first_terminal = elapsed
			rows.append({"t": elapsed, "animation": String(model._current),
				"position": model._player.current_animation_position, "melee_left": model._melee_left})
	var result := {"level": level, "attack_interval": wrench.attack_interval(), "shots": shots,
		"poses": rows, "terminal_pose_count": terminal_count, "first_terminal_at": first_terminal}
	farmer.free()
	return result


func _benchmark(scenario: String) -> Dictionary:
	var farmer := _spawn_farmer(0)
	var model := farmer.get_node("Model/Pose/Mabel") as MabelModel
	var samples: Array[float] = []
	for i in range(BENCHMARK_ITERATIONS + 100):
		farmer.velocity = Vector3(0.0, 0.0, -7.0) if scenario == "run" \
			or (scenario == "alternating_idle_run" and i % 2 == 1) else Vector3.ZERO
		var start := Time.get_ticks_usec()
		model.step_pose(farmer)
		var elapsed := float(Time.get_ticks_usec() - start)
		if i >= 100:
			samples.append(elapsed)
	var total := 0.0
	for value in samples:
		total += value
	samples.sort()
	var result := {"scenario": scenario, "iterations": samples.size(), "mean_us": total / samples.size(),
		"median_us": samples[samples.size() / 2], "p95_us": samples[ceili(samples.size() * 0.95) - 1],
		"max_us": samples[-1], "excludes": "Rendering, GPU time, physics, and input latency"}
	farmer.free()
	return result
