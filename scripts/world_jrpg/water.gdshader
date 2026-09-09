shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.17, 0.35, 0.33, 1.0);
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world_position.xz;
    float wave = sin(p.x * 3.7 + p.y * 1.3 + TIME * 0.8) * sin(p.y * 5.1 - TIME * 0.55);
    float ripple = pow(max(0.0, wave), 9.0);
    float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
    ALBEDO = mix(base_color.rgb, vec3(0.57, 0.68, 0.65), fresnel * 0.68) + ripple * 0.07;
    NORMAL = normalize(NORMAL + vec3(sin(p.x * 2.0 + TIME) * 0.035, 0.0, cos(p.y * 2.8 + TIME) * 0.035));
    METALLIC = 0.25;
    ROUGHNESS = 0.22;
    SPECULAR = 0.8;
}
