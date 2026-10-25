class_name RobotFactory
extends RefCounted
## Kit-bashes a robot's look from clay primitives (GDD 10.1, 10.4): body shape, head, eye style, antenna,
## locomotion, weapon arm, emblem and accessories, all on one shared clay material with per-part
## instance uniforms (tint, pattern, wear), so robots never duplicate materials.
##
## Readability locks (never broken by the genome): type sets the scale and locomotion family; class sets
## the weapon arm, eye glow color and chest icon; weak points get hazard trim and a glow. Every robot
## carries the Factory DNA: the BOLT Co. cog on its chest and an antenna bulb that blinks with its wave.
## Parts are authored at Scout size; the kit node is scaled per type.

## Eye glow by class: melee red, short-range amber, long-range blue.
const CLASS_EYE_COLORS: Array[Color] = [Color(1.0, 0.16, 0.1), Color(1.0, 0.62, 0.1), Color(0.3, 0.6, 1.0)]
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

const PATTERN_IDS: Dictionary[StringName, int] = {
	&"none": 0, &"stripes": 1, &"polka_dots": 2, &"checker": 3, &"rust_patches": 4, &"hazard_tape": 5,
	&"stars": 6, &"flame_decals": 1,
}
const WEAR_AMOUNTS: Dictionary[StringName, float] = {&"fresh": 0.0, &"scuffed": 0.35, &"patched": 0.5, &"rusty": 0.75}

## Sockets at Scout size (y up, front = -Z).
const BODY := Vector3(0.0, 0.56, 0.0)
const HEAD := Vector3(0.0, 0.88, 0.0)
const EYE := Vector3(0.0, 0.89, -0.2)
const ANTENNA := Vector3(0.0, 1.06, 0.0)
const ARM_WEAPON := Vector3(0.33, 0.52, -0.08)
const ARM_OFF := Vector3(-0.33, 0.55, 0.0)
const CHEST := Vector3(0.0, 0.6, -0.31)
const BACK := Vector3(0.0, 0.58, 0.31)

static var _meshes: Dictionary[String, Mesh] = {}


## What the robot script animates after the build.
class Look:
	var bulb: MeshInstance3D
	var eyes: Array[MeshInstance3D] = []
	var wheels: Array[Node3D] = []


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
	var pattern := PATTERN_IDS.get(genome.pattern, 0) as int
	var wear := WEAR_AMOUNTS.get(genome.wear, 0.0) as float
	var eye_color := CLASS_EYE_COLORS[int(archetype.robot_class)]

	var look := Look.new()
	_body(kit, genome.body_shape, primary, secondary, trim, pattern, wear)
	_head(kit, genome.head, primary, secondary, trim, wear)
	look.eyes = _eyes(kit, genome.eye_style, eye_color, trim)
	look.bulb = _antenna(kit, genome.antenna, secondary, trim)
	var locomotion := genome.locomotion_by_type[type_index] if type_index < genome.locomotion_by_type.size() else &"unicycle"
	look.wheels = _locomotion(kit, locomotion, secondary, trim)
	_weapon_arm(kit, archetype.robot_class, genome.melee_arm, secondary, trim)
	_off_arm(kit, secondary, trim)
	_emblem(kit, trim, eye_color)

	_accessory(kit, genome.accessory, primary, secondary, trim)
	if cosmetic.randf() < 0.2 and not genome.theme.accessories.is_empty():
		var extra := genome.theme.accessories[cosmetic.randi_range(0, genome.theme.accessories.size() - 1)]
		if extra != genome.accessory:
			_accessory(kit, extra, primary, secondary, trim)
	for robot_trait in traits:
		_accessory(kit, robot_trait.tell, primary, secondary, trim)
	if is_foreman:
		_accessory(kit, &"crown", primary, secondary, GOLD)
	if archetype.robot_type == RobotArchetype.RobotType.HEAVY:
		# Weak point on the back (Thumper's vent): hazard-striped and glowing (readability lock).
		_part(kit, _box(Vector3(0.24, 0.2, 0.06)), HAZARD, BACK + Vector3(0.0, 0.04, 0.02), Vector3.ZERO, 0.6, 5, DARK)
	return look


## The stolen grain sack a fleeing thief carries on its back.
static func attach_sack(kit: Node3D) -> void:
	if kit != null:
		_accessory(kit, &"sack", Color.WHITE, Color.WHITE, Color.WHITE)


# --- Body parts -----------------------------------------------------------------------------------

static func _body(kit: Node3D, shape: StringName, primary: Color, secondary: Color, trim: Color, pattern: int, wear: float) -> void:
	var p := pattern
	var pc := secondary.lerp(Color.WHITE, 0.35)
	match shape:
		&"tin_can":
			_part(kit, _cyl(0.28, 0.28, 0.42), primary, BODY, Vector3.ZERO, 0.0, p, pc, wear)
			_part(kit, _cyl(0.29, 0.29, 0.03), trim, BODY + Vector3(0.0, 0.2, 0.0))
		&"gumdrop":
			_part(kit, _cyl(0.17, 0.32, 0.42), primary, BODY, Vector3.ZERO, 0.0, p, pc, wear)
		&"toaster":
			_part(kit, _box(Vector3(0.56, 0.42, 0.42)), primary, BODY, Vector3.ZERO, 0.0, p, pc, wear)
			for x: float in [-0.1, 0.1]:
				_part(kit, _box(Vector3(0.05, 0.02, 0.3)), DARK, BODY + Vector3(x, 0.21, 0.0))
		&"egg":
			_part(kit, _sphere(0.29, 0.52), primary, BODY + Vector3(0.0, 0.02, 0.0), Vector3.ZERO, 0.0, p, pc, wear)
		&"barrel":
			_part(kit, _cyl(0.29, 0.29, 0.42), primary, BODY, Vector3.ZERO, 0.0, p, pc, wear)
			for y: float in [-0.12, 0.12]:
				_part(kit, _cyl(0.305, 0.305, 0.04), trim, BODY + Vector3(0.0, y, 0.0))
		_:  # lunchbox
			_part(kit, _box(Vector3(0.6, 0.38, 0.38)), primary, BODY, Vector3.ZERO, 0.0, p, pc, wear)
			_part(kit, _box(Vector3(0.1, 0.06, 0.03)), trim, BODY + Vector3(0.0, 0.12, -0.2))


static func _head(kit: Node3D, shape: StringName, primary: Color, secondary: Color, trim: Color, wear: float) -> void:
	match shape:
		&"dome":
			_part(kit, _sphere(0.21, 0.36), primary, HEAD, Vector3.ZERO, 0.0, 0, Color.WHITE, wear)
		&"bucket":
			_part(kit, _cyl(0.17, 0.21, 0.3), secondary, HEAD, Vector3.ZERO, 0.0, 0, Color.WHITE, wear)
			_part(kit, _cyl(0.175, 0.175, 0.03), trim, HEAD + Vector3(0.0, 0.15, 0.0))
		&"light_bulb":
			_part(kit, _sphere(0.2, 0.4), primary.lerp(Color.WHITE, 0.3), HEAD + Vector3(0.0, 0.02, 0.0), Vector3.ZERO, 0.15)
			_part(kit, _cyl(0.1, 0.1, 0.12), trim, HEAD + Vector3(0.0, -0.17, 0.0))
		&"old_tv":
			_part(kit, _box(Vector3(0.42, 0.32, 0.3)), secondary, HEAD, Vector3.ZERO, 0.0, 0, Color.WHITE, wear)
			_part(kit, _box(Vector3(0.34, 0.24, 0.02)), DARK, HEAD + Vector3(0.0, 0.0, -0.15))
		&"teapot":
			_part(kit, _sphere(0.2, 0.36), primary, HEAD, Vector3.ZERO, 0.0, 0, Color.WHITE, wear)
			_part(kit, _cyl(0.025, 0.045, 0.18), primary, HEAD + Vector3(0.22, 0.02, 0.0), Vector3(0.0, 0.0, -0.9))
			_part(kit, _sphere(0.04, 0.08), trim, HEAD + Vector3(0.0, 0.19, 0.0))
		_:  # mailbox
			_part(kit, _box(Vector3(0.3, 0.2, 0.4)), secondary, HEAD + Vector3(0.0, -0.04, 0.0), Vector3.ZERO, 0.0, 0, Color.WHITE, wear)
			_part(kit, _cyl(0.15, 0.15, 0.4), secondary, HEAD + Vector3(0.0, 0.06, 0.0), Vector3(PI * 0.5, 0.0, 0.0), 0.0, 0, Color.WHITE, wear)
			_part(kit, _box(Vector3(0.03, 0.12, 0.03)), Color(0.9, 0.2, 0.15), HEAD + Vector3(0.17, 0.05, 0.08))


static func _eyes(kit: Node3D, style: StringName, eye_color: Color, trim: Color) -> Array[MeshInstance3D]:
	var eyes: Array[MeshInstance3D] = []
	var facing := Vector3(PI * 0.5, 0.0, 0.0)  # cylinder axis toward -Z
	match style:
		&"twin_goggles":
			for x: float in [-0.075, 0.075]:
				eyes.append(_part(kit, _cyl(0.06, 0.06, 0.05), eye_color, EYE + Vector3(x, 0.0, 0.0), facing, 2.5))
			_part(kit, _box(Vector3(0.3, 0.03, 0.02)), DARK, EYE + Vector3(0.0, 0.0, 0.015))
		&"visor":
			eyes.append(_part(kit, _box(Vector3(0.3, 0.065, 0.05)), eye_color, EYE, Vector3.ZERO, 2.5))
		&"led_grid":
			_part(kit, _box(Vector3(0.25, 0.15, 0.03)), DARK, EYE + Vector3(0.0, 0.0, 0.01))
			eyes.append(_part(kit, _box(Vector3(0.21, 0.11, 0.04)), eye_color, EYE, Vector3.ZERO, 2.5, 3, eye_color.darkened(0.5)))
		&"monocle":
			eyes.append(_part(kit, _cyl(0.08, 0.08, 0.04), eye_color, EYE + Vector3(0.03, 0.0, 0.0), facing, 2.5))
			_part(kit, _torus(0.075, 0.1), trim, EYE + Vector3(0.03, 0.0, 0.0), facing)
		_:  # cyclops
			eyes.append(_part(kit, _cyl(0.085, 0.085, 0.05), eye_color, EYE, facing, 2.5))
			_part(kit, _torus(0.08, 0.105), trim, EYE + Vector3(0.0, 0.0, 0.005), facing)
	return eyes


## Returns the bulb, which every robot has on top of its antenna (Factory DNA).
static func _antenna(kit: Node3D, style: StringName, secondary: Color, trim: Color) -> MeshInstance3D:
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
		_:  # bulb: a plain stem
			_part(kit, _cyl(0.012, 0.012, 0.22), DARK, ANTENNA + Vector3(0.0, 0.11, 0.0))
	return _part(kit, _sphere(0.045, 0.09), BULB_COLOR, top, Vector3.ZERO, 0.5)


static func _locomotion(kit: Node3D, style: StringName, secondary: Color, trim: Color) -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	var axle := Vector3(0.0, 0.0, PI * 0.5)  # cylinder axis along X
	match style:
		&"pogo":
			for i in 4:
				_part(kit, _torus(0.05, 0.08), METAL, Vector3(0.0, 0.08 + 0.055 * i, 0.0))
			_part(kit, _cyl(0.12, 0.12, 0.04), DARK, Vector3(0.0, 0.02, 0.0))
		&"waddle_legs":
			for x: float in [-0.14, 0.14]:
				_part(kit, _cyl(0.065, 0.065, 0.26), secondary, Vector3(x, 0.19, 0.0))
				_part(kit, _box(Vector3(0.15, 0.07, 0.22)), DARK, Vector3(x, 0.035, -0.03))
		&"mini_treads":
			for x: float in [-0.18, 0.18]:
				_part(kit, _box(Vector3(0.14, 0.16, 0.42)), DARK, Vector3(x, 0.1, 0.0))
				_part(kit, _box(Vector3(0.15, 0.04, 0.3)), trim, Vector3(x, 0.19, 0.0))
		&"tripod":
			for angle: float in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
				var foot := Vector3(sin(angle) * 0.22, 0.0, cos(angle) * 0.22)
				_part(kit, _box(Vector3(0.05, 0.4, 0.05)), secondary, foot * 0.5 + Vector3(0.0, 0.18, 0.0),
						Vector3(cos(angle) * 0.5, 0.0, -sin(angle) * 0.5))
		&"treads":
			for x: float in [-0.2, 0.2]:
				_part(kit, _box(Vector3(0.18, 0.22, 0.62)), DARK, Vector3(x, 0.12, 0.0))
				for z: float in [-0.22, 0.0, 0.22]:
					wheels.append(_part(kit, _cyl(0.08, 0.08, 0.2), METAL, Vector3(x, 0.12, z), axle))
		&"four_legs":
			for x: float in [-0.17, 0.17]:
				for z: float in [-0.15, 0.15]:
					_part(kit, _cyl(0.07, 0.08, 0.32), secondary, Vector3(x, 0.17, z))
					_part(kit, _cyl(0.09, 0.09, 0.04), DARK, Vector3(x, 0.02, z))
		&"giant_wheel":
			var wheel := _part(kit, _cyl(0.3, 0.3, 0.2), DARK, Vector3(0.0, 0.3, 0.0), axle)
			_part(wheel, _cyl(0.12, 0.12, 0.22), trim, Vector3.ZERO)
			wheels.append(wheel)
		_:  # unicycle
			var wheel := _part(kit, _cyl(0.2, 0.2, 0.1), DARK, Vector3(0.0, 0.2, 0.0), axle)
			_part(wheel, _cyl(0.07, 0.07, 0.12), trim, Vector3.ZERO)
			wheels.append(wheel)
			for x: float in [-0.07, 0.07]:
				_part(kit, _box(Vector3(0.03, 0.2, 0.03)), METAL, Vector3(x, 0.32, 0.0))
	return wheels


## Class lock: melee robots always carry a claw, fist or hammer arm.
static func _weapon_arm(kit: Node3D, robot_class: RobotArchetype.RobotClass, style: StringName, secondary: Color, trim: Color) -> void:
	var arm := Vector3(PI * 0.5, 0.0, 0.0)
	_part(kit, _cyl(0.045, 0.045, 0.24), secondary, ARM_WEAPON + Vector3(0.0, 0.0, -0.08), arm)
	var hand := ARM_WEAPON + Vector3(0.0, 0.0, -0.22)
	if robot_class != RobotArchetype.RobotClass.MELEE:
		_part(kit, _cyl(0.05, 0.07, 0.16), METAL, hand, arm)
		return
	match style:
		&"fist":
			_part(kit, _sphere(0.085, 0.17), trim, hand)
		&"hammer":
			_part(kit, _cyl(0.06, 0.06, 0.2), METAL, hand + Vector3(0.0, 0.0, -0.03), Vector3(0.0, 0.0, PI * 0.5))
		_:  # claw
			for x: float in [-0.04, 0.04]:
				_part(kit, _box(Vector3(0.03, 0.05, 0.14)), trim, hand + Vector3(x, 0.0, -0.04), Vector3(0.0, x * 6.0, 0.0))


static func _off_arm(kit: Node3D, secondary: Color, trim: Color) -> void:
	_part(kit, _cyl(0.04, 0.04, 0.18), secondary, ARM_OFF + Vector3(0.0, -0.06, 0.0), Vector3(0.0, 0.0, -0.4))
	_part(kit, _sphere(0.055, 0.11), trim, ARM_OFF + Vector3(-0.04, -0.15, 0.0))


## The BOLT Co. cog on every chest plate, with the class icon (melee: a little fist) under it.
static func _emblem(kit: Node3D, trim: Color, eye_color: Color) -> void:
	var facing := Vector3(PI * 0.5, 0.0, 0.0)
	_part(kit, _cyl(0.07, 0.07, 0.02, 8), trim, CHEST, facing)
	for i in 4:
		var angle := i * PI * 0.5
		_part(kit, _box(Vector3(0.03, 0.03, 0.02)), trim, CHEST + Vector3(cos(angle) * 0.085, sin(angle) * 0.085, 0.0))
	_part(kit, _sphere(0.03, 0.06), eye_color, CHEST + Vector3(0.0, -0.1, 0.0), Vector3.ZERO, 0.8)


static func _accessory(kit: Node3D, id: StringName, _primary: Color, secondary: Color, trim: Color) -> void:
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
				_part(kit, _cyl(0.05, 0.05, 0.02, 5), Color(1.0, 0.4, 0.8), HEAD + Vector3(x, 0.1, -0.19), Vector3(PI * 0.5, 0.0, 0.0))
		&"afro":
			_part(kit, _sphere(0.2, 0.34), secondary.darkened(0.3), HEAD + Vector3(0.0, 0.1, 0.07))
		&"bandana":
			_part(kit, _cyl(0.215, 0.215, 0.06), Color(0.85, 0.15, 0.15), HEAD + Vector3(0.0, 0.08, 0.0), Vector3.ZERO, 0.0, 2, Color.WHITE)
			_part(kit, _sphere(0.05, 0.1), Color(0.85, 0.15, 0.15), HEAD + Vector3(0.0, 0.08, 0.22))
		&"tricorn":
			_part(kit, _box(Vector3(0.38, 0.06, 0.24)), DARK, HEAD + Vector3(0.0, 0.17, 0.0))
			_part(kit, _box(Vector3(0.2, 0.08, 0.14)), DARK, HEAD + Vector3(0.0, 0.22, 0.0))
		&"hook":
			_part(kit, _torus(0.03, 0.055), METAL, ARM_OFF + Vector3(-0.05, -0.2, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
		&"speed_fins":
			for x: float in [-0.12, 0.12]:
				_part(kit, _box(Vector3(0.02, 0.16, 0.14)), Color(1.0, 0.95, 0.9), BACK + Vector3(x, 0.05, 0.04), Vector3(0.0, 0.0, x * 3.0))
		&"armor_plates":
			for x: float in [-0.3, 0.3]:
				_part(kit, _box(Vector3(0.05, 0.3, 0.3)), METAL, BODY + Vector3(x, 0.0, 0.0))
		&"spark_coil":
			# Overcharged's tell: a copper coil on a mast with a glowing core that crackles (Robot._on_tick_12).
			_part(kit, _cyl(0.025, 0.025, 0.3), METAL, BACK + Vector3(0.0, 0.3, 0.04))
			for y: float in [0.36, 0.42, 0.48]:
				_part(kit, _torus(0.05, 0.075), COPPER, BACK + Vector3(0.0, y, 0.04))
			var core := _part(kit, _sphere(0.07, 0.14), SPARK_COLOR, BACK + Vector3(0.0, 0.58, 0.04), Vector3.ZERO, 3.0)
			core.name = SPARK_CORE
		&"gold_band":
			_part(kit, _cyl(0.31, 0.31, 0.05), GOLD, BODY + Vector3(0.0, -0.17, 0.0), Vector3.ZERO, 0.3)
		&"sack":
			_part(kit, _sphere(0.13, 0.22), Color(0.72, 0.58, 0.38), BACK + Vector3(0.0, 0.0, 0.08))
			_part(kit, _cyl(0.03, 0.05, 0.06), Color(0.55, 0.42, 0.28), BACK + Vector3(0.0, 0.12, 0.08))
		&"crown":
			_part(kit, _cyl(0.15, 0.17, 0.08), trim, HEAD + Vector3(0.0, 0.22, 0.0), Vector3.ZERO, 0.4)
			for i in 5:
				var angle := i * TAU / 5.0
				_part(kit, _cyl(0.0, 0.03, 0.08), trim, HEAD + Vector3(sin(angle) * 0.14, 0.3, cos(angle) * 0.14), Vector3.ZERO, 0.4)
		_:
			pass


# --- Mesh and part helpers ------------------------------------------------------------------------

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
