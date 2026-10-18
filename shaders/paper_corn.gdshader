// Paper corn in weather (GDD 4.6, 15.2): the same look as CornField's own material (vertex-color paper strips,
// light glowing through the leaves), plus a stepped wind sway for Breezy and a wet sheen for Drizzle.
// Weather puts this on the corn chunks only while there is wind or rain; calm dry runs keep the original.
// The sway is stepped at 12 fps like the clay boil (GDD 15.4) and stops with Reduce Motion.
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

global uniform float clay_boil_enabled;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;
// World XZ direction the wind blows toward.
uniform vec2 wind_direction = vec2(1.0, 0.0);
// Tip sway in meters at full wind, for the tallest stalks (about 3.3 m).
uniform float sway_meters = 0.8;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 backlight_color = vec3(0.32, 0.36, 0.12);

void vertex() {
	if (wind_strength > 0.0 && clay_boil_enabled > 0.5) {
		float t = floor(TIME * 12.0) / 12.0;
		vec3 origin = MODEL_MATRIX[3].xyz;
		float phase = dot(origin.xz, vec2(0.11, 0.07));
		float plant = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
		// A steady lean, slow gusts that roll across the field, and each stalk's own flutter.
		float gust = 0.5 + 0.3 * sin(t * 1.3 + phase) + 0.12 * sin(t * 3.7 + phase * 2.3) + 0.08 * sin(t * 6.1 + plant);
		float h = clamp((VERTEX.y - origin.y) / 3.3, 0.0, 1.2);
		vec2 bend = normalize(wind_direction + vec2(0.0001)) * wind_strength * sway_meters * gust * h * h;
		VERTEX.xz += bend;
		VERTEX.y -= length(bend) * 0.35 * h;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(1.0, 0.8, wetness);
	ROUGHNESS = mix(0.9, 0.45, wetness);
	BACKLIGHT = backlight_color;
}
