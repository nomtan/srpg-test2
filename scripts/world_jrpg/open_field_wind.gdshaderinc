// Shared wind model for the Phase 2 vegetation shaders (include after open_field_common).
// Push along wind_direction = steady base + spatial noise drifting downwind + gusts that
// roll across the land as broad bands, so a meadow shows waves instead of one sine.
uniform vec2 wind_direction = vec2(0.82, 0.57);
// Overall strength; the world raises it in rain and lowers it in snow.
uniform float wind_strength = 1.0;

vec2 of_wind_dir() { return normalize(wind_direction); }

// 0 when the gust band is away, 1 at its crest.
float of_wind_gust(vec2 p, float t) {
    vec2 dir = of_wind_dir();
    float along = dot(p, dir);
    float across = dot(p, vec2(-dir.y, dir.x));
    float band = of_noise(vec2(along * 0.03 - t * 0.42, across * 0.018));
    return smoothstep(0.42, 0.82, band);
}

// Scalar push along of_wind_dir(), roughly 0.1..1.5 at wind_strength 1.
float of_wind_push(vec2 p, float t) {
    vec2 drift = of_wind_dir() * t * 1.6;
    float spatial = of_noise(p * 0.18 - drift * 0.18) - 0.5;
    return (0.4 + spatial * 0.55 + of_wind_gust(p, t) * 0.85) * wind_strength;
}
