shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"

// Plan B: keep the existing 32x32 pixel-art albedo. Only the albedo source
// differs from flat_terrain_solid.gdshader - tile variation still applies
// (hue-shifts the whole texture per tile so B gets individual-tile identity
// too), but strata is skipped since it would fight the baked texture
// pattern.
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec3 style_tint = vec3(1.0);

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec3 wn = world_normal();
    vec3 wp = world_pos();
    vec3 col = texture(albedo_tex, UV).rgb * style_tint;
    col = apply_variation(col, floor(wp.xz / tile_size));
    ALBEDO = col * face_factor(wn);
}
