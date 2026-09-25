shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D expression_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool expression_enabled = false;
uniform vec2 expression_uv_scale = vec2(1.0, 1.0);
uniform vec2 expression_uv_offset = vec2(0.0, 0.0);
uniform bool expression_projected = false;
uniform bool expression_pinned_uv2 = false;
uniform vec4 expression_face_rect = vec4(-0.23, 0.96, 0.46, 0.32);
uniform vec2 expression_atlas_offset = vec2(0.0, 0.0);
uniform vec2 expression_surface_depth = vec2(-1.0, 1.0);
uniform float expression_feature_scale = 1.0;
uniform float shadow_band = 0.68;
uniform float middle_band = 0.84;

// Reserved for future palette, expression, emblem, and gameplay effects.
// Keep per-surface ShaderMaterial instances so Head parameters can change independently.
varying vec3 expression_rest_position;
varying vec3 expression_rest_normal;

void vertex() {
	expression_rest_position = VERTEX;
	expression_rest_normal = NORMAL;
}

void fragment() {
	vec4 base = texture(base_color_texture, UV);
	if (expression_enabled) {
		vec2 feature_uv = UV * expression_uv_scale + expression_uv_offset;
		if (expression_projected) {
			feature_uv = expression_pinned_uv2 ? UV2 : vec2(
				(expression_rest_position.x - expression_face_rect.x) / expression_face_rect.z,
				1.0 - (expression_rest_position.y - expression_face_rect.y) / expression_face_rect.w
			);
			feature_uv = (feature_uv - vec2(0.5, 0.5)) / expression_feature_scale + vec2(0.5, 0.5);
		}
		bool face_surface = feature_uv.x >= 0.0 && feature_uv.x <= 1.0 && feature_uv.y >= 0.0 && feature_uv.y <= 1.0;
		face_surface = face_surface && (expression_pinned_uv2 || (expression_rest_normal.z > 0.15 && expression_rest_position.z >= expression_surface_depth.x && expression_rest_position.z <= expression_surface_depth.y));
		if (!expression_projected || face_surface) {
			vec2 sample_uv = expression_projected ? feature_uv * vec2(0.5, 0.5) + expression_atlas_offset : feature_uv;
			vec4 expression = texture(expression_texture, sample_uv);
			base.rgb = mix(base.rgb, expression.rgb, expression.a);
		}
	}
	ALBEDO = base.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = ALBEDO * shadow_band;
}

void light() {
	float energy = clamp(max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), LIGHT_COLOR.b) / PI, 0.0, 1.0);
	float illumination = max(dot(normalize(NORMAL), LIGHT), 0.0) * ATTENUATION * energy * (2.2 / PI) + 0.045;
	float band = illumination >= 0.60 ? 1.0 : (illumination >= 0.28 ? middle_band : shadow_band);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(band - shadow_band));
}
