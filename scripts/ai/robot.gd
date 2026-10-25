class_name Robot
extends CharacterBody3D
## Shared robot health, damage, drops and appearance. This AI drives the ground melee robots: Nibbler,
## Clanker and Thumper, alone or in trios. VerticalRobot supplies the roof and flying ranged behaviors.
##
## Melee AI (GDD 9.6): walk the navmesh to the silo or the farmer and bash it. RobotTargeting decides which,
## from the archetype's behavior variables: the silo-focus roll at spawn, distractions while on the silo
## and the rules that send it back. Nibblers may instead grab a 20-bushel grain sack at the chute and run
## for the corn (GDD 3.3); in a trio the other two escort the thief (a heist crew).
## Sidearms (M2-B9): a melee robot with on_unreachable = throw (Clanker bolts, Thumper clods) makes up to
## MAX_THROWS telegraphed throws through a RangedAttack at a farmer it can't reach, then goes back to the
## silo. An archetype's front_guard (the Clanker's arm guard) cuts damage from hits in front of it.
## The look is kit-bashed by RobotFactory from the wave's RobotGenome. Poses step at 12 fps (GDD 15.4).
## This state machine is replaced by LimboAI behavior trees later (GDD 18.4).

signal destroyed(robot: Robot, killer: Node)

enum AiState { SEEK, WINDUP, RECOVER, STEALING, FLEEING, DEAD }
## ESCORT: a heist crew member following its thief (RobotSquad).
enum TargetKind { SILO, PLAYER, CHUTE, ESCORT }

const GROUP: StringName = &"robots"
const THIEF_GROUP: StringName = &"thieves"
const SACK_SIZE: float = 20.0
const FOREMAN_HP_MULTIPLIER: float = 3.0
## Foreman drops are fixed (GDD 12.2).
const FOREMAN_DROPS: Dictionary[StringName, int] = {&"al": 10, &"cu": 6, &"au": 2, &"pc": 3}
## Distance from the silo at which a fleeing thief is gone into the corn.
const ESCAPE_RADIUS: float = 102.0
## A ground robot can't reach a farmer standing more than this far above it.
const REACH_HEIGHT: float = 2.5
## A farmer this far above the farm floor is up on a perch (the airborne trigger).
const PERCH_HEIGHT: float = 2.5
## How long the angry eye stays after a robot switches to the farmer.
const ANGRY_TIME: float = 1.5
## Throws at an out-of-reach farmer before going back to the silo (decision R-D2).
const MAX_THROWS: int = 2
## The farmer must be out of reach this long before a throw, so a jump doesn't draw one.
const THROW_DELAY: float = 0.5
const GENE_LIBRARY_PATH := "res://data/robots/gene_library.tres"

## Every antenna bulb in the wave blinks together (Factory DNA). The WaveDirector shortens the period
## (in 12 fps frames) when the wave is almost over.
static var hive_period: int = 12
## The chain depth of the death blast dealing damage right now (robots it kills are one deeper).
static var _blast_depth: int = 0

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
## Who it is after (shared by a trio). Made in setup().
var targeting: RobotTargeting = null
var is_thief: bool = false
## A heist crew member guarding its thief.
var is_escort: bool = false
var sack_amount: float = 0.0
var hp_multiplier: float = 1.0
var damage_multiplier: float = 1.0
## Robots that may shoot this wave's farmers at once (DifficultyCurve.farmer_attack_tokens).
var attack_tokens: int = 2
## This wave's ranged scaling (M2-B10): charge-time multiplier, aim lead for straight shots, volley size.
var charge_multiplier: float = 1.0
var aim_lead: float = 0.0
var volley_size: int = 1
## On_unreachable = throw is live this wave (DifficultyCurve.throws_at_unreachable).
var throws_unlocked: bool = false
## The archetype's front_guard is up this wave (DifficultyCurve.arm_guard_up).
var guard_up: bool = false
var drop_multiplier: float = 1.0
var speed_multiplier: float = 1.0
## Setting SILO or PLAYER from outside (tutorial, tests) sends RobotTargeting there too.
var target_kind: TargetKind = TargetKind.SILO:
	set(value):
		target_kind = value
		if targeting == null or is_thief or is_escort:
			return
		if value == TargetKind.SILO and targeting.on_farmer():
			targeting.return_to_silo()
		elif value == TargetKind.PLAYER and not targeting.on_farmer():
			var farmer := target_player
			if farmer == null and is_inside_tree():
				farmer = GameState.get_nearest_player(global_position)
			targeting.switch_to_farmer(farmer)
var target_player: Node3D = null
var ai_state: AiState = AiState.SEEK
var look: RobotFactory.Look
## True from the moment a destroyed robot starts its RobotExplosion; the explosion plays the pop sound.
var exploding: bool = false
## Overcharged (GDD 10.3): the death blast from the family's traits, sized for this robot and wave.
## A radius of 0 means the robot doesn't blow up.
var death_blast_radius: float = 0.0
var death_blast_damage: float = 0.0
var death_blast_farmer_damage: float = 0.0
## How many death blasts in a row led to this robot's death: 0 when the player killed it directly.
var chain_depth: int = 0

var _attack_timer: float = 0.0
var _first_attack: bool = true
var _repath_timer: float = 0.0
var _angry_left: float = 0.0
var _steal_timer: float = 0.0
var _escape_point: Vector3 = Vector3.ZERO
var _vertical_velocity: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _last_attacker: Node = null
## Flat direction of the last hit, so the death explosion throws parts away from the attacker.
var _last_hit_direction: Vector3 = Vector3.ZERO
var _pose_frame: int = 0
var _hit_pop_left: float = 0.0
var _marker: Label3D = null
var _spark_core: MeshInstance3D = null
## The out-of-reach throw (on_unreachable = throw), or null.
var _throw: RangedAttack = null
var _throws_done: int = 0

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
	attack_tokens = curve.farmer_attack_tokens(wave)
	charge_multiplier = curve.charge_multiplier(wave)
	aim_lead = curve.aim_lead(wave)
	volley_size = curve.volley_size(wave)
	throws_unlocked = curve.throws_at_unreachable(wave)
	guard_up = curve.arm_guard_up(wave)
	drop_multiplier = curve.drop_multiplier(wave)
	var blast_size := sqrt(RobotFactory.TYPE_SCALES[int(archetype.robot_type)])
	for robot_trait in all_traits():
		hp_multiplier *= robot_trait.hp_multiplier
		speed_multiplier *= robot_trait.speed_multiplier
		if robot_trait.death_blast_radius > 0.0:
			death_blast_radius = maxf(death_blast_radius, robot_trait.death_blast_radius * blast_size)
			death_blast_damage = maxf(death_blast_damage,
					robot_trait.death_blast_damage * blast_size * curve.hp_multiplier(wave))
			death_blast_farmer_damage = maxf(death_blast_farmer_damage,
					robot_trait.death_blast_farmer_damage * blast_size * damage_multiplier)
	if foreman and family != null:
		foreman_title = family.foreman_title(rng)

	if robot_squad != null:
		squad = robot_squad
		squad_index = squad.join(self)
	if squad != null and squad_index > 0 and squad.targeting != null:
		# Trio followers take the leader's rolls (GDD 9.6).
		targeting = squad.targeting
		if squad.heist_leader != null:
			is_escort = true
			target_kind = TargetKind.ESCORT
	else:
		targeting = RobotTargeting.new(archetype, rng)
		var steal_chance := archetype.steal_chance
		# Scouts steal at the curve's per-wave thief share; a Thieving family raises it (GDD 11.7, ROADMAP D4).
		# The leader rolls for its trio, which then counts as one thief: a heist crew.
		if archetype.robot_class == RobotArchetype.RobotClass.MELEE \
				and archetype.robot_type == RobotArchetype.RobotType.SCOUT:
			var thieving := all_traits().any(func(t: RobotTrait) -> bool: return t.thieving)
			steal_chance = curve.thief_chance(wave, archetype.silo_focus, thieving)
		if not targeting.hunter and not foreman and rng.randf() < steal_chance:
			is_thief = true
			targeting.can_be_distracted = false
			target_kind = TargetKind.CHUTE
		if squad != null:
			squad.targeting = targeting
			if is_thief:
				squad.heist_leader = self
	if not is_thief and not is_escort:
		_sync_target()
	targeting.switched.connect(_on_target_switched)
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
	_spark_core = _pose.find_child(RobotFactory.SPARK_CORE, true, false) as MeshInstance3D
	for tell in archetype.tells:
		var part := _pose.get_node_or_null(NodePath("Kit/%s" % tell)) as Node3D
		if part != null:
			part.visible = tell_live(tell)
	if archetype.on_unreachable == RobotArchetype.OnUnreachable.THROW and throws_unlocked:
		_make_throw()
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


## Whether the part for `tell` shows this wave: the arm guard and the throwers' ammo only once they work.
func tell_live(tell: StringName) -> bool:
	match tell:
		&"arm_guard":
			return guard_up and archetype.front_guard > 0.0
		&"bolt_pouch", &"clod_scoop":
			return throws_unlocked
	return true


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
	_update_targeting(delta)
	if _update_throw(delta):
		agent.velocity = Vector3.ZERO
		return

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

## Ticks RobotTargeting (a trio's leader ticks it for all three) and follows its decision.
func _update_targeting(delta: float) -> void:
	if is_escort:
		_update_escort()
		return
	if is_thief or target_kind == TargetKind.CHUTE or targeting == null:
		return
	if squad == null or squad.leader() == self:
		targeting.tick(delta, sense())
	_sync_target()


## What this robot senses for RobotTargeting this frame.
func sense() -> RobotTargeting.Senses:
	var senses := RobotTargeting.Senses.new()
	var flat := global_position - _silo_center()
	flat.y = 0.0
	senses.distance_from_silo = flat.length()
	var farmer := targeting.farmer if targeting.on_farmer() and _is_living(targeting.farmer) else null
	if farmer == null:
		farmer = GameState.get_nearest_player(global_position)
	if farmer == null:
		return senses
	senses.farmer = farmer
	senses.farmer_distance = global_position.distance_to(farmer.global_position)
	senses.farmer_reachable = can_reach(farmer)
	senses.farmer_airborne = farmer_airborne(farmer)
	senses.farmer_repairing = farmer is Farmer and (farmer as Farmer).repair.is_repairing
	return senses


## Ground melee robots can't get at a farmer up on a roof, ladder or zipline; VerticalRobot can shoot one.
func can_reach(farmer: Node3D) -> bool:
	return farmer.global_position.y - global_position.y <= REACH_HEIGHT


## The farmer is jetpacking, or up off the farm floor on a perch, ladder or zipline.
func farmer_airborne(farmer: Node3D) -> bool:
	if farmer is Farmer and (farmer as Farmer).state in [Farmer.State.JETPACKING, Farmer.State.CLIMBING,
			Farmer.State.ZIPLINING]:
		return true
	var floor_y := GameState.silo.global_position.y if GameState.silo != null else 0.0
	return farmer.global_position.y - floor_y > PERCH_HEIGHT


func _sync_target() -> void:
	if targeting.on_farmer():
		target_player = targeting.farmer
		if target_kind != TargetKind.PLAYER:
			target_kind = TargetKind.PLAYER
	else:
		target_player = null
		if target_kind != TargetKind.SILO:
			target_kind = TargetKind.SILO


## Heist escorts follow their thief and fight a farmer who comes near either of them (RobotSquad).
func _update_escort() -> void:
	if squad == null or not squad.heist_active():
		is_escort = false
		if squad != null and squad.heist_escaped:
			_flee_outward()
		else:
			# The thief is gone: the escorts carry on as an ordinary pair, distractible again.
			targeting.can_be_distracted = true
			target_kind = TargetKind.SILO
			_sync_target()
		return
	var thief := squad.heist_leader
	var farmer := GameState.get_nearest_player(global_position)
	var reach := archetype.distract_range
	var threat := farmer != null and can_reach(farmer) \
			and (farmer.global_position.distance_to(global_position) <= reach
				or farmer.global_position.distance_to(thief.global_position) <= reach)
	if threat:
		target_player = farmer
		target_kind = TargetKind.PLAYER
	elif target_kind == TargetKind.PLAYER and (farmer == null
			or farmer.global_position.distance_to(thief.global_position) > reach * 1.5):
		target_player = null
		target_kind = TargetKind.ESCORT


func _is_living(node: Node3D) -> bool:
	return node != null and is_instance_valid(node) and (not node.has_method(&"is_alive") or node.call(&"is_alive"))


## The "!" pop and an angry eye when it switches to the farmer after a distraction (GDD 9.6).
func _on_target_switched(goal: RobotTargeting.Goal) -> void:
	if goal != RobotTargeting.Goal.FARMER or ai_state == AiState.DEAD or not is_inside_tree():
		return
	_throws_done = 0
	_angry_left = ANGRY_TIME
	var pop := Label3D.new()
	pop.text = "!"
	pop.font_size = 44
	pop.outline_size = 10
	pop.modulate = Color(1.0, 0.3, 0.2)
	pop.fixed_size = true
	pop.pixel_size = 0.0012
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(pop)
	pop.position = Vector3(0.0, 1.5 * type_scale() + 0.3, 0.0)
	var tween := pop.create_tween()
	tween.tween_property(pop, ^"position:y", pop.position.y + 0.5, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(pop.queue_free)


func _silo_center() -> Vector3:
	return GameState.silo.global_position if GameState.silo != null else Vector3.ZERO


func _target_position() -> Vector3:
	var silo := GameState.silo
	match target_kind:
		TargetKind.PLAYER:
			if target_player != null and is_instance_valid(target_player):
				return target_player.global_position
		TargetKind.ESCORT:
			if squad != null and squad.heist_active():
				var thief := squad.heist_leader
				return thief.global_position + Basis(Vector3.UP, thief.model.rotation.y) \
						* RobotSquad.formation_offset(squad_index, type_scale())
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
	if squad != null and squad_index > 0 and target_kind != TargetKind.ESCORT:
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
		TargetKind.ESCORT:
			return false
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


# --- Ranged attacks and throws (M2-B7, B9, B10) ---------------------------------------------------

## A RangedAttack child firing `profile` from `muzzle`, with this wave's tokens, charge and aim lead.
func make_ranged_attack(profile: AttackProfile, muzzle: Node3D, attack_name: String = "RangedAttack") -> RangedAttack:
	var attack := RangedAttack.new()
	attack.name = attack_name
	add_child(attack)
	attack.setup(self, profile, muzzle)
	attack.token_limit = attack_tokens
	attack.charge_multiplier = charge_multiplier
	attack.aim_lead = aim_lead
	return attack


## What a RangedAttack set up with this robot aims at next; melee robots aim their throws themselves.
func ranged_target() -> Node3D:
	return null


## A glowing ball on the weapon hand that charges before each shot; hidden until then.
func make_muzzle(at: Vector3, color: Color, radius: float = 0.24, muzzle_name: String = "ChargingProjectile") -> MeshInstance3D:
	var muzzle := MeshInstance3D.new()
	muzzle.name = muzzle_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	muzzle.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	muzzle.material_override = material
	model.add_child(muzzle)
	muzzle.position = at
	muzzle.visible = false
	return muzzle


func _make_throw() -> void:
	var profile := archetype.ranged_attack()
	if profile == null:
		push_warning("%s throws when out of reach but has no attack profile." % archetype.id)
		return
	var hand := RobotFactory.ARM_WEAPON + Vector3(0.0, 0.25, -0.2)
	var muzzle := make_muzzle(hand * type_scale(), profile.color, profile.projectile_radius * 1.2, "ThrowCharge")
	_throw = make_ranged_attack(profile, muzzle, "Throw")
	# No token free: hold the throw (and give up on the usual clock) rather than lob it at the silo.
	_throw.silo_fallback = false
	_throw.target_provider = func() -> Node3D: return targeting.farmer if wants_throw() else null
	_throw.fired.connect(func() -> void: _throws_done += 1)
	_throw.finished.connect(_on_throw_finished)


## On_unreachable = throw: its farmer has been out of reach for THROW_DELAY, is within the throw's range,
## and it has throws left.
func wants_throw() -> bool:
	if _throw == null or is_thief or is_escort or targeting == null or not targeting.on_farmer():
		return false
	if _throws_done >= MAX_THROWS or targeting.unreachable_time() < THROW_DELAY:
		return false
	var farmer := targeting.farmer
	if not _is_living(farmer) or can_reach(farmer):
		return false
	return global_position.distance_to(farmer.global_position) <= _throw.profile.attack_range


## Runs the out-of-reach throw. True while a throw is under way: the robot stands still for it and the
## give-up clock holds. With no token free it keeps walking and gives up on the usual clock.
func _update_throw(delta: float) -> bool:
	if _throw == null:
		return false
	match _throw.state:
		RangedAttack.State.FIRING, RangedAttack.State.RECOVER:
			targeting.hold_give_up()
			_throw.step(delta)
			return true
		RangedAttack.State.CHARGING:
			if not wants_throw():
				_throw.cancel()
				return false
			targeting.hold_give_up()
			_throw.step(delta)
			return true
	if ai_state != AiState.SEEK or not wants_throw():
		return false
	_throw.step(delta)
	if _throw.state == RangedAttack.State.CHARGING:
		targeting.hold_give_up()
		return true
	return false


## After its last throw it goes back to the silo, unless the farmer has come back within reach.
func _on_throw_finished() -> void:
	if _throws_done < MAX_THROWS or ai_state == AiState.DEAD or not targeting.on_farmer():
		return
	if not _is_living(targeting.farmer) or not can_reach(targeting.farmer):
		targeting.return_to_silo(RobotTargeting.Return.UNREACHABLE)
		_sync_target()


## Throws made at the current out-of-reach farmer.
func throws_done() -> int:
	return _throws_done


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


## Runs straight out into the corn: heist escorts whose thief got away.
func _flee_outward() -> void:
	var out := global_position - _silo_center()
	out.y = 0.0
	_escape_point = _silo_center() + (out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD) \
			* (ESCAPE_RADIUS + 4.0)
	ai_state = AiState.FLEEING
	_repath_timer = 0.0


func _escape() -> void:
	if sack_amount > 0.0:
		EventBus.hud_message.emit("A thief got away with %d bushels!" % roundi(sack_amount), 2.5)
	if squad != null and squad.heist_leader == self:
		squad.heist_escaped = true
	sack_amount = 0.0
	_die(null, false)


# --- Damage ---------------------------------------------------------------------------------------

func take_damage(packet: DamagePacket) -> void:
	if ai_state == AiState.DEAD:
		return
	_last_attacker = packet.source
	_hit_pop_left = 0.08
	var push := packet.knockback
	if push == Vector3.ZERO and is_instance_valid(packet.source) and packet.source is Node3D:
		push = global_position - (packet.source as Node3D).global_position
	push.y = 0.0
	_last_hit_direction = push.normalized() if push.length_squared() > 0.0001 else Vector3.ZERO
	if packet.knockback != Vector3.ZERO and archetype.robot_type != RobotArchetype.RobotType.HEAVY:
		_knockback = packet.knockback
		_vertical_velocity = maxf(_vertical_velocity, packet.knockback.y)
	var attacker := packet.source as Node3D
	if attacker != null and attacker.is_in_group(&"players") and targeting != null and not is_thief and not is_escort:
		var was_on_farmer := targeting.on_farmer()
		targeting.on_hurt(attacker, global_position.distance_to(attacker.global_position))
		_sync_target()
		if targeting.on_farmer() and not was_on_farmer:
			_repath_timer = 0.0
	var amount := packet.amount
	if guard_up and archetype.front_guard > 0.0 and hit_from_front(packet):
		amount *= 1.0 - archetype.front_guard
		Fx.puff(self, packet.position, RobotFactory.METAL, 0.2, 0.12)
	health.apply_damage(amount)


## The hit came from within FRONT_GUARD_HALF_ANGLE of the way it faces: from the attacker if it has a
## position, else from where it landed.
func hit_from_front(packet: DamagePacket) -> bool:
	var origin := packet.position
	if is_instance_valid(packet.source) and packet.source is Node3D:
		origin = (packet.source as Node3D).global_position
	var to_hit := origin - global_position
	to_hit.y = 0.0
	if to_hit.length_squared() < 0.0001:
		return false
	var forward := -model.global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_hit.normalized()) >= cos(deg_to_rad(RobotArchetype.FRONT_GUARD_HALF_ANGLE))


func _on_died() -> void:
	_die(_last_attacker, true)


## Kills the robot. `award_drops` is false for debug clears, escapes and robots that fall off the world;
## only kills that award drops explode, so thieves slip quietly into the corn.
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
	if _marker != null:
		_marker.visible = false
	exploding = award_drops
	chain_depth = _blast_depth
	if chain_depth >= 2:
		EventBus.hud_message.emit("Chain reaction x%d!" % (chain_depth + 1), 1.2)
	EventBus.robot_destroyed.emit(self, killer)
	destroyed.emit(self, killer)
	var tween := create_tween()
	if exploding:
		# Anticipation: swell for one stop-motion frame, then the explosion takes the parts and bursts.
		var fx := RobotExplosion.for_robot(self, _last_hit_direction, death_blast_radius)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		# Uniform: Jolt can't scale the eye hurtbox under the model non-uniformly.
		tween.tween_property(model, ^"scale", Vector3.ONE * 1.25, fx.fuse) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if death_blast_radius > 0.0:
			tween.tween_callback(_detonate)
		tween.tween_interval(0.1)
		tween.tween_callback(queue_free)
		return
	Fx.puff(self, drop_point, Color(0.95, 0.95, 0.9), 0.5 * type_scale(), 0.35)
	tween.tween_property(model, ^"scale", Vector3.ONE * 1.3, 0.06)
	# Not quite zero: Jolt rejects singular transforms on the eye hurtbox under the model.
	tween.tween_property(model, ^"scale", Vector3.ONE * 0.01, 0.12)
	tween.tween_callback(queue_free)


func kill(award_drops: bool = false) -> void:
	_die(null, award_drops)


## Overcharged's death blast, on the explosion's burst frame. Robots it kills credit whoever killed this
## one, so a chain started by the farmer pays the farmer; Overcharged victims go off in turn a fuse later.
func _detonate() -> void:
	var center := global_position + Vector3.UP * 0.5 * type_scale()
	var source: Node = _last_attacker if is_instance_valid(_last_attacker) else null
	_blast_depth = chain_depth + 1
	AreaAttack.hit_robots(self, center, death_blast_radius, death_blast_damage, source, 6.0)
	_blast_depth = 0
	if death_blast_farmer_damage <= 0.0:
		return
	for node in get_tree().get_nodes_in_group(&"players"):
		var farmer := node as Node3D
		if farmer == null or not farmer.has_method(&"take_damage"):
			continue
		var offset := farmer.global_position + Vector3.UP * 0.9 - center
		var distance := offset.length()
		if distance > death_blast_radius:
			continue
		var packet := DamagePacket.create(death_blast_farmer_damage * maxf(0.5, 1.0 - distance / death_blast_radius),
				self, farmer.global_position)
		var outward := Vector3(offset.x, 0.0, offset.z)
		packet.knockback = (outward.normalized() if outward.length_squared() > 0.0001 else Vector3.ZERO) * 7.0 \
				+ Vector3.UP * 3.0
		farmer.call(&"take_damage", packet)


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
		&"pc": _roll_part(rng, power_cell_chance(), archetype.drop_pc_min, archetype.drop_pc_max),
	}


## Chance to drop Power Cells, with upgrade luck and traits (Overcharged doubles it).
func power_cell_chance() -> float:
	var chance := archetype.drop_pc_chance * StatService.get_stat(&"drops.rare_chance", 1.0)
	for robot_trait in all_traits():
		chance *= robot_trait.power_cell_chance_multiplier
	return chance


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
	if _angry_left > 0.0:
		_angry_left -= 1.0 / 12.0
		var angry := _angry_left > 0.0
		for eye in look.eyes:
			# A hot, flickering glare: it means business.
			eye.set_instance_shader_parameter(&"emission_strength", (7.0 if frame % 2 == 0 else 5.0) if angry else 2.5)
	if _spark_core != null:
		_crackle(frame)
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


## Overcharged's tell: the coil core flickers and now and then throws a little arc.
func _crackle(frame: int) -> void:
	var beat := (frame * 7 + get_instance_id()) % 11
	_spark_core.set_instance_shader_parameter(&"emission_strength", 6.0 if beat < 2 else (1.5 if beat < 6 else 3.0))
	if beat == 0:
		var from := _spark_core.global_position
		var jitter := Vector3(randf_range(-0.3, 0.3), randf_range(-0.25, 0.1), randf_range(-0.3, 0.3)) * type_scale()
		Fx.tracer(self, from, from + jitter, RobotFactory.SPARK_COLOR)


## Anticipation before a hit (GDD 15.4): a squash. Heavies rear up instead.
func _windup_pose_scale() -> Vector3:
	return Vector3(1.2, 0.8, 1.2)
