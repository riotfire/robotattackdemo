class_name UpgradeNode
extends Resource
## One tool on the pegboard (GDD 13, 18.5). Systems never read levels directly; they read stats from
## StatService, which folds every owned node's effects into modifier stacks.

## BUILD: defense recipes and the trapper's upgrades (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md).
enum Branch { TRAVEL, ATTACK, REPAIR, DEFEND, FARMHAND, BUILD }

const BRANCH_NAMES: PackedStringArray = ["Travel", "Attack", "Repair", "Defend", "Farmhand", "Build"]

@export var id: StringName = &""
@export var branch: Branch = Branch.TRAVEL
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var max_level: int = 1
@export var prerequisites: Array[UpgradeRequirement] = []
@export var cost_curve: CostCurve
@export var effects: Array[StatModifier] = []
## Column and row of the peg on its branch's board.
@export var board_position: Vector2i = Vector2i.ZERO


func is_unlock() -> bool:
	return max_level == 1
