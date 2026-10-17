shader_type spatial;
render_mode specular_disabled;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// Trunks and branches of the seed-driven illustration trees (tools/vegetation/build_seed_trees.py).
// Vertex COLOR: rgb = painted sRGB bark brown (dull brown foot -> deep umber limbs).
// UV: the tileable bark texture (u around the branch, v along it); its grey value carves the
// fissures and grain into the brown. Lit with the same soft, wrapped falloff as the crowns.
uniform sampler2D bark_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// How deep the fissures and grain cut into the painted brown.
uniform float bark_contrast = 1.0;
uniform float wrap_low = -0.35;
uniform float wrap_high = 0.9;
uniform float shade_level = 0.55;
uniform vec3 shade_tint : source_color = vec3(0.8, 0.86, 1.0);
uniform float shadow_strength = 0.7;
uniform float fill = 0.1;
uniform float wetness = 0.0;
// 0 = summer, 0.8 = snow weather (open_field_world sets it): snow settles on upward faces.
uniform float snow_cover = 0.0;
varying vec3 world_normal;

void vertex() {
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float bark = texture(bark_texture, UV).r;
    vec3 color = COLOR.rgb * mix(1.0, bark * 1.25, bark_contrast);
    color *= 1.0 - wetness * 0.25;
    color = mix(color, vec3(0.9, 0.93, 0.97), snow_cover * smoothstep(0.35, 0.85, world_normal.y));
    ALBEDO = of_to_linear(color);
    EMISSION = ALBEDO * fill;
    ROUGHNESS = 1.0;
}

void light() {
    float lit = smoothstep(wrap_low, wrap_high, dot(NORMAL, LIGHT));
    vec3 sun = LIGHT_COLOR / PI;
    if (LIGHT_IS_DIRECTIONAL) {
        lit *= mix(1.0, ATTENUATION, shadow_strength);
        DIFFUSE_LIGHT += mix(shade_level * shade_tint, vec3(1.0), lit) * sun;
    } else {
        DIFFUSE_LIGHT += lit * ATTENUATION * sun;
    }
}
