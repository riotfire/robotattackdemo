class_name RobotSkin
extends RefCounted
## The sculpted monowheel robot, split into parts by tools/split_monowheel.py, and the morphs that reshape them for
## the body and head genes. A morph bends the part's own mesh, so a toaster body is still the same painted torso with
## its rivets and emblem, pushed out into a box. Meshes are built once per part and shape, and shared.
##
## Morph settings: `box` and `cylinder` push the rounded part toward that shape (0..1); `size` scales it; `taper` narrows
## the top (negative: the bottom); `bulge` swells the middle.

const PARTS_PATH := "res://assets/models/robots/parts/monowheel.glb"
const BODY_MORPHS: Dictionary[StringName, Dictionary] = {
	&"tin_can": {&"cylinder": 0.9, &"size": Vector3(0.88, 1.0, 0.88)},
	&"gumdrop": {&"cylinder": 0.5, &"taper": 0.4, &"size": Vector3(1.08, 1.0, 1.08)},
	&"toaster": {&"box": 0.4, &"size": Vector3(1.08, 0.9, 0.82)},
	&"egg": {&"taper": 0.3, &"size": Vector3(0.92, 1.15, 0.92)},
	&"barrel": {&"cylinder": 0.75, &"bulge": 0.2, &"size": Vector3(0.95, 1.0, 0.95)},
	&"lunchbox": {&"box": 0.45, &"size": Vector3(1.16, 0.82, 0.78)},
}
const HEAD_MORPHS: Dictionary[StringName, Dictionary] = {
	&"dome": {},
	&"bucket": {&"cylinder": 0.9, &"taper": -0.28, &"size": Vector3(0.9, 1.08, 0.9)},
	&"light_bulb": {&"taper": -0.4, &"size": Vector3(1.0, 1.22, 1.0)},
	&"old_tv": {&"box": 0.5, &"size": Vector3(1.12, 0.92, 0.9)},
	&"teapot": {&"size": Vector3(1.1, 0.86, 1.1)},
	&"mailbox": {&"box": 0.35, &"size": Vector3(0.82, 0.92, 1.12)},
}
## The rounded shells morphs work on, in kit units about each part's pivot (ears and tanks reach further out).
const TORSO_SHELL := Vector3(0.2, 0.176, 0.18)
const HEAD_SHELL := Vector3(0.17, 0.157, 0.18)

static var _meshes: Dictionary[StringName, Mesh] = {}
static var _sockets: Dictionary[StringName, Vector3] = {}
static var _morphed: Dictionary[String, ArrayMesh] = {}


static func mesh(part: StringName) -> Mesh:
	_load_parts()
	return _meshes[part]


## The part's socket in kit space.
static func socket(part: StringName) -> Vector3:
	_load_parts()
	return _sockets[part]


## `part` (the torso or head) reshaped by `settings`, about its pivot.
static func morphed(part: StringName, shape: StringName, settings: Dictionary, shell: Vector3) -> Mesh:
	if settings.is_empty():
		return mesh(part)
	var key := "%s:%s" % [part, shape]
	if not _morphed.has(key):
		_morphed[key] = _bend(mesh(part), settings, shell)
	return _morphed[key]


## Where a point on the part (relative to its pivot) ends up, for placing what sits on it.
static func bend_point(p: Vector3, settings: Dictionary, shell: Vector3) -> Vector3:
	var q := p / shell
	var box := settings.get(&"box", 0.0) as float
	var cylinder := settings.get(&"cylinder", 0.0) as float
	var length := q.length()
	if length > 0.0001:
		if box > 0.0:
			q *= lerpf(1.0, length / maxf(absf(q.x), maxf(absf(q.y), absf(q.z))), box)
		if cylinder > 0.0:
			var flat := Vector2(q.x, q.z).length()
			q *= lerpf(1.0, length / maxf(flat, absf(q.y)), cylinder)
	var ring := 1.0 + (settings.get(&"bulge", 0.0) as float) * (1.0 - clampf(q.y * q.y, 0.0, 1.0)) \
			- (settings.get(&"taper", 0.0) as float) * clampf(q.y, -1.0, 1.0)
	q.x *= ring
	q.z *= ring
	return q * shell * (settings.get(&"size", Vector3.ONE) as Vector3)


static func _load_parts() -> void:
	if not _meshes.is_empty():
		return
	var root := (load(PARTS_PATH) as PackedScene).instantiate()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		_meshes[StringName(instance.name)] = instance.mesh
		_sockets[StringName(instance.name)] = instance.position
	root.free()


## Moves every vertex through bend_point, and re-derives its normal by bending two small steps along the surface.
static func _bend(source: Mesh, settings: Dictionary, shell: Vector3) -> ArrayMesh:
	const STEP: float = 0.004
	var arrays := source.surface_get_arrays(0)
	var positions := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	for i in positions.size():
		var p := positions[i]
		var n := normals[i]
		var side := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var along := n.cross(side)
		var bent := bend_point(p, settings, shell)
		var bent_normal := (bend_point(p + along * STEP, settings, shell) - bent) \
				.cross(bend_point(p + side * STEP, settings, shell) - bent)
		if bent_normal.dot(n) < 0.0:
			bent_normal = -bent_normal
		if bent_normal.length_squared() > 0.0:
			normals[i] = bent_normal.normalized()
		positions[i] = bent
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
