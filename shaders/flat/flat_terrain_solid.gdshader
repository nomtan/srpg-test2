shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"
#include "res://shaders/flat/flat_grass_dirt_boundary.gdshaderinc"

// Plan A: one flat color per tile. Variation comes entirely from
// apply_variation() (tile hue jitter) and apply_strata() (cliff banding),
// not from any texture.
uniform vec3 base_color : source_color;
uniform float side_brightness : hint_range(0.3, 1.5) = 1.0;

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec3 wn = world_normal();
    vec3 wp = world_pos();
    vec3 col = base_color;
    if (wn.y > 0.5) {
        vec3 varied_top = apply_variation(col, variation_tile_id(wp, wn));
        col = mix(
            varied_top,
            grass_dirt_boundary_color(wp),
            grass_dirt_boundary_mask(wp)
        );
    } else if (abs(wn.y) < 0.5) {
        col = apply_strata(col, wp.y);
        col = apply_variation(col, variation_tile_id(wp, wn));
        col *= side_brightness;
    }
    ALBEDO = col * face_factor(wn);
}
