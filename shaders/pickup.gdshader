shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A small emission floor keeps loot legible at dusk without lights, bloom or textures.
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	EMISSION = COLOR.rgb * 0.45;
	RIM = 0.35;
	RIM_TINT = 0.25;
}
