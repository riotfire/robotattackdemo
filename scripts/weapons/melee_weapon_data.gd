class_name MeleeWeaponData
extends WeaponData
## Swing tuning for melee weapons (the wrench, GDD 6.2). max_range is the reach.

## Radius of the sphere a swing sweeps at the end of its reach.
@export var hit_radius: float = 0.9
## Every 3rd hit in a combo is a finisher: this damage multiplier plus knockback.
@export var combo_multiplier: float = 1.5
@export var combo_knockback: float = 9.0
## A pause longer than this restarts the combo count.
@export var combo_reset_time: float = 1.2
