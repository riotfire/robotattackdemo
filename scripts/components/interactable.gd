class_name Interactable
extends Node3D
## Something the farmer can use with Interact (GDD 5.2): ziplines, the dinner bell, the tool shed.
## The farmer focuses the nearest one in range; silo cracks are handled separately and take priority.
## In co-op, interact() is the client's intent and runs on the host (GDD 18.8).

const GROUP: StringName = &"interactables"

## How close the farmer's feet must be to interaction_point().
@export var interact_range: float = 1.8
## 0 = press; otherwise Interact must be held this long.
@export var hold_time: float = 0.0
@export var prompt: String = "Interact"


func _ready() -> void:
	add_to_group(GROUP)


func interaction_point() -> Vector3:
	return global_position


func can_interact(_farmer: Farmer) -> bool:
	return true


func prompt_text(_farmer: Farmer) -> String:
	return prompt


func interact(_farmer: Farmer) -> void:
	pass
