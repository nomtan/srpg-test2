shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_schlick_ggx;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
#include "res://scripts/world_jrpg/open_field_wind.gdshaderinc"
// Blender-built grass and flower clusters (assets/environment/vegetation/grass, flowers).
// Vertex COLOR: r = root->tip tone, g = wind weight (0 at the root), b = per-blade phase,
// a = petal palette on flower heads (1 warm, 0 cool).
// INSTANCE_CUSTOM.xyz: the terrain normal under the clump (zero when not supplied).
// flower = 0 is GrassMaterial; flower = 1 is FlowerMaterial (the petal surface only).
// Ghibli / BotW meadow (after Kristof Dedene's EEVEE stylized-grass setup):
//   * every blade is shaded with the ground's normal, so the field lights like the
//     terrain under it: hills keep their soft light and shadow, no per-blade noise;
//   * a blade's root is exactly the terrain's turf color at that spot (of_meadow) and
//     ramps to a lighter, warmer tip, so the carpet melts into the ground;
//   * gust bands roll across the field, bending blades and flashing the tips.
uniform float bend = 0.2;
uniform float flutter = 0.04;
uniform vec3 light_green : source_color = vec3(0.66, 0.84, 0.38);
uniform vec3 yellow_green : source_color = vec3(0.80, 0.82, 0.40);
uniform vec3 dark_green : source_color = vec3(0.30, 0.50, 0.24);
// How far tips lean toward the patch variant (light / base / yellow / dark green).
uniform float variant_amount = 0.22;
// Tip lift over the root color, and the slight darkening at the root that gives the
// carpet depth near the camera.
uniform vec3 tip_lift = vec3(1.2, 1.17, 0.94);
uniform float root_shade = 0.86;
uniform float flower = 0.0;
// Petals: a muted palette for the dark-fantasy field. Each drift (noise patch) takes one
// colour of its asset's warm or cool pair, so flowers bloom in clusters, not confetti.
uniform vec3 petal_white : source_color = vec3(0.93, 0.91, 0.84);
uniform vec3 petal_yellow : source_color = vec3(0.93, 0.80, 0.38);
uniform vec3 petal_violet : source_color = vec3(0.62, 0.52, 0.80);
uniform vec3 petal_blue : source_color = vec3(0.50, 0.58, 0.80);
uniform vec3 petal_center : source_color = vec3(0.86, 0.62, 0.20);
// Blades sink into the ground between these camera distances, ahead of the visibility
// range end, so the grass boundary never shows as a line.
uniform float fade_start = 52.0;
uniform float fade_end = 68.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 origin;
varying vec3 ground;
varying float near;
varying float gust;

void vertex() {
    origin = MODEL_MATRIX[3].xyz;
    // Turf color under this vertex before the wind moves it: the root vertices sit on the
    // ground and take exactly its color.
    ground = of_meadow(VERTEX.xz, of_biome(VERTEX.xz).rgb);
    vec3 ground_normal = INSTANCE_CUSTOM.xyz;
    NORMAL = dot(ground_normal, ground_normal) > 0.25 ? normalize(ground_normal) : vec3(0.0, 1.0, 0.0);
    float w = COLOR.g;
    vec2 dir = of_wind_dir();
    float push = of_wind_push(origin.xz, TIME);
    gust = of_wind_gust(origin.xz, TIME);
    float wobble = sin(TIME * 3.3 + COLOR.b * 6.283 + origin.x * 0.9 + origin.z * 0.6) * flutter * wind_strength;
    vec2 offset = (dir * push * bend + vec2(-dir.y, dir.x) * wobble) * w;
    // Bent blades also dip, so tips swing on an arc instead of stretching.
    VERTEX.xz += offset;
    VERTEX.y -= dot(offset, offset) * 1.6 * w;
    float fade = 1.0 - smoothstep(fade_start, fade_end, distance(origin, CAMERA_POSITION_WORLD));
    // The tip ramp flattens out ahead of the sink, so the carpet's far edge is already
    // the ground's color when the blades go.
    near = smoothstep(0.0, 0.6, fade);
    VERTEX.y = origin.y + (VERTEX.y - origin.y) * fade - (1.0 - fade) * 0.05;
}

void fragment() {
    vec4 biome = of_biome(origin.xz);
    // Variants cluster in patches (noise) with a little per-clump jitter (hash).
    float pick = fract(of_noise(origin.xz * 0.21 + 7.0) * 1.7 + of_hash(origin.xz) * 0.45);
    vec3 variant = pick < 0.25 ? light_green : (pick < 0.5 ? ground : (pick < 0.75 ? yellow_green : dark_green));
    vec3 tip = mix(ground * tip_lift + vec3(0.03, 0.04, 0.0), variant, variant_amount);
    float t = smoothstep(0.05, 1.0, COLOR.r);
    vec3 color = mix(ground * mix(1.0, root_shade, near), tip, t * near);
    if (flower > 0.5) {
        bool first = of_noise(origin.xz * 0.09 + 41.0) + of_hash(origin.xz) * 0.12 < 0.55;
        vec3 warm = first ? petal_white : petal_yellow;
        vec3 cool = first ? petal_violet : petal_blue;
        vec3 petal = mix(cool, warm, COLOR.a) * mix(0.78, 1.04, COLOR.r);
        color = COLOR.r < 0.15 ? petal_center : petal;
    }
    // A passing gust bends the blades and flashes their tips lighter: the rolling waves
    // across the meadow.
    color = mix(color, color * vec3(1.24, 1.2, 1.02), gust * t * near * 0.75);
    color *= mix(vec3(1.0), vec3(0.85, 0.9, 0.9), biome.a * 0.6);
    if (biome_debug > 0.5) color = of_biome_debug(origin.xz) * mix(0.55, 1.0, COLOR.r);
    color = mix(color, vec3(0.92, 0.95, 0.98), snow_cover * COLOR.r * 0.7);
    color *= 1.0 - wetness * 0.18;
    ALBEDO = of_to_linear(color);
    // Same surface response as the terrain, so blade and ground light identically.
    ROUGHNESS = mix(0.95, 0.5, wetness);
    SPECULAR = 0.25;
    // Godot flips NORMAL on back faces when culling is off; both sides keep the ground
    // normal.
    if (!FRONT_FACING) NORMAL = -NORMAL;
}
