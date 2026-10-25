class_name RobotSquad
extends RefCounted
## A trio's shared blackboard (GDD 9.6): members walk in a loose triangle behind the leader and attack in
## a 3-beat rhythm. The leader rolls the target, role and any distraction for all three (one shared
## RobotTargeting). If the leader falls, the next living member leads.
##
## Heist crew: in a thief trio only the leader carries a sack; the other two escort it and fight anyone who
## chases it. If the thief is destroyed the escorts become an ordinary pair; if it escapes, they slip away too.

var members: Array[Robot] = []
var targeting: RobotTargeting = null
## The sack carrier of a heist crew, or null.
var heist_leader: Robot = null
## The heist leader got away into the corn with its sack.
var heist_escaped: bool = false


## Adds a member and returns its slot index (0 = leader).
func join(robot: Robot) -> int:
	members.append(robot)
	return members.size() - 1


func leader() -> Robot:
	for robot in members:
		if is_instance_valid(robot) and robot.ai_state != Robot.AiState.DEAD:
			return robot
	return null


## True while the crew's thief is alive and still on its heist.
func heist_active() -> bool:
	return heist_leader != null and is_instance_valid(heist_leader) and heist_leader.ai_state != Robot.AiState.DEAD


## Formation slot in the leader's frame (front = -Z): a loose triangle behind it.
static func formation_offset(index: int, scale: float) -> Vector3:
	match index:
		1:
			return Vector3(-1.4, 0.0, 1.4) * scale
		2:
			return Vector3(1.4, 0.0, 1.4) * scale
	return Vector3.ZERO
