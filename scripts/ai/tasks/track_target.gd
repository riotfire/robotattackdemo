@tool
extends BTAction
## Keeps the robot's farmer target current, every tick (GDD 9.2, 4.5). Always succeeds, so it leads the
## tree's root BTDynamicSequence ahead of the decisions.
## - A dead or missing farmer: target the nearest living one instead, or the silo if there's none.
## - A farmer perched out of reach (PerchQuery.CLIMB_REACH above the robot) for the archetype's
##   unreachable_give_up_time: give up and go back to the silo.
## - While the farmer is perched: sets `perched_var`, and `stand_var` to the spot below them on the
##   robot's level (PerchQuery.stand_spot), which BTApproach walks to and waits at.

@export var perched_var: StringName = &"target_perched"
@export var stand_var: StringName = &"perch_stand"

var _unreachable_time: float = 0.0


func _generate_name() -> String:
	return "TrackTarget  ➜%s %s" % [LimboUtility.decorate_output_var(perched_var), LimboUtility.decorate_output_var(stand_var)]


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	var perched := false
	if robot.target_kind == Robot.TargetKind.PLAYER:
		var target := robot.target_player
		if target == null or not is_instance_valid(target) \
				or (target.has_method("is_alive") and not target.call("is_alive")):
			target = GameState.get_nearest_player(robot.global_position)
			robot.target_player = target
			if target == null:
				robot.target_kind = Robot.TargetKind.SILO
		if target != null:
			perched = PerchQuery.is_perched(robot.global_position, target.global_position)
			if perched:
				_unreachable_time += delta
				if _unreachable_time >= robot.archetype.unreachable_give_up_time:
					robot.target_kind = Robot.TargetKind.SILO
					robot.target_player = null
					_unreachable_time = 0.0
					perched = false
			else:
				_unreachable_time = 0.0
			if perched:
				blackboard.set_var(stand_var, PerchQuery.stand_spot(target.global_position, robot.global_position.y))
	blackboard.set_var(perched_var, perched)
	return SUCCESS
