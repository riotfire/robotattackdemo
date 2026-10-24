extends Node3D
## Boots a run: seeds the RNG streams, spawns the farmer and starts the wave loop.
## Seed: set run_seed in the inspector, or pass `-- --seed=1234` on the command line; -1 rolls a random one.
## The HUD handles restart after game over (it keeps processing while the tree is paused).
## A profile that hasn't finished Level 0 "Morning Chores" starts in it; `-- --tutorial` replays it and
## `-- --skip-tutorial` goes straight to the first intermission.

@export var run_seed: int = -1

@onready var _spawner: PlayerSpawner = $PlayerSpawner
@onready var _director: WaveDirector = $WaveDirector


func _ready() -> void:
	var seed_value := run_seed
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = arg.trim_prefix("--seed=").to_int()
	GameState.start_run(seed_value)
	print("Robot Attack! run seed: %d" % GameState.run_seed)
	_spawner.spawn_players()
	var tutorial := not SaveManager.tutorial_completed
	for arg in OS.get_cmdline_user_args():
		if arg == "--tutorial":
			tutorial = true
		elif arg == "--skip-tutorial":
			tutorial = false
	_director.start_run(tutorial)
	if tutorial:
		var chores := TutorialDirector.new()
		chores.name = "TutorialDirector"
		add_child(chores)
		chores.begin(self)
	EventBus.game_over.connect(_on_game_over)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_game_over(_reason: StringName) -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
