@tool
extends BTAction
## A thief with its sack runs out along the nearest corn lane and is gone once it's Robot.ESCAPE_RADIUS
## from the silo (GDD 3.3). It only succeeds as the robot leaves the game.

var _escape_point: Vector3 = Vector3.ZERO
var _started: bool = false


func _generate_name() -> String:
	return "FleeToCorn"


func _enter() -> void:
	_started = false


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	robot.ai_state = Robot.AiState.FLEEING
	if not _started:
		# The tick the sack comes loose: pick the lane, run from the next tick.
		_started = true
		_escape_point = robot.escape_point()
		robot.repath_now()
		return RUNNING
	if robot.has_escaped():
		robot.escape()
		return SUCCESS
	robot.walk_to(delta, _escape_point)
	return RUNNING
