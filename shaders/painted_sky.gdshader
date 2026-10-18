// Painted backdrop sky (GDD 15.2): a soft warm gradient with cotton-ball clouds, like a painted card
// behind a tabletop set. Clouds are puffy noise blobs lit from the sun side. The backdrop is static on
// purpose: reading TIME would make Godot re-render the sky's radiance map every frame.
// TimeOfDay sets the colors per lighting preset (data/environment/time_of_day), shifts the cloud layer per
// run (cloud_offset), and turns on painted stars at night. The disc follows the key light, so at night
// it is the moon.
shader_type sky;
render_mode use_debanding;

uniform vec4 zenith_color : source_color = vec4(0.36, 0.6, 0.9, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.93, 0.89, 0.78, 1.0);
uniform vec4 ground_color : source_color = vec4(0.55, 0.62, 0.42, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.72, 0.76, 0.86, 1.0);
uniform sampler2D cloud_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.1;
uniform float cloud_scale = 0.22;
uniform float sun_disc_size = 0.035;
uniform vec4 sun_disc_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float sun_disc_energy = 1.6;
uniform vec2 cloud_offset = vec2(0.0);
uniform float star_strength : hint_range(0.0, 1.0) = 0.0;

float cloud_density(vec2 p) {
	// Big billows plus smaller lumps on top give the "cotton ball" silhouette.
	float d = texture(cloud_noise, p).r * 0.78 + texture(cloud_noise, p * 2.3 + 0.31).r * 0.22;
	return smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + cloud_softness, d);
}

// Small painted dots on a grid of directions; most cells stay empty.
float stars(vec3 dir) {
	vec3 cell = floor(dir * 160.0);
	float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	vec3 local = fract(dir * 160.0) - 0.5;
	float dot_mask = smoothstep(0.32, 0.08, length(local));
	return step(0.992, h) * dot_mask * (0.5 + 0.5 * fract(h * 917.0));
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 sky_col = mix(horizon_color.rgb, zenith_color.rgb, smoothstep(0.0, 0.55, up));
	// A painted horizon band: slightly warmer and brighter right at the skyline.
	sky_col = mix(sky_col, horizon_color.rgb * 1.05, exp(-abs(up) * 18.0) * 0.5);
	if (up < 0.0) {
		sky_col = mix(horizon_color.rgb, ground_color.rgb, smoothstep(0.0, 0.25, -up));
	}

	vec3 sun_dir = LIGHT0_DIRECTION;
	float sun_dot = dot(dir, sun_dir);
	// Soft paper-cut sun disc and a warm glow around it.
	float disc = smoothstep(1.0 - sun_disc_size, 1.0 - sun_disc_size * 0.7, sun_dot);
	sky_col += LIGHT0_COLOR * pow(max(sun_dot, 0.0), 24.0) * 0.25;
	// Below 1 the energy also fades the disc out (TimeOfDay hides it while the light swings to a new preset).
	sky_col = mix(sky_col, sun_disc_color.rgb * sun_disc_energy, disc * clamp(sun_disc_energy, 0.0, 1.0) * float(LIGHT0_ENABLED));
	if (star_strength > 0.0 && up > 0.04) {
		sky_col += vec3(1.0, 0.96, 0.85) * stars(dir) * star_strength * smoothstep(0.04, 0.25, up) * (1.0 - disc);
	}

	if (up > 0.02) {
		// Project onto a flat cloud ceiling; flatten toward the horizon so clouds stack into a band.
		vec2 p = dir.xz / (up + 0.18) * cloud_scale + cloud_offset;
		float c = cloud_density(p);
		// Fake lighting: sample a little toward the sun; denser there means this side is shaded.
		float toward = cloud_density(p + normalize(sun_dir.xz + vec2(0.0001)) * 0.03);
		float lit = clamp(1.0 - (toward - c) * 2.5, 0.0, 1.0);
		vec3 col = mix(cloud_shade.rgb, cloud_color.rgb, lit * 0.7 + 0.3);
		float fade = smoothstep(0.02, 0.2, up);
		sky_col = mix(sky_col, col, c * fade);
	}
	COLOR = sky_col;
}
