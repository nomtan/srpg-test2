shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, unshaded, cull_back;

#include "res://shaders/flat/flat_core.gdshaderinc"
#include "res://shaders/flat/pixel_character_core.gdshaderinc"

// Face texture quad companion to flat_character.gdshader - same unshaded +
// face_factor treatment, textured instead of solid so the face art shows.
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec2 face_texture_resolution = vec2(32.0, 28.0);

void vertex() {
    FLAT_VERTEX_SETUP
}

void fragment() {
    vec2 resolution = max(face_texture_resolution, vec2(1.0));
    vec2 pixel_uv = (floor(UV * resolution) + 0.5) / resolution;
    vec4 face = texture(albedo_texture, pixel_uv);
    vec3 shaded = face.rgb * face_factor(world_normal());
    ALBEDO = pixel_palette(shaded, FRAGCOORD.xy);
    ALPHA = face.a;
}
