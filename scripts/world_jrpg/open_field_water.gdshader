shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
#include "res://scripts/world_jrpg/open_field_toon_water.gdshaderinc"
// Still water, the lake and the sea, cel-shaded like a painted anime sea: flat color bands
// by depth (clear mint shallows down to opaque deep blue), squirming white wave lines,
// a solid foam band at the waterline and, on the sea, surf lines rolling in.
// COLOR.r is the water depth / 8 baked from the height field; COLOR.g fades the surface
// out where a river ribbon takes over at the same level.
uniform vec3 shallow : source_color = vec3(0.58, 0.88, 0.78);
uniform vec3 mid : source_color = vec3(0.30, 0.70, 0.74);
uniform vec3 deep : source_color = vec3(0.14, 0.45, 0.62);
uniform vec3 abyss : source_color = vec3(0.09, 0.30, 0.50);
uniform vec3 line_color : source_color = vec3(0.86, 0.97, 0.98);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sky_tint : source_color = vec3(0.74, 0.90, 0.97);
// Depths (m) where the shallow / mid / deep / abyss bands begin.
uniform vec3 band_depths = vec3(0.7, 2.2, 5.0);
// Opacity of each band: the shallows stay clear enough to see the ground.
uniform vec4 band_alpha = vec4(0.32, 0.62, 0.88, 0.97);
uniform float wetness = 0.0;
// Pattern scale: 1 for the lake, larger for the sea's swell.
uniform float wave_size = 1.0;
// 1 rolls surf lines in toward the shore (the sea).
uniform float surf = 0.0;
// Directional light kept in cast shadows.
uniform float shade = 0.55;
varying vec3 world_position;
varying float depth;
varying float handover;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    depth = COLOR.r * 8.0;
    handover = COLOR.g;
}

void fragment() {
    vec2 p = world_position.xz;
    float t = TIME;
    // Wobbly band edges, so the depth contours read as brush strokes rather than isolines.
    float wobble = (of_noise(p * 0.12 / wave_size + t * 0.04) - 0.5) + (of_noise(p * 0.5 - t * 0.07) - 0.5) * 0.4;
    float d = depth + wobble * 0.9;
    float b1 = tw_step(band_depths.x, d);
    float b2 = tw_step(band_depths.y, d);
    float b3 = tw_step(band_depths.z, d);
    vec3 color = mix(mix(mix(shallow, mid, b1), deep, b2), abyss, b3);
    float alpha = mix(mix(mix(band_alpha.x, band_alpha.y, b1), band_alpha.z, b2), band_alpha.w, b3);
    // Wave lines: Voronoi borders warped by noise and stretched across the swell, broken
    // into strokes by a mask that thins them out over deep water.
    vec2 q = p / (2.4 * wave_size);
    q += vec2(of_noise(q * 0.5 + t * 0.07), of_noise(q * 0.5 + 7.0 - t * 0.07)) * 1.6;
    float edge = tw_voronoi_edge(q * vec2(0.7, 2.2), t * 0.55);
    float lines = 1.0 - tw_step(0.03, edge);
    // Only scattered strokes survive: denser over the shelf, rare out on deep water.
    float strokes = of_noise(p * 0.6 / wave_size + vec2(t * 0.08, -t * 0.05)) * 0.6 + of_noise(p * 0.06 / wave_size) * 0.4;
    lines *= tw_step(mix(0.58, 0.68, b2), strokes);
    // Far off the strokes would shrink into noise; let them fade into the flat color.
    lines *= 1.0 - smoothstep(70.0, 180.0, length(VERTEX));
    color = mix(color, line_color, lines * 0.9);
    alpha = max(alpha, lines * 0.85);
    // Waterline foam: a solid band that laps in and out.
    float lap = sin(t * 1.2 + of_noise(p * 0.25) * 6.0) * 0.06;
    float foam = 1.0 - tw_step(0.2 + lap, depth);
    // Surf: thin crest lines whose phase runs toward shallower water.
    float crest = fract(depth * 0.8 + t * 0.22 + of_noise(p * 0.04) * 0.6);
    foam = max(foam, surf * (1.0 - tw_step(0.07, crest)) * (1.0 - tw_step(2.2, depth)) * tw_step(0.3, depth));
    // Rain: hard little rings.
    float ring = abs(length(fract(p * 0.7) - 0.5) - fract(t * 1.5) * 0.5);
    foam = max(foam, wetness * (1.0 - tw_step(0.025, ring)) * 0.7);
    color = mix(color, foam_color, foam);
    alpha = max(alpha, foam * 0.95);
    // Grazing angles pick up a flat band of sky.
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    color = mix(color, sky_tint, tw_step(0.45, fresnel) * 0.25);
    ALBEDO = color;
    ALPHA = alpha * (1.0 - handover);
    ROUGHNESS = 1.0;
}

void light() {
    DIFFUSE_LIGHT += tw_diffuse(LIGHT_COLOR, dot(NORMAL, LIGHT), ATTENUATION, shade);
    SPECULAR_LIGHT += tw_glint(LIGHT_COLOR, NORMAL, LIGHT, VIEW, ATTENUATION, world_position.xz, TIME);
}
