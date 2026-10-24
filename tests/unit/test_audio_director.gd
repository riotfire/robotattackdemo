extends GutTest
## M2-J5 regression coverage: live phase events route music; siren and all core cues load.
## The siren is the cut between the field theme (between waves) and the attack theme.


func after_each() -> void:
	AudioDirector.set_music_state(&"intermission")


## Steps the director's fades the way the engine would, `seconds` at a time.
func _run_audio(seconds: float, step: float = 0.05) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		AudioDirector._process(step)
		elapsed += step


func _gain(player_index: int) -> float:
	return AudioDirector.get(&"_music_gain")[player_index]


func _loudest_gain() -> float:
	return maxf(_gain(0), _gain(1))


func test_every_wave_phase_has_a_loaded_music_state() -> void:
	for phase in range(WaveDirector.Phase.size()):
		var state: StringName = AudioDirector.state_for_phase(phase, 1)
		if state != AudioDirector.SIREN_STATE:
			assert_true(AudioDirector.MUSIC.has(state), "phase %d maps to a stem" % phase)
			assert_not_null(load(AudioDirector.MUSIC[state]), "phase %d stem loads" % phase)
		EventBus.wave_phase_changed.emit(phase, 1)
		assert_eq(AudioDirector.music_state, state, "phase %d switches live music" % phase)
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.SPAWNING, 5), &"boss")
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.MOP_UP, 10), &"boss")


func test_field_theme_between_waves_attack_theme_while_robots_attack_and_silence_at_the_siren() -> void:
	var field: String = AudioDirector.MUSIC[AudioDirector.state_for_phase(WaveDirector.Phase.INTERMISSION, 1)]
	var attack: String = AudioDirector.MUSIC[AudioDirector.state_for_phase(WaveDirector.Phase.SPAWNING, 1)]
	assert_true(field.ends_with("/Surveying the Field.mp3"), "intermission plays the field theme")
	assert_true(attack.ends_with("/Robot Attack Pixel Banjo Defense.mp3"), "attack plays the banjo theme")
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.CLEARED, 1), &"intermission",
			"a cleared wave heads back to the field theme")
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.MOP_UP, 1), &"combat", "mop-up keeps the attack theme")
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.SIREN, 1), AudioDirector.SIREN_STATE, "the siren is the cut")
	assert_false(AudioDirector.MUSIC.has(AudioDirector.SIREN_STATE), "the siren has no stem of its own")
	for path in [field, attack]:
		assert_not_null(load(path) as AudioStreamMP3, "%s imports as an MP3" % path)
	AudioDirector.set_music_state(&"combat")
	assert_true((load(attack) as AudioStreamMP3).loop, "the attack theme loops for long waves")


func test_wave_event_switches_music_and_siren_event_plays_cue() -> void:
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.SIREN, 1)
	assert_eq(AudioDirector.music_state, &"siren")
	var voice_before: int = AudioDirector.get(&"_next_sfx")
	EventBus.siren_started.emit(1, PackedInt32Array([1, 3]))
	var player := AudioDirector.get_node("Sfx%d" % voice_before) as AudioStreamPlayer
	assert_not_null(player.stream, "siren assigned an audio stream")
	assert_true(player.stream.resource_path.ends_with("/siren.wav"), "siren uses the siren cue")
	assert_true(player.playing, "siren actually starts playback")


func test_ringing_the_bell_cuts_the_field_theme_for_the_siren_then_the_attack_theme_fades_in() -> void:
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.INTERMISSION, 1)
	_run_audio(AudioDirector.MUSIC_FADE_SECONDS + 0.1)
	assert_almost_eq(_loudest_gain(), 1.0, 0.001, "the field theme is up between waves")

	EventBus.wave_phase_changed.emit(WaveDirector.Phase.SIREN, 1)
	assert_eq(AudioDirector.music_state, AudioDirector.SIREN_STATE)
	_run_audio(AudioDirector.MUSIC_FADE_SECONDS + 0.05)
	assert_eq(_loudest_gain(), 0.0, "all music is out while the siren sounds")
	for index in 2:
		assert_false((AudioDirector.get_node("Music%d" % index) as AudioStreamPlayer).playing, "music player %d is stopped" % index)

	var cue_length: float = (load(AudioDirector.CUES[&"siren"]) as AudioStream).get_length()
	_run_audio(cue_length - AudioDirector.MUSIC_FADE_SECONDS - 0.15) # Stay inside the siren cue.
	assert_eq(AudioDirector.music_state, AudioDirector.SIREN_STATE, "the attack theme waits for the siren cue to finish")
	_run_audio(0.25)
	assert_eq(AudioDirector.music_state, &"combat", "the attack theme enters right after the siren")
	_run_audio(AudioDirector.POST_SIREN_FADE_SECONDS / 2.0)
	var halfway := _loudest_gain()
	assert_between(halfway, 0.2, 0.8, "the attack theme fades in rather than cutting in")
	_run_audio(AudioDirector.POST_SIREN_FADE_SECONDS)
	assert_almost_eq(_loudest_gain(), 1.0, 0.001, "and reaches full level")


func test_field_theme_fades_out_with_the_intermission_countdown_before_the_siren() -> void:
	var director := WaveDirector.new()
	add_child_autofree(director)
	director.siren_lead_time = 3.0
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.INTERMISSION, 1)

	director.time_left = 60.0
	_run_audio(AudioDirector.MUSIC_FADE_SECONDS + 0.1)
	assert_almost_eq(_loudest_gain(), 1.0, 0.001, "full volume mid-intermission")

	director.time_left = director.siren_lead_time + AudioDirector.PRE_SIREN_FADE_SECONDS / 2.0
	_run_audio(0.1)
	assert_almost_eq(_loudest_gain(), 0.5, 0.01, "half way through the fade-out window")

	director.time_left = director.siren_lead_time
	_run_audio(0.1)
	assert_eq(_loudest_gain(), 0.0, "silent the moment the siren starts")

	director.phase = WaveDirector.Phase.SIREN
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.SIREN, 1)
	_run_audio(0.1)
	assert_eq(_loudest_gain(), 0.0, "the field theme does not pop back when the siren phase begins")


func test_a_cleared_wave_crossfades_the_attack_theme_into_the_field_theme() -> void:
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.SPAWNING, 2)
	_run_audio(AudioDirector.POST_SIREN_FADE_SECONDS + 0.1)
	assert_eq(AudioDirector.music_state, &"combat")
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.CLEARED, 2)
	assert_eq(AudioDirector.music_state, &"intermission")
	_run_audio(AudioDirector.WAVE_END_FADE_SECONDS + 0.1)
	var field_player := AudioDirector.get_node("Music%d" % AudioDirector.get(&"_music_active")) as AudioStreamPlayer
	assert_true(field_player.stream.resource_path.ends_with("/Surveying the Field.mp3"), "the field theme took over")
	assert_almost_eq(_loudest_gain(), 1.0, 0.001)
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.INTERMISSION, 3)
	assert_eq(AudioDirector.music_state, &"intermission", "the next intermission does not restart the theme")


func test_core_cues_and_bus_layout_are_available() -> void:
	for bus in [&"Music", &"SFX", &"Ambience", &"UI"]:
		assert_gte(AudioServer.get_bus_index(bus), 0, "bus %s exists" % bus)
	for cue in [&"pistol", &"wrench", &"robot_pop", &"silo_alarm"]:
		var voice_before: int = AudioDirector.get(&"_next_sfx")
		AudioDirector.play_cue(cue)
		var player := AudioDirector.get_node("Sfx%d" % voice_before) as AudioStreamPlayer
		assert_not_null(player.stream, "%s assigned a stream" % cue)
		assert_true(player.stream.resource_path.ends_with("/%s.wav" % cue), "%s loads the expected cue" % cue)
	assert_eq(AudioDirector.get_children().filter(
			func(child: Node) -> bool: return child.name.begins_with("Sfx")).size(), AudioDirector.SFX_VOICES)
