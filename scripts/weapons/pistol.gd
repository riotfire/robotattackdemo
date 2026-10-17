class_name Pistol
extends Weapon
## The Rivet Pistol (GDD 6.2): hitscan, 12 damage, 4 shots/s semi-auto, 10-round magazine, 1.1 s reload,
## 40 m range. Unlimited reserve ammo (GDD 6.1). Eyes are weak points (x2).
## Bought for 20 Al at the pegboard; Damage, Fire Rate and Handling apply through StatService.

@export var damage: float = 12.0
@export var shots_per_second: float = 4.0
@export var magazine_size: int = 10
@export var reload_time: float = 1.1
@export var max_range: float = 40.0

var ammo: int = 0
var _cooldown: float = 0.0
var _reload_left: float = 0.0

@onready var _muzzle: Marker3D = $Muzzle


func _ready() -> void:
	ammo = magazine_now()


func magazine_now() -> int:
	return roundi(StatService.get_stat(&"pistol.magazine", magazine_size))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			ammo = magazine_now()


func trigger(just_pressed: bool, _held: bool) -> void:
	if just_pressed:
		fire()


func fire() -> void:
	if _reload_left > 0.0 or _cooldown > 0.0 or farmer == null:
		return
	if ammo <= 0:
		reload()
		return
	ammo -= 1
	_cooldown = 1.0 / StatService.get_stat(&"pistol.fire_rate", shots_per_second)

	var from := _muzzle.global_position
	var aim_point := farmer.get_aim_point(max_range)
	var dir := (aim_point - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * max_range, SHOT_MASK, [farmer.get_rid()])
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := from + dir * max_range
	if not hit.is_empty():
		end = hit["position"]
		var hurtbox := hit["collider"] as Hurtbox
		if hurtbox != null:
			var shot_damage := StatService.get_stat(&"pistol.damage", damage) * farmer.damage_multiplier()
			hurtbox.hit(DamagePacket.create(shot_damage, farmer, end))
			Fx.puff(self, end, Color(1.0, 0.95, 0.6) if not hurtbox.is_weak_point else Color(1.0, 0.3, 0.2), 0.15, 0.15)
		else:
			Fx.puff(self, end, Color(0.8, 0.75, 0.65), 0.1, 0.2)
	Fx.tracer(self, from, end)
	if ammo == 0:
		reload()


func reload() -> void:
	if _reload_left <= 0.0 and ammo < magazine_now():
		_reload_left = StatService.get_stat(&"pistol.reload_time", reload_time)


func is_reloading() -> bool:
	return _reload_left > 0.0


func ammo_text() -> String:
	return "RELOADING" if is_reloading() else "%d / %d" % [ammo, magazine_now()]
