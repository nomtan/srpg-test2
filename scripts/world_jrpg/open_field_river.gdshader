shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
#include "res://scripts/world_jrpg/open_field_toon_water.gdshaderinc"
// Flowing river ribbons (see _build_river_meshes), cel-shaded to match the lake and sea:
// flat depth bands, long white streaks riding the current, two-tone stripes racing down
// each fall and round foam bubbles churning below it. UV.x is meters across the river,
// UV.y the distance along the flow; COLOR.r = depth / 8, g = waterfall sheet, b = fade at
// the spring and where the river meets still water, a = foam below a fall.
uniform vec3 shallow : source_color = vec3(0.62, 0.90, 0.80);
uniform vec3 mid : source_color = vec3(0.33, 0.73, 0.76);
uniform vec3 deep : source_color = vec3(0.16, 0.48, 0.63);
uniform vec3 line_color : source_color = vec3(0.88, 0.98, 0.98);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 fall_color : source_color = vec3(0.70, 0.90, 0.95);
// Depths (m) where the mid and deep bands begin.
uniform vec2 band_depths = vec2(0.5, 1.4);
uniform vec3 band_alpha = vec3(0.30, 0.62, 0.9);
uniform float wetness = 0.0;
// Flow speed in meters per second.
uniform float flow_speed = 1.6;
uniform float shade = 0.55;
varying vec3 world_position;
varying vec4 data;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    data = COLOR;
}

void fragment() {
    float depth = data.r * 8.0;
    float fall = clamp(data.g, 0.0, 1.0);
    float t = TIME * flow_speed;
    if (!FRONT_FACING) NORMAL = -NORMAL;
    float wobble = of_noise(vec2(UV.x * 0.8, (UV.y - t) * 0.3)) - 0.5;
    float d = depth + wobble * 0.5;
    float b1 = tw_step(band_depths.x, d);
    float b2 = tw_step(band_depths.y, d);
    vec3 color = mix(mix(shallow, mid, b1), deep, b2);
    float alpha = mix(mix(band_alpha.x, band_alpha.y, b1), band_alpha.z, b2);
    // Streaks: Voronoi borders stretched along the current and scrolled with it, broken
    // into dashes.
    vec2 flow = vec2(UV.x * 1.1, (UV.y - t) * 0.12);
    float edge = tw_voronoi_edge(flow + vec2(of_noise(flow * 1.3) * 0.5, 0.0), TIME * 0.8);
    float streaks = (1.0 - tw_step(0.04, edge)) * tw_step(0.55, of_noise(vec2(UV.x * 0.6, (UV.y - t) * 0.2) + 3.0));
    color = mix(color, line_color, streaks * (1.0 - fall));
    alpha = max(alpha, streaks * 0.85 * (1.0 - fall));
    // Waterfall: two-tone stripes falling down the sheet, white at the lip.
    float stripe = of_noise(vec2(UV.x * 1.6, (UV.y - t * 1.6) * 0.5)) * 0.75 + of_noise(vec2(UV.x * 4.0, UV.y - t * 1.6)) * 0.25;
    vec3 sheet = mix(fall_color, foam_color, tw_step(0.58, stripe));
    sheet = mix(sheet, mid, 1.0 - tw_step(0.36, stripe));
    color = mix(color, sheet, tw_step(0.5, fall));
    alpha = max(alpha, tw_step(0.5, fall) * 0.95);
    // Churn below a fall: clusters of round bubbles that boil and drift downstream.
    float bubbles = tw_voronoi_f1(vec2(UV.x, UV.y - t * 0.6) * 1.3, TIME * 2.5);
    float churn = 1.0 - tw_step(0.12 + 0.38 * data.a, bubbles);
    churn *= tw_step(0.05, data.a) * (1.0 - tw_step(0.5, fall));
    // Lapping foam where the river meets its banks.
    float lap = 1.0 - tw_step(0.1 + wobble * 0.15, depth);
    float ring = abs(length(fract(world_position.xz * 0.7) - 0.5) - fract(TIME * 1.5) * 0.5);
    float rain = wetness * (1.0 - tw_step(0.025, ring)) * 0.7;
    float foam = max(max(churn, lap), rain);
    color = mix(color, foam_color, foam);
    alpha = max(alpha, foam * 0.95);
    ALBEDO = color;
    ALPHA = alpha * clamp(data.b, 0.0, 1.0);
    ROUGHNESS = 1.0;
}

void light() {
    DIFFUSE_LIGHT += tw_diffuse(LIGHT_COLOR, dot(NORMAL, LIGHT), ATTENUATION, shade);
    SPECULAR_LIGHT += tw_glint(LIGHT_COLOR, NORMAL, LIGHT, VIEW, ATTENUATION, world_position.xz, TIME) * 0.6;
}
