class_name DinnerBell
extends Interactable
## The dinner bell by the porch (GDD 11.1): hold Interact during an intermission to call the next wave
## early and collect the Early Bird bonus.


func _ready() -> void:
	super._ready()
	hold_time = 1.0
	prompt = "Hold to ring the dinner bell (start the wave early)"


func _director() -> WaveDirector:
	return get_tree().get_first_node_in_group(WaveDirector.GROUP) as WaveDirector


func can_interact(_farmer: Farmer) -> bool:
	var director := _director()
	return director != null and director.phase == WaveDirector.Phase.INTERMISSION


func interact(_farmer: Farmer) -> void:
	var director := _director()
	if director != null:
		director.ring_bell()
	var bell := get_node_or_null(^"Bell") as Node3D
	if bell != null:
		var tween := create_tween()
		for i in 3:
			tween.tween_property(bell, ^"rotation:z", 0.5, 0.08)
			tween.tween_property(bell, ^"rotation:z", -0.5, 0.08)
		tween.tween_property(bell, ^"rotation:z", 0.0, 0.08)
