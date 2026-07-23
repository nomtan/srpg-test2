shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Transparent painted grass sits over a dirt-colored block. VoxelMap marks
// only edges/corners that touch same-height dirt, producing an organic inset
// there. The texture itself is a low ground-cover decal; upright long grass is
// intentionally supplied by separate decoration assets.
uniform sampler2D grass_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float fringe_width : hint_range(0.08, 0.40) = 0.18;
uniform float pattern_seed = 0.0;
uniform float overlay_scale = 1.0;
uniform int texture_turn : hint_range(0, 3) = 0;
uniform float texture_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float texture_tile_size : hint_range(0.1, 4.0) = 1.0;
uniform float texture_brightness : hint_range(0.3, 2.0) = 1.0;

uniform bool trim_n = false;
uniform bool trim_e = false;
uniform bool trim_s = false;
uniform bool trim_w = false;
uniform bool trim_ne = false;
uniform bool trim_se = false;
uniform bool trim_sw = false;
uniform bool trim_nw = false;

float pixel_hash(float value, float salt) {
    return fract(sin(value * 91.17 + salt * 37.31 + pattern_seed * 0.071) * 43758.5453);
}

float edge_depth(float coordinate, float salt) {
    float pixel = floor(coordinate * 32.0);
    float wobble = (pixel_hash(pixel, salt) - 0.5) * 0.11;
    return clamp(fringe_width + wobble, 0.06, 0.38);
}

float keep_outside_corner(vec2 from_corner, float salt) {
    vec2 pixel_uv = floor(from_corner * 32.0) / 32.0;
    float wobble = (pixel_hash(pixel_uv.x * 32.0 + pixel_uv.y * 71.0, salt) - 0.5) * 0.07;
    return step(fringe_width * 1.18 + wobble, length(pixel_uv));
}

vec2 rotate_texture_uv(vec2 uv) {
    if (texture_turn == 1) return vec2(1.0 - uv.y, uv.x);
    if (texture_turn == 2) return vec2(1.0 - uv.x, 1.0 - uv.y);
    if (texture_turn == 3) return vec2(uv.y, 1.0 - uv.x);
    return uv;
}

void fragment() {
    // The mesh may overlap adjacent grass cells. cell_uv keeps the trim mask
    // aligned to the original one-cell footprint while texture_uv rotates only
    // the painted marks, never the map-facing north/east/south/west flags.
    vec2 cell_uv = (UV - vec2(0.5)) * overlay_scale + vec2(0.5);
    vec2 uv = floor(cell_uv * 32.0) / 32.0;
    float keep = 1.0;

    if (trim_n) keep *= step(edge_depth(uv.x, 1.0), uv.y);
    if (trim_s) keep *= step(edge_depth(uv.x, 2.0), 1.0 - uv.y);
    if (trim_w) keep *= step(edge_depth(uv.y, 3.0), uv.x);
    if (trim_e) keep *= step(edge_depth(uv.y, 4.0), 1.0 - uv.x);

    if (trim_nw) keep *= keep_outside_corner(uv, 5.0);
    if (trim_ne) keep *= keep_outside_corner(vec2(1.0 - uv.x, uv.y), 6.0);
    if (trim_se) keep *= keep_outside_corner(vec2(1.0 - uv.x, 1.0 - uv.y), 7.0);
    if (trim_sw) keep *= keep_outside_corner(vec2(uv.x, 1.0 - uv.y), 8.0);

    vec2 texture_uv = rotate_texture_uv(UV);
    texture_uv = (texture_uv - vec2(0.5)) / max(texture_tile_size, 0.001) + vec2(0.5);
    vec4 tex = texture(grass_tex, texture_uv);
    ALBEDO = tex.rgb * texture_brightness;
    ALPHA = tex.a * keep * texture_opacity;
    ALPHA_SCISSOR_THRESHOLD = 0.05;
}
