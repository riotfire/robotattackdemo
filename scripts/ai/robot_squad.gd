class_name RobotSquad
extends RefCounted
## A Grunt squad's shared blackboard (GDD 9.6): members walk in a loose triangle behind the leader and
## attack in a 3-beat rhythm. If the leader falls, the next living member leads.

var members: Array[Robot] = []


## Adds a member and returns its slot index (0 = leader).
func join(robot: Robot) -> int:
	members.append(robot)
	return members.size() - 1


func leader() -> Robot:
	for robot in members:
		if is_instance_valid(robot) and robot.ai_state != Robot.AiState.DEAD:
			return robot
	return null


## Formation slot in the leader's frame (front = -Z): a loose triangle behind it.
static func formation_offset(index: int, scale: float) -> Vector3:
	match index:
		1:
			return Vector3(-1.4, 0.0, 1.4) * scale
		2:
			return Vector3(1.4, 0.0, 1.4) * scale
	return Vector3.ZERO
