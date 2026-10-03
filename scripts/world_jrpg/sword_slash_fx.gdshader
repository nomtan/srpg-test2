shader_type spatial;
// Crescent for sword trails: a solid white-hot band along the leading rim cooling through gold and orange
// into an ember-red tail, with faint strands in the ember region.
// Premultiplied alpha lets the light add onto the scene while the ember tail still darkens it slightly.
// UV.x is age (0 at the blade, 1 at the tail). UV.y runs from the inner edge (0) to the outer edge (1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha;

uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform vec4 base_color : source_color = vec4(1.0, 0.78, 0.18, 1.0);
uniform vec4 shade_color : source_color = vec4(1.0, 0.42, 0.04, 1.0);
uniform vec4 tail_color : source_color = vec4(0.45, 0.07, 0.02, 1.0);
uniform float intensity = 1.4;
// Shifts the strand pattern so stacked ribbons don't line up.
uniform float seed = 0.0;
// Crescent thickness behind the blade, as a fraction of the ribbon width.
uniform float thickness_scale = 0.62;
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

// Heat 0..1 → ember red, orange, gold, white.
vec3 ramp(float heat) {
	vec3 color = mix(tail_color.rgb, shade_color.rgb, smoothstep(0.0, 0.35, heat));
	color = mix(color, base_color.rgb, smoothstep(0.3, 0.65, heat));
	return mix(color, core_color.rgb, smoothstep(0.7, 0.95, heat));
}

void fragment() {
	float age = UV.x;
	float r = UV.y;
	// Thick behind the blade, thinning to a hooked point as it ages.
	float body = thickness_scale * pow(sin(3.14159 * mix(0.15, 1.0, age)), 0.65) * (1.0 - 0.45 * age);
	// Gently wavering inner edge so the crescent doesn't read as a cut-out band.
	float fray = (noise(vec2(age * 3.0, seed)) - 0.5) * 0.18 * age;
	float inner = 1.0 - body + fray;
	float thickness = max(1.0 - inner, 1e-3);
	float t = (r - inner) / thickness;
	// Soft shoulder on the inner side, crisp leading rim on the outer side.
	float shape = smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(1.0 - fwidth(t), 1.0, t));
	// Depth in from the leading rim (0 at the rim, 1 at the inner edge).
	float d = 1.0 - clamp(t, 0.0, 1.0);
	// Solid white-hot band along the rim: wide behind the blade, narrowing as the stroke ages.
	float core_depth = mix(0.7, 0.12, smoothstep(0.0, 0.85, age));
	float core = 1.0 - smoothstep(core_depth - 0.04, core_depth + 0.04, d);
	// Below the core the light cools through gold and orange into the ember wash.
	float glow = 1.0 - smoothstep(core_depth, core_depth + 0.45, d);
	// Faint strands only in the cooling ember region, never across the white band.
	float streak = noise(vec2(age * 1.8 + seed * 3.1, r * 34.0 + seed));
	float strands = smoothstep(0.62, 0.8, streak) * smoothstep(0.2, 0.5, age) * (1.0 - core) * 0.5;
	// The white band stays white most of the way, then yellows near the tail.
	float heat = clamp(mix((0.3 + 0.45 * glow) * (1.0 - age * 0.6), 1.0 - age * 0.3, core) + strands * 0.25, 0.0, 1.0);
	float fade = (1.0 - age * age) * smoothstep(0.0, 0.04, age + 0.02);
	float fill = shape * (mix(0.2 + 0.6 * glow, 1.0, core) + strands * 0.4);
	ALBEDO = ramp(heat) * fill * intensity * fade * opacity;
	// Partial coverage keeps the gold saturated over bright ground instead of washing out to white;
	// the ember body occludes a little more, like the reference's dark wake.
	float cover = shape * (1.0 - glow) * smoothstep(0.1, 0.6, age) * 0.4 + min(fill, 1.0) * 0.45;
	ALPHA = clamp(cover * fade * opacity, 0.0, 1.0);
}
