class_name PropScatter
extends Node3D
## Per-run prop variation (GDD 4.6): each run fills a seeded subset of the authored slots (child Marker3Ds,
## metadata "kinds") with hay bale stacks, crate piles, fences, scarecrows and at most one tractor, then
## rebakes the navmesh so robots path around them. Props are low cover (1-3 m) you can jump onto.

@export_range(0.0, 1.0) var fill_chance: float = 0.65
@export var nav_region: NavigationRegion3D

const C_HAY := Color(0.9, 0.78, 0.4)
const C_WOOD := Color(0.6, 0.44, 0.28)
const C_TRACTOR := Color(0.25, 0.6, 0.3)
const C_DARK := Color(0.18, 0.16, 0.15)
const C_CLOTH := Color(0.55, 0.3, 0.25)
const C_STRAW := Color(0.93, 0.8, 0.45)
const C_TWINE := Color(0.62, 0.48, 0.25)

# Clayified CC0 models (tools/clayify, CREDITS.md).
const CRATE_MODEL := preload("res://assets/models/props/prop_crate_02.glb")
const FENCE_MODELS: Array[PackedScene] = [
	preload("res://assets/models/props/prop_fence_01.glb"), preload("res://assets/models/props/prop_fence_02.glb"),
]

var placed: Array[StaticBody3D] = []


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)


func _on_run_started(_run_seed: int) -> void:
	scatter()


func scatter() -> void:
	for prop in placed:
		if is_instance_valid(prop):
			prop.queue_free()
	placed.clear()
	var rng := RngService.stream(RngService.STREAM_FARM)
	var tractor_placed := false
	for child in get_children():
		var slot := child as Marker3D
		if slot == null or rng.randf() > fill_chance:
			continue
		var kinds: PackedStringArray = slot.get_meta(&"kinds", PackedStringArray(["hay"]))
		var kind := kinds[rng.randi_range(0, kinds.size() - 1)]
		if kind == "tractor":
			if tractor_placed:
				kind = "hay"
			tractor_placed = true
		var prop := _build(kind, rng)
		prop.name = "%s_%s" % [kind.capitalize(), slot.name]
		add_child(prop)
		prop.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), slot.global_position)
		placed.append(prop)
	if nav_region != null and nav_region.navigation_mesh != null:
		# Bake into a copy so the shared resource on disk (and in the cache) never changes.
		nav_region.navigation_mesh = nav_region.navigation_mesh.duplicate() as NavigationMesh
		nav_region.bake_navigation_mesh(true)


func _build(kind: String, rng: RandomNumberGenerator) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	match kind:
		"hay":
			var count := rng.randi_range(1, 3)
			for i in mini(count, 2):
				_bale(body, Vector3(0.0, 0.45, (i - 0.5) * 0.9 if count > 1 else 0.0), rng)
			if count == 3:
				_bale(body, Vector3(0.0, 1.35, 0.0), rng)
		"crates":
			var count := rng.randi_range(2, 4)
			var spots: Array[Vector3] = [Vector3(0, 0.5, 0), Vector3(1.05, 0.5, 0.1), Vector3(0.5, 1.5, 0.05), Vector3(-0.2, 0.5, 1.05)]
			for i in count:
				_shape(body, Vector3(1.0, 1.0, 1.0), spots[i])
				var crate_basis := Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)).scaled(Vector3.ONE * 4.0)
				Clay.model(body, CRATE_MODEL, Transform3D(crate_basis, spots[i] - Vector3.UP * 0.5))
		"fence":
			var fence := FENCE_MODELS[rng.randi() % FENCE_MODELS.size()]
			Clay.model(body, fence, Transform3D(Basis().scaled(Vector3(0.68, 1.05, 1.2)), Vector3.ZERO))
			_shape(body, Vector3(4.0, 1.15, 0.25), Vector3(0.0, 0.575, 0.0))
		"scarecrow":
			_box(body, Vector3(0.15, 2.2, 0.15), Vector3(0.0, 1.1, 0.0), C_WOOD)
			_box(body, Vector3(1.6, 0.12, 0.12), Vector3(0.0, 1.6, 0.0), C_WOOD, false)
			_box(body, Vector3(0.6, 0.7, 0.3), Vector3(0.0, 1.45, 0.0), C_CLOTH, false)
			var head := SphereMesh.new()
			head.radius = 0.22
			head.height = 0.44
			Clay.part(body, head, C_STRAW, Transform3D(Basis(), Vector3(0.0, 2.15, 0.0)))
		"tractor":
			_box(body, Vector3(1.6, 1.1, 3.2), Vector3(0.0, 1.0, 0.0), C_TRACTOR)
			_box(body, Vector3(1.4, 1.2, 1.2), Vector3(0.0, 2.1, 0.7), C_TRACTOR)
			for x: float in [-1.0, 1.0]:
				_wheel(body, 0.75, Vector3(x, 0.75, 0.8))
				_wheel(body, 0.45, Vector3(x, 0.45, -1.2))
	return body


func _box(body: StaticBody3D, size: Vector3, center: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	Clay.part(body, mesh, color, Transform3D(Basis(), center))
	if collide:
		_shape(body, size, center)


## A hay bale with two twine bands, slightly askew so a stack looks hand-placed.
func _bale(body: StaticBody3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	var size := Vector3(1.2, 0.9, 0.85)
	_shape(body, size, center)
	var tilt := Basis(Vector3.UP, rng.randf_range(-0.08, 0.08))
	var bale := BoxMesh.new()
	bale.size = size - Vector3(0.02, 0.02, 0.02)
	Clay.part(body, bale, C_HAY.darkened(rng.randf_range(0.0, 0.12)), Transform3D(tilt, center))
	var band := BoxMesh.new()
	band.size = Vector3(0.06, size.y + 0.02, size.z + 0.02)
	for x: float in [-0.3, 0.3]:
		Clay.part(body, band, C_TWINE, Transform3D(tilt, center + tilt * Vector3(x, 0.0, 0.0)))


func _shape(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)


func _wheel(body: StaticBody3D, radius: float, center: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.35
	Clay.part(body, mesh, C_DARK, Transform3D(Basis(Vector3.BACK, PI * 0.5), center))
