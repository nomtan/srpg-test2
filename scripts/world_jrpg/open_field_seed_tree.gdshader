shader_type spatial;
render_mode world_vertex_coords, specular_disabled, cull_disabled;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// Seed-driven illustration broadleaves (tools/vegetation/build_seed_trees.py). The painted
// vertex color carries the look: each lump's pale sunlit cap over the crown's yellow-green
// to blue-green gradient. Light only adds a soft, wrapped falloff on the crown's proxy
// normal (no cel bands), so the crown reads as a soft painted mass of tiny leaves.
// Vertex COLOR: rgb = painted sRGB color, a = 1 card / 0 core.
// UV2 (cards only): the corner's offset from the card center in the view plane (m).
uniform sampler2D leaf_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff = 0.5;
// Alpha scaled up per mip level so the thin leaves keep their coverage far away.
uniform float mip_coverage = 0.3;
uniform float alpha_edge = 0.3;
uniform float biome_harmony = 0.3;
// Wrapped N.L: the lit side falls off over this range instead of a hard terminator.
uniform float wrap_low = -0.45;
uniform float wrap_high = 0.85;
// The side away from the sun keeps this much light, tinted cool (blue-green shade).
uniform float shade_level = 0.8;
uniform vec3 shade_tint : source_color = vec3(0.74, 0.88, 1.12);
// Painted fill: a share of the albedo that never goes dark, so the underside stays a
// readable blue-green like an illustration instead of sinking into the ambient.
uniform float fill = 0.2;
// Shadows from other casters only dim the crown; full strength turns it muddy.
uniform float shadow_strength = 0.35;
// How far a card is pulled toward the camera, relative to its half diagonal, so its own
// lump's core never cuts it.
uniform float card_push = 0.6;
// Per-leaf value from the texture.
uniform float leaf_contrast = 0.22;
uniform float wetness = 0.0;
// 0 = summer foliage, 0.8 = snow weather (open_field_world sets it).
uniform float snow_cover = 0.0;
// Snowed crown: shaded side -> sunlit side, and how much foliage green shows through.
uniform vec3 snow_shade : source_color = vec3(0.66, 0.74, 0.84);
uniform vec3 snow_light : source_color = vec3(0.97, 0.98, 1.0);
uniform float snow_foliage = 0.12;
// 1 on the seed conifers' copy of this material: needles stay green through the seasons.
uniform float evergreen = 0.0;
varying vec3 world_normal;
varying vec3 world_pos;
varying vec3 tree_tint;
varying float tree_seed;
varying vec3 debug_color;

void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    vec4 biome = of_biome(origin.xz);
    vec3 harmony = clamp(biome.rgb / vec3(0.48, 0.64, 0.29), vec3(0.75), vec3(1.25));
    float h = of_hash(origin.xz);
    tree_seed = of_hash(origin.xz + 11.7);
    tree_tint = mix(vec3(1.0), harmony, biome_harmony) * mix(vec3(0.96, 1.0, 1.03), vec3(1.04, 1.02, 0.94), h) * (0.96 + 0.08 * of_hash(origin.xz + 3.1));
    debug_color = biome_debug > 0.5 ? of_biome_debug(origin.xz) : vec3(-1.0);
    if (COLOR.a > 0.5) {
        float scale = length(MODEL_MATRIX[0].xyz);
        vec3 to_camera = normalize(CAMERA_POSITION_WORLD - VERTEX);
        VERTEX += (INV_VIEW_MATRIX[0].xyz * UV2.x + INV_VIEW_MATRIX[1].xyz * UV2.y + to_camera * length(UV2) * card_push) * scale;
    }
    world_normal = NORMAL;
    world_pos = VERTEX;
}

void fragment() {
    float card = COLOR.a;
    vec4 leaf = texture(leaf_texture, UV);
    vec2 texel = UV * vec2(textureSize(leaf_texture, 0));
    float mip = max(0.0, 0.5 * log2(max(dot(dFdx(texel), dFdx(texel)), dot(dFdy(texel), dFdy(texel)))));
    ALPHA = card > 0.5 ? clamp(leaf.a * (1.0 + mip * mip_coverage), 0.0, 1.0) : 1.0;
    ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
    ALPHA_ANTIALIASING_EDGE = alpha_edge;
    ALPHA_TEXTURE_COORDINATE = texel;
    // Both faces of a card shade with the proxy normal (cull_disabled would flip it).
    NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
    vec3 color = COLOR.rgb;
    color *= mix(1.0, mix(1.0 - leaf_contrast, 1.0 + leaf_contrast * 0.5, leaf.r), card);
    // The core shows through the gaps as deeper foliage, broken up so it never reads as a shell.
    float n = of_noise(vec2(world_pos.x + world_pos.z, world_pos.y) * 2.3);
    color *= mix(mix(0.85, 1.05, n), 1.0, card);
    color *= tree_tint;
    color = evergreen > 0.5 ? of_season_evergreen(color, tree_seed) : of_season_leaf(color, tree_seed);
    if (debug_color.x >= 0.0) color = debug_color;
    // Snow: the whole crown turns snow-white, keeping its painted light (each lump's bright
    // cap, the shaded underside) as cool blue-grey to white, with a trace of the foliage.
    float lum = dot(color, vec3(0.3, 0.59, 0.11));
    vec3 snowy = mix(snow_shade, snow_light, smoothstep(0.18, 0.62, lum));
    snowy = mix(snowy, color, snow_foliage);
    color = mix(color, snowy, clamp(snow_cover * 1.25, 0.0, 1.0));
    color *= 1.0 - wetness * 0.2;
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
