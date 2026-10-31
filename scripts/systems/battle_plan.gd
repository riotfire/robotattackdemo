class_name BattlePlan
extends Resource
## A wave's battle plan (M2-B11, ROBOT_ATTACK_VARIETY_PLAN.md "Battle plans"): a named bend of the spawn mix and
## director rules, shown beside the family name ("The Minty Pirate Teapots - Barrage!"). Rows live in
## data/source/robots/battle_plans/; the director rolls one per wave from wave 8 and two from wave 31.

## Waves a plan sits out after it ran (no plan repeats within 3 waves).
const REPEAT_GAP: int = 3
const FIRST_PLAN_WAVE: int = 8
const STACK_WAVE: int = 31

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var first_wave: int = 8
## Multiplies the melee, ranged and flight columns' share of weighted picks.
@export var melee_weight: float = 1.0
@export var ranged_weight: float = 1.0
@export var flight_weight: float = 1.0
## Raises the live Roof Lobber cap to at least this (0 keeps the wave's cap).
@export var rooftop_cap: int = 0
## Scales the number of reserved climbers.
@export var climber_multiplier: float = 1.0
## Extra Drones allowed in the wave.
@export var drone_cap_bonus: int = 0
@export var thief_share_multiplier: float = 1.0
## Added to the share of small melee spawns that come as Spitters.
@export var spitter_share_bonus: float = 0.0
## Only small robots (and the reserved climbers) are bought.
@export var small_only: bool = false
## Scales the threat budget; with small_only this is the "x1.4 count".
@export var count_multiplier: float = 1.0
@export var hp_multiplier: float = 1.0
## Two opposite lanes are used, and spawns alternate between them.
@export var paired_lanes: bool = false
## The plan only rolls when this archetype id is in the game (Siege needs the Longneck, M2-B12).
@export var requires_archetype: StringName = &""


func column_weight(robot_class: int) -> float:
	match robot_class:
		RobotArchetype.RobotClass.MELEE:
			return melee_weight
		RobotArchetype.RobotClass.RANGED:
			return ranged_weight
	return flight_weight


## How many plans a wave rolls: none before FIRST_PLAN_WAVE, two from STACK_WAVE.
static func plan_count(wave: int) -> int:
	if wave < FIRST_PLAN_WAVE:
		return 0
	return 2 if wave >= STACK_WAVE else 1


## The wave's plans. `recent` maps earlier waves to the ids they ran; `have` lists archetype ids in the game.
## No plan repeats within REPEAT_GAP waves unless nothing else is eligible, and a wave never rolls one twice.
static func choose(library: Array[BattlePlan], wave: int, recent: Dictionary, have: Array[StringName],
		rng: RandomNumberGenerator) -> Array[BattlePlan]:
	var chosen: Array[BattlePlan] = []
	for _slot in plan_count(wave):
		var fresh: Array[BattlePlan] = []
		var any: Array[BattlePlan] = []
		for plan in library:
			if plan == null or plan.first_wave > wave or chosen.has(plan):
				continue
			if not plan.requires_archetype.is_empty() and plan.requires_archetype not in have:
				continue
			any.append(plan)
			var ran_lately := false
			for back in range(1, REPEAT_GAP + 1):
				if plan.id in recent.get(wave - back, []):
					ran_lately = true
			if not ran_lately:
				fresh.append(plan)
		var pool := fresh if not fresh.is_empty() else any
		if pool.is_empty():
			break
		chosen.append(pool[rng.randi_range(0, pool.size() - 1)])
	return chosen
