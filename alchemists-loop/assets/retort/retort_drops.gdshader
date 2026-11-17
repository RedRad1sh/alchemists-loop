shader_type canvas_item;

uniform vec4 flow_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float flow_speed = 1.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float ang = atan(uv.y, uv.x) + TIME * flow_speed;
	float r = length(uv);
	float drops = smoothstep(0.02, 0.0, abs(fract(ang * 0.5) - 0.5) * r - 0.02);
	COLOR = vec4(flow_color.rgb, drops * flow_color.a * smoothstep(0.5, 0.2, r));
}
