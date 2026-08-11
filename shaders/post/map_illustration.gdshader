shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float illustration_strength : hint_range(0.0, 1.0) = 0.55;
uniform float color_steps : hint_range(4.0, 24.0) = 12.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.28;
uniform float paper_grain : hint_range(0.0, 0.08) = 0.018;
uniform float warmth : hint_range(-0.15, 0.15) = 0.035;

float luminance(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

float paper_noise(vec2 pixel_position) {
	vec2 grain_cell = floor(pixel_position * 0.5);
	return fract(sin(dot(grain_cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	float center_luma = luminance(source);
	float neighbor_delta = 0.0;
	neighbor_delta += abs(center_luma - luminance(texture(screen_texture, SCREEN_UV + vec2(pixel.x, 0.0)).rgb));
	neighbor_delta += abs(center_luma - luminance(texture(screen_texture, SCREEN_UV - vec2(pixel.x, 0.0)).rgb));
	neighbor_delta += abs(center_luma - luminance(texture(screen_texture, SCREEN_UV + vec2(0.0, pixel.y)).rgb));
	neighbor_delta += abs(center_luma - luminance(texture(screen_texture, SCREEN_UV - vec2(0.0, pixel.y)).rgb));

	vec3 posterized = floor(source * color_steps + 0.5) / color_steps;
	vec3 illustrated = mix(source, posterized, 0.62);
	illustrated *= 1.0 - smoothstep(0.035, 0.24, neighbor_delta) * edge_strength;
	illustrated += vec3(warmth, warmth * 0.45, -warmth * 0.25);
	float grain = paper_noise(SCREEN_UV / pixel) - 0.5;
	illustrated += grain * paper_grain;

	COLOR = vec4(mix(source, clamp(illustrated, 0.0, 1.0), illustration_strength), 1.0);
}
