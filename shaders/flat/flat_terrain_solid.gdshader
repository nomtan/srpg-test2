shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"

// Plan A: one flat color per tile. Variation comes entirely from
// apply_variation() (tile hue jitter) and apply_strata() (cliff banding),
// not from any texture.
uniform vec3 base_color : source_color;

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec3 wn = world_normal();
    vec3 wp = world_pos();
    vec3 col = base_color;
    if (wn.y > 0.5) {
        col = apply_variation(col, floor(wp.xz / tile_size));
    } else if (abs(wn.y) < 0.5) {
        col = apply_strata(col, wp.y);
    }
    ALBEDO = col * face_factor(wn);
}
