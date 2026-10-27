class_name HealZone
extends Area3D
## The Home porch heal zone (GDD 3.4, 8.1): 15 HP/s while standing in it, during waves and intermissions.

@export var heal_per_second: float = 15.0
## The stat that scales it (Porch Swing for the porch); empty for a fixed rate.
@export var heal_stat: StringName = &"home.heal_rate"

var _bodies: Array[Node3D] = []


const GROUP: StringName = &"heal_zones"


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 1 << 7  # Interactables
	collision_mask = 1 << 1  # Player
	monitorable = false
	body_entered.connect(func(body: Node3D) -> void: _bodies.append(body))
	body_exited.connect(func(body: Node3D) -> void: _bodies.erase(body))


func _physics_process(delta: float) -> void:
	for body in _bodies:
		if is_instance_valid(body) and body.has_method("heal"):
			var rate := heal_per_second if heal_stat.is_empty() else StatService.get_stat(heal_stat, heal_per_second)
			body.call("heal", rate * delta)


func contains(body: Node3D) -> bool:
	return body in _bodies
