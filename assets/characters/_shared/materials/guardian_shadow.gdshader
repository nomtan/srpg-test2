shader_type spatial;
// Guardian look: the painted Tripo texture shown flat (like enemy_dissolve) with a faint crimson rim,
// plus a per-instance `reveal` that draws the body in as ink. It forms from the tail upward along
// vertical brush streaks whose edge keeps wavering (an ink-and-crimson fringe, swelling a little), and
// erases the same way from the head down. 0 = gone, 1 = whole.
render_mode unshaded, cull_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
// Model-space height of the guardian (tail tip at 0); the reveal front runs over it.
uniform float height = 0.96;
// How ragged the front is, as a fraction of the height.
uniform float spread = 0.45;
// Brush streaks per model unit (across the strokes; along them it is stretched).
uniform float stroke_scale = 7.0;
uniform float wobble_speed = 0.7;
uniform vec3 ink_color : source_color = vec3(0.015, 0.004, 0.02);
uniform vec3 edge_color : source_color = vec3(0.95, 0.07, 0.14);
uniform float edge_width = 0.06;
uniform vec3 rim_color : source_color = vec3(0.6, 0.02, 0.1);
uniform float rim_strength = 0.35;
// Swelling of the surface right at the front, in model units.
uniform float swell = 0.012;
instance uniform float reveal = 1.0;

varying vec3 model_position;
varying float front;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Distance past the reveal front (> 0 drawn). Brush streaks run vertically and sway sideways with
// height and time, so the front advances in uneven fingers of ink.
float reveal_margin(vec3 p, float t) {
	float h = clamp(p.y / height, 0.0, 1.0);
	float sway = sin(p.y * 9.0 + t * 1.7) * 0.05 + sin(p.y * 23.0 - t * 2.3) * 0.02;
	vec3 q = vec3((p.x + sway) * stroke_scale * 2.6, p.y * stroke_scale * 0.45 - t * 0.8, (p.z - sway) * stroke_scale * 2.6);
	float streak = noise(q);
	float fine = noise(p * stroke_scale * 5.0 + vec3(0.0, -t * 2.2, 0.0));
	float n = streak * 0.72 + fine * 0.28;
	return reveal * (1.0 + spread + edge_width) - (h + n * spread);
}

void vertex() {
	// Skinned, so the streaks stay on the body as it moves.
	model_position = VERTEX;
	front = 1.0;
	if (reveal < 1.0) {
		float m = reveal_margin(VERTEX, TIME * wobble_speed);
		front = m;
		VERTEX += NORMAL * swell * exp(-abs(m) * 18.0) * (1.0 - reveal * reveal);
	}
}

void fragment() {
	vec3 color = texture(base_color_texture, UV).rgb;
	float facing = abs(dot(NORMAL, VIEW));
	color += rim_color * rim_strength * pow(1.0 - facing, 3.0);
	if (reveal < 1.0) {
		float m = reveal_margin(model_position, TIME * wobble_speed);
		if (m < 0.0) {
			discard;
		}
		// A thin crimson burn right on the front, then a band of raw ink behind it.
		float glow = 1.0 - smoothstep(0.0, edge_width * 0.35, m);
		float inked = 1.0 - smoothstep(edge_width * 0.35, edge_width * 1.6, m);
		color = mix(color, ink_color, inked * 0.9);
		color = mix(color, edge_color * 1.8, glow);
	}
	ALBEDO = color;
}
