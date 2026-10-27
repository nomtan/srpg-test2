shader_type spatial;
// Enemy look: the painted Tripo texture shown flat (as character_toon with shade_strength = 0),
// plus a per-instance dissolve that burns the model away into dust from glowing edges.
render_mode unshaded;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
// Edge glow while dissolving.
uniform vec3 ember_color : source_color = vec3(1.0, 0.52, 0.22);
uniform float ember_width = 0.08;
// Noise cells per metre of model space.
uniform float noise_scale = 18.0;
// 0 = whole, 1 = gone. Set per mesh with set_instance_shader_parameter, so instances sharing
// this material dissolve independently.
instance uniform float dissolve = 0.0;

varying vec3 model_position;

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

void vertex() {
	// Skinned, so the pattern stays on the body as it moves.
	model_position = VERTEX;
}

void fragment() {
	vec3 color = texture(base_color_texture, UV).rgb;
	if (dissolve > 0.0) {
		float n = noise(model_position * noise_scale) * 0.65 + noise(model_position * noise_scale * 2.7) * 0.35;
		float threshold = dissolve * (1.0 + ember_width) - ember_width * 0.5;
		if (n < threshold) {
			discard;
		}
		// Ashen as it goes, glowing at the burning edge.
		color = mix(color, vec3(dot(color, vec3(0.3, 0.59, 0.11))) * 0.6, clamp(dissolve * 2.0, 0.0, 1.0));
		color = mix(color, ember_color * 1.6, 1.0 - smoothstep(threshold, threshold + ember_width, n));
	}
	ALBEDO = color;
}
