shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.42;
uniform float band_split : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	float band = step(band_split, lambert);
	float tone = mix(shadow_tone, 1.0, band);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tone;
}
