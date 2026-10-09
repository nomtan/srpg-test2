shader_type spatial;
render_mode specular_disabled;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// Low-poly anime trees (open_field_toon_trees.gd). Opaque and static: no wind, no alpha
// cards. Vertex COLOR: rgb = painted sRGB color, a = 1 foliage / 0 bark. Lighting is three
// flat cel bands (cool shade / lit / warm sunlit cap) plus a thin rim, so each puff of the
// crown reads as a round, sunlit ball.
uniform float biome_harmony = 0.3;
uniform float band_threshold = 0.45;
uniform float band_softness = 0.03;
// Shadow from other casters, banded into flat painted shapes.
uniform float shadow_band = 0.5;
uniform float shadow_softness = 0.25;
uniform float shade_level = 0.42;
uniform vec3 shade_tint : source_color = vec3(0.7, 0.85, 1.1);
uniform float highlight_threshold = 0.82;
uniform float highlight_strength = 0.2;
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.97, 0.72);
uniform float rim = 0.3;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 tree_tint;
varying vec3 world_normal;
varying vec3 debug_color;

void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    vec4 biome = of_biome(origin.xz);
    vec3 harmony = clamp(biome.rgb / vec3(0.48, 0.64, 0.29), vec3(0.7), vec3(1.3));
    float h = of_hash(origin.xz);
    // Per-tree palette shift (biome harmony and variation), foliage only.
    vec3 tint = mix(vec3(1.0), harmony, biome_harmony) * mix(vec3(0.95, 1.0, 1.03), vec3(1.05, 1.02, 0.92), h) * (0.95 + 0.1 * of_hash(origin.xz + 3.1));
    tree_tint = mix(vec3(1.0), tint, COLOR.a);
    debug_color = biome_debug > 0.5 ? of_biome_debug(origin.xz) : vec3(-1.0);
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 color = COLOR.rgb * tree_tint;
    if (debug_color.x >= 0.0 && COLOR.a > 0.5) color = debug_color;
    color = mix(color, vec3(0.92, 0.95, 0.98), snow_cover * smoothstep(0.2, 0.7, world_normal.y) * 0.8);
    color *= 1.0 - wetness * 0.2;
    ALBEDO = of_to_linear(color);
    ROUGHNESS = 1.0;
}

void light() {
    float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
    float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
    vec3 sun = LIGHT_COLOR / PI;
    if (LIGHT_IS_DIRECTIONAL) {
        float shadow = smoothstep(shadow_band - shadow_softness, shadow_band + shadow_softness, ATTENUATION);
        float band = lit * shadow;
        DIFFUSE_LIGHT += mix(shade_level * shade_tint, vec3(1.0), band) * sun;
        float cap = smoothstep(highlight_threshold - band_softness, highlight_threshold + band_softness, ndl);
        DIFFUSE_LIGHT += cap * band * highlight_strength * highlight_tint * sun;
        float edge = smoothstep(0.55, 0.75, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
        DIFFUSE_LIGHT += edge * rim * band * sun * vec3(1.0, 1.0, 0.8);
    } else {
        DIFFUSE_LIGHT += lit * ATTENUATION * sun;
    }
}
