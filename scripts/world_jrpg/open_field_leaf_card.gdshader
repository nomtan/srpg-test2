shader_type spatial;
render_mode world_vertex_coords, specular_disabled, cull_disabled;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
#include "res://scripts/world_jrpg/open_field_wind.gdshaderinc"
// Illustration-style leaf-card crowns (tools/vegetation: build_card_tree). The cards carry
// the smooth proxy volume's normals, so lighting them in a few flat bands paints the crown
// as soft clumps; the leaf texture only cuts the outline and adds per-leaf value.
// Vertex COLOR: r = tone, g = wind weight, b = per-mass phase, a = 1 card / 0 solid core.
uniform sampler2D leaf_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff = 0.5;
// Mipmaps average the thin leaf tips away, so at a distance the cut-out would erode and
// sparkle; alpha is scaled up per mip level to keep the cards' coverage (Golus).
uniform float mip_coverage = 0.3;
// Under MSAA the cut-out edge resolves through alpha to coverage instead of a hard step.
uniform float alpha_edge = 0.3;
uniform vec3 shadow_color : source_color = vec3(0.17, 0.33, 0.33);
uniform vec3 base_color : source_color = vec3(0.30, 0.50, 0.24);
uniform vec3 highlight_color : source_color = vec3(0.62, 0.74, 0.32);
uniform float biome_harmony = 0.45;
// Lit / shade boundary on the wrapped N.L, and its width: small = crisp cel edge.
uniform float band_threshold = 0.42;
uniform float band_softness = 0.06;
// Shadow from other casters, banded so it lands as flat painted shapes; the band is kept
// wide enough that the shadow map's filtered edge does not crawl as the camera moves.
uniform float shadow_band = 0.5;
uniform float shadow_softness = 0.3;
// The shaded side keeps this much sun, tinted cool, instead of going to ambient only.
uniform float shade_level = 0.32;
uniform vec3 shade_tint : source_color = vec3(0.75, 0.9, 1.1);
// Thin bright rim where the crown turns away from the camera toward the sun.
uniform float rim = 0.25;
uniform float sway = 0.16;
uniform float rustle = 0.03;
// The card flutter fades out by this distance: sub-pixel motion only reads as flicker.
uniform float rustle_distance = 30.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 world_normal;
varying vec3 world_pos;
// Per-tree palette multiplier (biome harmony and variation), constant over the instance,
// so it is evaluated per vertex instead of per fragment.
varying vec3 tree_tint;
varying vec3 debug_color;

void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    vec4 biome = of_biome(origin.xz);
    vec3 harmony = clamp(biome.rgb / vec3(0.48, 0.64, 0.29), vec3(0.65), vec3(1.35));
    float h = of_hash(origin.xz);
    tree_tint = mix(vec3(1.0), harmony, biome_harmony) * mix(vec3(0.94, 1.0, 1.03), vec3(1.06, 1.03, 0.9), h) * (0.95 + 0.1 * of_hash(origin.xz + 3.1));
    debug_color = biome_debug > 0.5 ? of_biome_debug(origin.xz) : vec3(-1.0);
    float scale = length(MODEL_MATRIX[0].xyz);
    float w = COLOR.g;
    vec2 dir = of_wind_dir();
    float push = of_wind_push(origin.xz, TIME);
    float bob = sin(TIME * 1.6 + COLOR.b * 6.283 + origin.x * 0.31 + origin.z * 0.17);
    vec2 offset = dir * (push * sway + bob * sway * 0.25 * wind_strength) * w * scale;
    // Cards flutter a little more than the cores so the outline shimmers in the wind.
    float near = 1.0 - smoothstep(rustle_distance * 0.5, rustle_distance, distance(VERTEX, CAMERA_POSITION_WORLD));
    float leaf = sin(TIME * 4.1 + dot(VERTEX, vec3(1.7, 2.3, 1.1)) + COLOR.b * 6.283) * rustle * wind_strength * w * mix(0.4, 1.0, COLOR.a) * near * scale;
    VERTEX.xz += offset;
    VERTEX += NORMAL * leaf;
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
    float tone = clamp(COLOR.r, 0.0, 1.0);
    vec3 color = tone < 0.5 ? mix(shadow_color, base_color, tone * 2.0) : mix(base_color, highlight_color, tone * 2.0 - 1.0);
    // Per-leaf value from the texture: a painted, not noisy, variation.
    color *= mix(1.0, mix(0.84, 1.12, leaf.r), card);
    // Cores get the same clusters, projected and blurred (a fixed mip, so the wrap seam
    // never shows), so the gaps between cards read as deeper foliage, not a smooth shell.
    vec2 core_uv = fract(vec2(world_pos.x + world_pos.z, world_pos.y) * 0.45) * 0.5;
    vec4 shade = textureLod(leaf_texture, core_uv, 2.0);
    color *= mix(mix(0.8, 1.06, shade.a * shade.r), 1.0, card);
    color *= tree_tint;
    if (debug_color.x >= 0.0) color = debug_color * mix(0.5, 1.0, tone);
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
        float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
        DIFFUSE_LIGHT += edge * rim * band * sun * vec3(1.0, 1.0, 0.8);
    } else {
        // Lamps and torches: the same band, scaled by their falloff.
        DIFFUSE_LIGHT += lit * ATTENUATION * sun;
    }
}
