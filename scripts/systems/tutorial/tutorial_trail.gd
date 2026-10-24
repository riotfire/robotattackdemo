class_name TutorialTrail
extends Node3D
## A trail of glowing clay pebbles from the farmer to the current goal (Level 0): follow the dots instead of
## reading directions. It follows the navmesh so it bends round buildings, and pulses toward the goal so the
## direction of travel reads at a glance. Pebbles near the farmer and near the goal are left out so the trail
## never clutters the view or the marker.

const POOL: int = 26
const SPACING: float = 1.9
const SKIP_NEAR_FARMER: float = 3.0
const STOP_BEFORE_GOAL: float = 2.6
const REFRESH_SECONDS: float = 0.35

var color: Color = Color(1.0, 0.82, 0.3)

var _farmer: Node3D
var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
var _points: PackedVector3Array = PackedVector3Array()
var _dots: Array[MeshInstance3D] = []
var _refresh_left: float = 0.0
var _fade: float = 0.0


func setup(farmer: Node3D) -> void:
	_farmer = farmer
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.26
	mesh.height = 0.07
	mesh.radial_segments = 10
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	for i in POOL:
		var dot := MeshInstance3D.new()
		dot.mesh = mesh
		dot.material_override = material
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.visible = false
		add_child(dot)
		_dots.append(dot)


func set_goal(goal: Vector3) -> void:
	_goal = goal
	_has_goal = true
	_refresh_left = 0.0


func clear_goal() -> void:
	_has_goal = false


func _process(delta: float) -> void:
	_fade = move_toward(_fade, 1.0 if _has_goal else 0.0, delta * 3.0)
	if _farmer == null or not is_instance_valid(_farmer) or _fade <= 0.0:
		for dot in _dots:
			dot.visible = false
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		_points = _route(_farmer.global_position, _goal)
	_place_dots()


## Pebble positions every SPACING meters along the way, from where the farmer stands to short of the goal.
func _place_dots() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var used := 0
	var travelled := 0.0
	var next_at := SKIP_NEAR_FARMER
	var total := 0.0
	for i in range(1, _points.size()):
		total += _points[i - 1].distance_to(_points[i])
	for i in range(1, _points.size()):
		var from := _points[i - 1]
		var to := _points[i]
		var length := from.distance_to(to)
		while next_at <= travelled + length and used < POOL:
			if total - next_at < STOP_BEFORE_GOAL:
				break
			var at := from.lerp(to, (next_at - travelled) / maxf(length, 0.001))
			var dot := _dots[used]
			dot.visible = true
			dot.position = at + Vector3.UP * 0.07
			# A wave of growing pebbles running toward the goal.
			var wave := 0.5 + 0.5 * sin(t * 5.0 - used * 0.7)
			dot.scale = Vector3.ONE * lerpf(0.55, 1.25, wave) * _fade
			used += 1
			next_at += SPACING
		travelled += length
	for i in range(used, POOL):
		_dots[i].visible = false


func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		if path.size() >= 2:
			return path
	return PackedVector3Array([from, to])
