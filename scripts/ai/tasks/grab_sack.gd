@tool
extends BTAction
## A thief at the chute (GDD 3.3): works a grain sack loose for `duration` seconds, facing the chute, then
## takes up to Robot.SACK_SIZE bushels (Robot.grab_sack).

@export var duration: float = 0.6

var _timer: float = 0.0
var _started: bool = false


func _generate_name() -> String:
	return "GrabSack %s s" % duration


func _enter() -> void:
	_started = false


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if not _started:
		_started = true
		robot.ai_state = Robot.AiState.STEALING
		_timer = duration
		return RUNNING
	robot.face(robot.target_position())
	_timer -= delta
	if _timer > 0.0:
		return RUNNING
	robot.grab_sack()
	return SUCCESS
