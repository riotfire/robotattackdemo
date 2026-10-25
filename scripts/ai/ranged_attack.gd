class_name RangedAttack
extends Node
## A robot's ranged attack (M2-B7, delivers M2-A4): charge, fire, recover, from an AttackProfile.
## The robot calls step() every physics frame while it can shoot and cancel() when it can't.
##
## Fairness rules (GDD 9.6): every shot charges a glow on the muzzle first, and lobs, rails and bombs also
## show an AttackTelegraph. A shot at a farmer needs one of that farmer's AttackTokens; with none free the
## robot shoots the silo. No more than MAX_PROJECTILES robot shots fly at once. Each shot charged at a
## farmer announces itself on EventBus.robot_shot_incoming, flagged when the shooter is off screen.
## DifficultyCurve scales the charge, the aim lead (straight shots only) and the volley from wave 6 (M2-B10).

## The last shot of an attack has left the muzzle.
signal fired
## The attack has recovered and can charge again.
signal finished

enum State { READY, CHARGING, FIRING, RECOVER }

## World and Player layers: shots hit the farm, the farmer and the silo, never other robots.
const PROJECTILE_MASK: int = 1 | 2
## Robot shots in flight at once, across every robot (performance and fairness).
const MAX_PROJECTILES: int = 24
## Lob and bomb circles are never smaller than this, so they read from a distance.
const MIN_CIRCLE_RADIUS: float = 1.2

## Every robot shot in flight: [Projectile, its launch count when fired].
static var _flying: Array[Array] = []

var profile: AttackProfile
var robot: Robot
var state: State = State.READY
## The farmer or the silo this attack is aimed at.
var target: Node3D = null
var telegraph: AttackTelegraph = null
## Farmer tokens this attack may hold at most; set from DifficultyCurve.farmer_attack_tokens.
var token_limit: int = 2
## Scales the charge (DifficultyCurve and traits, M2-B10); the profile's floor still holds.
var charge_multiplier: float = 1.0
## Share of a moving farmer's travel during the flight that straight shots aim ahead (DifficultyCurve.aim_lead).
## Lobs, rails and bombs never lead.
var aim_lead: float = 0.0
## Shots per attack instead of the profile's volley; 0 keeps the profile's (DifficultyCurve.volley_size).
var volley_override: int = 0
## With no farmer token free, shoot the silo instead (true) or hold fire (false: out-of-reach throws).
var silo_fallback: bool = true
## Returns the target to aim at next: a farmer, the silo, or null to hold fire. Defaults to the robot's
## ranged_target().
var target_provider: Callable

var _muzzle: Node3D
var _timer: float = 0.0
var _charge: float = 0.0
var _shots_left: int = 0
var _aim_point: Vector3
var _aim_locked: bool = false
var _pending: int = 0
var _release_left: float = 0.0


## `muzzle` is where shots leave and the glow that charges.
func setup(owner_robot: Robot, attack: AttackProfile, muzzle: Node3D) -> void:
	robot = owner_robot
	profile = attack
	_muzzle = muzzle
	if _muzzle != null:
		_muzzle.visible = false
	target_provider = robot.ranged_target
	robot.destroyed.connect(_on_robot_destroyed)


## Robot shots flying right now.
static func projectiles_in_flight() -> int:
	for i in range(_flying.size() - 1, -1, -1):
		var projectile := _flying[i][0] as Projectile
		if not is_instance_valid(projectile) or not projectile.is_active or projectile.launches != int(_flying[i][1]):
			_flying.remove_at(i)
	return _flying.size()


func step(delta: float) -> void:
	_tick_release(delta)
	match state:
		State.READY:
			if projectiles_in_flight() >= MAX_PROJECTILES:
				return
			var next: Node3D = target_provider.call() if target_provider.is_valid() else null
			if next == null:
				return
			_begin_charge(next)
		State.CHARGING:
			if not _target_valid():
				cancel()
				return
			_timer -= delta
			var t := 1.0 - maxf(0.0, _timer) / _charge
			if not _aim_locked:
				_aim_point = aim_point(target)
				if profile.kind == AttackProfile.Kind.RAIL and _timer <= profile.aim_lock_time:
					_aim_locked = true
			robot._face(_aim_point)
			if _muzzle != null:
				_muzzle.scale = Vector3.ONE * (0.5 + 0.5 * t)
			_update_telegraph(t)
			if _timer <= 0.0:
				if _muzzle != null:
					_muzzle.visible = false
				if telegraph != null:
					telegraph.lock()
				_shots_left = volley_count()
				_fire_next()
		State.FIRING:
			_timer -= delta
			if _timer <= 0.0:
				_fire_next()
		State.RECOVER:
			_timer -= delta
			if _timer <= 0.0:
				state = State.READY
				robot.ai_state = Robot.AiState.SEEK
				finished.emit()


## Stops a charge in progress (the robot started climbing, died, or lost its target). Shots already flying
## keep going.
func cancel() -> void:
	if state == State.CHARGING:
		if _muzzle != null:
			_muzzle.visible = false
		_clear_telegraph()
		AttackTokens.release(self)
		state = State.READY
		if robot.ai_state != Robot.AiState.DEAD:
			robot.ai_state = Robot.AiState.SEEK


## A destroyed robot stops charging and frees its token at once; shots already flying keep going.
func _on_robot_destroyed(_robot: Robot, _killer: Node) -> void:
	cancel()
	AttackTokens.release(self)


func _exit_tree() -> void:
	AttackTokens.release(self)
	# A circle for a shot that is still falling stays until it lands; anything else goes now.
	if telegraph != null and is_instance_valid(telegraph) and _pending > 0 and telegraph.locked:
		get_tree().create_timer(maxf(0.1, _release_left), true, true).timeout.connect(telegraph.finish)
		telegraph = null
	_clear_telegraph()


## Where a shot at `node` aims: above a farmer's feet or up the silo. Straight shots lead a moving farmer by
## aim_lead; lobs never track.
func aim_point(node: Node3D) -> Vector3:
	if not is_farmer(node):
		return node.global_position + Vector3.UP * profile.aim_height_silo
	var point := node.global_position + Vector3.UP * profile.aim_height_farmer
	if aim_lead <= 0.0 or profile.kind != AttackProfile.Kind.STRAIGHT:
		return point
	var moving: Variant = node.get(&"velocity")
	if not moving is Vector3:
		return point
	var flight := _muzzle_position().distance_to(point) / maxf(1.0, profile.speed)
	return point + (moving as Vector3) * flight * aim_lead


## Shots per attack: the volley override, or the profile's.
func volley_count() -> int:
	return maxi(1, volley_override if volley_override > 0 else profile.volley)


static func is_farmer(node: Node) -> bool:
	return node != null and node.is_in_group(&"players")


## The velocity a shot leaves at to reach `to` from `from`, and its flight time: [Vector3, float].
func launch(from: Vector3, to: Vector3) -> Array:
	var offset := to - from
	match profile.kind:
		AttackProfile.Kind.RAIL:
			return [offset.normalized() * profile.speed, profile.attack_range / maxf(1.0, profile.speed)]
		AttackProfile.Kind.BOMB:
			var drift := Vector3(robot.velocity.x, 0.0, robot.velocity.z)
			var fall := maxf(0.1, from.y - to.y)
			return [drift, sqrt(2.0 * fall / maxf(0.1, profile.gravity))]
	var horizontal := Vector2(offset.x, offset.z).length()
	var flight_time := maxf(0.35, horizontal / profile.speed)
	var velocity := offset / flight_time
	velocity.y += 0.5 * profile.gravity * flight_time
	return [velocity, flight_time]


func _begin_charge(next: Node3D) -> void:
	target = next
	if is_farmer(target) and not AttackTokens.acquire(target, self, token_limit):
		# Enough robots are already shooting this farmer: shoot the silo instead, or hold fire.
		target = GameState.silo if silo_fallback else null
		if target == null:
			return
	state = State.CHARGING
	robot.ai_state = Robot.AiState.WINDUP
	_charge = profile.effective_charge_time(charge_multiplier)
	_timer = _charge
	_aim_locked = false
	_aim_point = aim_point(target)
	if _muzzle != null:
		_muzzle.visible = true
		_muzzle.scale = Vector3.ONE * 0.5
	_clear_telegraph()
	var radius := maxf(MIN_CIRCLE_RADIUS, profile.splash_radius)
	telegraph = AttackTelegraph.create(robot, profile.telegraph(), radius)
	_update_telegraph(0.0)
	if is_farmer(target):
		var flight: float = launch(_muzzle_position(), _aim_point)[1]
		EventBus.robot_shot_incoming.emit(robot, target, _charge + flight, _off_screen())


## Fires the next shot of the volley, then waits volley_gap for the one after or recovers.
func _fire_next() -> void:
	_fire_one()
	_shots_left -= 1
	if _shots_left > 0:
		state = State.FIRING
		_timer = profile.volley_gap
		return
	state = State.RECOVER
	robot.ai_state = Robot.AiState.RECOVER
	_timer = maxf(0.0, profile.interval - _charge - profile.volley_gap * (volley_count() - 1))
	fired.emit()


func _fire_one() -> void:
	var from := _muzzle_position()
	var shot := launch(from, _aim_point)
	var velocity: Vector3 = shot[0]
	var flight_time: float = shot[1]
	var exclude: Array[RID] = [robot.get_rid()]
	var projectile := ProjectilePool.of(robot).launch(from, velocity, profile.gravity, flight_time + 1.0,
			PROJECTILE_MASK, exclude, _on_projectile_hit, profile.color, profile.projectile_radius)
	_flying.append([projectile, projectile.launches])
	_pending += 1
	_release_left = maxf(_release_left, flight_time + 1.0)
	Fx.puff(robot, from, profile.color, 0.3, 0.2)
	if telegraph != null and telegraph.kind == &"aim_line":
		var line := telegraph
		telegraph = null
		robot.get_tree().create_timer(0.15, true, true).timeout.connect(line.finish)


func _on_projectile_hit(hit: Dictionary) -> bool:
	var collider := hit["collider"] as Node
	var at: Vector3 = hit["position"]
	var damage := robot.damage_multiplier if is_instance_valid(robot) else 1.0
	var source: Node = robot if is_instance_valid(robot) else null
	if is_farmer(collider) and collider.has_method(&"take_damage"):
		collider.call(&"take_damage", DamagePacket.create(profile.damage_vs_farmer * damage, source, at))
	elif collider is Silo:
		(collider as Silo).take_damage(DamagePacket.create(profile.damage_vs_silo * damage, source, at))
	if profile.splash_radius > 0.0:
		_splash(at, collider, damage, source)
	if is_instance_valid(robot):
		Fx.puff(robot, at, Color(1.0, 0.65, 0.2), maxf(0.35, profile.splash_radius * 0.5), 0.2)
	_shot_done()
	return false


## Splash damage to farmers within splash_radius of the impact (not the one hit directly), falling off
## to half at the edge, and to the silo if its wall is in range.
func _splash(at: Vector3, direct: Node, damage: float, source: Node) -> void:
	for node in robot.get_tree().get_nodes_in_group(&"players"):
		var farmer := node as Node3D
		if farmer == null or farmer == direct or not farmer.has_method(&"take_damage"):
			continue
		var distance := (farmer.global_position + Vector3.UP * 0.9).distance_to(at)
		if distance <= profile.splash_radius:
			var falloff := maxf(0.5, 1.0 - distance / profile.splash_radius)
			farmer.call(&"take_damage", DamagePacket.create(profile.damage_vs_farmer * damage * falloff, source, at))
	var silo := GameState.silo
	if silo != null and direct != silo and silo.distance_to_wall(at) <= profile.splash_radius:
		silo.take_damage(DamagePacket.create(profile.damage_vs_silo * damage * 0.5, source, at))


func _shot_done() -> void:
	_pending = maxi(0, _pending - 1)
	if _pending == 0:
		_release_left = 0.0
		AttackTokens.release(self)
		if state != State.CHARGING:
			_clear_telegraph()


## Gives the token back and clears the circle once every shot has had time to land, hit or not.
func _tick_release(delta: float) -> void:
	if _release_left <= 0.0:
		return
	_release_left -= delta
	if _release_left <= 0.0:
		_pending = 0
		AttackTokens.release(self)
		if state != State.CHARGING:
			_clear_telegraph()


func _update_telegraph(progress: float) -> void:
	if telegraph == null:
		return
	telegraph.set_progress(progress)
	match telegraph.kind:
		&"aim_line":
			telegraph.stretch(_muzzle_position(), _aim_point)
		&"bomb_shadow":
			var from := _muzzle_position()
			var ground := _ground_below(_aim_point)
			var fall: float = launch(from, ground[0])[1]
			var drift := Vector3(robot.velocity.x, 0.0, robot.velocity.z) * (fall + maxf(0.0, _timer))
			var landing := _ground_below(Vector3(from.x, from.y, from.z) + drift)
			telegraph.place(landing[0], landing[1])
		_:
			if is_farmer(target):
				var ground := _ground_below(target.global_position + Vector3.UP * 0.5)
				telegraph.place(ground[0], ground[1])
			elif target is Silo:
				var silo := target as Silo
				var wall := silo.wall_point_toward(robot.global_position, profile.aim_height_silo)
				telegraph.place(wall, wall - Vector3(silo.global_position.x, wall.y, silo.global_position.z))
			else:
				telegraph.place(_aim_point)


## The ground under `point`: [position, normal]. Falls back to the point itself over nothing.
func _ground_below(point: Vector3) -> Array:
	var space := robot.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * 60.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return [Vector3(point.x, 0.0, point.z), Vector3.UP]
	return [hit["position"], hit["normal"]]


func _target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return not (target.has_method(&"is_alive") and not target.call(&"is_alive"))


func _muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle != null else robot.global_position + Vector3.UP


func _off_screen() -> bool:
	var camera := robot.get_viewport().get_camera_3d() if robot.is_inside_tree() else null
	return camera != null and not camera.is_position_in_frustum(robot.global_position)


func _clear_telegraph() -> void:
	if telegraph != null and is_instance_valid(telegraph):
		telegraph.finish()
	telegraph = null
