class_name CornField
extends MultiMeshInstance3D
## The endless corn wall (GDD 4.2, 4.7): visual only, no collision, so the farmer can wade in.
## Rebuilt from the cosmetic RNG stream every run, leaving a clear gap at each spawn lane.

@export var inner_radius: float = 100.0
@export var outer_radius: float = 128.0
@export var spacing: float = 1.3
@export var jitter: float = 0.45
@export var height_range: Vector2 = Vector2(2.3, 3.3)
@export var lane_gap_width: float = 7.0
@export var stalk_color: Color = Color(0.42, 0.55, 0.22)
@export var tassel_color: Color = Color(0.8, 0.72, 0.35)


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

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
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
			var stalk_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, h, 1.0))
			var lean_axis := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
			if lean_axis.is_normalized():
				stalk_basis = Basis(lean_axis, rng.randf_range(0.0, 0.08)) * stalk_basis
			transforms.append(Transform3D(stalk_basis, p + Vector3.UP * h * 0.5))
			colors.append(stalk_color.lerp(tassel_color, rng.randf() * 0.35))

	var stalk := BoxMesh.new()
	stalk.size = Vector3(0.16, 1.0, 0.16)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	stalk.material = material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stalk
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	multimesh = mm


func _in_lane_gap(p: Vector3, lane_dirs: Array[Vector3]) -> bool:
	for dir in lane_dirs:
		if p.dot(dir) <= 0.0:
			continue
		var lateral := (p - dir * p.dot(dir)).length()
		if lateral < lane_gap_width * 0.5:
			return true
	return false
