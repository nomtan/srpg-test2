shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

#include "res://shaders/flat/flat_core.gdshaderinc"

// Cross-quad foliage (grass_short/grass_tall - see build_grass_props.py's
// build_cross(), a 45/135-degree 2-quad cross). Deliberately does NOT run
// face_factor(): each quad in a tuft has a different world normal, so
// face-shading them independently would light the quads to different
// brightnesses and the tuft would visibly fall apart into separate cards.
// Multiplying by face_top directly keeps the whole tuft one flat brightness
// (see docs/dev/phase/phase17-step1-fix.md F2).
//
// A/B terrain toggling in flat_validation.gd does NOT touch this shader -
// vegetation always renders this way regardless of Plan A/B, so the A/B
// comparison stays scoped to the ground tiles only.
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec3 style_tint = vec3(1.0);

// Per-tuft (not per-pixel, not per-quad) variation: every quad in a tuft
// shares the instance's own origin, so all 3 quads get the identical hue
// jitter while neighboring tufts differ.
varying flat vec3 flat_instance_origin;

void vertex() {
    FLAT_VERTEX_SETUP
    flat_instance_origin = MODEL_MATRIX[3].xyz;
}

void fragment() {
    vec4 tex = texture(albedo_tex, UV);
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
    vec3 col = apply_variation(tex.rgb * style_tint, floor(flat_instance_origin.xz / tile_size));
    ALBEDO = col * face_top;
}
