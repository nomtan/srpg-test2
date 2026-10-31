shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, shadows_disabled;
// A unit's HP gauge over its head: a dark frame around the bar, the remaining HP in the fill
// colour (lighter along the top), the HP just lost as a pale trail that drains after it, and
// the empty part dark. It faces the camera and draws over everything.
uniform vec3 fill_color : source_color = vec3(0.35, 0.85, 0.35);
uniform vec3 trail_color : source_color = vec3(1.0, 0.86, 0.55);
uniform float ratio = 1.0;
uniform float trail = 1.0;
// Quad width over height, and the frame thickness as a share of the height.
uniform float aspect = 9.0;
uniform float border = 0.16;

void vertex() {
    // Camera-facing billboard at the node's origin, keeping its scale.
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
    vec2 edge = vec2(border / aspect, border);
    bool inside = all(greaterThan(UV, edge)) && all(lessThan(UV, 1.0 - edge));
    float t = (UV.x - edge.x) / (1.0 - 2.0 * edge.x);
    float v = (UV.y - edge.y) / (1.0 - 2.0 * edge.y);
    vec3 color = vec3(0.04, 0.04, 0.06);
    float alpha = 0.92;
    if (inside) {
        if (t < ratio) {
            color = fill_color * mix(1.35, 0.8, v);
            alpha = 1.0;
        } else if (t < trail) {
            color = trail_color;
            alpha = 1.0;
        } else {
            color = vec3(0.12, 0.12, 0.15);
            alpha = 0.85;
        }
    }
    ALBEDO = color;
    ALPHA = alpha;
}
