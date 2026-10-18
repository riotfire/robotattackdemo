class_name CornField
extends MultiMeshInstance3D
## The endless corn wall (GDD 4.2, 4.7): visual only, no collision, so the farmer can wade in.
## Rebuilt from the cosmetic RNG stream every run, leaving a clear gap at each spawn lane.
## Each plant is a hand-cut paper corn stalk (GDD 15.2): a tapered stalk, drooping paper-strip leaves, a
## husked cob and a tassel, built once as an ArrayMesh with the colors in vertex colors.

@export var inner_radius: float = 100.0
@export var outer_radius: float = 128.0
@export var spacing: float = 1.3
@export var jitter: float = 0.45
@export var height_range: Vector2 = Vector2(2.3, 3.3)
@export var lane_gap_width: float = 7.0
## The ring is split into this many angular chunks so off-screen corn is frustum-culled.
@export var chunks: int = 8
@export var stalk_color: Color = Color(0.45, 0.6, 0.24)
@export var leaf_color: Color = Color(0.4, 0.62, 0.22)
@export var leaf_tip_color: Color = Color(0.72, 0.74, 0.34)
@export var cob_color: Color = Color(0.98, 0.8, 0.28)
@export var tassel_color: Color = Color(0.86, 0.72, 0.36)

static var _plant_mesh: ArrayMesh


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)


func _on_run_started(_run_seed: int) -> void:
	rebuild()


func rebuild() -> void:
	var rng := RngService.stream(RngService.STREAM_COSMETIC)
	var lane_dirs: Array[Vector3] = []
	for lane in get_tree().get_nodes_in_group(LaneMarker.GROUP):
		var flat := (lane as Node3D).global_position
		flat.y = 0.0
		lane_dirs.append(flat.normalized())

	var transforms: Array[Array] = []
	var colors: Array[Array] = []
	for c in chunks:
		transforms.append([])
		colors.append([])
	var steps := ceili(outer_radius / spacing)
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var p := Vector3(ix * spacing + rng.randf_range(-jitter, jitter), 0.0, iz * spacing + rng.randf_range(-jitter, jitter))
			var r := p.length()
			if r < inner_radius or r > outer_radius:
				continue
			if _in_lane_gap(p, lane_dirs):
				continue
			var h := rng.randf_range(height_range.x, height_range.y)
			var w := h * rng.randf_range(0.85, 1.1)
			var stalk_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w))
			var lean_axis := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
			if lean_axis.is_normalized():
				stalk_basis = Basis(lean_axis, rng.randf_range(0.0, 0.08)) * stalk_basis
			var chunk := int(fposmod(atan2(p.z, p.x), TAU) / TAU * chunks) % chunks
			transforms[chunk].append(Transform3D(stalk_basis, p))
			# A per-plant tint: some plants a little sun-bleached toward straw.
			colors[chunk].append(Color.WHITE.lerp(Color(1.08, 0.98, 0.72), rng.randf() * rng.randf()))

	multimesh = null
	for child in get_children():
		child.queue_free()
	for c in chunks:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _plant()
		mm.instance_count = transforms[c].size()
		for i in transforms[c].size():
			mm.set_instance_transform(i, transforms[c][i])
			mm.set_instance_color(i, colors[c][i])
		var chunk_instance := MultiMeshInstance3D.new()
		chunk_instance.multimesh = mm
		chunk_instance.cast_shadow = cast_shadow
		add_child(chunk_instance)


## One corn plant, 1 m tall with its origin at the foot. Instances scale it to their height.
func _plant() -> ArrayMesh:
	if _plant_mesh != null:
		return _plant_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stalk: a six-sided taper.
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var b0 := Vector3(cos(a0), 0.0, sin(a0)) * 0.022
		var b1 := Vector3(cos(a1), 0.0, sin(a1)) * 0.022
		var t0 := Vector3(cos(a0), 0.0, sin(a0)) * 0.012 + Vector3.UP * 0.92
		var t1 := Vector3(cos(a1), 0.0, sin(a1)) * 0.012 + Vector3.UP * 0.92
		_quad(st, b0, b1, t1, t0, stalk_color, stalk_color.lightened(0.1))
	# Paper-strip leaves spiralling up the stalk, arching out and drooping at the tip.
	for i in 5:
		var y := 0.18 + 0.13 * i
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * 2.4)
		var side := dir.cross(Vector3.UP)
		var length := 0.44 - 0.04 * absf(i - 2.0)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var segments := 3
		for k in segments + 1:
			var t := float(k) / segments
			var spine := Vector3(0.0, y, 0.0) + dir * length * t + Vector3.UP * (0.16 * t - 0.3 * t * t) * length * 2.0
			var half := 0.045 * (1.0 - t * 0.85)
			var l := spine - side * half
			var r := spine + side * half
			if k > 0:
				var c0 := leaf_color.lerp(leaf_tip_color, (t - 1.0 / segments) * 0.8)
				var c1 := leaf_color.lerp(leaf_tip_color, t * 0.8)
				_quad(st, prev_l, prev_r, r, l, c0, c1)
			prev_l = l
			prev_r = r
	# Cob in its husk, leaning off the stalk.
	var cob_base := Vector3(0.03, 0.5, 0.0)
	var cob_tip := cob_base + Vector3(0.07, 0.17, 0.0)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 1) / 5.0
		var o0 := Vector3(0.0, 0.0, cos(a0)) * 0.035 + Vector3(sin(a0), 0.0, 0.0) * 0.03
		var o1 := Vector3(0.0, 0.0, cos(a1)) * 0.035 + Vector3(sin(a1), 0.0, 0.0) * 0.03
		var mid := cob_base.lerp(cob_tip, 0.45)
		_tri(st, cob_base, mid + o0, mid + o1, leaf_color, cob_color)
		_tri(st, mid + o0, cob_tip, mid + o1, cob_color, cob_color.lightened(0.15))
	# Tassel: a few spikes at the top.
	for i in 5:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 5.0 + 0.3)
		var base := Vector3.UP * 0.9
		var tip := base + dir * 0.09 + Vector3.UP * 0.12
		var side := dir.cross(Vector3.UP) * 0.012
		_tri(st, base - side, base + side, tip, tassel_color.darkened(0.15), tassel_color)
	st.generate_normals()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	# Light glowing through thin paper leaves.
	material.backlight_enabled = true
	material.backlight = Color(0.32, 0.36, 0.12)
	mesh.surface_set_material(0, material)
	_plant_mesh = mesh
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, low: Color, high: Color) -> void:
	_tri(st, a, b, c, low, high)
	st.set_color(low)
	st.add_vertex(a)
	st.set_color(high)
	st.add_vertex(c)
	st.add_vertex(d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, low: Color, high: Color) -> void:
	st.set_color(low)
	st.add_vertex(a)
	st.add_vertex(b)
	st.set_color(high)
	st.add_vertex(c)


func _in_lane_gap(p: Vector3, lane_dirs: Array[Vector3]) -> bool:
	for dir in lane_dirs:
		if p.dot(dir) <= 0.0:
			continue
		var lateral := (p - dir * p.dot(dir)).length()
		if lateral < lane_gap_width * 0.5:
			return true
	return false
