class_name MilestoneRewards
extends RefCounted
## First-completion milestones of the run (PHASE_CHECKPOINT_PROGRESSION_PLAN.md step 4). A milestone never
## hands over an item: every weapon, recipe and defense is bought at the shed and built. A milestone only
## opens something up for building and says so, once per profile, the first time its wave is cleared. A
## profile that has already cleared the wave (an older save, a veteran resuming at a later phase) settles it
## on load instead, without the announcement.
##   w2_pistol   clear wave 2 (the first Roof Lobber): the Rivet Pistol blueprint, and with it every gun.
##   w9_jetpack  clear wave 9: the jetpack blueprint.
## StatService.MILESTONE_GATES holds the gates themselves (keep the waves in step); these are their announcements.

const REWARDS: Array[Dictionary] = [
	{"id": "w2_pistol", "wave": 2,
		"text": "Rivet Pistol blueprint! Buy it at the shed for 20 Al."},
	{"id": "w9_jetpack", "wave": 9,
		"text": "Jetpack blueprint! Build Grandpa's jetpack at the shed."},
]


## Settles every milestone whose wave is at most `cleared_wave` and that this profile hasn't had yet.
## Returns the newly settled milestones' messages, for the HUD.
static func reconcile(cleared_wave: int) -> PackedStringArray:
	var messages := PackedStringArray()
	for reward in REWARDS:
		var id: String = reward["id"]
		if int(reward["wave"]) > cleared_wave or id in SaveManager.granted_rewards:
			continue
		SaveManager.granted_rewards.append(id)
		messages.append(reward["text"])
	return messages
