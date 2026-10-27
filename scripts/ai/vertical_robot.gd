class_name VerticalRobot
extends Robot
## Two ranged enemies that make the farm's height matter. Lobbers walk to a building, climb its outer
## wall, and throw from the roof. Drones rise above the farm and circle the silo while firing.
## The shooting is a RangedAttack running the archetype's AttackProfile (M2-B7); who it shoots comes from
## the shared RobotTargeting: the farmer while it is after them and within range, otherwise the silo.

const ROOF_GROUP: StringName = &"roof_lobbers"
## Building paths relative to the farm's navigation region, independent of the scene wrapper.
const ROOF_SITES: Array[Dictionary] = [
	{"path": ^"ToolShed", "entry": Vector3(5.2, 0.0, 0.0), "wall": Vector3(4.55, 0.0, 0.0), "edge_y": 4.05, "top": Vector3(3.3, 4.05, 0.0)},
	{"path": ^"Barn", "entry": Vector3(10.4, 0.0, 0.0), "wall": Vector3(9.55, 0.0, 0.0), "edge_y": 9.15, "top": Vector3(0.0, 13.1, 0.0)},
	{"path": ^"Stables", "entry": Vector3(0.0, 0.0, 5.4), "wall": Vector3(0.0, 0.0, 4.55), "edge_y": 6.1, "top": Vector3(0.0, 6.1, 2.6)},
	{"path": ^"ChickenHouse", "entry": Vector3(-6.3, 0.0, 0.0), "wall": Vector3(-5.55, 0.0, 0.0), "edge_y": 3.6, "top": Vector3(-3.2, 3.6, 0.0)},
]

@export var aerial: bool = false
## Authored waves name the roof (a ROOF_SITES path such as ToolShed); otherwise it picks the nearest free one.
var forced_roof: StringName = &""
@export var climb_speed: float = 3.2
@export var flight_speed: float = 9.0
## Drones stop shooting this far out from the silo (flat distance).
@export var aerial_fire_radius: float = 36.0

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
var _muzzle: MeshInstance3D
var _rotor: Node3D
var ranged: RangedAttack


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
	_muzzle = make_muzzle(Vector3(0.0, 1.15, -0.55), Color(1.0, 0.45, 0.1) if aerial else Color(1.0, 0.84, 0.2))
	var profile := archetype.ranged_attack()
	if profile == null:
		push_warning("%s has no attack profile; using the drone's." % archetype.id)
		profile = load(AttackProfile.resource_path_for(&"drone_shot")) as AttackProfile
	ranged = make_ranged_attack(profile, _muzzle)
	if aerial:
		# Drones fire volleys late in a run (DifficultyCurve.volley_size, M2-B10).
		ranged.volley_override = volley_size


func _choose_roof() -> void:
	var region := _roof_navigation_region()
	var best_score := INF
	for i in ROOF_SITES.size():
		var site := ROOF_SITES[i]
		var building := region.get_node_or_null(site["path"] as NodePath) as Node3D if region != null else null
		if building == null:
			continue
		var entry := building.to_global(site["entry"] as Vector3)
		var score := global_position.distance_to(entry)
		for node in get_tree().get_nodes_in_group(ROOF_GROUP):
			if node != self and node is VerticalRobot and (node as VerticalRobot)._roof_index == i:
				score += 100.0
		if not forced_roof.is_empty():
			score += 0.0 if StringName(String(site["path"])) == forced_roof else 1000.0
		else:
			score -= _decoy_pull(building.to_global(site["top"] as Vector3))
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


## A Scarecrow Decoy on a roof draws Lobbers within its (elevated) lure radius to that roof instead.
func _decoy_pull(roof_top: Vector3) -> float:
	for node in get_tree().get_nodes_in_group(Defense.GROUP):
		var decoy := node as ScarecrowDecoy
		if decoy != null and decoy.active and decoy.site != null and decoy.site.kind == &"roof" \
				and decoy.global_position.distance_to(roof_top) < 4.0 \
				and decoy.global_position.distance_to(global_position) <= decoy.lure_radius() * 2.0:
			return 150.0
	return 0.0


## Main may be instanced below a smoke/test scene or another game root. Prefer the registered silo's
## farm, then the robot's ancestors and standalone current scene, rather than assuming current_scene is Main.
func _roof_navigation_region() -> Node3D:
	for origin: Node in [GameState.silo, self, get_tree().current_scene]:
		if not is_instance_valid(origin):
			continue
		var context := origin
		while context != null:
			for path: NodePath in [^"Farm/NavRegion", ^"NavRegion"]:
				var region := context.get_node_or_null(path) as Node3D
				if region != null:
					return region
			context = context.get_parent()
	return null


func _physics_process(delta: float) -> void:
	if ai_state == AiState.DEAD:
		return
	if global_position.y < -20.0:
		_die(null, false)
		return
	_hit_pop_left = maxf(0.0, _hit_pop_left - delta)
	if _process_launch(delta):
		ranged.cancel()
		return
	_update_targeting(delta)
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
		ranged.step(delta)
	else:
		ranged.cancel()


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if travel == Travel.APPROACH:
		super._on_velocity_computed(safe_velocity)


## Drones never touch a spring; a Lobber thrown off its perch lands, gets up and climbs again.
func launchable() -> bool:
	return not aerial and super.launchable()


func _on_landed_from_launch() -> void:
	travel = Travel.APPROACH
	_climb_stage = 0


## Back on the ground it walks to its wall and climbs again. If the throw only knocked it along the roof (a
## ridge perch), it walks back up to the top instead: there's no navmesh up there.
func _on_recovered_from_launch() -> void:
	super._on_recovered_from_launch()
	ai_state = AiState.SEEK
	var floor_y := GameState.silo.global_position.y if GameState.silo != null else 0.0
	if _roof_index >= 0 and global_position.y - floor_y > 1.5:
		travel = Travel.CLIMB
		collision_mask = 0
		_climb_stage = 2
		_climb_target = _roof_top
	else:
		travel = Travel.APPROACH


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


## What RangedAttack aims at next: the farmer while RobotTargeting is after them and they're within the
## profile's range, otherwise the silo. Drones hold fire beyond aerial_fire_radius.
func ranged_target() -> Node3D:
	if aerial:
		var flat := global_position - _silo_center()
		flat.y = 0.0
		if flat.length() > aerial_fire_radius:
			return null
	if target_kind == TargetKind.PLAYER and _is_living(target_player) \
			and target_player.global_position.distance_to(global_position) <= ranged.profile.attack_range:
		return target_player
	return GameState.silo


## A ranged robot can shoot a farmer on a roof or in the air.
func can_reach(_farmer: Node3D) -> bool:
	return true


func _on_tick_12(frame: int) -> void:
	super._on_tick_12(frame)
	if aerial and _rotor != null and ai_state != AiState.DEAD:
		_rotor.rotate_y(PI * 0.45)


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
