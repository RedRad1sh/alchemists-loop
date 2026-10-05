shader_type canvas_item;
// Текстура бумаги Аркана: пергамент с помятостями и желтизной по краям.
// Процедурная — без ассетов; два слоя value-noise дают крупные и мелкие
// складки, виньетка придаёт объём страницы.

uniform float paper_darkness : hint_range(0.0, 1.0) = 0.0;
uniform float crease_strength : hint_range(0.0, 2.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	// Крупные «волны» бумаги + мелкие помятости.
	float big = fbm(uv * 4.0 + vec2(1.7, 0.3));
	float small = fbm(uv * 18.0 + vec2(5.2, 2.1));
	float crease = big * 0.55 + small * 0.28;

	// Базовый пергамент: тёплый светлый тон с лёгким градиентом.
	vec3 base = vec3(0.855, 0.80, 0.66);
	base += vec3(0.05, 0.03, -0.02) * (uv.y - 0.5);      // градиент по вертикали
	base += vec3(0.02, 0.015, -0.01) * (uv.x - 0.5);     // лёгкий боковой свет

	// Помятости: тёмные и светлые складки.
	float crease_dark = smoothstep(0.55, 0.75, crease);
	float crease_light = smoothstep(0.75, 0.95, crease);
	vec3 tone = base
		- vec3(0.10, 0.09, 0.07) * crease_dark * crease_strength
		+ vec3(0.06, 0.05, 0.04) * crease_light * crease_strength;

	// Желтизна/потемнение у краёв (старая бумага).
	vec2 edge = smoothstep(0.0, 0.12, min(uv, 1.0 - uv));
	float vignette = edge.x * edge.y;
	tone = mix(tone * 0.82, tone, vignette);

	// Лёгкая зернистость (шумовое пятно).
	tone *= 0.98 + 0.04 * hash(uv * 137.0);

	vec3 col = tone * (1.0 - paper_darkness * 0.35);
	COLOR = vec4(col, 1.0);
}