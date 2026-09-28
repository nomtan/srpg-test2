shader_type spatial;
// Crescent for sword trails: smooth colour gradient with a same-colour glow spilling outside
// the silhouette so the stroke reads as emissive. The shape erodes away with age.
// UV.x is age (0 at the blade, 1 at the tail). UV.y runs from the inner edge (0) to the outer
// edge (1); the mesh extends past both by glow_width so the halo has room to draw.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.72, 0.93, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.8, 0.72, 1.0, 1.0);
uniform vec4 tail_color : source_color = vec4(0.82, 0.74, 1.0, 1.0);
uniform float glow_width = 0.25;
uniform float glow_strength = 0.75;
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

// Anti-aliased hard step.
float cel(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((x - edge) / w + 0.5, 0.0, 1.0);
}

void fragment() {
	float age = UV.x;
	float r = UV.y;
	// Thick behind the blade, thinning to a point as it ages.
	float body = 0.72 * pow(sin(3.14159 * mix(0.18, 1.0, age)), 0.7) * (1.0 - 0.35 * age);
	// Blocky fray on the inner edge.
	float fray = (floor(noise(vec2(age * 7.0, 0.5)) * 4.0) / 4.0 - 0.4) * 0.35 * age;
	float inner = 1.0 - body + fray;
	float thickness = max(1.0 - inner, 1e-3);
	// Distance to the nearest silhouette edge, in UV units (negative outside).
	float dist = min(r - inner, 1.0 - r);
	float shape = cel(0.0, dist);
	// Smooth gradient across the width: white rim, pale cyan, pale purple inside.
	float t = clamp((r - inner) / thickness, 0.0, 1.0);
	vec3 color = mix(shade_color.rgb, base_color.rgb, smoothstep(0.0, 0.55, t));
	color = mix(color, highlight_color.rgb, smoothstep(0.55, 0.95, t));
	// Drift toward the tail colour as the stroke ages.
	color = mix(color, tail_color.rgb, smoothstep(0.15, 0.9, age) * (1.0 - smoothstep(0.7, 1.0, t)));
	// Soft speed lines running along the sweep.
	float lines = smoothstep(0.62, 0.85, noise(vec2(age * 1.5, r * 11.0))) * smoothstep(0.2, 0.5, age) * (1.0 - t) * 0.6;
	float fade = 1.0 - age * age;
	// Halo in the stroke's own colour, strongest at the silhouette.
	vec3 glow_color = mix(base_color.rgb, tail_color.rgb, smoothstep(0.15, 0.9, age));
	float halo = pow(1.0 - clamp(-dist / glow_width, 0.0, 1.0), 2.0) * glow_strength * step(0.02, body);
	ALBEDO = mix(glow_color, color, shape);
	ALPHA = clamp(mix(halo, 1.0 - lines, shape) * fade * opacity, 0.0, 1.0);
}
