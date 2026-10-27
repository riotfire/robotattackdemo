class_name OpeningGroup
extends Resource
## One arrival in an authored opening wave (OpeningWave): a few robots that enter together from one lane.
## Generated from data/source/opening/groups.csv by tools/build_opening_waves.gd.
##
## A group is released at release_time seconds into the attack, or after_delay seconds after group
## after_group has been resolved (every robot in it destroyed or gone), whichever the row sets. A due group
## still waits while it would push the wave over its live cap, so a queue is never dumped all at once.

## Seconds after the siren ends. Ignored when after_group is set.
@export var release_time: float = 0.0
## Index of the group (in its wave) that must be resolved first, or -1.
@export var after_group: int = -1
@export var after_delay: float = 0.0
## 0 and 1: the wave's main lanes; 2: a third direction, announced as a raid when it opens.
@export var lane_slot: int = 0
## The members, in parallel: archetype id, robot count (1 alone, 3 a trio), and a role.
@export var archetype_ids: Array[StringName] = []
@export var counts: PackedInt32Array = PackedInt32Array()
## &"" (as the archetype rolls it), &"thief" (the teaching thief), &"foreman" or &"calm" (never a thief).
@export var roles: Array[StringName] = []
## Roof Lobbers in this group climb this roof (VerticalRobot.ROOF_SITES path, e.g. ToolShed).
@export var roof: StringName = &""
## A debut caption id: shown once per profile (SaveManager.first_time) when the group arrives.
@export var intro: StringName = &""
## Announce the group's lane a few seconds before it is released (a late raid from a new direction).
@export var announce: bool = false


func robot_count() -> int:
	var total := 0
	for count in counts:
		total += maxi(1, count)
	return total


func has_foreman() -> bool:
	return &"foreman" in roles
