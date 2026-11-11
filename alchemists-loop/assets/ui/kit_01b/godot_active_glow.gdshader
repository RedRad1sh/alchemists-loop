shader_type canvas_item;

// Готовый шейдер мягкого внешнего и внутреннего свечения активной кнопки для Godot 4.x
// Важно: у TextureButton / TextureRect включите небольшой запас прозрачных полей (или Region / Margin),
// либо положите дубликат текстуры под кнопку с этим шейдером и увеличенным scale (напр. 1.12).

uniform float active_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
uniform float glow_radius : hint_range(1.0, 16.0) = 6.0;
uniform float rim_boost : hint_range(0.0, 1.5) = 0.45;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (active_amount <= 0.001) {
		COLOR = base;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * glow_radius;
		float halo = 0.0;
		// 8-направленная выборка альфы для мягкого контурного свечения
		halo += texture(TEXTURE, UV + vec2( px.x,  0.0)).a;
		halo += texture(TEXTURE, UV + vec2(-px.x,  0.0)).a;
		halo += texture(TEXTURE, UV + vec2( 0.0,  px.y)).a;
		halo += texture(TEXTURE, UV + vec2( 0.0, -px.y)).a;
		halo += texture(TEXTURE, UV + vec2( px.x,  px.y) * 0.707).a;
		halo += texture(TEXTURE, UV + vec2(-px.x,  px.y) * 0.707).a;
		halo += texture(TEXTURE, UV + vec2( px.x, -px.y) * 0.707).a;
		halo += texture(TEXTURE, UV + vec2(-px.x, -px.y) * 0.707).a;
		halo /= 8.0;

		float outer_glow = clamp(halo * (1.0 - base.a) * 1.8, 0.0, 1.0) * active_amount;
		// Лёгкий тёплый отсвет по самой латунной кромке кнопки
		float inner_rim = clamp((1.0 - halo) * base.a * 2.2, 0.0, 1.0) * rim_boost * active_amount;

		vec3 lit_rgb = mix(base.rgb, glow_color.rgb, inner_rim);
		vec3 final_rgb = mix(glow_color.rgb, lit_rgb, base.a > 0.01 ? 1.0 : 0.0);
		float final_a = max(base.a, outer_glow * glow_color.a);

		COLOR = vec4(final_rgb, final_a);
	}
}
