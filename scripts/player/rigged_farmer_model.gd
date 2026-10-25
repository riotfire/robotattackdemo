class_name RiggedFarmerModel
extends Node3D
## The rigged Blender farmer (assets/models/player/player_farmer_rigged.glb), a test alternative to the clay body.
## The file also carries the Blender scene's grass, sky and icosphere dressing, so only the skinned farmer mesh stays.
##
## The file has no animations, so this poses the deform bones from code. A base pose follows the farmer's state
## (idle, run, jump, fall, zipline, and the gun hold while aiming); one-shot overlays (land, wrench swing, gun recoil,
## hurt) play on top. Poses update on the 24 fps stop-motion tick (GDD 15.4), so they step "on ones" and hold between
## ticks. Each pose is a world-space rotation (+X is the farmer's left, +Y up, +Z forward) that the bones compound down
## their chains.

const TICK: float = 1.0 / 24.0
## How quickly a pose eases toward its target, per second. Each tick moves it by 1 - exp(-BLEND_RATE * TICK).
const BLEND_RATE: float = 14.0
## Gait radians per metre travelled, and the leg and arm swing at full stride (radians).
const GAIT_PER_METRE: float = 1.8
const FULL_STRIDE_SPEED: float = 7.0
const LEG_SWING: float = 0.8
const ARM_SWING: float = 0.7
const KNEE_BEND: float = 1.4
const ELBOW_BEND: float = 1.0
## Forward lean at full stride, so the run looks like it carries momentum.
const RUN_LEAN: float = 0.16
## How far the arms hang from the T-pose (the rig's arms start straight out).
const ARM_DOWN: float = 1.25
## Jumping arms lift out to the sides; the zipline grip is a wider V, since the rig's arms are short against its head.
const JUMP_ARM_RAISE: float = 1.0
## The zipline is 1.95 m over the farmer's feet and the rig's straight arm only reaches about 1.6 m, so the hanging
## farmer is lifted this much and grips the line with its right hand, leaving the left hand on the weapon.
const HANG_GRIP: float = 1.45
const HANG_LIFT: float = 0.42
## Aiming turns the torso so the weapon arm points down the sights, with the head turned back to look ahead.
const AIM_TWIST: float = 0.7
const LAND_TIME: float = 0.28
const HURT_TIME: float = 0.35
const FIRE_TIME: float = 0.24
const FIRE_HOLD_TIME: float = 0.5
const ATTACK_TIME: float = 0.34
## Overlay curves as [time 0-1, angle] keys. The wrench arm winds back, strikes over the head and recovers.
const SWING_KEYS: Array = [[0.0, 0.0], [0.3, 0.9], [0.55, -2.1], [1.0, 0.0]]
const COCK_KEYS: Array = [[0.0, 0.0], [0.3, 0.5], [0.55, -0.5], [1.0, 0.0]]
const LEAN_KEYS: Array = [[0.0, 0.0], [0.3, -0.12], [0.55, 0.28], [1.0, 0.0]]

## Index 0 is the farmer's left (+X in the rig, where the wrench is held), index 1 the right.
const SIDE_SIGN: Array[float] = [1.0, -1.0]
const UPPER_ARM: Array[String] = ["DEF-upper_arm.L", "DEF-upper_arm.R"]
const FOREARM: Array[String] = ["DEF-forearm.L", "DEF-forearm.R"]
const THIGH: Array[String] = ["DEF-thigh.L", "DEF-thigh.R"]
const SHIN: Array[String] = ["DEF-shin.L", "DEF-shin.R"]
const FOOT: Array[String] = ["DEF-foot.L", "DEF-foot.R"]
const SHOULDER: Array[String] = ["DEF-shoulder.L", "DEF-shoulder.R"]
const SPINE_LOW: String = "DEF-spine.001"
const SPINE_HIGH: String = "DEF-spine.003"
const HEAD: String = "DEF-spine.006"
## The farmer's left hand (the wrench and the guns ride here).
const HAND: String = "DEF-hand.L"

var _farmer: Farmer
var _skeleton: Skeleton3D
var _index: Dictionary = {}
## Bones this script poses. Every other bone stays at rest and follows its posed parents.
var _driven: Array[int] = []
var _parents: PackedInt32Array
## Each bone's rest rotation in its parent's frame, and its rest rotation in skeleton space.
var _rest_local: Array[Quaternion] = []
var _rest_world: Array[Quaternion] = []
## Eased world-space rotation each driven bone currently applies.
var _increments: Dictionary = {}
var _run_phase: float = 0.0
var _idle_time: float = 0.0
var _land_left: float = 0.0
var _hurt_left: float = 0.0
var _fire_left: float = 0.0
var _fire_hold: float = 0.0
var _attack_left: float = 0.0
var _hand_bone: int = -1
## How far the held weapon is tipped about the model's X axis (negative points the barrel down).
var _tilt: float = 0.0


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.visible = mesh.skin != null
	_skeleton = $rig/Skeleton3D
	var count := _skeleton.get_bone_count()
	_parents.resize(count)
	_rest_local.resize(count)
	_rest_world.resize(count)
	for i in count:
		_index[_skeleton.get_bone_name(i)] = i
		_parents[i] = _skeleton.get_bone_parent(i)
		_rest_local[i] = _skeleton.get_bone_rest(i).orthonormalized().basis.get_rotation_quaternion()
		_rest_world[i] = _skeleton.get_bone_global_rest(i).orthonormalized().basis.get_rotation_quaternion()
	for bone_name in UPPER_ARM + FOREARM + THIGH + SHIN + FOOT + SHOULDER + [SPINE_LOW, SPINE_HIGH, HEAD]:
		_driven.append(_index[bone_name])
	for bone in _driven:
		_increments[bone] = Quaternion()
	_hand_bone = _index[HAND]


## Called by the farmer once its weapons exist. Wires up the one-shot overlays.
func setup(owner_farmer: Farmer) -> void:
	_farmer = owner_farmer
	_farmer.movement.landed.connect(on_landed)
	_farmer.hurt.connect(on_hurt)
	for weapon in _farmer.weapons.weapons:
		weapon.fired.connect(on_fired)


func on_landed(fall_speed: float) -> void:
	if fall_speed > 3.0:
		_land_left = LAND_TIME


func on_hurt() -> void:
	_hurt_left = HURT_TIME


## Melee swings (wrench, maul, scythe) wind the left arm up; guns kick back and hold the aim.
func on_fired(shot: WeaponShot) -> void:
	if shot.weapon is Wrench or shot.weapon is SweepWeapon:
		_attack_left = ATTACK_TIME
	else:
		_fire_left = FIRE_TIME
		_fire_hold = FIRE_HOLD_TIME


## Poses the skeleton for one 24 fps tick. The farmer calls this from its tick_24 handler.
func step_pose(farmer: Farmer) -> void:
	var speed := Vector2(farmer.velocity.x, farmer.velocity.z).length()
	if farmer.state == Farmer.State.GROUNDED and speed > 0.5:
		_run_phase += TICK * speed * GAIT_PER_METRE
	_idle_time += TICK
	_land_left = maxf(0.0, _land_left - TICK)
	_hurt_left = maxf(0.0, _hurt_left - TICK)
	_fire_left = maxf(0.0, _fire_left - TICK)
	_fire_hold = maxf(0.0, _fire_hold - TICK)
	_attack_left = maxf(0.0, _attack_left - TICK)

	var aim := _holding_gun(farmer) and (farmer.is_aiming or _fire_hold > 0.0)
	var pose := {}
	_state_pose(pose, farmer, speed, aim)
	_overlays(pose)
	_ease(pose)
	_apply()
	position.y = lerpf(position.y, HANG_LIFT if farmer.state == Farmer.State.ZIPLINING else 0.0, 0.45)
	# The left hand carries the held weapon, so it moves with the swing and the recoil while the rig shows.
	_skeleton.force_update_all_bone_transforms()
	if visible:
		var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone)
		_farmer.weapons.position = _farmer.model.to_local(hand.origin)
		_tilt = lerpf(_tilt, _carry_tilt(aim), 0.5)
		_farmer.weapons.rotation.x = _tilt


func _holding_gun(farmer: Farmer) -> bool:
	var weapon := farmer.weapons.current
	return weapon != null and not (weapon is Wrench or weapon is SweepWeapon)


func _state_pose(pose: Dictionary, farmer: Farmer, speed: float, aim: bool) -> void:
	match farmer.state:
		Farmer.State.ZIPLINING:
			_hang_pose(pose)
		Farmer.State.JETPACKING:
			_jump_pose(pose, aim)
		Farmer.State.AIRBORNE:
			if farmer.velocity.y > 0.5:
				_jump_pose(pose, aim)
			else:
				_fall_pose(pose, aim)
		Farmer.State.GROUNDED:
			if speed > 0.5:
				_run_pose(pose, clampf(speed / FULL_STRIDE_SPEED, 0.4, 1.0), aim)
			else:
				_idle_pose(pose, aim)
		_:
			_idle_pose(pose, aim)
	if aim and farmer.state != Farmer.State.ZIPLINING:
		_add(pose, SPINE_LOW, _ry(-AIM_TWIST * 0.5))
		_add(pose, SPINE_HIGH, _ry(-AIM_TWIST * 0.5))
		_add(pose, HEAD, _ry(AIM_TWIST * 0.85))


func _idle_pose(pose: Dictionary, aim: bool) -> void:
	for side in 2:
		_arm(pose, side, 0.0, aim, 0.0)
	if aim:
		# A braced stance: weapon-side foot forward, back foot planted, knees soft, chin down the sights.
		_leg(pose, 0, 0.3, 0.3, 0.12)
		_leg(pose, 1, -0.25, 0.35, 0.12)
		_add(pose, SPINE_LOW, _rx(0.06))
		_add(pose, HEAD, _rx(0.12))
	else:
		var breath := sin(_idle_time * 2.4) * 0.025
		_add(pose, SPINE_LOW, _rx(breath))
		_add(pose, HEAD, _rx(-breath))


## One leg. `hip` swings it forward and `knee` bends it back (radians); `spread` opens it outward. A level foot
## stays flat on the ground however the leg is folded.
func _leg(pose: Dictionary, side: int, hip: float, knee: float, spread: float = 0.0, level_foot: bool = true) -> void:
	if spread != 0.0:
		_add(pose, THIGH[side], _rz(SIDE_SIGN[side] * spread))
	_add(pose, THIGH[side], _rx(-hip))
	_add(pose, SHIN[side], _rx(knee))
	if level_foot:
		_add(pose, FOOT[side], _rx(hip - knee))


func _run_pose(pose: Dictionary, stride: float, aim: bool) -> void:
	var swing := sin(_run_phase)
	for side in 2:
		# The right leg runs half a cycle behind the left.
		var leg := sin(_run_phase + side * PI)
		_leg(pose, side, LEG_SWING * stride * leg, KNEE_BEND * stride * maxf(0.0, leg))
		# The trailing foot rolls onto its toes as it pushes off.
		_add(pose, FOOT[side], _rx(0.5 * stride * maxf(0.0, -leg)))
		# Each arm swings against the leg on its own side.
		_arm(pose, side, ARM_SWING * stride * leg, aim, -ELBOW_BEND * (0.6 + 0.4 * stride))
	_add(pose, SPINE_LOW, _rx(RUN_LEAN * stride))
	_add(pose, SPINE_HIGH, _rx(RUN_LEAN * stride))
	# The head stays level with the horizon while the body leans.
	_add(pose, HEAD, _rx(-RUN_LEAN * stride * 1.5))
	if not aim:
		# Shoulders counter-rotate against the hips.
		_add(pose, SPINE_LOW, _ry(-0.12 * stride * swing))
		_add(pose, SPINE_HIGH, _ry(0.3 * stride * swing))
		_add(pose, HEAD, _ry(-0.18 * stride * swing))


func _jump_pose(pose: Dictionary, aim: bool) -> void:
	for side in 2:
		_leg(pose, side, 0.6, 1.1, 0.0, false)
		if aim:
			_arm(pose, side, 0.0, true, -0.3)
		else:
			_add(pose, UPPER_ARM[side], _rz(SIDE_SIGN[side] * JUMP_ARM_RAISE))
			_add(pose, SHOULDER[side], _rz(SIDE_SIGN[side] * JUMP_ARM_RAISE * 0.35))
	_add(pose, SPINE_LOW, _rx(0.12))
	_add(pose, HEAD, _rx(-0.2))


func _fall_pose(pose: Dictionary, aim: bool) -> void:
	for side in 2:
		var s: float = SIDE_SIGN[side]
		_leg(pose, side, 0.15, 0.45, 0.14, false)
		if aim:
			_arm(pose, side, 0.0, true, -0.3)
		else:
			_add(pose, UPPER_ARM[side], _rz(s * 0.75))
			_add(pose, FOREARM[side], _rx(-0.5))
			_add(pose, SHOULDER[side], _rz(s * 0.25))
	_add(pose, SPINE_LOW, _rx(-0.1))
	_add(pose, HEAD, _rx(-0.15))


## Hanging from a zipline: the right arm reaches straight up to the line, the left hangs with the weapon, and the
## legs dangle behind with the knees bent and the feet staggered.
func _hang_pose(pose: Dictionary) -> void:
	_add(pose, UPPER_ARM[1], _rz(-HANG_GRIP))
	_add(pose, SHOULDER[1], _rz(-HANG_GRIP * 0.5))
	_arm(pose, 0, 0.15, false, -0.35)
	_leg(pose, 0, -0.1, 0.6, 0.06, false)
	_leg(pose, 1, -0.35, 1.1, 0.0, false)
	_add(pose, FOOT[0], _rx(0.4))
	_add(pose, FOOT[1], _rx(0.5))
	# The body's weight hangs from the gripping hand: roll toward it, arch the back, look up at the line.
	_add(pose, SPINE_LOW, _rz(-0.15))
	_add(pose, SPINE_LOW, _rx(-0.2))
	_add(pose, SPINE_HIGH, _rx(0.12))
	_add(pose, HEAD, _rx(-0.5))
	_add(pose, HEAD, _rz(0.1))


## One arm. Hangs at the side and swings by `swing`, or takes its aiming role when `aim`.
func _arm(pose: Dictionary, side: int, swing: float, aim: bool, elbow: float) -> void:
	var s: float = SIDE_SIGN[side]
	if aim:
		_aim_arm(pose, side)
		return
	_add(pose, UPPER_ARM[side], _rz(-s * ARM_DOWN))
	_add(pose, UPPER_ARM[side], _rx(swing))
	_add(pose, FOREARM[side], _rx(elbow))


## The left arm (it carries the weapon) points out at the target. The right arm swings out and back for balance,
## which keeps it clear of the face and gives the stance a wider silhouette. Each undoes the torso turn first, so
## it is posed as if the shoulders were square.
func _aim_arm(pose: Dictionary, side: int) -> void:
	_add(pose, UPPER_ARM[side], _ry(AIM_TWIST))
	_add(pose, UPPER_ARM[side], _rz(-SIDE_SIGN[side] * ARM_DOWN))
	if side == 0:
		_add(pose, UPPER_ARM[side], _rx(-1.45))
		_add(pose, FOREARM[side], _rx(-0.1))
	else:
		_add(pose, UPPER_ARM[side], _rz(SIDE_SIGN[side] * 0.5))
		_add(pose, UPPER_ARM[side], _rx(0.4))
		_add(pose, FOREARM[side], _rx(-0.35))


## How the held weapon is tipped. Guns point at the ground while carried, come level to aim, and kick up when they
## fire; melee tools ride lower than the hip and stay out of the swing's way.
func _carry_tilt(aim: bool) -> float:
	if _attack_left > 0.0:
		return 0.0
	var kick := 0.4 * pow(_fire_left / FIRE_TIME, 2.0)
	if aim:
		return kick
	var gun := _farmer.weapons.current != null and not (_farmer.weapons.current is Wrench or _farmer.weapons.current is SweepWeapon)
	return -0.8 if gun else -0.3


func _overlays(pose: Dictionary) -> void:
	if _attack_left > 0.0:
		var t := 1.0 - _attack_left / ATTACK_TIME
		_add(pose, UPPER_ARM[0], _rx(_curve(t, SWING_KEYS)))
		_add(pose, FOREARM[0], _rx(_curve(t, COCK_KEYS)))
		_add(pose, UPPER_ARM[1], _rx(-0.35 * _curve(t, SWING_KEYS)))
		_add(pose, SPINE_HIGH, _rx(_curve(t, LEAN_KEYS)))
	if _fire_left > 0.0:
		# The shot kicks the weapon arm up, rocks the torso and head back, and drives the back foot into the ground.
		var recoil := pow(_fire_left / FIRE_TIME, 2.0)
		_add(pose, UPPER_ARM[0], _rx(0.55 * recoil))
		_add(pose, UPPER_ARM[1], _rx(0.3 * recoil))
		_add(pose, SPINE_LOW, _rx(-0.16 * recoil))
		_add(pose, SPINE_HIGH, _rx(-0.16 * recoil))
		_add(pose, HEAD, _rx(-0.3 * recoil))
		_add(pose, THIGH[1], _rx(0.2 * recoil))
		_add(pose, SHIN[1], _rx(0.35 * recoil))
		_add(pose, SHIN[0], _rx(0.2 * recoil))
	if _hurt_left > 0.0:
		var jolt := pow(_hurt_left / HURT_TIME, 2.0)
		_add(pose, SPINE_LOW, _rx(-0.2 * jolt))
		_add(pose, SPINE_HIGH, _rx(-0.2 * jolt))
		_add(pose, HEAD, _rx(-0.3 * jolt))
		for side in 2:
			_add(pose, UPPER_ARM[side], _rz(SIDE_SIGN[side] * 0.5 * jolt))
			_add(pose, SHIN[side], _rx(0.3 * jolt))
	if _land_left > 0.0:
		var squat := sin((1.0 - _land_left / LAND_TIME) * PI)
		for side in 2:
			_add(pose, THIGH[side], _rx(-0.35 * squat))
			_add(pose, SHIN[side], _rx(0.9 * squat))
		_add(pose, SPINE_HIGH, _rx(0.25 * squat))


## Adds `q` after whatever the bone already has, so later calls turn the pose further in world space.
func _add(pose: Dictionary, bone: String, q: Quaternion) -> void:
	var b: int = _index[bone]
	var previous: Quaternion = pose.get(b, Quaternion())
	pose[b] = q * previous


func _ease(pose: Dictionary) -> void:
	var blend := 1.0 - exp(-BLEND_RATE * TICK)
	for b in _driven:
		var goal: Quaternion = pose.get(b, Quaternion())
		var current: Quaternion = _increments[b]
		_increments[b] = current.slerp(goal, blend)


## Each driven bone's absolute local rotation: the world rotation it should have, expressed in the local frame its
## posed parent gives it. Undriven bones stay at rest and follow their parents.
func _apply() -> void:
	for b in _driven:
		var parent: int = _parents[b]
		var parent_world := _rest_world[parent] if parent >= 0 else Quaternion()
		var parent_total := _total(parent)
		var local := parent_world.inverse() * parent_total.inverse() * _total(b) * parent_world * _rest_local[b]
		_skeleton.set_bone_pose_rotation(b, local)


## The world rotation a bone carries: its own eased increment on top of its parent's.
func _total(bone: int) -> Quaternion:
	if bone < 0:
		return Quaternion()
	var increment: Quaternion = _increments.get(bone, Quaternion())
	return increment * _total(_parents[bone])


static func _rx(angle: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, angle)


static func _ry(angle: float) -> Quaternion:
	return Quaternion(Vector3.UP, angle)


static func _rz(angle: float) -> Quaternion:
	return Quaternion(Vector3(0.0, 0.0, 1.0), angle)


## Eases through [time, value] keys, smoothstepping each segment.
static func _curve(t: float, keys: Array) -> float:
	for i in range(1, keys.size()):
		var end: Array = keys[i]
		if t <= end[0]:
			var start: Array = keys[i - 1]
			return lerpf(start[1], end[1], smoothstep(start[0], end[0], t))
	return keys[keys.size() - 1][1]
