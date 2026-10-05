shader_type spatial;
render_mode world_vertex_coords, specular_disabled;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
#include "res://scripts/world_jrpg/open_field_wind.gdshaderinc"
// Blender-built trees (assets/environment/vegetation/trees). One shader for both shared
// materials: foliage = 0 is TreeTrunkMaterial, foliage = 1 is TreeFoliageMaterial.
// Vertex COLOR: r = tone (0 shadow / 0.5 base / 1 highlight), g = wind weight
// (0 trunk base .. 1 outer foliage), b = per-mass phase.
uniform float foliage = 1.0;
// Foliage palette: cool shadow inside / below, base green, warm highlight on top.
uniform vec3 shadow_color : source_color = vec3(0.19, 0.34, 0.31);
uniform vec3 base_color : source_color = vec3(0.30, 0.48, 0.24);
uniform vec3 highlight_color : source_color = vec3(0.58, 0.70, 0.32);
uniform vec3 bark_dark : source_color = vec3(0.32, 0.25, 0.19);
uniform vec3 bark_light : source_color = vec3(0.58, 0.48, 0.37);
// How far the biome ground tint pulls the palette (shared Tree / Grass / Ground harmony).
uniform float biome_harmony = 0.45;
// Wind: whole-limb sway (m at weight 1) and small surface rustle of the leaf masses.
uniform float sway = 0.16;
uniform float rustle = 0.035;
// Wrapped diffuse keeps the shaded side of the crown green instead of black.
uniform float wrap = 0.5;
uniform float translucency = 0.35;
// Sun-driven fill (directional lights only, unshadowed): lifts the crown's underside the
// way skylight bounce would, and fades with the sun at night.
uniform float fill = 0.14;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 origin;
varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
    origin = MODEL_MATRIX[3].xyz;
    float scale = length(MODEL_MATRIX[0].xyz);
    float w = COLOR.g;
    vec2 dir = of_wind_dir();
    // The whole tree samples one push (its trunk position), so the crown moves as one
    // body; the per-mass bob and rustle keep the clumps from moving in lockstep.
    float push = of_wind_push(origin.xz, TIME);
    float bob = sin(TIME * 1.6 + COLOR.b * 6.283 + origin.x * 0.31 + origin.z * 0.17);
    vec2 offset = dir * (push * sway + bob * sway * 0.25 * wind_strength) * w * scale;
    float leaf = sin(TIME * 4.1 + dot(VERTEX, vec3(1.7, 2.3, 1.1)) + COLOR.b * 6.283) * rustle * wind_strength * w * foliage * scale;
    VERTEX.xz += offset;
    VERTEX += NORMAL * leaf;
    world_normal = NORMAL;
    world_pos = VERTEX;
}

void fragment() {
    float tone = COLOR.r;
    vec3 color;
    if (foliage > 0.5) {
        color = tone < 0.5 ? mix(shadow_color, base_color, tone * 2.0) : mix(base_color, highlight_color, tone * 2.0 - 1.0);
        vec4 biome = of_biome(origin.xz);
        vec3 harmony = clamp(biome.rgb / vec3(0.48, 0.64, 0.29), vec3(0.65), vec3(1.35));
        color *= mix(vec3(1.0), harmony, biome_harmony);
        // Small per-tree variation: some crowns a touch warmer, some cooler.
        float h = of_hash(origin.xz);
        color *= mix(vec3(0.94, 1.0, 1.03), vec3(1.06, 1.03, 0.9), h) * (0.95 + 0.1 * of_hash(origin.xz + 3.1));
        if (biome_debug > 0.5) color = of_biome_debug(origin.xz) * mix(0.5, 1.0, tone);
        color = mix(color, vec3(0.92, 0.95, 0.98), snow_cover * smoothstep(0.2, 0.7, world_normal.y) * 0.8);
    } else {
        // Bark: vertical streaks over a root-dark to limb-light gradient.
        float streak = of_noise(vec2(atan(world_normal.z, world_normal.x) * 3.0, world_pos.y * 0.4 + origin.x));
        color = mix(bark_dark, bark_light, clamp(tone * 0.8 + streak * 0.35, 0.0, 1.0));
    }
    color *= 1.0 - wetness * 0.2;
    ALBEDO = of_to_linear(color);
    ROUGHNESS = mix(0.9, 0.55, wetness);
}

void light() {
    float ndl = dot(NORMAL, LIGHT);
    float w = wrap * mix(0.5, 1.0, foliage);
    float diffuse = smoothstep(0.0, 1.0, clamp((ndl + w) / (1.0 + w), 0.0, 1.0));
    DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
    // Sun shining through the crown edges toward the camera.
    float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 4.0) * translucency * foliage;
    DIFFUSE_LIGHT += back * ATTENUATION * LIGHT_COLOR / PI * vec3(1.0, 1.05, 0.7) * ALBEDO;
    if (LIGHT_IS_DIRECTIONAL) DIFFUSE_LIGHT += fill * mix(0.5, 1.0, foliage) * LIGHT_COLOR / PI * vec3(0.85, 0.95, 1.05);
}
