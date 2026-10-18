extends Node
## M2-J5 audio foundation. EventBus owns game events; this autoload owns playback and mix routing.
## Placeholder music is intentionally small. Final stems can replace the WAVs without changing callers.

const MUSIC_FADE_SECONDS := 0.45
const SFX_VOICES := 8
const MUSIC_GAIN_DB := -8.0

const MUSIC: Dictionary = {
	&"intermission": "res://assets/audio/music_intermission.wav",
	&"siren": "res://assets/audio/music_siren.wav",
	&"combat": "res://assets/audio/music_combat.wav",
	&"boss": "res://assets/audio/music_boss.wav",
	&"cleared": "res://assets/audio/music_cleared.wav",
	&"game_over": "res://assets/audio/music_game_over.wav",
}
const CUES: Dictionary = {
	&"siren": "res://assets/audio/siren.wav",
	&"pistol": "res://assets/audio/pistol.wav",
	&"wrench": "res://assets/audio/wrench.wav",
	&"robot_pop": "res://assets/audio/robot_pop.wav",
}

var music_state: StringName = &""
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := -1
var _music_previous := -1
var _fade_elapsed := 0.0
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _leak_player: AudioStreamPlayer
var _leak_poll := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % index
		player.bus = &"Music"
		add_child(player)
		_music_players.append(player)
	for index in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % index
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)
	_leak_player = AudioStreamPlayer.new()
	_leak_player.name = "GrainLeak"
	_leak_player.bus = &"Ambience"
	_leak_player.stream = _looped_stream("res://assets/audio/grain_leak.wav")
	add_child(_leak_player)

	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	EventBus.siren_started.connect(_on_siren_started)
	EventBus.robot_destroyed.connect(_on_robot_destroyed)
	EventBus.crack_opened.connect(_on_crack_changed)
	EventBus.crack_resized.connect(_on_crack_changed)
	EventBus.crack_closed.connect(_on_crack_changed)
	EventBus.run_started.connect(_on_run_started)


## Quitting frees the players mid-sound. The AudioServer drops a stopped playback only on its next mix step, on the
## audio thread, and any it still lists when it shuts down leak along with the WAVs they hold. So stop every player,
## then wait (at most half a second) for a mix that started after the stop to finish.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _music_players + _sfx_players + [_leak_player]:
		player.stop()
	var stopped_at := Time.get_ticks_usec()
	while Time.get_ticks_usec() - stopped_at < 500000 and _last_mix_usec() <= stopped_at:
		OS.delay_msec(1)
	AudioServer.lock()  # Blocks until a mix in progress is done.
	AudioServer.unlock()


func _process(delta: float) -> void:
	if _music_previous >= 0:
		_fade_elapsed += delta
		var blend := clampf(_fade_elapsed / MUSIC_FADE_SECONDS, 0.0, 1.0)
		_music_players[_music_active].volume_db = MUSIC_GAIN_DB + linear_to_db(maxf(blend, 0.001))
		_music_players[_music_previous].volume_db = MUSIC_GAIN_DB + linear_to_db(maxf(1.0 - blend, 0.001))
		if blend >= 1.0:
			_music_players[_music_previous].stop()
			_music_previous = -1
	_leak_poll -= delta
	if _leak_poll <= 0.0:
		_leak_poll = 0.25
		_update_leak()


## One state per WaveDirector phase, with a heavier combat stem every fifth wave.
static func state_for_phase(phase: int, wave: int) -> StringName:
	match phase:
		WaveDirector.Phase.INTERMISSION:
			return &"intermission"
		WaveDirector.Phase.SIREN:
			return &"siren"
		WaveDirector.Phase.SPAWNING, WaveDirector.Phase.MOP_UP:
			return &"boss" if wave > 0 and wave % 5 == 0 else &"combat"
		WaveDirector.Phase.CLEARED:
			return &"cleared"
		WaveDirector.Phase.GAME_OVER:
			return &"game_over"
	return &"intermission"


func set_music_state(state: StringName) -> void:
	if state == music_state or not MUSIC.has(state):
		return
	var stream := _looped_stream(MUSIC[state])
	if stream == null:
		push_warning("AudioDirector: missing music stem %s" % state)
		return
	var incoming := 0 if _music_active < 0 else 1 - _music_active
	if _music_previous >= 0:
		_music_players[_music_previous].stop()
		_music_previous = -1
	_music_players[incoming].stop()
	_music_players[incoming].stream = stream
	_music_players[incoming].volume_db = MUSIC_GAIN_DB - 60.0 if _music_active >= 0 else MUSIC_GAIN_DB
	_music_players[incoming].play()
	if _music_active >= 0:
		_music_previous = _music_active
		_fade_elapsed = 0.0
	_music_active = incoming
	music_state = state


## Weapons play their WeaponData.fire_cue through here from Weapon.begin_shot(), which runs only once a shot or
## swing actually starts.
## The fixed voice pool bounds SFX cost during crowded waves.
func play_cue(cue: StringName) -> void:
	if not CUES.has(cue):
		push_warning("AudioDirector: unknown cue %s" % cue)
		return
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stop()
	player.stream = load(CUES[cue]) as AudioStream
	if player.stream != null:
		player.play()


## When the latest mix step started, on the Time.get_ticks_usec() clock.
func _last_mix_usec() -> int:
	return Time.get_ticks_usec() - roundi(AudioServer.get_time_since_last_mix() * 1000000.0)


func _looped_stream(path: String) -> AudioStream:
	var stream := load(path) as AudioStream
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _on_wave_phase_changed(phase: int, wave: int) -> void:
	set_music_state(state_for_phase(phase, wave))


func _on_siren_started(_wave: int, _lanes: PackedInt32Array) -> void:
	play_cue(&"siren")


func _on_robot_destroyed(_robot: Node3D, _killer: Node) -> void:
	play_cue(&"robot_pop")


func _on_crack_changed(_crack: Node3D) -> void:
	_update_leak()


func _on_run_started(_seed: int) -> void:
	_leak_player.stop()
	set_music_state(&"intermission")


func _update_leak() -> void:
	var rate := 0.0
	if GameState.silo != null and is_instance_valid(GameState.silo) and not GameState.is_game_over:
		rate = GameState.silo.total_leak_rate()
	if rate <= 0.0:
		_leak_player.stop()
		return
	_leak_player.volume_db = -32.0 + minf(rate * 2.0, 10.0)
	if not _leak_player.playing:
		_leak_player.play()
