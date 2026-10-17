class_name DamagePacket
extends RefCounted
## One hit of damage (GDD 18.4). Anything damageable implements take_damage(packet: DamagePacket).

var amount: float = 0.0
## The node that caused the hit (a player, a robot). May be freed later; check is_instance_valid.
var source: Node = null
var position: Vector3 = Vector3.ZERO
var is_weak_point: bool = false
var knockback: Vector3 = Vector3.ZERO
var stun_time: float = 0.0


static func create(damage: float, from: Node, at: Vector3) -> DamagePacket:
	var packet := DamagePacket.new()
	packet.amount = damage
	packet.source = from
	packet.position = at
	return packet
