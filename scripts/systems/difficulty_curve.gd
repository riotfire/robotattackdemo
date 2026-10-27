class_name DifficultyCurve
extends Resource
## Wave length, threat budget and endless scaling (GDD 11.3-11.6, Appendix A).
## Pure functions of the wave number so they can be unit-tested (tests/test_difficulty_curve.gd).
## Phases are 3 waves (PHASE_CHECKPOINT_PROGRESSION_PLAN.md): Lesson, Twist, Big Haul. Every scaling step
## below starts on a phase's first wave (waves 1, 4, 7, 10, ...), so a retry of a phase always plays by the
## same rules; the third and fourth lanes are the deliberate exceptions (announced twist-wave raids).

@export_group("Spawn window (11.3)")
@export var window_base: float = 45.0
@export var window_step: float = 7.0
@export var window_cap: float = 210.0

@export_group("Threat budget (11.4)")
@export var budget_base: float = 12.0
@export var budget_scale: float = 6.0
@export var budget_exponent: float = 1.3
## Waves per phase. The last wave of every phase is the Big Haul, with the Foreman.
@export var waves_per_phase: int = 3
@export var big_haul_multiplier: float = 1.3
## Budget multipliers for the first generated waves after the authored opening (waves 7, 8, 9), so the count
## steps up from the opening's 15-20 robots instead of jumping to the curve's 33 (the playtest simulation's
## finding 3: "a cliff, not a step"). Every later wave keeps the plain curve (the phase plan's P-D6).
@export var opening_handoff: PackedFloat32Array = [0.7, 0.8, 0.85]

@export_group("Stat scaling (11.5)")
@export var hp_linear: float = 0.07
@export var hp_quadratic: float = 0.002
@export var damage_linear: float = 0.04
@export var damage_quadratic: float = 0.001
@export var drop_linear: float = 0.03

@export_group("Spawn lanes (11.6)")
## Waves at which the active lane count steps up; lane count = lanes_base + number of thresholds reached.
## 5 and 14 are twist waves (the late third and fourth lanes); 31 starts the late phase.
@export var lane_thresholds: PackedInt32Array = [5, 14, 31]
@export var lanes_base: int = 2

@export_group("Family traits (10.3)")
## Waves at which wave families roll one more trait: 0 traits before the first, 1 from it, and so on.
@export var trait_thresholds: PackedInt32Array = [7, 16, 31]

@export_group("Thieves (11.7)")
## Share of spawns that are thieves (scouts that grab a grain sack) in wave 1, then up by thief_share_per_wave.
@export var thief_share_base: float = 0.10
@export var thief_share_per_wave: float = 0.015
@export var thief_share_cap: float = 0.4
## A Thieving family multiplies the share by this (ROADMAP D4), up to thieving_share_cap.
@export var thieving_share_multiplier: float = 1.5
@export var thieving_share_cap: float = 0.6

@export_group("Groups (9.6)")
## An archetype with a later trio chance (RobotArchetype.trio_chance_late) keeps its trio_chance until
## this wave, jumps trio_step_share of the way to the later value here, then climbs to it by trio_full_wave.
@export var trio_step_wave: int = 4
@export_range(0.0, 1.0) var trio_step_share: float = 0.6667
@export var trio_full_wave: int = 16

@export_group("Vertical threats")
## Phase 1 stays on the ground; from phase 2's Lesson, reserve roughly one climber per three other robots.
@export var climber_first_wave: int = 4
@export_range(0.0, 0.5) var climber_target_share: float = 0.25
## Generated waves give this share of the reserved climbers to the silo-ladder climber (Rung Runner) instead
## of the Roof Lobber, from ladder_climber_first_wave. It takes part of the same allocation, never a second one.
@export var ladder_climber_first_wave: int = 7
@export_range(0.0, 1.0) var ladder_climber_share: float = 0.35

@export_group("Attack scaling (9.6, M2-B10)")
## The authored opening (waves 1 to this, OpeningWave resources) keeps the M1 values of every knob below;
## scaling starts after it.
@export var opening_last_wave: int = 6
## First waves of the middle and late phases. The early phase runs from opening_last_wave + 1.
@export var mid_first_wave: int = 16
@export var late_first_wave: int = 31
## Robots that may shoot at one farmer at once (AttackTokens), by phase: opening, early, middle, late.
@export var farmer_tokens_by_phase: PackedInt32Array = [2, 3, 4, 5]
## Multiplies every ranged robot's charge time, by phase. AttackProfile keeps the 0.45 s floor.
@export var charge_multiplier_by_phase: PackedFloat32Array = [1.0, 0.9, 0.8, 0.7]
## How far ahead of a moving farmer straight shots aim, as a share of where the farmer will be when the
## shot arrives, by phase. Lobs, rails and bombs never lead. The early phase's lead waits for aim_lead_first_wave.
@export var aim_lead_by_phase: PackedFloat32Array = [0.0, 0.3, 0.6, 0.6]
@export var aim_lead_first_wave: int = 10
## Shots per attack for Drones and Spitters in a trio: 1 until volley_two_wave, 2 until volley_three_wave, then 3.
@export var volley_two_wave: int = 16
@export var volley_three_wave: int = 25
## Share of small ground melee spawns that come as Spitters: spitter_share_base at spitter_first_wave, then
## up spitter_share_per_wave each wave, to spitter_share_cap.
@export var spitter_first_wave: int = 13
@export var spitter_share_base: float = 0.10
@export var spitter_share_per_wave: float = 0.02
@export var spitter_share_cap: float = 0.4
## Weighted-pick shares of the attack grid's columns (melee, ranged, flight) by phase after the opening.
## The climber reservation and per-wave caps determine final composition. The opening keeps plain weights.
@export var column_weights_early: PackedFloat32Array = [0.60, 0.28, 0.12]
@export var column_weights_mid: PackedFloat32Array = [0.52, 0.30, 0.18]
@export var column_weights_late: PackedFloat32Array = [0.45, 0.33, 0.22]
## Melee robots with on_unreachable = throw throw at an out-of-reach farmer from this wave (M2-B9). Phase 5,
## "the robots fight back", teaches it together with the Spitter and the arm guard.
@export var unreachable_throw_first_wave: int = 13
## The Clanker's front arm guard is up from this wave (M2-B9); until then it is the M1 Clanker.
@export var arm_guard_first_wave: int = 13

@export_group("Spawn pacing (11.4)")
## Relative spawn intensity over the window: ramp, peak, short lull, bigger peak. Never even.
@export var pacing_floor: float = 0.55
@export var first_peak_time: float = 0.22
@export var first_peak_height: float = 1.0
@export var second_peak_time: float = 0.7
@export var second_peak_height: float = 1.5
@export var peak_width: float = 0.15
## Spread events across this fraction of the wave window to keep pressure steady and reduce long gaps.
@export_range(0.5, 1.0, 0.05) var spawn_window_fraction: float = 0.8


func spawn_window(wave: int) -> float:
	return minf(window_base + window_step * (wave - 1), window_cap)


## Budget before the Big Haul multiplier (the table in GDD 11.4).
func base_threat_budget(wave: int) -> float:
	return budget_base + budget_scale * pow(float(wave), budget_exponent)


func is_big_haul(wave: int) -> bool:
	return wave > 0 and wave % maxi(1, waves_per_phase) == 0


## 1 for waves 1-3, 2 for 4-6, ...
func phase_of(wave: int) -> int:
	return floori(float(maxi(1, wave) - 1) / maxi(1, waves_per_phase)) + 1


## 1, 2 or 3: the Lesson, Twist or Big Haul of its phase.
func wave_in_phase(wave: int) -> int:
	return posmod(maxi(1, wave) - 1, maxi(1, waves_per_phase)) + 1


## The first wave of the phase `wave` is in (1, 4, 7, ...): where a lost attempt starts again.
func phase_first_wave(wave: int) -> int:
	return (phase_of(wave) - 1) * maxi(1, waves_per_phase) + 1


func threat_budget(wave: int) -> float:
	return base_threat_budget(wave) * (big_haul_multiplier if is_big_haul(wave) else 1.0) * handoff_multiplier(wave)


## The opening_handoff multiplier for `wave`, or 1.
func handoff_multiplier(wave: int) -> float:
	var index := wave - opening_last_wave - 1
	return opening_handoff[index] if index >= 0 and index < opening_handoff.size() else 1.0


func hp_multiplier(wave: int) -> float:
	var w := float(wave - 1)
	return 1.0 + hp_linear * w + hp_quadratic * w * w


func damage_multiplier(wave: int) -> float:
	var w := float(wave - 1)
	return 1.0 + damage_linear * w + damage_quadratic * w * w


func drop_multiplier(wave: int) -> float:
	return 1.0 + drop_linear * float(wave - 1)


## GDD 10.3: 0 (waves 1-6, the authored opening), 1 (7-15), 2 (16-30), 3 (31+).
func trait_count(wave: int) -> int:
	var count := 0
	for threshold in trait_thresholds:
		if wave >= threshold:
			count += 1
	return count


## GDD 11.6: 2 lanes (1-4), 3 (5-13), 4 (14-30), 5 (31+).
func lane_count(wave: int) -> int:
	var count := lanes_base
	for threshold in lane_thresholds:
		if wave >= threshold:
			count += 1
	return count


## Share of the wave's spawns that are thieves (GDD 11.7): thief_share_base in wave 1, creeping up each wave.
## A Thieving family multiplies it by thieving_share_multiplier, up to thieving_share_cap.
func thief_share(wave: int, thieving: bool = false) -> float:
	var share := minf(thief_share_cap, thief_share_base + thief_share_per_wave * float(wave - 1))
	if thieving:
		share = minf(thieving_share_cap, share * thieving_share_multiplier)
	return share


## Steal roll for a scout group, applied after its silo-focus roll. Dividing by the chance of going for
## the silo makes the overall thief share come out at thief_share(wave). A heist crew counts as one thief.
func thief_chance(wave: int, silo_focus: float, thieving: bool = false) -> float:
	return thief_share(wave, thieving) / maxf(0.01, silo_focus)


## 0 for the opening (waves 1-6), 1 early (7-15), 2 middle (16-30), 3 late (31+).
func attack_phase(wave: int) -> int:
	if wave <= opening_last_wave:
		return 0
	if wave < mid_first_wave:
		return 1
	if wave < late_first_wave:
		return 2
	return 3


## Robots that may shoot at one farmer at once in this wave (AttackTokens): 2, then 3 / 4 / 5 by phase.
func farmer_attack_tokens(wave: int) -> int:
	return farmer_tokens_by_phase[mini(attack_phase(wave), farmer_tokens_by_phase.size() - 1)]


## Multiplies ranged charge times in this wave: 1.0, then 0.9 / 0.8 / 0.7. The 0.45 s floor still holds.
func charge_multiplier(wave: int) -> float:
	return charge_multiplier_by_phase[mini(attack_phase(wave), charge_multiplier_by_phase.size() - 1)]


## Aim lead for straight shots in this wave: 0 until aim_lead_first_wave, then 0.3, then 0.6 from wave 16.
func aim_lead(wave: int) -> float:
	if wave < aim_lead_first_wave:
		return 0.0
	return aim_lead_by_phase[mini(attack_phase(wave), aim_lead_by_phase.size() - 1)]


## Shots per attack for Drones and Spitter trios in this wave: 1, then 2 from wave 16, 3 from wave 25.
func volley_size(wave: int) -> int:
	if wave >= volley_three_wave:
		return 3
	return 2 if wave >= volley_two_wave else 1


## Share of small ground melee spawns that come as Spitters: 10% at wave 13, +2 points a wave, up to 40%.
func spitter_share(wave: int) -> float:
	if wave < spitter_first_wave:
		return 0.0
	return minf(spitter_share_cap, spitter_share_base + spitter_share_per_wave * float(wave - spitter_first_wave))


## Weighted-pick shares of the melee, ranged and flight columns; empty in the opening, which keeps plain
## type weights. The director reserves climbers separately and limits drones before using these weights.
func column_weights(wave: int) -> PackedFloat32Array:
	match attack_phase(wave):
		0:
			return PackedFloat32Array()
		1:
			return column_weights_early
		2:
			return column_weights_mid
	return column_weights_late


## Melee robots with on_unreachable = throw throw at an out-of-reach farmer in this wave.
func throws_at_unreachable(wave: int) -> bool:
	return wave >= unreachable_throw_first_wave


## The Clanker's front arm guard is up in this wave.
func arm_guard_up(wave: int) -> bool:
	return wave >= arm_guard_first_wave


## Chance a spawn of `archetype` is a trio in this wave (GDD 9.6). 0 for large robots, flyers and Foremen.
func trio_chance(wave: int, archetype: RobotArchetype, foreman: bool = false) -> float:
	if foreman or not archetype.can_form_trio():
		return 0.0
	var early := archetype.trio_chance
	var late := archetype.trio_chance_late
	if late < 0.0 or wave < trio_step_wave:
		return early
	var step := early + (late - early) * trio_step_share
	var t := clampf(float(wave - trio_step_wave) / maxf(1.0, float(trio_full_wave - trio_step_wave)), 0.0, 1.0)
	return lerpf(step, late, t)


## Number of individual climbers to reserve for this many other robots. The Foreman, when present,
## counts among the other robots; a three-robot squad counts as three, rather than one spawn event.
func climber_count(wave: int, other_robots: int) -> int:
	if wave < climber_first_wave or climber_target_share <= 0.0:
		return 0
	return roundi(float(other_robots) * climber_target_share / maxf(0.01, 1.0 - climber_target_share))


## How many of `climbers` reserved climbers climb the silo ladder (Rung Runners) instead of a roof. At least
## one once they're in generated waves and there are two or more climbers, so both routes stay in play.
func ladder_climber_count(wave: int, climbers: int) -> int:
	if wave < ladder_climber_first_wave or climbers <= 0 or ladder_climber_share <= 0.0:
		return 0
	var count := roundi(float(climbers) * ladder_climber_share)
	if climbers >= 2:
		count = maxi(1, count)
	return mini(count, climbers)


## Relative spawn intensity at normalized time t in [0, 1].
func pacing_intensity(t: float) -> float:
	var first := first_peak_height * exp(-pow((t - first_peak_time) / peak_width, 2.0))
	var second := second_peak_height * exp(-pow((t - second_peak_time) / peak_width, 2.0))
	var ramp := pacing_floor * smoothstep(0.0, 0.15, t)
	return ramp + first + second


## Spawn times (seconds from the start of the window) for `count` spawn events, shaped by
## pacing_intensity. Sorted, all within [0, window]; the first lands at 0 so the attack opens the moment
## the siren ends. Deterministic: no RNG.
func spawn_schedule(count: int, window: float) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	if count <= 0:
		return times
	const SAMPLES := 200
	var cdf := PackedFloat32Array()
	cdf.resize(SAMPLES + 1)
	cdf[0] = 0.0
	for i in SAMPLES:
		var t := (float(i) + 0.5) / SAMPLES
		cdf[i + 1] = cdf[i] + pacing_intensity(t)
	var total := cdf[SAMPLES]
	var sample := 0
	for k in count:
		var target := (float(k) + 0.5) / count * total
		while sample < SAMPLES and cdf[sample + 1] < target:
			sample += 1
		var span := cdf[sample + 1] - cdf[sample]
		var frac := (target - cdf[sample]) / span if span > 0.0 else 0.0
		times.append((float(sample) + frac) / SAMPLES * window)
	times[0] = 0.0
	return times
