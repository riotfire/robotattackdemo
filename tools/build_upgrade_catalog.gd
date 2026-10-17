extends SceneTree
## Writes the M1 pegboard (GDD 13) as one UpgradeNode .tres per node in res://data/upgrades/.
## 33 purchasable nodes across the five branches, plus the free Milk-Can Jetpack unlock.
## Run from the project folder:
##   <godot> --headless --path . --script res://tools/build_upgrade_catalog.gd
## Re-running overwrites the .tres files; after that, tune nodes in the inspector instead.
##
## Recipes follow GDD 12.4: levels 1-3 cost Aluminium, 4-6 add Copper, 7-8 Copper + Gold, 9-10 add Power
## Cells, each part growing x1.35 per level from where it first appears.

const OUT_DIR := "res://data/upgrades"

const T := UpgradeNode.Branch.TRAVEL
const A := UpgradeNode.Branch.ATTACK
const R := UpgradeNode.Branch.REPAIR
const D := UpgradeNode.Branch.DEFEND
const F := UpgradeNode.Branch.FARMHAND

const FLAT := StatModifier.Kind.FLAT
const PCT := StatModifier.Kind.ADD_PCT
const MUL := StatModifier.Kind.MUL
const MAX := StatModifier.Kind.MAX
const FLAG := StatModifier.Kind.FLAG

var _count: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for file in DirAccess.get_files_at(OUT_DIR):
		if file.ends_with(".tres"):
			DirAccess.remove_absolute(OUT_DIR.path_join(file))

	# TRAVEL (GDD 13.4)
	_node(&"travel.comfy_boots", T, "Comfy Boots", "+3% run speed per level.", 5, [],
			_al_cu(12.0, 5), [StatModifier.make(&"player.run_speed", PCT, 0.03)], Vector2i(0, 0))
	_node(&"travel.springy_soles", T, "Springy Soles", "+10% jump height per level.", 3, [_req(&"travel.comfy_boots", 2)],
			_al(15.0, 3), [StatModifier.make(&"player.jump_height", PCT, 0.10)], Vector2i(0, 1))
	_node(&"travel.zipline_grip", T, "Zipline Grip", "+30% zipline speed per level. Level 2: fire any weapon while riding.", 2,
			[_req(&"travel.comfy_boots", 3)], CostCurve.new().add_part(&"al", 25.0, 1, 2).add_part(&"cu", 10.0, 2, 2),
			[StatModifier.make(&"zipline.speed", PCT, 0.30), StatModifier.make(&"zipline.any_weapon", FLAG, 0.0, PackedFloat32Array([0.0, 1.0]))],
			Vector2i(0, 2))
	_node(&"travel.jetpack", T, "Milk-Can Jetpack", "Grandpa's jetpack. Free after wave 2 of your first run; hold Jump in the air.", 1, [],
			null, [StatModifier.make(&"jetpack.owned", FLAG, 1.0)], Vector2i(1, 0))
	_node(&"travel.fuel_tank", T, "Fuel Tank", "x1.2 flight time per level (compounding).", 10, [_req(&"travel.jetpack")],
			_full(15.0), [StatModifier.make(&"jetpack.flight_time", MUL, 1.2)], Vector2i(1, 1))
	_node(&"travel.quick_refill", T, "Quick Refill", "+15% recharge speed per level. Level 4 also cuts the recharge delay by 0.25 s.", 8,
			[_req(&"travel.jetpack")], _al_to_au(12.0, 8),
			[StatModifier.make(&"jetpack.recharge_speed", PCT, 0.15),
			StatModifier.make(&"jetpack.recharge_delay", FLAT, 0.0, PackedFloat32Array([0, 0, 0, -0.25, -0.25, -0.25, -0.25, -0.25]))],
			Vector2i(2, 1))
	_node(&"travel.thrusters", T, "Thrusters", "+8% jetpack climb rate and air speed per level.", 5, [_req(&"travel.fuel_tank", 2)],
			_al_cu(20.0, 5), [StatModifier.make(&"jetpack.climb_rate", PCT, 0.08), StatModifier.make(&"jetpack.air_speed", PCT, 0.08)],
			Vector2i(1, 2))
	_node(&"travel.hover_mode", T, "Hover Mode", "Hold Jump while aiming to hover, burning fuel at 40%.", 1, [_req(&"travel.fuel_tank", 3)],
			_fixed({&"cu": 25}), [StatModifier.make(&"jetpack.hover", FLAG, 1.0)], Vector2i(2, 2))
	_node(&"travel.death_from_above", T, "Death From Above", "+10% damage while airborne per level.", 5, [_req(&"travel.hover_mode")],
			CostCurve.new().add_part(&"cu", 15.0, 1, 5).add_part(&"au", 3.0, 3, 5).add_part(&"pc", 1.0, 5, 5),
			[StatModifier.make(&"combat.airborne_damage", PCT, 0.10)], Vector2i(2, 3))

	# ATTACK (GDD 13.5)
	_node(&"attack.wrench_damage", A, "Swing Damage", "+12% wrench damage per level.", 10, [],
			_full(12.0), [StatModifier.make(&"wrench.damage", PCT, 0.12)], Vector2i(0, 0))
	_node(&"attack.wrench_speed", A, "Swing Speed", "+8% swing speed per level.", 5, [],
			_al_cu(15.0, 5), [StatModifier.make(&"wrench.swing_rate", PCT, 0.08)], Vector2i(0, 1))
	_node(&"attack.pistol", A, "Rivet Pistol", "A reliable rivet gun: 12 damage, 10 rounds, 40 m.", 1, [],
			_fixed({&"al": 20}), [StatModifier.make(&"pistol.unlocked", FLAG, 1.0)], Vector2i(1, 0))
	_node(&"attack.pistol_damage", A, "Pistol Damage", "+12% pistol damage per level.", 10, [_req(&"attack.pistol")],
			_full(15.0), [StatModifier.make(&"pistol.damage", PCT, 0.12)], Vector2i(1, 1))
	_node(&"attack.pistol_rate", A, "Pistol Fire Rate", "+8% pistol fire rate per level.", 10, [_req(&"attack.pistol")],
			_full(15.0), [StatModifier.make(&"pistol.fire_rate", PCT, 0.08)], Vector2i(2, 1))
	_node(&"attack.pistol_handling", A, "Pistol Handling", "+2 magazine and -8% reload time per level.", 5, [_req(&"attack.pistol")],
			_al_cu(20.0, 5), [StatModifier.make(&"pistol.magazine", FLAT, 2.0), StatModifier.make(&"pistol.reload_time", PCT, -0.08)],
			Vector2i(1, 2))

	# REPAIR (GDD 13.6)
	_node(&"repair.elbow_grease", R, "Elbow Grease", "+15% wrench repair speed per level.", 8, [],
			_al_to_au(12.0, 8), [StatModifier.make(&"repair.speed", PCT, 0.15)], Vector2i(0, 0))
	_node(&"repair.bigger_patches", R, "Bigger Patches", "+10% Structure restored per repair tick per level.", 5,
			[_req(&"repair.elbow_grease", 2)], _al_cu(18.0, 5), [StatModifier.make(&"repair.amount", PCT, 0.10)], Vector2i(0, 1))
	_node(&"repair.leak_plugs", R, "Leak Plugs", "-8% leak rate per crack per level.", 5, [_req(&"repair.elbow_grease", 2)],
			_al_cu(15.0, 5), [StatModifier.make(&"silo.leak_rate", PCT, -0.08)], Vector2i(1, 1))
	_node(&"repair.harvest_helpers", R, "Harvest Helpers", "+16 bushels Harvest Bonus per level (40 -> 120).", 5, [],
			CostCurve.new().add_part(&"al", 15.0, 1, 5).add_part(&"cu", 6.0, 3, 5).add_part(&"au", 2.0, 5, 5),
			[StatModifier.make(&"silo.harvest_bonus", FLAT, 16.0)], Vector2i(2, 0))
	_node(&"repair.bigger_silo", R, "Bigger Silo", "+10% grain capacity per level; Harvest Bonus fills the new space.", 5,
			[_req(&"repair.leak_plugs", 3)], _cu_au(15.0, 5), [StatModifier.make(&"silo.max_grain", PCT, 0.10)], Vector2i(1, 2))
	_node(&"repair.sack_tracker", R, "Sack Tracker", "Grain thieves show through walls; dropped sacks roll home after 5 s.", 1, [],
			_fixed({&"cu": 25}), [StatModifier.make(&"grain.sack_tracker", FLAG, 1.0)], Vector2i(2, 1))

	# DEFEND (GDD 13.7)
	_node(&"defend.hearty_breakfast", D, "Hearty Breakfast", "+10 max HP per level.", 5, [],
			_al_cu(15.0, 5), [StatModifier.make(&"player.max_hp", FLAT, 10.0)], Vector2i(0, 0))
	_node(&"defend.porch_swing", D, "Porch Swing", "+20% Home healing per level.", 5, [],
			_al(12.0, 5), [StatModifier.make(&"home.heal_rate", PCT, 0.20)], Vector2i(0, 1))
	_node(&"defend.armor_overalls", D, "Armor: Overalls", "25 armor. Absorbs damage first; recharges after 4 s.", 1, [],
			_fixed({&"al": 30}), [StatModifier.make(&"player.armor", MAX, 25.0)], Vector2i(1, 0))
	_node(&"defend.armor_vest", D, "Armor: Padded Vest", "50 armor.", 1, [_req(&"defend.armor_overalls")],
			_fixed({&"al": 60, &"cu": 20}), [StatModifier.make(&"player.armor", MAX, 50.0)], Vector2i(1, 1))
	_node(&"defend.armor_regen", D, "Armor Regen", "+15% armor regen rate and -0.4 s regen delay per level.", 5,
			[_req(&"defend.armor_vest")], _cu_au(12.0, 5),
			[StatModifier.make(&"player.armor_regen_rate", PCT, 0.15), StatModifier.make(&"player.armor_regen_delay", FLAT, -0.4)],
			Vector2i(1, 2))
	_node(&"defend.plating_tin", D, "Plating: Tin", "The silo takes 10% less damage.", 1, [],
			_fixed({&"al": 40}), [StatModifier.make(&"silo.damage_reduction", MAX, 0.10)], Vector2i(2, 0))
	_node(&"defend.plating_aluminium", D, "Plating: Aluminium", "The silo takes 18% less damage.", 1,
			[_req(&"defend.plating_tin")], _fixed({&"al": 100, &"cu": 20}), [StatModifier.make(&"silo.damage_reduction", MAX, 0.18)],
			Vector2i(2, 1))
	_node(&"defend.rivet_count", D, "Rivet Count", "+10% silo max Structure per level.", 5, [_req(&"defend.plating_tin")],
			_al_cu(20.0, 5), [StatModifier.make(&"silo.max_structure", PCT, 0.10)], Vector2i(3, 1))
	_node(&"defend.crack_stoppers", D, "Crack Stoppers", "-15% chance per level that damage opens a new crack.", 3,
			[_req(&"defend.rivet_count", 3)], _cu_au(15.0, 3), [StatModifier.make(&"silo.crack_stop_chance", FLAT, 0.15)],
			Vector2i(3, 2))

	# FARMHAND (GDD 13.8)
	_node(&"farmhand.scrap_magnet", F, "Scrap Magnet", "+1.5 m pickup magnet radius per level (base 3 m).", 5, [],
			_al(10.0, 5), [StatModifier.make(&"pickups.magnet_radius", FLAT, 1.5)], Vector2i(0, 0))
	_node(&"farmhand.lucky_horseshoe", F, "Lucky Horseshoe", "+15% (relative) Gold and Power Cell drop chance per level.", 5,
			[_req(&"farmhand.scrap_magnet", 2)], _cu_au(15.0, 5), [StatModifier.make(&"drops.rare_chance", PCT, 0.15)],
			Vector2i(0, 1))
	_node(&"farmhand.scrap_vac", F, "Scrap Vac", "End-of-wave auto-collect: 50% of leftover parts, +10% per level.", 5, [],
			_al_cu(12.0, 5), [StatModifier.make(&"pickups.scrap_vac", FLAT, 0.10)], Vector2i(1, 0))
	_node(&"farmhand.early_bird", F, "Early Bird", "+25 / 50 / 75% Early Bird bonus for ringing the bell early.", 3, [],
			_al_cu(12.0, 3), [StatModifier.make(&"economy.early_bird", PCT, 0.0, PackedFloat32Array([0.25, 0.5, 0.75]))],
			Vector2i(1, 1))

	print("Wrote %d upgrade nodes to %s" % [_count, OUT_DIR])
	quit(0)


func _node(id: StringName, branch: UpgradeNode.Branch, display_name: String, description: String, max_level: int,
		prerequisites: Array[UpgradeRequirement], cost: CostCurve, effects: Array[StatModifier], board_position: Vector2i) -> void:
	var node := UpgradeNode.new()
	node.id = id
	node.branch = branch
	node.display_name = display_name
	node.description = description
	node.max_level = max_level
	node.prerequisites = prerequisites
	node.cost_curve = cost
	node.effects = effects
	node.board_position = board_position
	var path := OUT_DIR.path_join(String(id).replace(".", "_") + ".tres")
	var err := ResourceSaver.save(node, path)
	if err != OK:
		push_error("Could not save %s: %s" % [path, error_string(err)])
	_count += 1


func _req(id: StringName, level: int = 1) -> UpgradeRequirement:
	return UpgradeRequirement.make(id, level)


## "Al -> PC": a 10-level track (Pistol Damage in GDD 12.4 is _full(15)).
func _full(base: float) -> CostCurve:
	return CostCurve.new().add_part(&"al", base, 1, 6).add_part(&"cu", _whole(base * 0.53), 4, 10) \
			.add_part(&"au", _whole(base * 0.27), 7, 10).add_part(&"pc", _whole(base * 0.13), 9, 10)


## "Al -> Au": an 8-level track.
func _al_to_au(base: float, levels: int) -> CostCurve:
	return CostCurve.new().add_part(&"al", base, 1, mini(6, levels)).add_part(&"cu", _whole(base * 0.53), 4, levels) \
			.add_part(&"au", _whole(base * 0.27), 7, levels)


## "Al / Cu" and "Al -> Cu": Aluminium throughout, Copper from level 4.
func _al_cu(base: float, levels: int) -> CostCurve:
	var curve := CostCurve.new().add_part(&"al", base, 1, levels)
	if levels >= 4:
		curve.add_part(&"cu", _whole(base * 0.53), 4, levels)
	return curve


func _al(base: float, levels: int) -> CostCurve:
	return CostCurve.new().add_part(&"al", base, 1, levels)


## "Cu / Au": Copper throughout, Gold for the upper half.
func _cu_au(base: float, levels: int) -> CostCurve:
	return CostCurve.new().add_part(&"cu", base, 1, levels).add_part(&"au", _whole(base * 0.3), ceili(levels / 2.0) + 1, levels)


## Part bases are whole numbers (Pistol Damage: Al 15, Cu 8, Au 4, PC 2).
func _whole(amount: float) -> float:
	return maxf(1.0, roundf(amount))


## A one-off price (unlocks and tiers).
func _fixed(parts: Dictionary[StringName, int]) -> CostCurve:
	var curve := CostCurve.new()
	for part in parts:
		curve.add_part(part, float(parts[part]), 1, 1)
	return curve
