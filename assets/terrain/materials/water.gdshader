shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D water_texture : source_color, filter_nearest;
uniform float scroll_speed_a : hint_range(0.0, 1.0) = 0.03;
uniform float scroll_speed_b : hint_range(0.0, 1.0) = 0.05;
uniform float distortion : hint_range(0.0, 0.1) = 0.015;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec2 warp = distortion * vec2(sin(TIME * 0.7 + UV.y * 6.0), cos(TIME * 0.6 + UV.x * 6.0));
	vec2 uv_a = UV + warp + vec2(TIME * scroll_speed_a, TIME * scroll_speed_a * 0.6);
	vec2 uv_b = UV * 1.3 + warp + vec2(-TIME * scroll_speed_b, TIME * scroll_speed_b * 0.4);
	vec3 color_a = texture(water_texture, uv_a).rgb;
	vec3 color_b = texture(water_texture, uv_b).rgb;
	ALBEDO = mix(color_a, color_b, 0.5);
	ALPHA = water_alpha;
}
