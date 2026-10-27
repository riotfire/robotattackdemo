class_name SpringTrap
extends Defense
## Spring Trap: a robot that steps on it is thrown up and out along the site's launch direction (DefenseSite).
## On the ground it delays a robot and knocks it back toward its lane; on the catwalk or a roof the throw
## ends in a fall, and the landing hurts (Robot.launch: capped impact damage, a short recovery, kill credit
## to whoever placed the trap). Medium robots fly less far; large robots and Foremen are never thrown, they
## stomp it instead. It needs reset_time before it fires again.

var _reset_left: float = 0.0
var _plate: Node3D
var _coil: Node3D


func _physics_process(delta: float) -> void:
	_reset_left = maxf(0.0, _reset_left - delta)
	if _plate != null:
		_plate.position.y = lerpf(0.42, 0.18, clampf(_reset_left / maxf(0.01, reset_time()), 0.0, 1.0))
	if not active or _reset_left > 0.0:
		return
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		var robot := node as Robot
		if robot == null or not robot.can_be_launched_now() or not _on_plate(robot):
			continue
		fire(robot)
		return


## Throws `robot` (or takes a large robot's stomp). Returns true if it flew.
func fire(robot: Robot) -> bool:
	_reset_left = reset_time()
	if not robot.launchable():
		take_damage(DamagePacket.create(definition.stomp_damage, robot, global_position))
		return false
	var power := StatService.get_stat(&"defense.spring_power", 1.0)
	if robot.archetype.robot_type == RobotArchetype.RobotType.GRUNT:
		power *= definition.medium_launch_share
	var impulse := site.launch_direction * definition.launch_out_speed * power + Vector3.UP * definition.launch_up_speed * power
	var flew := robot.launch(impulse, placed_by, self)
	if flew:
		AudioDirector.play_cue(&"spring_boing")
		Fx.puff(self, global_position + Vector3.UP * 0.4, Color(0.95, 0.85, 0.4), 0.4, 0.25)
		if _coil != null:
			var tween := _coil.create_tween()
			tween.tween_property(_coil, ^"scale:y", 1.8, 0.06)
			tween.tween_property(_coil, ^"scale:y", 1.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return flew


func reset_time() -> float:
	return definition.reset_time * maxf(0.2, StatService.get_stat(&"defense.spring_reset", 1.0))


func is_ready() -> bool:
	return active and _reset_left <= 0.0


func label_height() -> float:
	return 1.2


func _on_plate(robot: Robot) -> bool:
	var offset := robot.global_position - global_position
	return absf(offset.y) <= 1.5 and Vector2(offset.x, offset.z).length() <= definition.trigger_radius + robot.archetype.body_radius * 0.5


func _build_look() -> void:
	var look := Node3D.new()
	look.name = "Look"
	add_child(look)
	var base := CylinderMesh.new()
	base.top_radius = 0.55
	base.bottom_radius = 0.6
	base.height = 0.12
	Clay.part(look, base, Color(0.45, 0.46, 0.5), Transform3D(Basis(), Vector3.UP * 0.06))
	_coil = Node3D.new()
	_coil.name = "Coil"
	look.add_child(_coil)
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.24
	hoop.outer_radius = 0.32
	hoop.rings = 16
	hoop.ring_segments = 6
	for i in 4:
		Clay.part(_coil, hoop, Color(0.85, 0.7, 0.25), Transform3D(Basis().scaled(Vector3(1.0, 0.6, 1.0)), Vector3.UP * (0.12 + i * 0.07)))
	_plate = Node3D.new()
	_plate.name = "Plate"
	look.add_child(_plate)
	var plate := CylinderMesh.new()
	plate.top_radius = 0.5
	plate.bottom_radius = 0.5
	plate.height = 0.08
	Clay.part(_plate, plate, Color(0.9, 0.3, 0.2), Transform3D.IDENTITY)
	# A yellow arrow on the plate shows which way robots fly.
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.36, 0.42, 0.04)
	var toward := site.launch_direction if site != null else Vector3.FORWARD
	var yaw := atan2(toward.x, toward.z)
	Clay.part(_plate, arrow, Color(1.0, 0.85, 0.2), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), Vector3.UP * 0.05), 0.6)
	_plate.position.y = 0.42
