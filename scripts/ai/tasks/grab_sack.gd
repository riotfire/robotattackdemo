@tool
extends BTAction
## A thief already at the chute finishes its sack grab before fleeing.
func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if robot.ai_state != Robot.AiState.STEALING:
		return FAILURE
	robot._face(robot._target_position())
	robot._steal_timer -= delta
	if robot._steal_timer <= 0.0:
		robot._grab_sack()
	return RUNNING
