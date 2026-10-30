@tool
extends BTAction
## The telegraph before a hit (GDD 9.6, 15.4): faces the target for the archetype's attack_windup, then
## succeeds. A squad member's first windup is held `squad_index` beats longer, so the squad lands its
## hits clank-clank-CLANK (one beat = attack_interval / squad_beats, from the squad blackboard).
##
## The tick that starts the windup only commits to it; the countdown starts on the next tick.

@export var first_attack_var: StringName = &"first_attack"
@export var beats_var: StringName = &"squad_beats"

var _timer: float = 0.0
var _started: bool = false


func _generate_name() -> String:
	return "Windup (rhythm: %s)" % LimboUtility.decorate_var(beats_var)


func _enter() -> void:
	_started = false


func _tick(delta: float) -> Status:
	var robot := agent as Robot
	if not _started:
		_started = true
		robot.ai_state = Robot.AiState.WINDUP
		_timer = robot.archetype.attack_windup
		var beats: int = blackboard.get_var(beats_var, 0, false)
		var first: bool = blackboard.get_var(first_attack_var, true, false)
		if first and beats > 0:
			_timer += robot.squad_index * robot.archetype.attack_interval / beats
		blackboard.set_var(first_attack_var, false)
		robot.begin_windup()
		return RUNNING
	robot.face(robot.target_position())
	_timer -= delta
	return SUCCESS if _timer <= 0.0 else RUNNING
