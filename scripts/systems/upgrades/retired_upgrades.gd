class_name RetiredUpgrades
extends RefCounted
## Pegboard nodes taken out of the catalog, and what a profile that bought them gets back
## (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md: retire the paid jump-height and zipline-speed ranks
## in favor of effects with demonstrated uses, and compensate prior purchases).
##
## Profiles don't record what they paid, so each level refunds the higher of its two historical prices:
## the 1.35 growth used until 2026-10-25 and the 1.25 growth after it (the generous fallback). Riding a
## zipline with any weapon, Zipline Grip's level 2, is now part of basic riding (weapon_holder.gd).

## Node id -> one {part: amount} per level, level 1 first.
const REFUNDS: Dictionary[StringName, Array] = {
	# Al 15 base: 15, 20 (1.35) or 19 (1.25), 27 (1.35) or 23 (1.25).
	&"travel.springy_soles": [{&"al": 15}, {&"al": 20}, {&"al": 27}],
	# Al 25 base, plus Cu 10 at level 2: 25, then 34 (1.35) or 31 (1.25) and 10 Cu.
	&"travel.zipline_grip": [{&"al": 25}, {&"al": 34, &"cu": 10}],
}


## Takes the retired nodes out of `levels` (node id -> level) and returns the parts to refund for them.
static func refund(levels: Dictionary) -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for key: Variant in levels.keys():
		var id := StringName(str(key))
		if not REFUNDS.has(id):
			continue
		var bought := clampi(int(levels[key]), 0, REFUNDS[id].size())
		for level in bought:
			var cost: Dictionary = REFUNDS[id][level]
			for part: StringName in cost:
				total[part] = total.get(part, 0) + int(cost[part])
		levels.erase(key)
	return total
