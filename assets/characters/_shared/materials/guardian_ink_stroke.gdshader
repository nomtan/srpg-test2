shader_type spatial;
// One sumi brush stroke for the guardian's summon / dismiss swirl (GuardianInkFx): a ribbon whose
// UV.x runs along the stroke (0 tail, 1 head) and UV.y across it. `draw` paints it on from the tail
// toward the head, `erase` eats it from the tail, so a stroke sweeps along its arc. Dry-brush streaks
// open up toward the drier end; the edges and the wet head glow crimson. The ribbon wavers in place.
// Premultiplied alpha: the ink darkens the scene, the crimson adds onto it.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_premul_alpha;

uniform vec4 ink_color : source_color = vec4(0.02, 0.004, 0.03, 1.0);
uniform vec4 glow_color : source_color = vec4(0.9, 0.06, 0.15, 1.0);
uniform float glow = 0.85;
uniform float ink_alpha = 0.9;
// Bristle streaks across the stroke.
uniform float bristles = 26.0;
uniform float wobble = 0.035;
instance uniform float draw = 1.0;
instance uniform float erase = 0.0;
instance uniform float opacity = 1.0;
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float cel(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((x - edge) / w + 0.5, 0.0, 1.0);
}

void vertex() {
	// Smoky waver: the ribbon ripples across its width and along its normal.
	float t = TIME * 2.4 + seed * 17.0;
	float ripple = sin(UV.x * 11.0 + t) * 0.6 + sin(UV.x * 23.0 - t * 1.3) * 0.4;
	VERTEX += NORMAL * ripple * wobble;
	VERTEX.y += sin(UV.x * 7.0 + t * 0.8) * wobble * 0.8;
}

void fragment() {
	float u = UV.x;
	float v = UV.y * 2.0 - 1.0;
	float span = max(draw - erase, 1e-3);
	// 0 at the trailing (eaten) end of what is shown, 1 at the wet head.
	float s = (u - erase) / span;
	if (s < 0.0 || s > 1.0 || opacity <= 0.0) {
		discard;
	}
	// Width: a pressed blob at the head, thinning and splitting toward the tail.
	float width = mix(0.25, 1.0, pow(s, 0.6)) * (1.0 - smoothstep(0.9, 1.0, s) * 0.7);
	width *= 0.85 + 0.15 * noise(vec2(u * 9.0 + seed * 5.0, seed));
	float body = width - abs(v);
	// Dry brush: streaks along the stroke, more of them toward the dry tail.
	float bristle = noise(vec2(u * 5.0 + seed * 13.0, (v * 0.5 + 0.5) * bristles));
	float dry = mix(0.62, 0.12, s);
	float a = cel(0.0, body) * cel(dry, bristle + 0.15 * noise(vec2(u * 40.0, v * 3.0 + seed)));
	// Ragged head edge.
	a *= cel(0.0, 1.0 - s - 0.06 * noise(vec2(v * 6.0, seed * 3.0)) + 0.06);
	float edge = 1.0 - smoothstep(0.0, 0.2, body / max(width, 1e-3));
	float wet = smoothstep(0.7, 1.0, s);
	float alpha = a * ink_alpha * opacity;
	vec3 color = ink_color.rgb * alpha + glow_color.rgb * glow * a * opacity * clamp(edge * 0.7 + wet * 0.3, 0.0, 1.0);
	ALBEDO = color;
	ALPHA = alpha;
}
