extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := get_tree().root
	var save := root.get_node("SaveManager")
	save.use_profile("/tmp/stables-preview-profile.json", true)
	save.tutorial_completed = true
	save.resume_wave = 2
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	get_tree().current_scene = main
	for i in 60:
		await get_tree().physics_frame
	var construction: ConstructionManager = main.get_node("Construction")
	construction.director.time_left = 90.0
	GameState.god_mode = true
	GameState.add_parts({&"al": 100})
	var farmer := GameState.players[0] as Farmer
	farmer.teleport_to(Vector3(20.0, 0.2, -16.0))
	farmer.camera_rig.yaw = 0.0
	farmer.camera_rig.pitch = deg_to_rad(-8.0)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/stables-workshop.png")
	farmer.teleport_to(construction.workshop.interaction_point() + Vector3.UP * 0.1)
	for i in 20:
		await get_tree().physics_frame
	construction.open_recipe_menu(farmer)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/stables-menu.png")
	construction.close_menu()
	StatService.grant(&"build.spring_trap")
	construction.craft(construction.definition(&"spring_trap"), farmer)
	for i in 660:
		await get_tree().physics_frame
	farmer.teleport_to(Vector3(20.0, 0.2, -14.0))
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/stables-pickup.png")
	get_tree().quit()
