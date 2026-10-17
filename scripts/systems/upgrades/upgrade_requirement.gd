class_name UpgradeRequirement
extends Resource
## A prerequisite: another node at a minimum level (the red yarn on the pegboard, GDD 13.1).

@export var node_id: StringName = &""
@export var level: int = 1


static func make(required_id: StringName, required_level: int = 1) -> UpgradeRequirement:
	var requirement := UpgradeRequirement.new()
	requirement.node_id = required_id
	requirement.level = required_level
	return requirement
