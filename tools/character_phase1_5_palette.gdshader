shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D base_color_texture : source_color, filter_linear_mipmap;
uniform sampler2D palette_mask : filter_linear_mipmap;
uniform vec4 primary_color : source_color = vec4(0.1,0.7,0.85,1.0);
uniform vec4 secondary_color : source_color = vec4(0.85,0.12,0.3,1.0);
uniform bool change_primary = false;
uniform bool change_secondary = false;
uniform sampler2D cape_mask : filter_linear_mipmap;
uniform sampler2D emblem_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool emblem_enabled = false;
void fragment() {
    vec3 original = texture(base_color_texture,UV).rgb;
    vec3 mask = texture(palette_mask,UV).rgb;
    float brightness = max(max(original.r,original.g),original.b);
    vec3 color = original;
    if (change_primary) color=mix(color,primary_color.rgb*brightness,mask.r);
    if (change_secondary) color=mix(color,secondary_color.rgb*brightness,mask.g);
    if (emblem_enabled) {
        vec4 emblem=texture(emblem_texture,UV2);
        float inside=step(0.0,UV2.x)*step(UV2.x,1.0)*step(0.0,UV2.y)*step(UV2.y,1.0);
        color=mix(color,emblem.rgb,emblem.a*texture(cape_mask,UV).r*inside);
    }
    ALBEDO=color;
}
