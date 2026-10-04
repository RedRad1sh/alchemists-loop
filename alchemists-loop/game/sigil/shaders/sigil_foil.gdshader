shader_type canvas_item;
render_mode blend_mix;

// Фольга редких карточек. Порты python/sigil_finish.py:foil_layer.
//
// Никакого TIME: кадр запекается в PNG, и появление времени означало бы,
// что кэш перестаёт быть кэшем. Движение задаётся фазой от seed'а —
// у одного рецепта полоса всегда одна и та же, у разных лежит по-разному.

uniform vec4 tint : source_color = vec4(1.0);

uniform float strength = 0.0;
uniform float phase = 0.0;
uniform vec2 card_size = vec2(512.0, 1024.0);

float band_of(vec2 uv, float freq, float p) {
	return 0.5 + 0.5 * sin((uv.x * 1.7 + uv.y * 2.3) * freq + p);
}

// В Godot 4.3 нет встроенной hsv2rgb, поэтому разворот в RGB сделан
// вручную. Проверка компиляции скриптов шейдеры не ловит: они собираются
// лениво, при первой отрисовке, и падают уже в рантайме.
vec3 hsv2rgb_manual(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	// Заливка только полем картинки: полоса под подписью не идёт.
	vec2 uvn = UV;
	float edge = min(min(uvn.x, 1.0 - uvn.x), min(uvn.y, 1.0 - uvn.y));
	float mask = smoothstep(0.0, 0.32, edge);

	float band = pow(band_of(UV, 5.0, phase * 6.2831853), 1.4);
	float s2 = 0.5 + 0.5 * sin((UV.x * -0.9 + UV.y * 3.7) * 2.2 + phase * 4.1);
	band = band * 0.72 + pow(s2, 3.0) * 0.28;
	band = clamp(band * 0.80 + 0.20, 0.0, 1.0);

	float hue = band * 0.42 + phase;
	vec3 rainbow = hsv2rgb_manual(vec3(fract(hue), 0.62, 1.0));
	COLOR = vec4(rainbow * tint.rgb, clamp(band * mask * (0.52 * strength) * tint.a, 0.0, 1.0));
}
