shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec2 card_size = vec2(512.0, 704.0);
uniform vec4 color_deep : source_color = vec4(0.03, 0.04, 0.07, 1.0);
uniform vec4 color_mid : source_color = vec4(0.10, 0.14, 0.24, 1.0);
uniform vec4 color_hot : source_color = vec4(0.35, 0.50, 0.78, 1.0);
uniform float noise_scale = 2.2;
uniform float warp_amount = 0.85;
uniform float phase = 0.0;
uniform float contrast = 1.0;
uniform float vignette = 0.45;
uniform float edge_softness = 0.18;
uniform float shape_amount = 0.55;
uniform float grain = 0.05;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n));
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(hash22(i) * 2.0 - 1.0, f);
	float b = dot(hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0, f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0, f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0, f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.45;
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) { break; }
		v += amp * gnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float aspect = card_size.x / max(card_size.y, 1.0);
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0) * noise_scale;

	vec2 q = vec2(fbm(p + vec2(phase, 0.0), 4),
				  fbm(p + vec2(0.0, phase) + 5.2, 4));
	vec2 r = vec2(fbm(p + warp_amount * q + vec2(1.7, 9.2) + phase * 0.5, 3),
				  fbm(p + warp_amount * q + vec2(8.3, 2.8) - phase * 0.5, 3));
	float f = fbm(p + warp_amount * r, 4);
	f = clamp(f * 0.5 + 0.5, 0.0, 1.0);

	float pool = smoothstep(0.30, 0.78, fbm(p * 0.5 + vec2(12.7, 4.1), 3) * 0.5 + 0.5);
	f = mix(f * 0.65, f, mix(1.0, pool, shape_amount));

	float t = pow(f, 1.0 / max(contrast, 0.05));
	vec3 col = mix(color_deep.rgb, color_mid.rgb, smoothstep(0.10, 0.62, t));
	col = mix(col, color_hot.rgb, smoothstep(0.56, 0.96, t) * (0.30 + 0.55 * (r.x * 0.5 + 0.5)));

	// Гребень: узкая жилка на переходе mid→hot. Не заливает поле.
	float ridge = smoothstep(0.52, 0.62, t) * (1.0 - smoothstep(0.66, 0.78, t));
	col += color_hot.rgb * ridge * 0.18 * (0.5 + 0.5 * r.y);

	// Шелк: едва заметная модуляция, среднее = 1.
	col *= 0.96 + 0.08 * (r.y * 0.5 + 0.5);

	float d = length((UV - vec2(0.5)) * vec2(aspect, 1.0));
	col *= mix(1.0, smoothstep(0.92, 0.26, d), vignette);

	float ex = min(min(UV.x, 1.0 - UV.x) * card_size.x, min(UV.y, 1.0 - UV.y) * card_size.y);
	float edge = smoothstep(0.0, max(edge_softness, 0.001) * 56.0, ex);
	col = mix(color_deep.rgb * 0.55, col, edge);

	col += (hash21(UV * card_size) - 0.5) * grain;

	COLOR = vec4(col, 1.0);
}