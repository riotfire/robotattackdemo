class_name Pistol
extends Weapon
## The Rivet Pistol (GDD 6.2): hitscan, 12 damage, 4 shots/s semi-auto, 10-round magazine, 1.1 s reload,
## 40 m range (data/weapons/pistol.tres). Unlimited reserve ammo (GDD 6.1). Eyes are weak points (x2).
## Bought for 20 Al at the pegboard; Damage, Fire Rate and Handling apply through StatService.

## The model's kick when fired: how far it jumps back (m), how far the muzzle rises, and the seconds to settle.
@export var recoil_distance: float = 0.05
@export var recoil_degrees: float = 9.0
@export var recoil_settle: float = 0.14

var ammo: int = 0
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _recoil_tween: Tween
var _body_rest: Transform3D

@onready var _muzzle: Marker3D = $Muzzle
@onready var _body: Node3D = $Body


func _ready() -> void:
	ammo = magazine_now()
	_body_rest = _body.transform


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
	kick()
	var from := _muzzle.global_position
	resolve_shot(begin_shot(from, farmer.get_aim_point(data.max_range) - from))
	if ammo == 0:
		reload()
	return true


## Jumps the model back and muzzle-up around the grip, then eases it home.
func kick() -> void:
	if _recoil_tween != null:
		_recoil_tween.kill()
	var kicked := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(recoil_degrees)), Vector3.BACK * recoil_distance) * _body_rest
	_body.transform = kicked
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(_body, ^"transform", _body_rest, recoil_settle) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func reload() -> void:
	if _reload_left <= 0.0 and ammo < magazine_now():
		_reload_left = stat(data.reload_stat, data.reload_time)


func is_reloading() -> bool:
	return _reload_left > 0.0


func ammo_text() -> String:
	return "RELOADING" if is_reloading() else "%d / %d" % [ammo, magazine_now()]
