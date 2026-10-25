class_name WeaponShot
extends RefCounted
## One shot or swing as it leaves the weapon, after on_fire mods have had their say.

var weapon: Weapon = null
var origin: Vector3 = Vector3.ZERO
## Normalized.
var direction: Vector3 = Vector3.FORWARD
var damage: float = 0.0
var max_range: float = 0.0
## How many more robots a gun's shot passes through after the first one it hits.
var pierce_left: int = 0
## Shove along `direction` given to each robot the shot hits (m/s).
var knockback: float = 0.0
## Robots this shot has already hit, so a piercing round lands once per robot, not once per hurtbox.
var hit_targets: Array[Node] = []
