class_name Farmer
extends CharacterBody3D
## The farmer, Pip (GDD 5). Holds the shared state chart, health and body armor, aiming and presentation;
## the work happens in child components, ticked in a fixed order every physics frame:
##   Movement (run, jump, jetpack, Hover Mode, ladders, ziplines) -> Repair (hold Interact on a crack)
##   -> Interaction (bell, shed, ziplines) -> WeaponHolder (weapons, the weapon wheel, melee, reload).
## Base values live on the components; StatService applies purchased upgrades on top (GDD 18.4).
## Co-op ready (GDD 18.8): no singleton. Registers with GameState and reads input only via its InputRouter.

enum State { GROUNDED, AIRBORNE, JETPACKING, CLIMBING, MANTLING, ZIPLINING, DEAD }

## Collision layers the aim ray can hit: World, RobotHurtbox, Silo.
const HURT_FLASH_SECONDS: float = 0.3
const HURT_TINT := Color(1.0, 0.12, 0.1)
## Metres the model jitters at the start of a hit.
const HURT_SHAKE: float = 0.12
const AIM_MASK: int = 1 | (1 << 4) | (1 << 5)

@export var turn_speed: float = 14.0

@export_group("Health and armor (GDD 3.4, 8.1)")
@export var max_health: float = 100.0
## Armor recharges at this rate after armor_regen_delay seconds without taking damage.
@export var armor_regen_rate: float = 10.0
@export var armor_regen_delay: float = 4.0

var state: State = State.GROUNDED
var is_aiming: bool = false
var armor: float = 0.0
var max_armor: float = 0.0
## Where the model turns to. Components set it while climbing, ziplining or repairing.
var facing_yaw: float = 0.0

var _combat_facing_left: float = 0.0
var _hurt_flash_left: float = 0.0
var _model_rest_position: Vector3
var _rest_tints: Dictionary = {}
var _since_damage: float = 99.0
var _land_squash_left: float = 0.0
var _pose_frame: int = 0

@onready var input: InputRouter = $InputRouter
@onready var health: HealthComponent = $Health
@onready var jetpack: Jetpack = $Jetpack
@onready var movement: FarmerMovement = $Movement
@onready var repair: FarmerRepair = $Repair
@onready var interaction: FarmerInteraction = $Interaction
@onready var weapons: WeaponHolder = $Model/WeaponHolder
@onready var camera_rig: FarmerCamera = $CameraRig
@onready var model: Node3D = $Model
@onready var _pose: Node3D = $Model/Pose
@onready var _jetpack_can: Node3D = $Model/JetpackCan
@onready var _jet_flame: Node3D = $Model/JetpackCan/Flame
@onready var _body_mesh: MeshInstance3D = $Model/Pose/Body


func _ready() -> void:
	_model_rest_position = model.position
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var rest: Variant = mesh.get_instance_shader_parameter(&"tint")
		if rest is Color:
			_rest_tints[mesh] = rest
	add_to_group(&"players")
	movement.setup(self)
	repair.setup(self)
	interaction.setup(self)
	weapons.setup(self)
	movement.landed.connect(_on_landed)
	health.reset(StatService.get_stat(&"player.max_hp", max_health))
	max_armor = StatService.get_stat(&"player.armor", 0.0)
	armor = max_armor
	health.died.connect(_on_died)
	StatService.stats_changed.connect(_on_stats_changed)
	StopMotionClock.tick_24.connect(_on_tick_24)
	camera_rig.attach(self)
	if input.player_index == 0:
		camera_rig.camera.make_current()
	facing_yaw = global_rotation.y
	GameState.register_player(self)


func _exit_tree() -> void:
	GameState.unregister_player(self)


func _physics_process(delta: float) -> void:
	_combat_facing_left = maxf(0.0, _combat_facing_left - delta)
	_hurt_flash_left = maxf(0.0, _hurt_flash_left - delta)
	_land_squash_left = maxf(0.0, _land_squash_left - delta)
	if state == State.DEAD:
		movement.fall(delta)
		return
	_update_armor(delta)

	var move := input.move_vector()
	var wish := camera_rig.flat_basis() * Vector3(move.x, 0.0, move.y)
	is_aiming = input.is_pressed(&"aim") and can_use_weapons()

	movement.physics_step(delta, move, wish)
	repair.physics_step(delta)
	interaction.physics_step(delta)
	weapons.physics_step(delta)
	_update_model(delta, wish)


func can_use_weapons() -> bool:
	return state in [State.GROUNDED, State.AIRBORNE, State.JETPACKING, State.ZIPLINING] and not repair.is_repairing


## Turns the model to the camera for `seconds`, so swings and shots go where the crosshair is.
func face_combat(seconds: float) -> void:
	_combat_facing_left = maxf(_combat_facing_left, seconds)


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


# --- Ladders: called by Climbable areas -----------------------------------------------------------

func add_climbable(ladder: Climbable) -> void:
	movement.add_climbable(ladder)


func remove_climbable(ladder: Climbable) -> void:
	movement.remove_climbable(ladder)


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
		_hurt_flash_left = HURT_FLASH_SECONDS
	if packet.knockback != Vector3.ZERO and state in [State.GROUNDED, State.AIRBORNE, State.JETPACKING]:
		movement.add_knockback(packet.knockback)


func heal(amount: float) -> void:
	health.heal(amount)


func is_alive() -> bool:
	return state != State.DEAD


func teleport_to(where: Vector3) -> void:
	if state in [State.CLIMBING, State.MANTLING, State.ZIPLINING]:
		movement.release(Vector3.ZERO)
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


func _on_died() -> void:
	state = State.DEAD
	jetpack.set_thrusting(false)
	weapons.close_wheel(false)
	model.rotation.x = deg_to_rad(-80.0)
	GameState.trigger_game_over(&"farmer")


# --- Presentation ---------------------------------------------------------------------------------

func _update_model(delta: float, wish: Vector3) -> void:
	if state not in [State.CLIMBING, State.ZIPLINING] and not repair.is_repairing:
		if is_aiming or _combat_facing_left > 0.0:
			facing_yaw = camera_rig.yaw
		elif Vector2(wish.x, wish.z).length() > 0.1:
			facing_yaw = atan2(-wish.x, -wish.z)
	model.rotation.y = lerp_angle(model.rotation.y, facing_yaw, 1.0 - exp(-turn_speed * delta))
	_jetpack_can.visible = GameState.jetpack_unlocked
	_jet_flame.visible = jetpack.is_thrusting
	_update_hurt_feedback()


## Taking a hit flashes the body red and shakes the model, both fading over HURT_FLASH_SECONDS.
func _update_hurt_feedback() -> void:
	var hurt := _hurt_flash_left > 0.0
	for mesh: MeshInstance3D in _rest_tints:
		mesh.set_instance_shader_parameter(&"tint", HURT_TINT if hurt else _rest_tints[mesh])
	_body_mesh.set_instance_shader_parameter(&"emission_strength", 0.7 if hurt else 0.0)
	if hurt:
		var strength := HURT_SHAKE * _hurt_flash_left / HURT_FLASH_SECONDS
		model.position = _model_rest_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * strength
	else:
		model.position = _model_rest_position


## Clay squash on a hard landing (GDD 3.4: purely visual).
func _on_landed(fall_speed: float) -> void:
	if fall_speed > 6.0:
		_land_squash_left = 0.12


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
		_pose.position.y = 0.0 if step != 2 else 0.05
	else:
		_pose.scale = Vector3.ONE
		_pose.position.y = 0.0
