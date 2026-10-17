class_name DifficultyCurve
extends Resource
## Wave length, threat budget and endless scaling (GDD 11.3-11.6, Appendix A).
## Pure functions of the wave number so they can be unit-tested (tests/test_difficulty_curve.gd).

@export_group("Spawn window (11.3)")
@export var window_base: float = 45.0
@export var window_step: float = 7.0
@export var window_cap: float = 210.0

@export_group("Threat budget (11.4)")
@export var budget_base: float = 12.0
@export var budget_scale: float = 6.0
@export var budget_exponent: float = 1.3
@export var waves_per_phase: int = 5
@export var big_haul_multiplier: float = 1.3

@export_group("Stat scaling (11.5)")
@export var hp_linear: float = 0.07
@export var hp_quadratic: float = 0.002
@export var damage_linear: float = 0.04
@export var damage_quadratic: float = 0.001
@export var drop_linear: float = 0.03

@export_group("Spawn lanes (11.6)")
## Waves at which the active lane count steps up; lane count = lanes_base + number of thresholds reached.
@export var lane_thresholds: PackedInt32Array = [5, 15, 30]
@export var lanes_base: int = 2

@export_group("Thieves (11.7)")
## Share of spawns that are thieves (scouts that grab a grain sack) in wave 1, then up by thief_share_per_wave.
@export var thief_share_base: float = 0.10
@export var thief_share_per_wave: float = 0.015
@export var thief_share_cap: float = 0.4

@export_group("Spawn pacing (11.4)")
## Relative spawn intensity over the window: ramp, peak, short lull, bigger peak. Never even.
@export var pacing_floor: float = 0.25
@export var first_peak_time: float = 0.3
@export var first_peak_height: float = 1.0
@export var second_peak_time: float = 0.78
@export var second_peak_height: float = 1.7
@export var peak_width: float = 0.11


func spawn_window(wave: int) -> float:
	return minf(window_base + window_step * (wave - 1), window_cap)


## Budget before the Big Haul multiplier (the table in GDD 11.4).
func base_threat_budget(wave: int) -> float:
	return budget_base + budget_scale * pow(float(wave), budget_exponent)


func is_big_haul(wave: int) -> bool:
	return wave > 0 and wave % waves_per_phase == 0


func threat_budget(wave: int) -> float:
	return base_threat_budget(wave) * (big_haul_multiplier if is_big_haul(wave) else 1.0)


func hp_multiplier(wave: int) -> float:
	var w := float(wave - 1)
	return 1.0 + hp_linear * w + hp_quadratic * w * w


func damage_multiplier(wave: int) -> float:
	var w := float(wave - 1)
	return 1.0 + damage_linear * w + damage_quadratic * w * w


func drop_multiplier(wave: int) -> float:
	return 1.0 + drop_linear * float(wave - 1)


## GDD 10.3: 0 (waves 1-5), 1 (6-15), 2 (16-30), 3 (31+).
func trait_count(wave: int) -> int:
	if wave <= 5:
		return 0
	if wave <= 15:
		return 1
	if wave <= 30:
		return 2
	return 3


## GDD 11.6: 2 lanes (1-4), 3 (5-14), 4 (15-29), 5 (30+).
func lane_count(wave: int) -> int:
	var count := lanes_base
	for threshold in lane_thresholds:
		if wave >= threshold:
			count += 1
	return count


## Share of the wave's spawns that are thieves (GDD 11.7): thief_share_base in wave 1, creeping up each wave.
func thief_share(wave: int) -> float:
	return minf(thief_share_cap, thief_share_base + thief_share_per_wave * float(wave - 1))


## Steal roll for a scout, applied after its farmer-target roll. Dividing by the chance of not going
## for the farmer makes the overall thief share come out at thief_share(wave).
func thief_chance(wave: int, farmer_target_chance: float) -> float:
	return thief_share(wave) / maxf(0.01, 1.0 - farmer_target_chance)


## Relative spawn intensity at normalized time t in [0, 1].
func pacing_intensity(t: float) -> float:
	var first := first_peak_height * exp(-pow((t - first_peak_time) / peak_width, 2.0))
	var second := second_peak_height * exp(-pow((t - second_peak_time) / peak_width, 2.0))
	var ramp := pacing_floor * smoothstep(0.0, 0.15, t)
	return ramp + first + second


## Spawn times (seconds from the start of the window) for `count` spawn events, shaped by
## pacing_intensity. Sorted, all within [0, window]. Deterministic: no RNG.
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
	return times
