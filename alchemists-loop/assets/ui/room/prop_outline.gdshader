shader_type canvas_item;
// Обводка по контуру предмета: тонкое кольцо сразу за силуэтом, найденное
// дилатацией альфы спрайта. Слой совпадает с rect спрайта, толщина задаётся
// в пикселях текстуры (SceneProps пересчитывает её в экранные px).
// breath — медленное «дыхание» яркости в покое: подсказывает, что предмет
// живой и кликабельный, но не двигает и не перекрашивает саму картинку.

const int SAMPLES = 24;

uniform vec4 outline_color : source_color = vec4(0.980, 0.839, 0.608, 1.0);
uniform float thickness : hint_range(0.0, 64.0) = 5.0;
uniform float breath : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;

void fragment() {
	float own = smoothstep(0.15, 0.6, texture(TEXTURE, UV).a);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * thickness;
	float ring = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		float a = float(i) * 6.2831853 / float(SAMPLES);
		vec2 dir = vec2(cos(a), sin(a));
		ring = max(ring, texture(TEXTURE, UV + dir * step_uv).a);
		ring = max(ring, texture(TEXTURE, UV + dir * step_uv * 0.5).a);
	}
	float edge = clamp(smoothstep(0.15, 0.6, ring) - own, 0.0, 1.0);
	float pulse = 1.0 - breath * (0.5 + 0.5 * sin(TIME * 2.2 + phase));
	COLOR = vec4(outline_color.rgb, outline_color.a * edge * pulse);
}
