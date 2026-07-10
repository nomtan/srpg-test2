shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D lava_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.015;
uniform float emission_strength : hint_range(0.0, 4.0) = 2.0;
// Flow direction of the scroll animation in UV space. Plane default flows
// diagonally; lava-fall side panels set this to a downward vec2(0.0, 1.0).
uniform vec2 flow_dir = vec2(1.0, 0.3);

void fragment() {
	vec2 uv = UV + flow_dir * TIME * scroll_speed;
	vec3 color = texture(lava_texture, uv).rgb;
	ALBEDO = color;
	EMISSION = color * emission_strength;
}
