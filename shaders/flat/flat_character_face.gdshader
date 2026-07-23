shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"

// Face texture quad companion to flat_character.gdshader - same unshaded +
// face_factor treatment, textured instead of solid so the face art shows.
uniform sampler2D albedo_texture : source_color;

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec4 face = texture(albedo_texture, UV);
    ALBEDO = face.rgb * face_factor(world_normal());
    ALPHA = face.a;
}
