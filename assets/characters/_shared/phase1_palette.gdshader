shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap;
uniform sampler2D palette_mask : filter_linear_mipmap;
uniform vec4 primary_color : source_color = vec4(1.0);
uniform vec4 secondary_color : source_color = vec4(1.0);
uniform vec4 accent_color : source_color = vec4(1.0);
uniform bool palette_enabled = false;
uniform sampler2D cape_mask : filter_linear_mipmap;
uniform sampler2D emblem_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 emblem_color : source_color = vec4(1.0);
uniform bool emblem_enabled = false;

void fragment() {
    vec3 original = texture(base_color_texture, UV).rgb;
    vec3 mask = texture(palette_mask, UV).rgb;
    vec3 color = original;
    if (palette_enabled) {
        float lightness = max(max(original.r, original.g), original.b);
        color = mix(color, primary_color.rgb * lightness, mask.r);
        color = mix(color, secondary_color.rgb * lightness, mask.g);
        color = mix(color, accent_color.rgb * lightness, mask.b);
    }
    if (emblem_enabled) {
        vec4 emblem = texture(emblem_texture, UV2) * emblem_color;
        float bounds = step(0.0, UV2.x) * step(UV2.x, 1.0)
                     * step(0.0, UV2.y) * step(UV2.y, 1.0);
        color = mix(color, emblem.rgb, emblem.a * texture(cape_mask, UV).r * bounds);
    }
    ALBEDO = color;
}
