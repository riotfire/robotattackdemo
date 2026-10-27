class_name ScarecrowDecoy
extends Defense
## Scarecrow Decoy: pulls a few nearby eligible robots off the silo for a while; they walk to it and bash it
## instead. On the ground it lures ground melee robots within lure_radius_ground. On the catwalk it lures
## Rung Runners (the only robots with a way up) to its spot from anywhere on their route, so it can lead them
## across a spring. On a roof it makes nearby Roof Lobbers choose that roof (VerticalRobot._choose_roof).
## It never distracts thieves, heist crews, Foremen or a robot already after the farmer, holds at most
## max_lured robots at once, and lets each go after lure_time.

const SCAN_PERIOD: float = 0.5

var _scan_left: float = 0.0
var _lured: Array[Robot] = []


func _physics_process(delta: float) -> void:
	if not active:
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_PERIOD
	_lured = _lured.filter(func(robot: Robot) -> bool:
			return is_instance_valid(robot) and robot.target_defense == self)
	if site != null and site.kind == &"roof":
		return
	var room := max_lured() - _lured.size()
	if room <= 0:
		return
	var radius := lure_radius()
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		var robot := node as Robot
		if robot == null or robot in _lured or not robot.can_be_lured_by(self):
			continue
		if site.kind == &"ground" and robot.global_position.distance_to(global_position) > radius:
			continue
		if robot.lure_to(self, definition.lure_time):
			_lured.append(robot)
			room -= 1
			if room <= 0:
				return


## Takes on a robot that found its own way to it (a Rung Runner on the catwalk), if there's room.
func adopt(robot: Robot) -> bool:
	_lured = _lured.filter(func(other: Robot) -> bool: return is_instance_valid(other) and other.target_defense == self)
	if not active or _lured.size() >= max_lured():
		return false
	_lured.append(robot)
	return true


func lure_radius() -> float:
	var base := definition.lure_radius_elevated if is_elevated() else definition.lure_radius_ground
	return base * StatService.get_stat(&"defense.decoy_radius", 1.0)


func max_lured() -> int:
	return maxi(1, roundi(StatService.get_stat(&"defense.decoy_lure", float(definition.max_lured))))


func lured_count() -> int:
	return _lured.size()


func label_height() -> float:
	return 2.4


func _build_look() -> void:
	var look := Node3D.new()
	look.name = "Look"
	add_child(look)
	var straw := Color(0.9, 0.78, 0.4)
	var pole := BoxMesh.new()
	pole.size = Vector3(0.1, 1.9, 0.1)
	Clay.part(look, pole, Color(0.55, 0.4, 0.25), Transform3D(Basis(), Vector3.UP * 0.95))
	var arms := BoxMesh.new()
	arms.size = Vector3(1.3, 0.09, 0.09)
	Clay.part(look, arms, Color(0.55, 0.4, 0.25), Transform3D(Basis(), Vector3.UP * 1.45))
	var shirt := BoxMesh.new()
	shirt.size = Vector3(0.62, 0.62, 0.28)
	Clay.part(look, shirt, Color(0.75, 0.28, 0.22), Transform3D(Basis(), Vector3.UP * 1.25))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	Clay.part(look, head, Color(0.86, 0.74, 0.52), Transform3D(Basis(), Vector3.UP * 1.82))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.36
	brim.bottom_radius = 0.36
	brim.height = 0.05
	Clay.part(look, brim, straw, Transform3D(Basis(), Vector3.UP * 1.98))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.16
	crown.bottom_radius = 0.2
	crown.height = 0.18
	Clay.part(look, crown, straw, Transform3D(Basis(), Vector3.UP * 2.08))
	# Two tin pie plates on the arms catch the light: the lure.
	var tin := CylinderMesh.new()
	tin.top_radius = 0.14
	tin.bottom_radius = 0.14
	tin.height = 0.03
	for side in [-1.0, 1.0]:
		Clay.part(look, tin, Color(0.85, 0.87, 0.9), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.62 * side, 1.38, 0.08)), 0.8)
