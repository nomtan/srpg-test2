// Shared flat-shading building blocks (docs/dev/phase/phase17-step1.md).
// No lighting is computed anywhere in this pipeline - render_mode unshaded
// everywhere, ALBEDO is written directly. Variation comes from hue, not
// value: see flat_shading_spec.md design rule 3 before touching this file.

group_uniforms facing;
uniform float face_top    : hint_range(0.0, 1.5) = 1.00;
uniform float face_side_x : hint_range(0.0, 1.5) = 0.92;
uniform float face_side_z : hint_range(0.0, 1.5) = 0.84;
uniform float face_bottom : hint_range(0.0, 1.5) = 0.68;
group_uniforms;

group_uniforms variation;
uniform float tile_size : hint_range(0.1, 4.0) = 1.0;
uniform float hue_jitter : hint_range(0.0, 0.15) = 0.04;
uniform float sat_jitter : hint_range(0.0, 0.3) = 0.08;
uniform float val_jitter : hint_range(0.0, 0.1) = 0.02;  // keep small
group_uniforms;

group_uniforms strata;
uniform bool  strata_enabled = true;
uniform float strata_height : hint_range(0.1, 4.0) = 0.5;
uniform float strata_hue_jitter : hint_range(0.0, 0.15) = 0.03;
uniform float strata_val_jitter : hint_range(0.0, 0.1) = 0.03;
group_uniforms;

// Assigns top/side/bottom coefficients from a world-space normal. The
// smoothstep is a no-op for axis-aligned voxel geometry but keeps sloped
// props / future non-axis-aligned meshes from popping between bands.
float face_factor(vec3 wn) {
    vec3 n = abs(wn);
    float side = mix(face_side_z, face_side_x, step(n.z, n.x));
    float vert = wn.y > 0.0 ? face_top : face_bottom;
    return mix(side, vert, smoothstep(0.55, 0.90, n.y));
}

// INV_VIEW_MATRIX isn't available in fragment() on the GL Compatibility
// renderer this project targets (see project.godot), unlike Forward+/Mobile.
// Computing world space in vertex() via MODEL_MATRIX and passing it through
// varyings works on every renderer instead. Godot only allows a varying to
// be assigned directly inside vertex() itself (not in a function it calls),
// so every shader that includes this file must call the FLAT_VERTEX_SETUP
// macro below from its own vertex():
//     void vertex() {
//         FLAT_VERTEX_SETUP
//     }
// world_normal()/world_pos() below then read the result back in fragment().
//
// flat_world_normal is `flat` - a normal is constant across a face, and
// `flat` guarantees no interpolation artifacts if a smooth-shaded mesh ever
// gets mixed in. flat_world_pos must NOT be flat - apply_variation()'s tile
// hash and apply_strata()'s height band both depend on the interpolated
// per-fragment world position; making it flat would collapse an entire
// polygon to one tile ID and erase the pattern.
// Note the qualifier order: Godot requires `varying flat`, not `flat
// varying` - the latter fails to parse ("Expected constant, function,
// uniform or varying") on this engine build.
varying flat vec3 flat_world_normal;
varying vec3 flat_world_pos;

// Object-like macro, called WITHOUT parentheses (`FLAT_VERTEX_SETUP`, not
// `FLAT_VERTEX_SETUP()`). Godot's shader preprocessor on this engine build
// does not support function-like macros (`#define NAME() ...`) - defining
// one compiles silently, but every #include of this file then fails to
// tokenize with "Unknown character '#'" at the *including* shader's
// #include line (confirmed by bisection). Keep this as a plain object-like
// macro; do not add parentheses.
#define FLAT_VERTEX_SETUP flat_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; flat_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

vec3 world_normal() { return normalize(flat_world_normal); }
vec3 world_pos()    { return flat_world_pos; }

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Tile-quantized (not per-pixel) hash - patches switch at tile boundaries,
// matching the reference image's look.
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Per-tile hue/sat/val jitter. Pass floor(world_pos().xz / tile_size) as
// tile_id. val_jitter defaults small on purpose - see design rule 3.
vec3 apply_variation(vec3 base, vec2 tile_id) {
    float h1 = hash21(tile_id);
    float h2 = hash21(tile_id + vec2(37.0, 91.0));
    float h3 = hash21(tile_id + vec2(11.0, 53.0));
    vec3 hsv = rgb2hsv(base);
    hsv.x = fract(hsv.x + (h1 - 0.5) * hue_jitter);
    hsv.y = clamp(hsv.y + (h2 - 0.5) * sat_jitter, 0.0, 1.0);
    hsv.z = clamp(hsv.z + (h3 - 0.5) * val_jitter, 0.0, 1.0);
    return hsv2rgb(hsv);
}

// Height-banded hue/val shift for cliff faces (the reference image's rust
// strata). Side faces only - call sites must gate on abs(wn.y) < 0.5
// themselves so the top face never bands.
vec3 apply_strata(vec3 base, float world_y) {
    if (!strata_enabled) {
        return base;
    }
    float band_id = floor(world_y / strata_height);
    float h1 = hash21(vec2(band_id, 17.0));
    float h2 = hash21(vec2(band_id, 53.0));
    vec3 hsv = rgb2hsv(base);
    hsv.x = fract(hsv.x + (h1 - 0.5) * strata_hue_jitter);
    hsv.z = clamp(hsv.z + (h2 - 0.5) * strata_val_jitter, 0.0, 1.0);
    return hsv2rgb(hsv);
}
