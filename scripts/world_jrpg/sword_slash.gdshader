shader_type spatial;
// Pre-shaped slash arc driven only by `progress` (0 → 1 over the whole effect):
// the lit crescent shoots out behind a leading tip, flashes at the full swing (`peak`),
// then collapses to a thin afterglow that stretches back along the arc while the tip burns away.
// UV.x runs along the swing (0 start, 1 full swing); UV.y from the inner edge (0) to the outer edge (1).
// Premultiplied alpha lets the light add onto the scene while still slightly covering it.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha;

uniform float progress = 0.0;
uniform float peak = 0.3;
uniform float trail_length = 0.75;
uniform float thickness = 0.7;
uniform vec4 core_color : source_color = vec4(1.0, 0.99, 0.93, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec4 fade_color : source_color = vec4(0.95, 0.4, 0.08, 1.0);
uniform float intensity = 1.6;
uniform float peak_flash = 1.0;
uniform float afterglow_width = 0.07;
uniform float afterglow_stretch = 0.25;
uniform float afterglow_fade = 1.6;
// Driven by the player to fade an interrupted attack.
uniform float opacity = 1.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float swing = clamp(progress / max(peak, 1e-4), 0.0, 1.0);
	float after = clamp((progress - peak) / max(1.0 - peak, 1e-4), 0.0, 1.0);
	// The tip shoots out and eases into the full swing.
	float head = 1.0 - (1.0 - swing) * (1.0 - swing);
	// Lit length behind the tip; the afterglow stretches it back as it fades.
	float span = max(trail_length + afterglow_stretch * after, 1e-3);
	float a = (head - u) / span;
	// After the full swing the tip burns away backward.
	float front = head - smoothstep(0.0, 0.8, after) * span * 0.6;
	float along = step(0.0, a) * (1.0 - smoothstep(0.75, 1.0, a)) * (1.0 - smoothstep(front - 0.03, front, u));
	// Crescent: thickest just behind the tip, tapering to a point at the tail.
	float body = thickness * pow(sin(3.14159 * mix(0.12, 1.0, clamp(a, 0.0, 1.0))), 0.6) * (1.0 - 0.35 * a);
	// The body collapses into a thin line once the swing is through.
	float settle = smoothstep(0.0, 0.35, after);
	body = mix(body, afterglow_width * (1.0 - 0.5 * clamp(a, 0.0, 1.0)), settle);
	body = max(body, 1e-3);
	float t = (v - (1.0 - body)) / body;
	// Soft inner shoulder, crisp outer rim.
	float rim = max(fwidth(t), 1e-3);
	float shape = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(1.0 - rim, 1.0, t)) * along;
	// White-hot band along the rim, widest behind the tip; the thin afterglow is all core.
	float d = 1.0 - clamp(t, 0.0, 1.0);
	float core_depth = mix(mix(0.6, 0.15, clamp(a, 0.0, 1.0)), 1.1, settle);
	float core = 1.0 - smoothstep(core_depth - 0.05, core_depth + 0.05, d);
	float cool = clamp(a * 0.8 + after * 0.6, 0.0, 1.0);
	vec3 color = mix(glow_color.rgb, fade_color.rgb, cool);
	color = mix(color, core_color.rgb, core * (1.0 - 0.5 * after));
	float flash = 1.0 + peak_flash * exp(-pow((progress - peak) / 0.07, 2.0));
	float appear = smoothstep(0.0, 0.2, swing);
	float vanish = 1.0 - pow(after, afterglow_fade);
	float fade = appear * vanish * (1.0 - 0.5 * clamp(a, 0.0, 1.0)) * opacity;
	float fill = shape * mix(0.45, 1.0, core);
	ALBEDO = color * fill * intensity * flash * fade;
	ALPHA = clamp(fill * 0.5 * fade, 0.0, 1.0);
}
