class_name StatModifier
extends Resource
## One effect of an upgrade node on one stat key (GDD 18.4), applied per purchased level.
## StatService folds all modifiers of a key into: max((base + FLAT) * (1 + ADD_PCT) * MUL, MAX), and
## FLAG keys read as unlocked when any owner has level >= 1.

enum Kind { FLAT, ADD_PCT, MUL, MAX, FLAG }

@export var stat: StringName = &""
@export var kind: Kind = Kind.ADD_PCT
## Per level: FLAT and ADD_PCT add `value` each level, MUL compounds `value` each level, MAX and FLAG
## use it once the node is owned.
@export var value: float = 0.0
## Optional explicit total per level (index 0 = level 1). Overrides `value` when not empty,
## e.g. Early Bird +25 / 50 / 75%.
@export var per_level: PackedFloat32Array = PackedFloat32Array()


## The modifier's total contribution at `level` (0 = not owned).
func value_at(level: int) -> float:
	if level <= 0:
		return 0.0
	if not per_level.is_empty():
		return per_level[mini(level, per_level.size()) - 1]
	match kind:
		Kind.FLAT, Kind.ADD_PCT:
			return value * level
		Kind.MUL:
			return pow(value, level)
	return value


static func make(stat_key: StringName, modifier_kind: Kind, amount: float, levels: PackedFloat32Array = PackedFloat32Array()) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat_key
	modifier.kind = modifier_kind
	modifier.value = amount
	modifier.per_level = levels
	return modifier
