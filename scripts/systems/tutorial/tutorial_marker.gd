class_name TutorialMarker
extends Node3D
## A ground-level destination ring. The normal HUD teaches the action and shows progress; this marker only
## anchors the pebble trail in the world, so it stays in view as the player approaches.

var color: Color = Color(1.0, 0.8, 0.3)
var radius: float = 1.6

var _shown: float = 0.0
var _wanted: bool = true
var _pulse: float = 0.0


static func create(where: Vector3, tint: Color, ring_radius: float = 1.6) -> TutorialMarker:
	var marker := TutorialMarker.new()
	marker.position = where
	marker.color = tint
	marker.radius = ring_radius
	marker._build()
	return marker


func _build() -> void:
	name = "TutorialMarker"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.025
	disc.radial_segments = 40
	var fill := MeshInstance3D.new()
	fill.name = "GroundFill"
	fill.mesh = disc
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.albedo_color = Color(color, 0.16)
	fill.material_override = fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.position.y = 0.035
	add_child(fill)

	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = radius - 0.07
	rim_mesh.outer_radius = radius
	rim_mesh.rings = 40
	rim_mesh.ring_segments = 6
	var rim := MeshInstance3D.new()
	rim.name = "GroundRim"
	rim.mesh = rim_mesh
	var rim_material := StandardMaterial3D.new()
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.albedo_color = color
	rim.material_override = rim_material
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.scale.y = 0.3
	rim.position.y = 0.07
	add_child(rim)


func set_wanted(on: bool) -> void:
	_wanted = on


func nudge() -> void:
	_pulse = 1.0


func is_gone() -> bool:
	return not _wanted and _shown <= 0.01


func _process(delta: float) -> void:
	_shown = move_toward(_shown, 1.0 if _wanted else 0.0, delta * 3.5)
	_pulse = maxf(0.0, _pulse - delta * 1.6)
	visible = _shown > 0.01
	var eased := _shown * _shown * (3.0 - 2.0 * _shown)
	var ripple := 1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.004) + _pulse * 0.18
	scale = Vector3(ripple, 1.0, ripple) * eased
