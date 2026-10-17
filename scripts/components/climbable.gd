class_name Climbable
extends Area3D
## A ladder or vine trellis (GDD 4.5). Climb at 4 m/s; you can't shoot while climbing.
## The origin is the foot of the climb line (where the climber's feet go) and local +Z points away
## from the wall. You step off at the top, or with Jump at any height listed in `landings`.

@export var climb_height: float = 8.0
## Heights above the origin of intermediate floors (e.g. silo catwalks) you can step onto with Jump.
@export var landings: PackedFloat32Array = PackedFloat32Array()
## How far toward the wall a landing step-off puts you.
@export var landing_depth: float = 1.2
## How far toward the wall, and how much higher than climb_height, the top step-off puts you.
@export var top_exit_depth: float = 1.2
@export var top_exit_rise: float = 0.0
@export var climb_speed: float = 4.0
## How far below / above a landing you can be and still step onto it.
@export var landing_window_below: float = 0.7
@export var landing_window_above: float = 1.0


func _ready() -> void:
	collision_layer = 1 << 7  # Interactables
	collision_mask = 1 << 1  # Player
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func outward() -> Vector3:
	var n := global_basis.z
	n.y = 0.0
	return n.normalized()


func height_above_base(world_position: Vector3) -> float:
	return world_position.y - global_position.y


func line_position(height: float) -> Vector3:
	return global_position + Vector3.UP * height


## The landing whose step-off window contains `height`, or NAN if none.
func landing_near(height: float) -> float:
	for landing in landings:
		if height >= landing - landing_window_below and height <= landing + landing_window_above:
			return landing
	return NAN


func landing_exit_point(landing: float) -> Vector3:
	return global_position - outward() * landing_depth + Vector3.UP * (landing + 0.05)


func top_exit_point() -> Vector3:
	return global_position - outward() * top_exit_depth + Vector3.UP * (climb_height + top_exit_rise + 0.05)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("add_climbable"):
		body.call("add_climbable", self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("remove_climbable"):
		body.call("remove_climbable", self)
