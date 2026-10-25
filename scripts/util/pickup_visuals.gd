class_name PickupVisuals
extends RefCounted
## Compact loot silhouettes. Each kind is built once, with all details in one surface/draw.
## No per-drop materials, textures, lights, shadows or physics bodies.

static var _meshes: Dictionary[StringName, ArrayMesh] = {}
static var _material: ShaderMaterial


static func create(kind: StringName, color: Color) -> MeshInstance3D:
	if not _meshes.has(kind):
		_meshes[kind] = _build(kind, color)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/pickup.gdshader")
	var visual := MeshInstance3D.new()
	visual.mesh = _meshes[kind]
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual


static func _build(kind: StringName, color: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		&"al":
			_gear(surface, color)
		&"cu":
			_tube(surface, color, 0.105, 0.027, 3.0, 0.29, 48)
		&"au":
			_tube(surface, color, 0.15, 0.038, 1.0, 0.0, 24)
		&"pc":
			_box(surface, Vector3.ZERO, Vector3(0.22, 0.30, 0.15), color)
			var silver := Color(0.8, 0.9, 1.0)
			_box(surface, Vector3(0.0, 0.15, 0.0), Vector3(0.23, 0.035, 0.16), silver)
			_box(surface, Vector3(0.0, -0.15, 0.0), Vector3(0.23, 0.035, 0.16), silver)
			_box(surface, Vector3(0.0, 0.184, 0.0), Vector3(0.09, 0.04, 0.08), silver)
			# A bright band and raised plus on both faces read as a battery while spinning.
			_box(surface, Vector3(0.0, -0.075, 0.0), Vector3(0.224, 0.035, 0.154), Color(0.3, 0.85, 1.0))
			_box(surface, Vector3(0.0, 0.035, 0.0), Vector3(0.09, 0.025, 0.158), silver)
			_box(surface, Vector3(0.0, 0.035, 0.0), Vector3(0.025, 0.09, 0.16), silver)
	surface.index()
	return surface.commit()


static func _gear(surface: SurfaceTool, color: Color) -> void:
	# Eight broad teeth and a real open center, tilted so the hole reads from above and the side.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-25.0))
	for i in 32:
		var a := TAU * i / 32.0
		var b := TAU * (i + 1) / 32.0
		var ra := 0.21 if i % 4 == 1 or i % 4 == 2 else 0.16
		var rb := 0.21 if (i + 1) % 4 == 1 or (i + 1) % 4 == 2 else 0.16
		var oa := Vector3(cos(a) * ra, sin(a) * ra, 0.035)
		var ob := Vector3(cos(b) * rb, sin(b) * rb, 0.035)
		var ia := Vector3(cos(a) * 0.075, sin(a) * 0.075, 0.035)
		var ib := Vector3(cos(b) * 0.075, sin(b) * 0.075, 0.035)
		var depth := Vector3(0.0, 0.0, 0.07)
		_quad(surface, tilt * ia, tilt * ib, tilt * ob, tilt * oa, color)
		_quad(surface, tilt * (oa - depth), tilt * (ob - depth), tilt * (ib - depth), tilt * (ia - depth), color)
		_quad(surface, tilt * oa, tilt * ob, tilt * (ob - depth), tilt * (oa - depth), color.darkened(0.18))
		_quad(surface, tilt * ib, tilt * ia, tilt * (ia - depth), tilt * (ib - depth), color.darkened(0.18))


static func _tube(surface: SurfaceTool, color: Color, radius: float, wire: float,
		turns: float, height: float, segments: int) -> void:
	# A real helix for copper; a closed torus for gold. Six sides are enough for tiny clay wire.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(65.0 if height == 0.0 else 15.0))
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / segments
		var angle := t * TAU * turns
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-sin(angle) * radius, height / (TAU * turns), cos(angle) * radius).normalized()
		var across := tangent.cross(radial).normalized()
		var center := radial * radius + Vector3.UP * ((t - 0.5) * height)
		for j in 6:
			var normal := radial * cos(TAU * j / 6.0) + across * sin(TAU * j / 6.0)
			points.append(tilt * (center + normal * wire))
			normals.append(tilt * normal)
	for i in segments:
		for j in 6:
			var a := i * 6 + j
			var b := i * 6 + (j + 1) % 6
			for index in [a, b + 6, b, a, a + 6, b + 6]:
				surface.set_color(color.srgb_to_linear())
				surface.set_normal(normals[index])
				surface.add_vertex(points[index])
	if height > 0.0:
		for j in range(1, 5):
			_triangle(surface, points[0], points[j + 1], points[j], color)
			var end := segments * 6
			_triangle(surface, points[end], points[end + j], points[end + j + 1], color)


static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for v in [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]:
		p.append(center + v)
	for face in [[0, 1, 2, 3], [7, 6, 5, 4], [4, 5, 1, 0], [3, 2, 6, 7], [1, 5, 6, 2], [4, 0, 3, 7]]:
		_quad(surface, p[face[0]], p[face[1]], p[face[2]], p[face[3]], color)


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(surface, a, b, c, color)
	_triangle(surface, a, c, d, color)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		surface.set_color(color.srgb_to_linear())
		surface.set_normal(normal)
		surface.add_vertex(point)
