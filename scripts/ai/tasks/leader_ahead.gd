@tool
extends BTCondition
## Succeeds for a squad follower whose leader is still more than `distance` from the follower's target:
## the squad is on the march, so keep formation (BTFollowLeader) rather than make for the target.
## The leader comes from the squad blackboard (RobotSquad), the member blackboard's parent scope.

@export var leader_var: StringName = &"squad_leader"
@export var distance: float = 8.0


func _generate_name() -> String:
	return "LeaderAhead %s > %s m from target" % [LimboUtility.decorate_var(leader_var), distance]


func _tick(_delta: float) -> Status:
	var robot := agent as Robot
	if robot.squad_index == 0:
		return FAILURE
	var leader := _leader()
	if leader == null or leader == robot:
		return FAILURE
	return SUCCESS if leader.global_position.distance_to(robot.target_position()) > distance else FAILURE


func _leader() -> Robot:
	var value: Variant = blackboard.get_var(leader_var, null, false)
	return value as Robot if is_instance_valid(value) else null
