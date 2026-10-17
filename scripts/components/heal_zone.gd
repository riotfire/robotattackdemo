class_name HealZone
extends Area3D
## The Home porch heal zone (GDD 3.4, 8.1): 15 HP/s while standing in it, during waves and intermissions.

@export var heal_per_second: float = 15.0

var _bodies: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 1 << 7  # Interactables
	collision_mask = 1 << 1  # Player
	monitorable = false
	body_entered.connect(func(body: Node3D) -> void: _bodies.append(body))
	body_exited.connect(func(body: Node3D) -> void: _bodies.erase(body))


func _physics_process(delta: float) -> void:
	for body in _bodies:
		if is_instance_valid(body) and body.has_method("heal"):
			body.call("heal", StatService.get_stat(&"home.heal_rate", heal_per_second) * delta)


func contains(body: Node3D) -> bool:
	return body in _bodies
