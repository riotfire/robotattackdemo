// Clay shader v1 (GDD 15.3): matte-waxy plasticine with subsurface scattering, thumbprint normal
// detail, permanent lumpiness and a stop-motion "boil" stepped at 12 fps by StopMotionClock.
// One material serves many objects: per-object color comes from the instance uniform `tint`
// (robots, props), or from `albedo_color` on per-color copies (baked farm scenes).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Set by StopMotionClock on every 12 Hz tick; clay_boil_enabled is 0 with Reduce Motion (GDD 20).
global uniform float clay_boil_frame;
global uniform float clay_boil_enabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float emission_strength = 0.0;
// Robot family genes (GDD 10.1): pattern applied in object space, and wear (0 fresh .. 1 rusty).
// 0 none, 1 stripes, 2 polka dots, 3 checker, 4 rust patches, 5 hazard tape, 6 stars.
instance uniform int pattern_id = 0;
instance uniform vec4 pattern_color : source_color = vec4(1.0);
instance uniform float wear = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D thumbprint_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float lump_strength = 0.012;  // permanent hand-sculpted lumpiness (meters)
uniform float boil_strength = 0.004;  // stop-motion surface jitter (meters)
uniform float print_scale = 2.5;
uniform float roughness_value = 0.62;
uniform float sss_strength = 0.25;
uniform float rim_strength = 0.2;

varying vec3 local_pos;

void vertex() {
	vec3 p = VERTEX;
	// Push along the direction from the mesh origin rather than the normal: graybox primitives have
	// split normals at hard edges, but corner vertices share a position, so seams never open.
	vec3 dir = normalize(p + vec3(0.0001, 0.0002, 0.0003));
	vec2 q = p.xz * 0.8 + p.y * 0.37;
	float lump = texture(noise_tex, q * 0.5).r - 0.5;
	float boil = 0.0;
	if (clay_boil_enabled > 0.5) {
		vec2 jitter = fract(sin(vec2(clay_boil_frame * 12.9898, clay_boil_frame * 78.233)) * 43758.5453);
		boil = texture(noise_tex, q * 2.0 + jitter).r - 0.5;
	}
	VERTEX += dir * (lump * lump_strength + boil * boil_strength);
	local_pos = VERTEX;
}

float pattern_mask(vec3 p) {
	if (pattern_id == 1) {
		return step(0.5, fract(p.y * 9.0));
	} else if (pattern_id == 2) {
		vec2 cell = fract(vec2(p.x + p.z, p.y) * 8.0) - 0.5;
		return step(length(cell), 0.22);
	} else if (pattern_id == 3) {
		vec3 c = floor(p * 7.0);
		return mod(c.x + c.y + c.z, 2.0);
	} else if (pattern_id == 4) {
		return step(0.62, texture(noise_tex, p.xy * 0.9 + p.z * 0.4).r);
	} else if (pattern_id == 5) {
		return step(0.5, fract((p.x + p.y + p.z) * 7.0));
	} else if (pattern_id == 6) {
		vec2 cell = fract(vec2(p.x + p.z, p.y) * 5.0) - 0.5;
		return step(abs(cell.x) + abs(cell.y), 0.16);
	}
	return 0.0;
}

void fragment() {
	float mottling = texture(noise_tex, local_pos.xy * 0.3 + local_pos.z * 0.1).r;
	vec3 base = albedo_color.rgb * tint.rgb;
	base = mix(base, pattern_color.rgb, pattern_mask(local_pos));
	// Wear: scuffs darken and roughen the clay; heavy wear adds rusty blotches.
	float rust = step(0.66, texture(noise_tex, local_pos.xz * 1.3 + local_pos.y).r) * step(0.6, wear);
	base = mix(base, base * 0.82, wear * 0.4);
	base = mix(base, vec3(0.55, 0.3, 0.16), rust * 0.7);
	ALBEDO = base * mix(0.88, 1.06, mottling);
	ROUGHNESS = mix(roughness_value, 0.92, wear);
	SPECULAR = 0.35;
	NORMAL_MAP = texture(thumbprint_normal, UV * print_scale).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	SSS_STRENGTH = sss_strength;
	RIM = rim_strength;
	RIM_TINT = 0.5;
	EMISSION = base * emission_strength;
}
