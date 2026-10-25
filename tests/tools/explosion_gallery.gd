extends Node3D
## Explosion gallery: a Nibbler, a Clanker, a Thumper and a Foreman Clanker stand on a lawn and pop one
## after another, then a grenade lands among a fresh row, then one shot sets off a snaking pack of
## Overcharged robots (GDD 10.3) to show the chain reaction. Tunes RobotExplosion and the death blast. The
## camera is a real FarmerCamera rig, so screen shake and freeze frames show too.
## Run the scene (F6 in the editor). Space pops the next robot; G throws a grenade; R refills the row;
## C lines up an Overcharged pack (Space sets it off).
## To review frame by frame, record it: godot --path . --write-movie /tmp/boom/frame.png
## --fixed-fps 30 --quit-after 500 res://tests/tools/explosion_gallery.tscn

const ARCHETYPES: Array[String] = [
	"res://data/robots/archetypes/nibbler.tres",
	"res://data/robots/archetypes/clanker.tres",
	"res://data/robots/archetypes/thumper.tres",
	"res://data/robots/archetypes/clanker.tres",
]
const SPACING := 3.2
const OVERCHARGED := "res://data/robots/traits/overcharged.tres"
## The Overcharged pack, left to right: a wobbly line of Nibblers (any blast kills one), two Nibblers
## flanking the first Clanker (it takes two Nibbler blasts), a Clanker squad (each Clanker's blast kills the
## next), and a Thumper that only gets dented, so the gallery finishes it off.
const CHAIN_PACK: Array[Array] = [
	[0, Vector3(-10.0, 0.0, -1.0)], [0, Vector3(-8.2, 0.0, -0.3)], [0, Vector3(-6.4, 0.0, -1.3)],
	[0, Vector3(-4.6, 0.0, -0.4)], [0, Vector3(-2.8, 0.0, -1.5)], [0, Vector3(-1.0, 0.0, -1.0)],
	[0, Vector3(0.5, 0.0, -1.9)], [0, Vector3(0.5, 0.0, -0.1)],
	[1, Vector3(1.4, 0.0, -1.0)], [1, Vector3(2.9, 0.0, -1.0)], [1, Vector3(4.4, 0.0, -1.0)],
	[2, Vector3(7.4, 0.0, -1.0)],
]
## Seconds between automatic pops (0 = only on Space).
@export var auto_interval: float = 1.6

var _robots: Array[Robot] = []
var _rig: FarmerCamera
var _timer: float = 0.8
var _round: int = 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.82, 0.9)
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	lawn.mesh = plane
	Clay.apply(lawn, Color(0.42, 0.58, 0.3))
	ground.add_child(lawn)
	add_child(ground)
	var farmer := (load("res://scenes/player/farmer.tscn") as PackedScene).instantiate()
	_rig = farmer.get_node(^"CameraRig").duplicate() as FarmerCamera
	farmer.free()
	add_child(_rig)
	_rig.global_position = Vector3(0.0, 2.4, 7.0)
	_rig.camera.rotation_degrees.x = -12.0
	_rig.camera.current = true
	RngService.start_run(5)
	_refill()


func _process(delta: float) -> void:
	# The rig only shakes itself when it follows a farmer, so drive the shake here.
	_rig.call(&"_update_shake", delta / maxf(Engine.time_scale, 0.01))
	if auto_interval <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = auto_interval
		if _round == 0 and _robots.any(func(r: Variant) -> bool: return is_instance_valid(r)):
			_pop_next()
		elif _round == 0:
			_round = 1
			_refill()
			_timer = 0.6
		elif _round == 1:
			_round = 2
			_grenade()
			_timer = 2.5
		elif _round == 2:
			_round = 3
			_chain_pack()
			_timer = 0.8
		elif _round == 3:
			_round = 4
			_pop_next()
			_timer = 4.0
		elif _round == 4:
			_round = 5
			_pop_next()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_pop_next()
			KEY_G:
				_grenade()
			KEY_R:
				_refill()
			KEY_C:
				_chain_pack()


func _refill() -> void:
	for robot in _robots:
		if is_instance_valid(robot):
			robot.queue_free()
	_robots.clear()
	var library := load("res://data/robots/gene_library.tres") as GeneLibrary
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + _round
	var genome := RobotGenome.roll(11 + _round, 6, library, [], DifficultyCurve.new())
	for i in ARCHETYPES.size():
		var archetype := load(ARCHETYPES[i]) as RobotArchetype
		var robot := archetype.scene.instantiate() as Robot
		robot.setup(archetype, 6, DifficultyCurve.new(), rng, genome, i == 3)
		add_child(robot)
		robot.agent.avoidance_enabled = false
		robot.ai_state = Robot.AiState.RECOVER
		robot.set(&"_attack_timer", 99999.0)
		robot.global_position = Vector3((i - 1.5) * SPACING, 0.0, 0.0)
		robot.rotation.y = PI
		_robots.append(robot)


func _chain_pack() -> void:
	for robot in _robots:
		if is_instance_valid(robot):
			robot.queue_free()
	_robots.clear()
	var library := load("res://data/robots/gene_library.tres") as GeneLibrary
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var genome := RobotGenome.roll(23, 6, library, [], DifficultyCurve.new())
	var traits: Array[RobotTrait] = [load(OVERCHARGED) as RobotTrait]
	for link in CHAIN_PACK:
		var archetype := load(ARCHETYPES[link[0]]) as RobotArchetype
		var robot := archetype.scene.instantiate() as Robot
		robot.setup(archetype, 6, DifficultyCurve.new(), rng, genome, false, traits)
		add_child(robot)
		robot.agent.avoidance_enabled = false
		robot.ai_state = Robot.AiState.RECOVER
		robot.set(&"_attack_timer", 99999.0)
		robot.global_position = link[1]
		robot.rotation.y = PI
		_robots.append(robot)


func _pop_next() -> void:
	for robot in _robots:
		if is_instance_valid(robot) and robot.ai_state != Robot.AiState.DEAD:
			var from := robot.global_position + Vector3(-2.0, 0.5, 3.0)
			robot.take_damage(DamagePacket.create(999999.0, null, from))
			return


func _grenade() -> void:
	var at := Vector3(0.0, 0.2, 0.0)
	RobotExplosion.blast(self, at, 5.0)
	AreaAttack.hit_robots(self, at, 5.0, 999999.0, null, 8.0, null)
