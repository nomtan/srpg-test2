shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.8, 0.87, 0.95, 0.65);
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    ALBEDO = tint.rgb;
    ALPHA = (1.0 - smoothstep(0.15, 0.5, length(UV - vec2(0.5)))) * tint.a * smoothstep(2.0, 5.0, length(VERTEX));
}
