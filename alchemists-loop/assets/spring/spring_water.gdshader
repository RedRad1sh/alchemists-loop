shader_type canvas_item;

// §7.3: вода родника — это собственные пиксели спрайта, вырезанные в отдельный
// слой (см. _spring_anim/extract_water.py). Шейдер их только окрашивает в цвет
// выбранной стихии и оживляет, поэтому течение всегда сидит ровно на струе.

/// Цвет источника из существующей палитры игры.
uniform vec4 flow_color : source_color = vec4(0.37, 0.81, 0.94, 1.0);
/// Темп потока: 1.0 = базовые 6 с между тиками, быстрый родник — больше.
uniform float flow_speed: hint_range(0.0, 4.0) = 1.0;
/// Насколько заметны бегущие блики.
uniform float band_strength: hint_range(0.0, 0.6) = 0.16;

// Голубая краска, которой нарисована вода в исходных спрайтах.
const vec3 WATER_BASE = vec3(0.37, 0.81, 0.94);

void fragment() {
	vec2 uv = UV;
	// Волна по обеим осям: границы не рвём, берём цвет из смещённой точки того же слоя.
	uv.x += sin(uv.y * 26.0 + TIME * 2.2 * flow_speed) * 0.006;
	uv.y += sin(uv.x * 22.0 - TIME * 1.6 * flow_speed) * 0.004;
	vec4 c = texture(TEXTURE, uv);
	// Фрагментный процессор Godot не знает досрочных выходов: весь вывод —
	// одно присваивание COLOR в конце.
	if (c.a > 0.01) {
		c.rgb *= clamp(flow_color.rgb / WATER_BASE, vec3(0.0), vec3(3.0));
		// Блик бежит вниз по струе.
		c.rgb *= 1.0 + band_strength * sin((uv.y - TIME * 0.55 * flow_speed) * 42.0);
		float s = fract(sin(dot(floor(uv * 90.0), vec2(12.9898, 78.233)) + TIME * 3.0 * flow_speed) * 43758.5453);
		c.rgb += vec3(step(0.994, s) * 0.45);
	}
	COLOR = c;
}
