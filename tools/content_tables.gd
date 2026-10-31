extends RefCounted
## Reads the content tables in res://data/source (format: data/source/README.md) and builds resources
## from their rows. The tools/build_*.gd generators save those resources as the .tres files in data/,
## and tests/unit/test_content_tables.gd builds them again to check the .tres files still match.
##
## A table is a folder of .csv files, read in file-name order, each starting with its own header row.
## Columns are matched by name, a blank cell keeps the script default, and a row whose first cell
## starts with "#" is skipped.

const SOURCE_DIR := "res://data/source"
const UPGRADES := "upgrades"
const ARCHETYPES := "robots/archetypes"
const PALETTES := "robots/palettes"
const THEMES := "robots/themes"
const TRAITS := "robots/traits"
const ATTACKS := "robots/attacks"
const BATTLE_PLANS := "robots/battle_plans"
const OPENING_WAVES := "opening/waves"
const OPENING_GROUPS := "opening/groups"
const DEFENSES := "defenses"

const UPGRADE_DIR := "res://data/upgrades"
const ROBOT_DIR := "res://data/robots"
const GENE_LIBRARY_PATH := "res://data/robots/gene_library.tres"
const OPENING_DIR := "res://data/opening"
const DEFENSE_DIR := "res://data/defenses"
const OPENING_GROUP_COLUMNS: PackedStringArray = ["wave", "group", "release", "after", "lane", "members", "roof", "intro",
		"announce", "note"]
const OPENING_ROLES: Array[StringName] = [&"", &"thief", &"foreman", &"calm"]
## The roofs Lobbers can climb (VerticalRobot.ROOF_SITES paths; test_content_tables.gd keeps the two in step).
## Listed here so the tools never load robot scripts, which need the game's autoloads.
const ROOF_PATHS: PackedStringArray = ["ToolShed", "Barn", "Stables", "ChickenHouse"]

const UPGRADE_COLUMNS: PackedStringArray = ["id", "branch", "board_col", "board_row", "display_name", "max_level",
		"prerequisites", "cost", "effects", "description"]
## Cost recipes named after the GDD 13 "Recipe" column ("Al -> PC" is al_to_pc). See _add_recipe.
const RECIPES: PackedStringArray = ["al_to_pc", "al_to_au", "al_cu", "cu_au", "al_cu_au"]
const PARTS: PackedStringArray = ["al", "cu", "au", "pc"]

## Added to every row: "file.csv:line", for error messages.
const WHERE := "@where"

## Problems found so far, each starting with "file.csv:line:". Generators refuse to write while it isn't empty.
var errors: PackedStringArray = []

var _stat_key := RegEx.create_from_string("^[a-z0-9_]+(\\.[a-z0-9_]+)+$")


# --- Reading tables ---------------------------------------------------------------------------------

## Every row of the table in `folder` (relative to SOURCE_DIR), as column name -> cell text.
func read_table(folder: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var dir := SOURCE_DIR.path_join(folder)
	if not DirAccess.dir_exists_absolute(dir):
		errors.append("%s: missing table folder" % dir)
		return rows
	var names := Array(DirAccess.get_files_at(dir))
	names.sort()
	for file_name: String in names:
		if file_name.get_extension() == "csv":
			rows.append_array(_read_csv(dir.path_join(file_name)))
	return rows


func cell(row: Dictionary, column: String) -> String:
	return str(row.get(column, ""))


func _read_csv(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("%s: %s" % [path, error_string(FileAccess.get_open_error())])
		return rows
	var header := PackedStringArray()
	var line := 0
	while not file.eof_reached():
		var cells := file.get_csv_line()
		line += 1
		var where := "%s:%d" % [path.get_file(), line]
		if "".join(cells).strip_edges().is_empty() or cells[0].strip_edges().begins_with("#"):
			continue
		if header.is_empty():
			# Spreadsheet exports may start with a byte-order mark and end rows with empty columns.
			cells[0] = cells[0].trim_prefix(char(0xFEFF))
			for name in cells:
				if not name.strip_edges().is_empty() and name.strip_edges() in header:
					errors.append("%s: column \"%s\" appears twice" % [where, name.strip_edges()])
				header.append(name.strip_edges())
			continue
		if cells.size() > header.size():
			errors.append("%s: %d cells, but the header has %d columns" % [where, cells.size(), header.size()])
			continue
		var row: Dictionary[String, String] = {WHERE: where}
		for i in header.size():
			if not header[i].is_empty():
				row[header[i]] = cells[i].strip_edges() if i < cells.size() else ""
		rows.append(row)
	return rows


## Splits a list cell into its items: "a 1; b 2" -> ["a 1", "b 2"].
func _items(text: String) -> PackedStringArray:
	var items := PackedStringArray()
	for item in text.split(";"):
		if not item.strip_edges().is_empty():
			items.append(item.strip_edges())
	return items


func _error(row: Dictionary, message: String) -> void:
	errors.append("%s: %s" % [cell(row, WHERE), message])


func _check_columns(row: Dictionary, known: PackedStringArray) -> void:
	for column: String in row:
		if column != WHERE and column not in known:
			_error(row, "unknown column \"%s\"" % column)


func _required(row: Dictionary, column: String) -> String:
	if cell(row, column).is_empty():
		_error(row, "%s is required" % column)
	return cell(row, column)


func _int(row: Dictionary, column: String, default: int) -> int:
	var text := cell(row, column)
	if text.is_empty():
		return default
	if not text.is_valid_int():
		_error(row, "%s should be a whole number, not \"%s\"" % [column, text])
		return default
	return int(text)


## An enum cell by name, case-insensitive ("travel", "short_range"). `names` is the enum's dictionary.
func _enum_value(row: Dictionary, column: String, names: Dictionary) -> int:
	var text := cell(row, column)
	var key := text.to_upper().replace(" ", "_")
	if names.has(key):
		return names[key]
	var options := PackedStringArray()
	for name: String in names:
		options.append(name.to_lower())
	_error(row, "%s should be one of %s, not \"%s\"" % [column, ", ".join(options), text])
	return 0


# --- Generic rows: one column per exported property ---------------------------------------------------

## The script's exported properties, in declaration order.
static func exported_properties(resource: Resource) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			result.append(property)
	return result


## Sets `resource`'s exported properties from the cells of the same name. Blank cells keep the script
## default, and columns in `skip` are left to the caller. Returns the names of the properties it set,
## in declaration order.
func fill(resource: Resource, row: Dictionary, skip: PackedStringArray = []) -> PackedStringArray:
	var properties := exported_properties(resource)
	var known := skip.duplicate()
	for property in properties:
		known.append(property.name)
	_check_columns(row, known)
	var assigned := PackedStringArray()
	for property in properties:
		var text := cell(row, property.name)
		if property.name in skip or text.is_empty():
			continue
		var value: Variant = _parse(row, property, text)
		if value != null:
			resource.set(property.name, value)
			assigned.append(property.name)
	return assigned


## A cell as the property's type: numbers, true/false, enum names, colors ("0.6 0.28 0.15" or
## "#rrggbb"), space-separated word lists for Array[StringName], and res:// paths for resources.
func _parse(row: Dictionary, property: Dictionary, text: String) -> Variant:
	var column: String = property.name
	match property.type:
		TYPE_STRING:
			return text
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_INT:
			if property.hint == PROPERTY_HINT_ENUM:
				var names: Dictionary[String, int] = {}
				for option: String in String(property.hint_string).split(","):
					names[option.get_slice(":", 0).to_upper().replace(" ", "_")] = int(option.get_slice(":", 1))
				return _enum_value(row, column, names)
			if text.is_valid_int():
				return int(text)
		TYPE_FLOAT:
			if text.is_valid_float():
				return float(text)
		TYPE_BOOL:
			if text.to_lower() in ["true", "false"]:
				return text.to_lower() == "true"
		TYPE_COLOR:
			if text.begins_with("#") and Color.html_is_valid(text):
				return Color.html(text)
			var parts := text.split(" ", false)
			if parts.size() in [3, 4] and Array(parts).all(func(part: String) -> bool: return part.is_valid_float()):
				return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() == 4 else 1.0)
		TYPE_ARRAY:
			if String(property.hint_string).begins_with("%d:" % TYPE_STRING_NAME):
				var words := Array([], TYPE_STRING_NAME, &"", null)
				for word in text.split(" ", false):
					words.append(StringName(word))
				return words
		TYPE_OBJECT:
			if text.begins_with("res://") and ResourceLoader.exists(text):
				return load(text)
			_error(row, "%s should be the res:// path of an existing file, not \"%s\"" % [column, text])
			return null
	_error(row, "%s can't be \"%s\" (%s)" % [column, text, type_string(property.type)])
	return null


# --- Pegboard ---------------------------------------------------------------------------------------

static func upgrade_path(id: StringName) -> String:
	return UPGRADE_DIR.path_join(String(id).replace(".", "_") + ".tres")


## The pegboard: one UpgradeNode per row of data/source/upgrades.
func upgrade_nodes() -> Array[UpgradeNode]:
	var nodes: Array[UpgradeNode] = []
	var where_by_id: Dictionary[StringName, String] = {}
	var id_by_peg: Dictionary[Vector3i, StringName] = {}
	for row in read_table(UPGRADES):
		_check_columns(row, UPGRADE_COLUMNS)
		var node := upgrade_from_row(row)
		if where_by_id.has(node.id):
			_error(row, "%s is already defined at %s" % [node.id, where_by_id[node.id]])
			continue
		where_by_id[node.id] = cell(row, WHERE)
		var peg := Vector3i(node.branch, node.board_position.x, node.board_position.y)
		if id_by_peg.has(peg):
			_error(row, "%s is on the same peg as %s" % [node.id, id_by_peg[peg]])
		id_by_peg[peg] = node.id
		nodes.append(node)
	var max_levels: Dictionary[StringName, int] = {}
	for node in nodes:
		max_levels[node.id] = node.max_level
	for node in nodes:
		for requirement in node.prerequisites:
			if not max_levels.has(requirement.node_id):
				errors.append("%s: %s requires %s, which isn't in the tables" % [where_by_id[node.id], node.id, requirement.node_id])
			elif requirement.level > max_levels[requirement.node_id]:
				errors.append("%s: %s requires %s level %d, but it only has %d" % [where_by_id[node.id], node.id,
						requirement.node_id, requirement.level, max_levels[requirement.node_id]])
	return nodes


func upgrade_from_row(row: Dictionary) -> UpgradeNode:
	var node := UpgradeNode.new()
	node.id = StringName(_required(row, "id"))
	node.branch = _enum_value(row, "branch", UpgradeNode.Branch) as UpgradeNode.Branch
	node.board_position = Vector2i(_int(row, "board_col", 0), _int(row, "board_row", 0))
	node.display_name = _required(row, "display_name")
	node.description = cell(row, "description")
	node.max_level = _int(row, "max_level", 1)
	if node.max_level < 1:
		_error(row, "max_level should be at least 1")
		node.max_level = 1
	node.prerequisites = _prerequisites(row)
	node.cost_curve = _cost_curve(row, node.max_level)
	node.effects = _effects(row, node.max_level)
	return node


## "travel.comfy_boots 2; travel.jetpack": node id and minimum level (default 1).
func _prerequisites(row: Dictionary) -> Array[UpgradeRequirement]:
	var result: Array[UpgradeRequirement] = []
	for item in _items(cell(row, "prerequisites")):
		var words := item.split(" ", false)
		if words.size() > 2 or (words.size() == 2 and not words[1].is_valid_int()):
			_error(row, "prerequisite \"%s\" should be \"<node id> [level]\"" % item)
			continue
		result.append(UpgradeRequirement.make(StringName(words[0]), int(words[1]) if words.size() == 2 else 1))
	return result


## "al_cu 12" (a recipe and its base), "al 25 1-2; cu 10 2-2" (part, base, first-last level; the levels
## default to all of them), or a mix. Blank: free (no cost curve).
func _cost_curve(row: Dictionary, levels: int) -> CostCurve:
	var text := cell(row, "cost")
	if text.is_empty():
		return null
	var curve := CostCurve.new()
	for item in _items(text):
		var words := item.split(" ", false)
		var usage := "cost \"%s\" should be \"<recipe> <base>\" or \"<part> <base> [first-last]\"" % item
		if words.size() < 2 or not words[1].is_valid_float():
			_error(row, usage)
		elif words[0] in RECIPES and words.size() == 2:
			_add_recipe(curve, words[0], float(words[1]), levels)
		elif words[0] in PARTS and words.size() <= 3:
			var first := 1
			var last := levels
			if words.size() == 3:
				var bounds := words[2].split("-")
				if bounds.size() != 2 or not bounds[0].is_valid_int() or not bounds[1].is_valid_int():
					_error(row, usage)
					continue
				first = int(bounds[0])
				last = int(bounds[1])
			if first < 1 or first > last or last > levels:
				_error(row, "cost \"%s\": levels %d-%d don't fit in 1-%d" % [item, first, last, levels])
				continue
			curve.add_part(StringName(words[0]), float(words[1]), first, last)
		else:
			_error(row, usage + " (recipes: %s; parts: %s)" % [", ".join(RECIPES), ", ".join(PARTS)])
	return curve


## Keep Aluminium useful at every rank; rare materials supplement the common-metal investment.
## Copper starts at 20% of the Al base, Gold at 6.7%; each grows only after its first charged rank.
## Power Cells are deliberate finishers: one at rank 9 and two at rank 10, rather than a growing tax.
## al_cu_au brings formerly Copper-only support tracks into the same mixed-material economy.
## cu_au remains supported for older/custom tables; the live catalog uses al_cu_au instead.
func _add_recipe(curve: CostCurve, recipe: String, base: float, levels: int) -> void:
	match recipe:
		"al_to_pc", "al_to_au":
			curve.add_part(&"al", base, 1, levels)
			_add_part_from(curve, &"cu", _whole(base * 0.2), 4, levels)
			_add_part_from(curve, &"au", _whole(base * 0.067), 7, levels)
			if recipe == "al_to_pc":
				_add_part_from(curve, &"pc", 1.0, 9, mini(9, levels))
				_add_part_from(curve, &"pc", 2.0, 10, levels)
		"al_cu":
			curve.add_part(&"al", base, 1, levels)
			_add_part_from(curve, &"cu", _whole(base * 0.2), 4, levels)
		"al_cu_au":
			curve.add_part(&"al", base, 1, levels)
			curve.add_part(&"cu", _whole(base * 0.125), 1, levels)
			_add_part_from(curve, &"au", _whole(base * 0.04), ceili(levels / 2.0) + 1, levels)
		"cu_au":
			curve.add_part(&"cu", base, 1, levels)
			_add_part_from(curve, &"au", _whole(base * 0.3), ceili(levels / 2.0) + 1, levels)


func _add_part_from(curve: CostCurve, part: StringName, base: float, first: int, last: int) -> void:
	if first <= last:
		curve.add_part(part, base, first, last)


## Part bases are whole numbers.
func _whole(amount: float) -> float:
	return maxf(1.0, roundf(amount))


## "player.run_speed add_pct 0.03; jetpack.hover flag": stat key, StatModifier kind (flat, add_pct, mul,
## max, flag) and the per-level value, or a list with one total per level ("[0 0 0 -0.25]"). A flag's
## value defaults to 1.
func _effects(row: Dictionary, levels: int) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for item in _items(cell(row, "effects")):
		var words := item.replace("[", " [ ").replace("]", " ] ").split(" ", false)
		if words.size() < 2 or not StatModifier.Kind.has(words[1].to_upper()):
			_error(row, "effect \"%s\" should be \"<stat> <kind> <value>\", kind one of flat, add_pct, mul, max, flag" % item)
			continue
		if _stat_key.search(words[0]) == null:
			_error(row, "effect \"%s\": \"%s\" isn't a stat key like player.run_speed" % [item, words[0]])
			continue
		var kind: StatModifier.Kind = StatModifier.Kind[words[1].to_upper()]
		var rest := words.slice(2)
		var value := 0.0
		var per_level := PackedFloat32Array()
		if rest.size() >= 2 and rest[0] == "[" and rest[rest.size() - 1] == "]":
			var numbers := rest.slice(1, rest.size() - 1)
			if not Array(numbers).all(func(word: String) -> bool: return word.is_valid_float()):
				_error(row, "effect \"%s\": the per-level list should only hold numbers" % item)
				continue
			if numbers.size() != levels:
				_error(row, "effect \"%s\" lists %d values for %d levels" % [item, numbers.size(), levels])
				continue
			for word in numbers:
				per_level.append(float(word))
		elif rest.size() == 1 and rest[0].is_valid_float():
			value = float(rest[0])
		elif rest.is_empty() and kind == StatModifier.Kind.FLAG:
			value = 1.0
		else:
			_error(row, "effect \"%s\" needs one number or a [per-level list]" % item)
			continue
		result.append(StatModifier.make(StringName(words[0]), kind, value, per_level))
	return result


# --- Robots -----------------------------------------------------------------------------------------

static func robot_path(kind: String, id: StringName) -> String:
	return ROBOT_DIR.path_join(kind).path_join("%s.tres" % id)


## The archetypes (GDD 9.3): one column per RobotArchetype property.
func archetypes() -> Array[RobotArchetype]:
	var result: Array[RobotArchetype] = []
	for row in archetype_rows():
		var archetype := RobotArchetype.new()
		fill(archetype, row)
		result.append(archetype)
	return result


func archetype_rows() -> Array[Dictionary]:
	return _unique_rows(ARCHETYPES)


## The robot attack profiles (M2-B7): one column per AttackProfile property. Reports archetypes that name
## a profile the table doesn't have.
func attacks() -> Array[AttackProfile]:
	var result: Array[AttackProfile] = []
	var ids: Array[StringName] = []
	for row in _unique_rows(ATTACKS):
		var profile := AttackProfile.new()
		fill(profile, row)
		if profile.charge_time < AttackProfile.MIN_CHARGE_TIME:
			_error(row, "charge_time can't be under %.2f s (fairness rule)" % AttackProfile.MIN_CHARGE_TIME)
		result.append(profile)
		ids.append(profile.id)
	for row in archetype_rows():
		var attack := StringName(cell(row, "ranged_attack_id"))
		if not attack.is_empty() and attack not in ids:
			_error(row, "ranged_attack_id \"%s\" isn't in %s" % [attack, ATTACKS])
	return result


## Palettes by id (the file name; GDD 10.1), in table order.
func palettes() -> Dictionary[StringName, RobotPalette]:
	var result: Dictionary[StringName, RobotPalette] = {}
	for row in _unique_rows(PALETTES):
		var palette := RobotPalette.new()
		fill(palette, row, ["id"])
		result[StringName(cell(row, "id"))] = palette
	return result


## Themes (GDD 10.1), whose "palettes" column lists palette ids looked up in `palettes_by_id`.
func themes(palettes_by_id: Dictionary[StringName, RobotPalette]) -> Array[FamilyTheme]:
	var result: Array[FamilyTheme] = []
	for row in _unique_rows(THEMES):
		var theme := FamilyTheme.new()
		fill(theme, row, ["palettes"])
		var picked: Array[RobotPalette] = []
		for id in cell(row, "palettes").split(" ", false):
			if palettes_by_id.has(StringName(id)):
				picked.append(palettes_by_id[StringName(id)])
			else:
				_error(row, "palette \"%s\" isn't in data/source/%s" % [id, PALETTES])
		theme.palettes = picked
		result.append(theme)
	return result


## Traits (GDD 10.3).
func traits() -> Array[RobotTrait]:
	var result: Array[RobotTrait] = []
	for row in _unique_rows(TRAITS):
		var robot_trait := RobotTrait.new()
		fill(robot_trait, row)
		result.append(robot_trait)
	return result


## Battle plans (M2-B11): one column per BattlePlan property.
func battle_plans() -> Array[BattlePlan]:
	var result: Array[BattlePlan] = []
	for row in _unique_rows(BATTLE_PLANS):
		var plan := BattlePlan.new()
		fill(plan, row)
		result.append(plan)
	return result


## The table's rows, reporting rows without an id and ids defined twice (ids name the .tres files).
func _unique_rows(folder: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var where_by_id: Dictionary[String, String] = {}
	for row in read_table(folder):
		var id := _required(row, "id")
		if id.is_empty():
			continue
		if where_by_id.has(id):
			_error(row, "%s is already defined at %s" % [id, where_by_id[id]])
			continue
		where_by_id[id] = cell(row, WHERE)
		rows.append(row)
	return rows


# --- Authored opening (OpeningWave) ------------------------------------------------------------------

static func opening_path(wave: int) -> String:
	return OPENING_DIR.path_join("wave_%d.tres" % wave)


## The authored opening: one OpeningWave per row of opening/waves.csv, holding its rows of opening/groups.csv.
## Reports unknown archetypes and roofs, gaps in the group numbers and "after" rules that point forward.
func opening_waves() -> Array[OpeningWave]:
	var archetype_ids: Array[String] = []
	for row in archetype_rows():
		archetype_ids.append(cell(row, "id"))
	var by_wave: Dictionary[int, OpeningWave] = {}
	var waves: Array[OpeningWave] = []
	for row in read_table(OPENING_WAVES):
		var opening := OpeningWave.new()
		fill(opening, row, ["lane_pool"])
		for lane in cell(row, "lane_pool").split(" ", false):
			if lane.is_valid_int():
				opening.lane_pool.append(int(lane))
			else:
				_error(row, "lane_pool should list lane numbers, not \"%s\"" % lane)
		if by_wave.has(opening.wave):
			_error(row, "wave %d is already defined" % opening.wave)
			continue
		by_wave[opening.wave] = opening
		waves.append(opening)
	var roofs := ROOF_PATHS
	for row in read_table(OPENING_GROUPS):
		_check_columns(row, OPENING_GROUP_COLUMNS)
		var wave := _int(row, "wave", 0)
		if not by_wave.has(wave):
			_error(row, "wave %d isn't in %s" % [wave, OPENING_WAVES])
			continue
		var opening := by_wave[wave]
		var index := _int(row, "group", -1)
		if index != opening.groups.size():
			_error(row, "groups of wave %d should be numbered 0, 1, 2, ... in order (expected %d)" % [wave, opening.groups.size()])
			continue
		var group := OpeningGroup.new()
		group.resource_scene_unique_id = "group_%d" % index
		group.lane_slot = _int(row, "lane", 0)
		if group.lane_slot < 0 or group.lane_slot > 2:
			_error(row, "lane should be 0 or 1 (the main lanes) or 2 (a third direction)")
		var after := cell(row, "after")
		if after.is_empty():
			var release := cell(row, "release")
			if not release.is_valid_float():
				_error(row, "release should be the seconds after the siren, or set \"after\" (\"<group>+<seconds>\")")
			group.release_time = float(release) if release.is_valid_float() else 0.0
		else:
			var parts := after.split("+")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_float() or int(parts[0]) >= index:
				_error(row, "after \"%s\" should be \"<an earlier group>+<seconds>\"" % after)
			else:
				group.after_group = int(parts[0])
				group.after_delay = float(parts[1])
		for member in _items(cell(row, "members")):
			var words := member.split(" ", false)
			if words.size() < 2 or words.size() > 3 or not words[1].is_valid_int() or int(words[1]) < 1:
				_error(row, "member \"%s\" should be \"<archetype> <count> [thief|foreman|calm]\"" % member)
				continue
			if words[0] not in archetype_ids:
				_error(row, "archetype \"%s\" isn't in data/source/%s" % [words[0], ARCHETYPES])
			var role := StringName(words[2]) if words.size() == 3 else &""
			if role not in OPENING_ROLES:
				_error(row, "member \"%s\": the role should be thief, foreman or calm" % member)
			group.archetype_ids.append(StringName(words[0]))
			group.counts.append(int(words[1]))
			group.roles.append(role)
		if group.archetype_ids.is_empty():
			_error(row, "a group needs at least one member")
		group.roof = StringName(cell(row, "roof"))
		if not group.roof.is_empty() and String(group.roof) not in roofs:
			_error(row, "roof \"%s\" should be one of %s" % [group.roof, ", ".join(roofs)])
		group.intro = StringName(cell(row, "intro"))
		group.announce = cell(row, "announce").to_lower() == "true"
		opening.groups.append(group)
	for opening in waves:
		if opening.groups.is_empty():
			errors.append("%s: wave %d has no groups in %s" % [OPENING_WAVES, opening.wave, OPENING_GROUPS])
	waves.sort_custom(func(a: OpeningWave, b: OpeningWave) -> bool: return a.wave < b.wave)
	for i in waves.size():
		if waves[i].wave != i + 1:
			errors.append("%s: the opening should cover waves 1-%d without gaps" % [OPENING_WAVES, waves.size()])
			break
	return waves


# --- Defenses (DefenseDefinition) -------------------------------------------------------------------

static func defense_path(id: StringName) -> String:
	return DEFENSE_DIR.path_join("%s.tres" % id)


## The buildable defenses: one column per DefenseDefinition property. Reports site kinds that don't exist.
func defenses() -> Array[DefenseDefinition]:
	var result: Array[DefenseDefinition] = []
	for row in _unique_rows(DEFENSES.path_join("items")):
		var definition := DefenseDefinition.new()
		fill(definition, row)
		for kind in definition.site_kinds:
			if kind not in DefenseDefinition.SITE_KINDS:
				_error(row, "site_kinds: \"%s\" should be one of %s" % [kind, ", ".join(DefenseDefinition.SITE_KINDS)])
		if definition.cost_al < 1:
			_error(row, "cost_al should be at least 1 (every copy costs parts)")
		if definition.assembly_time <= 0.0:
			_error(row, "assembly_time should be above 0 (no perk may skip construction)")
		result.append(definition)
	return result


# --- Writing ----------------------------------------------------------------------------------------

## Deletes the .tres files in `dir` that aren't in `keep` (rows removed from a table). Returns their names.
static func remove_stale(dir: String, keep: PackedStringArray) -> PackedStringArray:
	var removed := PackedStringArray()
	for file_name in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "tres" and file_name not in keep:
			DirAccess.remove_absolute(dir.path_join(file_name))
			removed.append(file_name)
	return removed
