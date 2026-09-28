shader_type spatial;
// Cel-look crescent for sword trails: flat colour bands, hard edges and an ink outline.
// The shape erodes away with age instead of fading.
// UV.x is age (0 at the blade, 1 at the tail), UV.y runs from the inner edge (0) to the outer edge (1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 highlight_color : source_color = vec4(0.97, 1.0, 1.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.38, 0.82, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.36, 0.42, 0.95, 1.0);
uniform vec4 tail_color : source_color = vec4(0.62, 0.44, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.12, 0.14, 0.38, 1.0);
uniform float outline_width = 0.05;
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
	// Chunky, blocky fray on the inner edge reads as painted cel shapes.
	float fray = (floor(noise(vec2(age * 7.0, 0.5)) * 4.0) / 4.0 - 0.4) * 0.35 * age;
	float inner = 1.0 - body + fray;
	float thickness = max(1.0 - inner, 1e-3);
	// Distance to the nearest silhouette edge, in UV units.
	float dist = min(r - inner, 1.0 - r);
	float shape = cel(0.0, dist);
	float fill = cel(outline_width * thickness, dist);
	// Three flat bands across the width: shade inside, base, highlight on the leading rim.
	float t = (r - inner) / thickness;
	vec3 color = mix(shade_color.rgb, base_color.rgb, cel(0.38, t));
	color = mix(color, highlight_color.rgb, cel(0.78, t));
	// Snap to the tail palette once the stroke is old.
	color = mix(color, mix(shade_color.rgb, tail_color.rgb, cel(0.5, t)), cel(0.55, age));
	// Hard-edged speed-line cutouts running along the sweep.
	float lines = cel(0.72, noise(vec2(age * 1.5, r * 11.0))) * cel(0.3, age) * (1.0 - cel(0.78, t));
	ALBEDO = mix(outline_color.rgb, color, fill);
	ALPHA = shape * (1.0 - lines) * opacity;
}
