shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float wetness = 0.0;
uniform float snow_cover = 0.0;

void vertex() {
    vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float gust = sin(TIME * 1.35 + world_position.x * 0.43 + world_position.z * 0.31);
    float flutter = sin(TIME * 3.2 + world_position.x * 2.7 + world_position.y * 3.1);
    VERTEX.x += (gust * 0.065 + flutter * 0.012) * COLOR.a;
    VERTEX.z += gust * 0.035 * COLOR.a;
}

void fragment() {
    // Preserve the authored grass colors without light direction or received shadows.
    vec3 color = COLOR.rgb * (1.0 - wetness * 0.18);
    ALBEDO = mix(color, vec3(0.83, 0.88, 0.9), snow_cover * 0.65);
}
