class_name TutorialDummy
extends StaticBody3D
## Grandpa's spring-loaded practice Dummy-Bot for Level 0 (GDD "Morning Chores"). It pops up on a hay bale with
## the BOLT Co. cog on its chest and glowing red eyes, and teaches by reacting to the 3-hit wrench combo
## (the eyes are a x2 weak point for the pistol). It pops into a puff
## of Aluminium, and its coiled spring snaps out and bonks the farmer for 20 so the Porch has something to fix.
## Not a Robot: no AI, no navigation, no wave bookkeeping.

signal destroyed(dummy: TutorialDummy)
signal bonked(farmer: Farmer)

const MAX_HEALTH: float = 75.0
const BONK_DAMAGE: float = 20.0
const BONK_DELAY: float = 0.32

const HURTBOX_LAYER: int = 1 << 4

var health: HealthComponent
## Aluminium dropped on the pop.
var drop_al: int = 20

var _body: Node3D
var _spring: Node3D
var _glove: Node3D
var _eyes: Array[MeshInstance3D] = []
var _target: Farmer
var _wobble: Tween
var _dead: bool = false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = MAX_HEALTH
	add_child(health)
	_build_hay()
	_build_robot()
	_build_hurtboxes()
	_pop_up()


func _build_hay() -> void:
	var hay := Color(0.9, 0.78, 0.4)
	for offset in [Vector3(-0.65, 0.45, 0.0), Vector3(0.65, 0.45, 0.0)]:
		var bale := BoxMesh.new()
		bale.size = Vector3(1.28, 0.9, 1.0)
		Clay.part(self, bale, hay.darkened(randf_range(0.0, 0.1)), Transform3D(Basis(), offset))
		var band := BoxMesh.new()
		band.size = Vector3(0.07, 0.92, 1.04)
		for x: float in [-0.3, 0.3]:
			Clay.part(self, band, Color(0.62, 0.48, 0.25), Transform3D(Basis(), offset + Vector3(x, 0.0, 0.0)))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.28, 0.9, 1.0)
		shape.shape = box
		shape.position = offset
		add_child(shape)


func _build_robot() -> void:
	_body = Node3D.new()
	_body.name = "Robot"
	_body.position = Vector3(0.0, 0.9, 0.0)
	add_child(_body)
	var steel := Color(0.56, 0.6, 0.66)
	var orange := Color(0.95, 0.55, 0.15)
	# The coil spring it stands on.
	_spring = Node3D.new()
	_spring.name = "Spring"
	_body.add_child(_spring)
	for i in 4:
		var coil := TorusMesh.new()
		coil.inner_radius = 0.2
		coil.outer_radius = 0.32
		coil.ring_segments = 6
		coil.rings = 14
		Clay.part(_spring, coil, Color(0.78, 0.8, 0.85), Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0.0, 0.06 + i * 0.1, 0.0)))
	var torso := BoxMesh.new()
	torso.size = Vector3(0.95, 0.9, 0.6)
	Clay.part(_body, torso, steel, Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)))
	var head := BoxMesh.new()
	head.size = Vector3(0.7, 0.55, 0.55)
	Clay.part(_body, head, steel.lightened(0.12), Transform3D(Basis(), Vector3(0.0, 1.55, 0.0)))
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.03
	antenna.bottom_radius = 0.03
	antenna.height = 0.35
	Clay.part(_body, antenna, steel.darkened(0.3), Transform3D(Basis(), Vector3(0.0, 1.97, 0.0)))
	# The BOLT Co. cog on the chest (readability lock: this is a robot).
	var cog_root := Node3D.new()
	cog_root.position = Vector3(0.0, 0.85, 0.33)
	cog_root.rotation.x = PI * 0.5
	_body.add_child(cog_root)
	var cog := CylinderMesh.new()
	cog.top_radius = 0.24
	cog.bottom_radius = 0.24
	cog.height = 0.07
	Clay.part(cog_root, cog, orange, Transform3D())
	for i in 8:
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.1, 0.07, 0.13)
		var angle := TAU * i / 8.0
		Clay.part(cog_root, tooth, orange, Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle), 0.0, cos(angle)) * 0.27))
	# Red eyes: glowing, the weak points.
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(1.0, 0.15, 0.1)
	eye_material.emission_enabled = true
	eye_material.emission = Color(1.0, 0.1, 0.05)
	eye_material.emission_energy_multiplier = 2.0
	for x: float in [-0.17, 0.17]:
		var eye := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.1
		ball.height = 0.2
		eye.mesh = ball
		eye.material_override = eye_material
		eye.position = Vector3(x, 1.55, 0.28)
		_body.add_child(eye)
		_eyes.append(eye)
	# The boxing-glove spring that bonks the farmer: tucked inside the chest until the dummy pops.
	_glove = Node3D.new()
	_glove.name = "Glove"
	_glove.position = Vector3(0.0, 0.85, 0.0)
	_glove.scale = Vector3.ONE * 0.01
	_body.add_child(_glove)
	for i in 6:
		var coil := TorusMesh.new()
		coil.inner_radius = 0.1
		coil.outer_radius = 0.17
		Clay.part(_glove, coil, Color(0.78, 0.8, 0.85), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.2), Vector3(0.0, 0.0, 0.1 + i * 0.1)))
	var fist := SphereMesh.new()
	fist.radius = 0.3
	fist.height = 0.6
	Clay.part(_glove, fist, Color(0.9, 0.2, 0.15), Transform3D(Basis(), Vector3(0.0, 0.0, 0.85)))


func _build_hurtboxes() -> void:
	# Body and head; the eyes are a separate x2 weak point (GDD 6.1).
	_hurtbox(_body.position + Vector3(0.0, 1.0, 0.0), Vector3(1.1, 2.0, 0.8), false)
	_hurtbox(_body.position + Vector3(0.0, 1.55, 0.3), Vector3(0.5, 0.25, 0.3), true)


func _hurtbox(at: Vector3, size: Vector3, weak: bool) -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.collision_layer = HURTBOX_LAYER
	hurtbox.collision_mask = 0
	hurtbox.is_weak_point = weak
	hurtbox.damage_multiplier = 2.0 if weak else 1.0
	hurtbox.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	hurtbox.add_child(shape)
	add_child(hurtbox)
	hurtbox.owner = self


## Springs up from lying flat on the bale, with a clay overshoot.
func _pop_up() -> void:
	_body.scale = Vector3(1.4, 0.05, 1.4)
	var tween := create_tween()
	tween.tween_property(_body, ^"scale", Vector3(0.85, 1.25, 0.85), 0.14)
	tween.tween_property(_body, ^"scale", Vector3(1.08, 0.92, 1.08), 0.1)
	tween.tween_property(_body, ^"scale", Vector3.ONE, 0.1)


## The wrench or pistol landed.
func take_damage(packet: DamagePacket) -> void:
	if _dead:
		return
	if packet.source is Farmer:
		_target = packet.source as Farmer
	health.apply_damage(packet.amount)
	if health.is_dead():
		_die()
		return
	_wobble_from(packet)


func _wobble_from(packet: DamagePacket) -> void:
	if _wobble != null:
		_wobble.kill()
	var away := (global_position - packet.position)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var lean := Vector3(away.z, 0.0, -away.x) * 0.35
	_wobble = create_tween()
	_wobble.tween_property(_body, ^"rotation", lean, 0.05)
	_wobble.tween_property(_body, ^"rotation", -lean * 0.6, 0.09)
	_wobble.tween_property(_body, ^"rotation", lean * 0.25, 0.09)
	_wobble.tween_property(_body, ^"rotation", Vector3.ZERO, 0.1)
	_spring.scale = Vector3(1.2, 0.7, 1.2)
	create_tween().tween_property(_spring, ^"scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Fx.puff(self, global_position + Vector3(0.0, 2.0, 0.0), Color(1.0, 0.9, 0.5), 0.18, 0.15)


func _die() -> void:
	_dead = true
	for hurtbox in find_children("*", "Hurtbox", false, false):
		(hurtbox as Hurtbox).set_deferred(&"collision_layer", 0)
	for eye in _eyes:
		eye.material_override = null
	var burst := global_position + Vector3(0.0, 2.2, 0.0)
	Fx.puff(self, burst, Color(0.97, 0.97, 0.95), 0.7, 0.4)
	Fx.puff(self, burst + Vector3(0.3, -0.2, 0.2), Color(1.0, 0.95, 0.8), 0.45, 0.35)
	var known := get_tree().get_nodes_in_group(Pickup.GROUP)
	Pickup.spawn_parts(self, burst, {&"al": drop_al})
	var drops: Array[Pickup] = []
	for node in get_tree().get_nodes_in_group(Pickup.GROUP):
		if node not in known:
			drops.append(node as Pickup)
	# The bits scatter, then fly to Pip, so a new player can't miss their first parts.
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		var farmer := _target if _target != null and is_instance_valid(_target) else GameState.get_nearest_player(global_position)
		for drop in drops:
			if is_instance_valid(drop) and farmer != null:
				drop.attract_to(farmer))
	AudioDirector.play_cue(&"robot_pop")
	destroyed.emit(self)
	get_tree().create_timer(BONK_DELAY).timeout.connect(_bonk)


## The loose spring snaps out and bonks whoever is nearest.
func _bonk() -> void:
	if not is_inside_tree():
		return
	var farmer := _target if _target != null and is_instance_valid(_target) else GameState.get_nearest_player(global_position) as Farmer
	if farmer != null:
		var aim := farmer.global_position + Vector3.UP * 1.0 - _glove.global_position
		var flat := Vector2(aim.x, aim.z)
		_body.rotation.y = atan2(aim.x, aim.z)
		var reach := clampf(aim.length(), 1.0, 3.2)
		_glove.scale = Vector3.ONE
		var tween := create_tween()
		tween.tween_property(_glove, ^"scale", Vector3(1.0, 1.0, reach / 1.15), 0.07)
		tween.tween_callback(func() -> void:
			var packet := DamagePacket.create(BONK_DAMAGE, self, global_position)
			var push := Vector3(flat.x, 0.0, flat.y).normalized() * 7.0 + Vector3.UP * 3.0
			packet.knockback = push
			farmer.take_damage(packet)
			Fx.puff(self, farmer.global_position + Vector3.UP, Color(1.0, 0.85, 0.3), 0.5, 0.2)
			AudioDirector.play_cue(&"wrench")
			bonked.emit(farmer))
		tween.tween_interval(0.35)
		tween.tween_property(_glove, ^"scale", Vector3(1.0, 1.0, 0.01), 0.3).set_trans(Tween.TRANS_ELASTIC)
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	var fall := create_tween()
	fall.tween_property(_body, ^"scale", Vector3(1.4, 0.05, 1.4), 0.25)
	fall.tween_callback(func() -> void: _body.visible = false)
