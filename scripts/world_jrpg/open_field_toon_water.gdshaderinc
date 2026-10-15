// Shared helpers for the cel-shaded (anime / Ghibli style) water of JRPGWorldSample2:
// hard color bands, Voronoi wave lines and foam bubbles, and banded lighting.
// Needs open_field_common.gdshaderinc (of_noise) included first.

vec2 tw_hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Hard step with a pixel-wide antialiased edge, so bands stay crisp at any distance.
float tw_step(float edge, float x) {
    float w = fwidth(x) * 0.75 + 0.0001;
    return smoothstep(edge - w, edge + w, x);
}

// Distance to the nearest Voronoi cell border; the feature points orbit with t, so the
// borders squirm like the bright wave lines of a painted sea.
float tw_voronoi_edge(vec2 p, float t) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    vec2 mg = vec2(0.0);
    vec2 mr = vec2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = 0.5 + 0.5 * sin(t + 6.2831 * tw_hash2(n + g));
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) {
                md = d;
                mr = r;
                mg = g;
            }
        }
    }
    md = 8.0;
    for (int j = -2; j <= 2; j++) {
        for (int i = -2; i <= 2; i++) {
            vec2 g = mg + vec2(float(i), float(j));
            vec2 o = 0.5 + 0.5 * sin(t + 6.2831 * tw_hash2(n + g));
            vec2 r = g + o - f;
            if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
        }
    }
    return md;
}

// Distance to the nearest Voronoi feature point (round foam bubbles).
float tw_voronoi_f1(vec2 p, float t) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = 0.5 + 0.5 * sin(t + 6.2831 * tw_hash2(n + g));
            md = min(md, length(g + o - f));
        }
    }
    return md;
}

// Banded directional light: full light or a flat shade, with hard cast shadows.
vec3 tw_diffuse(vec3 light_color, float ndl, float attenuation, float shade) {
    float lit = smoothstep(0.42, 0.58, attenuation) * step(0.0, ndl);
    return light_color * max(ndl, 0.3) * mix(shade, 1.0, lit) / PI;
}

// The sun's reflection broken into hard sparkles.
vec3 tw_glint(vec3 light_color, vec3 normal, vec3 light, vec3 view, float attenuation, vec2 p, float t) {
    float facing = dot(reflect(-light, normal), view);
    float sparkle = step(0.62, of_noise(p * 1.7 + vec2(t * 0.9, -t * 0.6)));
    return light_color * step(0.975, facing) * sparkle * smoothstep(0.42, 0.58, attenuation) * 1.5;
}
