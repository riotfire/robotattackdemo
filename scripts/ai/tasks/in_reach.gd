@tool
extends BTCondition
## Succeeds when the robot's target is within its attack range plus `extra`, or, for a thief, when the
## chute is within grabbing distance (Robot.target_in_reach).

@export var extra: float = 0.0


func _generate_name() -> String:
	return "InReach" if is_zero_approx(extra) else "InReach +%s m" % extra


func _tick(_delta: float) -> Status:
	return SUCCESS if (agent as Robot).target_in_reach(extra) else FAILURE
