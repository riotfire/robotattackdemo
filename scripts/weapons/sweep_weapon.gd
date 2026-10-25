class_name SweepWeapon
extends Weapon
## Heavy maul or spinning scythe. A visible wind-up makes the high-damage sweep interruptible;
## the scythe covers the full circle while the maul only covers the front arc.

@export_range(1.0, 360.0) var arc_degrees: float = 90.0
@export var windup: float = 0.32
@export var knockback: float = 12.0

var _cooldown: float = 0.0
var _windup_left: float = 0.0
var _swing_forward: Vector3 = Vector3.FORWARD
var _swing_tween: Tween

@onready var _pivot: Node3D = $Pivot


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0 and farmer != null and farmer.weapons.current == self and farmer.can_use_weapons():
			_land_swing()


func attack() -> bool:
	if _cooldown > 0.0 or _windup_left > 0.0 or farmer == null:
		return false
	_cooldown = attack_interval()
	_swing_forward = farmer.aim_direction_flat(data.max_range + 4.0)
	_windup_left = windup
	if _swing_tween != null:
		_swing_tween.kill()
	_pivot.rotation = Vector3(0.0, 0.0, 0.0)
	_swing_tween = create_tween()
	if arc_degrees >= 359.0:
		_swing_tween.tween_property(_pivot, ^"rotation:y", TAU, maxf(windup + 0.3, attack_interval() * 0.65))
		_swing_tween.tween_property(_pivot, ^"rotation:y", 0.0, 0.12)
	else:
		_pivot.rotation.x = deg_to_rad(65.0)
		_swing_tween.tween_property(_pivot, ^"rotation:x", deg_to_rad(90.0), maxf(0.0, windup - 0.1))
		_swing_tween.tween_property(_pivot, ^"rotation:x", deg_to_rad(-100.0), 0.1)
		_swing_tween.tween_property(_pivot, ^"rotation:x", 0.0, 0.35)
	return true


func _land_swing() -> void:
	var center := farmer.global_position + Vector3.UP * 0.9
	var sphere := SphereShape3D.new()
	sphere.radius = data.max_range
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = ROBOT_HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var targets: Dictionary[Node, Hurtbox] = {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 128):
		var box := result["collider"] as Hurtbox
		if box == null or box.receiver() == null:
			continue
		var toward := box.global_position - center
		toward.y = 0.0
		if arc_degrees < 359.0 and toward.length() > 0.01 \
				and _swing_forward.dot(toward.normalized()) < cos(deg_to_rad(arc_degrees * 0.5)):
			continue
		var target := box.receiver()
		if not targets.has(target) or (targets[target].is_weak_point and not box.is_weak_point):
			targets[target] = box
	var shot := begin_shot(center, _swing_forward)
	for target: Node in targets:
		var box := targets[target]
		var packet := DamagePacket.create(shot.damage, farmer, box.global_position)
		var outward := box.global_position - center
		outward.y = 0.0
		packet.knockback = outward.normalized() * knockback + Vector3.UP * knockback * 0.3
		deliver_hit(box, packet)
		Fx.puff(self, box.global_position, Color(1.0, 0.8, 0.35), 0.3)
