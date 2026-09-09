shader_type spatial;
render_mode cull_disabled;

uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
uniform vec3 tactical_center = vec3(0.0);
uniform float tactical_radius = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float gust = sin(TIME * 1.35 + world_position.x * 0.43 + world_position.z * 0.31);
    float flutter = sin(TIME * 3.2 + world_position.x * 2.7 + world_position.y * 3.1);
    VERTEX.x += (gust * 0.065 + flutter * 0.012) * COLOR.a;
    VERTEX.z += gust * 0.035 * COLOR.a;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    if (UV2.x > 0.5 && tactical_radius > 0.0 && distance(world_position.xz, tactical_center.xz) < tactical_radius) discard;
    vec3 color = COLOR.rgb;
    // Subtle continuous bark grain; foliage color lives on the actual leaf geometry.
    if (COLOR.a < 0.001 && UV2.x < 0.5) {
        float grain = sin(world_position.y * 9.0 + sin(world_position.x * 37.0 + world_position.z * 31.0) * 2.0);
        color *= 0.94 + grain * 0.08;
    }
    color *= 1.0 - wetness * 0.18;
    ALBEDO = mix(color, vec3(0.83, 0.88, 0.9), snow_cover * smoothstep(0.35, 0.9, world_normal.y));
    ROUGHNESS = mix(0.88, 0.48, wetness);
    SPECULAR = 0.18;
    // Small fill suggests light passing through thin foliage in Compatibility mode.
    EMISSION = ALBEDO * 0.035 * COLOR.a;
}
