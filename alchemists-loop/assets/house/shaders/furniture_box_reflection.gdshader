// Reflection of the projected source sprite clipped inside the mirrored box.
shader_type spatial;
#include "res://assets/house/shaders/surface_grade.gdshaderinc"
render_mode unshaded, cull_disabled, blend_premul_alpha,
		shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D sprite_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 projection_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 alpha_rect_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_x = false;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float fade_power : hint_range(0.0, 6.0) = 0.0;
uniform float blur_mips : hint_range(0.0, 6.0) = 2.5;
// The same correction as the sprite itself, so the reflection of a graded variant
// is the reflection of the graded picture rather than of the raw one.
uniform vec4 grade = vec4(1.0, 1.0, 1.0, 0.0);
uniform float grade_alpha = 1.0;
uniform vec4 tint_color = vec4(1.0, 1.0, 1.0, 1.0);

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
		vec4 c = texture(sprite_tex, sample_uv, local_uv.y * blur_mips);
		float fade = 1.0;
		if (fade_power > 0.001) {
			fade = pow(clamp(local_uv.y, 0.0, 1.0), fade_power);
		}
		vec3 rgb = c.rgb;
		float a = c.a;
		if (abs(grade.x - 1.0) > 0.0001 || abs(grade.y - 1.0) > 0.0001
				|| abs(grade.z - 1.0) > 0.0001 || abs(grade.w) > 0.0001
				|| abs(grade_alpha - 1.0) > 0.0001) {
			rgb = _grade(rgb, grade.x, grade.y, grade.z, grade.w);
			a = clamp(a * grade_alpha, 0.0, 1.0);
		}
		rgb *= tint_color.rgb;
		a = clamp(a * tint_color.a, 0.0, 1.0);
		ALBEDO = rgb * a;
		ALPHA = a * opacity * fade;
	}
}
