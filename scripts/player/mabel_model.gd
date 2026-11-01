class_name MabelModel
extends Node3D
## Mabel, the farmer (assets/Mabel Annimation.glb): a Mixamo-rigged character with twenty baked animations.
## The farmer picks one from its state each 24 fps stop-motion tick (GDD 15.4) and advances the player by hand, so the
## motion steps "on ones" like the rest of the game. Mixamo clips carry root motion, which is stripped here because
## the CharacterBody3D does the moving.
## Every change of clip cross-fades from a snapshot of the pose on screen, so held poses (idle, the rope grip) and
## clips that stop mid-stride blend like any other.

const TICK: float = 1.0 / 24.0
## Standing height the model is scaled to, in metres (the farmer's capsule is 1.7 m).
const HEIGHT: float = 1.75
const BLEND: float = 0.15
## Ground speed at which a clip's planted foot stays put, measured by tests/tools/pose_gallery.tscn. Clips play
## faster or slower than 1x to match the farmer's speed, so the feet do not skate.
const WALK_SPEED: float = 1.29
const RUN_SPEED: float = 4.4
## Above this ground speed the walk gives way to the run.
const RUN_THRESHOLD: float = 2.4
const WALK_RATE: Vector2 = Vector2(0.4, 1.9)
const RUN_RATE: Vector2 = Vector2(0.55, 1.45)
const MELEE_SPEED: float = 3.0
const MELEE_TIME: float = 0.5
## Where the slash lands in clip seconds. A wind-up paces the clip to arrive there as the blow does, within MELEE_WINDUP_RATE.
const MELEE_STRIKE: float = 0.45
const MELEE_WINDUP_RATE: Vector2 = Vector2(1.0, 3.0)
## The scythe's whirl: she turns a full circle over this long with the blade held out along this line (x right, z back).
const SPIN_TIME: float = 0.55
const SPIN_ARM := Vector3(0.75, -0.05, -0.66)
## She slides her grip down the pole for the whirl, so the end of it clears her and the blade reaches further.
const SPIN_GRIP_SLIDE: float = 0.5
const FIRE_HOLD_TIME: float = 0.5
## Swing_on_Rope_to_Ground is the whole zipline, in clip seconds: she takes hold at ZIPLINE_GRIP and is swung out to
## ZIPLINE_HANG, where she holds for the ride; letting go plays on from ROPE_RELEASE, through the tumble, to ROPE_LAND (her
## feet just short of the ground), then the touchdown crouch and the rise to standing at ROPE_END.
## It is a swing on a vertical rope, so the legs and body hang right but the hands are in front of her face; the arms
## are re-aimed at the cable (see _pose_zipline_arms).
const ROPE: StringName = &"Swing_on_Rope_to_Ground"
const ZIPLINE_GRIP: float = 0.2
const ZIPLINE_HANG: float = 0.8
const ROPE_RELEASE: float = 1.15
const ROPE_LAND: float = 2.3
const ROPE_END: float = 3.4
## The tumble is paced to the real drop so she touches down as her feet reach the ground; a short drop plays it up to
## this much faster, and a long one as slow as the lower limit before she holds the pose in the air.
const ROPE_RATE: Vector2 = Vector2(0.8, 2.0)
const ROPE_LAND_RATE: float = 1.5
## Holding the stick this far on touchdown skips the crouch and runs.
const ROPE_RUN_STICK: float = 0.3
## Through the tumble and the first frames of the touchdown her hands are up by her face, so the weapon is stowed
## until the clip has lowered them (a clip second).
const ROPE_HANDS_DOWN: float = 2.5
## How far the gripping hands lean in toward the cable, as a fraction of the arm's length, and how fast she is lowered
## onto the cable (m/s) so the hands meet it.
const ZIPLINE_ARM_INWARD: float = 0.22
const ZIPLINE_LOWER_SPEED: float = 3.0
## The palm is this far past the wrist bone, so the wrist hangs this far below the cable.
const ZIPLINE_PALM_REACH: float = 0.1
const ARM_CHAINS: Dictionary = {"Left": ["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"],
		"Right": ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]}
## The ladder clip climbs only 0.46 m/s at 1x while the ladder moves the farmer at 4 m/s, so no rate keeps the hands on
## the rungs. This is as fast as the hand-over-hand still reads at 24 fps.
const LADDER_RATE: float = 2.2
## Regular_Jump, in clip seconds: standing with arms at the sides at 0, the push-off at LAUNCH, the airborne tuck at
## about 0.8, touchdown with arms out at HOLD, then a recovery back to standing that ends at END.
const JUMP: StringName = &"Regular_Jump"
const JUMP_LAUNCH: float = 0.5
## Where a farmer who walks off a ledge or lets go of a line joins the clip, just past the top of the arc.
const JUMP_FALL_START: float = 0.85
const JUMP_HOLD: float = 1.0
const JUMP_END: float = 1.8
const JUMP_RATE: float = 0.9
const LAND_RATE: float = 1.5
const LOOPING: Array[String] = ["Running", "Walking", "Fast_Ladder_Climb", "Ladder_Climb", "Idle_3", "Fall2",
		"Aim_Walk", "Aim_Run"]
## A breathing idle, 10 s long, that starts and ends on the same standing pose.
const IDLE: StringName = &"Idle_3"
## Fall2 is a bracing mid-air pose that takes over from the jump pose once the farmer is dropping faster than a plain
## jump ever lands (7.6 m/s), so hops keep the jump clip and real drops brace.
const FALL: StringName = &"Fall2"
const FALL_SPEED: float = 8.0
## Thrusting holds a built pose: dangling legs under a relaxed or aiming torso (see _build_aim_clip).
const JET_LEGS: StringName = &"Jumping_Down"
const JET_LEGS_TIME: float = 0.93
## The worn jetpack rides her chest; this is its centre from that bone, in the farmer's frame at rest (z back).
const CHEST: String = "mixamorig_Spine2"
const PACK_OFFSET := Vector3(0.0, -0.08, 0.24)
## The hand bone sits at the wrist; a held weapon's grip is this far on, in the fist.
const FIST_REACH: float = 0.085
## Both straight arms meet here in the pistol stance: x right of centre and z forward of the shoulders, as shares of an
## arm's length, and y above the shoulders in metres.
const STANCE_MEET := Vector3(0.42, -0.03, -0.88)
## How the scythe rests when carried: the pole up and tipped a little forward, the blade forward.
const CARRY_UPRIGHT := Basis(Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, -1.0, 0.0))
const CARRY_TIP: float = 0.2
## Hit_Reaction_1 flinches (1.2 s of clip, played in HIT_TIME) when a standing farmer is hit; at most once per cooldown,
## so sustained fire does not pin her in it.
const HIT: StringName = &"Hit_Reaction_1"
const HIT_TIME: float = 0.45
const HIT_COOLDOWN: float = 1.0
## Standing_Reload takes 3.3 s of clip and is stretched to the weapon's reload time.
const RELOAD: StringName = &"Standing_Reload"
## The shooting walks barely lift their feet (they shuffle at under 1 m/s), so aiming on the move uses clips built
## from them: the legs of the matching locomotion clip under the aiming pose's torso and arms.
const AIM_POSE: String = "Walk_Forward_While_Shooting_inplace"
## Laid over her skin while she flashes from a hit, the way the clay body flashes through its tint.
const HURT_OVERLAY_COLOR := Color(1.0, 0.1, 0.08, 0.55)
## The death clip plays at this fraction of its speed, so the fall reads in slow motion. The stats wait for it.
const DEATH: StringName = &"Dead"
const DEATH_RATE: float = 0.5
const HAND: String = "mixamorig_RightHand"
const HIPS: String = "mixamorig_Hips"
const HEAD_TOP: String = "mixamorig_HeadTop_End"
const FOOT_L: String = "mixamorig_LeftToeBase"
const FOOT_R: String = "mixamorig_RightToeBase"

var _farmer: Farmer
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _hand_bone: int = -1
var _melee_left: float = 0.0
var _fire_hold: float = 0.0
var _hit_left: float = 0.0
var _hit_cooldown: float = 0.0
## What is playing: a clip's name, or a label (idle, aim_idle, jump, land) for a clip held or played in a special way.
var _current: StringName = &""
var _last_state: Farmer.State = Farmer.State.GROUNDED
var _blend_left: float = 0.0
var _from_position := PackedVector3Array()
var _from_rotation: Array[Quaternion] = []
var _rest_y: float = 0.0
## How far she is lowered below the farmer's origin so her hands reach the cable, and where that is heading.
var _hang_offset: float = 0.0
var _hang_target: float = 0.0
## True from letting go of a line until she is standing again (or something else takes her over).
var _roping_off: bool = false
var hurt_overlay: StandardMaterial3D
## The hand's turn in the aiming pose, in the farmer's frame. A weapon points straight ahead there, so this ties the
## weapons' frame to the hand's.
var _aim_hand: Basis = Basis.IDENTITY
var _chest_rest: Basis = Basis.IDENTITY
var _melee_windup: float = 0.0
var _melee_rate: float = MELEE_SPEED
var _spin_left: float = 0.0
var _meshes: Array[Node] = []


func _ready() -> void:
	_skeleton = find_children("*", "Skeleton3D", true, false)[0]
	_player = find_children("*", "AnimationPlayer", true, false)[0]
	_hand_bone = _skeleton.find_bone(HAND)
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for anim_name in _player.get_animation_list():
		var anim := _player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if String(anim_name) in LOOPING else Animation.LOOP_NONE
		_strip_root_motion(anim, String(anim_name) == "Fast_Ladder_Climb")
	hurt_overlay = StandardMaterial3D.new()
	hurt_overlay.albedo_color = HURT_OVERLAY_COLOR
	hurt_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hurt_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_meshes = find_children("*", "MeshInstance3D", true, false)
	_build_aim_clip("Aim_Idle", "Idle_3", 0.0)
	_build_aim_clip("Aim_Walk", "Walking")
	_build_aim_clip("Aim_Run", "Running")
	_build_aim_clip("Jet_Aim", String(JET_LEGS), JET_LEGS_TIME)
	_build_aim_clip("Jet_Fly", String(JET_LEGS), JET_LEGS_TIME, "Idle_3")
	_fit_to_height()
	_measure_rest_frames()


## Called by the farmer once its weapons exist. Wires up the attack reactions.
func setup(owner_farmer: Farmer) -> void:
	_farmer = owner_farmer
	for weapon in _farmer.weapons.weapons:
		weapon.fired.connect(_on_fired)
		var sweep := weapon as SweepWeapon
		if sweep != null:
			sweep.swing_started.connect(_on_swing_started)
	_farmer.hurt.connect(_on_hurt)


## Tints her red while the farmer is flashing from a hit.
func set_hurt(hurt: bool) -> void:
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = hurt_overlay if hurt else null


func _on_hurt() -> void:
	if _hit_cooldown <= 0.0:
		_hit_left = HIT_TIME
		_hit_cooldown = HIT_COOLDOWN


func _on_fired(shot: WeaponShot) -> void:
	if shot.weapon is Wrench:
		_melee_left = MELEE_TIME
		_melee_windup = 0.0
	elif not shot.weapon is SweepWeapon:
		_fire_hold = FIRE_HOLD_TIME


## A sweep's blow lands when its wind-up ends, so the clip starts now and is paced to meet it. A full-circle sweep turns
## her all the way round.
func _on_swing_started(weapon: SweepWeapon) -> void:
	_melee_windup = weapon.windup
	_melee_rate = clampf(MELEE_STRIKE / maxf(weapon.windup, TICK), MELEE_WINDUP_RATE.x, MELEE_WINDUP_RATE.y)
	_melee_left = weapon.windup + MELEE_TIME - MELEE_STRIKE / MELEE_SPEED
	if weapon.arc_degrees >= 359.0:
		_spin_left = SPIN_TIME


## Picks this tick's clip from the farmer's state and advances it one 24 fps step.
func step_pose(farmer: Farmer) -> void:
	_melee_left = maxf(0.0, _melee_left - TICK)
	_melee_windup = maxf(0.0, _melee_windup - TICK)
	_fire_hold = maxf(0.0, _fire_hold - TICK)
	_spin_left = 0.0 if farmer.state == Farmer.State.DEAD else maxf(0.0, _spin_left - TICK)
	_hit_left = maxf(0.0, _hit_left - TICK)
	_hit_cooldown = maxf(0.0, _hit_cooldown - TICK)
	var flat := Vector2(farmer.velocity.x, farmer.velocity.z)
	var speed := flat.length()
	var reload_time := _reload_time(farmer)
	var gun := _holding_gun(farmer) and (farmer.is_aiming or _fire_hold > 0.0 or reload_time > 0.0)
	var airborne := farmer.state in [Farmer.State.MANTLING, Farmer.State.JETPACKING, Farmer.State.AIRBORNE]
	if _melee_left > 0.0 and farmer.state != Farmer.State.DEAD:
		_play(&"Right_Hand_Sword_Slash", _melee_rate if _melee_windup > 0.0 else MELEE_SPEED)
	else:
		match farmer.state:
			Farmer.State.DEAD:
				_play(DEATH, DEATH_RATE)
			Farmer.State.ZIPLINING:
				# She takes hold and is yanked into the swing, then hangs there for the rest of the ride.
				_play(ROPE, 1.0, ZIPLINE_GRIP, &"rope_ride")
			Farmer.State.CLIMBING:
				# The ladder moves the farmer by position, so climbing speed comes from the stick: up plays the
				# clip forward, down plays it backward.
				_play(&"Fast_Ladder_Climb", -signf(farmer.input.move_vector().y) * LADDER_RATE)
			Farmer.State.MANTLING, Farmer.State.JETPACKING, Farmer.State.AIRBORNE:
				if farmer.state == Farmer.State.AIRBORNE and (_roping_off or _last_state == Farmer.State.ZIPLINING):
					# Off a line the rope clip plays on, instead of the plain jump, until she is down.
					_rope_flight(farmer)
				elif farmer.state == Farmer.State.JETPACKING:
					_play(&"Jet_Aim" if gun else &"Jet_Fly", 0.0)
				elif farmer.velocity.y < -FALL_SPEED and farmer.state != Farmer.State.MANTLING:
					_play(FALL, 1.0)
				else:
					# A jump from the ground starts at the push-off (the crouch would play on the way up); anything
					# else, a ledge, the end of a line, joins the clip past the top of the arc.
					var pushed_off := _last_state == Farmer.State.GROUNDED and farmer.velocity.y > 0.5
					var start := JUMP_LAUNCH if pushed_off or farmer.state == Farmer.State.MANTLING else JUMP_FALL_START
					_play(JUMP, JUMP_RATE, start, &"jump")
			_:
				var recovering := _current in [&"jump", &"land"] and _player.current_animation_position < JUMP_END
				if _roping_off and _rope_landing(farmer):
					pass  # The rope clip is playing her touchdown.
				elif speed < 0.5 and _current == FALL:
					# A hard drop lands on the jump clip's touchdown pose and plays its recovery.
					_play(JUMP, LAND_RATE, JUMP_HOLD, &"land")
				elif speed < 0.5 and recovering:
					# Touching down plays the clip's recovery, which ends on the idle pose.
					_current = &"land"
					_player.speed_scale = LAND_RATE
				elif _hit_left > 0.0 and speed < 0.5 and not gun:
					_play(HIT, 1.2 / HIT_TIME)
				else:
					_ground(farmer, flat, speed, gun, reload_time)
	_last_state = farmer.state
	if farmer.state not in [Farmer.State.AIRBORNE, Farmer.State.GROUNDED]:
		_roping_off = false
	_player.advance(TICK)
	if _current == &"rope_ride" and _player.current_animation_position >= ZIPLINE_HANG:
		_player.seek(ZIPLINE_HANG, true)
		_player.speed_scale = 0.0
	elif _current == &"rope_air" and _player.current_animation_position >= ROPE_LAND:
		_player.seek(ROPE_LAND, true)
		_player.speed_scale = 0.0
	if _current == &"jump" and airborne and _player.current_animation_position >= JUMP_HOLD:
		_player.seek(JUMP_HOLD, true)
		_player.speed_scale = 0.0
	var gripping := farmer.state == Farmer.State.ZIPLINING
	# A held clip is not re-evaluated by advance(), so what is laid over it (the blend, the arms) would stack on its
	# own last result.
	if (_blend_left > 0.0 or gripping or _in_pistol_stance(farmer)) and is_zero_approx(_player.speed_scale):
		_player.seek(_player.current_animation_position, true)
	var gun_up := _holding_gun(farmer) and _fire_hold > 0.0
	if gripping:
		_pose_zipline_arms(farmer, gun_up)
	elif _in_pistol_stance(farmer):
		_pose_pistol_stance()
	var spin := TAU * (1.0 - _spin_left / SPIN_TIME) if _spin_left > 0.0 else 0.0
	(get_parent() as Node3D).rotation.y = spin
	if _spin_left > 0.0:
		_pose_arm_along(SPIN_ARM)
	_hang_offset = move_toward(_hang_offset, _hang_target if gripping else 0.0, ZIPLINE_LOWER_SPEED * TICK)
	position.y = _rest_y + _hang_offset
	if _blend_left > 0.0:
		_blend_pose()
	# The weapon rides the right hand, so it moves with the swing. It is stowed on a ladder, where it cannot be used,
	# on a cable, where both hands are on the line until she fires, and in the tumble off one, where the hands are up by
	# her face.
	if visible:
		_farmer.weapons.visible = farmer.state not in [Farmer.State.CLIMBING, Farmer.State.MANTLING] \
				and (not gripping or gun_up) and (not _hands_by_face() or _fire_hold > 0.0)
		_skeleton.force_update_all_bone_transforms()
		_hold_weapon(farmer, spin)
		_wear_jetpack(farmer)


## Puts the weapons on the hand: the grip in the fist, and the weapon turned with the hand, except for one carried upright
## and the scythe mid-whirl, which is held out along the arm.
func _hold_weapon(farmer: Farmer, spin: float) -> void:
	var hand := _in_farmer(farmer, _hand_bone)
	var wrist := _in_farmer(farmer, _skeleton.get_bone_parent(_hand_bone)).origin
	var weapon := farmer.weapons.current
	var turn := hand.basis * _aim_hand.inverse()
	var slide := Vector3.ZERO
	if _spin_left > 0.0:
		turn = Basis(Vector3.UP, spin) * Basis.looking_at(SPIN_ARM.normalized())
		slide = turn * Vector3.FORWARD * SPIN_GRIP_SLIDE
	elif weapon != null and weapon.hold_upright:
		turn = Basis(Vector3.RIGHT, -CARRY_TIP) * CARRY_UPRIGHT
	farmer.weapons.transform = Transform3D(turn, hand.origin + (hand.origin - wrist).normalized() * FIST_REACH + slide)


## Keeps the pack on her back: it follows the chest bone, turned as far as the chest has turned from its rest.
func _wear_jetpack(farmer: Farmer) -> void:
	var chest := _in_farmer(farmer, _skeleton.find_bone(CHEST))
	var turn := chest.basis * _chest_rest.inverse()
	farmer.jetpack_model.transform = Transform3D(turn, chest.origin + turn * PACK_OFFSET)


## Bone `bone`'s current pose in the farmer's Model frame, without scale.
func _in_farmer(farmer: Farmer, bone: int) -> Transform3D:
	var pose := farmer.model.global_transform.affine_inverse() * _skeleton.global_transform \
			* _skeleton.get_bone_global_pose(bone)
	return Transform3D(pose.basis.orthonormalized(), pose.origin)


func _in_pistol_stance(farmer: Farmer) -> bool:
	var weapon := farmer.weapons.current
	return weapon != null and weapon.pistol_stance and _current in [&"Aim_Idle", &"Aim_Walk", &"Aim_Run", &"Jet_Aim"]


## The aim clips hold a long gun across the body; a pistol gets both arms straight out, the hands meeting on the grip.
func _pose_pistol_stance() -> void:
	_skeleton.force_update_all_bone_transforms()
	var to_pose := (get_parent() as Node3D).global_basis.inverse() * _skeleton.global_basis
	var shoulders: Dictionary = {}
	var reach := 0.0
	for side: String in ARM_CHAINS:
		var chain: Array = ARM_CHAINS[side]
		shoulders[side] = to_pose * _skeleton.get_bone_global_pose(_skeleton.find_bone(chain[0])).origin
		reach = (to_pose * _skeleton.get_bone_rest(_skeleton.find_bone(chain[1])).origin).length() \
				+ (to_pose * _skeleton.get_bone_rest(_skeleton.find_bone(chain[2])).origin).length()
	var right: Vector3 = shoulders["Right"]
	var left: Vector3 = shoulders["Left"]
	var meet := Vector3(STANCE_MEET.x * reach, (right.y + left.y) * 0.5 + STANCE_MEET.y,
			(right.z + left.z) * 0.5 + STANCE_MEET.z * reach)
	for side: String in ARM_CHAINS:
		var chain: Array = ARM_CHAINS[side]
		_aim_arm(_skeleton.find_bone(chain[0]), _skeleton.find_bone(chain[1]), _skeleton.find_bone(chain[2]),
				(to_pose.inverse() * (meet - (shoulders[side] as Vector3))).normalized())
	_level_hand()


## Points the right arm along `direction` (the Pose's frame), for the whirl.
func _pose_arm_along(direction: Vector3) -> void:
	_skeleton.force_update_all_bone_transforms()
	var chain: Array = ARM_CHAINS["Right"]
	var to_skeleton := _skeleton.global_basis.inverse() * (get_parent() as Node3D).global_basis
	_aim_arm(_skeleton.find_bone(chain[0]), _skeleton.find_bone(chain[1]), _skeleton.find_bone(chain[2]),
			(to_skeleton * direction).normalized())


## Turns the right hand to its aiming pose, so the gun in it points straight ahead whatever the arm is doing.
func _level_hand() -> void:
	_skeleton.force_update_all_bone_transforms()
	var to_skeleton := (_skeleton.global_basis.inverse() * _farmer.model.global_basis).orthonormalized()
	var parent_basis := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(_hand_bone)).basis.orthonormalized()
	_skeleton.set_bone_pose_rotation(_hand_bone, (parent_basis.inverse() * to_skeleton * _aim_hand).get_rotation_quaternion())


## Swings the arms to the cable overhead (the right arm points forward while she fires, one hand still on the line),
## then lowers the whole figure until her hands are at cable height. Each arm is turned from the pose the clip left
## it in by the shortest rotation, so the clip's twist stays and nothing snaps.
func _pose_zipline_arms(farmer: Farmer, firing: bool) -> void:
	_skeleton.force_update_all_bone_transforms()
	var to_skeleton := _skeleton.global_transform.basis.inverse() * farmer.model.global_basis
	var hands_y := 0.0
	for side: String in ARM_CHAINS:
		var chain: Array = ARM_CHAINS[side]
		var upper := _skeleton.find_bone(chain[0])
		var lateral := signf(farmer.model.to_local((_skeleton.global_transform
				* _skeleton.get_bone_global_pose(upper)).origin).x)
		var direction := Vector3(-lateral * ZIPLINE_ARM_INWARD, 1.0, 0.0)
		if firing and side == "Right":
			direction = Vector3(0.0, 0.1, -1.0)
		_aim_arm(upper, _skeleton.find_bone(chain[1]), _skeleton.find_bone(chain[2]),
				(to_skeleton * direction).normalized())
	if firing:
		_level_hand()
	_skeleton.force_update_all_bone_transforms()
	for side: String in ARM_CHAINS:
		var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(ARM_CHAINS[side][2]))
		hands_y += farmer.to_local(hand.origin).y * 0.5
	var line := farmer.movement.current_zipline()
	if line != null:
		# Measured with the current drop taken back out, so the target does not chase itself.
		_hang_target = line.hang_height - (hands_y + ZIPLINE_PALM_REACH - _hang_offset)


## Points `upper` and `lower` along `direction` (skeleton space) and leaves the hand in line with the forearm.
func _aim_arm(upper: int, lower: int, hand: int, direction: Vector3) -> void:
	for pair: Array in [[upper, lower], [lower, hand]]:
		var bone: int = pair[0]
		var child: int = pair[1]
		var parent_basis := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(bone)).basis
		var current := parent_basis * Basis(_skeleton.get_bone_pose_rotation(bone))
		var axis := (current * _skeleton.get_bone_rest(child).origin.normalized()).normalized()
		var turned := Basis(Quaternion(axis, direction)) * current
		_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())
	_skeleton.set_bone_pose_rotation(hand, _skeleton.get_bone_rest(hand).basis.get_rotation_quaternion())


## Off a line, the rope clip plays on from the let-go through the tumble, paced so its landing frame arrives with her feet
## at the ground. A short drop (the end of the line, a jump low on it) joins the tumble part way through. Past the
## landing frame she hangs there until she touches down, or braces if the drop turns out to be a long one.
func _rope_flight(farmer: Farmer) -> void:
	var held := _current == &"rope_air" and _player.current_animation_position >= ROPE_LAND
	if held and farmer.velocity.y < -FALL_SPEED:
		_roping_off = false
		_play(FALL, 1.0)
		return
	var airtime := _airtime(farmer)
	if _current != &"rope_air":
		_play(ROPE, 1.0, maxf(ROPE_RELEASE, ROPE_LAND - airtime * ROPE_RATE.y), &"rope_air")
	_roping_off = true
	_player.speed_scale = clampf((ROPE_LAND - _player.current_animation_position) / maxf(airtime, TICK),
			ROPE_RATE.x, ROPE_RATE.y)


## Her touchdown after the tumble: the crouch and the rise to standing, starting from the landing frame (cut to if she
## came down early). Returns false, and lets the usual poses take over, once she is up or the stick is held.
func _rope_landing(farmer: Farmer) -> bool:
	if farmer.input.move_vector().length() > ROPE_RUN_STICK \
			or (_current == &"rope_land" and _player.current_animation_position >= ROPE_END):
		_roping_off = false
		return false
	if _current != &"rope_land":
		var from := _player.current_animation_position if _current == &"rope_air" else 0.0
		_play(ROPE, ROPE_LAND_RATE, maxf(from, ROPE_LAND - 0.05), &"rope_land")
	return true


## True while the rope clip has her hands up by her face, where the weapon would cover it.
func _hands_by_face() -> bool:
	return _current == &"rope_air" \
			or (_current == &"rope_land" and _player.current_animation_position < ROPE_HANDS_DOWN)


## Seconds until the farmer reaches the floor under her at her current fall speed.
func _airtime(farmer: Farmer) -> float:
	var gravity := farmer.movement.gravity
	var rise := farmer.velocity.y
	return (rise + sqrt(rise * rise + 2.0 * gravity * farmer.movement.height_above_floor())) / gravity


func _ground(farmer: Farmer, flat: Vector2, speed: float, gun: bool, reload_time: float) -> void:
	if gun:
		var forward := Vector2(0.0, -1.0).rotated(-farmer.model.rotation.y)
		var running := speed > RUN_THRESHOLD
		var rate := clampf(speed / RUN_SPEED, RUN_RATE.x, RUN_RATE.y) if running \
				else clampf(speed / WALK_SPEED, WALK_RATE.x, WALK_RATE.y)
		if speed > 0.5:
			# Backing away plays the legs in reverse.
			_play(&"Aim_Run" if running else &"Aim_Walk", -rate if flat.dot(forward) < 0.0 else rate)
		elif reload_time > 0.0:
			_play(RELOAD, _player.get_animation(RELOAD).length / reload_time)
		else:
			_play(&"Aim_Idle", 0.0)
	elif speed > RUN_THRESHOLD:
		_play(&"Running", clampf(speed / RUN_SPEED, RUN_RATE.x, RUN_RATE.y))
	elif speed > 0.5:
		_play(&"Walking", clampf(speed / WALK_SPEED, WALK_RATE.x, WALK_RATE.y))
	else:
		_play(IDLE, 1.0)


## The reload time of the gun in hand while it is reloading, otherwise 0.
func _reload_time(farmer: Farmer) -> float:
	var weapon := farmer.weapons.current as Pistol
	if weapon == null or not weapon.is_reloading():
		return 0.0
	return weapon.stat(weapon.data.reload_stat, weapon.data.reload_time)


## Real seconds the death clip takes at DEATH_RATE, so the farmer's stats can wait for the fall to finish.
func death_seconds() -> float:
	return _player.get_animation(DEATH).length / DEATH_RATE


## Plays `clip` at `speed` (negative runs it backward, zero holds it). A change of clip, or of `label`, which names a
## clip held or played in a special way, starts it at `from` seconds and fades in from the pose on screen.
func _play(clip: StringName, speed: float, from: float = 0.0, label: StringName = &"") -> void:
	var key := clip if label == &"" else label
	_player.speed_scale = speed
	if key == _current:
		return
	if _current != &"":
		_snapshot_pose()
	_current = key
	_player.play(clip)
	_player.seek(from, true)


func _snapshot_pose() -> void:
	var count := _skeleton.get_bone_count()
	_from_position.resize(count)
	_from_rotation.resize(count)
	for i in count:
		_from_position[i] = _skeleton.get_bone_pose_position(i)
		_from_rotation[i] = _skeleton.get_bone_pose_rotation(i)
	_blend_left = BLEND


## Mixes the pose the clip just wrote with the snapshot taken when it started, the snapshot fading out.
func _blend_pose() -> void:
	_blend_left = maxf(0.0, _blend_left - TICK)
	var old := smoothstep(0.0, 1.0, _blend_left / BLEND)
	for i in _skeleton.get_bone_count():
		_skeleton.set_bone_pose_position(i, _skeleton.get_bone_pose_position(i).lerp(_from_position[i], old))
		_skeleton.set_bone_pose_rotation(i, _skeleton.get_bone_pose_rotation(i).slerp(_from_rotation[i], old))


func _holding_gun(farmer: Farmer) -> bool:
	var weapon := farmer.weapons.current
	return weapon != null and not (weapon is Wrench or weapon is SweepWeapon)


## Builds `clip_name` from the legs and hips of `legs_from` and the torso, arms and head of `upper_from`'s first frame
## (the aiming pose unless named). A negative `hold` loops the legs; otherwise they are held at that time.
func _build_aim_clip(clip_name: String, legs_from: String, hold: float = -1.0, upper_from: String = AIM_POSE) -> void:
	var library := _player.get_animation_library(&"")
	if library.has_animation(clip_name):
		return  # The glb's animations are shared by every instance of it.
	var legs := _player.get_animation(legs_from)
	var aim := _player.get_animation(upper_from)
	var built := Animation.new()
	built.length = legs.length if hold < 0.0 else TICK
	built.loop_mode = Animation.LOOP_LINEAR if hold < 0.0 else Animation.LOOP_NONE
	for t in legs.get_track_count():
		if _is_lower_body(legs.track_get_path(t)):
			if hold < 0.0:
				legs.copy_track(t, built)
			else:
				_add_sampled_track(built, legs, t, hold)
	for t in aim.get_track_count():
		if not _is_lower_body(aim.track_get_path(t)):
			_add_sampled_track(built, aim, t, 0.0)
	library.add_animation(clip_name, built)


func _is_lower_body(path: NodePath) -> bool:
	var bone := String(path).get_slice(":", 1)
	return bone.ends_with("Hips") or "Leg" in bone or "Foot" in bone or "Toe" in bone


## Adds a one-key copy of track `t` of `source`, sampled at `time`, to `target`.
func _add_sampled_track(target: Animation, source: Animation, t: int, time: float) -> void:
	var type := source.track_get_type(t)
	var index := target.add_track(type)
	target.track_set_path(index, source.track_get_path(t))
	match type:
		Animation.TYPE_POSITION_3D:
			target.position_track_insert_key(index, 0.0, source.position_track_interpolate(t, time))
		Animation.TYPE_ROTATION_3D:
			target.rotation_track_insert_key(index, 0.0, source.rotation_track_interpolate(t, time))
		Animation.TYPE_SCALE_3D:
			target.scale_track_insert_key(index, 0.0, source.scale_track_interpolate(t, time))


## Pins the hips over the feet so the clips play in place: sideways and forward motion is replaced by the rig's
## rest position (some clips are baked offset from it), and the ladder clip's climb is flattened too, since the
## ladder moves the farmer. Jumping and the rope keep their vertical motion.
func _strip_root_motion(anim: Animation, flatten_height: bool) -> void:
	var rest := _skeleton.get_bone_rest(_skeleton.find_bone(HIPS)).origin
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D or not str(anim.track_get_path(t)).ends_with(HIPS):
			continue
		var keys := anim.track_get_key_count(t)
		var mean_y := 0.0
		for k in keys:
			mean_y += (anim.track_get_key_value(t, k) as Vector3).y / keys
		for k in keys:
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(rest.x, mean_y if flatten_height else v.y, rest.z))


## Reads the two frames the held things are placed from, in the farmer's Model frame (this node is turned 180 degrees
## in it): the right hand in the aiming pose and the chest at rest.
func _measure_rest_frames() -> void:
	var to_model := (basis * (global_basis.inverse() * _skeleton.global_basis)).orthonormalized()
	_chest_rest = (to_model * _skeleton.get_bone_global_rest(_skeleton.find_bone(CHEST)).basis).orthonormalized()
	_player.play(&"Aim_Idle")
	_player.seek(0.0, true)
	_skeleton.force_update_all_bone_transforms()
	_aim_hand = (to_model * _skeleton.get_bone_global_pose(_hand_bone).basis).orthonormalized()


## Scales the model to HEIGHT and stands its feet on the origin, whatever units the file was exported in. Measured
## from the rest-pose skeleton, since a skinned mesh's own bounds are not in model space.
func _fit_to_height() -> void:
	var to_self := global_transform.affine_inverse() * _skeleton.global_transform
	var top := (to_self * _skeleton.get_bone_global_rest(_skeleton.find_bone(HEAD_TOP))).origin.y
	var feet := minf((to_self * _skeleton.get_bone_global_rest(_skeleton.find_bone(FOOT_L))).origin.y,
			(to_self * _skeleton.get_bone_global_rest(_skeleton.find_bone(FOOT_R))).origin.y)
	if top - feet <= 0.001:
		return
	var s := HEIGHT / (top - feet)
	scale = Vector3.ONE * s
	_rest_y = -feet * s
	position.y = _rest_y
