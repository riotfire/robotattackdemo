@tool
extends BTAction
## Preserve each robot's movement hook (including the Rung Runner's catwalk travel).
## _goal_position reads squad formation and projects perched targets onto reachable ground.
func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if robot.ai_state != Robot.AiState.SEEK:
		return FAILURE
	robot.desired_velocity = robot._seek_velocity(delta)
	if robot.desired_velocity == Vector3.ZERO and blackboard.get_var(&"target_perched", false):
		robot._face(robot._target_position())
	return RUNNING
