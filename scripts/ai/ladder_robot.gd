class_name LadderRobot
extends Robot
## The Rung Runner (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md slice 2): a clearly marked light robot
## that climbs the silo ladder to the first catwalk, walks around it and bashes the silo at that height, so
## its hits open catwalk cracks. It is part of the wave's climber share, not added on top of it.
##
## Its route is authored, not free climbing: the navmesh to the ladder's foot, the ladder line itself, the
## catwalk landing, then the catwalk ring by angle around the silo (0 = the ladder side). At most
## MAX_ON_LADDER climb at once, LADDER_GAP apart, and the rest wait beside the foot, never on it, so they
## can't jam the ladder; the farmer passes through them. Climbing clanks in a metal rhythm, shows a marker
## and tells the HUD (EventBus.climber_alert) so the warning can point at the ladder.
##
## Up there it picks the catwalk crack socket on the side with an open crack (else either side). A catwalk
## barricade on that side turns it the other way, the supported alternate route, unless both ways are shut;
## then it smashes the nearer one. A catwalk decoy pulls it to the decoy. A spring on its path throws it
## off: it falls, lands hurt (Robot.launch), gets up and walks back to the ladder. A farmer who comes onto
## the catwalk gets fought there; one below is out of reach. Ground fire works the whole way up.

enum Travel { APPROACH, QUEUE, CLIMB, CATWALK }

const LADDER_GROUP: StringName = &"ladder_climbers"
const MAX_ON_LADDER: int = 2
## Metres between two robots on the ladder.
const LADDER_GAP: float = 2.2
## How far beside the ladder foot a waiting climber stands.
const WAIT_OFFSET: float = 2.4
## Middle of the catwalk's walkway, from the silo's axis.
const CATWALK_RADIUS: float = 4.8
## The first catwalk's crack sockets sit 45 degrees either side of the ladder.
const ATTACK_ANGLE: float = PI / 4.0
## It stops this far (radians) short of a decoy or barricade it is going to hit.
const STOP_SHORT: float = 0.32
const CLANK_PERIOD: float = 0.42

@export var climb_speed: float = 2.2
@export var catwalk_speed: float = 3.0

var travel: Travel = Travel.APPROACH
## Height of the catwalk it climbs to, above the ladder's foot.
var landing: float = 8.0
var _ladder: Climbable = null
var _climb_height: float = 0.0
var _angle: float = 0.0
var _goal_angle: float = ATTACK_ANGLE
var _side: float = 1.0
var _clank_left: float = 0.0
var _wait_side: float = 1.0
var _climb_marker: Label3D = null


func _ready() -> void:
	super._ready()
	add_to_group(LADDER_GROUP)
	_ladder = _find_ladder()
	if _ladder != null and not _ladder.landings.is_empty():
		landing = _ladder.landings[0]
	_wait_side = 1.0 if get_instance_id() % 2 == 0 else -1.0
	_climb_marker = Label3D.new()
	_climb_marker.name = "ClimbMarker"
	_climb_marker.text = "^"
	_climb_marker.font_size = 40
	_climb_marker.outline_size = 9
	_climb_marker.modulate = Color(1.0, 0.82, 0.15)
	_climb_marker.pixel_size = 0.0014
	_climb_marker.fixed_size = true
	_climb_marker.no_depth_test = true
	_climb_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_climb_marker.position = Vector3(0.0, 1.35, 0.0)
	_climb_marker.visible = false
	add_child(_climb_marker)


func _exit_tree() -> void:
	if travel in [Travel.CLIMB, Travel.CATWALK]:
		EventBus.climber_alert.emit(self, false)


func can_steal() -> bool:
	return false


func is_elevated() -> bool:
	return travel in [Travel.CLIMB, Travel.CATWALK]


## The farmer is only within reach on the same floor: on the catwalk with it, or on the ground with it.
func can_reach(farmer: Node3D) -> bool:
	if travel == Travel.CLIMB:
		return false
	return absf(farmer.global_position.y - global_position.y) <= REACH_HEIGHT


func _physics_process(delta: float) -> void:
	if ai_state == AiState.DEAD:
		return
	if global_position.y < -20.0:
		_die(null, false)
		return
	if not is_elevated():
		super._physics_process(delta)
		if ai_state not in [AiState.LAUNCHED, AiState.STUNNED]:
			_update_ground_route()
		return
	_hit_pop_left = maxf(0.0, _hit_pop_left - delta)
	if _process_launch(delta):
		return
	match travel:
		Travel.CLIMB:
			_climb(delta)
		Travel.CATWALK:
			_update_targeting(delta)
			_update_catwalk_target()
			var desired := _ai_step(delta)
			_walk_ring(desired, delta)


# --- On the ground ---------------------------------------------------------------------------------

## Heading for the silo means heading for the ladder; at its foot it climbs, or waits beside it.
func _update_ground_route() -> void:
	if target_kind != TargetKind.SILO or _ladder == null:
		return
	var foot := _foot()
	var flat := Vector2(global_position.x - foot.x, global_position.z - foot.z)
	match travel:
		Travel.APPROACH:
			if flat.length() <= 1.0 and is_on_floor():
				if _ladder_has_room():
					_start_climb()
				else:
					travel = Travel.QUEUE
		Travel.QUEUE:
			if _ladder_has_room():
				travel = Travel.APPROACH


func _target_position() -> Vector3:
	if target_kind == TargetKind.SILO and not is_elevated() and _ladder != null:
		return _wait_spot() if travel == Travel.QUEUE else _foot()
	return super._target_position()


## It never bashes the silo from the ground: its job is the ladder.
func _target_in_range(extra: float = 0.0) -> bool:
	if target_kind == TargetKind.SILO and not is_elevated():
		return false
	if target_kind == TargetKind.SILO and travel == Travel.CATWALK:
		return absf(angle_difference(_angle, _goal_angle)) <= 0.08
	return super._target_in_range(extra)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if not is_elevated():
		super._on_velocity_computed(safe_velocity)


func _foot() -> Vector3:
	return _ladder.global_position + _ladder.outward() * 0.7


func _wait_spot() -> Vector3:
	var side := Vector3.UP.cross(_ladder.outward()).normalized()
	return _foot() + side * WAIT_OFFSET * _wait_side + _ladder.outward() * 0.8


func _ladder_has_room() -> bool:
	var climbing := 0
	for node in get_tree().get_nodes_in_group(LADDER_GROUP):
		var other := node as LadderRobot
		if other == self or other == null or other.ai_state == AiState.DEAD or other.travel != Travel.CLIMB:
			continue
		climbing += 1
		if other._climb_height < LADDER_GAP:
			return false
	return climbing < MAX_ON_LADDER


# --- The ladder ------------------------------------------------------------------------------------

func _start_climb() -> void:
	travel = Travel.CLIMB
	ai_state = AiState.SEEK
	_release_defense()
	agent.velocity = Vector3.ZERO
	agent.avoidance_enabled = false
	collision_mask = 0
	_climb_height = maxf(0.0, _ladder.height_above_base(global_position))
	_clank_left = 0.0
	_climb_marker.visible = true
	EventBus.climber_alert.emit(self, true)


func _climb(delta: float) -> void:
	_climb_height = minf(landing, _climb_height + climb_speed * speed_multiplier * delta)
	global_position = _ladder.line_position(_climb_height)
	velocity = Vector3.UP * climb_speed
	_face(_ladder.global_position - _ladder.outward())
	_clank_left -= delta
	if _clank_left <= 0.0:
		_clank_left = CLANK_PERIOD
		AudioDirector.play_cue(&"climb_clank", 0.92 + 0.16 * float(int(_climb_height * 2.0) % 2), -4.0)
	if _climb_height >= landing - 0.01:
		_step_onto_catwalk()


func _step_onto_catwalk() -> void:
	global_position = _ladder.landing_exit_point(landing)
	velocity = Vector3.ZERO
	travel = Travel.CATWALK
	ai_state = AiState.SEEK
	_angle = _angle_of(global_position)
	_pick_side()
	Fx.puff(self, global_position + Vector3.UP * 0.3, Color(1.0, 0.82, 0.3), 0.3, 0.2)


# --- The catwalk -----------------------------------------------------------------------------------

## Toward a crack it can grow if there is one, away from a barricaded side if the other is clear.
func _pick_side() -> void:
	var silo := GameState.silo
	_side = 1.0 if get_instance_id() % 3 != 0 else -1.0
	if silo != null:
		for crack in silo.get_cracks():
			if crack.band == 1:
				_side = signf(angle_difference(_angle, _angle_of(crack.global_position)))
				if _side == 0.0:
					_side = 1.0
				break
	var ahead := _barricade_toward(_side)
	if ahead != null and _barricade_toward(-_side) == null:
		_side = -_side
	_goal_angle = _angle + _side * ATTACK_ANGLE


## Catwalk decoys pull it in; a barricade across its way is smashed when there's no way round.
func _update_catwalk_target() -> void:
	var delta := get_physics_process_delta_time()
	_lure_cooldown = maxf(0.0, _lure_cooldown - delta)
	if targeting != null and targeting.on_farmer():
		return
	if target_kind == TargetKind.DEFENSE and _defense_alive():
		if target_defense is ScarecrowDecoy:
			_lure_left -= delta
			if _lure_left <= 0.0:
				_release_defense()
		return
	if target_kind == TargetKind.DEFENSE:
		_release_defense()
	var decoy := _catwalk_decoy()
	if decoy != null and _lure_cooldown <= 0.0 and decoy.adopt(self):
		_set_defense_target(decoy)
		_lure_left = decoy.definition.lure_time
		return
	var wall := _barricade_toward(signf(angle_difference(_angle, _goal_angle)))
	if wall != null and absf(angle_difference(_angle, wall.site.catwalk_angle)) <= STOP_SHORT + 0.05:
		_set_defense_target(wall)


func _catwalk_decoy() -> ScarecrowDecoy:
	for node in get_tree().get_nodes_in_group(Defense.GROUP):
		var decoy := node as ScarecrowDecoy
		if decoy != null and decoy.active and decoy.site != null and decoy.site.kind == &"catwalk" \
				and absf(decoy.global_position.y - global_position.y) < 2.0 and decoy.lured_count() < decoy.max_lured():
			return decoy
	return null


## The finished catwalk barricade between here and the attack spot on `side` (+1 or -1).
func _barricade_toward(side: float) -> ScrapBarricade:
	var best: ScrapBarricade = null
	var best_gap := INF
	for node in get_tree().get_nodes_in_group(Defense.GROUP):
		var wall := node as ScrapBarricade
		if wall == null or not wall.active or wall.site == null or wall.site.kind != &"catwalk" \
				or absf(wall.global_position.y - global_position.y) > 2.0:
			continue
		var gap := angle_difference(_angle, wall.site.catwalk_angle) * side
		if gap > -0.05 and gap < ATTACK_ANGLE + 0.1 and gap < best_gap:
			best_gap = gap
			best = wall
	return best


## The flat velocity _ai_step wants, turned into steps around the ring. Seeking the silo walks to the goal
## angle; seeking the farmer or a defense walks to its angle and stops short.
func _seek_velocity(_delta: float) -> Vector3:
	if travel != Travel.CATWALK:
		return super._seek_velocity(_delta)
	var goal := _goal_angle
	var stop := 0.0
	match target_kind:
		TargetKind.PLAYER:
			if target_player != null and is_instance_valid(target_player):
				goal = _angle_of(target_player.global_position)
				stop = 0.22
		TargetKind.DEFENSE:
			if _defense_alive():
				goal = target_defense.site.catwalk_angle if target_defense.site != null else _angle_of(target_defense.global_position)
				stop = STOP_SHORT
	var gap := angle_difference(_angle, goal)
	if absf(gap) <= stop + 0.02:
		return Vector3.ZERO
	var tangent := Vector3(cos(_angle), 0.0, -sin(_angle)) * signf(gap)
	return tangent * catwalk_speed * speed_multiplier


func _walk_ring(desired: Vector3, delta: float) -> void:
	var silo := GameState.silo
	if silo == null:
		return
	var speed := desired.length()
	if speed > 0.01:
		var forward := Vector3(cos(_angle), 0.0, -sin(_angle))
		var step := speed * delta / CATWALK_RADIUS * signf(desired.dot(forward))
		_angle += step
		_face(global_position + desired)
	var center := silo.global_position
	global_position = Vector3(center.x + sin(_angle) * CATWALK_RADIUS, center.y + landing + 0.05,
			center.z + cos(_angle) * CATWALK_RADIUS)
	velocity = desired
	if ai_state in [AiState.WINDUP, AiState.STEALING] or (ai_state == AiState.SEEK and speed <= 0.01):
		_face(_target_position())


## Up on the catwalk it hits the silo at its own height, so the crack opens (or grows) on the catwalk.
func _deal_hit() -> void:
	var silo := GameState.silo
	if travel == Travel.CATWALK and target_kind == TargetKind.SILO and silo != null:
		var height := global_position.y - silo.global_position.y + 0.6
		var hit_point := silo.wall_point_toward(global_position, height)
		silo.take_damage(DamagePacket.create(archetype.damage_vs_silo * damage_multiplier, self, hit_point))
		Fx.puff(self, hit_point, Color(0.95, 0.8, 0.4), 0.2, 0.2)
		return
	super._deal_hit()


## Catwalk decoys work through their own pull (_update_catwalk_target); ground decoys pull it like any
## ground robot until it reaches the ladder.
func can_be_lured_by(decoy: Defense) -> bool:
	if is_elevated():
		return false
	return super.can_be_lured_by(decoy)


# --- Thrown off ------------------------------------------------------------------------------------

func _on_launched() -> void:
	if travel in [Travel.CLIMB, Travel.CATWALK]:
		EventBus.climber_alert.emit(self, false)
	_climb_marker.visible = false
	travel = Travel.APPROACH


## A weak throw can leave it on the catwalk; otherwise it walks back to the ladder.
func _on_recovered_from_launch() -> void:
	super._on_recovered_from_launch()
	agent.avoidance_enabled = true
	var silo := GameState.silo
	if silo != null and global_position.y - silo.global_position.y > landing - 1.0 \
			and silo.distance_to_wall(global_position) < 2.2:
		travel = Travel.CATWALK
		collision_mask = 0
		_angle = _angle_of(global_position)
		_pick_side()
		_climb_marker.visible = true
		EventBus.climber_alert.emit(self, true)
	else:
		travel = Travel.APPROACH


func _die(killer: Node, award_drops: bool) -> void:
	if travel in [Travel.CLIMB, Travel.CATWALK] and ai_state != AiState.DEAD:
		EventBus.climber_alert.emit(self, false)
	if _climb_marker != null:
		_climb_marker.visible = false
	super._die(killer, award_drops)


func _angle_of(point: Vector3) -> float:
	var center := GameState.silo.global_position if GameState.silo != null else Vector3.ZERO
	return atan2(point.x - center.x, point.z - center.z)


func _find_ladder() -> Climbable:
	var silo := GameState.silo
	if silo == null:
		return null
	return silo.get_node_or_null(^"Ladder") as Climbable
