class_name WeaponData
extends Resource
## One weapon's base stats (GDD 6.2, 18.4); one .tres per weapon in data/weapons/. Pegboard tracks apply on
## top through StatService: each *_stat field names the stat key its track modifies (empty = fixed).

enum TriggerMode {
	## Fires once per press (the Rivet Pistol).
	SEMI,
	## Keeps firing while held, at fire_rate (the wrench, and later the Machine Gun).
	AUTO,
}

@export var id: StringName
@export var display_name: String = "Weapon"
## Number key and weapon-wheel position, 1-6 (GDD 5.2). Slot 1 is at the top of the wheel, then clockwise.
@export_range(1, 6) var slot: int = 1
## StatService flag that puts it in the farmer's hands (bought at the pegboard); empty = always carried.
@export var unlock_flag: StringName
## Usable while riding a zipline without Zipline Grip 2 (GDD 13.4).
@export var usable_on_zipline: bool = false
@export var trigger_mode: TriggerMode = TriggerMode.SEMI

@export_group("Damage and rate")
@export var damage: float = 10.0
@export var damage_stat: StringName
## Shots (or swings) per second.
@export var fire_rate: float = 1.0
@export var fire_rate_stat: StringName
@export var max_range: float = 40.0

@export_group("Magazine")
## 0 = no magazine (melee).
@export var magazine_size: int = 0
@export var magazine_stat: StringName
@export var reload_time: float = 0.0
@export var reload_stat: StringName

@export_group("Projectile")
## 0 = hitscan along the aim ray. Above 0, shots are pooled projectiles flying at this speed (m/s).
@export var projectile_speed: float = 0.0
## Downward pull on projectiles, m/s^2 (lobbed eggs).
@export var projectile_gravity: float = 0.0
@export var projectile_radius: float = 0.06
@export var projectile_color: Color = Color(1.0, 0.85, 0.45)

@export_group("Mods (GDD 6.3)")
@export var mod_slots: int = 1
## Flag that adds the Gold Mod Slot (Damage 8 + Fire Rate 8, M2-C5).
@export var gold_mod_slot_flag: StringName


func uses_projectiles() -> bool:
	return projectile_speed > 0.0
