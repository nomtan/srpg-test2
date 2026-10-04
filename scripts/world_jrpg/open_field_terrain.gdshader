shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// Vertex COLOR carries material weights: r = dirt path, g = shore sand, b = cobbled plaza,
// a = crop field.
// Grass, rock (by slope/altitude), snow and lakebed are resolved per pixel.
uniform float lake_level = 10.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
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
    vec3 color = of_grass(p) * (0.93 + fine * 0.12);
    vec3 dirt = mix(vec3(0.80, 0.71, 0.56), vec3(0.67, 0.58, 0.45), of_noise(p * 0.6)) * (0.92 + fine * 0.14);
    color = mix(color, dirt, smoothstep(0.15, 0.85, COLOR.r));
    color = mix(color, vec3(0.87, 0.81, 0.63) * (0.94 + fine * 0.1), COLOR.g);
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
    float facets = of_noise(p * 0.12 + world_position.y * 0.05) * 0.65 + of_noise(p * 0.45 - world_position.y * 0.2) * 0.35;
    vec3 rock = mix(vec3(0.47, 0.50, 0.56), vec3(0.69, 0.71, 0.74), facets) * (0.9 + fine * 0.15);
    float steep = (1.0 - smoothstep(0.60, 0.80, n.y)) * (1.0 - COLOR.g);
    float alpine = smoothstep(56.0, 74.0, world_position.y + (of_noise(p * 0.05) - 0.5) * 14.0);
    color = mix(color, rock, max(steep, alpine * (1.0 - smoothstep(0.9, 0.98, n.y) * 0.4)));
    float snow = smoothstep(90.0, 102.0, world_position.y + (of_noise(p * 0.07) - 0.5) * 12.0) * smoothstep(0.35, 0.65, n.y);
    snow = max(snow, snow_cover * smoothstep(0.5, 0.9, n.y));
    color = mix(color, vec3(0.93, 0.95, 0.98), snow);
    color = mix(color, vec3(0.30, 0.45, 0.42), smoothstep(0.0, 5.0, lake_level - world_position.y));
    color *= 1.0 - wetness * 0.2;
    ALBEDO = of_to_linear(color);
    ROUGHNESS = mix(0.95, 0.45, wetness);
    SPECULAR = 0.25;
}
