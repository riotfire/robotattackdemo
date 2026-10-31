extends GutTest


func test_spotter_calls_name_landmarks_in_a_short_sentence() -> void:
	assert_eq(WaveDirector.spotter_call(PackedInt32Array([1])), "They're coming in by the barn!")
	assert_eq(WaveDirector.spotter_call(PackedInt32Array([7, 8])), "Spotted by the house and tool shed!")
	assert_eq(WaveDirector.spotter_call(PackedInt32Array([1]), true), "More coming by the barn!")
	assert_eq(WaveDirector.spotter_call(PackedInt32Array([1, 1])), "They're coming in by the barn!")
	assert_eq(WaveDirector.spotter_call(PackedInt32Array()), "Here they come!")
	assert_eq(WaveDirector.spotter_call(PackedInt32Array([1, 2, 7])), "Spotted by the barn, stables and house!")


func test_spotter_calls_leave_wave_details_on_the_hud_card() -> void:
	var callout := WaveDirector.spotter_call(PackedInt32Array([1, 2, 3, 7, 8]))
	assert_lt(callout.length(), 100)
	assert_false(callout.contains("Wave"))
	assert_false(callout.contains("north"))
	assert_false(callout.contains("BIG HAUL"))
	for text: String in WaveDirector.INTROS.values():
		assert_lte(text.split(" ").size(), 9, "debut warnings also fit a quick call")
