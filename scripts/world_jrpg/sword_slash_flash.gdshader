shader_type spatial;
// Cel-look impact flash: a hard-edged four-point star with an ink outline, drawn on a billboard quad.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_mix;

uniform vec4 fill_color : source_color = vec4(0.97, 1.0, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.12, 0.14, 0.38, 1.0);
// 0 → 1 over the flash; the star thins out instead of fading.
uniform float progress = 0.0;

float cel(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((x - edge) / w + 0.5, 0.0, 1.0);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	// Astroid-like star: long spikes on the axes, pinched between them.
	float star = pow(p.x, 0.45) + pow(p.y, 0.45);
	float radius = mix(1.0, 0.55, progress);
	float thin = 1.0 - progress * 0.6;
	float dist = radius * thin - star * mix(0.9, 1.3, progress);
	float shape = cel(0.0, dist);
	float fill = cel(0.08, dist);
	vec3 color = mix(fill_color.rgb, core_color.rgb, cel(0.4, dist) * (1.0 - progress));
	ALBEDO = mix(outline_color.rgb, color, fill);
	ALPHA = shape * cel(progress, 0.98);
}
