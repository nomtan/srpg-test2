// Autotile-style dirt intrusion applied directly to a grass top. Neighbor
// flags come from VoxelMap, while world XZ keeps the mask aligned to the tile
// regardless of the imported mesh UV orientation.
uniform bool grass_dirt_boundary_enabled = false;
uniform vec3 grass_dirt_color : source_color = vec3(0.55, 0.40, 0.22);
uniform float grass_dirt_boundary_width : hint_range(0.04, 0.40) = 0.18;
uniform float grass_dirt_tile_size : hint_range(0.1, 4.0) = 0.2;
uniform float grass_dirt_hue_jitter : hint_range(0.0, 0.15) = 0.01;
uniform float grass_dirt_sat_jitter : hint_range(0.0, 0.3) = 0.11;
uniform float grass_dirt_val_jitter : hint_range(0.0, 0.1) = 0.06;
uniform bool grass_dirt_edge_n = false;
uniform bool grass_dirt_edge_e = false;
uniform bool grass_dirt_edge_s = false;
uniform bool grass_dirt_edge_w = false;
uniform bool grass_dirt_corner_ne = false;
uniform bool grass_dirt_corner_se = false;
uniform bool grass_dirt_corner_sw = false;
uniform bool grass_dirt_corner_nw = false;

float grass_boundary_hash(float value, float salt, vec2 tile_id) {
    float tile_salt = dot(tile_id, vec2(17.13, 41.71));
    return fract(sin(value * 91.17 + salt * 37.31 + tile_salt) * 43758.5453);
}

float grass_boundary_depth(float coordinate, float salt, vec2 tile_id) {
    float pixel = floor(coordinate * 32.0);
    float wobble = (grass_boundary_hash(pixel, salt, tile_id) - 0.5) * 0.09;
    return clamp(grass_dirt_boundary_width + wobble, 0.03, 0.44);
}

float grass_boundary_corner(vec2 from_corner, float salt, vec2 tile_id) {
    vec2 pixel_uv = floor(from_corner * 32.0) / 32.0;
    float wobble = (
        grass_boundary_hash(pixel_uv.x * 32.0 + pixel_uv.y * 71.0, salt, tile_id)
        - 0.5
    ) * 0.06;
    return 1.0 - step(
        grass_dirt_boundary_width * 1.25 + wobble,
        length(pixel_uv)
    );
}

float grass_dirt_boundary_mask(vec3 world_position) {
    if (!grass_dirt_boundary_enabled) {
        return 0.0;
    }

    vec2 tile_id = floor(world_position.xz + vec2(0.0001));
    vec2 local_uv = fract(world_position.xz + vec2(0.0001));
    vec2 uv = floor(local_uv * 32.0) / 32.0;
    float mask = 0.0;

    if (grass_dirt_edge_n) {
        mask = max(mask, 1.0 - step(
            grass_boundary_depth(uv.x, 1.0, tile_id),
            uv.y
        ));
    }
    if (grass_dirt_edge_s) {
        mask = max(mask, step(
            1.0 - grass_boundary_depth(uv.x, 2.0, tile_id),
            uv.y
        ));
    }
    if (grass_dirt_edge_w) {
        mask = max(mask, 1.0 - step(
            grass_boundary_depth(uv.y, 3.0, tile_id),
            uv.x
        ));
    }
    if (grass_dirt_edge_e) {
        mask = max(mask, step(
            1.0 - grass_boundary_depth(uv.y, 4.0, tile_id),
            uv.x
        ));
    }

    if (grass_dirt_corner_nw) {
        mask = max(mask, grass_boundary_corner(uv, 5.0, tile_id));
    }
    if (grass_dirt_corner_ne) {
        mask = max(mask, grass_boundary_corner(
            vec2(1.0 - uv.x, uv.y), 6.0, tile_id
        ));
    }
    if (grass_dirt_corner_se) {
        mask = max(mask, grass_boundary_corner(
            vec2(1.0 - uv.x, 1.0 - uv.y), 7.0, tile_id
        ));
    }
    if (grass_dirt_corner_sw) {
        mask = max(mask, grass_boundary_corner(
            vec2(uv.x, 1.0 - uv.y), 8.0, tile_id
        ));
    }

    return mask;
}

vec3 grass_dirt_boundary_color(vec3 world_position) {
    vec2 dirt_tile_id = floor(
        world_position.xz / max(grass_dirt_tile_size, 0.001)
    );
    float h1 = hash21(dirt_tile_id);
    float h2 = hash21(dirt_tile_id + vec2(37.0, 91.0));
    float h3 = hash21(dirt_tile_id + vec2(11.0, 53.0));
    vec3 hsv = rgb2hsv(grass_dirt_color);
    hsv.x = fract(hsv.x + (h1 - 0.5) * 2.0 * grass_dirt_hue_jitter);
    hsv.y = clamp(
        hsv.y * (1.0 + (h2 - 0.5) * 2.0 * grass_dirt_sat_jitter),
        0.0,
        1.0
    );
    hsv.z = clamp(
        hsv.z * (1.0 + (h3 - 0.5) * 2.0 * grass_dirt_val_jitter),
        0.0,
        1.0
    );
    return hsv2rgb(hsv);
}
