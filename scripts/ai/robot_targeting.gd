class_name RobotTargeting
extends RefCounted
## Who a robot is after: the silo or a farmer (GDD 9.2, 9.6; M2-B6). Reads the archetype's behavior
## variables. A trio shares one RobotTargeting on its RobotSquad: the leader's senses drive it and every
## member follows, so the group rolls its target and any distraction once.
##
## At spawn it rolls silo_focus; a robot that fails the roll hunts the farmer. While on the silo, once a
## second, an active trigger (hurt, near, repairing, airborne) switches it to the farmer with chance
## distractibility; a farmer hit also rolls at once. It goes back to the silo when any return rule is met:
## the farmer goes down, it chased for chase_time, the farmer led it leash_range from the silo, or the farmer
## stayed out of reach for give_up_time. Chase time and the leash start counting once it is within
## distract_range of the farmer, so a hunter walking in from the corn isn't recalled on the way.
## A robot throwing at an out-of-reach farmer (on_unreachable = throw, M2-B9) holds the give-up clock while
## each throw is in the air, then sends it back itself after its last throw.
## No nodes are touched: Robot gathers the Senses each physics frame, so tests can drive every rule.

enum Goal { SILO, FARMER }
## Why it last went back to the silo.
enum Return { NONE, FARMER_DOWN, CHASE_TIME, LEASH, UNREACHABLE }

## How often a robot on the silo rolls for a distraction.
const DISTRACT_PERIOD: float = 1.0
## How long a farmer's hit keeps the hurt trigger active, so the next once-a-second roll still sees it.
const HURT_MEMORY: float = 1.0

## What a robot (or a trio's leader) senses this frame. Robot.sense() fills one in.
class Senses:
	## The nearest living farmer, or null.
	var farmer: Node3D = null
	var farmer_distance: float = INF
	## The robot's flat distance from the silo.
	var distance_from_silo: float = 0.0
	## False when it can't get at the farmer (a ground robot under a farmer on a roof).
	var farmer_reachable: bool = true
	## The farmer is jetpacking or up on a perch.
	var farmer_airborne: bool = false
	## The farmer is repairing a crack.
	var farmer_repairing: bool = false


## Emitted when it switches to a farmer after a distraction (the "!" pop) or goes back to the silo.
signal switched(goal: Goal)

var archetype: RobotArchetype
var goal: Goal = Goal.SILO
## The farmer it is after while goal is FARMER.
var farmer: Node3D = null
## True when the spawn roll sent it after the farmer.
var hunter: bool = false
## Within distract_range of its farmer at least once since it switched to them.
var engaged: bool = false
var last_return: Return = Return.NONE
## False for thieves and the tutorial's practice robot: nothing pulls them off their job.
var can_be_distracted: bool = true

var _rng: RandomNumberGenerator
var _since_switch: float = INF
var _chase_elapsed: float = 0.0
var _unreachable_elapsed: float = 0.0
var _distract_clock: float = 0.0
var _hurt_left: float = 0.0
var _hurt_by: Node3D = null
var _give_up_hold: float = 0.0
var _senses: Senses = Senses.new()


## `rng` is the wave's spawn stream: the spawn roll comes from it, then this robot's own stream is seeded
## from it, so a seed replays the same distractions.
func _init(robot_archetype: RobotArchetype, rng: RandomNumberGenerator) -> void:
	archetype = robot_archetype
	hunter = rng.randf() >= archetype.silo_focus
	goal = Goal.FARMER if hunter else Goal.SILO
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng.randi()


func on_farmer() -> bool:
	return goal == Goal.FARMER


func has_trigger(trigger: StringName) -> bool:
	return trigger in archetype.distract_triggers


## The hurt trigger is active: a farmer hit it (or a trio member) from within distract_range just now.
func is_hurt() -> bool:
	return _hurt_left > 0.0


## How long the farmer it is after has been out of reach.
func unreachable_time() -> float:
	return _unreachable_elapsed


## Holds the give-up clock for a moment: call every frame while a throw at the out-of-reach farmer is under
## way (any trio member can). The robot sends it back with return_to_silo() after its last throw.
func hold_give_up() -> void:
	_give_up_hold = 0.1


func tick(delta: float, senses: Senses) -> void:
	_senses = senses
	_since_switch += delta
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_give_up_hold = maxf(0.0, _give_up_hold - delta)
	if goal == Goal.FARMER:
		_tick_chase(delta, senses)
		return
	_distract_clock += delta
	if _distract_clock >= DISTRACT_PERIOD:
		_distract_clock -= DISTRACT_PERIOD
		_roll_distraction(senses.farmer)


## A farmer damaged the robot (or a member of its trio) from `distance` away.
func on_hurt(attacker: Node3D, distance: float) -> void:
	if not has_trigger(&"hurt") or distance > archetype.distract_range:
		return
	_hurt_left = HURT_MEMORY
	_hurt_by = attacker
	if goal == Goal.SILO:
		_distract_clock = 0.0
		_roll_distraction(attacker)


## Sends it after `target` now, whatever its rolls say (debug and scripted encounters).
func switch_to_farmer(target: Node3D) -> void:
	if target == null:
		return
	goal = Goal.FARMER
	farmer = target
	engaged = false
	_chase_elapsed = 0.0
	_unreachable_elapsed = 0.0
	_since_switch = 0.0
	switched.emit(goal)


func return_to_silo(reason: Return = Return.NONE) -> void:
	if goal == Goal.SILO:
		return
	goal = Goal.SILO
	farmer = null
	hunter = false
	last_return = reason
	_since_switch = 0.0
	_distract_clock = 0.0
	switched.emit(goal)


func _tick_chase(delta: float, senses: Senses) -> void:
	if farmer == null or not is_instance_valid(farmer) \
			or (farmer.has_method(&"is_alive") and not farmer.call(&"is_alive")):
		farmer = senses.farmer
		if farmer == null:
			return_to_silo(Return.FARMER_DOWN)
			return
	if not engaged and senses.farmer == farmer and senses.farmer_distance <= archetype.distract_range:
		engaged = true
	if engaged:
		_chase_elapsed += delta
	if senses.farmer_reachable:
		_unreachable_elapsed = 0.0
	elif _give_up_hold <= 0.0:
		_unreachable_elapsed += delta
	if archetype.give_up_time > 0.0 and _unreachable_elapsed >= archetype.give_up_time:
		return_to_silo(Return.UNREACHABLE)
	elif engaged and archetype.chase_time > 0.0 and _chase_elapsed >= archetype.chase_time:
		return_to_silo(Return.CHASE_TIME)
	elif engaged and archetype.leash_range > 0.0 and senses.distance_from_silo > archetype.leash_range:
		return_to_silo(Return.LEASH)


func _roll_distraction(target: Node3D) -> void:
	if not can_be_distracted or target == null or _since_switch < archetype.commit_time:
		return
	# A farmer the robot can't reach is no lure: hovering out of reach never pulls robots off the silo.
	if not _senses.farmer_reachable or not _trigger_active():
		return
	if _rng.randf() < archetype.distractibility:
		switch_to_farmer(_hurt_by if is_hurt() and is_instance_valid(_hurt_by) else target)


func _trigger_active() -> bool:
	if is_hurt():
		return true
	var near := _senses.farmer != null and _senses.farmer_distance <= archetype.distract_range
	if not near:
		return false
	return has_trigger(&"near") \
			or (has_trigger(&"repairing") and _senses.farmer_repairing) \
			or (has_trigger(&"airborne") and _senses.farmer_airborne)
