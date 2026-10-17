class_name Weapon
extends Node3D
## Base for everything in the farmer's WeaponHolder (GDD 6, 18.4). The farmer forwards trigger input;
## weapons aim along the farmer's camera-center ray (GDD 5.3).

## Collision layers a shot can hit: World, RobotHurtbox, Silo (GDD 18.6).
const SHOT_MASK: int = 1 | (1 << 4) | (1 << 5)
const ROBOT_HURTBOX_MASK: int = 1 << 4

@export var display_name: String = "Weapon"

var farmer: Farmer


func setup(owner_farmer: Farmer) -> void:
	farmer = owner_farmer


## Called every physics step while this weapon is equipped and usable.
func trigger(_just_pressed: bool, _held: bool) -> void:
	pass


func reload() -> void:
	pass


func ammo_text() -> String:
	return ""


func set_equipped(equipped: bool) -> void:
	visible = equipped
