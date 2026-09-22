shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Blender exports a separate skinned hull, expanded .003 source units and
// reversed. Extruding the flat surface normals here would split its edges.
uniform vec4 outline_color : source_color = vec4(0.086, 0.106, 0.143, 1.0);

void vertex() {
	// Keep the fine hull behind painted surfaces at tangencies and creases.
	vec4 view_vertex = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_vertex.z -= 0.008;
	POSITION = PROJECTION_MATRIX * view_vertex;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
