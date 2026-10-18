class_name WeaponShot
extends RefCounted
## One shot or swing as it leaves the weapon, after on_fire mods have had their say.

var weapon: Weapon = null
var origin: Vector3 = Vector3.ZERO
## Normalized.
var direction: Vector3 = Vector3.FORWARD
var damage: float = 0.0
var max_range: float = 0.0
