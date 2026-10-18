class_name Wrench
extends Weapon
## Grandpa's big red wrench (GDD 6.2): melee weapon and repair tool. 25 damage, every 3rd hit in a combo
## does x1.5 with knockback, 1.6 swings/s, 2.2 m reach (data/weapons/wrench.tres, a MeleeWeaponData).

var _cooldown: float = 0.0
var _combo: int = 0
var _since_last_swing: float = 99.0
var _swing_tween: Tween

@onready var _pivot: Node3D = $Pivot


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_since_last_swing += delta


func attack() -> bool:
	return swing()


## Swings if off cooldown. Returns true if a swing happened.
func swing() -> bool:
	if _cooldown > 0.0 or farmer == null:
		return false
	var melee := data as MeleeWeaponData
	_cooldown = attack_interval()
	if _since_last_swing > melee.combo_reset_time:
		_combo = 0
	_since_last_swing = 0.0
	_combo += 1
	var finisher := _combo >= 3
	if finisher:
		_combo = 0
	_animate(finisher)

	var forward := farmer.aim_direction_flat(melee.max_range + 6.0)
	var center := farmer.global_position + Vector3.UP * 0.9 + forward * (melee.max_range - melee.hit_radius)
	var swing_shot := begin_shot(center, forward)
	var shape := SphereShape3D.new()
	shape.radius = melee.hit_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), swing_shot.origin)
	params.collision_mask = ROBOT_HURTBOX_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	# One hit per robot. The swing sphere covers a whole Nibbler, so a weak point inside it is luck,
	# not aim: melee lands on a regular hurtbox when there is one and leaves eye shots to the guns.
	var targets: Dictionary[Node, Hurtbox] = {}
	for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var hurtbox := result["collider"] as Hurtbox
		if hurtbox == null:
			continue
		var current: Hurtbox = targets.get(hurtbox.receiver())
		if current == null or (current.is_weak_point and not hurtbox.is_weak_point):
			targets[hurtbox.receiver()] = hurtbox
	for hurtbox: Hurtbox in targets.values():
		var packet := DamagePacket.create(swing_shot.damage * (melee.combo_multiplier if finisher else 1.0), farmer, hurtbox.global_position)
		if finisher:
			packet.knockback = swing_shot.direction * melee.combo_knockback + Vector3.UP * 3.0
		deliver_hit(hurtbox, packet)
		Fx.puff(self, hurtbox.global_position, Color(1.0, 0.85, 0.4), 0.2)
	return true


func _animate(finisher: bool) -> void:
	visible = true
	if _swing_tween != null:
		_swing_tween.kill()
	_pivot.rotation = Vector3(deg_to_rad(70.0), 0.0, 0.0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_pivot, ^"rotation:x", deg_to_rad(-100.0 if finisher else -70.0), 0.12)
	_swing_tween.tween_property(_pivot, ^"rotation:x", 0.0, 0.2)
	_swing_tween.tween_callback(func() -> void: visible = farmer != null and farmer.weapons.current == self)
