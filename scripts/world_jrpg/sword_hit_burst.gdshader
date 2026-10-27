shader_type spatial;
// Cel hit effect where a sword blow lands, drawn on a camera-facing quad and driven by `elapsed` seconds:
// a thin diagonal flash, then a four-point star burst ragged with hooked spikes, bitten edges and loose shards
// that hollows out from its centre.
// Premultiplied alpha: the dark needles cover the scene, the light adds onto it.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled, blend_premul_alpha;

uniform float elapsed = 0.0;
// Varies the shapes per hit (0 → 1).
uniform float seed = 0.0;
uniform vec4 core_color : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.35, 0.55, 1.0, 1.0);
uniform vec4 ink_color : source_color = vec4(0.05, 0.07, 0.18, 1.0);
uniform float glow = 2.0;
// Soft white glow hugging the flash and the star's outline.
uniform float white_glow = 0.7;
// How far that glow spreads past the outline (higher = tighter).
uniform float white_glow_falloff = 18.0;
// Half the quad's size in effect units: everything fits within 1 except the long diagonal points along the cut.
// The quad is scaled up to match (BURST_SIZE in sword_hit_fx.gd).
uniform float extent = 2.5;
// Turns the whole effect on screen, counterclockwise in radians.
uniform float tilt = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

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

// 0 → 1 while t runs from start to end.
float phase(float t, float start, float end) {
	return clamp((t - start) / (end - start), 0.0, 1.0);
}

// Tapered spike around `direction` from radius `start` out to `reach`, curling by `bend` radians toward its tip;
// > 0 inside, in distance units. A spike with start > 0 is a loose shard, pointed at both ends.
float spike(float r, float angle, float direction, float start, float reach, float width, float bend) {
	float s = clamp((r - start) / (reach - start), 0.0, 1.0);
	float profile = start > 0.0 ? pow(sin(3.14159 * s), 0.8) : pow(1.0 - s, 1.5);
	float offset = angle - direction - bend * s * s;
	offset = atan(sin(offset), cos(offset));
	return min(width * profile - abs(offset) * r, min(reach - r, r - start));
}

vec2 rotate(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void fragment() {
	vec2 p = rotate(vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0) * extent, -tilt);
	float r = length(p);
	// Direction of the cut: the flash and the star's long diagonal points run along it.
	float cut = 0.95 + 0.5 * seed;
	vec2 q = rotate(p, -cut);
	// Past the unit circle only the diagonal points draw.
	if (r > 1.0 && abs(q.y) > 0.2) {
		discard;
	}
	float angle = atan(p.y, p.x);
	float t = elapsed;
	float light = 0.0;
	float halo = 0.0;
	float ink = 0.0;
	// White glow just outside the lit shapes.
	float sheen = 0.0;

	// Diagonal flash along the cut, gone within a couple of frames.
	float k1 = phase(t, 0.0, 0.07);
	float reach = mix(1.5, 2.4, k1);
	float along = clamp(abs(q.x) / reach, 0.0, 1.0);
	float blade_width = 0.12 * (1.0 - 0.6 * k1) * pow(1.0 - along, 1.6) * (0.6 + 0.4 * noise(vec2(q.x * 14.0, seed * 31.0)));
	float flash_on = step(t, 0.07);
	light += cel(0.0, blade_width - abs(q.y)) * step(abs(q.x), reach) * flash_on;
	halo += exp(-abs(q.y) * 16.0) * (1.0 - along) * flash_on;
	sheen += exp(min(blade_width - abs(q.y), 0.0) * white_glow_falloff) * step(abs(q.x), reach) * (1.0 - along) * flash_on;

	// Star burst: snaps open, thins, and hollows out from the centre.
	float k2 = phase(t, 0.03, 0.17);
	float burst_on = step(0.03, t) * step(t, 0.17);
	float open = 1.0 - pow(1.0 - clamp(k2 * 3.0, 0.0, 1.0), 2.0);
	vec2 bp = p / (open + 1e-3);
	float br = length(bp);
	float thin = mix(1.0, 0.55, k2);
	// Core with hooked side spikes, its edge bitten into between them.
	float star = 0.3 * thin - br;
	for (int i = 0; i < 7; i++) {
		float index = float(i) + seed * 17.0;
		float side = hash(vec2(index, 2.9)) < 0.5 ? -1.0 : 1.0;
		star = max(star, spike(br, angle, hash(vec2(index, 0.7)) * 6.283, 0.0, mix(0.45, 0.7, hash(vec2(index, 1.9))),
			mix(0.14, 0.24, hash(vec2(index, 3.3))) * thin, side * mix(0.3, 0.7, hash(vec2(index, 5.1)))));
	}
	for (int i = 0; i < 5; i++) {
		float index = float(i) + seed * 23.0;
		float around = hash(vec2(index, 6.1)) * 6.283;
		vec2 bite = vec2(cos(around), sin(around)) * mix(0.3, 0.42, hash(vec2(index, 8.3)));
		star = min(star, length(bp - bite) - mix(0.08, 0.13, hash(vec2(index, 9.7))));
	}
	// The four long points: needle-thin sideways, broader up and down.
	star = max(star, spike(br, angle, 0.0, 0.0, 0.95, 0.14 * thin, 0.05));
	star = max(star, spike(br, angle, 3.14159, 0.0, 0.9, 0.14 * thin, -0.05));
	star = max(star, spike(br, angle, 1.5708, 0.0, 0.85, 0.2 * thin, 0.12 * (seed - 0.5)));
	star = max(star, spike(br, angle, -1.5708, 0.0, 0.7, 0.2 * thin, -0.15));
	// The long diagonal points along the cut (upper right and lower left).
	star = max(star, spike(br, angle, cut, 0.0, 2.4, 0.16 * thin, 0.0));
	star = max(star, spike(br, angle, cut + 3.14159, 0.0, 2.1, 0.16 * thin, 0.0));
	// Loose shards flung off the edge.
	for (int i = 0; i < 4; i++) {
		float index = float(i) + seed * 29.0;
		float start = mix(0.42, 0.58, hash(vec2(index, 4.4)));
		star = max(star, spike(br, angle, hash(vec2(index, 1.1)) * 6.283, start, start + mix(0.12, 0.25, hash(vec2(index, 2.2))),
			mix(0.05, 0.08, hash(vec2(index, 3.6))) * thin, mix(-0.3, 0.3, hash(vec2(index, 7.7)))));
	}
	float star_fill = cel(0.0, star);
	float hollow = cel(0.0, mix(-0.3, 1.2, smoothstep(0.3, 1.0, k2)) - 1.6 * br - 0.3 * noise(p * 7.0 + seed * 13.0));
	light += star_fill * (1.0 - hollow) * burst_on;
	ink += 0.6 * star_fill * hollow * (1.0 - k2) * burst_on;
	halo += 2.5 * exp(-r * 4.5) * (1.0 - k2) * burst_on;
	// The star's field is in its opened-up units; scale back so the glow keeps its width as it opens.
	sheen = max(sheen, exp(min(star * open, 0.0) * white_glow_falloff) * (1.0 - hollow) * (1.0 - 0.6 * k2) * burst_on);
	// Needle spikes across the burst: light while it flares, then dark ink lines.
	float needle = cel(0.0, 0.013 * (1.0 - abs(p.x)) - abs(p.y)) * burst_on;
	light += needle * (1.0 - step(0.4, k2));
	ink += needle * step(0.4, k2);

	float bounds = 1.0 - smoothstep(0.92 * extent, extent, r);
	light = clamp(light, 0.0, 1.0) * bounds;
	halo = clamp(halo, 0.0, 1.5) * bounds;
	ink = clamp(ink, 0.0, 1.0) * bounds;
	// Fade out before the drawn area ends (the unit circle, or the band along the cut) so the glow has no hard rim.
	float room = max(1.0 - smoothstep(0.8, 1.0, r), 1.0 - smoothstep(0.1, 0.2, abs(q.y)));
	sheen = clamp(sheen, 0.0, 1.0) * (1.0 - light) * room * bounds;
	vec3 color = ink_color.rgb * ink + mix(glow_color.rgb, core_color.rgb, light) * glow * light + glow_color.rgb * glow * 0.5 * halo;
	color += core_color.rgb * white_glow * sheen;
	float alpha = ink + 0.6 * light + 0.15 * halo + 0.2 * white_glow * sheen;
	// Drop empty pixels outright so the quad itself never shows (fog, glow or blending on a blank pixel).
	if (alpha < 0.01 && max(color.r, max(color.g, color.b)) < 0.01) {
		discard;
	}
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
