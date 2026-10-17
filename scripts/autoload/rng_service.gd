extends Node
## Seeded RNG streams (GDD 18.2, 18.8). Every random roll in the game comes from a named stream,
## so cosmetic rolls never shift balance rolls and any peer can rebuild a wave from (run_seed, wave).

const STREAM_GENOME: StringName = &"genome"
const STREAM_SPAWNS: StringName = &"spawns"
const STREAM_DROPS: StringName = &"drops"
const STREAM_COSMETIC: StringName = &"cosmetic"
const STREAM_SILO: StringName = &"silo"
## Per-run farm layout variation that affects play (prop scatter, GDD 4.6).
const STREAM_FARM: StringName = &"farm"

var run_seed: int = 0
var _streams: Dictionary[StringName, RandomNumberGenerator] = {}


func start_run(seed_value: int) -> void:
	run_seed = seed_value
	_streams.clear()


## A stream that lives for the whole run. Its sequence depends on how many rolls came before.
func stream(stream_name: StringName) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		_streams[stream_name] = make_rng([run_seed, stream_name])
	return _streams[stream_name]


## A fresh stream for one wave. Same (run_seed, wave, name) always gives the same sequence.
func wave_stream(stream_name: StringName, wave: int) -> RandomNumberGenerator:
	return make_rng([run_seed, wave, stream_name])


static func make_rng(key: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng
