class_name WeatherType
extends Resource
## One weather type (GDD 4.6): Clear, Breezy, Drizzle or Morning Fog, rolled once per run. Mostly cosmetic.
## The one gameplay effect is long_range_multiplier: Morning Fog shortens long-range robots' engagement
## range by 20%. Robots read it through Weather.engagement_range_multiplier(), never from here.
## Each field is a change on top of the time-of-day preset (AtmosphereLook.compose), so every weather works
## with every preset, night included.

@export var id: StringName
@export var display_name: String = ""
## Relative chance of being rolled for a run.
@export_range(0.0, 10.0, 0.01) var weight: float = 1.0

@export_group("Gameplay")
## Engagement range multiplier for long-range robots (GDD 4.6).
@export_range(0.1, 1.0, 0.01) var long_range_multiplier: float = 1.0

@export_group("Fog")
## Depth fog distances in meters. The defaults are the farm's boundary fog (GDD 4.7): the corn wall at
## 100 m fades out and the spawn ring at 110 m is hidden.
@export var fog_begin: float = 55.0
@export var fog_end: float = 125.0
@export var fog_curve: float = 1.4
## Scales the preset's aerial perspective. Lower reads as a flat bank of fog instead of distance haze.
@export_range(0.0, 1.0, 0.01) var aerial_perspective_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var fog_sky_affect_add: float = 0.0
## Pulls the preset's fog color toward its own gray (0 keeps it, 1 is fully gray).
@export_range(0.0, 1.0, 0.01) var fog_desaturate: float = 0.0
## Multiplies the fog color's brightness.
@export_range(0.0, 2.0, 0.01) var fog_brightness: float = 1.0

@export_group("Sky and light")
@export_range(-1.0, 1.0, 0.01) var cloud_coverage_add: float = 0.0
## Overcast: pulls the sky and cloud colors toward gray.
@export_range(0.0, 1.0, 0.01) var sky_desaturate: float = 0.0
@export_range(0.0, 2.0, 0.01) var sun_energy_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var shadow_opacity_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var ambient_energy_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var saturation_scale: float = 1.0
@export_range(0.1, 2.0, 0.01) var exposure_scale: float = 1.0
## Added to the preset's glow so robot eye glows stay readable (Morning Fog, GDD 4.6).
@export_range(0.0, 2.0, 0.01) var glow_boost: float = 0.0
## Scales the preset's glow threshold. Fog dims eyes along with everything else, so it blooms them sooner.
@export_range(0.3, 2.0, 0.01) var glow_threshold_scale: float = 1.0

@export_group("Wind and rain")
## 0 calm .. 1 breezy: how hard the corn sways (and, from M2-B2, how far flyers drift).
@export_range(0.0, 1.0, 0.01) var wind_strength: float = 0.0
## 0 dry .. 1 full drizzle of falling clay droplets.
@export_range(0.0, 1.0, 0.01) var rain_amount: float = 0.0
## 0 dry .. 1 soaked: shinier clay, darker felt, wet corn.
@export_range(0.0, 1.0, 0.01) var wetness: float = 0.0
@export_range(0, 64) var puddle_count: int = 0
