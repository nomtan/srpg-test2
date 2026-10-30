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
// dull, nearly grey dormant grass in winter.
vec3 of_season_grass(vec3 c, vec2 p) {
    if (season == 1) return c;
    float l = of_luma(c) / 0.55;
    float n = of_noise(p * 0.03 + 71.0);
    if (season == 0) return mix(c, mix(vec3(0.55, 0.77, 0.33), vec3(0.64, 0.80, 0.38), n) * l, 0.5);
    if (season == 2) return mix(c, mix(vec3(0.72, 0.64, 0.34), vec3(0.58, 0.52, 0.30), n) * l, 0.5 + 0.2 * n);
    return mix(c, mix(vec3(0.58, 0.57, 0.52), vec3(0.50, 0.50, 0.47), n) * l, 0.88);
}

// Broadleaf crowns. seed (0..1, per tree) staggers autumn into orange, red and yellow
// trees (no green left); winter keeps the autumn hues, heavily faded.
vec3 of_season_leaf(vec3 c, float seed) {
    if (season == 1) return c;
    float l = of_luma(c) / 0.5;
    // Spring: fresh green, with one tree in seven in pink blossom.
    if (season == 0) return seed < 0.14 ? mix(c, vec3(1.0, 0.74, 0.84) * mix(l, 1.0, 0.5), 0.85) : mix(c, vec3(0.58, 0.82, 0.36) * l, 0.45);
    vec3 hue = seed < 0.4 ? vec3(0.95, 0.52, 0.17) : (seed < 0.72 ? vec3(0.84, 0.27, 0.16) : vec3(0.96, 0.78, 0.24));
    vec3 autumn = hue * l * 0.9;
    if (season == 2) return autumn;
    return mix(autumn, vec3(of_luma(autumn)), 0.75) * 0.9;
}

// Conifers: a little lighter in spring; in autumn and winter they follow the broadleaves
// (no green crowns left in autumn, faded autumn hues in winter).
vec3 of_season_evergreen(vec3 c, float seed) {
    if (season == 0) return c * vec3(1.04, 1.07, 0.98);
    if (season >= 2) return of_season_leaf(c, seed);
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
// Battle-grid view (F4): grid_span m tactical cells inside 0..grid_extent, each outlined as
// its own tile: blue glowing tiles for the move range, thin faint outlines for a band of
// cells around it, and a yellow cursor cell with corner brackets. grid_range_map holds one
// texel per tactical cell (texel (0, 0) at cell grid_range_origin): R = 1 in the move
// range, G = 1 in the range and the band. The terrain and the grass blades both draw it, so it lies over
// the turf.
uniform float grid_debug = 0.0;
uniform float grid_span = 2.0;
uniform float grid_extent = 400.0;
uniform sampler2D grid_range_map : filter_nearest, repeat_disable, hint_default_black;
uniform vec2 grid_range_origin = vec2(-100000.0);
uniform vec2 grid_cursor = vec2(-100000.0);
// The explorer's cell: a slightly more opaque fill with a wider inner glow.
uniform vec2 grid_current = vec2(-100000.0);

vec2 of_grid_cell(vec2 cell) {
    vec2 uv = (cell - grid_range_origin + 0.5) / vec2(textureSize(grid_range_map, 0));
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec2(0.0);
    return texture(grid_range_map, uv).rg;
}

float of_grid_in_range(vec2 cell) {
    return of_grid_cell(cell).r;
}

// Grass blade height scale at ground point p: blades in the move range are cut to grid_mow
// so the tiles stay clear while the turf still shows.
uniform float grid_mow = 0.3;
float of_grid_mow(vec2 p) {
    if (grid_debug < 0.5) return 1.0;
    return of_grid_in_range(floor(p / grid_span)) > 0.5 ? grid_mow : 1.0;
}

// Blends the grid over `color` (sRGB) at ground point p and adds its glow (sRGB) to `glow`.
// px: meters per screen pixel along x / z, so lines keep about the same width on screen
// and fade where cells shrink to a few pixels.
void of_grid_overlay(vec2 p, vec2 px, inout vec3 color, inout vec3 glow) {
    if (grid_debug < 0.5 || p.x < 0.0 || p.y < 0.0 || p.x > grid_extent || p.y > grid_extent) return;
    const vec3 LINE = vec3(0.45, 0.88, 1.0);
    const vec3 FILL = vec3(0.25, 0.66, 0.96);
    const vec3 CURSOR = vec3(1.0, 0.8, 0.22);
    vec2 t = p / grid_span;
    vec2 cell = floor(t);
    vec2 f = t - cell;
    vec2 step_t = max(px / grid_span, vec2(1e-5));
    vec2 cells = of_grid_cell(cell);
    bool cursor = length(cell - grid_cursor) < 0.5;
    bool current = length(cell - grid_current) < 0.5;
    if (cells.g < 0.5 && !cursor) return;
    // Every cell is its own tile, outlined just inside its edges so neighbors keep a gap:
    // pixels inside the outline (negative in the gap).
    vec2 inside = (min(f, 1.0 - f) - 0.045) / step_t;
    float to_rim = min(inside.x, inside.y);
    float visible = 1.0 - smoothstep(0.06, 0.2, max(step_t.x, step_t.y));
    if (cells.r > 0.5) {
        // In range: a blue tile with a bright glowing rim.
        float rim = 1.0 - smoothstep(0.8, 2.2, abs(to_rim));
        // The explorer's own cell glows twice as far in from its rim.
        float halo = to_rim > 0.0 ? exp(-to_rim / (current ? 12.0 : 6.0)) : exp(to_rim / 6.0) * 0.4;
        // The cursor's yellow replaces the blue fill but keeps the rim.
        if (!cursor && to_rim > 0.0) {
            // The explorer's own cell is also a little more opaque.
            color = mix(color, FILL, (current ? 0.52 : 0.42) + halo * 0.2);
            glow += FILL * (0.42 + halo * 0.4);
        }
        glow += LINE * (halo * 0.6 + rim * 1.5);
        color = mix(color, vec3(0.5, 0.9, 1.0), rim);
    } else if (cells.g > 0.5) {
        // The band around the range: a thin faint outline only.
        float rim = (1.0 - smoothstep(0.4, 1.4, abs(to_rim))) * visible;
        color = mix(color, LINE, rim * 0.6);
        glow += LINE * rim * 0.5;
    }
    if (cursor) {
        // Corner brackets: L-shaped arms along each corner's two edges, thicker than the outline.
        vec2 c = min(f, 1.0 - f) / step_t;
        vec2 arm = 0.28 / step_t;
        float thick = 3.5;
        float bracket = max((1.0 - smoothstep(thick, thick + 1.0, c.x)) * step(c.y, arm.y), (1.0 - smoothstep(thick, thick + 1.0, c.y)) * step(c.x, arm.x));
        float outline = 1.0 - smoothstep(0.6, 1.6, abs(to_rim));
        color = mix(color, CURSOR, 0.5);
        color = mix(color, vec3(1.0, 0.92, 0.5), max(bracket, outline * 0.7));
        glow += CURSOR * (0.3 + outline * 0.6 + bracket * 2.2);
    }
}

// Meters per pixel at a point `dist` m from the camera, for of_grid_overlay off the
// terrain (the grass blades), where screen derivatives of the ground point do not exist.
vec2 of_grid_px(float dist, float elevation, mat4 projection, vec2 viewport) {
    return vec2(dist * 2.0 / (projection[1][1] * viewport.y) / max(elevation, 0.2));
}

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
