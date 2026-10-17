class_name HealthComponent
extends Node
## HP for anything that can be destroyed (GDD 18.4).

signal health_changed(current: float, maximum: float)
signal died

@export var max_health: float = 100.0

var current: float = 0.0
var invulnerable: bool = false


func _ready() -> void:
	current = max_health


func reset(new_max: float) -> void:
	max_health = new_max
	current = new_max
	health_changed.emit(current, max_health)


## Returns the damage actually taken.
func apply_damage(amount: float) -> float:
	if invulnerable or is_dead() or amount <= 0.0:
		return 0.0
	var taken := minf(amount, current)
	current -= taken
	health_changed.emit(current, max_health)
	if current <= 0.0:
		died.emit()
	return taken


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0 or current >= max_health:
		return
	current = minf(max_health, current + amount)
	health_changed.emit(current, max_health)


func is_dead() -> bool:
	return current <= 0.0


func fraction() -> float:
	return current / max_health if max_health > 0.0 else 0.0
