class_name WeaponMod
extends Resource
## A weapon mod (GDD 6.3, 18.4): a small strategy script that hooks a weapon's shots. Subclass it and
## override the hooks you need; the weapon calls them for every mod it has installed, in install order.
## Mods are per weapon node, so each co-op farmer has their own.

@export var id: StringName
@export var display_name: String = "Mod"
@export_multiline var description: String = ""


## Before a shot or swing resolves. Change `shot` to change it (damage, direction, range).
func on_fire(_weapon: Weapon, _shot: WeaponShot) -> void:
	pass


## Before a hit lands on `target`. Change `packet` to change the hit (damage, stun, knockback).
## packet.is_weak_point is already set.
func on_hit(_weapon: Weapon, _target: Node, _packet: DamagePacket) -> void:
	pass


## After a hit from this weapon destroyed `target`.
func on_kill(_weapon: Weapon, _target: Node, _packet: DamagePacket) -> void:
	pass
