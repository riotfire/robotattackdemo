@tool
extends BTAction
## Walks the navmesh toward the robot's target (Robot.target_position). Never finishes: higher-priority
## branches take over once the target is in reach. A perched farmer (`perched_var`, from BTTrackTarget)
## is waited for at the foot of the perch (`stand_var`), looking up at them.

@export var perched_var: StringName = &"target_perched"
@export var stand_var: StringName = &"perch_stand"


func _generate_name() -> String:
	return "Approach target (perch: %s)" % LimboUtility.decorate_var(stand_var)


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	robot.ai_state = Robot.AiState.SEEK
	var perched: bool = blackboard.get_var(perched_var, false)
	if perched:
		var stand: Vector3 = blackboard.get_var(stand_var, robot.global_position)
		robot.walk_to(delta, stand)
		if robot.desired_velocity == Vector3.ZERO:
			robot.face(robot.target_position())
	else:
		robot.walk_to(delta, robot.target_position())
	return RUNNING
