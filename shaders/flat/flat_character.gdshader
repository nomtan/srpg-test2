shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"

// Single flat albedo per surface. No tile variation, no strata - characters
// aren't the thing individual-difference is meant to sell here.
uniform vec3 albedo_color : source_color;

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    ALBEDO = albedo_color * face_factor(world_normal());
}
