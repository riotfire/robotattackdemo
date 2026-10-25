extends Node3D
## Actual-size loot on grass and dirt. N toggles night, Space pauses the spin, Escape exits.
## Capture both lighting conditions: godot --path . res://tests/tools/pickup_gallery.tscn
## -- --out=/tmp/pickup-gallery (writes PNGs and exits).

var _environment: Environment
var _sun: DirectionalLight3D
var _night := false
var _pickups: Array[Pickup] = []


func _ready() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(_sun)
	_lighting()
	for row in 2:
		var lawn := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(20.0, 5.0)
		lawn.mesh = plane
		lawn.position.z = -float(row) * 5.0
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.3, 0.43, 0.16) if row == 0 else Color(0.34, 0.23, 0.13)
		material.roughness = 1.0
		lawn.material_override = material
		add_child(lawn)
		var kinds: Array[StringName] = [&"al", &"cu", &"au", &"pc"]
		for i in kinds.size():
			var pickup := Pickup.new()
			pickup.kind = kinds[i]
			pickup._landed = true
			add_child(pickup)
			pickup.position = Vector3((i - 1.5) * 1.15, 0.12, -row * 5.0)
			_pickups.append(pickup)
	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.position = Vector3(0.0, 2.6, 4.5)
	camera.look_at(Vector3(0.0, 0.0, -1.5))
	camera.current = true
	var label := Label.new()
	label.text = "ALUMINUM: GEAR     /     COPPER: SPRING     /     GOLD: RING     /     POWER CELL: BLUE BATTERY\nActual size on grass and dirt  •  N: day/night  •  Space: freeze spin"
	label.position = Vector2(24.0, 24.0)
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_capture.call_deferred(arg.trim_prefix("--out="))


func _process(_delta: float) -> void:
	# Keep the display alive for inspection without changing gameplay pickup lifetimes.
	for pickup in _pickups:
		pickup._age = 0.0


func _lighting() -> void:
	_environment.background_color = Color(0.025, 0.04, 0.08) if _night else Color(0.65, 0.78, 0.9)
	_environment.ambient_light_color = Color(0.35, 0.45, 0.7) if _night else Color(0.85, 0.9, 1.0)
	_environment.ambient_light_energy = 0.18 if _night else 0.6
	_sun.light_energy = 0.12 if _night else 1.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_N:
		_night = not _night
		_lighting()
	elif event.keycode == KEY_SPACE:
		for pickup in _pickups:
			pickup.set_physics_process(not pickup.is_physics_processing())
	elif event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _capture(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for pickup in _pickups:
		pickup.set_physics_process(false)
	for night in [false, true]:
		_night = night
		_lighting()
		for frame in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("night.png" if night else "day.png"))
	get_tree().quit()
