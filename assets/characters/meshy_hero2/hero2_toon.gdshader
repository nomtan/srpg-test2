shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float shadow_band : hint_range(0.0, 1.0) = 0.68;
uniform float middle_band : hint_range(0.0, 1.0) = 0.84;
uniform float middle_threshold : hint_range(0.0, 1.0) = 0.28;
uniform float light_threshold : hint_range(0.0, 1.0) = 0.60;

void fragment() {
	ALBEDO = texture(base_color_texture, UV).rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Neutral fill protects the painted palette even inside a scene shadow.
	EMISSION = ALBEDO * shadow_band;
}

void light() {
	// Match the Eevee preview's 2.2-energy white key and .045 neutral world.
	// Use scene light direction/shadows, but do not dye the Base Color with
	// the sample's warm evening light or add continuous specular gradients.
	float energy = clamp(max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), LIGHT_COLOR.b) / PI, 0.0, 1.0);
	float illumination = max(dot(normalize(NORMAL), LIGHT), 0.0) * ATTENUATION * energy * (2.2 / PI) + 0.045;
	float band = illumination >= light_threshold ? 1.0 : (illumination >= middle_threshold ? middle_band : shadow_band);
	// Godot multiplies DIFFUSE_LIGHT by ALBEDO. Additional lights cannot
	// accumulate beyond the brightest band and wash out the source texture.
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(band - shadow_band));
}
