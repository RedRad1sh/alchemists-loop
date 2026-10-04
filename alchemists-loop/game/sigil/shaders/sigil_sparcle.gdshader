shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.5;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(p, p);

	float horizontal = exp(
		-140.0 * p.y * p.y - 8.0 * p.x * p.x
	);
	float vertical = exp(
		-140.0 * p.x * p.x - 8.0 * p.y * p.y
	);

	float d1 = p.x + p.y;
	float d2 = p.x - p.y;
	float diagonals = (
		exp(-110.0 * d1 * d1)
		+ exp(-110.0 * d2 * d2)
	) * exp(-20.0 * r2);

	float core = exp(-55.0 * r2);
	float halo = exp(-7.0 * r2);

	float alpha = intensity * strength * (
		0.55 * core
		+ 0.30 * (horizontal + vertical)
		+ 0.10 * diagonals
		+ 0.08 * halo
	);

	float edge = 1.0 - smoothstep(
		0.78, 1.0, max(abs(p.x), abs(p.y))
	);

	vec3 color = mix(glow_color.rgb, vec3(1.0), core * 0.85);
	COLOR = vec4(color, clamp(alpha * edge, 0.0, 0.95));
}