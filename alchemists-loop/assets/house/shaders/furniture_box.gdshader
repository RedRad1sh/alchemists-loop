// View-projected texture clipped inside the fixed furniture bounding box.
shader_type spatial;
#include "res://assets/house/shaders/surface_grade.gdshaderinc"
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_test_disabled,
		shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D sprite_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 projection_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 alpha_rect_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_x = false;
// The sprite variant's own colour correction, straight from the .asset file:
// brightness, contrast, saturation, hue, plus a separate alpha multiplier so a
// sprite with translucent parts can be faded without touching its colour.
uniform vec4 grade = vec4(1.0, 1.0, 1.0, 0.0);
uniform float grade_alpha = 1.0;
uniform vec4 tint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float opacity = 1.0;

void fragment() {
	vec2 local_uv = (UV2 - projection_rect.xy) / projection_rect.zw;
	if (local_uv.x < 0.0 || local_uv.x > 1.0 || local_uv.y < 0.0 || local_uv.y > 1.0) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;
	} else {
		if (flip_x) {
			local_uv.x = 1.0 - local_uv.x;
		}
		vec2 sample_uv = mix(alpha_rect_uv.xy, alpha_rect_uv.zw, local_uv);
		vec4 c = texture(sprite_tex, sample_uv);
		vec3 rgb = c.rgb;
		float a = c.a;
		// At identity this is the same two lines the shader shipped with before
		// colour correction existed, so an ungraded asset costs nothing.
		if (abs(grade.x - 1.0) > 0.0001 || abs(grade.y - 1.0) > 0.0001
				|| abs(grade.z - 1.0) > 0.0001 || abs(grade.w) > 0.0001
				|| abs(grade_alpha - 1.0) > 0.0001) {
			rgb = _grade(rgb, grade.x, grade.y, grade.z, grade.w);
			a = clamp(a * grade_alpha, 0.0, 1.0);
		}
		rgb *= tint_color.rgb;
		a = clamp(a * tint_color.a * opacity, 0.0, 1.0);
		ALBEDO = rgb * a;
		ALPHA = a;
	}
}
