class_name HeavyRobot
extends Robot
## A Heavy melee robot, the Thumper (GDD 9.3): rears up, then slams. The slam hits its target and sends
## a shockwave ring along the ground that the farmer can jump over. Weak point: the back vent (x2).
## Knockback doesn't move it.


func _on_windup_started() -> void:
	Fx.puff(self, global_position + Vector3.UP * 0.2, Color(0.8, 0.75, 0.65), 0.6, 0.3)


func _deal_hit() -> void:
	super._deal_hit()
	if archetype.shockwave_damage > 0.0:
		var ground := global_position
		var wave_ring := Shockwave.new()
		wave_ring.damage = archetype.shockwave_damage * damage_multiplier
		wave_ring.max_radius = archetype.shockwave_radius
		wave_ring.duration = archetype.shockwave_time
		wave_ring.source = self
		get_tree().current_scene.add_child(wave_ring)
		wave_ring.global_position = Vector3(ground.x, ground.y + 0.05, ground.z)
		FarmerCamera.shake_at(ground, 0.3, 4.0, 25.0)


func _windup_pose_scale() -> Vector3:
	return Vector3(0.92, 1.15, 0.92)
