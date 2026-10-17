class_name Clay
extends RefCounted
## Helpers for the shared clay material (GDD 15.3, shaders/clay.gdshader).
## Runtime objects (robots, props) share one material and set a per-instance `tint`, so no material is
## duplicated per robot (GDD 10.4). Scenes baked by tools use per-color copies via colored().

const MATERIAL_PATH := "res://shaders/clay_material.tres"

static var _shared: ShaderMaterial
static var _colored: Dictionary[Color, ShaderMaterial] = {}


static func shared() -> ShaderMaterial:
	if _shared == null:
		_shared = load(MATERIAL_PATH) as ShaderMaterial
	return _shared


## A copy of the clay material with a fixed albedo color (cached per color).
static func colored(color: Color) -> ShaderMaterial:
	if not _colored.has(color):
		var material := shared().duplicate() as ShaderMaterial
		material.set_shader_parameter(&"albedo_color", color)
		_colored[color] = material
	return _colored[color]


## Gives `instance` the shared clay material tinted `color`. `glow` > 0 makes it emissive.
static func apply(instance: GeometryInstance3D, color: Color, glow: float = 0.0) -> void:
	instance.material_override = shared()
	instance.set_instance_shader_parameter(&"tint", color)
	if glow > 0.0:
		instance.set_instance_shader_parameter(&"emission_strength", glow)


## A MeshInstance3D with `mesh`, tinted clay, at `xform` under `parent`.
static func part(parent: Node, mesh: Mesh, color: Color, xform: Transform3D, glow: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	instance.transform = xform
	apply(instance, color, glow)
	return instance
