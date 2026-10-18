class_name AtmosphereLook
extends RefCounted
## What the farm looks like right now: a time-of-day preset with the run's weather and per-run variation on
## top (compose), blended between presets during a phase change (blend), and pushed onto the WorldEnvironment,
## the key light and the painted sky (apply). Plain values, so tests and the readability rules (M2-F3) can
## build any preset x weather combination without a scene.

var sun_elevation: float = 42.0
var sun_bearing: float = 215.0
var sun_color: Color = Color(1.0, 0.93, 0.82)
var sun_energy: float = 1.3
var shadow_opacity: float = 1.0

var zenith_color: Color = Color(0.36, 0.6, 0.9)
var horizon_color: Color = Color(0.93, 0.89, 0.78)
var ground_color: Color = Color(0.55, 0.62, 0.42)
var cloud_color: Color = Color(1.0, 0.99, 0.96)
var cloud_shade: Color = Color(0.72, 0.76, 0.86)
var cloud_coverage: float = 0.4
var cloud_offset: Vector2 = Vector2.ZERO
var sun_disc_color: Color = Color(1.0, 0.95, 0.8)
var sun_disc_energy: float = 1.6
var sun_disc_size: float = 0.035
var star_strength: float = 0.0

var ambient_color: Color = Color(0.0, 0.0, 0.0)
var ambient_sky_contribution: float = 0.85
var ambient_energy: float = 1.1
var fog_color: Color = Color(0.9, 0.87, 0.78)
var fog_begin: float = 55.0
var fog_end: float = 125.0
var fog_curve: float = 1.4
var fog_aerial_perspective: float = 0.45
var fog_sky_affect: float = 0.1

var exposure: float = 1.05
var saturation: float = 1.12
var contrast: float = 1.04
var glow_intensity: float = 0.0
var glow_threshold: float = 1.6


## `preset` with `weather` (Clear when null) and the run's variation (none when null) applied on top.
static func compose(preset: LightingPreset, weather: WeatherType = null,
		roll: EnvironmentTable.Roll = null) -> AtmosphereLook:
	var look := AtmosphereLook.new()
	for property in look.get_property_list():
		var key: String = property["name"]
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and key in preset:
			look.set(key, preset.get(key))
	if roll != null:
		look.sun_bearing = fposmod(look.sun_bearing + roll.sun_bearing_offset, 360.0)
		look.cloud_offset = roll.cloud_offset
		look.cloud_coverage += roll.cloud_coverage_offset
	if weather == null:
		weather = WeatherType.new()
	look.fog_begin = weather.fog_begin
	look.fog_end = weather.fog_end
	look.fog_curve = weather.fog_curve
	look.fog_aerial_perspective *= weather.aerial_perspective_scale
	look.fog_sky_affect = clampf(look.fog_sky_affect + weather.fog_sky_affect_add, 0.0, 1.0)
	look.fog_color = _desaturated(look.fog_color, weather.fog_desaturate) * weather.fog_brightness
	look.cloud_coverage = clampf(look.cloud_coverage + weather.cloud_coverage_add, 0.0, 1.0)
	look.zenith_color = _desaturated(look.zenith_color, weather.sky_desaturate)
	look.horizon_color = _desaturated(look.horizon_color, weather.sky_desaturate)
	look.cloud_color = _desaturated(look.cloud_color, weather.sky_desaturate)
	look.cloud_shade = _desaturated(look.cloud_shade, weather.sky_desaturate)
	look.sun_energy *= weather.sun_energy_scale
	look.shadow_opacity *= weather.shadow_opacity_scale
	look.ambient_energy *= weather.ambient_energy_scale
	look.saturation *= weather.saturation_scale
	look.exposure *= weather.exposure_scale
	look.glow_intensity += weather.glow_boost
	look.glow_threshold *= weather.glow_threshold_scale
	return look


## This look moved `t` (0..1) of the way to `to`. The key light swings the short way round the compass.
func blend(to: AtmosphereLook, t: float) -> AtmosphereLook:
	var out := AtmosphereLook.new()
	for property in get_property_list():
		if not int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var key: String = property["name"]
		var from_value: Variant = get(key)
		var to_value: Variant = to.get(key)
		if key == "sun_bearing":
			out.sun_bearing = fposmod(rad_to_deg(lerp_angle(deg_to_rad(sun_bearing), deg_to_rad(to.sun_bearing), t)), 360.0)
		elif from_value is float:
			out.set(key, lerpf(from_value, to_value, t))
		elif from_value is Color:
			out.set(key, (from_value as Color).lerp(to_value, t))
		elif from_value is Vector2:
			out.set(key, (from_value as Vector2).lerp(to_value, t))
	return out


func apply(env: Environment, sun: DirectionalLight3D) -> void:
	if sun != null:
		sun.rotation_degrees = Vector3(-sun_elevation, 180.0 - sun_bearing, 0.0)
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.shadow_opacity = shadow_opacity
	if env == null:
		return
	env.ambient_light_color = ambient_color
	env.ambient_light_sky_contribution = ambient_sky_contribution
	env.ambient_light_energy = ambient_energy
	env.tonemap_exposure = exposure
	env.adjustment_saturation = saturation
	env.adjustment_contrast = contrast
	env.fog_light_color = fog_color
	env.fog_depth_begin = fog_begin
	env.fog_depth_end = fog_end
	env.fog_depth_curve = fog_curve
	env.fog_aerial_perspective = fog_aerial_perspective
	env.fog_sky_affect = fog_sky_affect
	env.glow_enabled = glow_intensity > 0.001
	env.glow_intensity = glow_intensity
	env.glow_hdr_threshold = glow_threshold
	if env.sky == null or not env.sky.sky_material is ShaderMaterial:
		return
	var sky_material := env.sky.sky_material as ShaderMaterial
	sky_material.set_shader_parameter(&"zenith_color", zenith_color)
	sky_material.set_shader_parameter(&"horizon_color", horizon_color)
	sky_material.set_shader_parameter(&"ground_color", ground_color)
	sky_material.set_shader_parameter(&"cloud_color", cloud_color)
	sky_material.set_shader_parameter(&"cloud_shade", cloud_shade)
	sky_material.set_shader_parameter(&"cloud_coverage", cloud_coverage)
	sky_material.set_shader_parameter(&"cloud_offset", cloud_offset)
	sky_material.set_shader_parameter(&"sun_disc_color", sun_disc_color)
	sky_material.set_shader_parameter(&"sun_disc_energy", sun_disc_energy)
	sky_material.set_shader_parameter(&"sun_disc_size", sun_disc_size)
	sky_material.set_shader_parameter(&"star_strength", star_strength)


static func _desaturated(color: Color, amount: float) -> Color:
	var gray := color.get_luminance()
	return color.lerp(Color(gray, gray, gray, color.a), amount)
