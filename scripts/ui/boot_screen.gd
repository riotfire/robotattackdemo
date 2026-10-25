class_name BootScreen
extends Control
## First scene of the game: a loading screen while the farm loads in the background, then a start screen.
## Pass `-- --skip-boot` to jump straight into the game.
## While "Loading..." shows, the farm is drawn into a hidden viewport so the renderer's shaders compile here
## instead of freezing the first gameplay frame (a cold Metal cache costs ~15 s on a fresh install).

const MAIN_SCENE := "res://scenes/main/main.tscn"
const MIN_LOADING_SECONDS := 1.5
const WARM_UP_SCENE := "res://scenes/farm/farm.tscn"
## Frames the warm-up viewport must draw without a new pipeline compile before Play is offered.
const WARM_UP_SETTLE_FRAMES := 10

var _loading_box: VBoxContainer
var _bar: ProgressBar
var _start_box: VBoxContainer
var _play: Button
var _elapsed: float = 0.0
var _loaded: bool = false
var _progress: Array = []
var _warm_up: SubViewport
var _settle_frames: int = 0
var _last_compiles: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	ResourceLoader.load_threaded_request(MAIN_SCENE)
	for arg in OS.get_cmdline_user_args():
		if arg == "--skip-boot":
			_start_game.call_deferred()


func _process(delta: float) -> void:
	if _loaded:
		return
	_elapsed += delta
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE, _progress)
	var fraction: float = _progress[0] if not _progress.is_empty() else 0.0
	_bar.value = minf(fraction, _elapsed / MIN_LOADING_SECONDS)
	if status == ResourceLoader.THREAD_LOAD_LOADED and _warm_up == null:
		_start_warm_up()
	if status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= MIN_LOADING_SECONDS and _warm_up_done():
		_loaded = true
		_warm_up.queue_free()
		_bar.value = 1.0
		_loading_box.visible = false
		_start_box.visible = true
		_play.grab_focus()
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		_loaded = true
		push_error("Could not load %s" % MAIN_SCENE)


func _start_warm_up() -> void:
	_warm_up = SubViewport.new()
	_warm_up.size = Vector2i(320, 180)
	_warm_up.own_world_3d = true
	# Pipelines are keyed on the render target, so match the main viewport's 3D settings.
	var root := get_viewport()
	_warm_up.msaa_3d = root.msaa_3d
	_warm_up.scaling_3d_mode = root.scaling_3d_mode
	_warm_up.scaling_3d_scale = root.scaling_3d_scale
	_warm_up.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm_up)
	_warm_up.add_child((ResourceLoader.load(WARM_UP_SCENE) as PackedScene).instantiate())
	# Draw first-kill resources close to the camera, above the farm's roofs. Merely loading
	# a shader (or hiding its sample behind the silo) does not warm its draw pipelines.
	var effects := Node3D.new()
	effects.name = "FirstKillWarmUp"
	_warm_up.add_child(effects)
	RobotExplosion.warm_up(effects)
	var index := 0
	for kind: StringName in [&"al", &"cu", &"au", &"pc"]:
		var pickup := PickupVisuals.create(kind, Pickup.COLORS[kind])
		effects.add_child(pickup)
		pickup.position = Vector3((index - 1.5) * 3.0, 1.0, 4.0)
		pickup.scale = Vector3.ONE * 4.0
		index += 1
	# A receiver makes the scorch decal and local-light variants actually render.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 14.0)
	Clay.part(effects, floor_mesh, Color(0.4, 0.5, 0.3), Transform3D.IDENTITY)
	effects.position.y = 240.0
	# Top-down over the whole farm so nothing is frustum-culled.
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 1000.0
	camera.position = Vector3(0.0, 250.0, 0.0)
	camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_warm_up.add_child(camera)


## True once the warm-up viewport has drawn a few frames in a row without compiling a new pipeline.
func _warm_up_done() -> bool:
	var compiles := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		compiles += RenderingServer.get_rendering_info(info)
	if compiles != _last_compiles:
		_last_compiles = compiles
		_settle_frames = 0
		return false
	_settle_frames += 1
	return _settle_frames >= WARM_UP_SETTLE_FRAMES


func _start_game() -> void:
	var scene := ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
	if scene == null:
		scene = load(MAIN_SCENE) as PackedScene
	get_tree().change_scene_to_packed(scene)


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.13, 0.10, 0.08)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	column.custom_minimum_size = Vector2(520, 0)
	center.add_child(column)

	var title := Label.new()
	title.text = "Robot Attack!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	column.add_child(title)

	var tagline := Label.new()
	tagline.text = "Defend the silo. Pop the robots."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 24)
	tagline.modulate = Color(1, 1, 1, 0.7)
	column.add_child(tagline)

	_loading_box = VBoxContainer.new()
	_loading_box.add_theme_constant_override("separation", 10)
	column.add_child(_loading_box)
	var loading := Label.new()
	loading.text = "Loading..."
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 22)
	_loading_box.add_child(loading)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 20)
	_loading_box.add_child(_bar)

	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", 14)
	_start_box.visible = false
	column.add_child(_start_box)
	_play = _make_button("Play", _start_game)
	_start_box.add_child(_play)
	if OS.get_name() != "Web":
		_start_box.add_child(_make_button("Quit", func() -> void: get_tree().quit()))


func _make_button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 64)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(handler)
	return button
