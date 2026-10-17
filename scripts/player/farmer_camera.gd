class_name FarmerCamera
extends Node3D
## Over-the-shoulder camera (GDD 5.3): offset (0.6, 1.6, 3.2) m, FOV 70 (50 while aiming), a SpringArm3D
## so walls never clip it, and a 1 m pull-back with a slight downward tilt while jetpacking.
## Updated every rendered frame from the farmer's interpolated position; never stepped (GDD 15.4).
## Scene layout: CameraRig (yaw) > Pitch > SpringArm3D > Camera3D.

@export var shoulder_offset: Vector3 = Vector3(0.6, 1.6, 3.2)
@export var fov: float = 70.0
@export var aim_fov: float = 50.0
@export var jetpack_pullback: float = 1.0
@export var jetpack_tilt_degrees: float = 8.0
## Pitch range in degrees (negative looks down).
@export var pitch_limits: Vector2 = Vector2(-70.0, 55.0)
@export var blend_speed: float = 8.0

var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)
var shoulder_side: float = 1.0
var target: Farmer

var _tilt: float = 0.0
var _pullback: float = 0.0

@onready var _pitch_node: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


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
