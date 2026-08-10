// Screen-stable pixel-art helpers shared by character body and face shaders.
// The model stays fully animated; only its rendered colors are grouped into
// small blocks and reduced to a compact per-channel palette.

group_uniforms pixel_art;
uniform float pixel_block_size : hint_range(1.0, 8.0, 1.0) = 3.0;
uniform float color_steps : hint_range(2.0, 16.0, 1.0) = 5.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.05) = 1.0;
group_uniforms;

float pixel_dither(vec2 fragment_position) {
    vec2 pixel = floor(fragment_position / max(pixel_block_size, 1.0));
    vec2 cell = mod(pixel, 4.0);
    vec4 row;
    if (cell.y < 1.0) {
        row = vec4(0.0, 8.0, 2.0, 10.0);
    } else if (cell.y < 2.0) {
        row = vec4(12.0, 4.0, 14.0, 6.0);
    } else if (cell.y < 3.0) {
        row = vec4(3.0, 11.0, 1.0, 9.0);
    } else {
        row = vec4(15.0, 7.0, 13.0, 5.0);
    }
    return (row[int(cell.x)] + 0.5) / 16.0;
}

vec3 pixel_palette(vec3 color, vec2 fragment_position) {
    float levels = max(color_steps - 1.0, 1.0);
    vec3 scaled = clamp(color, 0.0, 1.0) * levels;
    vec3 rounded = floor(scaled + 0.5) / levels;
    vec3 lower = floor(scaled) / levels;
    vec3 upper = min(lower + vec3(1.0 / levels), vec3(1.0));
    float threshold = pixel_dither(fragment_position);
    vec3 ordered = mix(lower, upper, step(vec3(threshold), fract(scaled)));
    return mix(rounded, ordered, dither_strength);
}
