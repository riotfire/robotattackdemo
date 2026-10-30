class_name RobotSquad
extends RefCounted
## A Grunt squad (GDD 9.6): members walk in a loose triangle behind the leader and attack in a 3-beat
## rhythm, clank-clank-CLANK. If the leader falls, the next living member leads.
##
## `blackboard` is the squad's shared LimboAI blackboard. Each member's behavior-tree blackboard uses it as
## its parent scope (Robot._bind_blackboard), so the tasks read squad vars as if they were the member's own:
##   squad_leader  Robot  the first living member; followers keep formation on it (BTFollowLeader)
##   squad_beats   int    beats per bar; member i's first windup is held i beats (BTWindup)

const BEATS: int = 3

var members: Array[Robot] = []
var blackboard: Blackboard = Blackboard.new()


func _init() -> void:
	blackboard.set_var(&"squad_leader", null)
	blackboard.set_var(&"squad_beats", BEATS)


## Adds a member and returns its slot index (0 = leader).
func join(robot: Robot) -> int:
	members.append(robot)
	robot.destroyed.connect(_on_member_destroyed)
	_update_leader()
	return members.size() - 1


func leader() -> Robot:
	for robot in members:
		if is_instance_valid(robot) and robot.ai_state != Robot.AiState.DEAD:
			return robot
	return null


func _on_member_destroyed(_robot: Robot, _killer: Node) -> void:
	_update_leader()


func _update_leader() -> void:
	blackboard.set_var(&"squad_leader", leader())


## Formation slot in the leader's frame (front = -Z): a loose triangle behind it.
static func formation_offset(index: int, scale: float) -> Vector3:
	match index:
		1:
			return Vector3(-1.4, 0.0, 1.4) * scale
		2:
			return Vector3(1.4, 0.0, 1.4) * scale
	return Vector3.ZERO
