class_name FarmerMovement
extends Node
## The farmer's feet (GDD 5.3, 5.4, 4.5): run, jump with coyote time and a jump buffer, the milk-can
## jetpack with Hover Mode, ladders, mantling onto landings, ziplines and knockback.
## Writes Farmer.state; the Farmer calls physics_step() once per physics frame, before repair, interaction
## and weapons, so they see this frame's state.

signal landed(fall_speed: float)

@export_group("Movement (GDD 5.3)")
@export var run_speed: float = 7.0
@export var aim_walk_speed: float = 4.0
@export var jump_height: float = 1.3
@export var gravity: float = 22.0
@export var ground_acceleration: float = 60.0
## Fraction of ground acceleration available in the air.
@export var air_control: float = 0.6
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var max_fall_speed: float = 40.0

@export_group("Climbing (GDD 4.5)")
@export var mantle_speed: float = 7.0
## After letting go of a ladder or zipline, ignore it for this long so you don't re-grab it instantly.
@export var regrab_delay: float = 0.4

@export_group("Jetpack (GDD 13.4)")
## Hover Mode burns fuel at this fraction of the thrust rate.
@export var hover_fuel_drain: float = 0.4

var is_hovering: bool = false
## The ladder being climbed.
var climbable: Climbable = null

var farmer: Farmer

var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _climbables: Array[Climbable] = []
var _regrab_left: float = 0.0
var _mantle_from: Vector3 = Vector3.ZERO
var _mantle_to: Vector3 = Vector3.ZERO
var _mantle_t: float = 0.0
var _mantle_duration: float = 0.3
var _zipline: Zipline = null
var _zip_distance: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _was_on_floor: bool = true


func setup(owner_farmer: Farmer) -> void:
	farmer = owner_farmer


func physics_step(delta: float, move: Vector2, wish: Vector3) -> void:
	_regrab_left = maxf(0.0, _regrab_left - delta)
	match farmer.state:
		Farmer.State.CLIMBING:
			_process_climb(move)
		Farmer.State.MANTLING:
			_process_mantle(delta)
		Farmer.State.ZIPLINING:
			_process_zipline(delta)
		_:
			_process_free_move(delta, wish)


## Falls straight down, for a farmer who is down.
func fall(delta: float) -> void:
	farmer.velocity = Vector3(0.0, farmer.velocity.y - gravity * delta, 0.0)
	farmer.move_and_slide()


func add_knockback(impulse: Vector3) -> void:
	_knockback += impulse


func _process_free_move(delta: float, wish: Vector3) -> void:
	var input := farmer.input
	var jetpack := farmer.jetpack
	var repairing := farmer.repair.is_repairing
	var grounded := farmer.is_on_floor()
	if grounded:
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if input.is_just_pressed(&"jump"):
		_jump_buffer_left = jump_buffer_time

	if _try_start_climb(wish, grounded):
		return

	var speed := 0.0 if repairing else (aim_walk_speed if farmer.is_aiming else StatService.get_stat(&"player.run_speed", run_speed))
	var target_velocity := wish * speed
	var accel := ground_acceleration * (1.0 if grounded else air_control)
	var velocity := farmer.velocity

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0 and not repairing:
		velocity.y = sqrt(2.0 * gravity * StatService.get_stat(&"player.jump_height", jump_height))
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		grounded = false

	# Hold Jump in the air to thrust once the jump's own upward speed has bled off. Hover Mode: hold
	# Jump while aiming to hang in the air at 40% fuel drain.
	var climb_rate := jetpack.climb_rate()
	var holding_jump := not grounded and input.is_pressed(&"jump")
	is_hovering = holding_jump and farmer.is_aiming and StatService.has_flag(&"jetpack.hover")
	var wants_thrust := holding_jump and (is_hovering or velocity.y <= climb_rate + 0.01)
	var thrusting := jetpack.update(delta, grounded, wants_thrust, hover_fuel_drain if is_hovering else 1.0)
	is_hovering = is_hovering and thrusting
	if thrusting:
		var target_vertical := 0.0 if is_hovering else climb_rate
		velocity.y = move_toward(velocity.y, target_vertical, jetpack.thrust_acceleration * delta)
		target_velocity = wish * jetpack.air_speed()
	elif not grounded:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_velocity, accel * delta)
	farmer.velocity = Vector3(horizontal.x, velocity.y, horizontal.z) + _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	var falling_speed := -farmer.velocity.y
	farmer.move_and_slide()

	if farmer.is_on_floor():
		if not _was_on_floor:
			landed.emit(falling_speed)
		farmer.state = Farmer.State.GROUNDED
	else:
		farmer.state = Farmer.State.JETPACKING if thrusting else Farmer.State.AIRBORNE
	_was_on_floor = farmer.is_on_floor()


# --- Ladders (GDD 4.5) ----------------------------------------------------------------------------

func _try_start_climb(wish: Vector3, grounded: bool) -> bool:
	if _climbables.is_empty() or _regrab_left > 0.0 or farmer.repair.is_repairing or wish.length() < 0.3:
		return false
	var dir := wish.normalized()
	for ladder in _climbables:
		var toward_wall := dir.dot(-ladder.outward())
		var height := ladder.height_above_base(farmer.global_position)
		var start := false
		if grounded and height < 0.6:
			start = toward_wall > 0.5  # At the foot: walk into the ladder.
		elif grounded:
			start = toward_wall < -0.5  # On a landing or the top: walk out over the edge onto it.
		else:
			start = absf(toward_wall) > 0.5 and farmer.velocity.y <= 2.0  # Grab it mid-air.
		if start and height <= ladder.climb_height + 0.3:
			_start_climb(ladder)
			return true
	return false


func _start_climb(ladder: Climbable) -> void:
	climbable = ladder
	farmer.state = Farmer.State.CLIMBING
	farmer.velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	farmer.jetpack.set_thrusting(false)


## Lets go of a ladder or zipline (or cuts a mantle short) and flies off at `new_velocity`.
func release(new_velocity: Vector3) -> void:
	climbable = null
	_zipline = null
	_regrab_left = regrab_delay
	farmer.velocity = new_velocity
	farmer.state = Farmer.State.AIRBORNE
	_was_on_floor = false


func _process_climb(move: Vector2) -> void:
	var ladder := climbable
	if ladder == null or not is_instance_valid(ladder):
		release(Vector3.ZERO)
		return
	var out := ladder.outward()
	var height := ladder.height_above_base(farmer.global_position)
	var climb_velocity := -move.y * ladder.climb_speed

	if farmer.input.is_just_pressed(&"jump"):
		var landing := ladder.landing_near(height)
		if not is_nan(landing):
			_start_mantle(ladder.landing_exit_point(landing))
		else:
			release(out * 4.0 + Vector3.UP * 4.5)
		return
	if height >= ladder.climb_height and climb_velocity > 0.0:
		_start_mantle(ladder.top_exit_point())
		return
	if height <= 0.05 and climb_velocity < 0.0:
		release(Vector3.ZERO)
		return

	var line := ladder.line_position(height)
	var pull := Vector3(line.x - farmer.global_position.x, 0.0, line.z - farmer.global_position.z) * 12.0
	farmer.velocity = pull + Vector3.UP * climb_velocity
	farmer.move_and_slide()
	farmer.facing_yaw = atan2(out.x, out.z)


func _start_mantle(to: Vector3) -> void:
	climbable = null
	farmer.state = Farmer.State.MANTLING
	farmer.velocity = Vector3.ZERO
	_mantle_from = farmer.global_position
	_mantle_to = to
	_mantle_t = 0.0
	_mantle_duration = clampf(_mantle_from.distance_to(_mantle_to) / mantle_speed, 0.25, 1.0)


func _process_mantle(delta: float) -> void:
	_mantle_t = minf(1.0, _mantle_t + delta / _mantle_duration)
	farmer.global_position = _mantle_from.lerp(_mantle_to, _mantle_t) + Vector3.UP * sin(_mantle_t * PI) * 0.6
	if _mantle_t >= 1.0:
		farmer.state = Farmer.State.GROUNDED
		_regrab_left = regrab_delay
		farmer.velocity = Vector3.ZERO


func add_climbable(ladder: Climbable) -> void:
	if ladder not in _climbables:
		_climbables.append(ladder)


func remove_climbable(ladder: Climbable) -> void:
	_climbables.erase(ladder)
	if ladder == climbable and farmer.state == Farmer.State.CLIMBING:
		release(Vector3.ZERO)


## True while climbing within step-off range of a landing (the HUD shows a prompt).
func can_step_off_ladder() -> bool:
	return farmer.state == Farmer.State.CLIMBING and climbable != null \
			and not is_nan(climbable.landing_near(climbable.height_above_base(farmer.global_position)))


# --- Ziplines (GDD 4.5) ---------------------------------------------------------------------------

func start_zipline(line: Zipline) -> void:
	if farmer.state == Farmer.State.ZIPLINING or _regrab_left > 0.0:
		return
	_zipline = line
	_zip_distance = 0.0
	farmer.state = Farmer.State.ZIPLINING
	farmer.velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	farmer.jetpack.set_thrusting(false)
	farmer.global_position = line.rider_position(0.0)


func _process_zipline(delta: float) -> void:
	var line := _zipline
	if line == null or not is_instance_valid(line):
		release(Vector3.ZERO)
		return
	var speed := line.ride_speed()
	var dir := line.direction()
	_zip_distance += speed * delta
	farmer.global_position = line.rider_position(_zip_distance)
	farmer.velocity = dir * speed
	var flat := Vector3(dir.x, 0.0, dir.z)
	farmer.facing_yaw = atan2(-flat.x, -flat.z)
	if farmer.input.is_just_pressed(&"jump"):
		release(flat * speed * 0.8 + Vector3.UP * 3.0)
	elif _zip_distance >= line.length():
		release(flat * speed * 0.3 + Vector3.UP * 1.0)


func zipline_progress() -> float:
	if farmer.state != Farmer.State.ZIPLINING or _zipline == null:
		return 0.0
	return clampf(_zip_distance / _zipline.length(), 0.0, 1.0)
