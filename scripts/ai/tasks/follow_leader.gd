@tool
extends BTAction
## Keeps a follower's slot in the squad's loose triangle behind the leader (GDD 9.6, RobotSquad).
## Never finishes; BTLeaderAhead guards it. Fails if the squad has no leader.

@export var leader_var: StringName = &"squad_leader"


func _generate_name() -> String:
	return "FollowLeader %s" % LimboUtility.decorate_var(leader_var)


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	var value: Variant = blackboard.get_var(leader_var, null, false)
	if not is_instance_valid(value):
		return FAILURE
	var leader := value as Robot
	robot.ai_state = Robot.AiState.SEEK
	var slot := RobotSquad.formation_offset(robot.squad_index, robot.type_scale())
	robot.walk_to(delta, leader.global_position + Basis(Vector3.UP, leader.model.rotation.y) * slot)
	return RUNNING
