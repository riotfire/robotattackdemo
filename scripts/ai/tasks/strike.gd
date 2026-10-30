@tool
extends BTAction
## The hit (Robot.strike): lands if the target is still within reach plus `grace`, since it may have
## stepped back during the windup. Always succeeds; a miss still costs the robot its recovery.

@export var grace: float = 0.5


func _generate_name() -> String:
	return "Strike (reach +%s m)" % grace


func _tick(_delta: float) -> Status:
	var robot := agent as Robot
	if robot.target_in_reach(grace):
		robot.strike()
	return SUCCESS
