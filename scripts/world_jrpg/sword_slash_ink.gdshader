shader_type spatial;
// Anime ink slash for the sword's quick attacks: a dark ink crescent whose leading (outer) rim burns cyan to white.
// It snaps out in a couple of frames, flattens into a thin cyan streak after the full swing (`peak`),
// then tears into ink flecks and broken light dashes as it fades.
// Driven like sword_slash.gdshader: `progress` (0 → 1 over the whole effect), `peak` and `opacity`.
// UV.x runs along the swing (0 start, 1 full swing); UV.y from the inner edge (0) to the outer edge (1).
// Premultiplied alpha: the ink covers the scene, the rim light adds onto it.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_premul_alpha;

uniform float progress = 0.0;
uniform float peak = 0.3;
// Driven by the player to fade an interrupted attack.
uniform float opacity = 1.0;
// Fraction of the arc lit behind the leading tip.
uniform float trail_length = 0.8;
// Crescent thickness behind the tip, as a fraction of the band width.
uniform float thickness = 1.0;
uniform vec4 ink_color : source_color = vec4(0.02, 0.05, 0.15, 1.0);
uniform vec4 edge_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.9, 1.0, 1.0, 1.0);
// Lit rim depth at the tip, as a fraction of the crescent's thickness (it narrows toward the tail).
uniform float edge_width = 0.4;
uniform float ink_alpha = 0.92;
uniform float glow = 2.6;
// Extra brightness at the full swing.
uniform float peak_flash = 1.2;
// Brush streaks across the band (higher = finer).
uniform float streaks = 30.0;
// Thickness of the streak the crescent flattens into, as a fraction of the band width.
uniform float streak_width = 0.12;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Hard cel step with an antialiased edge: 0 below edge, 1 above.
float cel(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((x - edge) / w + 0.5, 0.0, 1.0);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float swing = clamp(progress / max(peak, 1e-4), 0.0, 1.0);
	float after = clamp((progress - peak) / max(1.0 - peak, 1e-4), 0.0, 1.0);
	// The tip snaps out and brakes hard into the full swing.
	float head = 1.0 - pow(1.0 - swing, 3.0);
	// Lit length behind the tip (0 at the tip, 1 at the tail); it stretches back as the streak fades.
	float span = max(trail_length + 0.25 * after, 1e-3);
	float a = (head - u) / span;
	float ac = clamp(a, 0.0, 1.0);
	// After the full swing the tip end burns away backward.
	float front = head - smoothstep(0.15, 1.0, after) * span * 0.7;
	float along = cel(0.0, a) * (1.0 - smoothstep(0.75, 1.0, a)) * (1.0 - cel(front, u));
	// Crescent: pointed at both ends, widest a third of the way behind the tip; it flattens into a thin streak.
	float settle = smoothstep(0.0, 0.3, after);
	float crescent = max(thickness * pow(sin(3.14159 * mix(0.03, 1.0, ac)), 0.75) * (1.0 - 0.4 * ac), 1e-3);
	float body = max(mix(crescent, streak_width * (1.0 - 0.6 * ac), settle), 1e-3);
	// The rim sits just inside the outer edge, leaving room for its glow.
	float rim = 0.93;
	float t = (v - (rim - body)) / body;
	// Ragged inner edge: brush strokes running along the swing.
	float brush = noise(vec2(u * 7.0, v * streaks));
	float shape = cel(0.4 * brush * (1.0 - settle), t) * (1.0 - cel(1.0, t)) * along;
	// Lit rim (cyan, white-hot at the very edge) narrowing toward the tail; the streak keeps ink wisps under its light.
	float depth = 1.0 - t;
	float lit_width = mix(edge_width * (1.0 - 0.6 * ac), 0.55, settle);
	float lit = 1.0 - cel(lit_width, depth + 0.12 * brush);
	float core = 1.0 - cel(lit_width * 0.35, depth);
	// Soft glow just past the rim, strongest near the tip.
	float halo = step(rim, v) * exp(-(v - rim) * 45.0) * along * (1.0 - ac) * (1.0 - settle);
	// Torn ink flecks left where the crescent was, scattering as the streak fades.
	float t0 = (v - (rim - crescent)) / crescent;
	float flecks = cel(0.0, t0) * (1.0 - cel(1.0, t0)) * along * settle * (1.0 - shape)
		* cel(0.5 + 0.45 * after, noise(vec2(u * 12.0 - after * 2.5, v * streaks * 0.6)));
	// Fading tears the ink into flecks and the light into dashes.
	float tear = noise(vec2(u * 24.0 - after * 3.0, v * 5.0));
	float keep = cel(after * 0.95, tear);
	float flash = 1.0 + peak_flash * exp(-pow((progress - peak) / 0.06, 2.0));
	float fade = smoothstep(0.0, 0.12, swing) * (1.0 - pow(after, 2.0)) * opacity * keep;
	vec3 light = mix(edge_color.rgb, core_color.rgb, core) * glow * flash * (1.0 - 0.5 * ac);
	float ink = shape * (1.0 - lit) * mix(0.7, 1.0, brush) + 0.8 * flecks;
	float shine = shape * lit;
	vec3 color = ink_color.rgb * ink_alpha * ink + light * shine + edge_color.rgb * glow * halo;
	float alpha = ink_alpha * ink + 0.65 * shine + 0.25 * halo;
	// Drop empty pixels outright so the band itself never shows (fog, glow or blending on a blank pixel).
	if (alpha * fade < 0.01 && max(color.r, max(color.g, color.b)) * fade < 0.01) {
		discard;
	}
	ALBEDO = color * fade;
	ALPHA = clamp(alpha * fade, 0.0, 1.0);
}
