shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, specular_disabled;

uniform sampler2D albedo_texture : source_color;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.42;
uniform float band_split : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 face = texture(albedo_texture, UV);
	ALBEDO = face.rgb;
	ALPHA = face.a;
	ROUGHNESS = 1.0;
}

void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	float band = step(band_split, lambert);
	float tone = mix(shadow_tone, 1.0, band);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tone;
}
