shader_type spatial;
render_mode specular_schlick_ggx;
// Dressed-stone masonry for JRPGWorldSample3's walls, towers and churches. Courses are laid
// in world space (running bond on walls, square flags on tops) and blended triplanar, so
// batched and rotated pieces keep continuous joints.
uniform vec4 stone : source_color = vec4(0.78, 0.76, 0.71, 1.0);
uniform vec4 mortar : source_color = vec4(0.56, 0.55, 0.51, 1.0);
// Block length and course height in meters.
uniform vec2 brick = vec2(1.2, 0.55);
uniform float variation = 0.14;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

float stone_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// One wall plane: u runs along the wall, v up; alternate courses shift half a block.
vec3 course(vec2 uv, vec2 size) {
    vec2 q = uv / size;
    float row = floor(q.y);
    q.x += mod(row, 2.0) * 0.5;
    vec2 cell = floor(q);
    vec2 f = fract(q);
    vec2 edge = min(f, 1.0 - f) * size;
    float joint = min(edge.x, edge.y);
    float h = stone_hash(cell);
    vec3 c = stone.rgb * (1.0 + (h - 0.5) * variation * 2.0);
    // A few warmer blocks break up the grey.
    c = mix(c, c * vec3(1.05, 1.0, 0.92), step(0.72, stone_hash(cell + 3.1)) * 0.6);
    // Chamfered edges read darker than the block faces.
    c *= mix(0.84, 1.0, smoothstep(0.0, 0.09, joint));
    return mix(mortar.rgb, c, smoothstep(0.022, 0.05, joint));
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 n = normalize(world_normal);
    vec3 w = pow(abs(n), vec3(4.0));
    w /= w.x + w.y + w.z;
    vec3 p = world_position;
    vec3 c = course(p.zy, brick) * w.x + course(p.xy, brick) * w.z + course(p.xz, vec2(brick.x, brick.x * 0.8)) * w.y;
    // Lake grime darkens the feet of the walls.
    c *= mix(0.86, 1.0, smoothstep(9.0, 15.0, p.y));
    float snow = clamp(snow_cover * 1.25, 0.0, 1.0) * smoothstep(0.6, 0.85, n.y);
    c = mix(c, vec3(0.93, 0.95, 0.98), snow);
    c *= 1.0 - wetness * 0.18;
    ALBEDO = c;
    ROUGHNESS = mix(0.92, 0.55, wetness);
}
