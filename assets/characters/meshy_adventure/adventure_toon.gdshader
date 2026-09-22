shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
// Face-slot only: Meshy's mouth is mostly geometry; a fine cel stroke makes
// expressions readable at the exploration camera's distance. Neutral is untouched.
uniform float expression_mouth : hint_range(-1.0, 1.0) = 0.0;
uniform bool use_expression_uv = false;
varying vec3 part_position;

void vertex() {
	// UV2 stores the face's rest coordinates so skinning cannot slide the mouth.
	part_position = use_expression_uv ? vec3(UV2.x - 0.5, UV2.y, 0.4) : VERTEX;
}

void fragment() {
	ALBEDO = texture(base_color_texture, UV).rgb * tint.rgb;
	float mouth_x = part_position.x / 0.061;
	float curve = 1.302 + sign(expression_mouth) * (0.027 * mouth_x * mouth_x - 0.010);
	float stroke = 1.0 - smoothstep(0.0015, 0.005, abs(part_position.y - curve));
	stroke *= 1.0 - smoothstep(0.85, 1.0, abs(mouth_x));
	stroke *= smoothstep(0.28, 0.32, part_position.z) * abs(expression_mouth);
	ALBEDO = mix(ALBEDO, vec3(0.20, 0.075, 0.06), stroke);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Meshy already paints its cel shadows into the original Base Color.
	EMISSION = ALBEDO * 0.72;
}

void light() {
	float energy = clamp(max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), LIGHT_COLOR.b) / PI, 0.0, 1.0);
	float value = max(dot(normalize(NORMAL), LIGHT), 0.0) * ATTENUATION * energy;
	float band = value > 0.55 ? 1.0 : (value > 0.22 ? 0.86 : 0.72);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(band - 0.72));
}
