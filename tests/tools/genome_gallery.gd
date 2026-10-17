extends Node3D
## Genome gallery (GDD 18.9): rolls robot families and lines up each one's Nibbler, Clanker, Thumper and
## Foreman side by side, to review variety and readability. Robots are posed but their AI is off.
## Run the scene (F6 in the editor). R rerolls with a new seed; arrow keys orbit; the family code and
## name sit under each row.

const GENE_LIBRARY := "res://data/robots/gene_library.tres"
const ARCHETYPES: Array[String] = [
	"res://data/robots/archetypes/nibbler.tres",
	"res://data/robots/archetypes/clanker.tres",
	"res://data/robots/archetypes/thumper.tres",
]

@export var families: int = 4
@export var start_wave: int = 6
@export var run_seed: int = 1

var _camera: Camera3D
var _yaw: float = 0.0
var _lineup: Node3D


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.84, 0.88)
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.5
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	Clay.apply(ground, Color(0.42, 0.58, 0.3))
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_place_camera()
	reroll(run_seed)


func reroll(seed_value: int) -> void:
	if _lineup != null:
		_lineup.free()
	_lineup = Node3D.new()
	add_child(_lineup)
	RngService.start_run(seed_value)
	var library := load(GENE_LIBRARY) as GeneLibrary
	var curve := DifficultyCurve.new()
	var history: Array[RobotGenome] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for row in families:
		var genome := RobotGenome.roll(seed_value, start_wave + row, library, history, curve)
		history.append(genome)
		var z := -row * 4.5
		var x := -7.0
		for i in ARCHETYPES.size() + 1:
			var archetype := load(ARCHETYPES[mini(i, ARCHETYPES.size() - 1)]) as RobotArchetype
			var foreman := i == ARCHETYPES.size()
			var robot := archetype.scene.instantiate() as Robot
			var bonus: Array[RobotTrait] = []
			if foreman:
				bonus = library.pick_traits(rng, 1, genome.traits)
			robot.setup(archetype, genome.wave, curve, rng, genome, foreman, bonus)
			_lineup.add_child(robot)
			robot.process_mode = Node.PROCESS_MODE_DISABLED
			robot.position = Vector3(x, 0.0, z)
			robot.model.rotation.y = PI - deg_to_rad(20.0)  # face the camera
			x += 2.0 + RobotFactory.TYPE_SCALES[int(archetype.robot_type)] * 1.4
		var label := Label3D.new()
		label.text = "%s   %s   %s" % [genome.family_name, genome.family_code, ", ".join(genome.trait_names())]
		label.font_size = 64
		label.pixel_size = 0.006
		label.outline_size = 10
		label.position = Vector3(-8.0, 0.05, z + 1.4)
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_lineup.add_child(label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.physical_keycode:
		KEY_R:
			run_seed += 1
			reroll(run_seed)
		KEY_LEFT:
			_yaw -= 0.15
			_place_camera()
		KEY_RIGHT:
			_yaw += 0.15
			_place_camera()


func _place_camera() -> void:
	var center := Vector3(2.0, 1.0, -families * 2.2)
	_camera.position = center + Vector3(sin(_yaw) * 4.0, 7.5, 11.0 + cos(_yaw) * 4.0)
	_camera.look_at(center, Vector3.UP)
