class_name SpitterRobot
extends Robot
## The Spitter (M2-B9, GDD 9.3): a small ground robot with a pea-shooter, spawned as a share of small ground
## melee spawns from wave 7 (DifficultyCurve.spitter_share). It walks to a spot 12-16 m from its target,
## stands still while each pea charges (the moment to rush it), and hops to a new spot every
## shots_per_spot shots. Once in its life it backs off when a farmer gets within back_off_trigger.
## Peas aim at catwalk height, so they open high cracks. A trio fires a staggered 3-beat volley, and from
## wave 16 each attack is a volley (DifficultyCurve.volley_size).
## Who it shoots comes from RobotTargeting like any robot: the farmer while it is after them, else the silo.

enum Move { APPROACH, SHOOT, HOP, BACK_OFF }

## Stand-off distance from its target (the silo wall or the farmer), rolled per robot in this range.
@export var stand_min: float = 12.0
@export var stand_max: float = 16.0
@export var shots_per_spot: int = 3
## A hop moves it this far around its target.
@export var hop_angle_degrees: float = 35.0
@export var back_off_trigger: float = 5.0
@export var back_off_distance: float = 4.0
## A hop or back-off ends after this long even if it hasn't arrived.
@export var reposition_timeout: float = 3.0

var ranged: RangedAttack
var move: Move = Move.APPROACH
var stand_distance: float = 14.0
var backed_off: bool = false
var _spot: Vector3 = Vector3.ZERO
var _shots_here: int = 0
var _hop_sign: float = 1.0
var _move_time: float = 0.0
var _stagger_left: float = 0.0


func setup(robot_archetype: RobotArchetype, wave_number: int, curve: DifficultyCurve, rng: RandomNumberGenerator,
		family: RobotGenome = null, foreman: bool = false, bonus_traits: Array[RobotTrait] = [],
		robot_squad: RobotSquad = null, role: StringName = &"", foreman_hp: float = 0.0) -> void:
	super.setup(robot_archetype, wave_number, curve, rng, family, foreman, bonus_traits, robot_squad, role, foreman_hp)
	var own := RandomNumberGenerator.new()
	own.seed = rng.randi()
	stand_distance = own.randf_range(stand_min, stand_max)
	_hop_sign = 1.0 if own.randf() < 0.5 else -1.0


func _ready() -> void:
	super._ready()
	var profile := archetype.ranged_attack()
	if profile == null:
		push_warning("%s has no attack profile; using the pea." % archetype.id)
		profile = load(AttackProfile.resource_path_for(&"spitter_pea")) as AttackProfile
	var muzzle := make_muzzle((RobotFactory.ARM_WEAPON + Vector3(0.0, 0.0, -0.52)) * type_scale(), profile.color, 0.1)
	ranged = make_ranged_attack(profile, muzzle)
	ranged.fired.connect(_on_fired)
	if squad != null:
		ranged.volley_override = volley_size
		# A trio's peas come in a staggered 3-beat volley (GDD 9.6).
		_stagger_left = squad_index * profile.interval / 3.0


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
	if is_on_floor():
		_vertical_velocity = -1.0
	else:
		_vertical_velocity -= gravity * delta
	_update_targeting(delta)
	_check_back_off()

	var target := current_target()
	var desired := Vector3.ZERO
	match move:
		Move.APPROACH:
			if target != null and (target_distance(target) <= stand_distance + 0.5
					or (agent.is_navigation_finished() and target_distance(target) <= ranged.profile.attack_range)):
				move = Move.SHOOT
			elif target != null:
				desired = _navigate(delta, _stand_spot(target))
		Move.SHOOT:
			if target == null or target_distance(target) > ranged.profile.attack_range:
				_set_move(Move.APPROACH)
			else:
				_stagger_left = maxf(0.0, _stagger_left - delta)
				if ranged.state == RangedAttack.State.READY:
					_face(target.global_position)
		Move.HOP, Move.BACK_OFF:
			_move_time += delta
			var flat := Vector2(_spot.x - global_position.x, _spot.z - global_position.z)
			if flat.length() < 0.8 or _move_time >= reposition_timeout \
					or (_move_time > 0.3 and agent.is_navigation_finished()):
				_set_move(Move.SHOOT)
			else:
				desired = _navigate(delta, _spot)
	ranged.step(delta)
	agent.velocity = desired


## The farmer while RobotTargeting is after a living one, otherwise the silo.
func current_target() -> Node3D:
	if target_kind == TargetKind.PLAYER and _is_living(target_player):
		return target_player
	return GameState.silo


## How far it is from `target`: from the silo's wall, or from the farmer.
func target_distance(target: Node3D) -> float:
	if target is Silo:
		return (target as Silo).distance_to_wall(global_position)
	return global_position.distance_to(target.global_position)


## RangedAttack charges only while it stands at its spot, its trio beat has come, and the target is in range.
func ranged_target() -> Node3D:
	if move != Move.SHOOT or _stagger_left > 0.0:
		return null
	var target := current_target()
	if target == null or target_distance(target) > ranged.profile.attack_range:
		return null
	return target


## A Spitter can shoot a farmer up on a roof or in the air, so it never needs to give up on one.
func can_reach(_farmer: Node3D) -> bool:
	return true


func _set_move(next: Move) -> void:
	if next != Move.SHOOT and ranged.state == RangedAttack.State.CHARGING:
		ranged.cancel()
	move = next
	_move_time = 0.0
	_repath_timer = 0.0


## Where to stand: stand_distance from the target, on the side it is coming from.
func _stand_spot(target: Node3D) -> Vector3:
	var center := target.global_position
	var reach := stand_distance
	if target is Silo:
		var wall := (target as Silo).wall_point_toward(global_position, 0.0)
		reach += Vector2(wall.x - center.x, wall.z - center.z).length()
	var out := global_position - center
	out.y = 0.0
	if out.length_squared() < 0.01:
		out = Vector3.FORWARD
	return Vector3(center.x, global_position.y, center.z) + out.normalized() * reach


func _on_fired() -> void:
	_shots_here += 1
	if _shots_here < shots_per_spot or move != Move.SHOOT:
		return
	_shots_here = 0
	var target := current_target()
	if target == null:
		return
	# Hop around the target, alternating sides.
	var center := Vector3(target.global_position.x, global_position.y, target.global_position.z)
	var out := global_position - center
	_spot = center + out.rotated(Vector3.UP, deg_to_rad(hop_angle_degrees) * _hop_sign)
	_hop_sign = -_hop_sign
	_set_move(Move.HOP)


## Once in its life, a farmer within back_off_trigger makes it back off back_off_distance.
func _check_back_off() -> void:
	if backed_off or move == Move.BACK_OFF:
		return
	var farmer := GameState.get_nearest_player(global_position)
	if farmer == null or not _is_living(farmer):
		return
	var away := global_position - farmer.global_position
	away.y = 0.0
	if away.length() > back_off_trigger:
		return
	backed_off = true
	if away.length_squared() < 0.01:
		away = model.global_basis.z
		away.y = 0.0
	_spot = global_position + away.normalized() * back_off_distance
	_set_move(Move.BACK_OFF)
