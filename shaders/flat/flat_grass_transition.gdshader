shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

#include "res://shaders/flat/flat_core.gdshaderinc"

// One overlay plane handles every grass->dirt autotile combination. VoxelMap
// supplies the four edge and four diagonal-corner flags from the cell's
// eight neighbors. The boundary is quantized to 32 pixels and receives a
// deterministic 1-3 px wobble so it reads as authored pixel art rather than
// a mathematically straight strip.
uniform sampler2D grass_tex : source_color, filter_nearest_mipmap;
uniform vec3 style_tint = vec3(1.0);
uniform float fringe_width : hint_range(0.08, 0.40) = 0.22;

uniform bool edge_n = false;
uniform bool edge_e = false;
uniform bool edge_s = false;
uniform bool edge_w = false;
uniform bool corner_ne = false;
uniform bool corner_se = false;
uniform bool corner_sw = false;
uniform bool corner_nw = false;

float pixel_hash(float value, float salt) {
    return fract(sin(value * 91.17 + salt * 37.31) * 43758.5453);
}

float edge_depth(float coordinate, float salt) {
    float pixel = floor(coordinate * 32.0);
    float wobble = (pixel_hash(pixel, salt) - 0.5) * 0.10;
    return fringe_width + wobble;
}

float corner_fill(vec2 from_corner, float salt) {
    vec2 pixel_uv = floor(from_corner * 32.0) / 32.0;
    float distance_from_corner = length(pixel_uv);
    float wobble = (pixel_hash(pixel_uv.x * 32.0 + pixel_uv.y * 71.0, salt) - 0.5) * 0.07;
    return 1.0 - step(fringe_width * 1.22 + wobble, distance_from_corner);
}

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec2 uv = floor(UV * 32.0) / 32.0;
    float mask = 0.0;

    if (edge_n) mask = max(mask, 1.0 - step(edge_depth(uv.x, 1.0), uv.y));
    if (edge_s) mask = max(mask, step(1.0 - edge_depth(uv.x, 2.0), uv.y));
    if (edge_w) mask = max(mask, 1.0 - step(edge_depth(uv.y, 3.0), uv.x));
    if (edge_e) mask = max(mask, step(1.0 - edge_depth(uv.y, 4.0), uv.x));

    if (corner_nw) mask = max(mask, corner_fill(uv, 5.0));
    if (corner_ne) mask = max(mask, corner_fill(vec2(1.0 - uv.x, uv.y), 6.0));
    if (corner_se) mask = max(mask, corner_fill(vec2(1.0 - uv.x, 1.0 - uv.y), 7.0));
    if (corner_sw) mask = max(mask, corner_fill(vec2(uv.x, 1.0 - uv.y), 8.0));

    vec4 tex = texture(grass_tex, UV);
    ALPHA = tex.a * mask;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    vec3 col = apply_variation(tex.rgb * style_tint, floor(world_pos().xz / tile_size));
    ALBEDO = col * face_top;
}
