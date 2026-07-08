shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D lava_texture : source_color, filter_nearest_mipmap;
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.015;
uniform float emission_strength : hint_range(0.0, 4.0) = 2.0;

void fragment() {
	vec2 uv = UV + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.3);
	vec3 color = texture(lava_texture, uv).rgb;
	ALBEDO = color;
	EMISSION = color * emission_strength;
}
