class_name CostCurve
extends Resource
## Part costs per level (GDD 12.4). Each part in the recipe has a base amount, the level it first appears
## at and the last level it's charged at; within that range cost(L) = base * growth^(L - first), rounded.
## Example (Pistol Damage): Al 15 at L1-10, Cu 3 from L4, Au 1 from L7, PC 1 at L9 / 2 at L10.

@export var growth: float = 1.25
@export var parts: Array[StringName] = []
@export var bases: PackedFloat32Array = PackedFloat32Array()
@export var first_levels: PackedInt32Array = PackedInt32Array()
@export var last_levels: PackedInt32Array = PackedInt32Array()


## Parts needed to buy `level` (1-based). Parts with zero cost are left out.
func cost(level: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for i in parts.size():
		if level < first_levels[i] or level > last_levels[i]:
			continue
		var amount := roundi(bases[i] * pow(growth, level - first_levels[i]))
		if amount > 0:
			result[parts[i]] = amount
	return result


func add_part(part: StringName, base: float, first_level: int, last_level: int) -> CostCurve:
	parts.append(part)
	bases.append(base)
	first_levels.append(first_level)
	last_levels.append(last_level)
	return self
