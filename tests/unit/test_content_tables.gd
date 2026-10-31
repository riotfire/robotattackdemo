extends GutTest
## Content tables (data/source, format in its README): the generated .tres files still match the tables,
## and every stat an upgrade modifies is read by some system (the orphan-stat rule, ROADMAP M2-A5, G1).

const ContentTables := preload("res://tools/content_tables.gd")

## Stat keys a node may modify before any system reads them, while the feature's WP is in progress.
## M2-G1 is done only when this is empty.
const PENDING_STATS: Array[StringName] = []
## Where systems read stats: runtime scripts, plus resources and scenes that hold a stat key for a script
## (e.g. a weapon's data naming its damage stat).
const READER_DIRS: PackedStringArray = ["res://scripts", "res://scenes", "res://data"]
## Not readers: the stat plumbing itself, the generated catalog and its source tables.
const NOT_READERS: PackedStringArray = ["res://scripts/autoload/stat_service.gd", "res://scripts/systems/upgrades",
		"res://data/upgrades", "res://data/source"]

var _quoted_key := RegEx.create_from_string("\"([a-z0-9_]+(?:\\.[a-z0-9_]+)+)\"")


func test_tables_read_without_errors() -> void:
	var tables := ContentTables.new()
	tables.upgrade_nodes()
	tables.archetypes()
	tables.themes(tables.palettes())
	tables.traits()
	tables.attacks()
	tables.battle_plans()
	tables.opening_waves()
	tables.defenses()
	assert_true(tables.errors.is_empty(), "table errors:\n" + "\n".join(tables.errors))


func test_opening_waves_match_the_tables() -> void:
	var waves := ContentTables.new().opening_waves()
	assert_eq(waves.size(), 6, "the authored opening covers waves 1-6")
	for opening in waves:
		_assert_matches_file(opening, ContentTables.opening_path(opening.wave), "build_opening_waves.gd")


func test_defenses_match_the_tables() -> void:
	var definitions := ContentTables.new().defenses()
	assert_eq(definitions.size(), 3, "spring trap, decoy and barricade")
	for definition in definitions:
		_assert_matches_file(definition, ContentTables.defense_path(definition.id), "build_defense_data.gd")
		assert_true(StatService.catalog.values().any(func(node: UpgradeNode) -> bool:
				return node.effects.any(func(effect: StatModifier) -> bool: return effect.stat == definition.recipe_flag)),
				"a pegboard node grants the %s recipe" % definition.id)


func test_the_tools_roof_list_matches_the_lobbers() -> void:
	var roofs := PackedStringArray()
	for site in VerticalRobot.ROOF_SITES:
		roofs.append(String(site["path"]))
	assert_eq(roofs, ContentTables.ROOF_PATHS, "tools/content_tables.gd lists the same roofs as VerticalRobot")


func test_upgrade_catalog_matches_the_tables() -> void:
	var nodes := ContentTables.new().upgrade_nodes()
	for node in nodes:
		_assert_matches_file(node, ContentTables.upgrade_path(node.id), "build_upgrade_catalog.gd")
	assert_eq(StatService.catalog.size(), nodes.size(), "data/upgrades holds exactly the table's nodes")


func test_robot_data_matches_the_tables() -> void:
	var tables := ContentTables.new()
	for archetype in tables.archetypes():
		_assert_matches_file(archetype, ContentTables.robot_path("archetypes", archetype.id), "build_robot_data.gd")
	var saved_palettes: Dictionary[StringName, RobotPalette] = {}
	var palettes := tables.palettes()
	for id in palettes:
		var path := ContentTables.robot_path("palettes", id)
		_assert_matches_file(palettes[id], path, "build_robot_data.gd")
		saved_palettes[id] = load(path) as RobotPalette
	var library := load(ContentTables.GENE_LIBRARY_PATH) as GeneLibrary
	var themes := tables.themes(saved_palettes)
	for theme in themes:
		_assert_matches_file(theme, ContentTables.robot_path("themes", theme.id), "build_robot_data.gd")
	assert_eq(library.themes.map(_path), themes.map(func(theme: FamilyTheme) -> String:
			return ContentTables.robot_path("themes", theme.id)), "the gene library lists every theme, in table order")
	for profile in tables.attacks():
		_assert_matches_file(profile, ContentTables.robot_path("attacks", profile.id), "build_robot_data.gd")
	for plan in tables.battle_plans():
		_assert_matches_file(plan, ContentTables.robot_path("battle_plans", plan.id), "build_robot_data.gd")
	for archetype in tables.archetypes():
		if archetype.robot_class != RobotArchetype.RobotClass.MELEE:
			assert_not_null(archetype.ranged_attack(), "%s names an attack profile that exists" % archetype.id)
	var traits := tables.traits()
	for robot_trait in traits:
		_assert_matches_file(robot_trait, ContentTables.robot_path("traits", robot_trait.id), "build_robot_data.gd")
	assert_eq(library.traits.map(_path), traits.map(func(robot_trait: RobotTrait) -> String:
			return ContentTables.robot_path("traits", robot_trait.id)), "the gene library lists every trait, in table order")


func test_every_upgrade_stat_is_read_by_a_system() -> void:
	var read := _stat_keys_in_readers()
	var orphans := PackedStringArray()
	for id in StatService.catalog:
		for modifier in StatService.catalog[id].effects:
			if not read.has(modifier.stat) and modifier.stat not in PENDING_STATS:
				orphans.append("%s (%s)" % [modifier.stat, id])
	assert_true(orphans.is_empty(), "stats no system reads: %s" % ", ".join(orphans))
	for key in PENDING_STATS:
		assert_false(read.has(key), "%s is read by %s now; remove it from PENDING_STATS" % [key, read.get(key, "")])


func test_tables_report_bad_cells() -> void:
	var tables := ContentTables.new()
	var row := {ContentTables.WHERE: "test.csv:2", "id": "travel.test", "branch": "sideways", "display_name": "Test",
		"max_level": "3", "cost": "al_cu twelve; gold 5", "effects": "player.run_speed add_pct 0.1; jump flag; x.y mul [1 2]",
		"prerequisites": "travel.comfy_boots two", "colour": "red"}
	tables._check_columns(row, ContentTables.UPGRADE_COLUMNS)
	var node := tables.upgrade_from_row(row)
	assert_eq(node.effects.size(), 1, "only the good effect is kept")
	var messages := "\n".join(tables.errors)
	for expected in ["unknown column \"colour\"", "branch should be one of", "cost \"al_cu twelve\"", "cost \"gold 5\"",
			"\"jump\" isn't a stat key", "lists 2 values for 3 levels", "prerequisite \"travel.comfy_boots two\""]:
		assert_string_contains(messages, expected)
	assert_true(messages.begins_with("test.csv:2: "), "errors say where the row is")


func test_cost_recipes_keep_common_materials_useful_and_rare_costs_bounded() -> void:
	var tables := ContentTables.new()
	var row := {ContentTables.WHERE: "test.csv:2", "cost": "al_to_pc 15"}
	var curve := tables._cost_curve(row, 10)
	assert_eq(curve.parts, [&"al", &"cu", &"au", &"pc", &"pc"] as Array[StringName])
	assert_eq(Array(curve.bases), [15.0, 3.0, 1.0, 1.0, 2.0])
	assert_eq(Array(curve.first_levels), [1, 4, 7, 9, 10])
	assert_eq(Array(curve.last_levels), [10, 10, 10, 9, 10])
	row["cost"] = "al_cu 12"
	assert_eq(tables._cost_curve(row, 3).parts, [&"al"] as Array[StringName], "no Copper on a 3-level track")
	row["cost"] = "cu_au 15"
	assert_eq(Array(tables._cost_curve(row, 5).first_levels), [1, 4], "Gold for the upper half")
	row["cost"] = "al_cu_au 24"
	var support := tables._cost_curve(row, 5)
	assert_eq(support.cost(1), {&"al": 24, &"cu": 3} as Dictionary[StringName, int])
	assert_eq(support.cost(5).get(&"pc", 0), 0, "support ranks never require Power Cells")
	row["cost"] = "al 60; cu 20"
	var unlock := tables._cost_curve(row, 1)
	assert_eq(unlock.cost(1), {&"al": 60, &"cu": 20} as Dictionary[StringName, int])
	assert_true(tables.errors.is_empty(), "\n".join(tables.errors))


## Every quoted stat-like key ("player.run_speed") in a reader file, mapped to the first file it's in.
func _stat_keys_in_readers() -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = {}
	for dir in READER_DIRS:
		for path in _files_under(dir):
			var text := FileAccess.get_file_as_string(path)
			if path.get_extension() == "gd":
				text = _without_comments(text)
			for result in _quoted_key.search_all(text):
				var key := StringName(result.get_string(1))
				if not found.has(key):
					found[key] = path
	return found


func _files_under(dir: String) -> PackedStringArray:
	var files := PackedStringArray()
	if dir in NOT_READERS:
		return files
	for file_name in DirAccess.get_files_at(dir):
		var path := dir.path_join(file_name)
		if path.get_extension() in ["gd", "tres", "tscn"] and path not in NOT_READERS:
			files.append(path)
	for sub in DirAccess.get_directories_at(dir):
		files.append_array(_files_under(dir.path_join(sub)))
	return files


## GDScript source with "#" comments removed (outside string literals).
func _without_comments(source: String) -> String:
	var lines := PackedStringArray()
	for line in source.split("\n"):
		var quote := ""
		var cut := line.length()
		var i := 0
		while i < line.length():
			var c := line[i]
			if quote.is_empty() and c == "#":
				cut = i
				break
			if c == "\\" and not quote.is_empty():
				i += 1
			elif c == "\"" or c == "'":
				quote = c if quote.is_empty() else ("" if quote == c else quote)
			i += 1
		lines.append(line.substr(0, cut))
	return "\n".join(lines)


func _assert_matches_file(expected: Resource, path: String, tool_name: String) -> void:
	if not ResourceLoader.exists(path):
		fail_test("%s is missing; run tools/%s" % [path, tool_name])
		return
	var saved := load(path)
	var differences := PackedStringArray()
	if saved.get_script() != expected.get_script():
		differences.append("it's a %s, not a %s" % [saved.get_script().get_global_name(), expected.get_script().get_global_name()])
	else:
		for property in ContentTables.exported_properties(expected):
			_diff(saved.get(property.name), expected.get(property.name), property.name, differences)
	assert_true(differences.is_empty(), "%s differs from its table row (edit the table and run tools/%s):\n%s" % [
			path, tool_name, "\n".join(differences)])


## Collects the differences between two values, following sub-resources and arrays. Resources saved in
## their own file are compared by path.
func _diff(actual: Variant, expected: Variant, label: String, out: PackedStringArray) -> void:
	if actual is Resource and expected is Resource:
		var a := actual as Resource
		var e := expected as Resource
		if _is_external(a) or _is_external(e):
			if a.resource_path != e.resource_path:
				out.append("%s: %s, table says %s" % [label, a.resource_path, e.resource_path])
		elif a.get_script() != e.get_script():
			out.append("%s: a %s, table says a %s" % [label, a.get_script(), e.get_script()])
		else:
			for property in ContentTables.exported_properties(e):
				_diff(a.get(property.name), e.get(property.name), "%s.%s" % [label, property.name], out)
	elif actual is Array and expected is Array:
		if (actual as Array).size() != (expected as Array).size():
			out.append("%s: %d items, table says %d" % [label, (actual as Array).size(), (expected as Array).size()])
			return
		for i in (expected as Array).size():
			_diff(actual[i], expected[i], "%s[%d]" % [label, i], out)
	elif typeof(actual) != typeof(expected) or actual != expected:
		out.append("%s: %s, table says %s" % [label, var_to_str(actual), var_to_str(expected)])


func _is_external(resource: Resource) -> bool:
	return not resource.resource_path.is_empty() and not resource.resource_path.contains("::")


func _path(resource: Resource) -> String:
	return resource.resource_path
