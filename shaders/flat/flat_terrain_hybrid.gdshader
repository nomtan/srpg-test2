shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"
#include "res://shaders/flat/flat_grass_dirt_boundary.gdshaderinc"

// Plan A+ (hybrid preview): keeps Plan A's flat top (base_color +
// apply_variation, no baked texture) but swaps Plan A's procedural strata
// banding on side faces for Plan B's pixel-art albedo, so soil/grass block
// side faces read as textured while the top stays the solid-color direction.
uniform vec3 base_color : source_color;
uniform sampler2D side_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 side_tint = vec3(1.0);
uniform float side_brightness : hint_range(0.3, 1.5) = 1.0;

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec3 wn = world_normal();
    vec3 wp = world_pos();
    vec3 col;
    if (wn.y > 0.5) {
        vec3 varied_top = apply_variation(
            base_color,
            variation_tile_id(wp, wn)
        );
        col = mix(
            varied_top,
            grass_dirt_boundary_color(wp),
            grass_dirt_boundary_mask(wp)
        );
    } else if (wn.y < -0.5) {
        // Hidden underside; never visible, so skip texturing it.
        col = base_color;
    } else {
        col = texture(side_tex, world_side_uv(wp, wn)).rgb * side_tint;
        col = apply_variation(col, variation_tile_id(wp, wn));
        col *= side_brightness;
    }
    ALBEDO = col * face_factor(wn);
}
