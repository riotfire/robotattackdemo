extends Node3D
## Robot look QA: turntables one family's archetypes in real scenes and writes contact sheets.
##   <out>/nibbler_families_N.png  the Nibbler across rolled families, front three-quarter
##   <out>/nibbler_close.png     one Nibbler's head and chest, close up
##   <out>/nibbler_turn.png      one Nibbler from four sides, in the source sculpt's palette if the family has it
##   <out>/lineup.png            every archetype of a few families, for scale and tells
##   <out>/heavy_close.png       a Thumper close up
##   <out>/pop_N.png             a Nibbler through a real kill, its parts in the air
## godot --path . --always-on-top --fixed-fps 60 --resolution 1600x900 res://tests/tools/robot_sheet.tscn -- --out=/tmp/robots

const GENE_LIBRARY := "res://data/robots/gene_library.tres"
const ARCHETYPES: Array[String] = ["nibbler", "spitter", "rung_runner", "roof_lobber", "drone", "clanker", "thumper"]

var _out: String = "/tmp/robot-sheet"
var _camera: Camera3D
var _library: GeneLibrary
var _curve: DifficultyCurve
var _lineup: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.84, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	Clay.apply(ground, Color(0.42, 0.58, 0.3))
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	_camera.make_current()
	_library = load(GENE_LIBRARY) as GeneLibrary
	_curve = DifficultyCurve.new()
	RngService.start_run(7)
	_run.call_deferred()


func _run() -> void:
	await _families()
	await _turn()
	await _sizes()
	await _pop()
	get_tree().quit()


func _spawn(archetype_id: String, genome: RobotGenome, at: Vector3, yaw: float, foreman: bool = false) -> Robot:
	var archetype := load("res://data/robots/archetypes/%s.tres" % archetype_id) as RobotArchetype
	var robot := archetype.scene.instantiate() as Robot
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	robot.setup(archetype, genome.wave, _curve, rng, genome, foreman)
	_lineup.add_child(robot)
	robot.process_mode = Node.PROCESS_MODE_DISABLED
	robot.position = at
	robot.model.rotation.y = yaw
	return robot


func _fresh() -> void:
	if _lineup != null:
		_lineup.free()
	_lineup = Node3D.new()
	add_child(_lineup)


func _shoot(file: String, center: Vector3, distance: float, height: float) -> void:
	_camera.position = center + Vector3(0.0, height, distance)
	_camera.look_at(center)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, file])


func _rolled(count: int, start: int) -> Array[RobotGenome]:
	var genomes: Array[RobotGenome] = []
	for i in count:
		var genome := RobotGenome.roll(7, start + i, _library, genomes, _curve)
		genomes.append(genome)
	return genomes


func _caption(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.005
	label.outline_size = 10
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_lineup.add_child(label)


func _families() -> void:
	var genomes := _rolled(15, 1)
	for page in 3:
		_fresh()
		for i in 5:
			var genome := genomes[page * 5 + i]
			genome.traits = []
			var at := Vector3((i - 2) * 1.8, 0.0, 0.0)
			_spawn("nibbler", genome, at, PI - deg_to_rad(20.0))
			_caption("%s\n%s %s %s %s" % [genome.family_name, genome.head, genome.eye_style, genome.antenna, genome.pattern], at + Vector3(0.0, 1.5, 0.0))
		await _shoot("nibbler_families_%d" % page, Vector3(0.0, 0.7, 0.0), 8.2, 1.0)


func _turn() -> void:
	_fresh()
	var genome := _classic()
	for i in 4:
		_spawn("nibbler", genome, Vector3((i - 1.5) * 1.5, 0.0, 0.0), PI + i * PI * 0.5 + 0.3)
	await _shoot("nibbler_turn", Vector3(0.0, 0.65, 0.0), 6.5, 0.9)
	_fresh()
	_spawn("nibbler", genome, Vector3.ZERO, PI - deg_to_rad(15.0))
	await _shoot("nibbler_close", Vector3(0.0, 0.72, 0.0), 2.6, 0.3)


func _pop() -> void:
	_fresh()
	var robot := _spawn("nibbler", _classic(), Vector3.ZERO, PI - deg_to_rad(15.0))
	robot.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().physics_frame
	robot.kill(true)
	for i in 4:
		await get_tree().create_timer(0.12, true, false, true).timeout
		await _shoot("pop_%d" % i, Vector3(0.0, 0.8, 0.0), 6.0, 0.6)


func _classic() -> RobotGenome:
	var genome := RobotGenome.from_code("CLASSC", 1, _library, _curve)
	genome.palette = RobotPalette.make("Classic", Color(0.92, 0.85, 0.72), Color(0.62, 0.17, 0.11), Color(0.72, 0.56, 0.28))
	genome.body_shape = &"egg"
	genome.head = &"dome"
	genome.eye_style = &"twin_goggles"
	genome.antenna = &"bulb"
	genome.melee_arm = &"claw"
	genome.pattern = &"none"
	genome.wear = &"fresh"
	genome.accessory = &""
	genome.traits = []
	genome.size = 1.0
	return genome


func _sizes() -> void:
	_fresh()
	var genomes := _rolled(3, 7)
	var z := 0.0
	for genome in genomes:
		var x := -9.0
		for id in ARCHETYPES:
			var archetype := load("res://data/robots/archetypes/%s.tres" % id) as RobotArchetype
			_spawn(id, genome, Vector3(x, 0.0, z), PI - deg_to_rad(20.0))
			x += 1.2 + RobotFactory.TYPE_SCALES[int(archetype.robot_type)] * 1.1
		z -= 4.5
	await _shoot("lineup", Vector3(0.0, 1.0, -4.5), 21.0, 7.0)
	_fresh()
	var family := genomes[2]
	print("heavy wear=%s pattern=%s traits=%s" % [family.wear, family.pattern, family.trait_names()])
	_spawn("thumper", family, Vector3.ZERO, PI - deg_to_rad(25.0))
	await _shoot("heavy_close", Vector3(0.0, 1.0, 0.0), 5.5, 0.6)
