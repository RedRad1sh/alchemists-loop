class_name BookPager
extends Control
## Книга для мобильной (портретной) ориентации.
##  - open_book()  : обложка откидывается, открывая страницу
##  - add_page()   : страница = любой Control, сверху появляется вкладка
##  - go_to(i)     : переход перелистыванием (лист вращается вокруг корешка)
##  - свайп от левого/правого края страницы листает так же
##  - close_book() : обложка закрывается
##
## Лист: снимок страницы (viewport -> ImageTexture) на TextureRect с
## шейдером, который вращает квад вокруг левого края с перспективой.

signal flipped(from_index: int, to_index: int)
signal close_requested

const INTRO_TIME := 1.3        # когда содержимое книги готово (для задержек интро)
const FLIP_TIME := 0.55
const OPEN_TIME := 0.85
const TAB_H := 48.0
const EDGE_ZONE := 36.0        # зона свайпа у края страницы, px
const SWIPE_MIN := 90.0
const HALF_PI := PI * 0.5

const LEAF_SHADER := """
shader_type canvas_item;

uniform float angle = 0.0;                 // 0 — лежит, PI/2 — ребром к зрителю
uniform vec2 leaf_size = vec2(600.0, 900.0);
uniform float cam_dist = 4.0;              // дистанция камеры в ширинах листа
uniform int mode = 0;                      // 0 — текстура страницы, 1 — обложка
uniform vec3 accent : source_color = vec3(0.85, 0.72, 0.42);
uniform vec3 base : source_color = vec3(0.16, 0.09, 0.07);

varying float shade;

void vertex() {
	float u = UV.x;
	float s = 1.0 / (1.0 - u * sin(angle) / cam_dist);
	VERTEX.x = u * leaf_size.x * cos(angle) * s;
	VERTEX.y = leaf_size.y * 0.5 + (UV.y - 0.5) * leaf_size.y * s;
	shade = 1.0 - 0.45 * sin(angle) * (0.3 + 0.7 * u);
}

vec3 cover_col(vec2 uv) {
	vec2 p = uv * leaf_size;
	vec2 e = min(p, leaf_size - p);
	float edge = min(e.x, e.y);
	float g = fract(sin(dot(floor(p * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 col = base * (0.85 + 0.3 * uv.y) * (0.94 + 0.12 * g);
	float l1 = 1.0 - smoothstep(0.0, 1.2, abs(edge - 22.0));
	float l2 = 1.0 - smoothstep(0.0, 0.8, abs(edge - 28.0));
	vec2 c = p - leaf_size * 0.5;
	float r = length(c);
	float ring = 1.0 - smoothstep(0.0, 1.4, abs(r - 96.0));
	float ring2 = 1.0 - smoothstep(0.0, 1.0, abs(r - 80.0));
	float ticks = step(0.82, fract(atan(c.y, c.x) / TAU * 16.0)) * step(96.0, r) * step(r, 108.0);
	float gold = clamp(l1 + l2 * 0.6 + ring + ring2 * 0.6 + ticks, 0.0, 1.0);
	col = mix(col, accent, gold * 0.9);
	col *= 0.75 + 0.25 * smoothstep(0.0, 0.08, uv.x);   // корешок темнее
	return col;
}

void fragment() {
	vec4 c = (mode == 0) ? texture(TEXTURE, UV) : vec4(cover_col(UV), 1.0);
	COLOR = vec4(c.rgb * shade, c.a);
}
"""

var accent := Color(0.85, 0.72, 0.42)
var cover_color := Color(0.16, 0.09, 0.07)
var page_color := Color(0.055, 0.055, 0.095)
var current := 0
var busy := false

var _pages: Array[Control] = []
var _tab_btns: Array[Button] = []
var _frame: Panel
var _paper: Panel
var _content: Control
var _tabs: HBoxContainer
var _holder: Control
var _cast: TextureRect
var _shield: Control
var _close_btn: Button
var _white: ImageTexture
var _leaf_shader: Shader
var _swipe_from := Vector2.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_leaf_shader = Shader.new()
	_leaf_shader.code = LEAF_SHADER
	var im := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	im.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(im)

	# --- Обложка (внешний корпус книги) ---
	_frame = Panel.new()
	_frame.name = "Cover"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fs := StyleBoxFlat.new()
	fs.bg_color = cover_color
	fs.set_corner_radius_all(14)
	fs.set_border_width_all(2)
	fs.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 26
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.draw.connect(_draw_page_edges)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# --- Бумага страниц ---
	_paper = Panel.new()
	_paper.name = "Paper"
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.offset_left = 16.0
	_paper.offset_top = 10.0
	_paper.offset_right = -10.0
	_paper.offset_bottom = -10.0
	var ps := StyleBoxFlat.new()
	ps.bg_color = page_color
	ps.set_corner_radius_all(6)
	ps.set_border_width_all(1)
	ps.border_color = Color(accent.r, accent.g, accent.b, 0.28)
	_paper.add_theme_stylebox_override("panel", ps)
	_paper.clip_contents = true
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper)

	# Тень у корешка
	var spine := TextureRect.new()
	spine.texture = _edge_tex()
	spine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spine.stretch_mode = TextureRect.STRETCH_SCALE
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spine.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	spine.offset_right = 34.0
	_paper.add_child(spine)

	# --- Содержимое: вкладки + поле страниц ---
	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.add_child(_content)

	_holder = Control.new()
	_holder.name = "PageHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.offset_top = TAB_H
	_holder.clip_contents = true
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_holder)

	# Тень, которую отбрасывает поднятый лист на открывающуюся страницу
	_cast = TextureRect.new()
	_cast.texture = _edge_tex()
	_cast.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cast.stretch_mode = TextureRect.STRETCH_SCALE
	_cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_cast.offset_top = TAB_H
	_cast.offset_right = 150.0
	_cast.modulate.a = 0.0
	_content.add_child(_cast)

	_tabs = HBoxContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = 18.0
	_tabs.offset_right = -6.0
	_tabs.offset_top = 4.0
	_tabs.offset_bottom = TAB_H
	_tabs.add_theme_constant_override("separation", 2)
	_content.add_child(_tabs)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.flat = true
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.custom_minimum_size = Vector2(44, 0)
	_close_btn.add_theme_font_size_override("font_size", 18)
	_close_btn.pressed.connect(func() -> void: close_requested.emit())
	_tabs.add_child(_close_btn)

	# Щит: блокирует ввод на время анимаций
	_shield = Control.new()
	_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_shield.visible = false
	add_child(_shield)


## Добавляет страницу и вкладку. Возвращает индекс страницы.
func add_page(title: String, page: Control) -> int:
	assert(_holder != null, "BookPager: сначала add_child(book) в дерево")
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = _pages.is_empty()
	_holder.add_child(page)
	var idx := _pages.size()
	_pages.append(page)

	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func() -> void: go_to(idx))
	_tabs.add_child(b)
	_tabs.move_child(b, idx)          # перед кнопкой «✕»
	_tab_btns.append(b)
	_refresh_tabs(current)
	return idx


func go_next() -> void:
	go_to(current + 1)


func go_prev() -> void:
	go_to(current - 1)


# ------------------------------------------------------------ перелистывание

func go_to(idx: int) -> void:
	if busy or idx == current or idx < 0 or idx >= _pages.size():
		return
	busy = true
	_shield.visible = true
	var from_i := current
	var forward := idx > from_i
	_refresh_tabs(idx)

	# Вперёд — лист несёт уходящую страницу, назад — приходящую.
	var tex: ImageTexture = await _snapshot(_pages[from_i] if forward else _pages[idx])
	var leaf := _make_leaf(tex, _holder.global_position - global_position, _holder.size, 0)
	var a0 := 0.0 if forward else HALF_PI
	var a1 := HALF_PI if forward else 0.0
	_set_leaf_angle(a0, leaf)
	if forward:
		_pages[from_i].visible = false   # под листом уже новая страница
		_pages[idx].visible = true

	var tw := create_tween()
	tw.tween_method(_set_leaf_angle.bind(leaf), a0, a1, FLIP_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished

	_pages[from_i].visible = false
	_pages[idx].visible = true
	leaf.queue_free()
	_cast.modulate.a = 0.0
	current = idx
	busy = false
	_shield.visible = false
	flipped.emit(from_i, idx)


## Снимок страницы с экрана. Остальные страницы на кадр скрываются.
func _snapshot(page: Control) -> ImageTexture:
	var states: Array[bool] = []
	for p in _pages:
		states.append(p.visible)
		p.visible = (p == page)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var vp := get_viewport().get_visible_rect().size
	var k := Vector2(img.get_size()) / vp
	var rect := Rect2i(Vector2i((_holder.global_position * k).round()),
		Vector2i((_holder.size * k).round()))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var tex := ImageTexture.create_from_image(img.get_region(rect))
	for i in _pages.size():
		_pages[i].visible = states[i]
	return tex


func _make_leaf(tex: Texture2D, pos: Vector2, sz: Vector2, mode: int) -> TextureRect:
	var leaf := TextureRect.new()
	leaf.texture = tex
	leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	leaf.stretch_mode = TextureRect.STRETCH_SCALE
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaf.position = pos
	leaf.size = sz
	var m := ShaderMaterial.new()
	m.shader = _leaf_shader
	m.set_shader_parameter("leaf_size", sz)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("accent", Vector3(accent.r, accent.g, accent.b))
	m.set_shader_parameter("base", Vector3(cover_color.r, cover_color.g, cover_color.b))
	leaf.material = m
	add_child(leaf)
	return leaf


func _set_leaf_angle(a: float, leaf: TextureRect) -> void:
	if not is_instance_valid(leaf):
		return
	(leaf.material as ShaderMaterial).set_shader_parameter("angle", a)
	_cast.modulate.a = 0.45 * sin(a * 2.0)   # пик на 45°, 0 на концах


# ---------------------------------------------------------- открытие/закрытие

func open_book() -> void:
	busy = true
	_shield.visible = true
	_content.modulate.a = 0.0
	modulate.a = 0.0
	await get_tree().process_frame            # дождаться layout (нужен size)
	pivot_offset = size * 0.5
	scale = Vector2(0.9, 0.9)
	var cover := _make_leaf(_white, Vector2.ZERO, size, 1)
	_set_leaf_angle(0.0, cover)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.tween_property(self, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

	var t2 := create_tween()
	t2.tween_method(_set_leaf_angle.bind(cover), 0.0, HALF_PI, OPEN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t2.finished
	cover.queue_free()
	var t3 := create_tween()
	t3.tween_property(_content, "modulate:a", 1.0, 0.3)
	await t3.finished
	busy = false
	_shield.visible = false


func close_book() -> void:
	busy = true
	_shield.visible = true
	var cover := _make_leaf(_white, Vector2.ZERO, size, 1)
	_set_leaf_angle(HALF_PI, cover)
	var tw := create_tween()
	tw.tween_property(_content, "modulate:a", 0.0, 0.18)
	tw.tween_method(_set_leaf_angle.bind(cover), HALF_PI, 0.0, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	await tw.finished


# ------------------------------------------------------------------- свайп

func _input(event: InputEvent) -> void:
	if busy or not is_visible_in_tree():
		_swipe_from = Vector2.INF
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.global_position
		if event.pressed:
			var r := _holder.get_global_rect()
			if r.has_point(p) and (p.x - r.position.x < EDGE_ZONE or r.end.x - p.x < EDGE_ZONE):
				_swipe_from = p
		elif _swipe_from != Vector2.INF:
			var dx := p.x - _swipe_from.x
			_swipe_from = Vector2.INF
			if absf(dx) > SWIPE_MIN:
				go_to(current + (1 if dx < 0.0 else -1))


# ---------------------------------------------------------------- оформление

func _refresh_tabs(active: int) -> void:
	for i in _tab_btns.size():
		var b := _tab_btns[i]
		var st := _tab_style(i == active)
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, st)
		var col := accent if i == active else Color(0.75, 0.75, 0.8, 0.75)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, col)


func _tab_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.10 if selected else 0.0)
	sb.border_width_bottom = 3
	sb.border_color = accent if selected else Color(accent.r, accent.g, accent.b, 0.0)
	sb.set_content_margin_all(6)
	return sb


func _edge_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.6))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.0, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 4
	return t


## «Торцы» страниц: тонкие линии справа и снизу между бумагой и обложкой.
func _draw_page_edges() -> void:
	var s := _frame.size
	var col := Color(0.82, 0.76, 0.6, 0.35)
	for i in 3:
		var o := float(i) * 2.5
		_frame.draw_line(Vector2(s.x - 8.0 + o, 20.0), Vector2(s.x - 8.0 + o, s.y - 20.0), col, 1.0)
		_frame.draw_line(Vector2(24.0, s.y - 8.0 + o), Vector2(s.x - 20.0, s.y - 8.0 + o), col, 1.0)
