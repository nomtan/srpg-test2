shader_type sky;
uniform vec3 zenith : source_color = vec3(0.20, 0.40, 0.65);
uniform vec3 horizon : source_color = vec3(0.75, 0.82, 0.86);
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.42, 0.51, 0.60);
uniform vec3 sun_direction = vec3(-0.5, 0.4, -0.5);
uniform float coverage = 0.45;
uniform float night = 0.0;
uniform float wind_clock = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p) {
    float value = 0.0, weight = 0.5;
    for (int i=0; i<5; i++) { value += noise(p) * weight; p = p * 2.03 + vec2(3.1, 7.2); weight *= 0.5; }
    return value;
}
void sky() {
    vec3 dir = normalize(EYEDIR);
    COLOR = mix(horizon, zenith, pow(max(dir.y, 0.0), 0.45));
    float sun = max(dot(dir, normalize(sun_direction)), 0.0);
    COLOR += cloud_lit * (pow(sun, 700.0) * 1.3 + pow(sun, 18.0) * 0.12) * (1.0 - coverage * 0.8);
    if (dir.y > 0.015) {
        vec2 p = dir.xz / (dir.y + 0.22) * 2.3 + vec2(wind_clock * 0.012, wind_clock * 0.003);
        float density = fbm(p);
        float threshold = mix(0.66, 0.23, coverage);
        float cloud = smoothstep(threshold - 0.04, threshold + 0.16, density);
        float light_edge = clamp((density - fbm(p + sun_direction.xz * 0.15)) * 8.0 + 0.55, 0.0, 1.0);
        vec3 cloud_color = mix(cloud_shade, cloud_lit, light_edge);
        cloud *= smoothstep(0.015, 0.10, dir.y);
        COLOR = mix(COLOR, cloud_color, cloud);
        vec2 stars = floor(dir.xz / (dir.y + 0.15) * 700.0);
        float star = step(0.9985, hash(stars)) * night * (1.0 - cloud) * smoothstep(0.1, 0.4, dir.y);
        COLOR += vec3(star * 0.7);
    }
}
