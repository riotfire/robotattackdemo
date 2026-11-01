extends Node
## Diagnostic only. Real-time rendered A/B measurements; never use --fixed-fps.
## Uses a disposable profile and changes settings only in this process.
## godot --path . --resolution 1600x900 res://tests/tools/responsiveness_probe.tscn -- --profile=/tmp/responsiveness-profile.json --out=/tmp/responsiveness

var _main: Node3D
var _director: WaveDirector
var _farmer: Farmer
var _out: String = "/tmp/responsiveness"
var _results: Array[Dictionary] = []
var _raw: PackedStringArray = ["scenario,frame,wall_ms,engine_1s_peak_process_ms,engine_1s_peak_physics_ms,render_cpu_ms,render_gpu_ms,draw_calls,primitives,time_scale,new_pipelines"]
var _viewport_rid: RID
var _burst_cpu: Array[Dictionary] = []
var _sweep_camera: bool = false


func _ready() -> void:
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if GameState.silo != null:
		GameState.silo.structure = GameState.silo.max_structure
		GameState.silo.grain = GameState.silo.max_grain


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ResponsivenessProbe requires a real renderer")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	SaveManager.use_profile(OS.get_temp_dir().path_join("responsiveness_%d.json" % OS.get_process_id()), true)
	SaveManager.tutorial_completed = true
	SaveManager.settings["mabel_model"] = true
	SaveManager.settings["reduce_motion"] = false
	StopMotionClock.enabled = true
	var boot := BootScreen.new()
	add_child(boot)
	var deadline := Time.get_ticks_msec() + 120000
	while not boot._loaded:
		if Time.get_ticks_msec() > deadline:
			push_error("Warm-up timed out")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	boot.queue_free()
	await get_tree().process_frame
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	_main.run_seed = 42
	add_child(_main)
	_director = _main.get_node("WaveDirector")
	_director.set_physics_process(false)
	_farmer = GameState.players[0] as Farmer
	_farmer.input.enabled = false
	_farmer.teleport_to(Vector3(0.0, 0.2, 22.0))
	_farmer.camera_rig.pitch = deg_to_rad(-15.0)
	GameState.god_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	await get_tree().create_timer(3.0).timeout
	var meta := {
		"engine": Engine.get_version_info().string,
		"adapter": RenderingServer.get_video_adapter_name(),
		"viewport": str(get_viewport().get_visible_rect().size),
		"window_pixels": str(DisplayServer.window_get_size()),
		"render_scale": get_viewport().scaling_3d_scale,
		"vsync": DisplayServer.window_get_vsync_mode(),
		"physics_hz": Engine.physics_ticks_per_second,
		"max_fps": Engine.max_fps,
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"seed": 42,
		"os_version": OS.get_version(),
		"low_processor_usage_mode": OS.low_processor_usage_mode,
		"probe_mode": "pacing" if "--pacing-only" in OS.get_cmdline_user_args() else ("small_bursts" if "--bursts-only" in OS.get_cmdline_user_args() else "animation_and_stress"),
	}
	print("RESPONSIVENESS_META ", JSON.stringify(meta))
	if "--pacing-only" in OS.get_cmdline_user_args():
		await _pacing()
		_write_results(meta, 0.0, 0.0)
		return
	if "--bursts-only" in OS.get_cmdline_user_args():
		await _small_bursts()
		_write_results(meta, 0.0, 0.0)
		return
	await _sample("farm_mabel_idle", 240)
	# Keep camera, character root and farm constant; only the pose path changes.
	_farmer.set_physics_process(false)
	_farmer.velocity = Vector3(0.0, 0.0, -7.0)
	await _settle(60)
	await _sample("farm_mabel_run_pose", 240)
	StopMotionClock.tick_24.disconnect(_farmer._on_tick_24)
	await _settle(60)
	await _sample("farm_mabel_pose_frozen", 240)
	_farmer.set_rigged_model(false)
	await _settle(60)
	await _sample("farm_clay_pose_frozen", 240)
	_farmer.set_rigged_model(true)
	StopMotionClock.tick_24.connect(_farmer._on_tick_24)
	_farmer.velocity = Vector3.ZERO
	_farmer.set_physics_process(true)
	await _settle(60)
	await _sample("farm_mabel_idle_repeat", 240)
	_director._enter_siren(10.0)
	var spawn_start := Time.get_ticks_usec()
	for i in 60:
		var pos := Vector3(float(i % 10 - 5) * 1.5, 0.1, float(i / 10) * -1.8 + 12.0)
		_director._spawn_robot(_director.archetypes[i % _director.archetypes.size()], pos, false, [], null)
	var spawn_ms := (Time.get_ticks_usec() - spawn_start) / 1000.0
	await get_tree().create_timer(3.0).timeout
	await _sample("sixty_mixed_robots", 300)
	# Separate the cost of rendering/AI from pose computation, with the same crowd.
	StopMotionClock.tick_24.disconnect(_farmer._on_tick_24)
	await _sample("sixty_mixed_robots_player_pose_frozen", 240)
	StopMotionClock.tick_24.connect(_farmer._on_tick_24)
	# Disable intentional hitstop only, preserving normal FX and stop-motion stepping.
	Hitstop._ready_at_msec = Time.get_ticks_msec() + 60000
	var death_start := Time.get_ticks_usec()
	for robot in get_tree().get_nodes_in_group(Robot.GROUP):
		robot.kill(true)
	var death_ms := (Time.get_ticks_usec() - death_start) / 1000.0
	await _sample("death_burst_without_hitstop", 300)
	await _settle(180)
	await _sample("post_burst_recovered", 180)
	_write_results(meta, spawn_ms, death_ms)


func _small_bursts() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("view.png"))
	await _sample("small_bursts_idle", 180)
	_director._enter_siren(10.0)
	var nibbler := load("res://data/robots/archetypes/nibbler.tres") as RobotArchetype
	for count in [3, 6, 12]:
		var start := Time.get_ticks_usec()
		var before := _compiles()
		for i in count:
			var pos := Vector3(float(i % 6 - 3) * 1.5, 0.1, 15.0 - float(i / 6) * 2.0)
			_director._spawn_robot(nibbler, pos, false, [], null)
		var spawn_ms := (Time.get_ticks_usec() - start) / 1000.0
		await _sample("spawn_%d_nibblers" % count, 180)
		var new_pipelines := _compiles() - before
		# Blocking hitstop directly avoids changing the visual stepping or camera shake.
		Hitstop._ready_at_msec = Time.get_ticks_msec() + 60000
		start = Time.get_ticks_usec()
		for robot in get_tree().get_nodes_in_group(Robot.GROUP):
			robot.kill(true)
		var death_ms := (Time.get_ticks_usec() - start) / 1000.0
		_burst_cpu.append({"count": count, "spawn_ms": spawn_ms, "death_ms": death_ms, "spawn_new_pipelines": new_pipelines})
		await _sample("kill_%d_without_hitstop" % count, 240)
		for pickup in get_tree().get_nodes_in_group(Pickup.GROUP):
			pickup.queue_free()
		await _settle(120)
	# Camera rotation is updated each render frame by the real rig; this stresses changing visibility.
	var wall: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 360:
		_farmer.camera_rig.yaw = float(i) * TAU / 360.0
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall.append(float(now - previous) / 1000.0)
		previous = now
	wall.sort()
	_results.append({"scenario": "farm_camera_360_sweep", "frames": 360, "wall_ms": {"p50": wall[180], "p95": wall[342], "p99": wall[356], "max": wall.back()}})
	print("RESPONSIVENESS_CAMERA_SWEEP ", JSON.stringify(_results.back()))


func _pacing() -> void:
	var cases := [
		{"label": "default_static", "vsync": DisplayServer.VSYNC_DISABLED, "cap": 0, "orbit": 0.0, "scale": 0.5},
		{"label": "default_camera_motion", "vsync": DisplayServer.VSYNC_DISABLED, "cap": 0, "orbit": 0.6, "scale": 0.5},
		{"label": "vsync_camera_motion", "vsync": DisplayServer.VSYNC_ENABLED, "cap": 0, "orbit": 0.6, "scale": 0.5},
		{"label": "vsync_cap60_camera_motion", "vsync": DisplayServer.VSYNC_ENABLED, "cap": 60, "orbit": 0.6, "scale": 0.5},
		{"label": "vsync_cap120_camera_motion", "vsync": DisplayServer.VSYNC_ENABLED, "cap": 120, "orbit": 0.6, "scale": 0.5},
		{"label": "off_cap60_camera_motion", "vsync": DisplayServer.VSYNC_DISABLED, "cap": 60, "orbit": 0.6, "scale": 0.5},
		{"label": "off_quarter_scale_camera_motion", "vsync": DisplayServer.VSYNC_DISABLED, "cap": 0, "orbit": 0.6, "scale": 0.25},
	]
	if "--pacing-confirm" in OS.get_cmdline_user_args():
		var repeat: Dictionary = cases[1].duplicate()
		repeat.label = "default_camera_motion_repeat"
		cases = [cases[1], cases[2], repeat, cases[5],
			{"label": "off_no_3d_camera_motion", "vsync": DisplayServer.VSYNC_DISABLED, "cap": 0, "orbit": 0.6, "scale": 0.5, "disable_3d": true}]
	for config in cases:
		DisplayServer.window_set_vsync_mode(config.vsync)
		Engine.max_fps = config.cap
		get_viewport().scaling_3d_scale = config.scale
		RenderingServer.viewport_set_disable_3d(_viewport_rid, bool(config.get("disable_3d", false)))
		_farmer.camera_rig.yaw = 0.0
		_sweep_camera = false
		await _settle(60)
		# Every configuration renders the same 360 camera angles, independent of its frame rate.
		_sweep_camera = config.orbit > 0.0
		await _sample(config.label, 360)
		_results.back()["configuration"] = config
		_results.back()["reported_vsync_mode"] = DisplayServer.window_get_vsync_mode()
		_results.back()["window_focused"] = get_window().has_focus()
	_sweep_camera = false
	RenderingServer.viewport_set_disable_3d(_viewport_rid, false)


func _write_results(meta: Dictionary, spawn_ms: float, death_ms: float) -> void:
	var report := {"metadata": meta, "small_burst_cpu": _burst_cpu, "samples": _results,
		"measurement_notes": "wall_ms is process_frame interval, not physical display latency. Engine process/physics monitors publish one-second maxima and can lag scenario boundaries. A zero GPU timer is unavailable, not free rendering. Synchronous spawn/kill calls are recorded separately and excluded from sample intervals."}
	if meta.probe_mode == "animation_and_stress":
		report["spawn_60_cpu_ms"] = spawn_ms
		report["kill_60_cpu_ms"] = death_ms
	var json_file := FileAccess.open(_out.path_join("rendered.json"), FileAccess.WRITE)
	json_file.store_string(JSON.stringify(report, "  "))
	var csv_file := FileAccess.open(_out.path_join("frames.csv"), FileAccess.WRITE)
	csv_file.store_string("\n".join(_raw))
	print("RESPONSIVENESS_DONE ", _out)
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _compiles() -> int:
	var count := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		count += RenderingServer.get_rendering_info(info)
	return count


func _sample(label: String, frames: int) -> void:
	var series := {"wall_ms": [], "process_ms": [], "physics_ms": [], "render_cpu_ms": [], "render_gpu_ms": [], "draw_calls": [], "primitives": []}
	var last := Time.get_ticks_usec()
	var pipeline_before := _compiles()
	var previous_pipelines := pipeline_before
	var over_25 := 0
	var over_33 := 0
	for i in frames:
		if _sweep_camera:
			_farmer.camera_rig.yaw = TAU * float(i) / float(frames)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var wall_ms := float(now - last) / 1000.0
		last = now
		var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var render_cpu := RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
		var render_gpu := RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var pipelines := _compiles()
		series.wall_ms.append(wall_ms)
		series.process_ms.append(process_ms)
		series.physics_ms.append(physics_ms)
		series.render_cpu_ms.append(render_cpu)
		series.render_gpu_ms.append(render_gpu)
		series.draw_calls.append(draws)
		series.primitives.append(primitives)
		over_25 += int(wall_ms > 25.0)
		over_33 += int(wall_ms > 33.333)
		_raw.append("%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.0f,%.0f,%.2f,%d" % [label, i, wall_ms, process_ms, physics_ms, render_cpu, render_gpu, draws, primitives, Engine.time_scale, pipelines - previous_pipelines])
		previous_pipelines = pipelines
	var result := {"scenario": label, "frames": frames, "over_25ms": over_25, "over_33ms": over_33, "new_pipelines": _compiles() - pipeline_before, "live_robots_end": _director.live_robot_count(), "pickups_end": get_tree().get_nodes_in_group(Pickup.GROUP).size()}
	for key in series:
		var values: Array = series[key]
		values.sort()
		if key in ["process_ms", "physics_ms"]:
			# Godot 4.7.2 publishes these as one-second maxima. Repeated queries are not independent CPU samples.
			result["engine_1s_peak_" + key] = {"max_observed": values.back()}
		else:
			result[key] = {"p50": values[frames / 2], "p95": values[int(frames * 0.95)], "p99": values[int(frames * 0.99)], "max": values.back()}
	_results.append(result)
	print("RESPONSIVENESS_SAMPLE ", JSON.stringify(result))
