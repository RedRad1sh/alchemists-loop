shader_type canvas_item;
render_mode blend_mix;

// Хромированный блик. Никакого TIME — phase снаружи, как у фольги.

uniform float phase = 0.0;
uniform float speed : hint_range(0.1, 3.0) = 0.8;
uniform float band_width : hint_range(0.05, 0.5) = 0.18;
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform float rainbow_shift : hint_range(0.0, 2.0) = 0.4;
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);

void fragment() {
	vec2 uv = UV;
	vec4 tex = texture(TEXTURE, uv);

	// phase уже крутится в скрипте; speed оставлен, чтобы не ломать
	// вызовы set_shader_parameter("speed", ...).
	float t = phase * speed;

	float diag = uv.x - uv.y * 0.5 + t * 0.3;
	float band = smoothstep(0.5 - band_width, 0.5, fract(diag))
			   * smoothstep(0.5 + band_width, 0.5, fract(diag));

	// Второй, более узкий фронт — «двойной блик» фольги.
	float diag2 = uv.x * 0.6 + uv.y * 0.8 - t * 0.17;
	float band2 = smoothstep(0.5 - band_width * 0.45, 0.5, fract(diag2))
				* smoothstep(0.5 + band_width * 0.45, 0.5, fract(diag2));
	band = max(band, band2 * 0.55);

	float rainbow = sin(diag * 12.0 + t * 2.0) * 0.5 + 0.5;
	vec3 chrome_color = mix(
		vec3(1.0, 0.95, 0.85),
		vec3(
			0.7 + 0.3 * sin(rainbow * 6.28 + rainbow_shift),
			0.7 + 0.3 * sin(rainbow * 6.28 + 2.094 + rainbow_shift),
			0.7 + 0.3 * sin(rainbow * 6.28 + 4.189 + rainbow_shift)
		),
		clamp(rainbow_shift, 0.0, 1.0)
	);

	float brightness = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float mask = smoothstep(0.3, 0.8, brightness) * band;

	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	mask *= smoothstep(0.0, 0.04, edge);

	vec3 result = mix(tex.rgb, chrome_color * tint.rgb, mask * intensity);
	COLOR = vec4(result, tex.a);
}