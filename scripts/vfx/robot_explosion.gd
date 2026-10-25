class_name RobotExplosion
extends Node3D
## The robot pop (GDD 2.1 "Cute chaos", 15.6): cotton-wool and cellophane, never gore. Layered the way
## VFX artists build explosions, each layer with its own job and lifetime:
##
##   0.00  Anticipation: the robot swells and glows hot for one stop-motion frame.
##   0.07  Burst: a 2-frame flash and a light pulse grab the eye; hitstop and screen shake land here.
##         A ground ring marks the blast; cellophane flame shards and sparks fly out fast and die fast.
##   0.07+ The robot's own clay parts fly off (biased along the killing blow), spin in stepped frames,
##         bounce and squash on the ground, cool from hot, and the eye bounces longest before it goes dark.
##   0.1+  Cotton puffs billow warm, whiten, then grey and shrink away; slow smoke rises after them.
##   9 s   A scorch mark stays behind on the ground.
##
## Overcharged robots (GDD 10.3) get a longer fuse that strobes white-hot so the player can read the
## coming blast, electric-blue sparks, and a ring that matches the blast's real radius. Robot._detonate
## deals the damage on the burst frame, so a chain ripples outward one fuse at a time.
##
## Visuals step at 24 fps (12 fps for smoke) like the rest of the stop-motion look (GDD 15.4); motion and
## collision run every physics tick. Budgets cap debris, lights and scorches so a grenade into a crowd
## stays cheap. Everything here is cosmetic: drops, signals and scoring already happened in Robot._die.

const ANTICIPATION: float = 0.07
## Overcharged fuse: long enough to read, short enough that a chain ripples rather than crawls.
const OVERCHARGED_FUSE: float = 0.28
const WORLD_MASK: int = 1 | (1 << 5)  # World, Silo
const GRAVITY: float = 22.0
const MAX_DEBRIS: int = 240
const MAX_LIGHTS: int = 6
const MAX_SCORCHES: int = 16
const SCORCH_SECONDS: float = 9.0
## Kills closer together than this count as a streak (bigger shake, a short freeze from the third).
const STREAK_MSEC: int = 350
const STEP_FPS: float = 24.0
const SMOKE_FPS: float = 12.0

const FLASH_COLOR := Color(1.0, 0.98, 0.85, 0.75)
const FIRE_COLORS: Array[Color] = [Color(1.0, 0.55, 0.1, 0.8), Color(1.0, 0.82, 0.2, 0.8), Color(1.0, 0.35, 0.12, 0.75)]
const SPARK_COLOR := Color(1.0, 0.85, 0.4)
const PUFF_WARM := Color(1.0, 0.78, 0.45)
const PUFF_WHITE := Color(0.97, 0.95, 0.9)
const PUFF_GREY := Color(0.56, 0.54, 0.52)
const SMOKE_GREY := Color(0.42, 0.41, 0.4)
const BOLT_COLOR := Color(0.62, 0.64, 0.68)

enum Kind { DEBRIS, SPARK, SHARD, PUFF, SMOKE }


class Piece:
	var node: MeshInstance3D
	var kind: int = Kind.DEBRIS
	var velocity: Vector3 = Vector3.ZERO
	var orientation: Basis = Basis()
	var spin_axis: Vector3 = Vector3.UP
	var spin_speed: float = 0.0
	var base_scale: Vector3 = Vector3.ONE
	## Negative while waiting to appear.
	var age: float = 0.0
	var life: float = 1.0
	var bounce: float = 0.4
	var resting: bool = false
	var squash_left: float = 0.0
	var size: float = 1.0
	var glow_rest: float = 0.0
	var is_eye: bool = false
	var counts_toward_budget: bool = false


static var live_debris: int = 0
static var _live_lights: int = 0
static var _scorches: Array[Decal] = []
static var _streak: int = 0
static var _last_kill_msec: int = -100000
static var _meshes: Dictionary[StringName, Mesh] = {}
static var _materials: Dictionary[Color, StandardMaterial3D] = {}
static var _two_sided_materials: Dictionary[Color, StandardMaterial3D] = {}
static var _scorch_texture: GradientTexture2D

## Overall size: 1 for a Scout, ~2.8 for a Heavy, more for a Foreman.
var power: float = 1.0
var ring_radius: float = 1.5
var hit_direction: Vector3 = Vector3.ZERO
var big: bool = false
## Seconds from death to burst.
var fuse: float = ANTICIPATION
var overcharged: bool = false

var _robot: Robot = null
var _from_robot: bool = false
var _foreman: bool = false
var _burst_done: bool = false
var _age: float = 0.0
var _burst_at: float = 0.0
var _flash_frame: int = 0
var _pieces: Array[Piece] = []
var _flash: MeshInstance3D
var _light: OmniLight3D
var _light_energy: float = 0.0
var _ring: MeshInstance3D
var _ground: Vector3 = Vector3.ZERO
var _has_ground: bool = false
var _rng := RandomNumberGenerator.new()
var _heated: Array[MeshInstance3D] = []


## A robot's death. Call from Robot._die; the robot must stay in the tree for `fuse` seconds so its parts
## can be taken (if it is gone by then the burst happens without them). A `blast_radius` above 0 is an
## Overcharged death blast.
static func for_robot(target: Robot, direction: Vector3, blast_radius: float = 0.0) -> RobotExplosion:
	var size := target.type_scale()
	var fx := _create(target, target.global_position + Vector3.UP * 0.55 * size)
	fx.power = size * (1.4 if target.is_foreman else 1.0)
	fx.ring_radius = 1.3 * fx.power
	fx.hit_direction = direction
	fx.big = target.is_foreman or target.archetype.robot_type == RobotArchetype.RobotType.HEAVY
	if blast_radius > 0.0:
		fx.overcharged = true
		fx.fuse = OVERCHARGED_FUSE
		fx.power *= 1.25
		fx.ring_radius = blast_radius
	fx._robot = target
	fx._from_robot = true
	fx._foreman = target.is_foreman
	fx._heat_up()
	return fx


## A blast with no robot parts (a grenade). The ring shows the real blast radius.
static func blast(context: Node, at: Vector3, radius: float) -> RobotExplosion:
	var fx := _create(context, at)
	fx.power = clampf(radius * 0.4, 0.8, 3.0)
	fx.ring_radius = radius
	fx._burst()
	return fx


## One of each layer's material, light and decal, frozen in place under `parent`, so BootScreen's warm-up
## compiles their shaders and pipelines. Without it the first pop of a session hitches while they compile.
static func warm_up(parent: Node) -> RobotExplosion:
	var fx := RobotExplosion.new()
	fx.name = "ExplosionWarmUp"
	fx.set_physics_process(false)
	parent.add_child(fx)
	# Fill every lazy cache during loading, including later flash colors and rare drops' blasts.
	for id: StringName in [&"sphere", &"shard", &"ring", &"puff", &"bolt", &"spark"]:
		_mesh(id)
	for color in FIRE_COLORS:
		_unshaded(color, true)
	for color in [FLASH_COLOR, Color(FIRE_COLORS[1], 0.55), SPARK_COLOR,
			RobotFactory.SPARK_COLOR, Color(RobotFactory.SPARK_COLOR, 0.9), Color(1.0, 0.95, 0.82, 0.85)]:
		_unshaded(color)
	fx._mesh_node(_mesh(&"sphere"), _unshaded(FLASH_COLOR), Vector3(-6.0, 1.0, 0.0), 2.0)
	fx._mesh_node(_mesh(&"shard"), _unshaded(FIRE_COLORS[0], true), Vector3(-3.0, 1.0, 0.0), 4.0)
	var ring := fx._mesh_node(_mesh(&"ring"), _unshaded(FLASH_COLOR), Vector3(0.0, 1.0, 0.0), 2.0)
	ring.transparency = 0.5
	var puff := fx._mesh_node(_mesh(&"puff"), Clay.shared(), Vector3(3.0, 1.0, 0.0), 1.5)
	puff.set_instance_shader_parameter(&"tint", PUFF_WARM)
	puff.set_instance_shader_parameter(&"emission_strength", 1.0)
	fx._mesh_node(_mesh(&"bolt"), Clay.shared(), Vector3(6.0, 1.0, 0.0), 8.0)
	fx._mesh_node(_mesh(&"spark"), _unshaded(SPARK_COLOR), Vector3(0.0, 1.0, -3.0), 8.0)
	var light := OmniLight3D.new()
	light.omni_range = 8.0
	light.shadow_enabled = false
	fx.add_child(light)
	var decal := Decal.new()
	decal.texture_albedo = _scorch()
	decal.size = Vector3(6.0, 4.0, 6.0)
	fx.add_child(decal)
	return fx


static func _create(context: Node, at: Vector3) -> RobotExplosion:
	var fx := RobotExplosion.new()
	fx.name = "RobotExplosion"
	fx.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fx._rng.randomize()
	var tree := context.get_tree()
	var parent := tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(fx)
	fx.global_position = at
	return fx


func _physics_process(delta: float) -> void:
	_age += delta
	if not _burst_done:
		if _age >= fuse:
			_burst()
		elif overcharged:
			# Strobe white-hot, faster and faster, until it blows.
			var hot := int(pow(_age / fuse, 1.6) * 9.0) % 2 == 0
			for mesh in _heated:
				if is_instance_valid(mesh):
					mesh.set_instance_shader_parameter(&"emission_strength", 2.5 if hot else 0.4)
		return
	_update_flash(_age - _burst_at)
	var space := get_world_3d().direct_space_state
	var index := _pieces.size() - 1
	while index >= 0:
		var piece := _pieces[index]
		if not _update_piece(piece, delta, space):
			_remove_piece(index)
		index -= 1
	if _pieces.is_empty() and _flash == null and _light == null and _ring == null:
		queue_free()


func _exit_tree() -> void:
	for index in range(_pieces.size() - 1, -1, -1):
		_remove_piece(index)
	if _light != null:
		_live_lights -= 1
		_light = null


# --- Anticipation and burst ----------------------------------------------------------------------

## The robot glows hot just before it pops.
func _heat_up() -> void:
	_heated = _robot_meshes()
	for mesh in _heated:
		mesh.set_instance_shader_parameter(&"emission_strength", 1.3)


func _robot_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if not is_instance_valid(_robot):
		return result
	var kit := _robot.get_node_or_null(^"Model/Pose/Kit")
	if kit == null:
		return result
	for node in kit.find_children("*", "MeshInstance3D", true, false):
		result.append(node as MeshInstance3D)
	return result


func _burst() -> void:
	_burst_done = true
	_burst_at = _age
	_find_ground()
	var r := 0.55 * power
	_spawn_flash(r)
	_spawn_light()
	_spawn_ring()
	for i in mini(roundi(6 + 3 * power), 14):
		_spawn_shard(r)
	for i in mini(roundi(7 + 3 * power), 16):
		_spawn_spark()
	for i in mini(roundi(5 + 2 * power), 11):
		_spawn_puff(r, i)
	for i in mini(roundi(2 + power), 5):
		_spawn_smoke(r)
	if is_instance_valid(_robot):
		_take_parts()
		for i in mini(roundi(2 + power * 1.5), 7):
			_spawn_bolt()
	_spawn_scorch(r)
	_impact()


## Screen shake, freeze frame and sound, scaled by size and kill streak.
func _impact() -> void:
	var now := Time.get_ticks_msec()
	_streak = _streak + 1 if now - _last_kill_msec < STREAK_MSEC else 0
	_last_kill_msec = now
	var trauma := 0.16 + 0.12 * power + 0.05 * mini(_streak, 4)
	if big:
		trauma += 0.15
	if overcharged:
		trauma += 0.12
	FarmerCamera.shake_at(global_position, minf(trauma, 0.85))
	if big:
		Hitstop.freeze(0.085 if _foreman else 0.065)
	elif _streak >= 2:
		Hitstop.freeze(0.045)
	if _from_robot:
		AudioDirector.play_pop(power)
	else:
		AudioDirector.play_cue(&"robot_pop", 0.5, 2.0)
		AudioDirector.play_cue(&"robot_pop", 0.75)


func _find_ground() -> void:
	var from := global_position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (2.5 + power), WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_has_ground = not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5
	if _has_ground:
		_ground = hit["position"]


# --- Layers ---------------------------------------------------------------------------------------

func _spawn_flash(r: float) -> void:
	_flash = _mesh_node(_mesh(&"sphere"), _unshaded(FLASH_COLOR), global_position, r * 0.75)


func _spawn_light() -> void:
	if _live_lights >= MAX_LIGHTS:
		return
	_live_lights += 1
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.4)
	_light.omni_range = 4.0 + 3.0 * power
	_light_energy = 3.0 + 2.0 * minf(power, 3.0)
	_light.light_energy = _light_energy
	_light.shadow_enabled = false
	add_child(_light)


func _spawn_ring() -> void:
	var at := _ground + Vector3.UP * 0.06 if _has_ground else global_position
	var color := Color(RobotFactory.SPARK_COLOR, 0.9) if overcharged else Color(1.0, 0.95, 0.82, 0.85)
	_ring = _mesh_node(_mesh(&"ring"), _unshaded(color), at, 0.2)


func _update_flash(since: float) -> void:
	if _flash != null:
		# Frame 1: small and white. Frame 2: bigger and warm. Then gone (the burst lasts ~2 frames).
		if since > 0.07:
			_flash.queue_free()
			_flash = null
		elif since > 0.035 and _flash_frame == 0:
			_flash_frame = 1
			_flash.scale *= 1.4
			_flash.material_override = _unshaded(Color(FIRE_COLORS[1], 0.55))
	if _light != null:
		var t := clampf(since / 0.28, 0.0, 1.0)
		_light.light_energy = _light_energy * (1.0 - t) * (1.0 - t)
		if t >= 1.0:
			_light.queue_free()
			_light = null
			_live_lights -= 1
	if _ring != null:
		var t := clampf(since / 0.24, 0.0, 1.0)
		var stepped := floorf(t * 0.24 * STEP_FPS) / (0.24 * STEP_FPS) if StopMotionClock.enabled else t
		var eased := 1.0 - pow(1.0 - stepped, 3.0)
		var radius := lerpf(0.2, ring_radius, eased)
		_ring.scale = Vector3(radius, radius * 0.35, radius)
		_ring.transparency = stepped
		if t >= 1.0:
			_ring.queue_free()
			_ring = null


## Cellophane flame shards: fast, bright, gone in a quarter second.
func _spawn_shard(r: float) -> void:
	var color := FIRE_COLORS[_rng.randi_range(0, FIRE_COLORS.size() - 1)]
	var dir := _random_dir(0.2)
	var piece := _add_piece(Kind.SHARD, _mesh(&"shard"), _unshaded(color, true), global_position + dir * r * 0.3,
			r * _rng.randf_range(0.7, 1.2))
	piece.velocity = dir * _rng.randf_range(5.0, 10.0) * sqrt(power)
	piece.life = _rng.randf_range(0.2, 0.32)
	piece.spin_axis = _random_dir(-1.0)
	piece.spin_speed = _rng.randf_range(8.0, 18.0)
	piece.orientation = Basis(_random_dir(-1.0), _rng.randf() * TAU)


func _spawn_spark() -> void:
	var color := RobotFactory.SPARK_COLOR if overcharged and _rng.randf() < 0.7 else SPARK_COLOR
	var piece := _add_piece(Kind.SPARK, _mesh(&"spark"), _unshaded(color), global_position, 1.0)
	piece.velocity = (_random_dir(0.1) + hit_direction * 0.4).normalized() * _rng.randf_range(9.0, 16.0)
	piece.life = _rng.randf_range(0.28, 0.45)


## Cotton-wool puffs (GDD 15.6): clay balls that pop out in stepped frames, warm from the flash, then
## whiten, grey and shrink away rather than fading.
func _spawn_puff(r: float, index: int) -> void:
	var offset := _random_dir(-0.3) * r * _rng.randf_range(0.1, 0.7)
	var piece := _add_piece(Kind.PUFF, _mesh(&"puff"), Clay.shared(), global_position + offset, 0.01)
	piece.size = r * _rng.randf_range(0.45, 0.8)
	piece.age = -0.012 * index
	piece.life = _rng.randf_range(0.8, 1.15)
	piece.velocity = offset.normalized() * _rng.randf_range(0.6, 1.4) + Vector3.UP * 0.5
	piece.node.set_instance_shader_parameter(&"tint", PUFF_WARM)
	piece.node.set_instance_shader_parameter(&"emission_strength", 1.0)


func _spawn_smoke(r: float) -> void:
	var at := global_position + Vector3(_rng.randf_range(-r, r) * 0.5, r * 0.3, _rng.randf_range(-r, r) * 0.5)
	var piece := _add_piece(Kind.SMOKE, _mesh(&"puff"), Clay.shared(), at, 0.01)
	piece.size = r * _rng.randf_range(0.4, 0.65)
	piece.age = -_rng.randf_range(0.1, 0.3)
	piece.life = _rng.randf_range(1.4, 2.0)
	piece.velocity = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.8, 1.3), _rng.randf_range(-0.3, 0.3))
	piece.node.set_instance_shader_parameter(&"tint", SMOKE_GREY)
	piece.node.visible = false


## The robot's own kit parts become the debris: the player sees *that* robot come apart.
func _take_parts() -> void:
	var meshes := _robot_meshes()
	var eyes: Array[MeshInstance3D] = []
	if _robot.look != null:
		eyes = _robot.look.eyes
	var center := global_position
	var room := MAX_DEBRIS - live_debris
	for mesh in meshes:
		var is_eye := eyes.has(mesh)
		# Over budget: keep the eyes and drop small trim; everything else vanishes in the flash.
		if room <= 0 and not is_eye:
			mesh.visible = false
			continue
		var xform := mesh.global_transform
		mesh.reparent(self, true)
		var piece := Piece.new()
		piece.node = mesh
		piece.kind = Kind.DEBRIS
		piece.base_scale = xform.basis.get_scale()
		piece.orientation = xform.basis.orthonormalized()
		var out := xform.origin - center
		out = out.normalized() if out.length_squared() > 0.0001 else _random_dir(0.0)
		var speed := _rng.randf_range(4.0, 8.5) * sqrt(power)
		piece.velocity = (out + Vector3.UP * 0.9 + hit_direction * 0.8 + _random_dir(-1.0) * 0.3).normalized() * speed
		piece.spin_axis = _random_dir(-1.0)
		piece.spin_speed = _rng.randf_range(5.0, 15.0)
		piece.life = _rng.randf_range(1.6, 2.6)
		piece.bounce = _rng.randf_range(0.35, 0.5)
		piece.is_eye = is_eye
		piece.counts_toward_budget = true
		live_debris += 1
		room -= 1
		var rest: Variant = mesh.get_instance_shader_parameter(&"emission_strength")
		piece.glow_rest = 2.5 if is_eye else 0.0
		if rest is float and not is_eye:
			piece.glow_rest = minf(rest, 0.6)
		if is_eye:
			# The bouncing eye (GDD 15.6): pops highest, bounces most, stays longest, then goes dark.
			piece.velocity = (Vector3.UP * 1.6 + out + hit_direction * 0.5).normalized() * speed * 1.2
			piece.bounce = 0.72
			piece.life = 3.2
		_pieces.append(piece)


## Bolts fly off too (GDD 9.6 hit feedback).
func _spawn_bolt() -> void:
	if live_debris >= MAX_DEBRIS:
		return
	var piece := _add_piece(Kind.DEBRIS, _mesh(&"bolt"), Clay.shared(), global_position + _random_dir(-1.0) * 0.2, 1.0)
	piece.node.set_instance_shader_parameter(&"tint", BOLT_COLOR)
	piece.velocity = (_random_dir(0.4) + hit_direction * 0.6).normalized() * _rng.randf_range(5.0, 9.0)
	piece.spin_axis = _random_dir(-1.0)
	piece.spin_speed = _rng.randf_range(10.0, 22.0)
	piece.life = _rng.randf_range(1.4, 2.2)
	piece.bounce = 0.55
	piece.counts_toward_budget = true
	live_debris += 1


## Explosions that leave nothing behind look "videogame-ish": a scorch mark stays on the ground.
func _spawn_scorch(r: float) -> void:
	if not _has_ground:
		return
	for index in range(_scorches.size() - 1, -1, -1):
		if not is_instance_valid(_scorches[index]):
			_scorches.remove_at(index)
	while _scorches.size() >= MAX_SCORCHES:
		_scorches.pop_front().queue_free()
	var decal := Decal.new()
	decal.texture_albedo = _scorch()
	var width := r * _rng.randf_range(2.6, 3.4)
	decal.size = Vector3(width, 1.2, width)
	decal.modulate = Color(1.0, 1.0, 1.0, 0.85)
	get_parent().add_child(decal)
	decal.global_position = _ground
	decal.rotate_y(_rng.randf() * TAU)
	_scorches.append(decal)
	var tween := decal.create_tween()
	tween.tween_interval(SCORCH_SECONDS - 2.0)
	tween.tween_property(decal, ^"modulate:a", 0.0, 2.0)
	tween.tween_callback(decal.queue_free)


# --- Per-piece update -----------------------------------------------------------------------------

## Returns false when the piece is finished.
func _update_piece(piece: Piece, delta: float, space: PhysicsDirectSpaceState3D) -> bool:
	var before := piece.age
	piece.age += delta
	if piece.age < 0.0:
		return true
	var fps := SMOKE_FPS if piece.kind == Kind.SMOKE else STEP_FPS
	var stepped := not StopMotionClock.enabled or floori(piece.age * fps) != floori(maxf(before, 0.0) * fps) \
			or before < 0.0
	var t := piece.age
	match piece.kind:
		Kind.DEBRIS:
			return _update_debris(piece, delta, space, stepped)
		Kind.SPARK:
			piece.velocity.y -= 14.0 * delta
			piece.velocity *= exp(-1.5 * delta)
			var pos := piece.node.global_position + piece.velocity * delta
			var dir := piece.velocity.normalized()
			var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
			var stretch := clampf(piece.velocity.length() / 10.0, 0.4, 1.4) * (1.0 - t / piece.life)
			piece.node.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1.0, 1.0, maxf(stretch, 0.05))), pos)
		Kind.SHARD:
			piece.velocity *= exp(-6.0 * delta)
			piece.orientation = Basis(piece.spin_axis, piece.spin_speed * delta) * piece.orientation
			var pos := piece.node.global_position + piece.velocity * delta
			if stepped:
				var shrink := pow(maxf(1.0 - t / piece.life, 0.0), 0.7)
				piece.node.global_transform = Transform3D(piece.orientation * Basis.from_scale(piece.base_scale * shrink), pos)
			else:
				piece.node.global_position = pos
		Kind.PUFF, Kind.SMOKE:
			_update_puff(piece, delta, stepped)
	return t < piece.life


func _update_debris(piece: Piece, delta: float, space: PhysicsDirectSpaceState3D, stepped: bool) -> bool:
	var pos := piece.node.global_position
	if not piece.resting:
		piece.velocity.y -= GRAVITY * delta
		var to := pos + piece.velocity * delta
		var query := PhysicsRayQueryParameters3D.create(pos, to, WORLD_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			pos = to
		else:
			var normal := hit["normal"] as Vector3
			var speed := piece.velocity.length()
			pos = (hit["position"] as Vector3) + normal * 0.04
			piece.velocity = piece.velocity.bounce(normal) * piece.bounce
			var along := normal * piece.velocity.dot(normal)
			piece.velocity = along + (piece.velocity - along) * 0.7
			piece.spin_speed *= 0.6
			if speed > 2.5:
				piece.squash_left = 1.0 / 12.0
			if piece.velocity.length() < 0.9 and normal.y > 0.6:
				piece.resting = true
		piece.orientation = Basis(piece.spin_axis, piece.spin_speed * delta) * piece.orientation
	piece.squash_left -= delta
	var t := piece.age
	var shape := piece.base_scale
	if piece.squash_left > 0.0:
		shape *= Vector3(1.3, 0.65, 1.3)  # springy clay
	if t > piece.life:
		# Stop-motion exit: a few shrinking frames instead of a fade.
		shape *= maxf(1.0 - (t - piece.life) / 0.2, 0.001)
	if stepped:
		piece.node.global_transform = Transform3D(piece.orientation.orthonormalized() * Basis.from_scale(shape), pos)
		_cool(piece, t)
	else:
		piece.node.global_position = pos
	return t < piece.life + 0.2


## Hot parts cool back to their own glow; the eye flickers and goes dark (X_X).
func _cool(piece: Piece, t: float) -> void:
	if piece.is_eye:
		var dark := t > 1.1 or (t > 0.7 and int(t * 12.0) % 2 == 0)
		piece.node.set_instance_shader_parameter(&"emission_strength", 0.0 if dark else piece.glow_rest)
	elif t < 0.6:
		piece.node.set_instance_shader_parameter(&"emission_strength", lerpf(1.3, piece.glow_rest, t / 0.6))
	elif t < 0.7:
		piece.node.set_instance_shader_parameter(&"emission_strength", piece.glow_rest)


func _update_puff(piece: Piece, delta: float, stepped: bool) -> void:
	var t := piece.age
	piece.velocity = piece.velocity.lerp(Vector3.UP * (1.0 if piece.kind == Kind.SMOKE else 0.5), 1.0 - exp(-3.0 * delta))
	var pos := piece.node.global_position + piece.velocity * delta
	if not stepped:
		piece.node.global_position = pos
		return
	piece.node.visible = true
	var grow_time := 0.16 if piece.kind == Kind.PUFF else 0.5
	var size := piece.size
	if t < grow_time:
		var g := t / grow_time
		# Overshoot a little (ease-out-back) so the puff pops instead of inflating.
		size *= 1.0 + 2.7 * pow(g - 1.0, 3.0) + 1.7 * pow(g - 1.0, 2.0)
	var exit := 0.25
	if t > piece.life - exit:
		size *= maxf((piece.life - t) / exit, 0.0)
	piece.node.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * maxf(size, 0.001)), pos)
	if piece.kind == Kind.PUFF:
		var color := PUFF_WARM.lerp(PUFF_WHITE, clampf(t / 0.3, 0.0, 1.0))
		color = color.lerp(PUFF_GREY, clampf((t - 0.35) / maxf(piece.life * 0.8 - 0.35, 0.01), 0.0, 1.0))
		piece.node.set_instance_shader_parameter(&"tint", color)
		piece.node.set_instance_shader_parameter(&"emission_strength", maxf(1.0 - t / 0.25, 0.0))


func _remove_piece(index: int) -> void:
	var piece := _pieces[index]
	if piece.counts_toward_budget:
		live_debris -= 1
	if is_instance_valid(piece.node):
		piece.node.queue_free()
	_pieces.remove_at(index)


# --- Helpers --------------------------------------------------------------------------------------

func _add_piece(kind: int, mesh: Mesh, material: Material, at: Vector3, size: float) -> Piece:
	var piece := Piece.new()
	piece.kind = kind
	piece.base_scale = Vector3.ONE * size
	piece.node = _mesh_node(mesh, material, at, size)
	_pieces.append(piece)
	return piece


func _mesh_node(mesh: Mesh, material: Material, at: Vector3, size: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * size), at)
	return node


## A random unit vector whose y is at least `min_y` (-1 for any direction).
func _random_dir(min_y: float) -> Vector3:
	var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(min_y, 1.0), _rng.randf_range(-1.0, 1.0))
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP


static func _mesh(id: StringName) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var mesh: Mesh
	match id:
		&"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
		&"puff":
			var puff := SphereMesh.new()
			puff.radius = 1.0
			puff.height = 2.0
			puff.radial_segments = 10
			puff.rings = 6
			mesh = puff
		&"ring":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.9
			torus.outer_radius = 1.0
			torus.rings = 32
			torus.ring_segments = 6
			mesh = torus
		&"shard":
			var prism := PrismMesh.new()
			prism.size = Vector3(0.45, 0.6, 0.02)
			mesh = prism
		&"spark":
			var box := BoxMesh.new()
			box.size = Vector3(0.035, 0.035, 0.3)
			mesh = box
		_:  # bolt: a hex nut
			var nut := CylinderMesh.new()
			nut.top_radius = 0.06
			nut.bottom_radius = 0.06
			nut.height = 0.05
			nut.radial_segments = 6
			nut.rings = 1
			mesh = nut
	_meshes[id] = mesh
	return mesh


static func _unshaded(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var cache := _two_sided_materials if double_sided else _materials
	if not cache.has(color):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		# The ring fades through instance transparency, so every material here can blend.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
		cache[color] = material
	return cache[color]


static func _scorch() -> GradientTexture2D:
	if _scorch_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.07, 0.05, 0.04, 0.85))
		gradient.set_color(1, Color(0.1, 0.08, 0.06, 0.0))
		gradient.add_point(0.55, Color(0.13, 0.1, 0.07, 0.55))
		_scorch_texture = GradientTexture2D.new()
		_scorch_texture.gradient = gradient
		_scorch_texture.fill = GradientTexture2D.FILL_RADIAL
		_scorch_texture.fill_from = Vector2(0.5, 0.5)
		_scorch_texture.fill_to = Vector2(1.0, 0.5)
		_scorch_texture.width = 128
		_scorch_texture.height = 128
	return _scorch_texture
