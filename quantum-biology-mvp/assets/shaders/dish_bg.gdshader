shader_type canvas_item;
// Фон «тёмная вода лаборатории»: живые каустики + верхний свет + виньетка.
// Без текстур — чистые вычисления по UV и TIME.

uniform vec4 base_col : source_color = vec4(0.028, 0.075, 0.09, 1.0);
uniform vec4 caustic_col : source_color = vec4(0.10, 0.34, 0.30, 1.0);
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;
uniform float time_scale : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;

	// --- базовая вода + крупные пятна света (каустики-«паутина») ---
	float c1 = sin(uv.x * 26.0 + t * 1.4) * 0.5 + 0.5;
	float c2 = sin(uv.y * 21.0 - t * 1.1) * 0.5 + 0.5;
	float c3 = sin((uv.x + uv.y) * 15.0 + t * 0.7) * 0.5 + 0.5;
	float web = smoothstep(0.45, 0.95, c1 * c2 * c3);

	// --- медленные «дышащие» пятна света ---
	float b1 = 0.5 + 0.5 * sin(distance(uv, vec2(0.5, 0.55)) * 6.0 - t * 0.5);
	float b2 = 0.5 + 0.5 * sin(distance(uv, vec2(0.62, 0.38)) * 9.0 + t * 0.35);
	float spots = clamp((b1 + b2) * 0.5, 0.0, 1.0);

	vec3 col = base_col.rgb;
	col += caustic_col.rgb * (web * caustic_strength * 0.6);
	col += caustic_col.rgb * (spots * caustic_strength * 0.22);

	// --- верхний «прожектор» над существом ---
	float dtop = distance(uv, vec2(0.5, 0.42));
	float pool = smoothstep(0.5, 0.0, dtop);
	col += vec3(0.06, 0.17, 0.15) * pool * 0.5;

	// --- виньетка (углы темнее) ---
	float d = distance(uv, vec2(0.5, 0.55));
	float vig = smoothstep(0.25, 0.85, d);
	col *= 1.0 - vig * vignette_strength;

	// --- едва заметное зерно ---
	float grain = fract(sin(dot(uv * 900.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (grain - 0.5) * 0.012;

	COLOR = vec4(col, 1.0);
}
