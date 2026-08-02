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
// Procedural leaf pattern controls
uniform float leaf_opacity : hint_range(0.0, 1.0) = 0.9;
const int LEAF_COUNT = 4;

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
    // Use the authored alpha for silhouette, but replace RGB with a
    // simple two-tone solid approach to match the pixel-art reference.
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_threshold;

    // Vertical mask inside each blade quad separates bright tops and
    // darker bases to create a two-tone silhouette.
    float top_mask = smoothstep(0.45, 0.65, UV.y);
    vec3 top_color = user_tint * 1.05;
    vec3 base_color = user_tint * 0.58;
    vec3 two_tone = mix(base_color, top_color, top_mask);

    // Per-tuft variation (tile-quantized)
    vec2 tuft_tile = floor(flat_instance_origin.xz / max(tile_size, 0.001));
    vec3 varied = apply_variation(two_tone, tuft_tile);

    // Procedural leaf marks: place a small number of ellipse-shaped
    // "leaves" in UV space per tuft. They are deterministic per-tile
    // via the tuft_tile seed and blend as darker patches over the base.
    float leaf_mask = 0.0;
    for (int i = 0; i < LEAF_COUNT; i++) {
        vec2 seed = tuft_tile + vec2(float(i) * 12.9898, float(i) * 78.233);
        float rx = hash21(seed + vec2(0.12, 0.34));
        float ry = hash21(seed + vec2(4.56, 7.89));
        float ang = hash21(seed + vec2(9.01, 3.27)) * 6.2831853;
        // Larger leaf marks for each tuft to match the reference scale
        float sx = 0.06 + hash21(seed + vec2(1.0, 2.0)) * 0.18;
        float sy = 0.04 + hash21(seed + vec2(3.0, 5.0)) * 0.12;
        vec2 center = vec2(0.12 + rx * 0.72, 0.10 + ry * 0.72);
        vec2 p = UV - center;
        float ca = cos(ang);
        float sa = sin(ang);
        vec2 rp = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
        float r = length(vec2(rp.x / max(sx, 0.0001), rp.y / max(sy, 0.0001)));
        float s = 1.0 - smoothstep(0.35, 0.95, r);
        leaf_mask = max(leaf_mask, s);
    }

    // Darker leaf color blended over the two-tone base using the leaf mask.
    vec3 leaf_color = varied * 0.72;
    vec3 final_col = mix(varied, leaf_color, clamp(leaf_mask * leaf_opacity, 0.0, 1.0));

    // Flat brightness across the tuft to preserve stylized look.
    ALBEDO = final_col * face_top;
}
