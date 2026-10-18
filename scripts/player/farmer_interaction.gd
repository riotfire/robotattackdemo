class_name FarmerInteraction
extends Node
## Interact (GDD 5.2) on the nearest Interactable in range: the dinner bell, the tool shed, ziplines.
## A silo crack in reach takes priority (FarmerRepair handles it), so Interact never does both.

## The bell, shed door or zipline in reach, if any.
var focus: Interactable = null
## 0..1 progress while holding Interact on a hold-to-use interactable.
var progress: float = 0.0

var farmer: Farmer

var _hold: float = 0.0
var _needs_release: bool = false


func setup(owner_farmer: Farmer) -> void:
	farmer = owner_farmer


func physics_step(delta: float) -> void:
	focus = null
	if farmer.repair.target == null and farmer.state == Farmer.State.GROUNDED:
		var best_distance := INF
		for node in get_tree().get_nodes_in_group(Interactable.GROUP):
			var candidate := node as Interactable
			var d := candidate.interaction_point().distance_to(farmer.global_position)
			if d <= candidate.interact_range and d < best_distance:
				best_distance = d
				focus = candidate
	var held := farmer.input.is_pressed(&"interact")
	if not held:
		_needs_release = false
	if focus == null or not focus.can_interact(farmer) or _needs_release:
		_hold = 0.0
		progress = 0.0
		return
	if focus.hold_time <= 0.0:
		if farmer.input.is_just_pressed(&"interact"):
			_needs_release = true
			focus.interact(farmer)
		return
	_hold = _hold + delta if held else 0.0
	progress = clampf(_hold / focus.hold_time, 0.0, 1.0)
	if _hold >= focus.hold_time:
		_hold = 0.0
		progress = 0.0
		_needs_release = true
		focus.interact(farmer)
