extends Node
## M2-J5 audio foundation. EventBus owns game events; this autoload owns playback and mix routing.
##
## The siren is the cut between the two themes. "Surveying the Field" plays between waves and
## bleeds out over the last PRE_SIREN_FADE_SECONDS of the intermission, so the siren sounds over
## silence. "Pixel Banjo Defense" fades in once the siren cue has finished and plays while robots attack.

const MUSIC_FADE_SECONDS := 0.45
const PRE_SIREN_FADE_SECONDS := 2.0
const POST_SIREN_FADE_SECONDS := 1.5
## Attack theme -> field theme once a wave is cleared.
const WAVE_END_FADE_SECONDS := 2.0
const SFX_VOICES := 8
const MUSIC_GAIN_DB := -8.0
## Pops closer together than this climb in pitch, so a multi-kill plays a rising run of pops.
const POP_STREAK_MSEC := 600
const POP_STREAK_STEP := 0.06
const POP_STREAK_MAX := 7

const FIELD_THEME := "res://assets/audio/music/Surveying the Field.mp3"
const ATTACK_THEME := "res://assets/audio/music/Robot Attack Pixel Banjo Defense.mp3"
## The siren phase is silence: the cut between the field theme and the attack theme.
const SIREN_STATE: StringName = &"siren"
const MUSIC: Dictionary = {
	&"intermission": FIELD_THEME,
	&"combat": ATTACK_THEME,
	&"boss": ATTACK_THEME, # No dedicated boss stem yet.
	&"game_over": "res://assets/audio/music_game_over.wav",
}
const CUES: Dictionary = {
	&"siren": "res://assets/audio/siren.wav",
	&"pistol": "res://assets/audio/pistol.wav",
	&"wrench": "res://assets/audio/wrench.wav",
	&"robot_pop": "res://assets/audio/robot_pop.wav",
	&"silo_alarm": "res://assets/audio/silo_alarm.wav",
	# The Rung Runner's metal climbing rhythm (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md slice 2).
	&"climb_clank": "res://assets/audio/climb_clank.wav",
	&"spring_boing": "res://assets/audio/spring_boing.wav",
	# One crisp relief sound when a crack is sealed (FIRST_FIVE_WAVES_FUN_PLAN.md).
	&"leak_sealed": "res://assets/audio/leak_sealed.wav",
}

var music_state: StringName = &""
var _music_players: Array[AudioStreamPlayer] = []
## Per music player: linear gain, the gain it is fading toward, and how fast (gain per second).
var _music_gain := PackedFloat32Array([0.0, 0.0])
var _music_target := PackedFloat32Array([0.0, 0.0])
var _music_rate := PackedFloat32Array([1.0, 1.0])
## The player started last. It keeps the index while fading out to silence.
var _music_active := -1
## Seconds until the attack theme enters after the siren cue; negative when nothing is pending.
var _attack_wait := -1.0
var _attack_state: StringName = &"combat"
var _director: WaveDirector
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _leak_player: AudioStreamPlayer
var _leak_poll := 0.0
var _pop_streak := 0
var _last_pop_msec := -100000


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
	if _attack_wait >= 0.0:
		_attack_wait -= delta
		if _attack_wait <= 0.0:
			set_music_state(_attack_state, POST_SIREN_FADE_SECONDS)
	_update_music(delta)
	_leak_poll -= delta
	if _leak_poll <= 0.0:
		_leak_poll = 0.25
		_update_leak()


## One state per WaveDirector phase. The siren is silent, and a cleared wave carries on with the
## field theme into the next intermission.
static func state_for_phase(phase: int, wave: int) -> StringName:
	match phase:
		WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.CLEARED:
			return &"intermission"
		WaveDirector.Phase.SIREN:
			return SIREN_STATE
		WaveDirector.Phase.SPAWNING, WaveDirector.Phase.MOP_UP:
			return &"boss" if GameState.is_big_haul(wave) else &"combat"
		WaveDirector.Phase.GAME_OVER:
			return &"game_over"
	return &"intermission"


## Crossfades to the state's stem; the siren state just fades the current stem out.
func set_music_state(state: StringName, fade_seconds: float = MUSIC_FADE_SECONDS) -> void:
	_attack_wait = -1.0
	if state == music_state:
		return
	var silent := state == SIREN_STATE
	var stream: AudioStream = null
	if not silent:
		if not MUSIC.has(state):
			return
		stream = _looped_stream(MUSIC[state])
		if stream == null:
			push_warning("AudioDirector: missing music stem %s" % state)
			return
	var rate := 1.0 / maxf(fade_seconds, 0.01)
	var outgoing := _music_active
	if outgoing >= 0:
		_music_target[outgoing] = 0.0
		_music_rate[outgoing] = rate
	music_state = state
	if silent:
		return
	var incoming := 0 if outgoing < 0 else 1 - outgoing
	_music_players[incoming].stop()
	_music_players[incoming].stream = stream
	_music_players[incoming].volume_db = MUSIC_GAIN_DB - 60.0
	_music_players[incoming].play()
	_music_gain[incoming] = 0.0
	_music_target[incoming] = 1.0
	_music_rate[incoming] = rate
	_music_active = incoming


## Weapons play their WeaponData.fire_cue through here from Weapon.begin_shot(), which runs only once a shot or
## swing actually starts.
## The fixed voice pool bounds SFX cost during crowded waves.
func play_cue(cue: StringName, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if not CUES.has(cue):
		push_warning("AudioDirector: unknown cue %s" % cue)
		return
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stop()
	player.stream = load(CUES[cue]) as AudioStream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	if player.stream != null:
		player.play()


## A robot exploding. `size` is the robot's scale (1 Scout, ~2.8 Heavy): bigger robots pop deeper, and
## big ones add a low boom layer under the pop. Quick kills in a row climb in pitch.
func play_pop(size: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	_pop_streak = mini(_pop_streak + 1, POP_STREAK_MAX) if now - _last_pop_msec < POP_STREAK_MSEC else 0
	_last_pop_msec = now
	var pitch := randf_range(0.93, 1.07) * (1.0 + POP_STREAK_STEP * _pop_streak) / pow(maxf(size, 0.5), 0.3)
	play_cue(&"robot_pop", pitch)
	if size >= 1.6:
		play_cue(&"robot_pop", pitch * 0.5, 3.0)


## When the latest mix step started, on the Time.get_ticks_usec() clock.
func _last_mix_usec() -> int:
	return Time.get_ticks_usec() - roundi(AudioServer.get_time_since_last_mix() * 1000000.0)


func _looped_stream(path: String) -> AudioStream:
	var stream := load(path) as AudioStream
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamMP3:
		stream.loop = true
	return stream


func _cue_length(cue: StringName) -> float:
	var stream := load(CUES[cue]) as AudioStream
	return stream.get_length() if stream != null else 0.0


func _update_music(delta: float) -> void:
	for index in _music_players.size():
		var gain := move_toward(_music_gain[index], _music_target[index], _music_rate[index] * delta)
		if index == _music_active and _music_target[index] > 0.0:
			gain = minf(gain, _pre_siren_gain())
		_music_gain[index] = gain
		if gain <= 0.0 and _music_target[index] <= 0.0:
			_music_players[index].stop()
		else:
			_music_players[index].volume_db = MUSIC_GAIN_DB + linear_to_db(maxf(gain, 0.001))


## The intermission countdown fades the field theme out so it is silent when the siren starts.
## The ceiling is the stored gain, so the theme stays down once the phase changes.
func _pre_siren_gain() -> float:
	if not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group(WaveDirector.GROUP) as WaveDirector
	if _director == null or _director.phase != WaveDirector.Phase.INTERMISSION:
		return 1.0
	return clampf((_director.time_left - _director.siren_lead_time) / PRE_SIREN_FADE_SECONDS, 0.0, 1.0)


func _on_wave_phase_changed(phase: int, wave: int) -> void:
	var state := state_for_phase(phase, wave)
	match phase:
		WaveDirector.Phase.SIREN:
			set_music_state(state)
			_attack_state = state_for_phase(WaveDirector.Phase.SPAWNING, wave)
			_attack_wait = _cue_length(&"siren")
		WaveDirector.Phase.SPAWNING, WaveDirector.Phase.MOP_UP:
			set_music_state(state, POST_SIREN_FADE_SECONDS)
		WaveDirector.Phase.CLEARED:
			set_music_state(state, WAVE_END_FADE_SECONDS)
		_:
			set_music_state(state)


func _on_siren_started(_wave: int, _lanes: PackedInt32Array) -> void:
	play_cue(&"siren")


func _on_robot_destroyed(robot: Node3D, _killer: Node) -> void:
	# An exploding robot pops on its burst frame instead, in sync with the flash.
	if robot is Robot and (robot as Robot).exploding:
		return
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
