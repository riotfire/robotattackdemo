class_name Main
extends Node3D
## Boots a run: seeds the RNG streams, spawns the farmer and starts the wave loop.
## Seed: set run_seed in the inspector, or pass `-- --seed=1234` on the command line; -1 rolls a random one.
## The HUD handles Retry Phase and Start over after game over (it keeps processing while the tree is paused).
## A run starts at the profile's phase checkpoint (SaveManager.resume_wave), or where the Harvest Report or
## the pause menu asked for (SaveManager.pending_start). A retry gets a new seed per attempt, derived from
## the last one, so a fixed --seed session still replays the same way.
## A profile that hasn't finished Level 0 "Morning Chores" starts in it; `-- --tutorial` replays it and
## `-- --skip-tutorial` goes straight to the first intermission. `-- --start-wave=7` starts at a wave.

@export var run_seed: int = -1

@onready var _spawner: PlayerSpawner = $PlayerSpawner
@onready var _director: WaveDirector = $WaveDirector


func _ready() -> void:
	var start := SaveManager.consume_pending_start()
	var seed_value := run_seed
	var start_wave := SaveManager.resume_wave
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--start-wave="):
			start_wave = maxi(1, arg.trim_prefix("--start-wave=").to_int())
	if start.has("seed"):
		seed_value = int(start["seed"])
	if start.has("wave"):
		start_wave = int(start["wave"])
	GameState.retried = bool(start.get("retry", false))
	GameState.attempt = int(start.get("attempt", 1))
	GameState.start_run(seed_value)
	print("Robot Attack! run seed: %d" % GameState.run_seed)
	var tutorial := not SaveManager.tutorial_completed
	for arg in OS.get_cmdline_user_args():
		if arg == "--tutorial":
			tutorial = true
		elif arg == "--skip-tutorial":
			tutorial = false
	if not tutorial and not StatService.has_flag(&"wrench.owned"):
		StatService.grant(&"attack.wrench")
	_spawner.spawn_players()
	_director.start_run(tutorial, start_wave)
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


## Reloads the scene to start again: the first wave of the lost phase (`retry`), or wave 1 (Start over).
static func restart(tree: SceneTree, retry: bool) -> void:
	var wave := GameState.phase_first_wave(maxi(1, GameState.wave)) if retry else 1
	SaveManager.pending_start = {
		"wave": wave,
		"retry": retry,
		"attempt": GameState.attempt + 1 if retry else 1,
		# A new seed per attempt (P-D2): a fresh family and lanes, derived so a seeded session replays.
		"seed": absi(hash([GameState.run_seed, wave, GameState.attempt])) % 2147483647,
	}
	if not retry:
		SaveManager.resume_wave = 1
	SaveManager.save_profile()
	tree.paused = false
	tree.reload_current_scene()
