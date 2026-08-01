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
uniform sampler2D albedo_tex_nearest : source_color, filter_nearest_mipmap;
uniform sampler2D albedo_tex_linear : source_color, filter_linear_mipmap;
uniform float antialiasing_strength : hint_range(0.0, 1.0) = 0.35;
uniform float mip_bias : hint_range(0.0, 2.0) = 0.0;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec3 style_tint = vec3(1.0);
uniform vec3 user_tint : source_color = vec3(0.48, 0.68, 0.32);
uniform float tint_blend : hint_range(0.0, 1.0) = 0.0;

// Per-tuft (not per-pixel, not per-quad) variation: every quad in a tuft
// shares the instance's own origin, so all 3 quads get the identical hue
// jitter while neighboring tufts differ.
varying flat vec3 flat_instance_origin;

void vertex() {
    FLAT_VERTEX_SETUP
    flat_instance_origin = MODEL_MATRIX[3].xyz;
}

void fragment() {
    vec4 nearest_tex = texture(albedo_tex_nearest, UV, mip_bias);
    vec4 linear_tex = texture(albedo_tex_linear, UV, mip_bias);
    vec4 tex = mix(nearest_tex, linear_tex, antialiasing_strength);
    // Linear mip filtering softens minified stair steps. Keep the authored
    // alpha cut so transparent texels do not form dark halos around blades.
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
    vec3 base_col = tex.rgb * style_tint;
    float tint_value = max(max(base_col.r, base_col.g), base_col.b);
    vec3 tinted_col = user_tint * tint_value;
    vec3 blended_col = mix(base_col, tinted_col, tint_blend);
    vec3 col = apply_variation(blended_col, floor(flat_instance_origin.xz / tile_size));
    ALBEDO = col * face_top;
}
