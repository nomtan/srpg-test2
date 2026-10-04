// Shared helpers for the JRPGWorldSample2 open-field shaders.
float of_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float of_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(of_hash(i), of_hash(i + vec2(1.0, 0.0)), f.x), mix(of_hash(i + vec2(0.0, 1.0)), of_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 of_to_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

// Painterly meadow tint in sRGB. Terrain, grass blades and moss all sample it,
// so the instanced grass melts into the ground beneath it.
vec3 of_grass(vec2 p) {
    float broad = of_noise(p * 0.012);
    float patch = of_noise(p * 0.045 + 17.0);
    float dry = of_noise(p * 0.028 + 41.0);
    vec3 c = mix(vec3(0.37, 0.57, 0.24), vec3(0.58, 0.75, 0.33), smoothstep(0.25, 0.75, broad));
    c = mix(c, vec3(0.29, 0.48, 0.22), smoothstep(0.55, 0.85, patch) * 0.5);
    c = mix(c, vec3(0.72, 0.75, 0.42), smoothstep(0.68, 0.88, dry) * 0.4);
    return c;
}
