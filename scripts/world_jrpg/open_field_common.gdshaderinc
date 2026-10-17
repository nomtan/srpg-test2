// Shared helpers for the JRPGWorldSample2 open-field shaders.
float of_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float of_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(of_hash(i), of_hash(i + vec2(1.0, 0.0)), f.x), mix(of_hash(i + vec2(0.0, 1.0)), of_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 of_to_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

// --- Seasons ----------------------------------------------------------------
// season: 0 spring, 1 summer (the painted base palette, left untouched), 2 autumn,
// 3 winter. FieldWeather picks it; JRPGWorldSample2 pushes it onto every material.
// Each helper keeps the input's value (luma) and swaps its hue, so the painted light and
// shade survive the recolor.
uniform int season = 1;

float of_luma(vec3 c) { return dot(c, vec3(0.30, 0.59, 0.11)); }

// Turf and grass blades: fresh yellow-green in spring, golden dry grass in autumn and
// dormant straw in winter.
vec3 of_season_grass(vec3 c, vec2 p) {
    if (season == 1) return c;
    float l = of_luma(c) / 0.55;
    float n = of_noise(p * 0.03 + 71.0);
    if (season == 0) return mix(c, mix(vec3(0.55, 0.77, 0.33), vec3(0.64, 0.80, 0.38), n) * l, 0.5);
    if (season == 2) return mix(c, mix(vec3(0.72, 0.64, 0.34), vec3(0.58, 0.52, 0.30), n) * l, 0.5 + 0.2 * n);
    return mix(c, mix(vec3(0.64, 0.60, 0.48), vec3(0.54, 0.52, 0.45), n) * l, 0.78);
}

// Winter frost: scattered patches of old snow on open ground (0..1). Zero otherwise.
float of_season_frost(vec2 p) {
    if (season != 3) return 0.0;
    return smoothstep(0.42, 0.68, of_noise(p * 0.035 + 61.0) * 0.75 + of_noise(p * 0.3) * 0.25) * 0.85;
}

// Broadleaf crowns. seed (0..1, per tree) staggers autumn into orange, red and yellow
// trees with a few late greens; winter leaves hang dry and brown.
vec3 of_season_leaf(vec3 c, float seed) {
    if (season == 1) return c;
    float l = of_luma(c) / 0.5;
    // Spring: fresh green, with one tree in seven in pink blossom.
    if (season == 0) return seed < 0.14 ? mix(c, vec3(1.0, 0.74, 0.84) * mix(l, 1.0, 0.5), 0.85) : mix(c, vec3(0.58, 0.82, 0.36) * l, 0.45);
    if (season == 2) {
        vec3 hue = seed < 0.4 ? vec3(0.95, 0.52, 0.17) : (seed < 0.72 ? vec3(0.84, 0.27, 0.16) : vec3(0.96, 0.78, 0.24));
        return mix(c, hue * l * 0.9, seed > 0.92 ? 0.35 : 0.88);
    }
    return mix(c, vec3(0.66, 0.52, 0.38) * l, 0.8);
}

// Conifers keep their needles: only a little lighter in spring and darker, colder in
// winter.
vec3 of_season_evergreen(vec3 c) {
    if (season == 0) return c * vec3(1.04, 1.07, 0.98);
    if (season == 2) return c * vec3(1.0, 0.96, 0.9);
    if (season == 3) return mix(c, vec3(0.20, 0.32, 0.30) * of_luma(c) / 0.4, 0.3);
    return c;
}

// Blossom trees flower only in spring; the rest of the year they are ordinary broadleaves.
vec3 of_season_blossom(vec3 c, float seed) {
    if (season == 0) return c;
    vec3 leaf = vec3(0.40, 0.66, 0.36) * of_luma(c) / 0.75;
    return season == 1 ? leaf : of_season_leaf(leaf, seed);
}

// Pink/red-dominant colors are blossom petals rather than leaves.
bool of_is_blossom(vec3 c) { return c.r > c.g + 0.08; }

// Meadow flowers: everywhere in spring and summer, thinning in autumn, gone in winter.
float of_season_bloom(vec2 p) {
    if (season == 3) return 0.0;
    if (season == 2) return step(of_hash(p + 5.3), 0.3);
    return 1.0;
}

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

// The turf color the terrain paints before paths, rock and snow: biome-tinted meadow with
// macro variation at ~100 m, ~30 m and ~5 m and forest-floor litter. The grass blades
// take it at their root, so a blade starts exactly the color of the ground it stands on.
vec3 of_meadow(vec2 p, vec3 tint) {
    float fine = of_noise(p * 1.7);
    vec3 color = of_grass_tinted(p, tint) * (0.93 + fine * 0.12);
    // The domain warp bends the noise so it reads as soil and light changes across the
    // land rather than a pattern.
    vec2 q = p + vec2(of_noise(p * 0.017), of_noise(p * 0.017 + 9.0)) * 40.0;
    color *= 0.93 + 0.14 * of_noise(q * 0.01 + 31.0);
    color = mix(color, color * vec3(1.08, 1.02, 0.80), smoothstep(0.58, 0.82, of_noise(q * 0.033 + 5.0)) * 0.45);
    color = mix(color, color * vec3(0.90, 0.98, 1.02), smoothstep(0.6, 0.85, of_noise(q * 0.03 - 13.0)) * 0.35);
    color *= 0.97 + 0.06 * of_noise(p * 0.2 + 2.0);
    // Forest floor: darker loam and leaf litter under the canopy, broken into patches.
    vec2 surface = of_biome_surface(p);
    float litter = surface.g * smoothstep(0.3, 0.7, of_noise(p * 0.25 + 19.0) * 0.6 + of_noise(p * 1.1) * 0.4 + surface.g * 0.3);
    color = mix(color, mix(vec3(0.33, 0.36, 0.20), vec3(0.42, 0.35, 0.22), of_noise(p * 0.5 + 4.0)) * (0.9 + fine * 0.2), litter * 0.6);
    return of_season_grass(color, p);
}
