class_name ScrapBarricade
extends Defense
## Scrap Barricade: a solid wall of junk across an approach. Robots collide with it (Defense.LAYER) and smash
## it before going on, which holds a push in one place; the farmer walks straight through, so it never cuts
## off a ladder, a crack or an exit. On the ground it stands across the way the farmer faced when placing it. On
## the catwalk it closes one way around the ring, so a Rung Runner either takes the other way (where a spring
## can wait for it) or, if both ways are shut, has to break through.

var _body: StaticBody3D
## Unit vector along the wall, and its half width.
var _along: Vector3 = Vector3.RIGHT
var _half_width: float = 1.8


func _ready() -> void:
	_orient()
	super._ready()
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = Defense.LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_half_width * 2.0, definition.barricade_height, 0.5)
	shape.shape = box
	shape.position = Vector3.UP * definition.barricade_height * 0.5
	_body.add_child(shape)
	add_child(_body)
	_body.global_basis = _wall_basis()
	_set_solid(active)


func _on_active_changed() -> void:
	super._on_active_changed()
	_set_solid(active)


func relocated() -> void:
	super.relocated()
	if _body != null:
		var box := (_body.get_child(0) as CollisionShape3D).shape as BoxShape3D
		box.size = Vector3(_half_width * 2.0, definition.barricade_height, 0.5)
		_body.global_basis = _wall_basis()


## Flat distance from `from` to the wall's segment.
func distance_from(from: Vector3) -> float:
	var flat := from - global_position
	flat.y = 0.0
	var along := clampf(flat.dot(_along), -_half_width, _half_width)
	return (flat - _along * along).length()


## The nearest point of the wall to `from`, half a meter up.
func strike_point(from: Vector3) -> Vector3:
	var flat := from - global_position
	flat.y = 0.0
	var along := clampf(flat.dot(_along), -_half_width, _half_width)
	return global_position + _along * along + Vector3.UP * 0.5


## True if the wall lies between `from` and `goal` (flat), within `reach` of `from`.
func blocks(from: Vector3, goal: Vector3, reach: float) -> bool:
	if not active or distance_from(from) > reach:
		return false
	var normal := Vector3.UP.cross(_along).normalized()
	var a := (from - global_position).dot(normal)
	var b := (goal - global_position).dot(normal)
	# On opposite sides, or right against it while the goal is beyond.
	return signf(a) != signf(b) or absf(a) < 0.35


func label_height() -> float:
	return definition.barricade_height + 0.6


func _set_solid(on: bool) -> void:
	if _body != null:
		_body.collision_layer = Defense.LAYER if on else 0


## Across the approach on the ground; along the radius (across the walkway) on the catwalk.
func _orient() -> void:
	var kind := site.kind if site != null else &"ground"
	_along = wall_along(kind, site.launch_direction if site != null else Vector3.FORWARD)
	_half_width = wall_half_width(definition, kind)


## The unit vector along a wall facing `out` on a `kind` floor (ConstructionManager's placement uses it too).
static func wall_along(kind: StringName, out: Vector3) -> Vector3:
	if kind == &"catwalk":
		return out
	return Vector3.UP.cross(out).normalized()


static func wall_half_width(defense_definition: DefenseDefinition, kind: StringName) -> float:
	if kind == &"catwalk":
		return minf(defense_definition.barricade_width * 0.5, 0.95)
	return defense_definition.barricade_width * 0.5


func _wall_basis() -> Basis:
	var normal := Vector3.UP.cross(_along).normalized()
	return Basis(_along, Vector3.UP, -normal).orthonormalized()


func _build_look() -> void:
	_orient()
	var look := Node3D.new()
	look.name = "Look"
	add_child(look)
	look.global_basis = _wall_basis()
	var height := definition.barricade_height
	var width := _half_width * 2.0
	var plank := BoxMesh.new()
	plank.size = Vector3(width, 0.22, 0.12)
	for i in 4:
		var tilt := Basis(Vector3.BACK, deg_to_rad(4.0 if i % 2 == 0 else -3.0))
		Clay.part(look, plank, Color(0.58, 0.43, 0.28).darkened(0.08 * (i % 2)), Transform3D(tilt, Vector3(0.0, 0.18 + i * 0.27, 0.1)))
	var crate := BoxMesh.new()
	crate.size = Vector3(0.5, 0.5, 0.5)
	for x in [-1.0, 1.0]:
		Clay.part(look, crate, Color(0.5, 0.36, 0.22), Transform3D(Basis(Vector3.UP, 0.3 * x), Vector3(x * (width * 0.5 - 0.3), 0.25, -0.15)))
	var tire := TorusMesh.new()
	tire.inner_radius = 0.16
	tire.outer_radius = 0.3
	Clay.part(look, tire, Color(0.15, 0.14, 0.14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, height - 0.05, -0.1)))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(width * 0.8, 0.08, 0.13)
	Clay.part(look, stripe, Color(0.95, 0.75, 0.15), Transform3D(Basis(), Vector3(0.0, height * 0.55, 0.17)), 0.3)
