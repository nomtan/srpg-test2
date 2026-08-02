shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Sparse pixel-art leaf marks placed above the solid grass cover. Geometry
// controls each cluster's position, size, and rotation; this shader preserves
// the decal silhouette and assigns a small illustrated foliage palette.
uniform sampler2D grass_tex : source_color, filter_nearest, repeat_disable;
uniform float pattern_seed = 0.0;
uniform float texture_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float texture_tile_size : hint_range(0.1, 4.0) = 1.0;
uniform float texture_brightness : hint_range(0.3, 2.0) = 1.0;
uniform float texture_saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec3 overlay_tint : source_color = vec3(0.48, 0.68, 0.32);
uniform float pixel_grid : hint_range(2.0, 12.0) = 6.0;
uniform float leaf_scale : hint_range(0.5, 3.0) = 1.0;
uniform float shape_jitter : hint_range(0.0, 2.0) = 1.0;

// Each leaf mark uses a restrained pale yellow-green palette. Keeping every
// tone lighter than the grass base gives the reference's softly painted look.
const vec3 LEAF_PALE = vec3(0.776, 0.824, 0.451); // #c6d273
const vec3 LEAF_LIGHT = vec3(0.714, 0.788, 0.412); // #b6c969
const vec3 LEAF_MID = vec3(0.624, 0.741, 0.361);   // #9fbd5c
const vec3 LEAF_GREEN = vec3(0.525, 0.678, 0.322); // #86ad52

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + pattern_seed * 0.017) * 43758.5453);
}

void fragment() {
    float safe_scale = max(leaf_scale, 0.001);
    vec2 texture_uv = (UV - vec2(0.5)) / safe_scale + vec2(0.5);
    vec2 native_texel = floor(texture_uv * 32.0) / 32.0;
    vec4 tex = texture(grass_tex, native_texel);

    float source_luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    float palette_roll = fract(
        hash21(floor(native_texel * 32.0)) + source_luma * 0.58
    );
    vec3 palette_color = LEAF_MID;
    if (palette_roll < 0.18) {
        palette_color = LEAF_GREEN;
    } else if (palette_roll > 0.82) {
        palette_color = LEAF_PALE;
    } else if (palette_roll > 0.52) {
        palette_color = LEAF_LIGHT;
    }

    float palette_luma = dot(palette_color, vec3(0.299, 0.587, 0.114));
    vec3 colored_leaf = mix(
        vec3(palette_luma),
        palette_color,
        texture_saturation
    );
    float alpha_jitter = mix(
        1.0,
        smoothstep(0.08, 0.42, tex.a + (palette_roll - 0.5) * 0.16),
        clamp(shape_jitter, 0.0, 1.0)
    );
    ALBEDO = colored_leaf * texture_brightness;
    ALPHA = tex.a * alpha_jitter * texture_opacity;
    ALPHA_SCISSOR_THRESHOLD = 0.08;
}
