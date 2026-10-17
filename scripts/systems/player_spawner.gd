class_name PlayerSpawner
extends Node
## Spawns one farmer per local player at the farm's "player_spawns" markers (GDD 18.2).
## M0 is single-player; co-op adds players here, each with its own InputRouter index (GDD 18.8).

@export var player_scene: PackedScene
@export var players_parent: Node3D
@export var local_player_count: int = 1


func spawn_players() -> void:
	var spawns := get_tree().get_nodes_in_group(&"player_spawns")
	for i in local_player_count:
		var farmer := player_scene.instantiate() as Farmer
		var spawn := spawns[i % spawns.size()] as Node3D if not spawns.is_empty() else null
		var where := spawn.global_position if spawn != null else Vector3.ZERO
		farmer.position = players_parent.to_local(where + Vector3.RIGHT * 1.5 * i)
		farmer.rotation.y = spawn.global_rotation.y if spawn != null else 0.0
		(farmer.get_node(^"InputRouter") as InputRouter).player_index = i
		players_parent.add_child(farmer)
		farmer.reset_physics_interpolation()
