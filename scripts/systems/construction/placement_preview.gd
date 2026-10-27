class_name PlacementPreview
extends Node3D
## The see-through ghost a defense shows while the farmer places it (ConstructionManager): its footprint and
## height, an arrow for the way it faces, green where it fits and red where it doesn't. Only a picture: it
## has no collision and isn't in Defense.GROUP, so robots never see it.

const FITS := Color(0.35, 1.0, 0.45, 0.45)
const BLOCKED := Color(1.0, 0.3, 0.25, 0.45)

var _material: StandardMaterial3D
var _shape: MeshInstance3D
var _arrow: MeshInstance3D
var _built_for: StringName = &""


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	_shape = MeshInstance3D.new()
	_shape.name = "Shape"
	_shape.material_override = _material
	_shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shape)
	var prism := PrismMesh.new()
	prism.size = Vector3(0.5, 0.7, 0.06)
	_arrow = MeshInstance3D.new()
	_arrow.name = "Arrow"
	_arrow.mesh = prism
	_arrow.material_override = _material
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)


## Moves the ghost of `definition` to `spot` and colors it by whether it fits.
func show_spot(definition: DefenseDefinition, spot: ConstructionManager.Spot) -> void:
	var key := StringName("%s_%s" % [definition.id, spot.kind])
	if key != _built_for:
		_built_for = key
		_shape.mesh = _mesh_for(definition, spot.kind)
	var footprint := ConstructionManager.Footprint.of(definition, spot.kind, spot.launch)
	global_position = spot.position
	_shape.basis = footprint.basis()
	_shape.position = Vector3.UP * (footprint.height * 0.5 + 0.02)
	# The arrow lies flat just above the shape, pointing the way a spring throws (or a wall faces).
	var yaw := atan2(spot.launch.x, spot.launch.z)
	_arrow.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	_arrow.position = Vector3.UP * (footprint.height + 0.08) + spot.launch * 0.15
	_material.albedo_color = FITS if spot.problem.is_empty() else BLOCKED


func _mesh_for(definition: DefenseDefinition, kind: StringName) -> Mesh:
	var footprint := ConstructionManager.Footprint.of(definition, kind, Vector3.FORWARD)
	if footprint.half_length > 0.0:
		var box := BoxMesh.new()
		box.size = Vector3(footprint.half_length * 2.0, footprint.height, footprint.radius * 2.0)
		return box
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = footprint.radius
	cylinder.bottom_radius = footprint.radius
	cylinder.height = footprint.height
	cylinder.radial_segments = 20
	cylinder.rings = 1
	return cylinder
