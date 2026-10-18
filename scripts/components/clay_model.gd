@tool
class_name ClayModel
extends Node3D
## Shows a clayified model (tools/clayify, assets/models/*.glb) with the vertex-colored clay material.
## The model is instanced as an internal child when the node enters the tree, so baked scenes only store
## the path to the .glb and the node's transform, never the mesh itself. Visual only: collision stays on
## the owning body's own shapes.

@export var model: PackedScene:
	set(value):
		model = value
		if is_inside_tree():
			_rebuild()
@export var cast_shadow: bool = true

var _instance: Node3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _instance != null:
		_instance.queue_free()
		_instance = null
	if model == null:
		return
	_instance = model.instantiate() as Node3D
	add_child(_instance, false, Node.INTERNAL_MODE_FRONT)
	for node in _instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = Clay.vertex_colored()
		if not cast_shadow:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The model's mesh bounds in its own space (all models are exported with the origin at bottom center).
static func model_aabb(scene: PackedScene) -> AABB:
	var root := scene.instantiate() as Node3D
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var local := _transform_to(root, mesh_instance) * mesh_instance.mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	root.free()
	return box


static func _transform_to(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != root and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
