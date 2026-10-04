shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// COLOR.r is the lake depth / 8 baked from the height field: shallow shores turn
// turquoise and foam, the middle of the lake becomes a deep blue mirror.
uniform vec3 shallow : source_color = vec3(0.45, 0.80, 0.80);
uniform vec3 deep : source_color = vec3(0.11, 0.36, 0.53);
uniform vec3 sky_tint : source_color = vec3(0.72, 0.87, 0.96);
uniform float wetness = 0.0;
varying vec3 world_position;
varying float depth;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    depth = COLOR.r * 8.0;
}

void fragment() {
    vec2 p = world_position.xz;
    float t = TIME;
    vec2 w1 = vec2(sin(p.x * 0.35 + t * 0.9 + sin(p.y * 0.21)), cos(p.y * 0.31 - t * 0.7 + sin(p.x * 0.17)));
    vec2 w2 = vec2(sin(p.y * 1.3 + t * 1.7), cos(p.x * 1.1 - t * 1.4));
    float rain = wetness * sin(length(fract(p * 0.7) - 0.5) * 40.0 - t * 12.0) * 0.03;
    vec3 wn = normalize(vec3(w1.x * 0.05 + w2.x * 0.02 + rain, 1.0, w1.y * 0.05 + w2.y * 0.02 + rain));
    NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    vec3 color = mix(shallow, deep, smoothstep(0.2, 6.0, depth));
    color = mix(color, sky_tint, fresnel * 0.55);
    float foam = (1.0 - smoothstep(0.05, 0.55, depth)) * (0.6 + 0.4 * sin(t * 1.5 + p.x * 0.8 + p.y * 0.6));
    foam = clamp(foam, 0.0, 1.0);
    ALBEDO = mix(color, vec3(0.95, 0.98, 1.0), foam * 0.75);
    ALPHA = clamp(mix(0.45, 0.9, smoothstep(0.0, 3.5, depth)) + foam * 0.4 + fresnel * 0.2, 0.0, 1.0);
    ROUGHNESS = 0.06;
    SPECULAR = 0.7;
}
