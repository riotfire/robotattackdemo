@tool
extends BTAction
## Recovery uses the robot's hook, including authored Foreman punish windows.
func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if robot.ai_state != Robot.AiState.RECOVER:
		return FAILURE
	robot._attack_timer -= delta
	if robot._attack_timer <= 0.0:
		robot.ai_state = Robot.AiState.SEEK
	return RUNNING
