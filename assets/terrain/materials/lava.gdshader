shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

#include "res://assets/terrain/materials/liquid_variation.gdshaderinc"

uniform sampler2D lava_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform float scroll_speed_a : hint_range(0.0, 1.0) = 0.12;
uniform float scroll_speed_b : hint_range(0.0, 1.0) = 0.18;
uniform float distortion : hint_range(0.0, 0.1) = 0.015;
uniform float emission_strength : hint_range(0.0, 4.0) = 2.0;
// Flow direction of the scroll animation in UV space. Plane default flows
// diagonally; lava-fall side panels set this to a downward vec2(0.0, 1.0).
uniform vec2 flow_dir = vec2(1.0, 0.3);

void vertex() {
	LIQUID_VERTEX_SETUP
}

void fragment() {
	vec2 warp = distortion * vec2(
		sin(TIME * 0.9 + UV.y * 7.0),
		cos(TIME * 0.8 + UV.x * 7.0)
	);
	vec2 uv_a = UV + warp + flow_dir * TIME * scroll_speed_a;
	vec2 uv_b = UV * 1.35 - warp - flow_dir * TIME * scroll_speed_b;
	vec3 color_a = texture(lava_texture, uv_a).rgb;
	vec3 color_b = texture(lava_texture, uv_b).rgb;
	vec3 color = apply_liquid_variation(mix(color_a, color_b, 0.42));
	ALBEDO = color;
	EMISSION = color * emission_strength;
}
