class_name ToolShed
extends Interactable
## The tool shed door (GDD 3.5, 13.1): opens the pegboard during intermissions. Shuttered during waves.

signal pegboard_requested(farmer: Farmer)

const GROUP_SHED: StringName = &"tool_shed"


func _ready() -> void:
	super._ready()
	add_to_group(GROUP_SHED)
	interact_range = 2.5
	prompt = "Open the pegboard"


func is_open() -> bool:
	var director := get_tree().get_first_node_in_group(WaveDirector.GROUP) as WaveDirector
	return director == null or director.phase in [WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.SIREN,
			WaveDirector.Phase.CLEARED]


func can_interact(_farmer: Farmer) -> bool:
	return true


func prompt_text(_farmer: Farmer) -> String:
	return prompt if is_open() else "The shed is shuttered during the attack!"


func interact(farmer: Farmer) -> void:
	if is_open():
		pegboard_requested.emit(farmer)
