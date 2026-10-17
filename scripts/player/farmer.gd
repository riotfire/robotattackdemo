class_name Farmer
extends CharacterBody3D
## The farmer, Pip (GDD 5): run, jump with coyote time and a jump buffer, the milk-can jetpack (with
## Hover Mode), ladders, ziplines, wrench and pistol, body armor, hold-to-repair on silo cracks and
## Interact for the bell, the shed and ziplines.
## Base values live here; StatService applies purchased upgrades on top (GDD 18.4).
## Co-op ready (GDD 18.8): no singleton. Registers with GameState and reads input only via its InputRouter.

enum State { GROUNDED, AIRBORNE, JETPACKING, CLIMBING, MANTLING, ZIPLINING, DEAD }

## Collision layers the aim ray can hit: World, RobotHurtbox, Silo.
const AIM_MASK: int = 1 | (1 << 4) | (1 << 5)

@export_group("Movement (GDD 5.3)")
@export var run_speed: float = 7.0
## Hold Run (L3) to move this many times faster than run_speed. Not while aiming or repairing.
@export var run_multiplier: float = 1.2
@export var aim_walk_speed: float = 4.0
@export var jump_height: float = 1.3
@export var gravity: float = 22.0
@export var ground_acceleration: float = 60.0
## Fraction of ground acceleration available in the air.
@export var air_control: float = 0.6
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var turn_speed: float = 14.0
@export var max_fall_speed: float = 40.0

@export_group("Health and armor (GDD 3.4, 8.1)")
@export var max_health: float = 100.0
## Armor recharges at this rate after armor_regen_delay seconds without taking damage.
@export var armor_regen_rate: float = 10.0
@export var armor_regen_delay: float = 4.0

@export_group("Repair (GDD 7)")
## Structure per second with the wrench.
@export var repair_rate: float = 20.0
## How close a crack must be to the farmer's chest.
@export var repair_reach: float = 2.5

@export_group("Climbing (GDD 4.5)")
@export var mantle_speed: float = 7.0
## After letting go of a ladder or zipline, ignore it for this long so you don't re-grab it instantly.
@export var regrab_delay: float = 0.4

@export_group("Jetpack (GDD 13.4)")
## Hover Mode burns fuel at this fraction of the thrust rate.
@export var hover_fuel_drain: float = 0.4

var state: State = State.GROUNDED
var is_aiming: bool = false
var is_repairing: bool = false
var is_hovering: bool = false
## The crack in reach, if any (highlighted in the world).
var repair_target: SiloCrack = null
## The bell, shed door or zipline in reach, if any.
var focus_interactable: Interactable = null
## 0..1 progress while holding Interact on a hold-to-use interactable.
var interact_progress: float = 0.0
var current_weapon: Weapon = null
var weapons: Array[Weapon] = []
## The ladder being climbed.
var climbable: Climbable = null
var armor: float = 0.0
var max_armor: float = 0.0

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
var _interact_hold: float = 0.0
var _interact_needs_release: bool = false
var _facing_yaw: float = 0.0
var _combat_facing_left: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _hurt_flash_left: float = 0.0
var _since_damage: float = 99.0
var _land_squash_left: float = 0.0
var _was_on_floor: bool = true
var _pose_frame: int = 0

@onready var input: InputRouter = $InputRouter
@onready var health: HealthComponent = $Health
@onready var jetpack: Jetpack = $Jetpack
@onready var camera_rig: FarmerCamera = $CameraRig
@onready var model: Node3D = $Model
@onready var wrench: Wrench = $Model/WeaponHolder/Wrench
@onready var pistol: Pistol = $Model/WeaponHolder/Pistol
@onready var _pose: Node3D = $Model/Pose
@onready var _jetpack_can: Node3D = $Model/JetpackCan
@onready var _jet_flame: Node3D = $Model/JetpackCan/Flame
@onready var _body_mesh: MeshInstance3D = $Model/Pose/Body


func _ready() -> void:
	add_to_group(&"players")
	weapons = [wrench, pistol]
	for weapon in weapons:
		weapon.setup(self)
	health.reset(StatService.get_stat(&"player.max_hp", max_health))
	max_armor = StatService.get_stat(&"player.armor", 0.0)
	armor = max_armor
	equip(1 if is_weapon_available(pistol) else 0)
	health.died.connect(_on_died)
	StatService.stats_changed.connect(_on_stats_changed)
	StopMotionClock.tick_24.connect(_on_tick_24)
	camera_rig.attach(self)
	if input.player_index == 0:
		camera_rig.camera.make_current()
	_facing_yaw = global_rotation.y
	GameState.register_player(self)


func _exit_tree() -> void:
	GameState.unregister_player(self)


func _physics_process(delta: float) -> void:
	_regrab_left = maxf(0.0, _regrab_left - delta)
	_combat_facing_left = maxf(0.0, _combat_facing_left - delta)
	_hurt_flash_left = maxf(0.0, _hurt_flash_left - delta)
	_land_squash_left = maxf(0.0, _land_squash_left - delta)
	if state == State.DEAD:
		velocity = Vector3(0.0, velocity.y - gravity * delta, 0.0)
		move_and_slide()
		return
	_update_armor(delta)

	var move := input.move_vector()
	var wish := camera_rig.flat_basis() * Vector3(move.x, 0.0, move.y)
	is_aiming = input.is_pressed(&"aim") and _can_use_weapons()

	match state:
		State.CLIMBING:
			_process_climb(move)
		State.MANTLING:
			_process_mantle(delta)
		State.ZIPLINING:
			_process_zipline(delta)
		_:
			_process_free_move(delta, wish)

	_update_repair(delta)
	_update_interaction(delta)
	_update_weapons()
	_update_model(delta, wish)


# --- Movement -------------------------------------------------------------------------------------

func _process_free_move(delta: float, wish: Vector3) -> void:
	var grounded := is_on_floor()
	if grounded:
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if input.is_just_pressed(&"jump"):
		_jump_buffer_left = jump_buffer_time

	if _try_start_climb(wish, grounded):
		return

	var run := run_multiplier if input.is_pressed(&"run") and not is_aiming else 1.0
	var speed := 0.0 if is_repairing else (aim_walk_speed if is_aiming else StatService.get_stat(&"player.run_speed", run_speed) * run)
	var target_velocity := wish * speed
	var accel := ground_acceleration * (1.0 if grounded else air_control)

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0 and not is_repairing:
		velocity.y = sqrt(2.0 * gravity * StatService.get_stat(&"player.jump_height", jump_height))
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		grounded = false

	# Hold Jump in the air to thrust once the jump's own upward speed has bled off. Hover Mode: hold
	# Jump while aiming to hang in the air at 40% fuel drain.
	var climb_rate := jetpack.climb_rate()
	var holding_jump := not grounded and input.is_pressed(&"jump")
	is_hovering = holding_jump and is_aiming and StatService.has_flag(&"jetpack.hover")
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
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z) + _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	var falling_speed := -velocity.y
	move_and_slide()

	if is_on_floor():
		if not _was_on_floor and falling_speed > 6.0:
			_land_squash_left = 0.12  # Clay squash on landing (GDD 3.4: purely visual).
		state = State.GROUNDED
	else:
		state = State.JETPACKING if thrusting else State.AIRBORNE
	_was_on_floor = is_on_floor()


func _try_start_climb(wish: Vector3, grounded: bool) -> bool:
	if _climbables.is_empty() or _regrab_left > 0.0 or is_repairing or wish.length() < 0.3:
		return false
	var dir := wish.normalized()
	for ladder in _climbables:
		var toward_wall := dir.dot(-ladder.outward())
		var height := ladder.height_above_base(global_position)
		var start := false
		if grounded and height < 0.6:
			start = toward_wall > 0.5  # At the foot: walk into the ladder.
		elif grounded:
			start = toward_wall < -0.5  # On a landing or the top: walk out over the edge onto it.
		else:
			start = absf(toward_wall) > 0.5 and velocity.y <= 2.0  # Grab it mid-air.
		if start and height <= ladder.climb_height + 0.3:
			_start_climb(ladder)
			return true
	return false


func _start_climb(ladder: Climbable) -> void:
	climbable = ladder
	state = State.CLIMBING
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	jetpack.set_thrusting(false)


func _stop_climb(new_velocity: Vector3) -> void:
	climbable = null
	_zipline = null
	_regrab_left = regrab_delay
	velocity = new_velocity
	state = State.AIRBORNE
	_was_on_floor = false


func _process_climb(move: Vector2) -> void:
	var ladder := climbable
	if ladder == null or not is_instance_valid(ladder):
		_stop_climb(Vector3.ZERO)
		return
	var out := ladder.outward()
	var height := ladder.height_above_base(global_position)
	var climb_velocity := -move.y * ladder.climb_speed

	if input.is_just_pressed(&"jump"):
		var landing := ladder.landing_near(height)
		if not is_nan(landing):
			_start_mantle(ladder.landing_exit_point(landing))
		else:
			_stop_climb(out * 4.0 + Vector3.UP * 4.5)
		return
	if height >= ladder.climb_height and climb_velocity > 0.0:
		_start_mantle(ladder.top_exit_point())
		return
	if height <= 0.05 and climb_velocity < 0.0:
		_stop_climb(Vector3.ZERO)
		return

	var line := ladder.line_position(height)
	var pull := Vector3(line.x - global_position.x, 0.0, line.z - global_position.z) * 12.0
	velocity = pull + Vector3.UP * climb_velocity
	move_and_slide()
	_facing_yaw = atan2(out.x, out.z)


func _start_mantle(to: Vector3) -> void:
	climbable = null
	state = State.MANTLING
	velocity = Vector3.ZERO
	_mantle_from = global_position
	_mantle_to = to
	_mantle_t = 0.0
	_mantle_duration = clampf(_mantle_from.distance_to(_mantle_to) / mantle_speed, 0.25, 1.0)


func _process_mantle(delta: float) -> void:
	_mantle_t = minf(1.0, _mantle_t + delta / _mantle_duration)
	global_position = _mantle_from.lerp(_mantle_to, _mantle_t) + Vector3.UP * sin(_mantle_t * PI) * 0.6
	if _mantle_t >= 1.0:
		state = State.GROUNDED
		_regrab_left = regrab_delay
		velocity = Vector3.ZERO


func add_climbable(ladder: Climbable) -> void:
	if ladder not in _climbables:
		_climbables.append(ladder)


func remove_climbable(ladder: Climbable) -> void:
	_climbables.erase(ladder)
	if ladder == climbable and state == State.CLIMBING:
		_stop_climb(Vector3.ZERO)


## True while climbing within step-off range of a landing (the HUD shows a prompt).
func can_step_off_ladder() -> bool:
	return state == State.CLIMBING and climbable != null \
			and not is_nan(climbable.landing_near(climbable.height_above_base(global_position)))


# --- Ziplines (GDD 4.5) ---------------------------------------------------------------------------

func start_zipline(line: Zipline) -> void:
	if state == State.ZIPLINING or _regrab_left > 0.0:
		return
	_zipline = line
	_zip_distance = 0.0
	state = State.ZIPLINING
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	jetpack.set_thrusting(false)
	global_position = line.rider_position(0.0)


func _process_zipline(delta: float) -> void:
	var line := _zipline
	if line == null or not is_instance_valid(line):
		_stop_climb(Vector3.ZERO)
		return
	var speed := line.ride_speed()
	var dir := line.direction()
	_zip_distance += speed * delta
	global_position = line.rider_position(_zip_distance)
	velocity = dir * speed
	var flat := Vector3(dir.x, 0.0, dir.z)
	_facing_yaw = atan2(-flat.x, -flat.z)
	if input.is_just_pressed(&"jump"):
		_stop_climb(flat * speed * 0.8 + Vector3.UP * 3.0)
	elif _zip_distance >= line.length():
		_stop_climb(flat * speed * 0.3 + Vector3.UP * 1.0)


func zipline_progress() -> float:
	if state != State.ZIPLINING or _zipline == null:
		return 0.0
	return clampf(_zip_distance / _zipline.length(), 0.0, 1.0)


# --- Interact: repair and interactables -----------------------------------------------------------

func _update_repair(delta: float) -> void:
	var previous := repair_target
	repair_target = null
	var silo := GameState.silo
	if silo != null and state == State.GROUNDED:
		repair_target = silo.nearest_crack(global_position + Vector3.UP, repair_reach)
	if previous != repair_target and previous != null and is_instance_valid(previous):
		previous.set_highlighted(false)
	if repair_target != null:
		repair_target.set_highlighted(true)
	is_repairing = repair_target != null and input.is_pressed(&"interact")
	if is_repairing:
		var to_crack := repair_target.global_position - global_position
		_facing_yaw = atan2(-to_crack.x, -to_crack.z)
		silo.repair_crack(repair_target, repair_rate_now() * delta)


## Structure per second the wrench restores, after Elbow Grease and Bigger Patches.
func repair_rate_now() -> float:
	return repair_rate * StatService.get_stat(&"repair.speed", 1.0) * StatService.get_stat(&"repair.amount", 1.0)


func _update_interaction(delta: float) -> void:
	focus_interactable = null
	if repair_target == null and state == State.GROUNDED:
		var best_distance := INF
		for node in get_tree().get_nodes_in_group(Interactable.GROUP):
			var candidate := node as Interactable
			var d := candidate.interaction_point().distance_to(global_position)
			if d <= candidate.interact_range and d < best_distance:
				best_distance = d
				focus_interactable = candidate
	var held := input.is_pressed(&"interact")
	if not held:
		_interact_needs_release = false
	if focus_interactable == null or not focus_interactable.can_interact(self) or _interact_needs_release:
		_interact_hold = 0.0
		interact_progress = 0.0
		return
	if focus_interactable.hold_time <= 0.0:
		if input.is_just_pressed(&"interact"):
			_interact_needs_release = true
			focus_interactable.interact(self)
		return
	_interact_hold = _interact_hold + delta if held else 0.0
	interact_progress = clampf(_interact_hold / focus_interactable.hold_time, 0.0, 1.0)
	if _interact_hold >= focus_interactable.hold_time:
		_interact_hold = 0.0
		interact_progress = 0.0
		_interact_needs_release = true
		focus_interactable.interact(self)


# --- Weapons --------------------------------------------------------------------------------------

func is_weapon_available(weapon: Weapon) -> bool:
	return weapon != pistol or StatService.has_flag(&"pistol.unlocked")


func equip(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
	if not is_weapon_available(weapons[index]):
		EventBus.hud_message.emit("Buy the %s at the tool shed pegboard first" % weapons[index].display_name, 2.0)
		return
	current_weapon = weapons[index]
	for weapon in weapons:
		weapon.set_equipped(weapon == current_weapon)


func _can_use_weapons() -> bool:
	return state in [State.GROUNDED, State.AIRBORNE, State.JETPACKING, State.ZIPLINING] and not is_repairing


## While ziplining only the pistol works, unless Zipline Grip 2 is owned (GDD 13.4).
func _weapon_usable_now(weapon: Weapon) -> bool:
	if state != State.ZIPLINING:
		return true
	return weapon == pistol or StatService.has_flag(&"zipline.any_weapon")


func _update_weapons() -> void:
	var index := weapons.find(current_weapon)
	if input.is_just_pressed(&"weapon_1"):
		equip(0)
	elif input.is_just_pressed(&"weapon_2"):
		equip(1)
	elif input.is_just_pressed(&"weapon_next") or input.is_just_pressed(&"weapon_prev"):
		var step := 1 if input.is_just_pressed(&"weapon_next") else -1
		for i in range(1, weapons.size()):
			var candidate := posmod(index + step * i, weapons.size())
			if is_weapon_available(weapons[candidate]):
				equip(candidate)
				break

	if not _can_use_weapons():
		return
	if input.is_just_pressed(&"melee") and _weapon_usable_now(wrench):
		if wrench.swing():
			_combat_facing_left = 0.5
	var fire_pressed := input.is_just_pressed(&"fire")
	var fire_held := input.is_pressed(&"fire")
	if fire_held:
		_combat_facing_left = 0.6
	if _weapon_usable_now(current_weapon):
		current_weapon.trigger(fire_pressed, fire_held)
	if input.is_just_pressed(&"reload") and repair_target == null and focus_interactable == null:
		current_weapon.reload()


## Outgoing damage multiplier: Death From Above while airborne (GDD 13.4).
func damage_multiplier() -> float:
	if state in [State.AIRBORNE, State.JETPACKING, State.ZIPLINING]:
		return StatService.get_stat(&"combat.airborne_damage", 1.0)
	return 1.0


## Flat direction the camera faces.
func aim_forward_flat() -> Vector3:
	return camera_rig.flat_forward()


## Flat direction from the farmer to whatever the crosshair is on, within max_distance. Melee uses this
## because up close the shoulder offset swings the camera's own forward up to ~30 degrees off target.
func aim_direction_flat(max_distance: float) -> Vector3:
	var to_aim := get_aim_point(max_distance) - global_position
	to_aim.y = 0.0
	if to_aim.length() < 0.3:
		return camera_rig.flat_forward()
	return to_aim.normalized()


## Where the camera-center ray lands, out to max_distance past the farmer (GDD 5.3).
func get_aim_point(max_distance: float) -> Vector3:
	var camera := camera_rig.camera
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	var reach := max_distance + origin.distance_to(global_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, AIM_MASK, [get_rid()])
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return origin + dir * reach
	return hit["position"]


# --- Health and armor -----------------------------------------------------------------------------

func take_damage(packet: DamagePacket) -> void:
	if state == State.DEAD or GameState.god_mode:
		return
	_since_damage = 0.0
	var amount := packet.amount
	var absorbed := minf(armor, amount)
	armor -= absorbed
	amount -= absorbed
	if health.apply_damage(amount) > 0.0 or absorbed > 0.0:
		_hurt_flash_left = 0.2
	if packet.knockback != Vector3.ZERO and state in [State.GROUNDED, State.AIRBORNE, State.JETPACKING]:
		_knockback += packet.knockback


func heal(amount: float) -> void:
	health.heal(amount)


func is_alive() -> bool:
	return state != State.DEAD


func teleport_to(where: Vector3) -> void:
	if state in [State.CLIMBING, State.MANTLING, State.ZIPLINING]:
		_stop_climb(Vector3.ZERO)
	global_position = where
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _update_armor(delta: float) -> void:
	_since_damage += delta
	if armor < max_armor and _since_damage >= StatService.get_stat(&"player.armor_regen_delay", armor_regen_delay):
		armor = minf(max_armor, armor + StatService.get_stat(&"player.armor_regen_rate", armor_regen_rate) * delta)


func _on_stats_changed() -> void:
	var new_max := StatService.get_stat(&"player.max_hp", max_health)
	if not is_equal_approx(new_max, health.max_health):
		var gained := new_max - health.max_health
		health.max_health = new_max
		health.heal(maxf(0.0, gained))
	var new_armor := StatService.get_stat(&"player.armor", 0.0)
	if new_armor > max_armor:
		armor = new_armor
	max_armor = new_armor
	armor = minf(armor, max_armor)
	if current_weapon == wrench and is_weapon_available(pistol) and pistol.ammo >= 0:
		equip(1)


func _on_died() -> void:
	state = State.DEAD
	jetpack.set_thrusting(false)
	model.rotation.x = deg_to_rad(-80.0)
	GameState.trigger_game_over(&"farmer")


# --- Presentation ---------------------------------------------------------------------------------

func _update_model(delta: float, wish: Vector3) -> void:
	if state not in [State.CLIMBING, State.ZIPLINING] and not is_repairing:
		if is_aiming or _combat_facing_left > 0.0:
			_facing_yaw = camera_rig.yaw
		elif Vector2(wish.x, wish.z).length() > 0.1:
			_facing_yaw = atan2(-wish.x, -wish.z)
	model.rotation.y = lerp_angle(model.rotation.y, _facing_yaw, 1.0 - exp(-turn_speed * delta))
	_jetpack_can.visible = GameState.jetpack_unlocked
	_jet_flame.visible = jetpack.is_thrusting
	_body_mesh.set_instance_shader_parameter(&"emission_strength", 0.8 if _hurt_flash_left > 0.0 else 0.0)


## Squash, stretch and run bob are posed "on ones" at 24 fps (GDD 15.4); facing and the root stay smooth.
func _on_tick_24(_frame: int) -> void:
	if state == State.DEAD:
		return
	_pose_frame += 1
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if _land_squash_left > 0.0:
		_pose.scale = Vector3(1.18, 0.82, 1.18)
		_pose.position.y = 0.0
	elif state == State.JETPACKING:
		_pose.scale = Vector3(0.94, 1.08, 0.94)
		_pose.position.y = 0.0
	elif state == State.GROUNDED and horizontal_speed > 1.0:
		var step := _pose_frame % 4
		_pose.scale = Vector3(1.03, 0.97, 1.03) if step == 0 else Vector3.ONE
		_pose.position.y = 0.05 if step == 2 else 0.0
	else:
		_pose.scale = Vector3.ONE
		_pose.position.y = 0.0
