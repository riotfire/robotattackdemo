class_name Weather
extends Node3D
## The run's weather (GDD 4.6): Clear, Breezy, Drizzle or Morning Fog. TimeOfDay rolls it at run start and
## hands it here; this node shows the parts that aren't lighting: wind in the paper corn, falling clay
## droplets, puddles and wet clay. Fog distances and the eye-glow boost are lighting (AtmosphereLook).
## Gameplay reads the weather only through the static queries below, so robots never need this node.

const CLAY_SHADER_PATH := "res://shaders/clay.gdshader"
const FELT_SHADER_PATH := "res://shaders/felt.gdshader"
const CORN_SHADER_PATH := "res://shaders/paper_corn.gdshader"
## Wet clay keeps this share of its dry roughness at full wetness.
const WET_ROUGHNESS := 0.55
## Wet felt keeps this share of its dry brightness at full wetness.
const WET_FELT := 0.78

## The run's weather (null before the first run and after the farm is gone).
static var current: WeatherType
## Wind for drifting flyers (Breezy, GDD 4.6): world-space direction scaled by wind strength (0..1).
static var wind: Vector3 = Vector3.ZERO

## Every clay material shares the dry roughness of the shared clay material (shaders/clay_material.tres).
## Read once, before any weather has touched it.
static var _dry_clay_roughness: float = -1.0
static var _puddle_orm: Texture2D
static var _puddle_normal: Texture2D

## The paper corn wall (CornField); its chunks get the swaying material in wind or rain.
@export var corn_field: Node3D
## Rain falls inside a box this wide around the camera.
@export var rain_area: float = 44.0
@export var rain_height: float = 16.0
## Drops at rain_amount 1.
@export var max_rain_drops: int = 1800
## Puddles go on open ground within this distance of the silo.
@export var puddle_radius: float = 48.0

var weather: WeatherType

var _rain: GPUParticles3D
var _puddles: Node3D
var _corn_material: ShaderMaterial
var _puddle_textures: Array[Texture2D] = []
## Bumped on every weather change, so a puddle placement still waiting for physics knows it's stale.
var _puddle_generation: int = 0


## Engagement range multiplier for a robot class under the current weather. Morning Fog shortens long-range
## robots' range by 20% (GDD 4.6); every other class and weather gives 1. The long-range class (M2-B2) scales
## its engagement and siege ranges by this.
static func engagement_range_multiplier(robot_class: RobotArchetype.RobotClass) -> float:
	if current == null or robot_class != RobotArchetype.RobotClass.RANGED:
		return 1.0
	return current.long_range_multiplier


static func engagement_range(base_range: float, robot_class: RobotArchetype.RobotClass) -> float:
	return base_range * engagement_range_multiplier(robot_class)


func _exit_tree() -> void:
	if current == weather:
		current = null
		wind = Vector3.ZERO


func _process(_delta: float) -> void:
	if _rain == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Emit upwind of the camera, so drops that slant with the wind still land around it.
		_rain.global_position = camera.global_position + Vector3.UP * rain_height * 0.6 - wind * 4.0


## Shows `type`. `wind_bearing` is where the wind blows toward (clockwise from north); `puddle_seed` places the
## puddles. Both come from the run's roll, so every peer sees the same weather.
func set_weather(type: WeatherType, wind_bearing: float, puddle_seed: int) -> void:
	weather = type
	current = type
	wind = Vector3.FORWARD.rotated(Vector3.UP, -deg_to_rad(wind_bearing)) * type.wind_strength
	_apply_rain()
	_apply_corn()
	_apply_wetness()
	_apply_puddles(puddle_seed)


func rain_drop_count() -> int:
	return _rain.amount if _rain != null else 0


func puddle_count() -> int:
	return _puddles.get_child_count() if _puddles != null else 0


func corn_is_swaying() -> bool:
	return _corn_material != null and float(_corn_material.get_shader_parameter(&"wind_strength")) > 0.0


# --- Rain -----------------------------------------------------------------------------------------

## Drizzle: little glossy clay droplets, simulated every rendered frame. Stepping at 12 fps
## moved a 15 m/s drop ~1.25 m per tick (nearly 5x its 0.26 m length), which read as strobing, not rain.
func _apply_rain() -> void:
	var drops := roundi(max_rain_drops * weather.rain_amount)
	if drops <= 0:
		if _rain != null:
			_rain.queue_free()
			_rain = null
		return
	if _rain == null:
		_rain = _build_rain()
		add_child(_rain)
	_rain.amount = drops
	var process := _rain.process_material as ParticleProcessMaterial
	process.direction = (Vector3.DOWN + wind * 0.35).normalized()
	_rain.emitting = true


func _build_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.local_coords = false
	rain.lifetime = 1.3
	rain.preprocess = 1.3
	rain.fixed_fps = 0
	rain.interpolate = true
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.visibility_aabb = AABB(Vector3(-rain_area, -rain_height * 1.5, -rain_area), Vector3(rain_area, rain_height * 2.0, rain_area) * 2.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(rain_area * 0.5, 0.5, rain_area * 0.5)
	process.spread = 4.0
	process.initial_velocity_min = 13.0
	process.initial_velocity_max = 16.0
	process.gravity = Vector3(0.0, -4.0, 0.0)
	process.particle_flag_align_y = true
	process.scale_min = 0.8
	process.scale_max = 1.2
	rain.process_material = process
	var drop := CapsuleMesh.new()
	drop.radius = 0.011
	drop.height = 0.26
	drop.radial_segments = 4
	drop.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.82, 0.95, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	material.shadow_to_opacity = false
	drop.material = material
	rain.draw_pass_1 = drop
	return rain


# --- Corn -----------------------------------------------------------------------------------------

func _apply_corn() -> void:
	if corn_field == null:
		return
	var needed := weather.wind_strength > 0.0 or weather.wetness > 0.0
	if needed and _corn_material == null:
		_corn_material = ShaderMaterial.new()
		_corn_material.shader = load(CORN_SHADER_PATH)
		corn_field.child_entered_tree.connect(_on_corn_chunk_added)
	elif not needed and _corn_material != null:
		_corn_material = null
		corn_field.child_entered_tree.disconnect(_on_corn_chunk_added)
	if _corn_material != null:
		_corn_material.set_shader_parameter(&"wind_strength", weather.wind_strength)
		_corn_material.set_shader_parameter(&"wind_direction", Vector2(wind.x, wind.z))
		_corn_material.set_shader_parameter(&"wetness", weather.wetness)
	# CornField rebuilds its chunks at run start, maybe after this; new chunks are caught by the signal.
	for chunk in corn_field.get_children():
		_on_corn_chunk_added(chunk)


func _on_corn_chunk_added(chunk: Node) -> void:
	var geometry := chunk as GeometryInstance3D
	if geometry != null:
		geometry.material_override = _corn_material


# --- Wet clay and felt ----------------------------------------------------------------------------

## Drizzle: shinier clay and darker felt (GDD 4.6). Clay and felt materials are shared resources that outlive
## a run, so wetness is always set from the dry values, never from what the last run left behind.
func _apply_wetness() -> void:
	var clay := load(CLAY_SHADER_PATH) as Shader
	var felt := load(FELT_SHADER_PATH) as Shader
	if _dry_clay_roughness < 0.0:
		_dry_clay_roughness = float(Clay.shared().get_shader_parameter(&"roughness_value"))
	var materials: Array[ShaderMaterial] = [Clay.shared(), Clay.vertex_colored()]
	var root := get_parent()
	if root != null:
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			var material := (node as GeometryInstance3D).material_override as ShaderMaterial
			if material != null and not material in materials:
				materials.append(material)
	var roughness := _dry_clay_roughness * lerpf(1.0, WET_ROUGHNESS, weather.wetness)
	var felt_scale := lerpf(1.0, WET_FELT, weather.wetness)
	for material in materials:
		if material.shader == clay:
			material.set_shader_parameter(&"roughness_value", roughness)
		elif material.shader == felt:
			_darken(material, &"albedo_color", felt_scale)
			_darken(material, &"patch_color", felt_scale)


## Sets a color parameter to its dry value (kept in the material's metadata) times `scale`.
static func _darken(material: ShaderMaterial, parameter: StringName, scale: float) -> void:
	var meta := StringName("dry_" + parameter)
	if not material.has_meta(meta):
		material.set_meta(meta, material.get_shader_parameter(parameter))
	var dry: Variant = material.get_meta(meta)
	if dry is Color:
		var color := dry as Color
		material.set_shader_parameter(parameter, Color(color.r * scale, color.g * scale, color.b * scale, color.a))


# --- Puddles --------------------------------------------------------------------------------------

## Glossy dark decals on open ground: they catch the sky like wet felt would.
func _apply_puddles(puddle_seed: int) -> void:
	if _puddles != null:
		_puddles.queue_free()
		_puddles = null
	_puddle_generation += 1
	var generation := _puddle_generation
	if weather.puddle_count <= 0:
		return
	_puddles = Node3D.new()
	_puddles.name = "Puddles"
	add_child(_puddles)
	# Wait for the physics space to hold this run's props before probing for open ground.
	await get_tree().physics_frame
	if generation != _puddle_generation or _puddles == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = puddle_seed
	var space := get_world_3d().direct_space_state
	var placed := 0
	var tries := 0
	while placed < weather.puddle_count and tries < weather.puddle_count * 8:
		tries += 1
		var angle := rng.randf() * TAU
		var distance := lerpf(9.0, puddle_radius, sqrt(rng.randf()))
		var size := rng.randf_range(3.0, 6.5)
		var yaw := rng.randf() * TAU
		var shape := rng.randi_range(0, 2)
		var at := Vector3(cos(angle), 0.0, sin(angle)) * distance
		if not _is_open_ground(space, at, size * 0.5):
			continue
		_puddles.add_child(_puddle(at, size, yaw, shape))
		placed += 1


## True when the ground at `at` and around it within `radius` is bare: no building, prop or step on it.
func _is_open_ground(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float) -> bool:
	for offset: Vector3 in [Vector3.ZERO, Vector3(radius, 0, 0), Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
		var query := PhysicsRayQueryParameters3D.create(at + offset + Vector3.UP * 30.0, at + offset + Vector3.DOWN)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit["position"] as Vector3).y > 0.05:
			return false
	return true


func _puddle(at: Vector3, size: float, yaw: float, shape: int) -> Decal:
	var decal := Decal.new()
	decal.position = at
	decal.rotation.y = yaw
	decal.size = Vector3(size, 0.4, size * 0.7)
	decal.texture_albedo = _puddle_texture(shape)
	decal.texture_orm = _orm_texture()
	decal.texture_normal = _flat_normal_texture()
	decal.albedo_mix = 0.8
	decal.modulate = Color(0.24, 0.27, 0.32)
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.cull_mask = 1
	return decal


## A soft-edged blob with a wobbly outline, generated once per shape.
func _puddle_texture(shape: int) -> Texture2D:
	while _puddle_textures.size() <= shape:
		var noise := FastNoiseLite.new()
		noise.seed = 31 + _puddle_textures.size()
		noise.frequency = 0.035
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var p := Vector2(x - 63.5, y - 63.5) / 63.5
				var edge := 0.72 + noise.get_noise_2d(x, y) * 0.35
				var alpha := clampf((edge - p.length()) / 0.08, 0.0, 1.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		_puddle_textures.append(ImageTexture.create_from_image(image))
	return _puddle_textures[shape]


## Water lies flat: it hides the felt's weave, so the puddle mirrors the sky in one smooth sheet.
static func _flat_normal_texture() -> Texture2D:
	if _puddle_normal == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color(0.5, 0.5, 1.0))
		_puddle_normal = ImageTexture.create_from_image(image)
	return _puddle_normal


## Occlusion 1, roughness low, metal 0: mirror-ish water over matte felt.
static func _orm_texture() -> Texture2D:
	if _puddle_orm == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color(1.0, 0.06, 0.0))
		_puddle_orm = ImageTexture.create_from_image(image)
	return _puddle_orm
