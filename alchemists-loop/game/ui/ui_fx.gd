class_name UIFx
extends RefCounted
# Фоновые эффекты на шейдерах: ноль draw-вызовов на CPU, дёшево на мобильных.

const AMBIENT_CODE := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(540.0, 960.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float aspect = rect_size.x / rect_size.y;
	// COLOR = цвет ColorRect (тема дома меняет его — шейдер подхватывает).
	vec3 base = COLOR.rgb;
	vec3 col = mix(base * 1.55 + vec3(0.010, 0.020, 0.030), base * 0.45, smoothstep(0.0, 1.0, uv.y));
	// холодное свечение сверху-слева
	vec2 c1 = vec2(0.18 + 0.06 * sin(TIME * 0.11), 0.12);
	col += vec3(0.10, 0.42, 0.42) * exp(-length((uv - c1) * vec2(aspect, 1.0)) * 3.4) * 0.35;
	// тёплый отсвет очага снизу
	vec2 c2 = vec2(0.5, 1.02);
	col += vec3(0.60, 0.30, 0.10) * exp(-length((uv - c2) * vec2(aspect, 1.0)) * 3.0) * 0.22 * (0.92 + 0.08 * sin(TIME * 1.7));
	// парящие искорки
	vec2 q = vec2(uv.x * aspect, uv.y) * 16.0 + vec2(0.0, TIME * 0.35);
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float r = hash(id);
	vec2 off = (vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5) * 0.6;
	float tw = 0.5 + 0.5 * sin(TIME * 1.5 + r * 6.2831);
	float m = (1.0 - smoothstep(0.0, 0.07, length(f - off))) * step(0.85, r) * tw;
	col += vec3(0.60, 0.95, 0.95) * m * 0.35;
	// виньетка и зерно против бандинга
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	col += (hash(FRAGCOORD.xy + fract(TIME) * 100.0) - 0.5) * 0.015;
	COLOR = vec4(col, 1.0);
}
"""

const FIELD_CODE := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(540.0, 700.0);
uniform vec2 center_offset_px = vec2(0.0, 23.0);
uniform vec4 accent : source_color = vec4(0.37, 0.89, 0.84, 1.0);

void fragment() {
	vec2 p = UV * rect_size - (rect_size * 0.5 + center_offset_px);
	float r = length(p);
	float ang = atan(p.y, p.x);
	// точечная сетка, ярче у центра
	vec2 g = (fract((p + 14.0) / 28.0) - 0.5) * 28.0;
	float dots = 1.0 - smoothstep(0.5, 1.5, length(g));
	float fade = 0.30 + 0.70 * exp(-r / 240.0);
	float a = dots * 0.10 * fade;
	float spin = TIME * 0.12;
	// пунктирное кольцо
	float dash = smoothstep(-0.15, 0.15, sin((ang + spin) * 18.0));
	a += (1.0 - smoothstep(0.0, 1.3, abs(r - 150.0))) * (0.10 + 0.14 * dash);
	// внешнее тонкое кольцо
	a += (1.0 - smoothstep(0.0, 1.0, abs(r - 184.0))) * 0.10;
	// риски между кольцами
	float k = fract((ang - spin * 0.6) * 24.0 / 6.2831853);
	float tick = 1.0 - smoothstep(0.0, 0.05, min(k, 1.0 - k));
	a += tick * (1.0 - smoothstep(0.0, 5.0, abs(r - 166.0))) * 0.20;
	// дыхание вокруг котла
	a += exp(-abs(r - 150.0) / 26.0) * 0.045 * (0.75 + 0.25 * sin(TIME * 1.2));
	COLOR = vec4(accent.rgb, clamp(a, 0.0, 0.6));
}
"""

static var _ambient_shader: Shader = null
static var _field_shader: Shader = null


static func _get_shader(kind: String) -> Shader:
	if kind == "ambient":
		if _ambient_shader == null:
			_ambient_shader = Shader.new()
			_ambient_shader.code = AMBIENT_CODE
		return _ambient_shader
	if _field_shader == null:
		_field_shader = Shader.new()
		_field_shader.code = FIELD_CODE
	return _field_shader


## Живой фон поверх ColorRect (его color используется как базовый тон).
static func ambient_bg(rect: ColorRect) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader("ambient")
	rect.material = mat
	var upd := func() -> void:
		mat.set_shader_parameter("rect_size", rect.size)
	rect.resized.connect(upd)
	upd.call()


## Руническое поле под котлом. Добавляется первым ребёнком — рисуется под всем.
static func field_decor(parent: Control, center_offset: Vector2 = Vector2(0, 23)) -> ColorRect:
	var r := ColorRect.new()
	r.name = "FieldDecor"
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader("field")
	mat.set_shader_parameter("center_offset_px", center_offset)
	r.material = mat
	parent.add_child(r)
	parent.move_child(r, 0)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var upd := func() -> void:
		mat.set_shader_parameter("rect_size", r.size)
	r.resized.connect(upd)
	upd.call()
	return r
