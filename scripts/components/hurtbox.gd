class_name Hurtbox
extends Area3D
## Where weapons land (GDD 18.4, layer 5 for robots). Forwards hits to its scene owner's take_damage().
## Weak points (robot eyes) are separate Hurtboxes with is_weak_point set and a x2 multiplier (GDD 6.1).

@export var damage_multiplier: float = 1.0
@export var is_weak_point: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = true


func receiver() -> Node:
	return owner


func hit(packet: DamagePacket) -> void:
	var target := receiver()
	if target == null or not target.has_method("take_damage"):
		return
	packet.amount *= damage_multiplier
	packet.is_weak_point = packet.is_weak_point or is_weak_point
	target.call("take_damage", packet)
