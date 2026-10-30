@tool
extends BTAction
## Choose theft or a melee windup once in reach; squad members delay only their first hit.
func _tick(_delta: float) -> Status:
	var robot := agent as Robot
	if robot.ai_state != Robot.AiState.SEEK or not robot._target_in_range():
		return FAILURE
	if robot.target_kind == Robot.TargetKind.CHUTE:
		robot.ai_state = Robot.AiState.STEALING
		robot._steal_timer = 0.6
	else:
		robot.ai_state = Robot.AiState.WINDUP
		robot._attack_timer = robot.windup_time()
		if robot._first_attack and robot.squad != null:
			var beats: int = blackboard.get_var(&"squad_beats", RobotSquad.BEATS)
			robot._attack_timer += robot.squad_index * robot.archetype.attack_interval / beats
		robot._first_attack = false
		robot._on_windup_started()
	return RUNNING
