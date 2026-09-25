shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D expression_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool expression_enabled = false;
uniform vec2 expression_uv_scale = vec2(1.0, 1.0);
uniform vec2 expression_uv_offset = vec2(0.0, 0.0);
uniform float shadow_band = 0.68;
uniform float middle_band = 0.84;

// Reserved for future palette, expression, emblem, and gameplay effects.
// Keep per-surface ShaderMaterial instances so Head parameters can change independently.
void fragment() {
	vec4 base = texture(base_color_texture, UV);
	if (expression_enabled) {
		vec4 expression = texture(expression_texture, UV * expression_uv_scale + expression_uv_offset);
		base.rgb = mix(base.rgb, expression.rgb, expression.a);
	}
	ALBEDO = base.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = ALBEDO * shadow_band;
}

void light() {
	float energy = clamp(max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), LIGHT_COLOR.b) / PI, 0.0, 1.0);
	float illumination = max(dot(normalize(NORMAL), LIGHT), 0.0) * ATTENUATION * energy * (2.2 / PI) + 0.045;
	float band = illumination >= 0.60 ? 1.0 : (illumination >= 0.28 ? middle_band : shadow_band);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(band - shadow_band));
}
