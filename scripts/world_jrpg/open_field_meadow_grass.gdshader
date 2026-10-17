shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
#include "res://scripts/world_jrpg/open_field_wind.gdshaderinc"
// Ghibli / BotW grass carpet (open_field_meadow.gd builds the patches).
// Vertex COLOR: r = root->tip tone, g = wind weight, b = per-blade phase, a = thinning rank.
// UV.y: height above the blade root in patch units; MODEL_MATRIX[1].y is the patch height.
// INSTANCE_CUSTOM.xyz: the terrain normal under the patch.
//   * Every blade is lit with the ground's normal, so the carpet shades as one soft mass
//     following the hills, like a painted field, never as per-blade noise.
//   * Roots take the terrain's turf color exactly and ramp to lighter, warmer tips; broad
//     swathes lean yellow or blue-green so the field reads in painted patches.
//   * Painted light: a soft terminator, cool lifted shadows, and tips that glow when the
//     sun is behind them.
//   * Gust bands roll across the field, bending the blades and flashing the tips.
uniform float bend = 0.42;
uniform float flutter = 0.06;
uniform vec3 tip_color : source_color = vec3(0.84, 0.92, 0.46);
uniform vec3 sun_swathe : source_color = vec3(0.86, 0.86, 0.42);
uniform vec3 cool_swathe : source_color = vec3(0.40, 0.66, 0.42);
// Tip lift over the root color, and how far the tips lean to the shared tip color.
uniform vec3 tip_lift = vec3(1.22, 1.2, 0.96);
uniform float tip_mix = 0.5;
// Darkening at the root that gives the carpet depth near the camera.
uniform float root_shade = 0.72;
// Painted light: wrap of the terminator, the share of sunlight kept in cast shadows and
// its cool tint, and the back-lit tip glow.
uniform float wrap = 0.35;
uniform float shadow_lift = 0.5;
uniform vec3 shadow_tint : source_color = vec3(0.6, 0.76, 1.0);
uniform float translucency = 0.9;
// Near blades thin out to the mid patch's density between these distances.
uniform float thin_start = 16.0;
uniform float thin_end = 28.0;
uniform float thin_keep = 0.3;
// Blades sink into the ground between these distances, ahead of the far range end.
uniform float fade_start = 56.0;
uniform float fade_end = 72.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 origin;
varying vec3 ground;
varying float near;
varying float gust;
varying float tone;

void vertex() {
    origin = MODEL_MATRIX[3].xyz;
    float patch_height = MODEL_MATRIX[1].y;
    // Height above this vertex's own blade root, in meters.
    float lift = UV.y * patch_height;
    ground = of_meadow(VERTEX.xz, of_biome(VERTEX.xz).rgb);
    vec3 ground_normal = INSTANCE_CUSTOM.xyz;
    NORMAL = dot(ground_normal, ground_normal) > 0.25 ? normalize(ground_normal) : vec3(0.0, 1.0, 0.0);
    float dist = distance(origin, CAMERA_POSITION_WORLD);
    // Distance thinning: high-rank blades fold into the ground first.
    float keep = mix(1.0, thin_keep, smoothstep(thin_start, thin_end, dist));
    float shrink = clamp((keep - COLOR.a) / 0.08, 0.0, 1.0);
    float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    float scale = shrink * fade;
    float w = COLOR.g;
    vec2 dir = of_wind_dir();
    float push = of_wind_push(origin.xz, TIME);
    gust = of_wind_gust(origin.xz, TIME);
    float wobble = sin(TIME * 3.1 + COLOR.b * 6.283 + origin.x * 0.9 + origin.z * 0.6) * flutter * wind_strength;
    vec2 offset = (dir * push * bend + vec2(-dir.y, dir.x) * wobble) * w * patch_height;
    VERTEX.xz += offset * scale;
    // Bent blades dip, so tips swing on an arc instead of stretching.
    float dip = dot(offset, offset) * 1.4 * w / max(patch_height, 0.05);
    VERTEX.y -= lift * (1.0 - scale) + min(dip, lift * 0.6) * scale + (1.0 - fade) * 0.05;
    near = smoothstep(0.0, 0.6, fade);
    tone = COLOR.r;
}

void fragment() {
    vec4 biome = of_biome(origin.xz);
    // Painted swathes: broad sunny-yellow and cool blue-green patches across the field.
    vec2 q = origin.xz + vec2(of_noise(origin.xz * 0.02), of_noise(origin.xz * 0.02 + 5.0)) * 30.0;
    float sunny = smoothstep(0.55, 0.8, of_noise(q * 0.035 + 11.0));
    float cool = smoothstep(0.58, 0.82, of_noise(q * 0.03 - 23.0));
    vec3 tip = mix(ground * tip_lift + vec3(0.03, 0.04, 0.0), tip_color, tip_mix);
    tip = mix(tip, sun_swathe, sunny * 0.35);
    tip = mix(tip, cool_swathe, cool * 0.3);
    // A little per-patch jitter so neighbors never match.
    tip *= 0.94 + of_hash(origin.xz) * 0.12;
    float t = smoothstep(0.0, 1.0, tone);
    vec3 root = ground * mix(1.0, root_shade, near);
    vec3 color = mix(root, tip, t * near);
    color = mix(color, color * vec3(1.22, 1.18, 1.0), gust * t * near * 0.7);
    color *= mix(vec3(1.0), vec3(0.85, 0.9, 0.9), biome.a * 0.6);
    if (biome_debug > 0.5) color = of_biome_debug(origin.xz) * mix(0.55, 1.0, tone);
    // Snow: whole blades go snow-white, cool blue-grey at the root to white at the tip.
    color = mix(color, mix(vec3(0.70, 0.77, 0.86), vec3(0.95, 0.97, 1.0), 0.35 + 0.65 * tone), clamp(snow_cover * 1.25, 0.0, 1.0));
    color *= 1.0 - wetness * 0.18;
    ALBEDO = of_to_linear(color);
    // Back faces keep the ground normal too (Godot flips NORMAL on them).
    if (!FRONT_FACING) NORMAL = -NORMAL;
}

void light() {
    float ndl = dot(NORMAL, LIGHT);
    // Soft painted terminator: wrapped and eased, never a hard toon step.
    float diffuse = smoothstep(-wrap, 1.0, ndl);
    // Cast shadows keep some cool sunlight, like the blue shade of a painted field
    // (sun only: lamps keep their falloff).
    vec3 lit = LIGHT_IS_DIRECTIONAL ? mix(shadow_tint * shadow_lift, vec3(1.0), ATTENUATION) : vec3(ATTENUATION);
    DIFFUSE_LIGHT += LIGHT_COLOR * lit * diffuse / PI;
    // Looking toward the sun, the tips glow through.
    float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0);
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * tone * tone * near * translucency * vec3(1.0, 1.0, 0.6) / PI;
}
