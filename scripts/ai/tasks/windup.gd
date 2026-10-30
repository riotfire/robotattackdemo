@tool
extends BTAction
## A committed melee telegraph. Target changes still use the current target, as before the migration.
func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if robot.ai_state != Robot.AiState.WINDUP:
		return FAILURE
	robot._face(robot._target_position())
	robot._attack_timer -= delta
	if robot._attack_timer <= 0.0:
		if robot._target_in_range(0.5):
			robot._deal_hit()
		robot.ai_state = Robot.AiState.RECOVER
		robot._attack_timer = robot.recover_time()
		robot._on_recover_started()
	return RUNNING
