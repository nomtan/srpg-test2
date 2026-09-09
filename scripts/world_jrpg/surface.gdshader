shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform int kind = 0; // 0 ground, 1 stone, 2 timber, 3 foliage, 4 slate
uniform vec3 tactical_center = vec3(0.0);
uniform float tactical_radius = 0.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
uniform float night_light = 0.0;
uniform bool lamp = false;
varying vec3 world_position;
varying vec3 world_normal;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    // Only foliage is cut away around the battle. Terrain and trunk collisions stay.
    if (kind == 3 && tactical_radius > 0.0 && distance(world_position.xz, tactical_center.xz) < tactical_radius) {
        discard;
    }
    vec3 n = abs(world_normal);
    vec2 uv = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
    float fine = hash(floor(uv * 12.0));
    float patch = hash(floor(uv * 2.0));
    float detail = 0.91 + fine * 0.16 + patch * 0.10;
    if (kind == 1) {
        float row = floor(uv.y * 2.5);
        vec2 brick = vec2(uv.x * 1.6 + mod(row, 2.0) * 0.5, uv.y * 2.5);
        vec2 edge = fract(brick);
        float mortar = step(0.05, edge.x) * step(0.07, edge.y);
        detail *= mix(0.64, 0.88 + hash(floor(brick)) * 0.24, mortar);
    } else if (kind == 2) {
        float grain = hash(vec2(floor(uv.x * 3.0), floor(uv.y * 30.0)));
        detail *= 0.80 + grain * 0.27;
        detail *= mix(0.72, 1.0, step(0.025, fract(uv.y * 3.0)));
    } else if (kind == 3) {
        detail = 0.77 + hash(floor(uv * 9.0)) * 0.38;
    } else if (kind == 5) {
        float layer = sin(world_position.y * 6.0 + patch * 1.6);
        detail = 0.85 + patch * 0.15 + fine * 0.12 + layer * 0.045;
    } else if (kind == 4) {
        detail *= 0.80 + hash(floor(uv * vec2(5.0, 7.0))) * 0.26;
    }
    float near_detail = 1.0 - smoothstep(25.0, 95.0, length(VERTEX));
    ALBEDO = base_color.rgb * mix(0.96, detail, near_detail);
    ALBEDO *= 1.0 - wetness * 0.2;
    ALBEDO = mix(ALBEDO, vec3(0.81, 0.87, 0.9) * mix(0.96, detail, 0.2), snow_cover * smoothstep(0.5, 0.95, world_normal.y));
    ROUGHNESS = mix(kind == 4 ? 0.75 : 0.95, 0.32, wetness);
    SPECULAR = mix(0.2, 0.65, wetness);
    if (lamp) EMISSION = vec3(1.0, 0.58, 0.19) * night_light * 1.5;
}
