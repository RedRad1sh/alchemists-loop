shader_type canvas_item;

## Хромированный блик для легендарных/мифических карточек.
## Накладывается поверх карточки как overlay. Анимированный металлический
## отлив: диагональная полоса бежит по карте, оставляя за собой радужный
## след. Параметры управляются uniform'ами из GDScript.

uniform float speed : hint_range(0.1, 3.0) = 0.8;
uniform float band_width : hint_range(0.05, 0.5) = 0.18;
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform float rainbow_shift : hint_range(0.0, 2.0) = 0.4;
uniform vec4 tint : hint_color = vec4(1.0, 0.95, 0.85, 1.0);

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;

	// Диагональная полоса: движется слева-снизу направо-вверх.
	float diag = uv.x - uv.y * 0.5 + t * 0.3;
	float band = smoothstep(0.5 - band_width, 0.5, diag) * smoothstep(0.5 + band_width, 0.5, diag);

	// Радужный сдвиг по нормали к полосе.
	float rainbow = sin(diag * 12.0 + t * 2.0) * 0.5 + 0.5;
	vec3 chrome_color = mix(
		vec3(1.0, 0.95, 0.85),
		vec3(
			0.7 + 0.3 * sin(rainbow * 6.28 + rainbow_shift),
			0.7 + 0.3 * sin(rainbow * 6.28 + 2.094 + rainbow_shift),
			0.7 + 0.3 * sin(rainbow * 6.28 + 4.189 + rainbow_shift)
		),
		rainbow_shift
	);

	// Маска: только яркие участки текстуры (блик на светлом).
	float brightness = dot(TEXTURE_PIXEL.rgb, vec3(0.299, 0.587, 0.114));
	float mask = smoothstep(0.3, 0.8, brightness) * band;

	vec3 base = texture(TEXTURE, uv).rgb;
	vec3 result = mix(base, chrome_color * tint.rgb, mask * intensity);

	COLOR = vec4(result, texture(TEXTURE, uv).a);
}
