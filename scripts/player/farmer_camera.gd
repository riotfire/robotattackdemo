class_name FarmerCamera
extends Node3D
## Over-the-shoulder camera (GDD 5.3): offset (0.6, 1.6, 3.2) m, FOV 70 (50 while aiming), a SpringArm3D
## so walls never clip it, and a 1 m pull-back with a slight downward tilt while jetpacking.
## Updated every rendered frame from the farmer's interpolated position; never stepped (GDD 15.4).
## Scene layout: CameraRig (yaw) > Pitch > SpringArm3D > Camera3D.
##
## Screen shake uses the "trauma" model (Eiserloh, GDC 2016): events add trauma (0–1), it decays
## linearly, and the visible shake is trauma squared, so small pops barely register and big ones kick.
## The shake is smooth noise on the lens offset and roll only, so the aim ray never moves.

const GROUP: StringName = &"farmer_cameras"
## Shake from a blast travels outward this fast (m/s), so far explosions arrive a beat late.
const SHAKE_TRAVEL_SPEED: float = 140.0

@export var shoulder_offset: Vector3 = Vector3(0.6, 1.6, 3.2)
@export var fov: float = 70.0
@export var aim_fov: float = 50.0
@export var jetpack_pullback: float = 1.0
@export var jetpack_tilt_degrees: float = 8.0
## Pitch range in degrees (negative looks down).
@export var pitch_limits: Vector2 = Vector2(-70.0, 55.0)
@export var blend_speed: float = 8.0
@export_group("Shake")
@export var shake_offset: float = 0.22
@export var shake_roll_degrees: float = 3.5
@export var shake_frequency: float = 22.0
## Trauma lost per second.
@export var trauma_decay: float = 1.5
## Reduce Motion (GDD 20) keeps this much of the shake.
@export var reduce_motion_shake: float = 0.3

var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)
var shoulder_side: float = 1.0
var target: Farmer

var _tilt: float = 0.0
var _pullback: float = 0.0
var trauma: float = 0.0
var _shake_time: float = 0.0
var _noise := FastNoiseLite.new()

@onready var _pitch_node: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group(GROUP)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()


func attach(farmer: Farmer) -> void:
	target = farmer
	_arm.add_excluded_object(farmer.get_rid())
	yaw = farmer.global_rotation.y
	_arm.position.x = shoulder_offset.x * shoulder_side
	_place(1.0)


func _process(delta: float) -> void:
	if target == null:
		return
	var look := target.input.consume_look(delta)
	yaw = wrapf(yaw - look.x, -PI, PI)
	pitch = clampf(pitch - look.y, deg_to_rad(pitch_limits.x), deg_to_rad(pitch_limits.y))
	if target.input.is_just_pressed(&"shoulder_swap"):
		shoulder_side = -shoulder_side
	_place(1.0 - exp(-blend_speed * delta))
	# Real seconds, so the shake keeps rattling through a freeze frame or the wheel's slow-mo.
	_update_shake(delta / maxf(Engine.time_scale, 0.01))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Shakes every farmer camera near `at`: full strength within `inner` metres, none past `outer`.
static func shake_at(at: Vector3, amount: float, inner: float = 6.0, outer: float = 40.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or amount <= 0.0:
		return
	for node in tree.get_nodes_in_group(GROUP):
		var rig := node as FarmerCamera
		var distance := rig.camera.global_position.distance_to(at)
		var falloff := 1.0 - clampf((distance - inner) / maxf(outer - inner, 0.01), 0.0, 1.0)
		if falloff <= 0.0:
			continue
		var delay := distance / SHAKE_TRAVEL_SPEED
		if delay < 0.03:
			rig.add_trauma(amount * falloff)
		else:
			tree.create_timer(delay, false, false, true).timeout.connect(rig.add_trauma.bind(amount * falloff))


func _update_shake(real_delta: float) -> void:
	trauma = maxf(trauma - trauma_decay * real_delta, 0.0)
	if trauma <= 0.0:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0 or camera.rotation.z != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			camera.rotation.z = 0.0
		return
	_shake_time += real_delta * shake_frequency
	var shake := trauma * trauma
	if bool(SaveManager.settings.get("reduce_motion", false)):
		shake *= reduce_motion_shake
	camera.h_offset = shake_offset * shake * _noise.get_noise_2d(_shake_time, 0.0)
	camera.v_offset = shake_offset * shake * _noise.get_noise_2d(_shake_time, 100.0)
	camera.rotation.z = deg_to_rad(shake_roll_degrees) * shake * _noise.get_noise_2d(_shake_time, 200.0)


func _place(blend: float) -> void:
	var jetting := target.jetpack.is_thrusting
	_pullback = lerpf(_pullback, jetpack_pullback if jetting else 0.0, blend)
	_tilt = lerpf(_tilt, jetpack_tilt_degrees if jetting else 0.0, blend)
	global_position = target.get_global_transform_interpolated().origin + Vector3.UP * shoulder_offset.y
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch - deg_to_rad(_tilt), 0.0, 0.0)
	_arm.position.x = lerpf(_arm.position.x, shoulder_offset.x * shoulder_side, blend)
	_arm.spring_length = shoulder_offset.z + _pullback
	camera.fov = lerpf(camera.fov, aim_fov if target.is_aiming else fov, blend)


## Flat forward direction of the camera (where "W" goes).
func flat_forward() -> Vector3:
	return -Basis(Vector3.UP, yaw).z


func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
