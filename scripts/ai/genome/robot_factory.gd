class_name RobotFactory
extends RefCounted
## Builds a robot's look (GDD 10.1, 10.4) from the sculpted monowheel robot's parts (RobotSkin), repainted in the
## family's palette and bent to its body and head genes, with clay primitives for the genes the sculpt doesn't have:
## eye style, antenna, weapon, accessories. Legs are the sculpt's arms, on boots cut from its tyre and mudguard. Everything shares the clay shader with per-part instance
## uniforms, so robots never duplicate materials. Families differ on the sculpt's skin by color only: the pattern and wear
## genes still roll, so family codes keep their looks, but aren't painted on.
##
## Readability locks (never broken by the genome): type sets the scale and locomotion family; class sets
## the weapon arm, eye glow color and chest icon; weak points get hazard trim and a glow. Every robot
## carries the Factory DNA: the BOLT Co. winged cog on its chest and an antenna bulb that blinks with its wave.
## An archetype's tells (M2-B9: the Clanker's arm guard, the Spitter's pea-shooter, the throwers' ammo) are
## built under a node named after the tell, so the robot can hide one that isn't live yet this wave.
## Parts are authored at Scout size; the kit node is scaled per type.

## Eye glow by class: melee red, short-range amber, long-range blue.
## By RobotArchetype.RobotClass: melee red, ranged blue, flight amber (GDD 9.2).
const CLASS_EYE_COLORS: Array[Color] = [Color(1.0, 0.16, 0.1), Color(0.3, 0.6, 1.0), Color(1.0, 0.62, 0.1)]
## Scout 0.8 m, Grunt 1.4 m, Heavy 2.6 m (GDD 9.1), relative to the Scout layout.
const TYPE_SCALES: PackedFloat32Array = [1.0, 1.75, 2.8]
const HAZARD := Color(1.0, 0.82, 0.12)
const GOLD := Color(1.0, 0.8, 0.25)
const DARK := Color(0.16, 0.15, 0.16)
const METAL := Color(0.62, 0.64, 0.68)
const BULB_COLOR := Color(1.0, 0.85, 0.35)
const COPPER := Color(0.78, 0.45, 0.22)
## Overcharged's electric blue (the coil core, the crackle and the blast's sparks).
const SPARK_COLOR := Color(0.55, 0.85, 1.0)
## Name of the Overcharged coil's glowing core under the kit.
const SPARK_CORE := &"SparkCore"

## Sockets at Scout size (y up, front = -Z).
const BODY := Vector3(0.0, 0.57, 0.0)
const HEAD := Vector3(0.0, 0.9, 0.0)
const EYE := Vector3(-0.01, 0.905, -0.18)
const ANTENNA := Vector3(0.0, 1.05, 0.0)
## Where legs and their guard meet the bottom of the torso.
const HIP_Y := 0.4
const ARM_WEAPON := Vector3(0.39, 0.4, 0.0)
const ARM_OFF := Vector3(-0.517, 0.38, -0.09)
const CHEST := Vector3(0.0, 0.5, -0.19)
const BACK := Vector3(0.0, 0.62, 0.33)
## The sculpt's two goggles, relative to the head part's pivot.
const GOGGLES: Array[Vector3] = [Vector3(-0.09, -0.002, -0.178), Vector3(0.086, 0.003, -0.168)]
## Accessories that sit on the head, so they ride up and down with its shape.
const HAT_ACCESSORIES: Array[StringName] = [&"tin_hat", &"mirror_ball", &"star_glasses", &"afro", &"bandana", &"tricorn", &"crown"]

static var _meshes: Dictionary[String, Mesh] = {}


## What the robot script animates after the build.
class Look:
	var bulb: MeshInstance3D
	var eyes: Array[MeshInstance3D] = []
	var wheels: Array[Node3D] = []


## A family's paint for the sculpted parts.
class Paint:
	var primary: Color
	var secondary: Color
	var trim: Color


## Builds the robot's look under `pose` (a fresh "Kit" child). `cosmetic` drives the per-robot jitter.
static func build(pose: Node3D, genome: RobotGenome, archetype: RobotArchetype, cosmetic: RandomNumberGenerator,
		is_foreman: bool = false, extra_traits: Array[RobotTrait] = []) -> Look:
	var old := pose.get_node_or_null(^"Kit")
	if old != null:
		old.free()
	var kit := Node3D.new()
	kit.name = "Kit"
	pose.add_child(kit)
	var type_index := int(archetype.robot_type)
	kit.scale = Vector3.ONE * TYPE_SCALES[type_index] * genome.size * cosmetic.randf_range(0.95, 1.05)

	var traits: Array[RobotTrait] = genome.traits.duplicate()
	traits.append_array(extra_traits)
	var gilded := traits.any(func(t: RobotTrait) -> bool: return t.id == &"gilded")
	var hue_shift := cosmetic.randf_range(-0.04, 0.04)
	var primary := _shift_hue(genome.palette.primary, hue_shift)
	var secondary := _shift_hue(genome.palette.secondary, hue_shift)
	var trim := GOLD if gilded else genome.palette.trim
	var eye_color := CLASS_EYE_COLORS[int(archetype.robot_class)]

	var paint := Paint.new()
	paint.primary = primary
	paint.secondary = secondary
	paint.trim = trim

	var look := Look.new()
	var shoulder_shift := _body(kit, genome.body_shape, paint)
	var head_settings := RobotSkin.HEAD_MORPHS.get(genome.head, {}) as Dictionary
	var head_mount := _head(kit, genome.head, head_settings, shoulder_shift.y, paint)
	look.eyes = _eyes(head_mount, genome.eye_style, head_settings, eye_color, trim)
	look.bulb = _antenna(head_mount.get_node(^"HatMount") as Node3D, genome.antenna, paint)
	var locomotion := genome.locomotion_by_type[type_index] if type_index < genome.locomotion_by_type.size() else &"unicycle"
	# The Nibbler is the monowheel itself; other Scouts may still roll a pogo.
	if archetype.id == &"nibbler":
		locomotion = &"unicycle"
	look.wheels = _locomotion(kit, locomotion, archetype.robot_class == RobotArchetype.RobotClass.FLIGHT, paint)
	_arms(kit, archetype.robot_class, genome.melee_arm, shoulder_shift, paint)
	_chest_icon(kit, eye_color)
	_pack(kit, genome.body_shape, paint)

	_accessory(kit, genome.accessory, primary, secondary, trim)
	if cosmetic.randf() < 0.2 and not genome.theme.accessories.is_empty():
		var extra := genome.theme.accessories[cosmetic.randi_range(0, genome.theme.accessories.size() - 1)]
		if extra != genome.accessory:
			_accessory(kit, extra, primary, secondary, trim)
	for robot_trait in traits:
		_accessory(kit, robot_trait.tell, primary, secondary, trim)
	if is_foreman:
		_accessory(kit, &"crown", primary, secondary, GOLD)
	for tell in archetype.tells:
		var holder := Node3D.new()
		holder.name = String(tell)
		kit.add_child(holder)
		_accessory(holder, tell, primary, secondary, trim)
	if archetype.robot_type == RobotArchetype.RobotType.HEAVY:
		# Weak point on the back (Thumper's vent): hazard-striped and glowing (readability lock).
		_part(kit, _box(Vector3(0.24, 0.2, 0.06)), HAZARD, BACK + Vector3(0.0, 0.04, 0.02), Vector3.ZERO, 0.6, 5, DARK)
	return look


## The stolen grain sack a fleeing thief carries on its back.
static func attach_sack(kit: Node3D) -> void:
	if kit != null:
		_accessory(kit, &"sack", Color.WHITE, Color.WHITE, Color.WHITE)


# --- Body parts -----------------------------------------------------------------------------------

## The torso, resting on the locomotion. Returns how far the shape moved the shoulders (y: and the neck) from the sculpt's.
static func _body(kit: Node3D, shape: StringName, paint: Paint) -> Vector3:
	var settings := RobotSkin.BODY_MORPHS.get(shape, {}) as Dictionary
	var shell := RobotSkin.TORSO_SHELL
	var bottom := RobotSkin.bend_point(Vector3(0.0, -shell.y, 0.0), settings, shell).y
	var center := RobotSkin.socket(&"torso") + Vector3(0.0, -shell.y - bottom, 0.0)
	_skin(kit, RobotSkin.morphed(&"torso", shape, settings, shell), center, Vector3.ZERO, paint)
	var trim := paint.trim
	match shape:
		&"tin_can":
			_part(kit, _cyl(0.2, 0.2, 0.025), trim, center + Vector3(0.0, 0.155, 0.0))
		&"toaster":
			for x: float in [-0.08, 0.08]:
				_part(kit, _box(Vector3(0.05, 0.02, 0.22)), DARK, center + Vector3(x, 0.165, 0.0))
		&"barrel":
			for y: float in [-0.09, 0.09]:
				_part(kit, _cyl(0.225, 0.225, 0.03), trim, center + Vector3(0.0, y, 0.0))
		&"lunchbox":
			_part(kit, _box(Vector3(0.1, 0.05, 0.03)), trim, center + Vector3(0.0, 0.11, -0.17))
	var shoulder := Vector3(0.206, 0.09, 0.0)
	var bent := RobotSkin.bend_point(shoulder, settings, shell)
	var top := RobotSkin.bend_point(Vector3(0.0, shell.y, 0.0), settings, shell).y + center.y
	return Vector3(bent.x - shoulder.x, top - RobotSkin.socket(&"torso").y - shell.y, 0.0)


## The head and what rides on it, under a mount lifted by `lift` so it stays on the neck. Its "HatMount" child follows
## the top of the head.
static func _head(kit: Node3D, shape: StringName, settings: Dictionary, lift: float, paint: Paint) -> Node3D:
	var mount := Node3D.new()
	mount.name = "HeadMount"
	mount.position.y = lift
	kit.add_child(mount)
	var shell := RobotSkin.HEAD_SHELL
	var bottom := RobotSkin.bend_point(Vector3(0.0, -shell.y, 0.0), settings, shell).y
	var center := RobotSkin.socket(&"head") + Vector3(0.0, -shell.y - bottom, 0.0)
	mount.set_meta(&"head_center", center)
	_skin(mount, RobotSkin.morphed(&"head", shape, settings, shell), center, Vector3.ZERO, paint)
	var hats := Node3D.new()
	hats.name = "HatMount"
	hats.position.y = center.y + RobotSkin.bend_point(Vector3(0.0, shell.y, 0.0), settings, shell).y - RobotSkin.socket(&"head").y - shell.y
	mount.add_child(hats)
	var trim := paint.trim
	match shape:
		&"bucket":
			_part(hats, _cyl(0.2, 0.2, 0.025), trim, HEAD + Vector3(0.0, 0.14, 0.0))
		&"light_bulb":
			_part(mount, _cyl(0.1, 0.1, 0.05), trim, RobotSkin.socket(&"head") + Vector3(0.0, -0.15, 0.0))
		&"teapot":
			_part(mount, _cyl(0.025, 0.05, 0.18), paint.primary, center + Vector3(0.24, 0.0, 0.0), Vector3(0.0, 0.0, -0.9))
			_part(hats, _sphere(0.035, 0.07), trim, HEAD + Vector3(0.0, 0.17, 0.0))
		&"mailbox":
			_part(mount, _box(Vector3(0.03, 0.12, 0.03)), Color(0.9, 0.2, 0.15), center + Vector3(0.17, 0.03, 0.08))
	return mount


## Eye glow is the class lock, so every style gets its own glowing lens: twin goggles glow in the sculpt's sockets, and
## the rest wear a plate over them.
static func _eyes(mount: Node3D, style: StringName, settings: Dictionary, eye_color: Color, trim: Color) -> Array[MeshInstance3D]:
	var eyes: Array[MeshInstance3D] = []
	var facing := Vector3(PI * 0.5, 0.0, 0.0)  # cylinder axis toward -Z
	var center := mount.get_meta(&"head_center") as Vector3
	var left := center + RobotSkin.bend_point(GOGGLES[0], settings, RobotSkin.HEAD_SHELL)
	var right := center + RobotSkin.bend_point(GOGGLES[1], settings, RobotSkin.HEAD_SHELL)
	var mid := (left + right) * 0.5
	var width := right.x - left.x + 0.1
	match style:
		&"twin_goggles":
			for at: Vector3 in [left, right]:
				eyes.append(_part(mount, _cyl(0.034, 0.034, 0.02), eye_color, at, facing, 2.5))
		&"visor":
			_part(mount, _box(Vector3(width, 0.09, 0.03)), DARK, mid)
			eyes.append(_part(mount, _box(Vector3(width - 0.04, 0.035, 0.04)), eye_color, mid + Vector3(0.0, 0.0, -0.01), Vector3.ZERO, 2.5))
			_part(mount, _box(Vector3(width + 0.02, 0.016, 0.04)), trim, mid + Vector3(0.0, 0.05, 0.0))
		&"led_grid":
			_part(mount, _box(Vector3(width, 0.12, 0.03)), DARK, mid)
			eyes.append(_part(mount, _box(Vector3(width - 0.04, 0.08, 0.04)), eye_color, mid + Vector3(0.0, 0.0, -0.005), Vector3.ZERO, 2.5, 3, eye_color.darkened(0.5)))
		&"monocle":
			_part(mount, _cyl(0.062, 0.062, 0.03), trim, left, facing)
			eyes.append(_part(mount, _cyl(0.055, 0.055, 0.04), eye_color, right + Vector3(0.0, 0.0, -0.01), facing, 2.5))
			_part(mount, _torus(0.05, 0.075), trim, right + Vector3(0.0, 0.0, -0.01), facing)
		_:  # cyclops
			_part(mount, _box(Vector3(width, 0.13, 0.03)), trim, mid)
			eyes.append(_part(mount, _cyl(0.055, 0.055, 0.05), eye_color, mid + Vector3(0.0, 0.0, -0.015), facing, 2.5))
			_part(mount, _torus(0.05, 0.075), DARK, mid + Vector3(0.0, 0.0, -0.015), facing)
	return eyes


## Returns the bulb, which every robot has on top of its antenna (Factory DNA).
static func _antenna(kit: Node3D, style: StringName, paint: Paint) -> MeshInstance3D:
	var secondary := paint.secondary
	var trim := paint.trim
	var top := ANTENNA + Vector3(0.0, 0.22, 0.0)
	match style:
		&"spring":
			for i in 4:
				_part(kit, _torus(0.025, 0.045), trim, ANTENNA + Vector3(0.0, 0.03 + 0.045 * i, 0.0))
			top = ANTENNA + Vector3(0.0, 0.22, 0.0)
		&"dish":
			_part(kit, _cyl(0.012, 0.012, 0.18), DARK, ANTENNA + Vector3(0.0, 0.09, 0.0))
			_part(kit, _cyl(0.11, 0.03, 0.04), trim, ANTENNA + Vector3(0.0, 0.16, 0.0), Vector3(0.5, 0.0, 0.0))
			top = ANTENNA + Vector3(0.0, 0.24, 0.0)
		&"propeller":
			_part(kit, _cyl(0.012, 0.012, 0.18), DARK, ANTENNA + Vector3(0.0, 0.09, 0.0))
			_part(kit, _box(Vector3(0.3, 0.012, 0.05)), secondary, ANTENNA + Vector3(0.0, 0.17, 0.0))
			top = ANTENNA + Vector3(0.0, 0.21, 0.0)
		&"lightning_rod":
			_part(kit, _cyl(0.004, 0.025, 0.32), METAL, ANTENNA + Vector3(0.0, 0.16, 0.0))
			top = ANTENNA + Vector3(0.0, 0.34, 0.0)
		&"whisk":
			for angle: float in [-0.35, 0.0, 0.35]:
				_part(kit, _box(Vector3(0.012, 0.24, 0.012)), METAL, ANTENNA + Vector3(sin(angle) * 0.05, 0.12, 0.0), Vector3(0.0, 0.0, -angle))
			top = ANTENNA + Vector3(0.0, 0.25, 0.0)
		_:  # bulb: the sculpt's own stem
			var stem := RobotSkin.socket(&"antenna")
			_skin(kit, RobotSkin.mesh(&"antenna"), stem, Vector3.ZERO, paint)
			top = stem + Vector3(-0.001, 0.07, 0.001)
	return _part(kit, _sphere(0.035, 0.07), BULB_COLOR, top, Vector3.ZERO, 0.5)


static func _locomotion(kit: Node3D, style: StringName, flying: bool, paint: Paint) -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	var axle := Vector3(0.0, 0.0, PI * 0.5)  # cylinder axis along X
	# A flier hovers on its rotor, with no use for legs (its wheel is hidden on spawn).
	match &"unicycle" if flying else style:
		&"pogo":
			_guard(kit, Vector3(0.0, HIP_Y, 0.0), Vector3(1.1, 0.5, 0.7), paint)
			_leg(kit, &"arm_left", Vector3(0.0, HIP_Y, 0.0), Vector3(0.0, 0.05, 0.0), 1.1, paint)
			_tyre(kit, Vector3(0.0, 0.05, 0.0), 0.62, Vector3.ZERO, paint)  # laid flat: the pogo's rubber pad
		&"waddle_legs":
			_guard(kit, Vector3(0.0, HIP_Y, 0.0), Vector3(1.75, 0.5, 0.7), paint)
			for x: float in [-0.14, 0.14]:
				_leg(kit, &"arm_left" if x < 0.0 else &"arm_right", Vector3(x, HIP_Y, 0.0), Vector3(x, 0.09, -0.02), 1.0, paint)
				_boot(kit, Vector3(x, 0.0, -0.03), 1.0, paint)
		&"mini_treads":
			for x: float in [-0.17, 0.17]:
				wheels.append(_tyre(kit, Vector3(x, 0.17, 0.0), 0.75, axle, paint))
				_guard(kit, Vector3(x, 0.3, 0.0), Vector3(1.0, 0.6, 0.85), paint)
			_waist(kit, 0.75, paint)
		&"tripod":
			_guard(kit, Vector3(0.0, HIP_Y, 0.0), Vector3(1.5, 0.5, 0.85), paint)
			for angle: float in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
				var out := Vector3(sin(angle), 0.0, cos(angle))
				var foot := out * 0.3
				_leg(kit, &"arm_left" if out.x < 0.0 else &"arm_right", out * 0.08 + Vector3(0.0, HIP_Y, 0.0), foot + Vector3(0.0, 0.1, 0.0), 0.85, paint)
				wheels.append(_tyre(kit, foot + Vector3(0.0, 0.09, 0.0), 0.4, axle, paint))
				_guard(kit, foot + Vector3(0.0, 0.14, 0.0), Vector3(0.6, 0.34, 0.45), paint)
		&"treads":
			for x: float in [-0.18, 0.18]:
				for z: float in [-0.17, 0.17]:
					wheels.append(_tyre(kit, Vector3(x, 0.16, z), 0.7, axle, paint))
				_guard(kit, Vector3(x, 0.29, 0.0), Vector3(0.95, 0.6, 1.55), paint)
			_waist(kit, 1.1, paint)
		&"four_legs":
			_guard(kit, Vector3(0.0, HIP_Y, 0.0), Vector3(2.0, 0.5, 1.1), paint)
			for x: float in [-0.17, 0.17]:
				for z: float in [-0.15, 0.15]:
					_leg(kit, &"arm_left" if x < 0.0 else &"arm_right", Vector3(x, HIP_Y, z), Vector3(x, 0.08, z), 1.0, paint)
					_boot(kit, Vector3(x, 0.0, z - 0.01), 0.75, paint)
		&"giant_wheel":
			wheels.append(_wheel(kit, 1.14, flying, axle, paint))
		_:  # unicycle
			wheels.append(_wheel(kit, 1.0, flying, axle, paint))
	return wheels


## The sculpt's mudguard, squashed and stretched by `shape` over what it covers.
static func _guard(kit: Node3D, at: Vector3, shape: Vector3, paint: Paint) -> MeshInstance3D:
	var guard := _skin(kit, RobotSkin.mesh(&"fender"), at, Vector3.ZERO, paint)
	guard.scale = shape
	return guard


## What joins the torso to wheels that sit out to its sides: a broad guard over a bellows, down between them.
static func _waist(kit: Node3D, depth: float, paint: Paint) -> void:
	_guard(kit, Vector3(0.0, HIP_Y, 0.0), Vector3(2.0, 0.5, depth), paint)
	_leg(kit, &"arm_left", Vector3(0.0, HIP_Y, 0.0), Vector3(0.0, 0.2, 0.0), 1.2, paint)


## One of the sculpt's arms as a leg, its shoulder at `hip` and its wrist at `ankle`: `girth` thickens it across its length.
static func _leg(kit: Node3D, arm: StringName, hip: Vector3, ankle: Vector3, girth: float, paint: Paint) -> MeshInstance3D:
	var wrist := RobotSkin.socket(&"claw_left" if arm == &"arm_left" else &"claw_right") - RobotSkin.socket(arm)
	var reach := ankle - hip
	var upright := Basis(Quaternion(wrist.normalized(), Vector3.DOWN))
	var size := Basis.from_scale(Vector3(girth, reach.length() / wrist.length(), girth))  # a short leg squashes its bellows
	var leg := _skin(kit, RobotSkin.mesh(arm), hip, Vector3.ZERO, paint)
	leg.basis = Basis(Quaternion(Vector3.DOWN, reach.normalized())) * size * upright
	return leg


## A rubber-soled boot on the ground at `at`: a flattened tyre, capped by a mudguard toe to heel.
static func _boot(kit: Node3D, at: Vector3, size: float, paint: Paint) -> void:
	var sole := _tyre(kit, at + Vector3(0.0, 0.03 * size, 0.0), 0.5 * size, Vector3.ZERO, paint)
	sole.scale.z *= 1.25
	_guard(kit, at + Vector3(0.0, 0.08 * size, 0.0), Vector3(0.95, 0.5, 0.62) * size, paint)


## The sculpt's wheel under its mudguard. A flier hides its wheel, and has no use for the guard.
static func _wheel(kit: Node3D, size: float, flying: bool, axle: Vector3, paint: Paint) -> MeshInstance3D:
	var hub := RobotSkin.socket(&"wheel")
	var wheel := _tyre(kit, Vector3(hub.x, hub.y * size, hub.z), size, axle, paint)
	if not flying:
		var guard := RobotSkin.socket(&"fender")
		var fender := _skin(kit, RobotSkin.mesh(&"fender"), Vector3(guard.x, hub.y * size + (guard.y - hub.y) * size, guard.z), Vector3.ZERO, paint)
		fender.scale = Vector3.ONE * size
	return wheel


static func _tyre(kit: Node3D, at: Vector3, size: float, axle: Vector3, paint: Paint) -> MeshInstance3D:
	var tyre := _skin(kit, RobotSkin.mesh(&"wheel"), at, axle, paint)
	tyre.scale = Vector3.ONE * size
	return tyre


## The sculpt's arms: the right reaches forward with the weapon, the left hangs back with its claw.
## Class lock: melee robots always carry a claw, fist or hammer; the others carry a gun barrel in place of the claw.
static func _arms(kit: Node3D, robot_class: RobotArchetype.RobotClass, style: StringName, shift: Vector3, paint: Paint) -> void:
	var trim := paint.trim
	var off := Vector3(-shift.x, shift.y, 0.0)
	var weapon := Vector3(shift.x, shift.y, 0.0)
	_skin(kit, RobotSkin.mesh(&"arm_left"), RobotSkin.socket(&"arm_left") + off, Vector3.ZERO, paint)
	_skin(kit, RobotSkin.mesh(&"claw_left"), RobotSkin.socket(&"claw_left") + off, Vector3.ZERO, paint)
	_skin(kit, RobotSkin.mesh(&"arm_right"), RobotSkin.socket(&"arm_right") + weapon, Vector3.ZERO, paint)
	var hand := ARM_WEAPON + weapon + Vector3(0.0, 0.0, -0.22)
	var along := Vector3(PI * 0.5, 0.0, 0.0)
	if robot_class != RobotArchetype.RobotClass.MELEE:
		_part(kit, _cyl(0.05, 0.07, 0.16), METAL, hand, along)
		return
	match style:
		&"fist":
			_part(kit, _sphere(0.075, 0.15), trim, hand)
		&"hammer":
			_part(kit, _cyl(0.025, 0.025, 0.2), METAL, hand + Vector3(0.0, 0.0, -0.06), along)
			_part(kit, _cyl(0.08, 0.08, 0.24), METAL, hand + Vector3(0.0, 0.0, -0.17), Vector3(0.0, 0.0, PI * 0.5))
		_:  # claw
			_skin(kit, RobotSkin.mesh(&"claw_right"), RobotSkin.socket(&"claw_right") + weapon, Vector3.ZERO, paint)


## The class icon under the sculpt's winged cog (melee: a little fist).
static func _chest_icon(kit: Node3D, eye_color: Color) -> void:
	_part(kit, _sphere(0.03, 0.06), eye_color, CHEST, Vector3.ZERO, 0.8)


## The sculpt's twin tanks and gauge, carried on the back of the torso's shape.
static func _pack(kit: Node3D, shape: StringName, paint: Paint) -> void:
	var settings := RobotSkin.BODY_MORPHS.get(shape, {}) as Dictionary
	var shell := RobotSkin.TORSO_SHELL
	var back := RobotSkin.bend_point(Vector3(0.0, 0.0, shell.z), settings, shell).z - shell.z
	_skin(kit, RobotSkin.mesh(&"pack"), RobotSkin.socket(&"pack") + Vector3(0.0, 0.0, back), Vector3.ZERO, paint)


static func _accessory(parent: Node3D, id: StringName, _primary: Color, secondary: Color, trim: Color) -> void:
	var kit := parent
	if id in HAT_ACCESSORIES:
		var hats := parent.get_node_or_null(^"HeadMount/HatMount") as Node3D
		if hats != null:
			kit = hats
	match id:
		&"tin_hat":
			_part(kit, _cyl(0.1, 0.14, 0.07), METAL, HEAD + Vector3(0.1, 0.19, 0.0), Vector3(0.0, 0.0, -0.4))
		&"exhaust_pipe":
			_part(kit, _cyl(0.035, 0.035, 0.32), METAL, BACK + Vector3(0.12, 0.12, 0.02))
			_part(kit, _cyl(0.045, 0.045, 0.03), DARK, BACK + Vector3(0.12, 0.29, 0.02))
		&"mirror_ball":
			_part(kit, _sphere(0.07, 0.14), Color(0.85, 0.88, 0.95), HEAD + Vector3(-0.2, 0.12, 0.0), Vector3.ZERO, 0.4, 3, Color(0.5, 0.55, 0.7))
		&"star_glasses":
			for x: float in [-0.08, 0.08]:
				_part(kit, _cyl(0.05, 0.05, 0.02, 5), Color(1.0, 0.4, 0.8), HEAD + Vector3(x - 0.01, 0.005, -0.2), Vector3(PI * 0.5, 0.0, 0.0))
		&"afro":
			_part(kit, _sphere(0.2, 0.34), secondary.darkened(0.3), HEAD + Vector3(0.0, 0.1, 0.07))
		&"bandana":
			_part(kit, _cyl(0.185, 0.185, 0.06), Color(0.85, 0.15, 0.15), HEAD + Vector3(0.0, 0.1, 0.0), Vector3.ZERO, 0.0, 2, Color.WHITE)
			_part(kit, _sphere(0.05, 0.1), Color(0.85, 0.15, 0.15), HEAD + Vector3(0.0, 0.1, 0.2))
		&"tricorn":
			_part(kit, _box(Vector3(0.38, 0.06, 0.24)), DARK, HEAD + Vector3(0.0, 0.17, 0.0))
			_part(kit, _box(Vector3(0.2, 0.08, 0.14)), DARK, HEAD + Vector3(0.0, 0.22, 0.0))
		&"hook":
			_part(kit, _torus(0.03, 0.055), METAL, ARM_OFF + Vector3(0.0, -0.14, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
		&"speed_fins":
			for x: float in [-0.12, 0.12]:
				_part(kit, _box(Vector3(0.02, 0.16, 0.14)), Color(1.0, 0.95, 0.9), BACK + Vector3(x, 0.05, 0.04), Vector3(0.0, 0.0, x * 3.0))
		&"armor_plates":
			for x: float in [-0.21, 0.21]:
				_part(kit, _box(Vector3(0.05, 0.26, 0.28)), METAL, BODY + Vector3(x, -0.03, 0.0))
		&"spark_coil":
			# Overcharged's tell: a copper coil on a mast with a glowing core that crackles (Robot._on_tick_12).
			_part(kit, _cyl(0.025, 0.025, 0.3), METAL, BACK + Vector3(0.0, 0.3, 0.04))
			for y: float in [0.36, 0.42, 0.48]:
				_part(kit, _torus(0.05, 0.075), COPPER, BACK + Vector3(0.0, y, 0.04))
			var core := _part(kit, _sphere(0.07, 0.14), SPARK_COLOR, BACK + Vector3(0.0, 0.58, 0.04), Vector3.ZERO, 3.0)
			core.name = SPARK_CORE
		&"gold_band":
			_part(kit, _cyl(0.225, 0.225, 0.05), GOLD, BODY + Vector3(0.0, -0.1, 0.0), Vector3.ZERO, 0.3)
		&"sack":
			_part(kit, _sphere(0.13, 0.22), Color(0.72, 0.58, 0.38), BACK + Vector3(0.0, 0.0, 0.08))
			_part(kit, _cyl(0.03, 0.05, 0.06), Color(0.55, 0.42, 0.28), BACK + Vector3(0.0, 0.12, 0.08))
		&"arm_guard":
			# The Clanker's guard: a riveted plate on the off arm, angled across its front.
			_part(kit, _box(Vector3(0.3, 0.34, 0.04)), METAL, ARM_OFF + Vector3(0.14, 0.08, -0.16), Vector3(0.0, 0.45, 0.0),
					0.0, 5, trim)
			for y: float in [-0.12, 0.12]:
				_part(kit, _sphere(0.02, 0.04), DARK, ARM_OFF + Vector3(0.13, 0.08 + y, -0.19))
		&"pea_shooter":
			# The Spitter's long barrel with a pea hopper on top.
			var along := Vector3(PI * 0.5, 0.0, 0.0)
			_part(kit, _cyl(0.035, 0.04, 0.34), METAL, ARM_WEAPON + Vector3(0.0, 0.0, -0.34), along)
			_part(kit, _torus(0.03, 0.05), trim, ARM_WEAPON + Vector3(0.0, 0.0, -0.5), along)
			_part(kit, _sphere(0.075, 0.15), Color(0.55, 0.9, 0.3), ARM_WEAPON + Vector3(0.0, 0.11, -0.12), Vector3.ZERO, 0.3)
		&"bolt_pouch":
			# Bolts to throw at a farmer out of reach.
			_part(kit, _box(Vector3(0.14, 0.12, 0.1)), Color(0.5, 0.36, 0.22), BODY + Vector3(0.24, -0.12, 0.08))
			for x: float in [-0.03, 0.03]:
				_part(kit, _cyl(0.018, 0.018, 0.1), METAL, BODY + Vector3(0.24 + x, -0.03, 0.08))
		&"clod_scoop":
			# A scoop of farm dirt to lob at a farmer out of reach.
			_part(kit, _cyl(0.12, 0.08, 0.12), METAL, BODY + Vector3(-0.24, 0.12, 0.08))
			_part(kit, _sphere(0.1, 0.16), Color(0.5, 0.36, 0.22), BODY + Vector3(-0.24, 0.2, 0.08))
		&"climb_hooks":
			# The Rung Runner's tell: hazard-yellow grapnel hooks on both hands and a coil of rope on its back,
			# readable from the ground at a glance.
			for x: float in [-1.0, 1.0]:
				var hand := ARM_OFF + Vector3(0.0, 0.0, 0.06) if x < 0.0 else ARM_WEAPON + Vector3(0.0, 0.0, -0.16)
				_part(kit, _torus(0.035, 0.06), HAZARD, hand + Vector3(0.0, 0.14, -0.06), Vector3(PI * 0.5, 0.0, 0.0), 0.5)
				_part(kit, _cyl(0.02, 0.02, 0.16), METAL, hand + Vector3(0.0, 0.06, -0.06))
			_part(kit, _torus(0.09, 0.14), Color(0.78, 0.62, 0.38), BACK + Vector3(0.0, 0.02, 0.06), Vector3(PI * 0.5, 0.0, 0.0))
			_part(kit, _box(Vector3(0.3, 0.05, 0.02)), HAZARD, BODY + Vector3(0.0, 0.14, -0.19), Vector3.ZERO, 0.4, 5, DARK)
		&"crown":
			_part(kit, _cyl(0.15, 0.17, 0.08), trim, HEAD + Vector3(0.0, 0.22, 0.0), Vector3.ZERO, 0.4)
			for i in 5:
				var angle := i * TAU / 5.0
				_part(kit, _cyl(0.0, 0.03, 0.08), trim, HEAD + Vector3(sin(angle) * 0.14, 0.3, cos(angle) * 0.14), Vector3.ZERO, 0.4)
		_:
			pass


# --- Mesh and part helpers ------------------------------------------------------------------------

## A sculpted part: the shared skin material with the family's paint.
static func _skin(parent: Node3D, mesh: Mesh, at: Vector3, euler: Vector3, paint: Paint) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	instance.transform = Transform3D(Basis.from_euler(euler), at)
	instance.material_override = Clay.robot_skin()
	instance.set_instance_shader_parameter(&"skin_primary", paint.primary)
	instance.set_instance_shader_parameter(&"skin_secondary", paint.secondary)
	instance.set_instance_shader_parameter(&"skin_trim", paint.trim)
	return instance


static func _part(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, euler: Vector3 = Vector3.ZERO, glow: float = 0.0,
		pattern: int = 0, pattern_color: Color = Color.WHITE, wear: float = 0.0) -> MeshInstance3D:
	var instance := Clay.part(parent, mesh, color, Transform3D(Basis.from_euler(euler), at), glow)
	if pattern != 0:
		instance.set_instance_shader_parameter(&"pattern_id", pattern)
		instance.set_instance_shader_parameter(&"pattern_color", pattern_color)
	if wear > 0.0:
		instance.set_instance_shader_parameter(&"wear", wear)
	return instance


static func _cyl(top: float, bottom: float, height: float, segments: int = 16) -> Mesh:
	var key := "cyl:%s:%s:%s:%d" % [top, bottom, height, segments]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = segments
		mesh.rings = 1
		_meshes[key] = mesh
	return _meshes[key]


static func _box(size: Vector3) -> Mesh:
	var key := "box:%s" % size
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return _meshes[key]


static func _sphere(radius: float, height: float) -> Mesh:
	var key := "sph:%s:%s" % [radius, height]
	if not _meshes.has(key):
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = height
		mesh.radial_segments = 16
		mesh.rings = 8
		_meshes[key] = mesh
	return _meshes[key]


static func _torus(inner: float, outer: float) -> Mesh:
	var key := "tor:%s:%s" % [inner, outer]
	if not _meshes.has(key):
		var mesh := TorusMesh.new()
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		mesh.rings = 16
		mesh.ring_segments = 8
		_meshes[key] = mesh
	return _meshes[key]


static func _shift_hue(color: Color, amount: float) -> Color:
	return Color.from_hsv(fposmod(color.h + amount, 1.0), color.s, color.v, color.a)
