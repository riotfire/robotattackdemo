extends Node
## Audit fixture, not a player bot or a balance test. Observes five real waves without defending.
## Protects the farmer and holds silo/grain at 50%; clears enemies after each spawn window.
## Writes measured evidence to /tmp; never loads the player's profile.

var main: Node
var director: WaveDirector
var elapsed := 0.0
var first_hit := -1.0
var damage := 0.0
var peak_live := 0
var spawn_counts := {}
var results: Array = []
var tracking := false

func _ready() -> void:
	SaveManager.use_profile("/tmp/opening-probe-%d.json" % OS.get_process_id(), true)
	SaveManager.tutorial_completed = true
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	if not tracking:
		return
	elapsed += delta
	peak_live = maxi(peak_live, director.live_robot_count())
	GameState.silo.structure = maxf(500.0, GameState.silo.structure)
	GameState.silo.grain = maxf(500.0, GameState.silo.grain)

func _spawned(robot: Node3D) -> void:
	if tracking:
		var id: String = str(robot.archetype.id)
		spawn_counts[id] = int(spawn_counts.get(id, 0)) + 1

func _damaged(amount: float, _at: Vector3) -> void:
	if tracking:
		if first_hit < 0.0:
			first_hit = elapsed
		damage += amount

func _run() -> void:
	# Create directly under root: reparenting a live main clears its registered silo/player.
	main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	director = main.get_node("WaveDirector")
	director._running = false
	EventBus.robot_spawned.connect(_spawned)
	EventBus.silo_damaged.connect(_damaged)
	for i in 60:
		await get_tree().physics_frame
	var region: NavigationRegion3D = main.get_node("Farm/NavRegion")
	while region.is_baking():
		await get_tree().physics_frame
	var schedule_rows: Array = []
	for seed_value in range(1, 101):
		RngService.start_run(seed_value)
		for wave_number in range(1, 6):
			director._wave_rng = RngService.wave_stream(RngService.STREAM_SPAWNS, wave_number)
			director._pick_lanes(director.curve.lane_count(wave_number))
			var events := director._build_spawn_events(wave_number)
			var counts := {}
			var cu := 0.0
			var al := 0.0
			for event in events:
				var a := event.archetype
				counts[str(a.id)] = int(counts.get(str(a.id), 0)) + event.robot_count()
				cu += event.robot_count() * a.drop_cu_chance * (a.drop_cu_min + a.drop_cu_max) / 2.0
				al += event.robot_count() * ((a.drop_al_min + a.drop_al_max) / 2.0 + a.drop_al_class_bonus) * director.curve.drop_multiplier(wave_number)
			var times := director.curve.spawn_schedule(events.size(), director.curve.spawn_window(wave_number) * director.curve.spawn_window_fraction)
			schedule_rows.append({"seed":seed_value,"wave":wave_number,"events":events.size(),"counts":counts,"expected_al_pre_rounding":al,"expected_cu":cu,"first_second_spawn_gap":times[1] if times.size()>1 else 0,"last_spawn":times[-1],"window":director.curve.spawn_window(wave_number),"budget":director.curve.threat_budget(wave_number)})
	FileAccess.open("/tmp/opening-schedules.json",FileAccess.WRITE).store_string(JSON.stringify(schedule_rows,"\t"))
	if "--schedule-only" in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	RngService.start_run(GameState.run_seed)
	GameState.god_mode = true
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		var farmer := GameState.players[0] as Farmer
		farmer.input.enabled = false
		farmer.teleport_to(Vector3(10.0, 0.2, 14.0))
		farmer.camera_rig.yaw = 0.62
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for wave_number in range(1, 6):
		for crack in GameState.silo.get_cracks().duplicate():
			GameState.silo.repair_crack(crack,100.0)
		GameState.silo.structure = 1000.0
		GameState.silo.grain = 1000.0
		elapsed = 0.0
		first_hit = -1.0
		damage = 0.0
		peak_live = 0
		spawn_counts = {}
		director._running = true
		director.skip_to_wave(wave_number)
		while director.phase != WaveDirector.Phase.SPAWNING:
			await get_tree().physics_frame
		tracking = true
		var captured := false
		while elapsed < director.spawn_window + 5.0:
			await get_tree().physics_frame
			if rendered and elapsed > 30.0 and not captured:
				captured = true
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("/tmp/opening-wave-%d.png" % wave_number)
		var foremen: Array = []
		for bot in get_tree().get_nodes_in_group(Robot.GROUP):
			if bot.is_foreman:
				foremen.append({"hp":bot.health.max_health,"traits":bot.all_traits().map(func(t: RobotTrait):return str(t.id))})
		var row := {"wave":wave_number,"observed_seconds":elapsed,"first_silo_hit_s":first_hit,"unopposed_silo_damage":damage,"peak_live":peak_live,"counts":spawn_counts.duplicate(),"foremen":foremen,"lanes":Array(director.active_lanes),"family":director.genome.family_name,"last_scheduled_spawn":director._schedule[-1],"cracks":GameState.silo.get_cracks().size(),"leak_per_second":GameState.silo.total_leak_rate()}
		tracking = false
		director.clear_robots(false)
		while director.phase != WaveDirector.Phase.CLEARED:
			await get_tree().physics_frame
		results.append(row)
		print("OPENING_AUDIT ",JSON.stringify(row))
		director._running = false
	FileAccess.open("/tmp/opening-runtime.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	get_tree().quit()
