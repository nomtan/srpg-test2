shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// Vertex COLOR carries material weights: r = dirt path, g = shore sand, b = cobbled plaza,
// a = crop field.
// Biome tint and wetness come from biome_map; grass, slope dirt/rock (by slope/altitude),
// snow and lakebed are resolved per pixel.
uniform float lake_level = 10.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
// Aerial perspective color for distant terrain (set per time of day / weather).
uniform vec3 haze_color = vec3(0.60, 0.73, 0.88);
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec2 p = world_position.xz;
    vec3 n = normalize(world_normal);
    float fine = of_noise(p * 1.7);
    vec4 biome = of_biome(p);
    vec3 color = of_grass_tinted(p, biome.rgb) * (0.93 + fine * 0.12);
    // Macro color variation at ~100 m, ~30 m and ~5 m. The domain warp bends the noise
    // so it reads as soil and light changes across the land rather than a pattern.
    vec2 q = p + vec2(of_noise(p * 0.017), of_noise(p * 0.017 + 9.0)) * 40.0;
    color *= 0.93 + 0.14 * of_noise(q * 0.01 + 31.0);
    color = mix(color, color * vec3(1.08, 1.02, 0.80), smoothstep(0.58, 0.82, of_noise(q * 0.033 + 5.0)) * 0.45);
    color = mix(color, color * vec3(0.90, 0.98, 1.02), smoothstep(0.6, 0.85, of_noise(q * 0.03 - 13.0)) * 0.35);
    color *= 0.97 + 0.06 * of_noise(p * 0.2 + 2.0);
    vec3 dirt = mix(vec3(0.80, 0.71, 0.56), vec3(0.67, 0.58, 0.45), of_noise(p * 0.6)) * (0.92 + fine * 0.14);
    // Forest floor: darker loam and leaf litter under the canopy, broken into patches.
    vec2 surface = of_biome_surface(p);
    float litter = surface.g * smoothstep(0.3, 0.7, of_noise(p * 0.25 + 19.0) * 0.6 + of_noise(p * 1.1) * 0.4 + surface.g * 0.3);
    color = mix(color, mix(vec3(0.33, 0.36, 0.20), vec3(0.42, 0.35, 0.22), of_noise(p * 0.5 + 4.0)) * (0.9 + fine * 0.2), litter * 0.6);
    // Rocky biomes expose stone outcrops through the turf.
    float outcrop_noise = of_noise(q * 0.09 + 23.0) * 0.65 + of_noise(p * 0.5 - 8.0) * 0.35;
    float outcrop = smoothstep(0.8 - surface.r * 0.32, 0.88 - surface.r * 0.32, outcrop_noise) * step(0.01, surface.r);
    vec3 stone = mix(vec3(0.55, 0.57, 0.60), vec3(0.72, 0.73, 0.74), of_noise(p * 0.7 + 3.0)) * (0.88 + fine * 0.18);
    color = mix(color, stone, outcrop * 0.7);
    color = mix(color, dirt, smoothstep(0.15, 0.85, COLOR.r));
    // Shore sand, with pebbles where the lakeshore biome is wet.
    float pebble = smoothstep(0.72, 0.8, of_noise(p * 6.0)) * biome.a;
    vec3 sand = mix(vec3(0.87, 0.81, 0.63), vec3(0.62, 0.62, 0.60), pebble) * (0.94 + fine * 0.1);
    color = mix(color, sand, COLOR.g);
    vec2 cell = p * 1.3 + vec2(0.0, floor(p.x * 1.3) * 0.5);
    vec2 edge = abs(fract(cell) - 0.5);
    float grout = smoothstep(0.42, 0.48, max(edge.x, edge.y));
    vec3 cobble = mix(vec3(0.76, 0.73, 0.66), vec3(0.62, 0.60, 0.56), of_hash(floor(cell)));
    color = mix(color, mix(cobble, vec3(0.45, 0.47, 0.40), grout), COLOR.b);
    // Crop fields: furrowed soil under rows of green or ripening crops.
    float rows = smoothstep(0.05, 0.45, sin(p.x * 3.2) * 0.5 + 0.5);
    vec3 crop = mix(vec3(0.50, 0.66, 0.28), vec3(0.80, 0.74, 0.40), smoothstep(0.35, 0.65, of_noise(p * 0.03)));
    vec3 farm = mix(mix(crop, vec3(0.56, 0.46, 0.33), 0.55), crop, rows) * (0.93 + fine * 0.12);
    color = mix(color, farm, COLOR.a);
    // Slope material: grass on the flat, worn earth and scree on medium slopes, bare rock
    // on steep faces. Noise breaks the bands up so they never follow contour lines.
    float breakup = (of_noise(p * 0.35 + world_position.y * 0.1) - 0.5) * 0.12;
    // Triplanar facets so cliff faces get strata instead of xz noise smeared down them.
    vec3 wp = world_position;
    vec3 tri = pow(abs(n), vec3(4.0));
    tri /= tri.x + tri.y + tri.z;
    float facets = (of_noise(wp.zy * vec2(0.12, 0.3)) * tri.x + of_noise(wp.xz * 0.12) * tri.y + of_noise(wp.xy * vec2(0.12, 0.3)) * tri.z) * 0.65
        + (of_noise(wp.zy * 0.45) * tri.x + of_noise(wp.xz * 0.45) * tri.y + of_noise(wp.xy * 0.45) * tri.z) * 0.35;
    vec3 rock = mix(vec3(0.47, 0.50, 0.56), vec3(0.69, 0.71, 0.74), facets) * (0.9 + fine * 0.15);
    float open_ground = (1.0 - COLOR.g) * (1.0 - COLOR.b) * (1.0 - COLOR.a);
    float medium = (1.0 - smoothstep(0.80, 0.94, n.y + breakup)) * open_ground;
    vec3 scree = mix(dirt * 0.92, rock, smoothstep(0.45, 0.75, of_noise(p * 0.8 + 7.0)));
    color = mix(color, scree, medium * 0.55);
    float steep = (1.0 - smoothstep(0.58, 0.78, n.y + breakup)) * (1.0 - COLOR.g);
    float alpine = smoothstep(88.0, 112.0, world_position.y + (of_noise(p * 0.05) - 0.5) * 20.0);
    color = mix(color, rock, max(steep, alpine * (1.0 - smoothstep(0.9, 0.98, n.y) * 0.4)));
    float snow = smoothstep(150.0, 172.0, world_position.y + (of_noise(p * 0.07) - 0.5) * 30.0) * smoothstep(0.4, 0.7, n.y);
    snow = max(snow, snow_cover * smoothstep(0.5, 0.9, n.y));
    color = mix(color, vec3(0.93, 0.95, 0.98), snow);
    color = mix(color, vec3(0.30, 0.45, 0.42), smoothstep(0.0, 5.0, lake_level - world_position.y));
    // Biome wetness: wetland and lakeshore ground is darker, cooler and glossier.
    float damp = biome.a * (1.0 - snow);
    color *= mix(vec3(1.0), vec3(0.82, 0.88, 0.90), damp);
    color *= 1.0 - wetness * 0.2;
    if (biome_debug > 0.5) {
        // Flat biome colors with a faint 1 m battle-cell grid near the camera.
        vec2 g = abs(fract(p) - 0.5);
        float line = smoothstep(0.46, 0.49, max(g.x, g.y)) * (1.0 - smoothstep(20.0, 60.0, length(VERTEX)));
        vec3 flat_color = (p.x < 0.0 || p.y < 0.0 || p.x > biome_extent || p.y > biome_extent) ? vec3(0.3) : of_biome_debug(p);
        color = mix(flat_color * (0.7 + 0.3 * n.y), vec3(0.05), line * 0.5);
    }
    // Distant ridges cool and lift toward the haze so the ranges layer into depth.
    float aerial = smoothstep(140.0, 900.0, length(VERTEX)) * (1.0 - biome_debug);
    color = mix(color, haze_color, aerial * 0.55);
    ALBEDO = of_to_linear(color);
    EMISSION = of_to_linear(haze_color) * aerial * 0.18;
    ROUGHNESS = mix(0.95, 0.45, max(wetness, damp * 0.6));
    SPECULAR = 0.25;
}
