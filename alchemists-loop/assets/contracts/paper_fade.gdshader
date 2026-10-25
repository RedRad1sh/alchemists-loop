shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// COLOR.rgb — вершинный цвет элемента: для текста это цвет шрифта, а в
	// фонтанном атласе глифы белые. Без перемножения шейдер возвращал атлас
	// как есть, и подпись под «выжженной» бумагой становилась белой.
	COLOR = vec4(mix(c.rgb, vec3(luma), amount) * COLOR.rgb, c.a * COLOR.a);
}
