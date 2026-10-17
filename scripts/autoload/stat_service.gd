extends Node
## Final stats from base values plus purchased upgrades (GDD 18.2, 18.4). Owns the upgrade catalog
## (every UpgradeNode .tres in data/upgrades) and the purchased levels, which SaveManager persists.
## Systems ask get_stat(&"key", base) / has_flag(&"key") and never look at levels themselves.

signal stats_changed

const UPGRADE_DIR := "res://data/upgrades"

var catalog: Dictionary[StringName, UpgradeNode] = {}
## Purchased level per node id.
var levels: Dictionary[StringName, int] = {}

## stat key -> [flat, add_pct, mul, max, has_max]
var _stacks: Dictionary[StringName, PackedFloat32Array] = {}


func _ready() -> void:
	load_catalog()


func load_catalog() -> void:
	catalog.clear()
	if not DirAccess.dir_exists_absolute(UPGRADE_DIR):
		return
	for file in ResourceLoader.list_directory(UPGRADE_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var node := load(UPGRADE_DIR.path_join(file)) as UpgradeNode
		if node != null and node.id != &"":
			catalog[node.id] = node
	_rebuild()


func get_stat(key: StringName, base: float) -> float:
	if not _stacks.has(key):
		return base
	var s := _stacks[key]
	var value := (base + s[0]) * (1.0 + s[1]) * s[2]
	return maxf(value, s[3]) if s[4] > 0.0 else value


func has_flag(key: StringName) -> bool:
	return _stacks.has(key) and _stacks[key][4] > 0.0


func level_of(id: StringName) -> int:
	return levels.get(id, 0)


func is_maxed(id: StringName) -> bool:
	return catalog.has(id) and level_of(id) >= catalog[id].max_level


func prerequisites_met(id: StringName) -> bool:
	if not catalog.has(id):
		return false
	for requirement in catalog[id].prerequisites:
		if level_of(requirement.node_id) < requirement.level:
			return false
	return true


## Cost of the next level, or an empty dictionary when maxed.
func next_cost(id: StringName) -> Dictionary[StringName, int]:
	if not catalog.has(id) or is_maxed(id) or catalog[id].cost_curve == null:
		return {}
	return catalog[id].cost_curve.cost(level_of(id) + 1)


func can_afford(cost: Dictionary[StringName, int]) -> bool:
	for part in cost:
		if GameState.parts.get(part, 0) < cost[part]:
			return false
	return true


func can_purchase(id: StringName) -> bool:
	return catalog.has(id) and not is_maxed(id) and prerequisites_met(id) and can_afford(next_cost(id))


## Buys the next level of `id`, spending parts from the bank. Returns true on success.
func purchase(id: StringName) -> bool:
	if not can_purchase(id):
		return false
	var cost := next_cost(id)
	var spend: Dictionary = {}
	for part in cost:
		spend[part] = -cost[part]
	GameState.add_parts(spend)
	levels[id] = level_of(id) + 1
	_rebuild()
	EventBus.upgrade_purchased.emit(id, levels[id])
	return true


## Sets a node's level without spending parts (free unlocks such as the jetpack, debug cheats).
func grant(id: StringName, level: int = 1) -> void:
	if level <= 0:
		levels.erase(id)
	else:
		levels[id] = level
	_rebuild()


## Replaces all levels (from a save, or a debug reset).
func set_levels(new_levels: Dictionary) -> void:
	levels.clear()
	for key: Variant in new_levels:
		if int(new_levels[key]) > 0:
			levels[StringName(str(key))] = int(new_levels[key])
	_rebuild()


func _rebuild() -> void:
	_stacks.clear()
	for id in levels:
		if not catalog.has(id):
			continue
		var level := mini(levels[id], catalog[id].max_level)
		for modifier in catalog[id].effects:
			if modifier == null or modifier.stat == &"":
				continue
			if not _stacks.has(modifier.stat):
				_stacks[modifier.stat] = PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0])
			var s := _stacks[modifier.stat]
			var amount := modifier.value_at(level)
			match modifier.kind:
				StatModifier.Kind.FLAT:
					s[0] += amount
				StatModifier.Kind.ADD_PCT:
					s[1] += amount
				StatModifier.Kind.MUL:
					s[2] *= amount
				StatModifier.Kind.MAX:
					s[3] = maxf(s[3], amount) if s[4] > 0.0 else amount
					s[4] = 1.0
				StatModifier.Kind.FLAG:
					if amount > 0.0:
						s[4] = 1.0
			_stacks[modifier.stat] = s
	stats_changed.emit()
