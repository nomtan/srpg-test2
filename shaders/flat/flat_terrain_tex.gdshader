shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"

// Plan B: keep the existing 32x32 pixel-art albedo. Only the albedo source
// differs from flat_terrain_solid.gdshader - tile variation still applies
// (hue-shifts the whole texture per tile so B gets individual-tile identity
// too), but strata is skipped since it would fight the baked texture
// pattern.
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 style_tint = vec3(1.0);
uniform float side_brightness : hint_range(0.3, 1.5) = 1.0;

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec3 wn = world_normal();
    vec3 wp = world_pos();
    vec2 sample_uv = abs(wn.y) < 0.5 ? world_side_uv(wp, wn) : UV;
    vec3 col = texture(albedo_tex, sample_uv).rgb * style_tint;
    col = apply_variation(col, variation_tile_id(wp, wn));
    if (abs(wn.y) < 0.5) {
        col *= side_brightness;
    }
    ALBEDO = col * face_factor(wn);
}
