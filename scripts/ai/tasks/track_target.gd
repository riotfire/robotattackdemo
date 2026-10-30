@tool
extends BTAction
## Publishes perch information; RobotTargeting remains the sole owner of target decisions.
func _tick(delta: float) -> Status:
	(agent as Robot).update_ai_blackboard(delta)
	return SUCCESS
