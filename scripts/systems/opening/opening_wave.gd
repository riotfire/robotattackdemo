class_name OpeningWave
extends Resource
## One wave of the authored six-wave opening (FIRST_FIVE_WAVES_FUN_PLAN.md as re-keyed onto 3-wave phases by
## PHASE_CHECKPOINT_PROGRESSION_PLAN.md step 4). The WaveDirector plays these instead of buying a roster with
## the threat budget: the order, lanes, live cap and Foreman are fixed on every seed, while robot cosmetics
## and the actual lanes (from lane_pool) stay seeded. Generated into data/opening/ from data/source/opening/
## by tools/build_opening_waves.gd.
##   Phase 1, wrench and roofs: 1 First Bonks, 2 Take the High Ground (the first Lobber, before any gun; its
##   clear unlocks the pistol), 3 the Foreman's first visit (450 HP).
##   Phase 2, split pressure: 4 Stop That Sack (Clankers, the thief, a barn Lobber), 5 Up the Ladder (a Rung
##   Runner on the ladder side while raids hit the far side), 6 the second Foreman (900 HP, from the far side,
##   clods at range) with climbers on the ladder.

@export var wave: int = 1
@export var title: String = ""
## Robots alive at once; a due group waits until it fits.
@export var live_cap: int = 6
## Main lanes (slots 0 and 1) the siren opens. Slot 2 opens later, when a raid group announces it.
@export var main_lanes: int = 2
## Lanes the main lanes are picked from (empty: any). Wave 1's first lane faces the farmer's start.
@export var lane_pool: PackedInt32Array = PackedInt32Array()
## Authored arrivals burst out of the crop rows this far from the silo, not the corn at ~110 m.
@export var spawn_distance: float = 45.0
## The Foreman's HP; 0 uses the curve (Thumper x3 x the wave's HP multiplier).
@export var foreman_hp: float = 0.0
## Below half health the Foreman throws dirt clods at a farmer out of slam range (M2-B14's ranged phase).
@export var foreman_throw_phase: bool = false
## The Foreman's defeat calls off the adds still to come and marks the survivors.
@export var foreman_cancels_adds: bool = true
## A short line for the siren card: what this wave asks of the player.
@export var hint: String = ""
@export var groups: Array[OpeningGroup] = []


func robot_count() -> int:
	var total := 0
	for group in groups:
		total += group.robot_count()
	return total


func has_foreman() -> bool:
	return groups.any(func(group: OpeningGroup) -> bool: return group.has_foreman())


func uses_third_lane() -> bool:
	return groups.any(func(group: OpeningGroup) -> bool: return group.lane_slot >= 2)
