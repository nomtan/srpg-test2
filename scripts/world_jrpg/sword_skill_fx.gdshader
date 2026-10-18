shader_type spatial;
// Pieces of the one-handed sword skill (sword_skill_fx.gd): cel-banded blue flame, wind rings, the vertical
// crescent, the finisher's flash, pillar, shell, nebula and stars. `mode` picks the piece; `progress` runs 0 → 1
// over its life. Premultiplied alpha: the pieces add light onto the scene and never darken it at their edges.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha, fog_disabled;

const int FLAME = 0;   // ground flame ring (XZ quad)
const int WIND = 1;    // thin swirling rings (XZ quad)
const int CRESCENT = 2;// vertical flame crescent (XY quad, opening toward -X)
const int FLASH = 3;   // starburst flash (billboard)
const int PILLAR = 4;  // light beam (Y billboard)
const int SHELL = 5;   // swirling sphere of arcs (sphere mesh)
const int NEBULA = 6;  // blue cloud on the ground (XZ quad)
const int STAR = 7;    // four-point twinkle, or a round dot when param.x is 0 (billboard)
const int SMOKE = 8;   // grey puff (billboard)
const int SPARKS = 9;  // white radial sparks (billboard)
const int INK = 10;    // dark ink blot (billboard)
const int STREAK = 11; // ground dash line along +X (XZ quad)

uniform int mode = 0;
// 0 none, 1 faces the camera, 2 turns about Y only.
uniform int billboard = 0;
uniform float progress = 0.0;
uniform float seed = 0.0;
uniform float intensity = 1.0;
uniform float opacity = 1.0;
// Per-mode knobs (see each mode).
uniform vec4 param = vec4(0.0);
uniform vec3 core_color : source_color = vec3(0.86, 0.97, 1.0);
uniform vec3 bright_color : source_color = vec3(0.3, 0.68, 1.0);
uniform vec3 deep_color : source_color = vec3(0.06, 0.24, 0.95);

varying vec3 local_normal_view;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (billboard == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	} else if (billboard == 2) {
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 side = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * s.x, 0.0), vec4(up * s.y, 0.0), vec4(cross(side, up) * s.z, 0.0), MODEL_MATRIX[3]);
	}
	local_normal_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Angular noise without a seam at ±PI.
float ring_noise(float angle, float r, float freq, float s) {
	return noise(vec2(cos(angle), sin(angle)) * freq + vec2(r * 3.0, s));
}

// Hard cel bands of the reference's flame: navy rim, deep blue, bright blue, white-cyan core, and bright veins.
// v is flame density; cut is the dissolve threshold. Returns premultiplied (rgb, cover).
vec4 cel_flame(float v, float cut, float vein_noise, float ink_amount) {
	float aa = 0.02;
	float body = smoothstep(cut - aa, cut + aa, v);
	float bright = smoothstep(cut + 0.08 - aa, cut + 0.08 + aa, v);
	float core = smoothstep(cut + 0.33 - aa, cut + 0.33 + aa, v);
	vec3 color = deep_color * body;
	color = mix(color, bright_color, bright);
	color = mix(color, core_color, core);
	// Thin lightning-like veins inside the flame.
	float vein = (1.0 - smoothstep(0.0, 0.022, abs(vein_noise - 0.5))) * bright * (1.0 - core);
	color += core_color * vein * 0.9;
	// Dark navy fringe just outside the flame body.
	// Faint blue glow just outside the flame body, adding light only so the edge fades into the scene.
	float rim = smoothstep(cut - 0.07, cut - 0.03, v) * (1.0 - body) * ink_amount;
	// A little cover inside the bright bands keeps them saturated over bright ground; none at the edge,
	// so the outline never darkens what is behind it.
	return vec4(color * body * intensity + deep_color * rim * 0.35 * intensity, bright * 0.3);
}

vec4 flame_ring(vec2 p) {
	// param: x ring radius (UV units, quad half-size is 1), y band width, z swept turns of the reveal.
	float r = length(p);
	float angle = atan(p.y, p.x);
	float t = progress;
	// The reveal spins in behind the blade, then the ring breaks into scattered patches.
	float lead = t * param.z * 6.2831853 / 0.35;
	float behind = mod(lead - (angle + 3.14159265), 6.2831853);
	float ragged = (fbm(p * 3.0 + seed) - 0.5) * 3.0;
	// Past one full turn the reveal edge runs off the end, so no seam is left where the angle wraps.
	float reach = min(lead, 6.2831853 + 2.2);
	float revealed = param.z <= 0.0 ? 1.0 : 1.0 - smoothstep(reach - 0.6, reach, behind + ragged);
	float band = 1.0 - smoothstep(0.0, param.y, abs(r - param.x - 0.05 * t));
	vec2 flow = vec2(cos(angle), sin(angle)) * (r * 4.0) + vec2(-sin(angle), cos(angle)) * t * 1.5;
	vec2 warp = vec2(fbm(flow + seed), fbm(flow.yx + seed + 4.0));
	float v = fbm(p * 4.0 + warp * 1.8 + seed) * 1.1 + band * 0.3;
	v *= band * revealed;
	float cut = mix(0.42, 0.8, smoothstep(0.25, 1.0, t)) + (1.0 - smoothstep(0.0, 0.12, t)) * 0.3;
	vec4 c = cel_flame(v, cut, fbm(p * 9.0 + warp * 2.0 + seed + t), 1.0);
	// Scattered blue dots spark across the ring as it breaks up.
	float dots = step(0.985, hash(floor(p * 38.0) + floor(seed * 7.0))) * band * smoothstep(0.2, 0.5, t);
	c.rgb += bright_color * dots * (1.0 - t) * intensity;
	return c;
}

vec4 wind_ring(vec2 p) {
	// param: x radius at the start, y radius at the end, z line count, w spiral twist.
	float r = length(p);
	float angle = atan(p.y, p.x);
	float t = progress;
	float radius = mix(param.x, param.y, 1.0 - pow(1.0 - t, 3.0));
	vec3 color = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		if (float(i) >= param.z) break;
		float fi = float(i);
		float ri = radius * (1.0 - fi * 0.12);
		float spiral = fract((angle + 3.14159265) / 6.2831853 + r * param.w + t * (1.4 + fi * 0.3) + fi * 0.27 + seed);
		float width = mix(0.012, 0.028, spiral) * (1.0 + fi * 0.5);
		float line = 1.0 - smoothstep(width * 0.4, width, abs(r - ri));
		float tail = pow(spiral, 1.6);
		color += mix(deep_color, core_color, tail * (1.0 - fi * 0.25)) * line * tail;
	}
	// Soft disc of light inside the rings.
	color += deep_color * 0.35 * (1.0 - smoothstep(0.0, radius, r)) * smoothstep(radius * 0.4, radius, r);
	float fade = (1.0 - smoothstep(0.55, 1.0, t)) * smoothstep(0.0, 0.06, t);
	return vec4(color * fade * intensity, 0.0);
}

vec4 crescent(vec2 p) {
	// Quad XY, the crescent bulges toward +X. param: x inner disc offset toward -X, y inner radius.
	float t = progress;
	float r = length(p);
	vec2 q = p + vec2(param.x, 0.0);
	float outer = 1.0 - smoothstep(0.86, 0.9, r);
	float inner = smoothstep(param.y - 0.02, param.y + 0.02, length(q));
	// Swept in from the top to the bottom in the first tenth of its life.
	float sweep = clamp(t / 0.12, 0.0, 1.0);
	float along = atan(p.x, p.y) / 3.14159265; // 0 at the top, 1 at the bottom on the +X side
	float reach = step(along, sweep * 1.05) * step(0.0, p.x + 0.15);
	float shape = outer * inner * reach;
	// Flame flowing upward and back along the arc as it dissolves.
	vec2 flow = p * 3.2 + vec2(-t * 0.6, -t * 2.2);
	vec2 warp = vec2(fbm(flow + seed), fbm(flow * 1.3 + seed + 5.0));
	float thick = smoothstep(0.0, 0.25, length(q) - param.y) * (1.0 - smoothstep(0.65, 0.9, r)) + 0.35;
	float v = (fbm(p * 4.5 + warp * 1.4 + seed) * 0.95 + thick * 0.3) * shape;
	float cut = mix(0.34, 0.9, smoothstep(0.18, 1.0, t));
	vec4 c = cel_flame(v, cut, fbm(p * 8.0 + warp * 2.0 + seed + t * 0.5), 1.0);
	// Whiter leading rim while fresh.
	float rim = (1.0 - smoothstep(0.0, 0.05, abs(r - 0.84))) * reach * step(param.y, length(q)) * (1.0 - smoothstep(0.1, 0.4, t));
	c.rgb += core_color * rim * intensity;
	// Ragged deep-blue tendrils trailing off the outer edge, additive so they stay see-through.
	float spikes = fbm(vec2(atan(p.y, p.x) * 6.0, r * 2.0 - t * 1.5) + seed + 2.0);
	float tendril = step(0.86, r) * step(r, 0.86 + spikes * 0.55 * (1.0 - t * 0.7) - 0.1) * reach * step(0.05, p.x);
	tendril *= 1.0 - smoothstep(0.35, 0.75, t);
	c.rgb += deep_color * tendril * 0.6 * intensity;
	return c;
}

vec4 flash(vec2 p) {
	float t = progress;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float rays = pow(ring_noise(angle, 0.0, 9.0, seed), 3.0) + pow(ring_noise(angle, 1.0, 23.0, seed + 3.0), 6.0) * 0.8;
	float reach = mix(0.35, 1.0, sqrt(t));
	float streak = rays * (1.0 - smoothstep(0.0, reach, r)) * 2.2;
	float core = 1.0 - smoothstep(0.0, mix(0.18, 0.3, t), r);
	float glow = exp(-r * 4.0) * 0.8;
	float fade = 1.0 - smoothstep(0.25, 1.0, t);
	vec3 color = mix(bright_color, core_color, clamp(core + streak * 0.5, 0.0, 1.0)) * (streak + glow) + core_color * core * 1.5;
	return vec4(color * fade * intensity, 0.0);
}

vec4 pillar(vec2 uv) {
	float t = progress;
	float x = abs(uv.x - 0.5) * 2.0;
	float width = mix(0.55, 0.08, smoothstep(0.0, 1.0, t));
	float beam = 1.0 - smoothstep(width * 0.3, width, x);
	float core = 1.0 - smoothstep(0.0, width * 0.3, x);
	float lines = smoothstep(0.6, 0.9, noise(vec2(uv.x * 30.0 + seed, uv.y * 2.0 - t * 8.0)));
	// Bright at the ground, thinning out toward the top.
	float top = smoothstep(0.0, 0.6, uv.y);
	float fade = 1.0 - smoothstep(0.3, 1.0, t);
	vec3 color = mix(bright_color, core_color, core) * (beam + lines * beam * 0.6) + core_color * core;
	return vec4(color * top * fade * intensity, 0.0);
}

vec4 shell(vec2 uv, vec3 n) {
	float t = progress;
	float spin = uv.x * 3.0 + uv.y * 2.4 + t * 1.7 + seed;
	float arcs = smoothstep(0.42, 0.47, abs(fract(spin) - 0.5));
	float breakup = smoothstep(0.35, 0.65, noise(vec2(uv.x * 14.0 + seed, uv.y * 6.0 + t * 3.0)));
	float rim = pow(1.0 - abs(n.z), 1.5);
	float fade = (1.0 - smoothstep(0.35, 1.0, t)) * smoothstep(0.0, 0.08, t);
	vec3 color = mix(deep_color, core_color, arcs) * (arcs * breakup + rim * 0.15);
	return vec4(color * fade * intensity, 0.0);
}

vec4 nebula(vec2 p) {
	float t = progress;
	float r = length(p);
	vec2 warp = vec2(fbm(p * 2.0 + seed + t * 0.3), fbm(p * 2.0 + seed + 7.0 - t * 0.3));
	float v = fbm(p * 2.6 + warp * 1.8 + seed);
	float mask = (1.0 - smoothstep(0.35, 1.0, r)) * smoothstep(0.3, 0.75, v);
	float fade = smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.4, 1.0, t));
	vec3 color = mix(deep_color * 0.6, bright_color, smoothstep(0.6, 0.85, v)) * mask;
	return vec4(color * fade * intensity, 0.0);
}

vec4 star(vec2 p) {
	// param.x: ray length (0 for a round dot).
	float t = progress;
	float twinkle = sin(t * 3.14159265) * (0.75 + 0.25 * sin(t * 40.0 + seed * 9.0));
	float r = length(p);
	float dot_glow = exp(-r * 9.0) * 1.2 + (1.0 - smoothstep(0.03, 0.08, r));
	float rays = 0.0;
	if (param.x > 0.0) {
		vec2 a = abs(p);
		rays = (1.0 - smoothstep(0.0, 0.04, a.y)) * (1.0 - smoothstep(0.0, param.x, a.x));
		rays += (1.0 - smoothstep(0.0, 0.04, a.x)) * (1.0 - smoothstep(0.0, param.x, a.y));
	}
	vec3 color = mix(bright_color, core_color, clamp(dot_glow + rays * 0.6, 0.0, 1.0)) * (dot_glow + rays);
	return vec4(color * twinkle * intensity, 0.0);
}

vec4 smoke(vec2 p) {
	float t = progress;
	float r = length(p);
	float v = fbm(p * 3.0 + vec2(seed, -t * 0.8)) - r * 0.9;
	float cut = mix(0.0, 0.25, t);
	float mask = smoothstep(cut, cut + 0.1, v);
	float fade = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.4, 1.0, t));
	vec3 grey = mix(vec3(0.35, 0.37, 0.42), vec3(0.75, 0.78, 0.85), smoothstep(0.1, 0.4, v));
	return vec4(grey * mask * fade * 0.7, mask * fade * 0.6);
}

vec4 sparks(vec2 p) {
	float t = progress;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float id = floor((angle + 3.14159265) / 6.2831853 * 26.0);
	float on = step(0.45, hash(vec2(id, seed)));
	float len = 0.15 + hash(vec2(id, seed + 1.0)) * 0.25;
	float head = mix(0.05, 0.95, sqrt(t)) * (0.6 + 0.4 * hash(vec2(id, seed + 2.0)));
	float along = 1.0 - smoothstep(0.0, len, head - r) - (1.0 - step(r, head));
	float across = 1.0 - smoothstep(0.0, 0.25, abs(fract((angle + 3.14159265) / 6.2831853 * 26.0) - 0.5) * 2.0);
	float fade = 1.0 - smoothstep(0.5, 1.0, t);
	float s = on * clamp(along, 0.0, 1.0) * across * fade;
	return vec4(core_color * s * intensity, 0.0);
}

vec4 ink(vec2 p) {
	float t = progress;
	float r = length(p);
	float v = fbm(p * 3.5 + seed) - r * 1.1 + 0.45;
	float cut = mix(0.0, 0.5, smoothstep(0.3, 1.0, t));
	float mask = smoothstep(cut, cut + 0.03, v) * smoothstep(0.0, 0.08, t);
	// Deep-blue blot that only adds light, so it never shows as a black patch.
	return vec4(mix(deep_color, bright_color, smoothstep(cut + 0.1, cut + 0.3, v)) * mask * 0.7 * intensity, 0.0);
}

vec4 streak(vec2 uv) {
	// Thin line along U, drawn out to the head then shrinking behind it.
	float t = progress;
	float head = clamp(t / 0.3, 0.0, 1.0);
	float tail = clamp((t - 0.3) / 0.7, 0.0, 1.0);
	float on = step(uv.x, head) * step(tail, uv.x);
	float y = abs(uv.y - 0.5) * 2.0;
	float line = 1.0 - smoothstep(0.05, 0.3, y);
	float core = 1.0 - smoothstep(0.0, 0.08, y);
	vec3 color = (deep_color * line + core_color * core) * on * (0.4 + 0.6 * uv.x);
	return vec4(color * intensity, 0.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec4 c = vec4(0.0);
	if (mode == FLAME) c = flame_ring(p);
	else if (mode == WIND) c = wind_ring(p);
	else if (mode == CRESCENT) c = crescent(vec2(p.x, -p.y));
	else if (mode == FLASH) c = flash(p);
	else if (mode == PILLAR) c = pillar(UV);
	else if (mode == SHELL) c = shell(UV, local_normal_view);
	else if (mode == NEBULA) c = nebula(p);
	else if (mode == STAR) c = star(p);
	else if (mode == SMOKE) c = smoke(p);
	else if (mode == SPARKS) c = sparks(p);
	else if (mode == INK) c = ink(p);
	else if (mode == STREAK) c = streak(UV);
	ALBEDO = c.rgb * opacity;
	ALPHA = clamp(c.a * opacity, 0.0, 1.0);
}
