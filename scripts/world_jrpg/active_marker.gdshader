shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;
// The active unit's marker: a white downward arrowhead over its head (straight sides meeting
// in a sharp tip, a curved notch across the top leaving two pointed wings) with a small
// diamond above the notch. White, with a yellow glow along its edges both inside and out.
// It faces the camera and draws over everything so the grid view always shows who acts.
uniform vec3 fill_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 glow_color : source_color = vec3(1.0, 0.8, 0.2);
// How far each glow fades from the edge, in the shape's units (the shape spans about -1..1).
uniform float inner_glow = 0.07;
uniform float outer_glow = 0.09;

void vertex() {
    // Camera-facing billboard at the node's origin, keeping its scale.
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

// Signed distance to a triangle (negative inside).
float triangle(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    vec2 v0 = p - a, v1 = p - b, v2 = p - c;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)), vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

void fragment() {
    // +1 at the top; the shape spans about -1..1 with a margin left for the outer glow.
    vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0) * 1.2;
    // Arrowhead: a triangle with a large circle cut from its top edge.
    float head = max(triangle(p, vec2(-0.85, 0.3), vec2(0.85, 0.3), vec2(0.0, -0.75)), 1.23 - length(p - vec2(0.0, 1.3)));
    // Diamond above the notch.
    vec2 q = abs(p - vec2(0.0, 0.42));
    float diamond = (q.x * 0.24 + q.y * 0.24 - 0.24 * 0.24) / length(vec2(0.24));
    float d = min(head, diamond);
    float aa = fwidth(d);
    float shape = 1.0 - smoothstep(-aa, aa, d);
    float inner = exp(min(d, 0.0) / inner_glow);
    float outer = exp(-max(d, 0.0) / outer_glow);
    ALBEDO = mix(glow_color, mix(fill_color, glow_color, inner * 0.85), shape);
    ALPHA = max(shape, outer * 0.8);
}
