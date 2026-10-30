@tool
extends BTAction
## Recovery after a hit: waits out the rest of the archetype's attack_interval (the windup took its
## share), then the robot is seeking again. Starts counting on the tick after it begins, like BTWindup.

var _timer: float = 0.0
var _started: bool = false


func _generate_name() -> String:
	return "Recover"


func _enter() -> void:
	_started = false


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if not _started:
		_started = true
		robot.ai_state = Robot.AiState.RECOVER
		_timer = maxf(0.0, robot.archetype.attack_interval - robot.archetype.attack_windup)
		return RUNNING
	_timer -= delta
	if _timer > 0.0:
		return RUNNING
	robot.ai_state = Robot.AiState.SEEK
	return SUCCESS
