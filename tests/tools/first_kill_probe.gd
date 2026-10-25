extends Node3D
## Rendered first-kill regression: both kills must compile zero additional pipelines after boot.
## Run this scene with -- --profile=/tmp/first-kill-profile.json; requires a real renderer.
## Timings are diagnostic, not pass/fail thresholds (hardware and frame caps vary).

var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()


func _compiles() -> int:
	var count := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		count += RenderingServer.get_rendering_info(info)
	return count


func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--skip-boot" in OS.get_cmdline_user_args():
		push_error("FirstKillProbe needs a graphical renderer and the boot warm-up")
		get_tree().quit(2)
		return
	var boot := BootScreen.new()
	add_child(boot)
	var deadline := Time.get_ticks_msec() + 120000
	while not boot._loaded:
		if Time.get_ticks_msec() > deadline:
			push_error("First-kill warm-up timed out")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	print("PROBE boot ready pipelines=", _compiles())
	boot.queue_free()
	await get_tree().process_frame
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	add_child(farm)
	RngService.start_run(7)
	var camera := Camera3D.new()
	camera.position = Vector3(16.0, 3.0, 15.0)
	add_child(camera)
	camera.look_at(Vector3(16.0, 0.6, 10.0))
	camera.current = true
	for attempt in 2:
		var archetype := (load("res://data/robots/archetypes/nibbler.tres") as RobotArchetype).duplicate() as RobotArchetype
		archetype.drop_al_min = 1
		archetype.drop_al_max = 1
		archetype.drop_cu_chance = 1.0
		archetype.drop_cu_min = 1
		archetype.drop_cu_max = 1
		archetype.drop_au_chance = 1.0
		archetype.drop_au_min = 1
		archetype.drop_au_max = 1
		archetype.drop_pc_chance = 1.0
		archetype.drop_pc_min = 1
		archetype.drop_pc_max = 1
		var robot := archetype.scene.instantiate() as Robot
		robot.setup(archetype, 1, DifficultyCurve.new(), RandomNumberGenerator.new())
		add_child(robot)
		robot.position = Vector3(16.0, 0.0, 10.0)
		robot.agent.avoidance_enabled = false
		robot.set_physics_process(false)
		for frame in 120:
			await get_tree().process_frame
		var before := _compiles()
		var start := Time.get_ticks_usec()
		robot.kill(true)
		var cpu_ms := (Time.get_ticks_usec() - start) / 1000.0
		var max_ms := 0.0
		for frame in 90:
			var tick := Time.get_ticks_usec()
			await get_tree().process_frame
			max_ms = maxf(max_ms, (Time.get_ticks_usec() - tick) / 1000.0)
		var new_pipelines := _compiles() - before
		print("PROBE kill=%d cpu_ms=%.2f worst_frame_ms=%.2f new_pipelines=%d" % [attempt + 1, cpu_ms, max_ms, new_pipelines])
		if new_pipelines != 0:
			_failures += 1
			push_error("Robot death compiled %d pipelines after loading" % new_pipelines)
	print("FIRST KILL PROBE PASSED" if _failures == 0 else "FIRST KILL PROBE FAILED")
	get_tree().quit(0 if _failures == 0 else 1)
