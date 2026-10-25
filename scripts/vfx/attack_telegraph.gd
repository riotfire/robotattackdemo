class_name AttackTelegraph
extends Node3D
## What a robot shot shows before it lands (M2-B7, GDD 9.6): a chalk circle where a lob will land, a
## red-yarn aim line for a rail, or a shadow circle under a falling bomb. RangedAttack makes one when it
## starts charging, moves it while it aims, locks it when it fires and clears it once the shot is done.
## Lives in the world, not under the robot, so a circle stays put when its robot dies mid-flight.

const CHALK := Color(0.97, 0.95, 0.88, 0.85)
const YARN := Color(0.9, 0.08, 0.06)
const SHADOW := Color(0.05, 0.04, 0.03, 0.55)

var kind: StringName = &""
var locked: bool = false

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _radius: float = 1.0


## A telegraph of `kind` (AttackProfile.telegraph()) in `context`'s scene, or null for straight shots.
static func create(context: Node, telegraph_kind: StringName, radius: float) -> AttackTelegraph:
	if telegraph_kind.is_empty():
		return null
	var telegraph := AttackTelegraph.new()
	telegraph.kind = telegraph_kind
	telegraph.name = "Telegraph_" + String(telegraph_kind)
	telegraph._radius = radius
	var tree := context.get_tree()
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(telegraph)
	return telegraph


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		&"landing_circle":
			var ring := TorusMesh.new()
			ring.inner_radius = maxf(0.05, _radius - 0.12)
			ring.outer_radius = _radius
			ring.rings = 24
			ring.ring_segments = 4
			_mesh.mesh = ring
			_mesh.scale = Vector3(1.0, 0.08, 1.0)
			_material.albedo_color = CHALK
		&"bomb_shadow":
			var disc := CylinderMesh.new()
			disc.top_radius = _radius
			disc.bottom_radius = _radius
			disc.height = 0.02
			disc.radial_segments = 20
			_mesh.mesh = disc
			_material.albedo_color = SHADOW
		&"aim_line":
			var line := BoxMesh.new()
			line.size = Vector3(0.05, 0.05, 1.0)
			_mesh.mesh = line
			_material.albedo_color = YARN
			_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_mesh.material_override = _material
	add_child(_mesh)


## A circle (or shadow) at `point`, flat against a surface facing `normal`.
func place(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if locked:
		return
	var up := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	global_transform = Transform3D(Basis(side, up, side.cross(up)), point + up * 0.04)


## The aim line from `from` to `to`.
func stretch(from: Vector3, to: Vector3) -> void:
	if locked:
		return
	var length := maxf(0.05, from.distance_to(to))
	var mid := (from + to) * 0.5
	var forward := (to - from).normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(forward, up), mid)
	_mesh.scale = Vector3(1.0, 1.0, length)


## 0..1: how far along the charge (or the fall) it is. Circles and shadows darken and the line thickens.
func set_progress(t: float) -> void:
	if _material == null:
		return
	var c := _material.albedo_color
	match kind:
		&"aim_line":
			var thick := lerpf(0.6, 1.6, t)
			_mesh.scale = Vector3(thick, thick, _mesh.scale.z)
		&"bomb_shadow":
			_material.albedo_color = Color(c.r, c.g, c.b, lerpf(0.25, SHADOW.a + 0.2, t))
		_:
			_material.albedo_color = Color(c.r, c.g, c.b, lerpf(0.45, CHALK.a, t))


## Stops following the target: the shot is on its way to this spot (or along this line).
func lock() -> void:
	locked = true
	if kind == &"aim_line":
		_material.albedo_color = Color(1.0, 0.25, 0.2)


func finish() -> void:
	queue_free()
