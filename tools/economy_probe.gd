extends SceneTree
## Reproducible composition and economy model; this is not a player-difficulty test. Waves 1-6 use the authored
## opening's fixed rosters (OpeningWave); later waves use the real seeded roster generator.
## Run: <godot> --headless --path . --script res://tools/economy_probe.gd
## Optional user args: -- --probe-seeds=256 --probe-last-wave=6
## All sampled robots are assumed legitimately killed and every sampled wave cleared.
## Full collection and 50%-Vac-only are separate recovery assumptions. No luck, traits,
## tutorial grants, purchases, defense spending, or optional ready bonuses are modeled.
## SceneState reads preserve runtime exports without instantiating the playable farm.
## Standalone directors/lanes never enter the tree or emit gameplay/save signals.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const FARM_SCENE := "res://scenes/farm/farm.tscn"
const UPGRADE_DIR := "res://data/upgrades"
const PARTS: Array[StringName] = [&"al", &"cu", &"au", &"pc"]
const DIRECTOR_EXPORTS: Array[StringName] = [
	&"curve", &"archetypes", &"foreman_archetype", &"spitter_archetype", &"type_weights",
	&"salvage_reward_interval", &"salvage_clear_parts", &"early_bird_base_al",
]

var _seeds: int = 256
var _last_wave: int = 6
var _lanes: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-seeds="):
			_seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--probe-last-wave="):
			_last_wave = int(arg.get_slice("=", 1))
	if _seeds < 1 or _last_wave < 1 or _seeds > 10000 or _last_wave > 100:
		push_error("Probe bounds: 1–10000 seeds and 1–100 waves.")
		quit(2)
		return
	var director = _load_director()
	if director == null:
		quit(1)
		return
	if not director.has_method(&"clear_rewards_for"):
		push_error("WaveDirector must expose its pure clear_rewards_for(wave_number) method.")
		_cleanup(director)
		quit(1)
		return
	var robot_constants := (load("res://scripts/ai/robot.gd") as Script).get_script_constant_map()
	if not robot_constants.has("FOREMAN_BOUNTY"):
		push_error("Robot must declare the directly banked FOREMAN_BOUNTY.")
		_cleanup(director)
		quit(1)
		return
	var bounty: Dictionary = robot_constants["FOREMAN_BOUNTY"]
	var foreman_drops: Dictionary = robot_constants["FOREMAN_DROPS"]
	var report := {
		"assumptions": {
			"seeds": _seeds, "seed_range": "0..%d" % (_seeds - 1), "waves": _last_wave,
			"kills": "All individual robots legitimately killed; all waves cleared.",
			"drops": "Analytical expectations from current archetype resources; no luck or traits.",
			"recovery": "Full collection versus 50%-Vac-only; banked guarantees unaffected.",
			"sweep_timing": "Vac-only includes the battle-start sweep following every sampled wave, including the final wave.",
			"excluded": "Tutorial, optional bell bonuses, defense spending, defeat losses, and purchases.",
			"optional_ready_base_al_per_clear": director.early_bird_base_al,
			"difficulty": "Composition/economy model only; not evidence of player survival or fun.",
		},
		"waves": [], "catalog": _catalog_report(),
	}
	var total_full := _empty_parts()
	var total_vac := _empty_parts()
	var total_physical := _empty_parts()
	var total_banked := _empty_parts()
	var total_robots := 0.0
	var total_climbers := 0.0
	var vertical_robots := 0.0
	var vertical_climbers := 0.0
	for wave_number in range(1, _last_wave + 1):
		var result := _sample_wave(director, wave_number, foreman_drops, bounty)
		report["waves"].append(result)
		_add_parts(total_physical, result["expected_physical_parts"])
		_add_parts(total_banked, result["expected_banked_rewards"])
		_add_parts(total_full, result["full_collection"])
		_add_parts(total_vac, result["vac_only_50_percent"])
		total_robots += result["mean_individual_robots"]
		total_climbers += result["mean_climbers"]
		if result["mean_climbers"] > 0.0:
			vertical_robots += result["mean_individual_robots"]
			vertical_climbers += result["mean_climbers"]
		report["waves"][-1]["cumulative_full_collection"] = _rounded_parts(total_full)
		report["waves"][-1]["cumulative_vac_only_50_percent"] = _rounded_parts(total_vac)
	report["totals"] = {
		"mean_individual_robots": snappedf(total_robots, 0.001),
		"mean_climbers": snappedf(total_climbers, 0.001),
		"climber_share_all_waves": snappedf(total_climbers / maxf(1.0, total_robots), 0.0001),
		"climber_share_waves_with_climbers": snappedf(vertical_climbers / maxf(1.0, vertical_robots), 0.0001),
		"expected_physical_parts": _rounded_parts(total_physical),
		"expected_banked_rewards": _rounded_parts(total_banked),
		"full_collection": _rounded_parts(total_full),
		"vac_only_50_percent": _rounded_parts(total_vac),
	}
	print(JSON.stringify(report, "  ", true))
	_cleanup(director)
	quit(0)


func _load_director():
	var state := (load(MAIN_SCENE) as PackedScene).get_state()
	var director = load("res://scripts/systems/wave_director.gd").new()
	var found := false
	for index in state.get_node_count():
		if state.get_node_name(index) != &"WaveDirector":
			continue
		found = true
		for property_index in state.get_node_property_count(index):
			var property_name := state.get_node_property_name(index, property_index)
			if property_name in DIRECTOR_EXPORTS:
				director.set(property_name, state.get_node_property_value(index, property_index))
	if not found or director.curve == null or director.archetypes.is_empty():
		push_error("Main scene has no configured WaveDirector.")
		director.free()
		return null
	var lane_map = director.get(&"_lanes")
	var farm_state := (load(FARM_SCENE) as PackedScene).get_state()
	for index in farm_state.get_node_count():
		var script: Script = null
		var lane_index := 1
		for property_index in farm_state.get_node_property_count(index):
			var property_name := farm_state.get_node_property_name(index, property_index)
			if property_name == &"script":
				script = farm_state.get_node_property_value(index, property_index) as Script
			elif property_name == &"lane_index":
				lane_index = int(farm_state.get_node_property_value(index, property_index))
		if script != null and script.resource_path == "res://scripts/systems/lane_marker.gd":
			var lane = load("res://scripts/systems/lane_marker.gd").new()
			lane.lane_index = lane_index
			_lanes.append(lane)
			lane_map[lane_index] = lane
	director.set(&"_lanes", lane_map)
	return director


func _sample_wave(director, wave_number: int, foreman_drops: Dictionary, bounty: Dictionary) -> Dictionary:
	var counts := {}
	var physical := _empty_parts()
	var banked := _empty_parts()
	var minimum_climbers := 2147483647
	var maximum_climbers := 0
	var minimum_drones := 2147483647
	var maximum_drones := 0
	var minimum_robots := 2147483647
	var maximum_robots := 0
	var share_min := 1.0
	var share_max := 0.0
	var total := 0
	var climbers := 0
	for seed_value in _seeds:
		# The real siren shuffles lanes before buying the roster with the same spawn stream.
		var rng_service := root.get_node(^"RngService")
		director.set(&"_wave_rng", rng_service.make_rng([seed_value, wave_number, &"spawns"]))
		director.call(&"_pick_lanes", director.curve.lane_count(wave_number))
		var authored = director.authored_wave(wave_number)
		var events: Array = _authored_events(director, authored) if authored != null \
				else director.call(&"_build_spawn_events", wave_number)
		var sample_count := 0
		# _enter_spawning appends the bonus Foreman after _build_spawn_events; authored waves list theirs.
		if authored == null and director.curve.is_big_haul(wave_number) and director.foreman_archetype != null:
			sample_count += 1
			counts[&"foreman"] = int(counts.get(&"foreman", 0)) + 1
			_add_parts(physical, foreman_drops)
			_add_parts(physical, bounty, -1.0)
			_add_parts(banked, bounty)
		var sample_climbers := 0
		var sample_drones := 0
		for event in events:
			var count: int = event.robot_count()
			var id: StringName = &"foreman" if event.foreman else event.archetype.id
			counts[id] = int(counts.get(id, 0)) + count
			sample_count += count
			if event.archetype.id in [&"roof_lobber", &"rung_runner"]:
				sample_climbers += count
			elif event.archetype.id == &"drone":
				sample_drones += count
			if event.foreman:
				_add_parts(physical, foreman_drops)
				_add_parts(physical, bounty, -1.0)
				_add_parts(banked, bounty)
			else:
				_add_parts(physical, _expected_drops(event.archetype, director.curve, wave_number), float(count))
		_add_parts(banked, director.call(&"clear_rewards_for", wave_number))
		total += sample_count
		minimum_robots = mini(minimum_robots, sample_count)
		maximum_robots = maxi(maximum_robots, sample_count)
		climbers += sample_climbers
		minimum_climbers = mini(minimum_climbers, sample_climbers)
		maximum_climbers = maxi(maximum_climbers, sample_climbers)
		minimum_drones = mini(minimum_drones, sample_drones)
		maximum_drones = maxi(maximum_drones, sample_drones)
		var share := float(sample_climbers) / maxf(1.0, float(sample_count))
		share_min = minf(share_min, share)
		share_max = maxf(share_max, share)
	var mean_counts := {}
	for id: StringName in counts:
		mean_counts[id] = snappedf(float(counts[id]) / _seeds, 0.001)
	var mean_physical := _scaled_parts(physical, 1.0 / _seeds)
	var mean_banked := _scaled_parts(banked, 1.0 / _seeds)
	var full := mean_banked.duplicate()
	var vac := mean_banked.duplicate()
	_add_parts(full, mean_physical)
	_add_parts(vac, mean_physical, 0.5)
	return {
		"wave": wave_number,
		"mean_individual_robots": float(total) / _seeds,
		"individual_robot_count_range": [minimum_robots, maximum_robots],
		"mean_counts_by_archetype": mean_counts,
		"mean_climbers": float(climbers) / _seeds,
		"climber_share": snappedf(float(climbers) / maxi(1, total), 0.0001),
		"climber_share_range": [snappedf(share_min, 0.0001), snappedf(share_max, 0.0001)],
		"climber_count_range": [minimum_climbers, maximum_climbers],
		"drone_count_range": [minimum_drones, maximum_drones],
		"expected_physical_parts": _rounded_parts(mean_physical),
		"expected_banked_rewards": _rounded_parts(mean_banked),
		"full_collection": _rounded_parts(full),
		"vac_only_50_percent": _rounded_parts(vac),
	}


## The authored wave's members as the director's own spawn events (a trio is one event of three).
func _authored_events(director, authored) -> Array:
	var events: Array = []
	var event_script = director.get_script().get_script_constant_map().get("SpawnEvent")
	for group in authored.groups:
		for i in group.archetype_ids.size():
			var archetype = director.archetype_by_id(group.archetype_ids[i])
			if archetype != null:
				events.append(event_script.new(archetype, group.roles[i] == &"foreman", group.counts[i]))
	return events


func _expected_drops(archetype, curve, wave_number: int) -> Dictionary:
	return {
		&"al": ((archetype.drop_al_min + archetype.drop_al_max) * 0.5 + archetype.drop_al_class_bonus) * curve.drop_multiplier(wave_number),
		&"cu": clampf(archetype.drop_cu_chance, 0.0, 1.0) * (archetype.drop_cu_min + archetype.drop_cu_max) * 0.5,
		&"au": clampf(archetype.drop_au_chance, 0.0, 1.0) * (archetype.drop_au_min + archetype.drop_au_max) * 0.5,
		&"pc": clampf(archetype.drop_pc_chance, 0.0, 1.0) * (archetype.drop_pc_min + archetype.drop_pc_max) * 0.5,
	}


func _catalog_report() -> Dictionary:
	var tracks := {}
	var total := _empty_parts()
	for file in ResourceLoader.list_directory(UPGRADE_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var upgrade = load(UPGRADE_DIR.path_join(file))
		if upgrade == null:
			continue
		var track_total := _empty_parts()
		for rank in range(1, upgrade.max_level + 1):
			if upgrade.cost_curve != null:
				_add_parts(track_total, upgrade.cost_curve.cost(rank))
		_add_parts(total, track_total)
		tracks[upgrade.id] = {"max_rank": upgrade.max_level, "total": _rounded_parts(track_total)}
	return {"total": _rounded_parts(total), "tracks": tracks}


func _empty_parts() -> Dictionary:
	return {&"al": 0.0, &"cu": 0.0, &"au": 0.0, &"pc": 0.0}


func _add_parts(into: Dictionary, source: Dictionary, scale: float = 1.0) -> void:
	for part in PARTS:
		into[part] = float(into.get(part, 0.0)) + float(source.get(part, 0.0)) * scale


func _scaled_parts(source: Dictionary, scale: float) -> Dictionary:
	var result := _empty_parts()
	_add_parts(result, source, scale)
	return result


func _rounded_parts(source: Dictionary) -> Dictionary:
	var result := {}
	for part in PARTS:
		result[part] = snappedf(float(source.get(part, 0.0)), 0.001)
	return result


func _cleanup(director) -> void:
	director.free()
	for lane in _lanes:
		lane.free()
	_lanes.clear()
