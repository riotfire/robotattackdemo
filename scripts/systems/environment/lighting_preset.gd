class_name LightingPreset
extends Resource
## One time-of-day lighting preset (GDD 4.6, 15.5): key light color and angle, the painted sky, fog color and
## exposure. TimeOfDay steps through six of them, one per phase. Fog distances belong to the weather
## (WeatherType), because they set how far the player can see (GDD 4.7).
## Presets are data so readability checks (M2-F3) can iterate them; AtmosphereLook combines one with a weather.

@export var id: StringName
@export var display_name: String = ""

@export_group("Key light")
## Degrees above the horizon. Moonlit Night uses the same light as the moon.
@export_range(5.0, 90.0, 0.5, "suffix:°") var sun_elevation: float = 42.0
## Compass bearing the light comes from, clockwise from north (90 = east, 180 = south, GDD 4.3 map).
@export_range(0.0, 360.0, 0.5, "suffix:°") var sun_bearing: float = 215.0
@export var sun_color: Color = Color(1.0, 0.93, 0.82)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 1.3
@export_range(0.0, 1.0, 0.01) var shadow_opacity: float = 1.0

@export_group("Painted sky")
@export var zenith_color: Color = Color(0.36, 0.6, 0.9)
@export var horizon_color: Color = Color(0.93, 0.89, 0.78)
@export var ground_color: Color = Color(0.55, 0.62, 0.42)
@export var cloud_color: Color = Color(1.0, 0.99, 0.96)
@export var cloud_shade: Color = Color(0.72, 0.76, 0.86)
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.4
## The paper-cut disc drawn where the key light is (the sun, or the moon at night).
@export var sun_disc_color: Color = Color(1.0, 0.95, 0.8)
@export_range(0.0, 4.0, 0.01) var sun_disc_energy: float = 1.6
@export_range(0.0, 0.2, 0.001) var sun_disc_size: float = 0.035
## Painted stars above the horizon; 0 by day.
@export_range(0.0, 1.0, 0.01) var star_strength: float = 0.0

@export_group("Ambient and fog")
## Fill light for the share the sky doesn't provide (1 - ambient_sky_contribution).
@export var ambient_color: Color = Color(0.0, 0.0, 0.0)
@export_range(0.0, 1.0, 0.01) var ambient_sky_contribution: float = 0.85
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 1.1
@export var fog_color: Color = Color(0.9, 0.87, 0.78)
## How much distant things take on the sky's color instead of the flat fog color.
@export_range(0.0, 1.0, 0.01) var fog_aerial_perspective: float = 0.45
@export_range(0.0, 1.0, 0.01) var fog_sky_affect: float = 0.1

@export_group("Camera")
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.05
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.12
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.04
## Bloom on emissive parts only (robot eyes, weak points). 0 turns glow off.
@export_range(0.0, 2.0, 0.01) var glow_intensity: float = 0.0
## Brightness above which things bloom. Keep it above sunlit clay so only emissive parts glow.
@export_range(0.5, 4.0, 0.01) var glow_threshold: float = 1.6
