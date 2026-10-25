extends GutTest
## Hit-height cracks (M2-B8, GDD 3.3, decision R-D3): a new crack is weighted 70% toward the height band the
## hit landed in, and waves 1-2 only open ground cracks.

const SILO_SCENE := "res://scenes/farm/silo.tscn"
const TRIALS := 1000

var _wave: int
var _silo_before: Silo


func before_each() -> void:
	_wave = GameState.wave
	_silo_before = GameState.silo


func after_each() -> void:
	GameState.wave = _wave
	GameState.silo = _silo_before


func test_bands_are_measured_from_the_sockets() -> void:
	var silo := _make_silo()
	assert_eq(silo.hit_band(silo.global_position + Vector3.UP * 0.6), 0, "a melee hit at the base")
	assert_eq(silo.hit_band(silo.global_position + Vector3.UP * 8.0), 1, "a lob or drone shot at 8 m")
	assert_eq(silo.hit_band(silo.global_position + Vector3.UP * 17.0), 2, "a shot at the top")


func test_ground_hits_crack_low_and_high_hits_crack_high() -> void:
	GameState.wave = 6
	var silo := _make_silo()
	var low := _band_counts(silo, 0.6)
	var mid := _band_counts(silo, 9.0)
	var high := _band_counts(silo, 17.0)
	assert_almost_eq(low[0] / float(TRIALS), 0.7, 0.05, "ground hits open ground cracks 70% of the time")
	assert_almost_eq(mid[1] / float(TRIALS), 0.7, 0.05, "catwalk-height hits open first-catwalk cracks")
	assert_almost_eq(high[2] / float(TRIALS), 0.7, 0.05, "high hits open upper-catwalk cracks")
	# The other 30% is shared by band_weights: ground 0.5 and catwalk 1 0.3 for a high hit.
	assert_gt(high[0], high[1], "the rest still leans toward the ground")
	assert_gt(low[1] + low[2], 0, "a ground hit can still crack high now and then")


func test_waves_one_and_two_never_open_a_catwalk_crack() -> void:
	for wave in [1, 2]:
		GameState.wave = wave
		var silo := _make_silo()
		var counts := _band_counts(silo, 17.0)
		assert_eq(counts[0], TRIALS, "wave %d: even high hits open ground cracks" % wave)


func test_a_full_ground_band_folds_damage_into_a_crack_early_on() -> void:
	GameState.wave = 2
	var silo := _make_silo()
	silo.max_active_cracks = 16
	# One crack's worth per hit, after any Silo Plating the test profile owns.
	var plating := clampf(StatService.get_stat(&"silo.damage_reduction", 0.0), 0.0, 0.9)
	var step := silo.max_structure * silo.crack_every_fraction
	var top := silo.global_position + Vector3.UP * 17.0
	# 9 cracks' worth: one more than the ground band holds, without bringing the silo down.
	for i in 9:
		silo.take_damage(DamagePacket.create(step / (1.0 - plating) + 0.01, null, top + Vector3(cos(i), 0.0, sin(i)) * 4.0))
	var bands := silo.get_cracks().map(func(crack: SiloCrack) -> int: return crack.band)
	assert_eq(bands.size(), 8, "only the 8 ground sockets crack")
	assert_false(bands.has(1) or bands.has(2), "no catwalk crack in wave 2")
	var pooled := 0.0
	for crack in silo.get_cracks():
		pooled += crack.pool
	assert_gt(pooled, 8.0 * step, "the ninth crack's worth went into an open crack's pool")
	# Below one crack's worth stays in the silo's counter until the next hit.
	assert_almost_eq(pooled + float(silo.get(&"_crack_counter")), silo.max_structure - silo.structure, 0.01,
			"every point of lost Structure is still repairable")


func _make_silo() -> Silo:
	var silo := (load(SILO_SCENE) as PackedScene).instantiate() as Silo
	add_child_autofree(silo)
	return silo


## How many of TRIALS picks land in each band for a hit at `height` on the silo's +X side.
func _band_counts(silo: Silo, height: float) -> PackedInt32Array:
	var counts := PackedInt32Array([0, 0, 0])
	var at := silo.global_position + Vector3(silo.radius, height, 0.0)
	for i in TRIALS:
		var socket: int = silo.call(&"_pick_socket", at)
		var marker := silo.get_node(^"CrackSockets").get_child(socket) as Marker3D
		counts[int(marker.get_meta(&"band", 0))] += 1
	return counts
