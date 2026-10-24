class_name Robot
extends CharacterBody3D
## Shared robot health, damage, drops and appearance. This AI drives the ground melee robots: Nibbler,
## Clanker squads and Thumper. VerticalRobot supplies the roof and flying ranged behaviors.
##
## Melee AI (GDD 9.6): walk the navmesh to the silo (70%) or the nearest farmer (30%), bash it, and switch
## to the farmer when hurt from within aggro range. Nibblers (and any melee robot in a Thieving family) may
## instead grab a 20-bushel grain sack at the chute and run for the corn (GDD 3.3).
## The look is kit-bashed by RobotFactory from the wave's RobotGenome. Poses step at 12 fps (GDD 15.4).
## This state machine is replaced by LimboAI behavior trees later (GDD 18.4).

signal destroyed(robot: Robot, killer: Node)

enum AiState { SEEK, WINDUP, RECOVER, STEALING, FLEEING, DEAD }
enum TargetKind { SILO, PLAYER, CHUTE }

const GROUP: StringName = &"robots"
const THIEF_GROUP: StringName = &"thieves"
const SACK_SIZE: float = 20.0
const FOREMAN_HP_MULTIPLIER: float = 3.0
## Foreman drops are fixed (GDD 12.2).
const FOREMAN_DROPS: Dictionary[StringName, int] = {&"al": 10, &"cu": 6, &"au": 2, &"pc": 3}
## Distance from the silo at which a fleeing thief is gone into the corn.
const ESCAPE_RADIUS: float = 102.0
const GENE_LIBRARY_PATH := "res://data/robots/gene_library.tres"

## Every antenna bulb in the wave blinks together (Factory DNA). The WaveDirector shortens the period
## (in 12 fps frames) when the wave is almost over.
static var hive_period: int = 12

@export var gravity: float = 22.0

var archetype: RobotArchetype
var genome: RobotGenome
## The wave family this robot belongs to (GDD 10.2), for the Almanac.
var family_code: String = ""
var wave: int = 1
var is_foreman: bool = false
var foreman_title: String = ""
## Traits on top of the family's (the Foreman's bonus trait).
var extra_traits: Array[RobotTrait] = []
var squad: RobotSquad = null
var squad_index: int = 0
var is_thief: bool = false
var sack_amount: float = 0.0
var hp_multiplier: float = 1.0
var damage_multiplier: float = 1.0
var drop_multiplier: float = 1.0
var speed_multiplier: float = 1.0
var target_kind: TargetKind = TargetKind.SILO
var target_player: Node3D = null
var ai_state: AiState = AiState.SEEK
var look: RobotFactory.Look

var _attack_timer: float = 0.0
var _first_attack: bool = true
var _repath_timer: float = 0.0
var _unreachable_time: float = 0.0
var _steal_timer: float = 0.0
var _escape_point: Vector3 = Vector3.ZERO
var _vertical_velocity: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _last_attacker: Node = null
var _pose_frame: int = 0
var _hit_pop_left: float = 0.0
var _marker: Label3D = null

@onready var health: HealthComponent = $Health
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model
@onready var _pose: Node3D = $Model/Pose


## Call before adding to the tree. `rng` is the wave's spawn stream, so targeting is deterministic.
func setup(robot_archetype: RobotArchetype, wave_number: int, curve: DifficultyCurve, rng: RandomNumberGenerator,
		family: RobotGenome = null, foreman: bool = false, bonus_traits: Array[RobotTrait] = [],
		robot_squad: RobotSquad = null) -> void:
	archetype = robot_archetype
	wave = wave_number
	genome = family
	family_code = family.family_code if family != null else ""
	is_foreman = foreman
	extra_traits = bonus_traits
	hp_multiplier = curve.hp_multiplier(wave) * (FOREMAN_HP_MULTIPLIER if foreman else 1.0)
	damage_multiplier = curve.damage_multiplier(wave)
	drop_multiplier = curve.drop_multiplier(wave)
	for robot_trait in all_traits():
		hp_multiplier *= robot_trait.hp_multiplier
		speed_multiplier *= robot_trait.speed_multiplier
	if foreman and family != null:
		foreman_title = family.foreman_title(rng)

	var roll := rng.randf()
	var steal_chance := archetype.steal_chance
	# Scouts steal at the curve's per-wave thief share; a Thieving family raises it (GDD 11.7, ROADMAP D4).
	# Squads never steal, so Grunt formations stay readable.
	if archetype.robot_class == RobotArchetype.RobotClass.MELEE \
			and archetype.robot_type == RobotArchetype.RobotType.SCOUT:
		var thieving := all_traits().any(func(t: RobotTrait) -> bool: return t.thieving)
		steal_chance = curve.thief_chance(wave, archetype.farmer_target_chance, thieving)
	if roll < archetype.farmer_target_chance:
		target_kind = TargetKind.PLAYER
	elif not foreman and robot_squad == null and rng.randf() < steal_chance:
		target_kind = TargetKind.CHUTE
		is_thief = true
	else:
		target_kind = TargetKind.SILO
	if robot_squad != null:
		squad = robot_squad
		squad_index = squad.join(self)
		if squad_index > 0:
			target_kind = squad.leader().target_kind
	_repath_timer = rng.randf() * 0.25


func _ready() -> void:
	add_to_group(GROUP)
	if is_thief:
		add_to_group(THIEF_GROUP)
	if archetype == null:
		push_warning("Robot spawned without an archetype; call setup() before adding it.")
		archetype = RobotArchetype.new()
	if genome == null:
		genome = RobotGenome.from_code("BOLTCO", wave, load(GENE_LIBRARY_PATH) as GeneLibrary, DifficultyCurve.new())
		family_code = genome.family_code
	health.reset(archetype.base_hp * hp_multiplier)
	health.died.connect(_on_died)
	agent.max_speed = move_speed()
	agent.velocity_computed.connect(_on_velocity_computed)
	# Always slide along walls. Robots are wider than the navmesh's 0.5 m clearance and turn for the next
	# waypoint about 1 m before a corner, so they clip building corners a few degrees off head-on; below the
	# default 15° move_and_slide() stops them dead there (tests/unit/test_robot_movement.gd).
	wall_min_slide_angle = 0.0
	look = RobotFactory.build(_pose, genome, archetype, RngService.stream(RngService.STREAM_COSMETIC), is_foreman, extra_traits)
	if is_foreman:
		_set_marker(foreman_title, Color(1.0, 0.82, 0.3), false, 1.0)
	elif is_thief:
		_set_marker("$", Color(1.0, 0.85, 0.3), StatService.has_flag(&"grain.sack_tracker"), 0.6)
	StopMotionClock.tick_12.connect(_on_tick_12)
	EventBus.robot_spawned.emit(self)


func all_traits() -> Array[RobotTrait]:
	var traits: Array[RobotTrait] = []
	if genome != null:
		traits.append_array(genome.traits)
	traits.append_array(extra_traits)
	return traits


func has_trait(id: StringName) -> bool:
	for robot_trait in all_traits():
		if robot_trait.id == id:
			return true
	return false


func move_speed() -> float:
	return archetype.move_speed * speed_multiplier


func type_scale() -> float:
	return RobotFactory.TYPE_SCALES[int(archetype.robot_type)]


func _physics_process(delta: float) -> void:
	if ai_state == AiState.DEAD:
		return
	if global_position.y < -20.0:
		_die(null, false)
		return
	_hit_pop_left = maxf(0.0, _hit_pop_left - delta)
	if is_on_floor():
		_vertical_velocity = -1.0
	else:
		_vertical_velocity -= gravity * delta
	_validate_target(delta)

	var desired := Vector3.ZERO
	match ai_state:
		AiState.SEEK:
			if _target_in_range():
				if target_kind == TargetKind.CHUTE:
					ai_state = AiState.STEALING
					_steal_timer = 0.6
				else:
					ai_state = AiState.WINDUP
					_attack_timer = archetype.attack_windup
					if _first_attack and squad != null:
						# Squads hit in a 3-beat rhythm: clank-clank-CLANK (GDD 9.6).
						_attack_timer += squad_index * archetype.attack_interval / 3.0
					_first_attack = false
					_on_windup_started()
			else:
				desired = _navigate(delta, _goal_position())
		AiState.WINDUP:
			_face(_target_position())
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				if _target_in_range(0.5):
					_deal_hit()
				ai_state = AiState.RECOVER
				_attack_timer = maxf(0.0, archetype.attack_interval - archetype.attack_windup)
		AiState.RECOVER:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				ai_state = AiState.SEEK
		AiState.STEALING:
			_face(_target_position())
			_steal_timer -= delta
			if _steal_timer <= 0.0:
				_grab_sack()
		AiState.FLEEING:
			var flat := global_position - _silo_center()
			flat.y = 0.0
			if flat.length() >= ESCAPE_RADIUS:
				_escape()
				return
			desired = _navigate(delta, _escape_point)
	# Movement happens in _on_velocity_computed once avoidance has adjusted this.
	agent.velocity = desired


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if ai_state == AiState.DEAD:
		return
	velocity = Vector3(safe_velocity.x, _vertical_velocity, safe_velocity.z) + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector3.ZERO, 25.0 * get_physics_process_delta_time())
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5 and ai_state in [AiState.SEEK, AiState.FLEEING]:
		_face(global_position + flat)


# --- Targeting ------------------------------------------------------------------------------------

func _validate_target(delta: float) -> void:
	if target_kind != TargetKind.PLAYER:
		return
	if target_player == null or not is_instance_valid(target_player) \
			or (target_player.has_method("is_alive") and not target_player.call("is_alive")):
		target_player = GameState.get_nearest_player(global_position)
		if target_player == null:
			target_kind = TargetKind.SILO
			return
	# Ground melee robots give up on a farmer camping out of reach.
	if target_player.global_position.y - global_position.y > 2.5:
		_unreachable_time += delta
		if _unreachable_time >= archetype.unreachable_give_up_time:
			target_kind = TargetKind.SILO
			target_player = null
			_unreachable_time = 0.0
	else:
		_unreachable_time = 0.0


func _silo_center() -> Vector3:
	return GameState.silo.global_position if GameState.silo != null else Vector3.ZERO


func _target_position() -> Vector3:
	var silo := GameState.silo
	match target_kind:
		TargetKind.PLAYER:
			if target_player != null and is_instance_valid(target_player):
				return target_player.global_position
		TargetKind.CHUTE:
			if silo != null:
				return silo.chute_position(0.6 + archetype.body_radius)
	if silo == null:
		return global_position
	var wall := silo.wall_point_toward(global_position, 0.0)
	return wall + (wall - silo.global_position).normalized() * (0.5 + archetype.body_radius)


## Where to walk: squad followers keep formation behind their leader until they're close.
func _goal_position() -> Vector3:
	var goal := _target_position()
	if squad != null and squad_index > 0:
		var leader := squad.leader()
		if leader != null and leader != self and leader.global_position.distance_to(goal) > 8.0:
			return leader.global_position + Basis(Vector3.UP, leader.model.rotation.y) * RobotSquad.formation_offset(squad_index, type_scale())
	return goal


func _target_in_range(extra: float = 0.0) -> bool:
	var reach := archetype.attack_range + extra
	match target_kind:
		TargetKind.PLAYER:
			if target_player != null and is_instance_valid(target_player):
				var offset := target_player.global_position - global_position
				return absf(offset.y) < 2.0 * type_scale() and Vector2(offset.x, offset.z).length() <= reach
			return false
		TargetKind.CHUTE:
			var chute := _target_position()
			return Vector2(chute.x - global_position.x, chute.z - global_position.z).length() <= 1.2
	var silo := GameState.silo
	return silo != null and silo.distance_to_wall(global_position) <= reach


func _navigate(delta: float, goal: Vector3) -> Vector3:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 0.25
		agent.target_position = goal
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0 or agent.is_navigation_finished():
		return Vector3.ZERO
	var to_next := agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length() < 0.05:
		return Vector3.ZERO
	return to_next.normalized() * move_speed()


func _face(point: Vector3) -> void:
	var dir := point - global_position
	if Vector2(dir.x, dir.z).length() > 0.01:
		model.rotation.y = atan2(-dir.x, -dir.z)


# --- Attacks (overridden by HeavyRobot) -----------------------------------------------------------

func _on_windup_started() -> void:
	pass


func _deal_hit() -> void:
	if target_kind == TargetKind.PLAYER and target_player != null and is_instance_valid(target_player):
		if target_player.has_method("take_damage"):
			var packet := DamagePacket.create(archetype.damage_vs_farmer * damage_multiplier, self, target_player.global_position)
			target_player.call("take_damage", packet)
		return
	var silo := GameState.silo
	if silo != null:
		var hit_point := silo.wall_point_toward(global_position, 0.6)
		silo.take_damage(DamagePacket.create(archetype.damage_vs_silo * damage_multiplier, self, hit_point))
		var big_beat := squad != null and squad_index == 2
		Fx.puff(self, hit_point, Color(0.95, 0.8, 0.4), 0.3 if big_beat else 0.18, 0.2)


# --- Grain theft (GDD 3.3) ------------------------------------------------------------------------

func _grab_sack() -> void:
	var silo := GameState.silo
	sack_amount = silo.steal_grain(SACK_SIZE) if silo != null else 0.0
	ai_state = AiState.FLEEING
	if sack_amount <= 0.0:
		return
	EventBus.grain_stolen.emit(sack_amount, self)
	RobotFactory.attach_sack(_pose.get_node(^"Kit") as Node3D)
	# Run for the nearest corn lane.
	var best := Vector3.ZERO
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(LaneMarker.GROUP):
		var lane := node as Node3D
		var d := lane.global_position.distance_to(global_position)
		if d < best_distance:
			best_distance = d
			best = lane.global_position
	var out := best - _silo_center()
	out.y = 0.0
	_escape_point = _silo_center() + out.normalized() * (ESCAPE_RADIUS + 4.0)
	_repath_timer = 0.0


func _escape() -> void:
	if sack_amount > 0.0:
		EventBus.hud_message.emit("A thief got away with %d bushels!" % roundi(sack_amount), 2.5)
	sack_amount = 0.0
	_die(null, false)


# --- Damage ---------------------------------------------------------------------------------------

func take_damage(packet: DamagePacket) -> void:
	if ai_state == AiState.DEAD:
		return
	_last_attacker = packet.source
	_hit_pop_left = 0.08
	if packet.knockback != Vector3.ZERO and archetype.robot_type != RobotArchetype.RobotType.HEAVY:
		_knockback = packet.knockback
		_vertical_velocity = maxf(_vertical_velocity, packet.knockback.y)
	var attacker := packet.source as Node3D
	if attacker != null and attacker.is_in_group(&"players") and target_kind == TargetKind.SILO \
			and global_position.distance_to(attacker.global_position) <= archetype.aggro_range:
		target_kind = TargetKind.PLAYER
		target_player = attacker
		_repath_timer = 0.0
	health.apply_damage(packet.amount)


func _on_died() -> void:
	_die(_last_attacker, true)


## Kills the robot. `award_drops` is false for debug clears, escapes and robots that fall off the world.
func _die(killer: Node, award_drops: bool) -> void:
	if ai_state == AiState.DEAD:
		return
	ai_state = AiState.DEAD
	remove_from_group(GROUP)
	remove_from_group(THIEF_GROUP)
	collision_layer = 0
	collision_mask = 0
	agent.avoidance_enabled = false
	for hurtbox in find_children("*Hurtbox", "Area3D"):
		hurtbox.set_deferred(&"collision_layer", 0)
	var drop_point := global_position + Vector3.UP * 0.5 * type_scale()
	if award_drops:
		Pickup.spawn_parts(self, drop_point, roll_drops())
		if sack_amount > 0.0:
			Pickup.spawn_grain(self, drop_point, sack_amount)
	EventBus.robot_destroyed.emit(self, killer)
	destroyed.emit(self, killer)
	Fx.puff(self, drop_point, Color(0.95, 0.95, 0.9), 0.5 * type_scale(), 0.35)
	var tween := create_tween()
	tween.tween_property(model, ^"scale", Vector3.ONE * 1.3, 0.06)
	# Not quite zero: Jolt rejects singular transforms on the eye hurtbox under the model.
	tween.tween_property(model, ^"scale", Vector3.ONE * 0.01, 0.12)
	tween.tween_callback(queue_free)


func kill(award_drops: bool = false) -> void:
	_die(null, award_drops)


## Parts dropped on death (GDD 12.2), scaled by the wave's drop multiplier, plus trait and upgrade luck.
func roll_drops() -> Dictionary[StringName, int]:
	if is_foreman:
		return FOREMAN_DROPS.duplicate()
	var rng := RngService.stream(RngService.STREAM_DROPS)
	var luck := StatService.get_stat(&"drops.rare_chance", 1.0)
	var gold := 1.0
	for robot_trait in all_traits():
		gold *= robot_trait.gold_chance_multiplier
	var al := float(rng.randi_range(archetype.drop_al_min, archetype.drop_al_max) + archetype.drop_al_class_bonus) * drop_multiplier
	return {
		&"al": floori(al) + (1 if rng.randf() < al - floorf(al) else 0),
		&"cu": _roll_part(rng, archetype.drop_cu_chance, archetype.drop_cu_min, archetype.drop_cu_max),
		&"au": _roll_part(rng, archetype.drop_au_chance * gold * luck, archetype.drop_au_min, archetype.drop_au_max),
		&"pc": _roll_part(rng, archetype.drop_pc_chance * luck, archetype.drop_pc_min, archetype.drop_pc_max),
	}


func _roll_part(rng: RandomNumberGenerator, chance: float, low: int, high: int) -> int:
	return rng.randi_range(low, high) if rng.randf() < chance else 0


## Called by the WaveDirector during a long mop-up so the last robots can be found (GDD 9.6).
func mark_straggler() -> void:
	if _marker == null:
		_set_marker("!", Color(1.0, 0.3, 0.2), true, 0.0)
	else:
		_marker.no_depth_test = true


func _set_marker(text: String, color: Color, through_walls: bool, extra_height: float) -> void:
	if _marker == null:
		_marker = Label3D.new()
		_marker.name = "Marker"
		_marker.font_size = 30
		_marker.outline_size = 8
		_marker.fixed_size = true
		_marker.pixel_size = 0.0012
		_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_marker)
	_marker.text = text
	_marker.modulate = color
	_marker.no_depth_test = through_walls
	_marker.position = Vector3(0.0, 1.5 * type_scale() + extra_height, 0.0)


# --- Presentation (stepped at 12 fps, GDD 15.4) ---------------------------------------------------

func _on_tick_12(frame: int) -> void:
	if ai_state == AiState.DEAD or look == null:
		return
	_pose_frame += 1
	if look.bulb != null:
		look.bulb.set_instance_shader_parameter(&"emission_strength", 3.0 if frame % maxi(2, hive_period) < 2 else 0.3)
	var speed := Vector2(velocity.x, velocity.z).length()
	for wheel in look.wheels:
		wheel.rotate_object_local(Vector3.UP, -speed * 0.08)

	var s := type_scale()
	var bob := 0.0
	var tilt := Vector3.ZERO
	match genome.personality:
		&"bouncy":
			bob = 0.07 if _pose_frame % 2 == 0 else 0.0
		&"sneaky":
			bob = 0.015 if _pose_frame % 2 == 0 else 0.0
			tilt.x = deg_to_rad(-8.0)
		&"marching":
			bob = 0.04 if _pose_frame % 2 == 0 else 0.0
			tilt.z = deg_to_rad(3.0 if _pose_frame % 4 < 2 else -3.0)
		&"wobbly":
			tilt.z = deg_to_rad(7.0 if _pose_frame % 4 < 2 else -7.0)
		_:  # grumpy
			bob = 0.02 if _pose_frame % 2 == 0 else 0.0
			tilt.x = deg_to_rad(5.0)
	var moving := ai_state in [AiState.SEEK, AiState.FLEEING] and speed > 0.3
	_pose.position.y = (bob if moving else 0.0) * s
	_pose.rotation = tilt if moving else Vector3.ZERO
	if ai_state == AiState.WINDUP:
		_pose.scale = _windup_pose_scale()
	else:
		_pose.scale = Vector3.ONE * (1.15 if _hit_pop_left > 0.0 else 1.0)


## Anticipation before a hit (GDD 15.4): a squash. Heavies rear up instead.
func _windup_pose_scale() -> Vector3:
	return Vector3(1.2, 0.8, 1.2)
