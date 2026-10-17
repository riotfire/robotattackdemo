class_name LaneMarker
extends Marker3D
## One of the 8 robot spawn lanes in the corn at ~110 m (GDD 4.7, 11.6).
## Local -Z faces the silo. The gate posts sit at the corn edge and light up during the siren.

const GROUP: StringName = &"spawn_lanes"

@export var lane_index: int = 1
@export var idle_color: Color = Color(0.55, 0.5, 0.45)
@export var active_color: Color = Color(1.0, 0.25, 0.15)
## Robots spawn within +/- this many meters of the lane center.
@export var spawn_half_width: float = 4.0

var is_active: bool = false
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	_material = StandardMaterial3D.new()
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = _material
	set_active(false)


func set_active(active: bool) -> void:
	is_active = active
	_material.albedo_color = active_color if active else idle_color
	_material.emission_enabled = active
	_material.emission = active_color
	_material.emission_energy_multiplier = 1.5
	var label := get_node_or_null(^"Sign") as Label3D
	if label != null:
		label.modulate = active_color if active else Color.WHITE


## A spawn point in the lane: `lateral` is in [-1, 1] across the lane width.
func spawn_position(lateral: float) -> Vector3:
	return global_position + global_basis.x * lateral * spawn_half_width
