@tool
extends BTAction
## Both sack carriers and escorts whose thief escaped use their existing escape route.
func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if robot.ai_state != Robot.AiState.FLEEING:
		return FAILURE
	var flat := robot.global_position - robot._silo_center()
	flat.y = 0.0
	if flat.length() >= Robot.ESCAPE_RADIUS:
		robot._escape()
	else:
		robot.desired_velocity = robot._navigate(delta, robot._escape_point)
	return RUNNING
