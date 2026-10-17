class_name FarmBoundary
extends Node
## "Lost in the Corn" (GDD 4.7): past 115 m from the silo the farmer pops back out at the corn edge.
## No penalty and no invisible wall.

@export var lost_radius: float = 115.0
@export var return_radius: float = 98.0


func _physics_process(_delta: float) -> void:
	var center := GameState.silo.global_position if GameState.silo != null else Vector3.ZERO
	for player in GameState.players:
		if not is_instance_valid(player):
			continue
		var flat := player.global_position - center
		flat.y = 0.0
		if flat.length() <= lost_radius:
			continue
		var target := center + flat.normalized() * return_radius
		target.y = 0.2
		if player.has_method("teleport_to"):
			player.call("teleport_to", target)
		EventBus.hud_message.emit("Whoa, lost in the corn!", 2.0)
