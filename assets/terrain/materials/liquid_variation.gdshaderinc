// World-tile hue variation shared by water and lava. Keeping this separate
// from flat_core avoids pulling terrain face/strata uniforms into liquids.
uniform float tile_size : hint_range(0.1, 4.0) = 1.0;
uniform float hue_jitter : hint_range(0.0, 0.15) = 0.0;

varying vec3 liquid_world_pos;
varying flat vec3 liquid_world_normal;

#define LIQUID_VERTEX_SETUP liquid_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; liquid_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;

float liquid_hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 liquid_rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 liquid_hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

vec3 apply_liquid_variation(vec3 base) {
	vec3 n = abs(normalize(liquid_world_normal));
	vec2 face_position;
	if (n.y >= n.x && n.y >= n.z) {
		face_position = liquid_world_pos.xz;
	} else if (n.x >= n.z) {
		face_position = liquid_world_pos.zy;
	} else {
		face_position = liquid_world_pos.xy;
	}
	vec2 tile_id = floor(face_position / max(tile_size, 0.001));
	vec3 hsv = liquid_rgb2hsv(base);
	hsv.x = fract(hsv.x + (liquid_hash21(tile_id) - 0.5) * hue_jitter);
	return liquid_hsv2rgb(hsv);
}
