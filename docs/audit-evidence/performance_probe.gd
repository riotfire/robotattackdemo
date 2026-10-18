extends Node
## Diagnostic only: frozen director, stationary camera, fixed robot population.
## Run this scene with --disable-vsync --resolution 1280x800 and a disposable --profile path.

var main: Node3D
var director: WaveDirector

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveManager.use_profile("/private/tmp/robot-attack-performance-profile.json", true)
	main = load("res://scenes/main/main.tscn").instantiate()
	main.run_seed = 42
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	director = main.get_node("WaveDirector")
	director.set_physics_process(false)
	GameState.god_mode = true
	GameState.silo.max_structure = 10000000.0
	GameState.silo.structure = 10000000.0
	GameState.silo.grain = 10000000.0
	var farmer: Farmer = GameState.players[0]
	farmer.input.enabled = false
	farmer.teleport_to(Vector3(0, 0.2, 22))
	farmer.camera_rig.pitch = deg_to_rad(-15)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(3.0).timeout
	print("AUDIT_META ", JSON.stringify({"engine": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(), "viewport": str(get_viewport().get_visible_rect().size), "window_pixels": str(DisplayServer.window_get_size()), "seed": 42, "vsync": DisplayServer.window_get_vsync_mode()}))
	await _sample("farm_idle", 180)
	director._enter_siren(10.0)
	var spawn_start := Time.get_ticks_usec()
	for i in 60:
		var pos := Vector3(float(i % 10 - 5) * 1.5, 0.1, float(i / 10) * -1.8 + 12.0)
		director._spawn_robot(director.archetypes[i % director.archetypes.size()], pos, false, [], null)
	print("AUDIT_SPAWN_60_MS ", (Time.get_ticks_usec() - spawn_start) / 1000.0)
	await get_tree().create_timer(3.0).timeout
	await _sample("sixty_mixed_robots", 300)
	var death_start := Time.get_ticks_usec()
	for robot in get_tree().get_nodes_in_group(Robot.GROUP):
		robot.kill(true)
	print("AUDIT_DEATH_60_MS ", (Time.get_ticks_usec() - death_start) / 1000.0)
	await _sample("death_and_pickup_burst", 180)
	get_tree().quit()

func _sample(label: String, frames: int) -> void:
	var times: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var physics: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	times.sort()
	draw_calls.sort()
	primitives.sort()
	physics.sort()
	print("AUDIT_SAMPLE ", JSON.stringify({"scenario": label, "frames": frames, "frame_ms_p50": times[frames / 2], "frame_ms_p95": times[int(frames * 0.95)], "frame_ms_p99": times[int(frames * 0.99)], "frame_ms_max": times.back(), "physics_ms_p95": physics[int(frames * 0.95)], "draw_calls_p50": draw_calls[frames / 2], "primitives_p50": primitives[frames / 2], "live_robots_end": director.live_robot_count(), "pickups_end": get_tree().get_nodes_in_group(Pickup.GROUP).size(), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}))
