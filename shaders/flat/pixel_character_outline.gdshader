shader_type spatial;
render_mode unshaded, cull_front;

uniform vec3 outline_color : source_color = vec3(0.025, 0.020, 0.030);
uniform float outline_width : hint_range(0.0, 0.05, 0.001) = 0.025;

void vertex() {
    VERTEX += NORMAL * outline_width;
}

void fragment() {
    ALBEDO = outline_color;
}
