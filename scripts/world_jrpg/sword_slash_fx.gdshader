shader_type spatial;
// Painterly crescent for sword trails. UV.x is age (0 at the blade, 1 at the tail),
// UV.y runs from the inner edge (0) to the outer edge (1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 edge_color : source_color = vec4(0.93, 0.99, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.42, 0.8, 1.0, 1.0);
uniform vec4 tail_color : source_color = vec4(0.6, 0.46, 1.0, 1.0);
uniform float opacity = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float age = UV.x;
	float r = UV.y;
	// Thick behind the blade, tapering to a point at the tail.
	float body = 0.7 * pow(sin(3.14159 * mix(0.18, 1.0, age)), 0.75);
	// Ragged inner edge that frays more as the trail ages.
	float fray = (noise(vec2(age * 9.0, r * 3.0)) - 0.5) * (0.15 + 0.45 * age);
	float inner = 1.0 - body + fray;
	float band = smoothstep(inner, inner + 0.12, r) * smoothstep(1.0, 0.93, r);
	// Streaks running along the sweep direction.
	float streak = noise(vec2(age * 2.5, r * 16.0));
	float streaks = mix(0.65, 1.0, smoothstep(0.25, 0.75, streak));
	float edge = smoothstep(0.8, 0.97, r);
	vec3 color = mix(core_color.rgb, tail_color.rgb, smoothstep(0.05, 0.85, age));
	color = mix(color, edge_color.rgb, edge * (1.0 - age * 0.7));
	ALBEDO = color;
	ALPHA = clamp(band * mix(streaks, 1.0, edge) * (1.0 - age * age) * opacity, 0.0, 1.0);
}
