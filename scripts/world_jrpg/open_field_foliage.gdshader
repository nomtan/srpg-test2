shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://scripts/world_jrpg/open_field_common.gdshaderinc"
// UV.x = wind weight (0 at the root). UV.y = 1 uses the authored vertex color
// (trees, flower heads); 0 tints by the shared meadow color with COLOR.r as shade.
uniform float sway = 0.3;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 origin;

void vertex() {
    origin = MODEL_MATRIX[3].xyz;
    float gust = sin(TIME * 1.25 + origin.x * 0.07 + origin.z * 0.05) * 0.65 + sin(TIME * 2.6 + origin.x * 0.4 + VERTEX.y * 0.8) * 0.3;
    VERTEX.x += gust * UV.x * sway;
    VERTEX.z += gust * UV.x * sway * 0.55;
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 color;
    if (UV.y > 0.5) {
        color = COLOR.rgb * (0.9 + 0.2 * of_hash(origin.xz));
    } else {
        color = of_grass(world_position.xz) * mix(0.62, 1.2, COLOR.r);
    }
    color = mix(color, vec3(0.92, 0.95, 0.98), snow_cover * smoothstep(0.3, 0.8, world_normal.y) * 0.75);
    color *= 1.0 - wetness * 0.18;
    ALBEDO = of_to_linear(color);
    ROUGHNESS = mix(0.85, 0.5, wetness);
    SPECULAR = 0.15;
    if (!FRONT_FACING) NORMAL = -NORMAL;
}
