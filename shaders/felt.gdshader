// Felt ground (GDD 15.2): flat matte flocked fabric, no lumps. World-space projected so the huge ground
// box and the crop/farmyard discs share one seamless weave. A large, soft color mottling breaks up the
// big flat areas the way hand-cut felt patches would.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.42, 0.58, 0.3, 1.0);
uniform vec4 patch_color : source_color = vec4(0.5, 0.64, 0.32, 1.0);
uniform sampler2D felt_color : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D felt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patch_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float felt_scale = 0.35;     // weave repeats per meter
uniform float patch_scale = 0.012;   // mottling patches per meter
uniform float fiber_contrast = 0.55; // how much the felt texture's light/dark fibers show
uniform float normal_depth = 0.8;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * felt_scale;
	// Two rotated samples hide the texture's tiling over 280 m of ground.
	float fibers = texture(felt_color, uv).r * 0.6 + texture(felt_color, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.37).r * 0.4;
	float patches = smoothstep(0.35, 0.7, texture(patch_noise, world_pos.xz * patch_scale).r);
	vec3 base = mix(albedo_color.rgb, patch_color.rgb, patches);
	ALBEDO = base * mix(1.0, fibers * 1.25, fiber_contrast);
	ROUGHNESS = 0.97;
	SPECULAR = 0.15;
	NORMAL_MAP = texture(felt_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	// Felt catches a fuzzy halo of light at grazing angles.
	RIM = 0.35;
	RIM_TINT = 0.8;
}
