class_name Fx
extends RefCounted
## Throwaway graybox effects: hitscan tracers and impact puffs.
## Replaced by pooled clay/cotton VFX in M1 (GDD 15.6).

static var _materials: Dictionary[Color, StandardMaterial3D] = {}


static func tracer(context: Node, from: Vector3, to: Vector3, color: Color = Color(1.0, 0.9, 0.5)) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, length)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var instance := _spawn(context, mesh, color, Transform3D(Basis.looking_at(dir, up), (from + to) * 0.5))
	var tween := instance.create_tween()
	tween.tween_property(instance, ^"transparency", 1.0, 0.08)
	tween.tween_callback(instance.queue_free)


static func puff(context: Node, at: Vector3, color: Color, radius: float = 0.25, duration: float = 0.25) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var instance := _spawn(context, mesh, color, Transform3D(Basis(), at))
	var tween := instance.create_tween()
	tween.set_parallel()
	tween.tween_property(instance, ^"scale", Vector3.ONE * 1.8, duration)
	tween.tween_property(instance, ^"transparency", 1.0, duration)
	tween.chain().tween_callback(instance.queue_free)


static func _spawn(context: Node, mesh: Mesh, color: Color, xform: Transform3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var parent := context.get_tree().current_scene if context.get_tree().current_scene != null else context.get_tree().root
	parent.add_child(instance)
	instance.global_transform = xform
	return instance


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[color] = m
	return _materials[color]
