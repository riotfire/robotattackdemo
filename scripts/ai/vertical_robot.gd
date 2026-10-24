class_name VerticalRobot
extends Robot
## Two ranged enemies that make the farm's height matter. Lobbers walk to a building, climb its outer
## wall, and throw from the roof. Drones rise above the farm and circle the silo while firing.

const PROJECTILE_MASK: int = 1 | 2
const ROOF_GROUP: StringName = &"roof_lobbers"
const ROOF_SITES: Array[Dictionary] = [
	{"path": ^"Farm/NavRegion/ToolShed", "entry": Vector3(5.2, 0.0, 0.0), "wall": Vector3(4.55, 0.0, 0.0), "edge_y": 4.05, "top": Vector3(3.3, 4.05, 0.0)},
	{"path": ^"Farm/NavRegion/Barn", "entry": Vector3(10.4, 0.0, 0.0), "wall": Vector3(9.55, 0.0, 0.0), "edge_y": 9.15, "top": Vector3(0.0, 13.1, 0.0)},
	{"path": ^"Farm/NavRegion/Stables", "entry": Vector3(0.0, 0.0, 5.4), "wall": Vector3(0.0, 0.0, 4.55), "edge_y": 6.1, "top": Vector3(0.0, 6.1, 2.6)},
	{"path": ^"Farm/NavRegion/ChickenHouse", "entry": Vector3(-6.3, 0.0, 0.0), "wall": Vector3(-5.55, 0.0, 0.0), "edge_y": 3.6, "top": Vector3(-3.2, 3.6, 0.0)},
]

@export var aerial: bool = false
@export var climb_speed: float = 3.2
@export var flight_speed: float = 9.0
@export var projectile_speed: float = 20.0
@export var projectile_gravity: float = 6.0
@export var player_priority_range: float = 24.0

enum Travel { APPROACH, CLIMB, PERCHED, FLYING }

var travel: Travel = Travel.APPROACH
var _roof_index: int = -1
var _entry: Vector3
var _wall_foot: Vector3
var _roof_edge: Vector3
var _roof_top: Vector3
var _climb_target: Vector3
var _climb_stage: int = 0
var _orbit_angle: float = 0.0
var _shot_target: Node3D
var _muzzle: MeshInstance3D
var _rotor: Node3D


func _ready() -> void:
	super._ready()
	agent.avoidance_enabled = not aerial
	if aerial:
		travel = Travel.FLYING
		collision_mask = 0
		floor_snap_length = 0.0
		var body_hit_shape := $BodyHurtbox/Shape as CollisionShape3D
		var wide_shape := body_hit_shape.shape.duplicate() as CapsuleShape3D
		wide_shape.radius = 0.7
		wide_shape.height = 1.3
		body_hit_shape.shape = wide_shape
		body_hit_shape.position.y = 0.65
		for wheel in look.wheels:
			wheel.visible = false
		var offset := global_position - _silo_center()
		_orbit_angle = atan2(offset.z, offset.x)
	else:
		add_to_group(ROOF_GROUP)
		_choose_roof()
	_make_silhouette()
	_make_muzzle()


func _choose_roof() -> void:
	var scene := get_tree().current_scene
	var best_score := INF
	for i in ROOF_SITES.size():
		var site := ROOF_SITES[i]
		var building := scene.get_node_or_null(site["path"] as NodePath) as Node3D
		if building == null:
			continue
		var entry := building.to_global(site["entry"] as Vector3)
		var score := global_position.distance_to(entry)
		for node in get_tree().get_nodes_in_group(ROOF_GROUP):
			if node != self and node is VerticalRobot and (node as VerticalRobot)._roof_index == i:
				score += 100.0
		if score < best_score:
			best_score = score
			_roof_index = i
			_entry = entry
			_wall_foot = building.to_global(site["wall"] as Vector3)
			_roof_edge = _wall_foot + Vector3.UP * float(site["edge_y"])
			_roof_top = building.to_global(site["top"] as Vector3)
	if _roof_index < 0:
		push_warning("Roof lobber found no farm roofs; falling back to ground combat.")
		travel = Travel.PERCHED
		_roof_top = global_position


func _physics_process(delta: float) -> void:
	if ai_state == AiState.DEAD:
		return
	if global_position.y < -20.0:
		_die(null, false)
		return
	_hit_pop_left = maxf(0.0, _hit_pop_left - delta)
	match travel:
		Travel.APPROACH:
			if Vector2(global_position.x - _entry.x, global_position.z - _entry.z).length() <= 2.0:
				_begin_climb()
			else:
				if is_on_floor():
					_vertical_velocity = -1.0
				else:
					_vertical_velocity -= gravity * delta
				agent.velocity = _navigate(delta, _entry)
		Travel.CLIMB:
			global_position = global_position.move_toward(_climb_target, climb_speed * delta)
			_face(_roof_top)
			if global_position.distance_to(_climb_target) < 0.05:
				_climb_stage += 1
				match _climb_stage:
					1: _climb_target = _roof_edge
					2: _climb_target = _roof_top
					_:
						travel = Travel.PERCHED
						ai_state = AiState.SEEK
		Travel.FLYING:
			_fly(delta)
		Travel.PERCHED:
			pass
	if travel in [Travel.PERCHED, Travel.FLYING]:
		_attack_step(delta)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if travel == Travel.APPROACH:
		super._on_velocity_computed(safe_velocity)


func _begin_climb() -> void:
	travel = Travel.CLIMB
	ai_state = AiState.SEEK
	agent.velocity = Vector3.ZERO
	collision_mask = 0
	# Reach the wall, scale it, then move inward onto the roof. Hurtboxes stay shootable.
	_climb_stage = 0
	_climb_target = _wall_foot
	Fx.puff(self, global_position + Vector3.UP, Color(1.0, 0.72, 0.2), 0.45, 0.3)


func _fly(delta: float) -> void:
	var center := _silo_center()
	var target: Vector3
	if global_position.y < 13.5:
		target = Vector3(global_position.x, 14.0, global_position.z)
	else:
		_orbit_angle += delta * 0.22
		target = center + Vector3(cos(_orbit_angle) * 22.0, 14.0, sin(_orbit_angle) * 22.0)
	var before := global_position
	global_position = global_position.move_toward(target, flight_speed * speed_multiplier * delta)
	velocity = (global_position - before) / maxf(delta, 0.001)
	_face(center)


func _attack_step(delta: float) -> void:
	match ai_state:
		AiState.SEEK:
			_shot_target = _pick_target()
			if _shot_target != null:
				ai_state = AiState.WINDUP
				_attack_timer = archetype.attack_windup
				_muzzle.visible = true
		AiState.WINDUP:
			if _shot_target == null or not is_instance_valid(_shot_target):
				ai_state = AiState.SEEK
				_muzzle.visible = false
				return
			_face(_shot_target.global_position)
			_attack_timer -= delta
			_muzzle.scale = Vector3.ONE * (0.5 + 0.5 * (1.0 - maxf(0.0, _attack_timer) / archetype.attack_windup))
			if _attack_timer <= 0.0:
				_throw_projectile()
				_muzzle.visible = false
				ai_state = AiState.RECOVER
				_attack_timer = maxf(0.0, archetype.attack_interval - archetype.attack_windup)
		AiState.RECOVER:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				ai_state = AiState.SEEK


func _pick_target() -> Node3D:
	if aerial:
		var flat := global_position - _silo_center()
		flat.y = 0.0
		if flat.length() > 36.0:
			return null
	var player := GameState.get_nearest_player(global_position)
	if player != null and player.global_position.distance_to(global_position) <= player_priority_range:
		return player
	return GameState.silo


func _throw_projectile() -> void:
	if _shot_target == null or not is_instance_valid(_shot_target):
		return
	var from := _muzzle.global_position
	var target := _shot_target.global_position + Vector3.UP * (1.0 if _shot_target is Farmer else 8.0)
	var delta := target - from
	var horizontal := Vector2(delta.x, delta.z).length()
	var flight_time := maxf(0.35, horizontal / projectile_speed)
	var launch_velocity := delta / flight_time
	var pull := 0.0 if aerial else projectile_gravity
	launch_velocity.y += 0.5 * pull * flight_time
	var color := Color(1.0, 0.45, 0.1) if aerial else Color(1.0, 0.84, 0.2)
	var exclude: Array[RID] = [get_rid()]
	ProjectilePool.of(self).launch(from, launch_velocity, pull, flight_time + 1.0, PROJECTILE_MASK,
		exclude, _on_projectile_hit, color, 0.2 if aerial else 0.26)
	Fx.puff(self, from, color, 0.3, 0.2)


func _on_projectile_hit(hit: Dictionary) -> bool:
	var collider := hit["collider"] as Node
	var at: Vector3 = hit["position"]
	if collider is Farmer:
		(collider as Farmer).take_damage(DamagePacket.create(archetype.damage_vs_farmer * damage_multiplier, self, at))
	elif collider is Silo:
		(collider as Silo).take_damage(DamagePacket.create(archetype.damage_vs_silo * damage_multiplier, self, at))
	Fx.puff(self, at, Color(1.0, 0.65, 0.2), 0.35, 0.2)
	return false


func _on_tick_12(frame: int) -> void:
	super._on_tick_12(frame)
	if aerial and _rotor != null and ai_state != AiState.DEAD:
		_rotor.rotate_y(PI * 0.45)


func _make_muzzle() -> void:
	_muzzle = MeshInstance3D.new()
	_muzzle.name = "ChargingProjectile"
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	_muzzle.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.45, 0.1) if aerial else Color(1.0, 0.84, 0.2)
	_muzzle.material_override = material
	model.add_child(_muzzle)
	_muzzle.position = Vector3(0.0, 1.15, -0.55)
	_muzzle.visible = false


func _make_silhouette() -> void:
	var part := MeshInstance3D.new()
	part.name = "Rotor" if aerial else "ThrowerPack"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.72, 0.95) if aerial else Color(0.95, 0.58, 0.14)
	part.material_override = material
	if aerial:
		var rotor := CylinderMesh.new()
		rotor.top_radius = 0.65
		rotor.bottom_radius = 0.65
		rotor.height = 0.09
		part.mesh = rotor
		part.position = Vector3(0.0, 1.22, 0.0)
		_rotor = part
	else:
		var pack := BoxMesh.new()
		pack.size = Vector3(0.65, 0.45, 0.35)
		part.mesh = pack
		part.position = Vector3(0.0, 0.58, 0.42)
	model.add_child(part)
