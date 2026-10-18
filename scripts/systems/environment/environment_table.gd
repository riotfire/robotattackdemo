class_name EnvironmentTable
extends Resource
## The six time-of-day presets in order (GDD 4.6: Dawn, Morning, Noon, Golden Hour, Dusk, Moonlit Night) and the
## weather types with their roll weights. TimeOfDay reads it at run start; tests iterate it.
## Pure functions of their inputs, so a run's sky can be rebuilt from its seed (GDD 18.8).

@export var presets: Array[LightingPreset] = []
@export var weathers: Array[WeatherType] = []

@export_group("Per-run variation")
## The key light's bearing shifts by up to this many degrees either way per run.
@export_range(0.0, 45.0, 0.5, "suffix:°") var sun_bearing_jitter: float = 15.0
## Cloud coverage shifts by up to this much either way per run.
@export_range(0.0, 0.2, 0.01) var cloud_coverage_jitter: float = 0.05


## Everything a run rolls for its sky. Built once at run start from the "environment" RngService stream.
class Roll:
	extends RefCounted
	var start_index: int = 0
	var weather_index: int = 0
	var sun_bearing_offset: float = 0.0
	## Shifts the painted cloud layer, so each run has its own clouds.
	var cloud_offset: Vector2 = Vector2.ZERO
	var cloud_coverage_offset: float = 0.0
	## Bearing the wind blows toward, clockwise from north.
	var wind_bearing: float = 0.0
	## Seeds puddle placement, so the puddle count never changes how many rolls the stream gives.
	var puddle_seed: int = 0

	func equals(other: Roll) -> bool:
		return (other != null and start_index == other.start_index and weather_index == other.weather_index
				and sun_bearing_offset == other.sun_bearing_offset and cloud_offset == other.cloud_offset
				and cloud_coverage_offset == other.cloud_coverage_offset and wind_bearing == other.wind_bearing
				and puddle_seed == other.puddle_seed)


## Rolls a run's starting preset, weather and variation. Always takes the same number of rolls from `rng`.
func roll(rng: RandomNumberGenerator) -> Roll:
	var result := Roll.new()
	result.start_index = rng.randi_range(0, presets.size() - 1)
	var weights := PackedFloat32Array()
	for weather in weathers:
		weights.append(weather.weight)
	result.weather_index = rng.rand_weighted(weights)
	result.sun_bearing_offset = rng.randf_range(-sun_bearing_jitter, sun_bearing_jitter)
	result.cloud_offset = Vector2(rng.randf(), rng.randf())
	result.cloud_coverage_offset = rng.randf_range(-cloud_coverage_jitter, cloud_coverage_jitter)
	result.wind_bearing = rng.randf() * 360.0
	result.puddle_seed = rng.randi()
	return result


## The preset shown during `wave`: the run's starting preset, one step further for every phase completed
## since the run's first wave, wrapping from Moonlit Night back to Dawn (GDD 4.6, 11.2).
func preset_index(start_index: int, wave: int, start_wave: int = 1) -> int:
	var phases_done := GameState.phase_of(maxi(wave, 1)) - GameState.phase_of(maxi(start_wave, 1))
	return posmod(start_index + phases_done, presets.size())


func preset_by_id(id: StringName) -> int:
	for i in presets.size():
		if presets[i].id == id:
			return i
	return -1


func weather_by_id(id: StringName) -> int:
	for i in weathers.size():
		if weathers[i].id == id:
			return i
	return -1
