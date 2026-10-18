class_name Projectile
extends Node3D
## A pooled projectile (GDD 18.4, 18.7): a small mesh with no physics body. Each physics step it sweeps a
## ray from where it was to where it's going, so even fast shots can't tunnel through a thin hurtbox.
## Launched and recycled by a ProjectilePool; weapons use it now, and robot projectiles (M2-A4) can too.

const MAX_PIERCES_PER_STEP: int = 4

static var _meshes: Dictionary[float, SphereMesh] = {}
static var _materials: Dictionary[Color, StandardMaterial3D] = {}

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 0.0
var collision_mask: int = 0
var time_left: float = 0.0
## Called as on_hit(hit: Dictionary) with an intersect_ray result. Returns true to fly on through.
var on_hit: Callable
var is_active: bool = false

var _exclude: Array[RID] = []
var _pool: ProjectilePool = null
var _mesh: MeshInstance3D


func _init() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false
	set_physics_process(false)


func launch(pool: ProjectilePool, from: Vector3, launch_velocity: Vector3, pull: float, lifetime: float, mask: int,
		exclude: Array[RID], hit_callback: Callable, color: Color, radius: float) -> void:
	_pool = pool
	velocity = launch_velocity
	gravity = pull
	time_left = lifetime
	collision_mask = mask
	_exclude = exclude.duplicate()
	on_hit = hit_callback
	_mesh.mesh = _sphere(radius)
	_mesh.material_override = _material(color)
	global_position = from
	reset_physics_interpolation()
	is_active = true
	visible = true
	set_physics_process(true)


## Stops it and hands it back to its pool.
func retire() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	set_physics_process(false)
	on_hit = Callable()
	_exclude.clear()
	if _pool != null and is_instance_valid(_pool):
		_pool.release(self)


func _physics_process(delta: float) -> void:
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var space := get_world_3d().direct_space_state
	for i in MAX_PIERCES_PER_STEP:
		var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, _exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var keep_going := on_hit.is_valid() and bool(on_hit.call(hit))
		if not keep_going or not is_active:
			global_position = hit["position"]
			retire()
			return
		_exclude.append(hit["rid"])
		from = hit["position"]
	global_position = to
	time_left -= delta
	if time_left <= 0.0:
		retire()


static func _sphere(radius: float) -> SphereMesh:
	if not _meshes.has(radius):
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		_meshes[radius] = mesh
	return _meshes[radius]


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		_materials[color] = m
	return _materials[color]
