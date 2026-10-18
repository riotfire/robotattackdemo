extends GutTest
## M2-J5 regression coverage: live phase events route music; siren and all core cues load.


func test_every_wave_phase_has_a_loaded_music_state() -> void:
	for phase in range(WaveDirector.Phase.size()):
		var state: StringName = AudioDirector.state_for_phase(phase, 1)
		assert_true(AudioDirector.MUSIC.has(state), "phase %d maps to a stem" % phase)
		assert_not_null(load(AudioDirector.MUSIC[state]), "phase %d stem loads" % phase)
		EventBus.wave_phase_changed.emit(phase, 1)
		assert_eq(AudioDirector.music_state, state, "phase %d switches live music" % phase)
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.SPAWNING, 5), &"boss")
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.MOP_UP, 10), &"boss")
	AudioDirector.set_music_state(&"intermission")


func test_wave_event_switches_music_and_siren_event_plays_cue() -> void:
	EventBus.wave_phase_changed.emit(WaveDirector.Phase.SIREN, 1)
	assert_eq(AudioDirector.music_state, &"siren")
	var voice_before: int = AudioDirector.get(&"_next_sfx")
	EventBus.siren_started.emit(1, PackedInt32Array([1, 3]))
	var player := AudioDirector.get_node("Sfx%d" % voice_before) as AudioStreamPlayer
	assert_not_null(player.stream, "siren assigned an audio stream")
	assert_true(player.stream.resource_path.ends_with("/siren.wav"), "siren uses the siren cue")
	assert_true(player.playing, "siren actually starts playback")
	AudioDirector.set_music_state(&"intermission")


func test_core_cues_and_bus_layout_are_available() -> void:
	for bus in [&"Music", &"SFX", &"Ambience", &"UI"]:
		assert_gte(AudioServer.get_bus_index(bus), 0, "bus %s exists" % bus)
	for cue in [&"pistol", &"wrench", &"robot_pop"]:
		var voice_before: int = AudioDirector.get(&"_next_sfx")
		AudioDirector.play_cue(cue)
		var player := AudioDirector.get_node("Sfx%d" % voice_before) as AudioStreamPlayer
		assert_not_null(player.stream, "%s assigned a stream" % cue)
		assert_true(player.stream.resource_path.ends_with("/%s.wav" % cue), "%s loads the expected cue" % cue)
	assert_eq(AudioDirector.get_children().filter(
			func(child: Node) -> bool: return child.name.begins_with("Sfx")).size(), AudioDirector.SFX_VOICES)
