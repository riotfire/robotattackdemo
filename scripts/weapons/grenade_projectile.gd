class_name GrenadeProjectile
extends Node3D
## A lobbed shell that bursts on contact or after its fuse. The blast hits each robot once.

var weapon: Weapon
var source: Node
var velocity: Vector3
var damage: float
var radius: float = 5.0
var gravity: float = 18.0
var fuse: float = 2.5

var _visual: MeshInstance3D


func _ready() -> void:
	_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	_visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.72, 0.18)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visual.material_override = material
	add_child(_visual)


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		_explode(global_position)
		return
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var exclude: Array[RID] = []
	if source is CollisionObject3D:
		exclude.append((source as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, Weapon.SHOT_MASK, exclude)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit["position"])
	else:
		global_position = to


func _explode(at: Vector3) -> void:
	AreaAttack.hit_robots(self, at, radius, damage, source, 8.0, weapon)
	global_position = at
	RobotExplosion.blast(self, at, radius)
	queue_free()
