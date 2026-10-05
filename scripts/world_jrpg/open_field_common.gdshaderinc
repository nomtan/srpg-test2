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

// --- Biomes -----------------------------------------------------------------
// biome_map: RGB = blended biome ground tint (sRGB), A = wetness, baked on a grid
// covering the playable square. Beyond it the far terrain falls back to biome_outside
// broken up by distant-forest patches. biome_debug swaps in the flat debug colors.
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D biome_debug_map : filter_linear, repeat_disable;
// R = rockiness (exposed stone patches), G = forest-floor litter.
uniform sampler2D biome_surface_map : filter_linear, repeat_disable;
uniform float biome_enabled = 0.0;
uniform float biome_debug = 0.0;
uniform float biome_uv_scale = 0.0025;
uniform float biome_uv_offset = 0.0;
uniform float biome_extent = 400.0;

vec4 of_biome(vec2 p) {
    if (biome_enabled < 0.5) return vec4(0.47, 0.65, 0.28, 0.0);
    vec4 inside = texture(biome_map, p * biome_uv_scale + biome_uv_offset);
    float out_d = length(max(max(-p, p - vec2(biome_extent)), vec2(0.0)));
    if (out_d <= 0.0) return inside;
    // Far hills: yellow-green highland with dark distant woods.
    float woods = smoothstep(0.45, 0.62, of_noise(p * 0.011 + 3.0));
    vec4 outside = vec4(mix(vec3(0.58, 0.68, 0.33), vec3(0.27, 0.45, 0.24), woods), 0.0);
    return mix(inside, outside, smoothstep(0.0, 70.0, out_d));
}

vec2 of_biome_surface(vec2 p) {
    if (biome_enabled < 0.5) return vec2(0.0);
    vec2 inside = texture(biome_surface_map, p * biome_uv_scale + biome_uv_offset).rg;
    float out_d = length(max(max(-p, p - vec2(biome_extent)), vec2(0.0)));
    return mix(inside, vec2(0.3, 0.0), smoothstep(0.0, 70.0, out_d));
}

vec3 of_biome_debug(vec2 p) {
    return texture(biome_debug_map, p * biome_uv_scale + biome_uv_offset).rgb;
}

// The painterly meadow variation of of_grass, recolored to a biome tint. The ratio keeps
// the patches and dry spots so a biome reads as a hue shift, not a flat fill.
vec3 of_grass_tinted(vec2 p, vec3 tint) {
    vec3 ratio = of_grass(p) / vec3(0.47, 0.65, 0.28);
    return tint * mix(vec3(1.0), ratio, 0.85);
}
