class_name Pistol
extends Weapon
## The Rivet Pistol (GDD 6.2): hitscan, 12 damage, 4 shots/s semi-auto, 10-round magazine, 1.1 s reload,
## 40 m range (data/weapons/pistol.tres). Unlimited reserve ammo (GDD 6.1). Eyes are weak points (x2).
## Bought for 20 Al at the pegboard; Damage, Fire Rate and Handling apply through StatService.

var ammo: int = 0
var _cooldown: float = 0.0
var _reload_left: float = 0.0

@onready var _muzzle: Marker3D = $Muzzle


func _ready() -> void:
	ammo = magazine_now()


func magazine_now() -> int:
	return roundi(stat(data.magazine_stat, data.magazine_size))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			ammo = magazine_now()


func attack() -> bool:
	return fire()


## Fires one rivet if loaded and off cooldown. Returns true if it fired.
func fire() -> bool:
	if _reload_left > 0.0 or _cooldown > 0.0 or farmer == null:
		return false
	if ammo <= 0:
		reload()
		return false
	ammo -= 1
	_cooldown = attack_interval()
	var from := _muzzle.global_position
	resolve_shot(begin_shot(from, farmer.get_aim_point(data.max_range) - from))
	if ammo == 0:
		reload()
	return true


func reload() -> void:
	if _reload_left <= 0.0 and ammo < magazine_now():
		_reload_left = stat(data.reload_stat, data.reload_time)


func is_reloading() -> bool:
	return _reload_left > 0.0


func ammo_text() -> String:
	return "RELOADING" if is_reloading() else "%d / %d" % [ammo, magazine_now()]
