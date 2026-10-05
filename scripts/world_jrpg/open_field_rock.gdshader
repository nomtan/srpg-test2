shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// Boulders, cliff slabs and ruin masonry: grained stone with moss on upward faces.
// COLOR.r is baked ambient occlusion (missing vertex colors default to white).
uniform vec4 stone : source_color = vec4(0.55, 0.58, 0.63, 1.0);
uniform float moss = 0.7;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 n = normalize(world_normal);
    vec3 wp = world_position;
    float grain = of_noise(wp.xz * 0.9 + wp.y * 0.7);
    float fine = of_noise(wp.xz * 4.0 + wp.y * 3.0);
    vec3 color = stone.rgb * (0.82 + grain * 0.22 + fine * 0.08) * mix(0.6, 1.0, COLOR.r);
    float top = smoothstep(0.55, 0.85, n.y) * moss * smoothstep(0.3, 0.6, of_noise(wp.xz * 0.5 + 3.0) + 0.25);
    color = mix(color, of_to_linear(of_grass_tinted(wp.xz, of_biome(wp.xz).rgb)) * 0.9, top);
    color = mix(color, vec3(0.82, 0.88, 0.93), snow_cover * smoothstep(0.5, 0.9, n.y));
    color *= 1.0 - wetness * 0.25;
    ALBEDO = color;
    ROUGHNESS = mix(0.9, 0.4, wetness);
    SPECULAR = 0.3;
}
