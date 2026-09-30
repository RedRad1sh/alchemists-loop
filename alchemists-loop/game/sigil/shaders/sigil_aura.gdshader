// Аура редкости: кольцевой ореол вокруг круга.
// uniform `pulse` намеренно НЕ связан со временем: в стилке он равен 0
// (детерминированный PNG), а в живой игре анимация может им управлять.

shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 center_uv = vec2(0.5, 0.42);
uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float ring_radius = 0.34;
uniform float ring_width = 0.010;
uniform float halo_width = 0.30;
uniform float intensity = 0.3;
uniform float pulse = 0.0;
uniform float sparkle = 0.35;
uniform float aspect = 0.727;
uniform float rays = 12.0;

void fragment() {
	vec2 d = (UV - center_uv) * vec2(aspect, 1.0);
	float r = length(d);
	float a = atan(d.y, d.x);

	float ring = smoothstep(ring_width, 0.0, abs(r - ring_radius));
	float halo = exp(-max(r - ring_radius, 0.0) / max(halo_width, 0.001) * 2.6);
	float inner = exp(-max(ring_radius - r, 0.0) / max(halo_width, 0.001) * 1.8) * 0.45;

	float rays_mod = 0.72 + 0.28 * sin(a * rays);
	rays_mod *= 0.78 + 0.22 * sin(a * rays * 2.37 + 1.1);
	float breakup = mix(1.0, rays_mod, sparkle * smoothstep(ring_radius * 0.65, ring_radius * 1.25, r));

	// Кольцо приглушено: иначе на тёмном фоне оно читается как неоновая
	// обруч и съедает круг. Основной вклад даёт гало.
	float amt = (ring * 0.55 + halo * 1.05 + inner) * intensity * breakup * (1.0 + pulse);
	amt *= smoothstep(0.0, 0.04, UV.x) * smoothstep(0.0, 0.04, 1.0 - UV.x);
	amt *= smoothstep(0.0, 0.04, UV.y) * smoothstep(0.0, 0.04, 1.0 - UV.y);

	COLOR = vec4(glow_color.rgb * amt, clamp(amt, 0.0, 1.0));
}
