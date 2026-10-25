class_name AreaAttack
extends RefCounted
## Shared radial robot hit for grenades and the jetpack ground pound. Each robot takes one body hit,
## even when several hurtboxes overlap the blast; weak points remain rewards for aimed shots.


static func hit_robots(context: Node3D, center: Vector3, radius: float, damage: float, source: Node,
		push: float = 0.0, weapon: Weapon = null) -> int:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = Weapon.ROBOT_HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var targets: Dictionary[Node, Hurtbox] = {}
	for result in context.get_world_3d().direct_space_state.intersect_shape(query, 128):
		var box := result["collider"] as Hurtbox
		if box == null or box.receiver() == null:
			continue
		var target := box.receiver()
		if not targets.has(target) or (targets[target].is_weak_point and not box.is_weak_point):
			targets[target] = box
	for target: Node in targets:
		var box := targets[target]
		var distance := (box.global_position - center).length()
		var packet := DamagePacket.create(damage * maxf(0.5, 1.0 - distance / maxf(radius, 0.01)), source,
				box.global_position)
		if push > 0.0:
			var outward := box.global_position - center
			outward.y = 0.0
			packet.knockback = outward.normalized() * push + Vector3.UP * push * 0.35
		if weapon != null and is_instance_valid(weapon):
			weapon.deliver_hit(box, packet)
		else:
			box.hit(packet)
	return targets.size()
