class_name FarmDecor
extends Node3D
## Set dressing with no gameplay role (no collision): wildflowers and grass tufts across
## the farmyard, and concentric crop rows across the crop ring with a path left along each spawn lane.
## Built at load from a fixed seed, as MultiMeshes of clayified CC0 models (tools/clayify, CREDITS.md).
## Built at run time rather than baked because headless tool runs can't save MultiMesh instance buffers.
## Tiny decor is too small to show clay lumps, so it uses a plain vertex-colored material (much cheaper than
## the clay shader over thousands of instances), and the crop rows are chunked per sector for culling.

const MODEL_DIR := "res://assets/models/"

@export var decor_seed: int = 4471
## Farmyard scatter stays inside this radius and outside these footprints (x, z rectangles).
@export var yard_radius: float = 54.0
@export var keep_out: Array[Rect2] = []
## Crop rows fill this ring, leaving `lane_path_width` clear along each lane bearing (22.5 + 45k degrees).
@export var crop_inner_radius: float = 58.0
@export var crop_outer_radius: float = 97.0
@export var lane_path_width: float = 9.0

## Farmyard models: [count, min scale, max scale].
const YARD: Dictionary[String, Array] = {
	"props/nature_grass_tuft.glb": [1300, 1.2, 1.9],
	"props/nature_flower_yellow.glb": [260, 1.8, 2.5],
	"props/nature_flower_red.glb": [200, 1.8, 2.5],
	"props/nature_flower_purple.glb": [200, 1.8, 2.5],
}
const CROPS: PackedStringArray = [
	"crops/crop_wheat.glb", "crops/crop_leafy.glb", "crops/crop_pumpkin.glb",
	"crops/crop_wheat.glb", "crops/crop_wheat.glb", "crops/crop_corn_mid.glb",
]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = decor_seed
	_build_yard(rng)
	_build_crop_rows(rng)


func _build_yard(rng: RandomNumberGenerator) -> void:
	for model_path in YARD:
		var spec: Array = YARD[model_path]
		var xforms: Array[Transform3D] = []
		var attempts := 0
		while xforms.size() < int(spec[0]) and attempts < 20000:
			attempts += 1
			# Clumps: pick a center, then scatter a handful around it.
			var center := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (yard_radius - 1.0)
			for c in rng.randi_range(3, 8):
				var p := center + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
				if p.length() > yard_radius or _kept_out(p):
					continue
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(spec[1], spec[2]))
				xforms.append(Transform3D(basis, Vector3(p.x, 0.02, p.y)))
		_add_multimesh(model_path, xforms)


func _build_crop_rows(rng: RandomNumberGenerator) -> void:
	for sector in 16:
		var crop := CROPS[rng.randi() % CROPS.size()]
		var xforms: Array[Transform3D] = []
		var a0 := deg_to_rad(22.5 * sector)
		var a1 := a0 + deg_to_rad(22.5)
		var radius := crop_inner_radius
		while radius < crop_outer_radius:
			var step := 1.6 / radius
			var a := a0 + step * 0.5
			while a < a1:
				var from_lane := deg_to_rad(absf(fposmod(rad_to_deg(a), 45.0) - 22.5)) * radius
				if from_lane > lane_path_width * 0.5:
					var p := Vector3(sin(a), 0.0, -cos(a)) * (radius + rng.randf_range(-0.2, 0.2))
					var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.7, 2.3))
					xforms.append(Transform3D(basis, p))
				a += step
			radius += 2.4
		_add_multimesh(crop, xforms)


static var _shared_material: StandardMaterial3D


static func _material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.vertex_color_is_srgb = false
		_shared_material.roughness = 0.75
		_shared_material.rim_enabled = true
		_shared_material.rim = 0.2
	return _shared_material


func _kept_out(p: Vector2) -> bool:
	for rect in keep_out:
		if rect.has_point(p):
			return true
	return false


func _add_multimesh(model_path: String, xforms: Array[Transform3D]) -> void:
	var root := (load(MODEL_DIR + model_path) as PackedScene).instantiate()
	var source := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source.mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	root.free()
	var instance := MultiMeshInstance3D.new()
	instance.name = model_path.get_file().get_basename()
	instance.multimesh = mm
	instance.material_override = _material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
