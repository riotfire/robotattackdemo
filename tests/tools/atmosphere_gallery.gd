extends Node3D
## Atmosphere gallery (GDD 4.6, 15.5): the real farm under every time-of-day preset and weather, seen from
## gameplay cameras with robot families standing in the crop rows at 10, 25 and 45 m. For reviewing that
## robots stay readable against the crops (also in grayscale), and for M2-F3's per-preset contrast work.
## Interactive: run the scene; F9 / F10 step the time of day / weather (TimeOfDay's debug keys), Tab
## switches the view, G toggles grayscale.
## Batch: add `-- --out=<absolute folder>` (and optionally `--seed=<n>`) to a windowed run. It saves one PNG
## per view x preset x weather plus a contact sheet per view (rows = presets, columns = weathers) in color
## and grayscale, then quits.

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const GENE_LIBRARY := "res://data/robots/gene_library.tres"
const ARCHETYPES: Array[String] = [
	"res://data/robots/archetypes/nibbler.tres",
	"res://data/robots/archetypes/clanker.tres",
	"res://data/robots/archetypes/thumper.tres",
]
## [name, camera position, look-at point]. South looks into the noon sun; north has it behind.
const VIEWS: Array[Array] = [
	["south", Vector3(-1.5, 2.4, 46.0), Vector3(0.0, 1.2, 80.0)],
	["north", Vector3(1.5, 2.4, -46.0), Vector3(0.0, 1.2, -80.0)],
	["overview", Vector3(6.0, 17.5, 18.0), Vector3(0.0, 0.0, 70.0)],
]
## Robot distances from the shoulder cameras, in meters.
const DISTANCES: PackedFloat32Array = [10.0, 25.0, 45.0]
## Each row stands off to one side, so nearer robots don't hide the farther ones.
const ROW_SHIFT: PackedFloat32Array = [-4.5, 3.5, -0.5]
const THUMB := Vector2i(480, 270)

var _farm: Node3D
var _time_of_day: TimeOfDay
var _camera: Camera3D
var _caption: Label
var _gray: ColorRect
var _view: int = 0
var _batching: bool = false


func _ready() -> void:
	var run_seed := 7
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			run_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_farm = (load(FARM_SCENE) as PackedScene).instantiate() as Node3D
	add_child(_farm)
	_time_of_day = _farm.get_node(^"TimeOfDay") as TimeOfDay
	_time_of_day.transition_time = 0.0
	GameState.start_run(run_seed)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.make_current()
	_build_overlay()
	_place_robots(run_seed)
	_set_view(0)
	if out != "":
		_batch.call_deferred(out)


func _batch(out: String) -> void:
	_batching = true
	DirAccess.make_dir_recursive_absolute(out)
	var table := _time_of_day.table
	for view in VIEWS.size():
		_set_view(view)
		var sheet := Image.create(THUMB.x * table.weathers.size(), THUMB.y * table.presets.size(), false, Image.FORMAT_RGB8)
		for w in table.weathers.size():
			_time_of_day.set_weather_index(w)
			for p in table.presets.size():
				_time_of_day.show_preset(p, false)
				_caption.text = "%s  ·  %s  ·  %s" % [table.presets[p].display_name, table.weathers[w].display_name, VIEWS[view][0]]
				# Let the sky's radiance map (ambient light lags it), the particles and the puddles settle.
				for i in 45:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var shot := get_viewport().get_texture().get_image()
				shot.convert(Image.FORMAT_RGB8)
				shot.save_png(out.path_join("%s_%s_%s.png" % [VIEWS[view][0], table.presets[p].id, table.weathers[w].id]))
				shot.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
				sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, THUMB), Vector2i(w * THUMB.x, p * THUMB.y))
		sheet.save_png(out.path_join("sheet_%s.png" % VIEWS[view][0]))
		_gray_copy(sheet).save_png(out.path_join("sheet_%s_gray.png" % VIEWS[view][0]))
	print("Atmosphere gallery saved to %s" % out)
	get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_TAB:
		_set_view((_view + 1) % VIEWS.size())
	elif key.physical_keycode == KEY_G:
		_gray.visible = not _gray.visible


func _process(_delta: float) -> void:
	if not _batching and _time_of_day.current_preset() != null:
		_caption.text = "%s  ·  %s  ·  %s" % [_time_of_day.current_preset().display_name,
				_time_of_day.current_weather().display_name, VIEWS[_view][0]]


func _set_view(index: int) -> void:
	_view = index
	_camera.position = VIEWS[index][1]
	_camera.look_at(VIEWS[index][2], Vector3.UP)


## Three families: one Nibbler, Clanker and Thumper each at 10, 25 and 45 m in front of both shoulder views.
func _place_robots(run_seed: int) -> void:
	var library := load(GENE_LIBRARY) as GeneLibrary
	var curve := DifficultyCurve.new()
	var history: Array[RobotGenome] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var no_traits: Array[RobotTrait] = []
	var robots := Node3D.new()
	robots.name = "Robots"
	add_child(robots)
	for view in 2:
		var origin: Vector3 = VIEWS[view][1]
		var forward := ((VIEWS[view][2] as Vector3) - origin)
		forward.y = 0.0
		forward = forward.normalized()
		var side := forward.cross(Vector3.UP)
		for row in DISTANCES.size():
			var genome := RobotGenome.roll(run_seed, 6 + view * 3 + row, library, history, curve)
			history.append(genome)
			for i in ARCHETYPES.size():
				var archetype := load(ARCHETYPES[i]) as RobotArchetype
				var robot := archetype.scene.instantiate() as Robot
				robot.setup(archetype, genome.wave, curve, rng, genome, false, no_traits)
				robots.add_child(robot)
				robot.process_mode = Node.PROCESS_MODE_DISABLED
				var at := Vector3(origin.x, 0.0, origin.z) + forward * DISTANCES[row] + side * (ROW_SHIFT[row] + (i - 1.0) * 1.8)
				robot.global_position = at
				robot.model.rotation.y = atan2(-forward.x, -forward.z) + PI + rng.randf_range(-0.4, 0.4)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_gray = ColorRect.new()
	_gray.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), 1.0);
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_gray.material = material
	_gray.visible = false
	layer.add_child(_gray)
	_caption = Label.new()
	_caption.position = Vector2(16.0, 12.0)
	_caption.add_theme_font_size_override(&"font_size", 22)
	_caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_caption)


static func _gray_copy(image: Image) -> Image:
	var gray := image.duplicate() as Image
	for y in gray.get_height():
		for x in gray.get_width():
			var c := gray.get_pixel(x, y)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			gray.set_pixel(x, y, Color(l, l, l))
	return gray
