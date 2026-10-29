shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_test_disabled,
		shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D sprite_tex : source_color, filter_linear, repeat_disable;
uniform vec4 projection_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 alpha_rect_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_x = false;
uniform vec4 tint = vec4(1.0);
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
		ALBEDO = c.rgb * c.a * tint.rgb;
		ALPHA = c.a * opacity;
	}
}
