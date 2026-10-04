class_name SigilCraftBoard
extends Control
## Экран крафта «Трансмуция» — вся вёрстка и взаимодействие в одном классе.
##
## Спека (2026-10-03, голос пользователя):
##   1. Полноэкранная страница (не модалка-панель), тёмный фон, поверх вкладок.
##   2. Круг трансмутации по центру (рендер рецепта, ~340px).
##   3. Ячейки на круге: полупрозрачные, по одной на ТИП ингредиента, внутри
##      фантомный (тусклый) орб нужного элемента — видно, что куда класть.
##   4. Элементы вокруг на свободном поле: лежат свободно, можно перекладывать
##      (бросил в пустое место — остались там), можно на ячейку.
##   5. Дроп на свою ячейку -> ячейка загорается. ОДИН перенос = элемент
##      размещён (количество — формальность, серверу уходит полный рецепт).
##   6. Тап по орбу = быстрый путь: сразу в свою ячейку.
##   7. Кнопка «НАЧАТЬ ТРАНСМУТАЦИЮ» внизу, активна, когда все ячейки полны.
##   8. Драг — механика эксперимента: ghost в корне сцены (z=100), отпускание
##      ловится глобально (_input), дроп по глобальным rect ячеек.
##
## Правки только здесь: main.gd вызывает show_craft() и слушает confirmed.

signal confirmed(craft: Dictionary)
signal closed

const ORB_SIZE := 56
const GHOST_SIZE := 62
const CELL_SIZE := 64
const CELL_RADIUS := 150.0   # радиус окружности ячеек от центра круга
const ORB_RADIUS := 220.0    # радиус, на котором лежат свободные орбы

## Фоновый шейдер: градиент + акцентное «дыхание» от центра + виньетка
## + два слоя дрейфующих пылинок. Процедурно, без текстур.
const BG_SHADER := """
shader_type canvas_item;

uniform vec3 col_top : source_color = vec3(0.05, 0.05, 0.09);
uniform vec3 col_bottom : source_color = vec3(0.012, 0.012, 0.03);
uniform vec3 accent : source_color = vec3(0.85, 0.72, 0.42);
uniform float aspect = 1.6;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(col_top, col_bottom, clamp(uv.y * 1.2 - 0.08, 0.0, 1.0));
	vec2 d = uv - vec2(0.5, 0.46);
	d.x *= aspect;
	float dist = length(d);
	float breath = 0.72 + 0.28 * sin(TIME * 0.55);
	col += accent * exp(-dist * dist * 9.0) * 0.15 * breath;
	col += accent * exp(-dist * dist * 2.2) * 0.05 * breath;
	float vig = 1.0 - smoothstep(0.3, 1.05, dist);
	col *= mix(0.5, 1.0, vig);
	for (int L = 0; L < 2; L++) {
		float fl = float(L);
		vec2 gp = (uv - vec2(0.5)) * vec2(aspect, 1.0) * (11.0 + fl * 9.0)
			+ vec2(0.0, TIME * (0.05 + fl * 0.035));
		vec2 id = floor(gp);
		vec2 f = fract(gp) - 0.5;
		float h = hash21(id + fl * 17.0);
		vec2 off = vec2(hash21(id + 3.7 + fl * 5.0), hash21(id + 9.1 + fl * 3.0)) - 0.5;
		float star = 1.0 - smoothstep(0.0, 0.06, length(f - off * 0.55));
		float tw = 0.35 + 0.65 * sin(TIME * (0.8 + h * 2.2) + h * 6.2831);
		col += vec3(0.85, 0.9, 1.0) * star * step(0.8, h) * max(tw, 0.0) * 0.4;
	}
	COLOR = vec4(col, 0.985);
}
"""

var craft: Dictionary = {}
var _accent := Color(0.85, 0.72, 0.42)
var _game: Node = null
var _orbs: Dictionary = {}          # elem_id -> ElementOrb (свободные на поле)
var _cells: Dictionary = {}         # elem_id -> Control (ячейка на круге)
var _placed: Dictionary = {}        # elem_id -> true (размещён)
var _ghost: ElementOrb = null
var _drag_id := ""
var _drag_ok := false
var _craft_btn: Button
var _drag_pos := Vector2.ZERO  # текущая позиция мыши во время переноса

var _board: Control                 # поле с орбами и кругом
var _circle: TextureRect            # круг (текстура рецепта)
var _glow: TextureRect              # мягкое свечение за кругом (градиент-текстура)
var _rune_ring: Control = null      # RuneRing — вращающееся рунное кольцо
var _btn_ok: StyleBox
var _btn_ok_hover: StyleBox
var _btn_ok_pressed: StyleBox
var _btn_no: StyleBox
var _btn_active := false
var _t := 0.0
var _closing := false
var _orb_home: Dictionary = {}      # elem_id -> Vector2 (точка покоя для bob)
var _orb_phase: Dictionary = {}     # elem_id -> float (фаза покачивания)


## Точка входа. game — узел Game (main.gd): нужен для _make_orb/_item_colors.
func show_craft(p_craft: Dictionary, game: Node) -> void:
	craft = p_craft.duplicate(true)
	_game = game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 25
	modulate.a = 0.0
	_accent = Color(1.0, 0.55, 0.12) if bool(craft.get("is_chromatic", false)) \
		else game._rarity_color(str(craft.get("rarity", "common")))
	_build(game)
	# Плавное открытие экрана
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Круг дорисовывается, когда рендер готов (кэш меню)
	var tex: Texture2D = await game._sigil.preview_texture(craft)
	if is_instance_valid(_circle) and tex != null:
		_circle.texture = tex


func _build(game: Node) -> void:
	# --- Фон: шейдер (градиент + виньетка + дыхание + пылинки) ---
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.02, 0.02, 0.045, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = BG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("accent", Vector3(_accent.r, _accent.g, _accent.b))
	bg.material = mat
	bg.resized.connect(func() -> void:
		var m := bg.material as ShaderMaterial
		if m != null and bg.size.y > 1.0:
			m.set_shader_parameter("aspect", bg.size.x / bg.size.y)
	)
	add_child(bg)

	# --- Шапка: заголовок со свечением + закрыть ---
	var head := HBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 24
	head.offset_right = -24
	head.offset_top = 16
	head.modulate.a = 0.0
	add_child(head)
	var title := Label.new()
	title.text = "ТРАНСМУТАЦИЯ"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.83, 0.6))
	# Свечение заголовка: тень в цвет акцента с размытым outline
	title.add_theme_color_override("font_shadow_color",
		Color(_accent.r, _accent.g, _accent.b, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 10)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.custom_minimum_size = Vector2(96, 38)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func() -> void: closed.emit())
	head.add_child(close_btn)
	var ht := create_tween()
	ht.tween_interval(0.12)
	ht.tween_property(head, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# --- Доска ---
	_board = Control.new()
	_board.name = "Board"
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.offset_top = 64
	_board.offset_bottom = -110
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_board)
	_board.resized.connect(_on_board_resized)

	# Пульсирующее свечение ЗА кругом (радиальная градиент-текстура, без _draw)
	var grad := Gradient.new()
	grad.set_color(0, Color(_accent.r, _accent.g, _accent.b, 0.5))
	grad.set_color(1, Color(_accent.r, _accent.g, _accent.b, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 0.0)
	gtex.width = 256
	gtex.height = 256
	_glow = TextureRect.new()
	_glow.name = "CircleGlow"
	_glow.texture = gtex
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.custom_minimum_size = Vector2(520, 520)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate.a = 0.0
	_board.add_child(_glow)
	_center(_glow, 520.0)

	# Круг трансмутации по центру доски
	_circle = TextureRect.new()
	_circle.name = "Circle"
	_circle.custom_minimum_size = Vector2(340, 340)
	_circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_circle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle.pivot_offset = Vector2(170, 170)
	_board.add_child(_circle)
	_center(_circle, 340.0)

	# Вращающееся рунное кольцо ПОВЕРХ круга (реагирует на заполнение)
	var ring := RuneRing.new()
	ring.name = "RuneRing"
	ring.accent = _accent
	ring.custom_minimum_size = Vector2(396, 396)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(ring)
	_center(ring, 396.0)
	_rune_ring = ring

	# --- Ячейки на круге: по одной на тип ингредиента, фантомный орб внутри ---
	var ings: Array = craft.get("ingredients", [])
	var n := maxi(ings.size(), 3)
	for i in ings.size():
		var d := ing_item(ings, i)
		var cell := _make_cell(d, game)
		cell.modulate.a = 0.0
		cell.scale = Vector2(0.5, 0.5)
		_board.add_child(cell)
		_cells[d.id] = cell
		var ct := create_tween()
		ct.tween_interval(0.1 + 0.06 * float(i))
		ct.tween_property(cell, "modulate:a", 1.0, 0.25) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(cell, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_layout_cells()

	# --- Свободные орбы: поочерёдное появление + покачивание (bob) ---
	for i in ings.size():
		var d := ing_item(ings, i)
		var orb: ElementOrb = game._make_orb(d.id, ORB_SIZE)
		orb.interactive = true
		orb.pivot_offset = Vector2(ORB_SIZE, ORB_SIZE) * 0.5
		var ang := TAU * float(i) / float(n) - PI / 2.0 + PI / float(n)
		var home := _board.size * 0.5 + Vector2(cos(ang), sin(ang)) * ORB_RADIUS \
			- Vector2(ORB_SIZE, ORB_SIZE) * 0.5
		_orb_home[d.id] = home
		_orb_phase[d.id] = float(i) * 1.7
		orb.position = home
		orb.modulate.a = 0.0
		orb.scale = Vector2(0.6, 0.6)
		orb.tapped.connect(_on_orb_tapped.bind(d.id))
		orb.drag_started.connect(_on_drag_started.bind(d.id))
		orb.drag_ended.connect(_on_drag_ended.bind(d.id))
		_board.add_child(orb)
		_orbs[d.id] = orb
		var ot := create_tween()
		ot.tween_interval(0.25 + 0.08 * float(i))
		ot.tween_property(orb, "modulate:a", 1.0, 0.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ot.parallel().tween_property(orb, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# --- Кнопка внизу ---
	_btn_ok = game._btn_style(Color(0.22, 0.58, 0.33))
	_btn_ok_hover = game._btn_style(Color(0.27, 0.68, 0.4))
	_btn_ok_pressed = game._btn_style(Color(0.18, 0.48, 0.28))
	_btn_no = game._btn_style(Color(0.15, 0.19, 0.17))
	_craft_btn = Button.new()
	_craft_btn.text = "НАЧАТЬ ТРАНСМУТАЦИЮ"
	_craft_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_craft_btn.offset_left = 120
	_craft_btn.offset_right = -120
	_craft_btn.offset_top = -92
	_craft_btn.offset_bottom = -36
	_craft_btn.add_theme_font_size_override("font_size", 17)
	_craft_btn.add_theme_stylebox_override("normal", _btn_no)
	_craft_btn.add_theme_stylebox_override("hover", _btn_no)
	_craft_btn.add_theme_stylebox_override("pressed", _btn_no)
	_craft_btn.add_theme_stylebox_override("disabled", _btn_no)
	_craft_btn.add_theme_color_override("font_disabled_color",
		Color(0.62, 0.65, 0.6, 0.85))
	_craft_btn.disabled = true
	_craft_btn.modulate.a = 0.0
	_craft_btn.pressed.connect(func() -> void:
		print("CRAFT-BOARD: confirmed pressed, placed=", _placed.size(), "/", _cells.size())
		confirmed.emit(craft))
	add_child(_craft_btn)
	var bt := create_tween()
	bt.tween_interval(0.3)
	bt.tween_property(_craft_btn, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_update_button()


## Ячейка: полупрозрачный круг с фантомным орбом нужного элемента.
## Пульс контура — бесконечный tween (детерминированно, без _draw-хаков).
func _make_cell(d: Dictionary, game: Node) -> Control:
	var cell := Control.new()
	cell.name = "Cell_" + d.id
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.pivot_offset = Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var ph: ElementOrb = game._make_orb(d.id, CELL_SIZE - 12)
	ph.interactive = false
	ph.pivot_offset = Vector2(CELL_SIZE - 12, CELL_SIZE - 12) * 0.5
	# Еле видимый фантом: сразу видно, что слот пуст и что за элемент нужен.
	ph.modulate = Color(1, 1, 1, 0.12)
	ph.position = Vector2(6, 6)
	cell.add_child(ph)
	cell.set_meta("ph", ph)
	cell.set_meta("pulse", 0.0)
	cell.set_meta("flash", 0.0)
	cell.draw.connect(_draw_cell.bind(cell))
	var loop := cell.create_tween().set_loops()
	loop.tween_method(_cell_pulse.bind(cell), 0.0, 1.0, 1.15)
	cell.mouse_entered.connect(func() -> void:
		cell.set_meta("hover", true)
		cell.queue_redraw()
	)
	cell.mouse_exited.connect(func() -> void:
		cell.set_meta("hover", false)
		cell.queue_redraw()
	)
	return cell


func _draw_cell(cell: Control) -> void:
	var filled: bool = cell.get_meta("filled", false)
	var hover: bool = bool(cell.get_meta("hover", false))
	var pulse: float = cell.get_meta("pulse", 0.0)
	var flash: float = cell.get_meta("flash", 0.0)
	var c := cell.size * 0.5
	var r := cell.size.x * 0.5 - 2.0
	if filled:
		# Двойное свечение заполненной ячейки + мягкий ореол
		cell.draw_circle(c, r + 3.0,
			Color(_accent.r, _accent.g, _accent.b, 0.10 + 0.05 * pulse))
		cell.draw_arc(c, r, 0.0, TAU, 48,
			Color(_accent.r, _accent.g, _accent.b, 0.55 + 0.2 * pulse), 2.6, true)
		cell.draw_arc(c, r - 5.0, 0.0, TAU, 48,
			Color(_accent.r, _accent.g, _accent.b, 0.9), 1.4, true)
	else:
		var a := 0.28 + 0.14 * pulse
		if hover:
			a += 0.18
		cell.draw_arc(c, r, 0.0, TAU, 48,
			Color(_accent.r, _accent.g, _accent.b, a), 2.0, true)
		# Тонкие «деления» вокруг пустого слота
		for i in 4:
			var ta := TAU * float(i) / 4.0 + pulse * 0.6
			cell.draw_line(c + Vector2(cos(ta), sin(ta)) * (r + 3.0),
				c + Vector2(cos(ta), sin(ta)) * (r + 7.0),
				Color(_accent.r, _accent.g, _accent.b, 0.25), 1.2, true)
	# Вспышка расширяющимся кольцом после дропа
	if flash > 0.003:
		var fr := r + 10.0 * (1.0 - flash)
		cell.draw_arc(c, fr, 0.0, TAU, 56,
			Color(1.0, 0.97, 0.88, 0.55 * flash), 2.0, true)


func _cell_pulse(v: float, cell: Control) -> void:
	if not is_instance_valid(cell):
		return
	cell.set_meta("pulse", v)
	cell.queue_redraw()


func _cell_flash(v: float, cell: Control) -> void:
	if not is_instance_valid(cell):
		return
	cell.set_meta("flash", v)
	cell.queue_redraw()


func _filled_ratio() -> float:
	if _cells.is_empty():
		return 0.0
	var f := 0
	for id in _cells.keys():
		if bool(_placed.get(id, false)):
			f += 1
	return float(f) / float(_cells.size())


## Центрирование узла по доске (вызывается при resize).
func _center(node: Control, side: float) -> void:
	node.set_anchors_preset(Control.PRESET_CENTER)
	node.position = _board.size * 0.5 - Vector2(side, side) * 0.5 \
		if _board.size.x > 0 else node.position
	node.resized.connect(func(): node.position = _board.size * 0.5 - Vector2(side, side) * 0.5)


## Ячейки по окружности круга: центр доски + CELL_RADIUS, равные углы.
func _layout_cells() -> void:
	if _board == null or _board.size.x <= 0:
		return
	var center := _board.size * 0.5
	var ings: Array = craft.get("ingredients", [])
	var n := maxi(ings.size(), 3)
	for i in ings.size():
		var d := ing_item(ings, i)
		var cell: Control = _cells.get(d.id)
		if cell == null:
			continue
		var ang := TAU * float(i) / float(n) - PI / 2.0
		cell.position = center + Vector2(cos(ang), sin(ang)) * CELL_RADIUS \
			- Vector2(CELL_SIZE, CELL_SIZE) * 0.5


## При resize доски: ячейки и «домики» свободных орбов пересчитываются.
func _on_board_resized() -> void:
	if _board == null or _board.size.x <= 0.0:
		return
	_layout_cells()
	var ings: Array = craft.get("ingredients", [])
	var n := maxi(ings.size(), 3)
	for i in ings.size():
		var d := ing_item(ings, i)
		if bool(_placed.get(d.id, false)):
			continue
		var ang := TAU * float(i) / float(n) - PI / 2.0 + PI / float(n)
		_orb_home[d.id] = _board.size * 0.5 \
			+ Vector2(cos(ang), sin(ang)) * ORB_RADIUS \
			- Vector2(ORB_SIZE, ORB_SIZE) * 0.5


func ing_item(ings: Array, i: int) -> Dictionary:
	var d := ings[i] as Dictionary
	return {"id": str(d.get("item_id", "")), "qty": int(d.get("qty", 0))}


# ------------------------------------------------------------- drag&drop

func _process(delta: float) -> void:
	if _board == null:
		return
	_t += delta
	# Ghost следует за мышью МЯГКО (lerp), не жёсткая привязка.
	if _ghost != null and is_instance_valid(_ghost) and _drag_id != "":
		_drag_pos = get_global_mouse_position()
		var target := _drag_pos - Vector2(GHOST_SIZE, GHOST_SIZE) * 0.5
		_ghost.position = _ghost.position.lerp(target, minf(1.0, delta * 18.0))
	# Пульсирующее свечение за кругом: ярче с заполнением ячеек.
	if _glow != null and is_instance_valid(_glow):
		_glow.modulate.a = 0.38 + 0.16 * sin(_t * 1.3) + 0.34 * _filled_ratio()
	# Лёгкое «дыхание» круга.
	if _circle != null and is_instance_valid(_circle):
		var b := 1.0 + 0.012 * sin(_t * 1.1)
		_circle.scale = Vector2(b, b)
	# Покачивание свободных орбов вокруг точек покоя (кроме того, что в руке).
	for id in _orbs:
		if id == _drag_id:
			continue
		var orb: ElementOrb = _orbs[id]
		if orb == null or not is_instance_valid(orb) or not orb.visible:
			continue
		var home: Vector2 = _orb_home.get(id, orb.position)
		var ph: float = _orb_phase.get(id, 0.0)
		orb.position = home + Vector2(0.0, sin(_t * 1.6 + ph) * 4.0)


func _on_orb_tapped(_orb: ElementOrb, elem_id: String) -> void:
	_place(elem_id)


func _on_drag_started(orb: ElementOrb, at: Vector2, elem_id: String) -> void:
	_drag_ok = not bool(_placed.get(elem_id, false))
	if not _drag_ok:
		orb.refuse()
		return
	_drag_id = elem_id
	_drag_pos = at
	# Ghost под каждый элемент свой: переиспользование давало «предыдущий»
	# элемент в руке вместо текущего.
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = orb.get_tree().root.get_node("Main")._make_orb(elem_id, GHOST_SIZE)
	_ghost.interactive = false
	_ghost.z_index = 100
	_ghost.pivot_offset = Vector2(GHOST_SIZE, GHOST_SIZE) * 0.5
	_ghost.position = at - Vector2(GHOST_SIZE, GHOST_SIZE) * 0.5
	ghost_parent().add_child(_ghost)
	# Scale-«хлопок» при захвате: 1 -> 1.14 -> 1.06
	var gt := create_tween()
	gt.tween_property(_ghost, "scale", Vector2(1.14, 1.14), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gt.tween_property(_ghost, "scale", Vector2(1.06, 1.06), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Оставшийся на поле орб чуть «прижат», пока его несут
	orb.scale = Vector2(0.94, 0.94)


func ghost_parent() -> Node:
	# Ghost в корне сцены — летает поверх всего окна.
	return get_tree().root.get_node("Main")


func _on_drag_ended(orb: ElementOrb, at: Vector2, elem_id: String) -> void:
	# Ghost удаляем ВСЕГДА: он нужен только пока перенос идёт. Не удаляли —
	# и он оставался висеть бледной иконкой на месте отпускания.
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if not _drag_ok or _drag_id != elem_id:
		_drag_id = ""
		return
	_drag_id = ""
	# Дроп на свою ячейку -> размещён; в пустое место поля -> перестановка.
	var cell: Control = _cells.get(elem_id)
	if cell != null and cell.get_global_rect().grow(10).has_point(at):
		_place(elem_id)
		return
	# Перестановка: орб плавно «перелетает» в точку броска (это новый дом bob).
	var local: Vector2 = _board.get_global_rect().position
	var new_home := at - local - Vector2(ORB_SIZE, ORB_SIZE) * 0.5
	var old_home: Vector2 = _orb_home.get(elem_id, orb.position)
	_orb_home[elem_id] = new_home
	var ft := create_tween()
	ft.tween_method(_orb_home_set.bind(elem_id), old_home, new_home, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var st := create_tween()
	st.tween_property(orb, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _orb_home_set(v: Vector2, id: String) -> void:
	_orb_home[id] = v


func _place(elem_id: String) -> void:
	if _placed.get(elem_id, false):
		return
	_placed[elem_id] = true
	# Орб уходит в круг: сжатие + фейд, потом скрываем
	var orb: ElementOrb = _orbs.get(elem_id)
	if orb != null and is_instance_valid(orb):
		var ot := create_tween()
		ot.tween_property(orb, "scale", Vector2(0.5, 0.5), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ot.parallel().tween_property(orb, "modulate:a", 0.0, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		ot.tween_callback(func() -> void:
			if is_instance_valid(orb):
				orb.visible = false
		)
	# Ячейка загорается: фантом проявляется «вспышкой» и оседает
	var cell: Control = _cells.get(elem_id)
	if cell != null:
		var ph: Control = cell.get_meta("ph")
		ph.modulate = Color(1, 1, 1, 1.0)
		ph.scale = Vector2(1.25, 1.25)
		var pt := create_tween()
		pt.tween_property(ph, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		cell.set_meta("filled", true)
		var ft := create_tween()
		ft.tween_method(_cell_flash.bind(cell), 1.0, 0.0, 0.55)
	# Рунное кольцо реагирует на заполнение
	if _rune_ring != null:
		_rune_ring.fill = _filled_ratio()
		_rune_ring.flash = 1.0
		var rt := create_tween()
		rt.tween_property(_rune_ring, "flash", 0.0, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Sfx.click()
	_update_button()


func _update_button() -> void:
	if _craft_btn == null:
		return
	var all := true
	for id in _cells.keys():
		if not bool(_placed.get(id, false)):
			all = false
			break
	_craft_btn.disabled = not all
	if all:
		_craft_btn.text = "НАЧАТЬ ТРАНСМУТАЦИЮ"
		if not _btn_active:
			_btn_active = true
			_craft_btn.add_theme_stylebox_override("normal", _btn_ok)
			_craft_btn.add_theme_stylebox_override("hover", _btn_ok_hover)
			_craft_btn.add_theme_stylebox_override("pressed", _btn_ok_pressed)
			_craft_btn.pivot_offset = _craft_btn.size * 0.5
			# Короткий scale-пульс при переходе в активное состояние
			var pt := create_tween()
			pt.tween_property(_craft_btn, "scale", Vector2(1.06, 1.06), 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			pt.tween_property(_craft_btn, "scale", Vector2.ONE, 0.2) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			# Пульсирующее свечение активной кнопки (self_modulate — не мешает фейдам)
			var gt := create_tween().set_loops()
			gt.tween_property(_craft_btn, "self_modulate", Color(1.22, 1.22, 1.1, 1.0), 0.7) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			gt.tween_property(_craft_btn, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.7) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_craft_btn.text = "РАЗМЕСТИ ВСЕ ЭЛЕМЕНТЫ (%d/%d)" % [_placed.size(), _cells.size()]
	print("CRAFT-BOARD: btn update, all=", all, " placed=", _placed.size(), "/", _cells.size())


func close() -> void:
	if _closing:
		return
	_closing = true
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
		_ghost = null
	# Сразу убираем из обработки ввода, чтобы фейд не блокировал UI
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


## =====================================================================
## Вращающееся рунное кольцо поверх круга трансмутации.
## fill — доля заполненных ячеек (яркость и скорость вращения),
## flash — вспышка при очередном дропе.
class RuneRing extends Control:

	var accent := Color(0.85, 0.72, 0.42)
	var fill := 0.0
	var flash := 0.0

	func _process(delta: float) -> void:
		rotation += delta * (0.22 + fill * 0.5)
		pivot_offset = size * 0.5
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		if r <= 4.0:
			return
		var a := 0.16 + fill * 0.25 + flash * 0.45
		draw_arc(c, r, 0.0, TAU, 72, Color(accent.r, accent.g, accent.b, a * 0.45), 4.5, true)
		draw_arc(c, r, 0.0, TAU, 72, Color(accent.r, accent.g, accent.b, a), 1.7, true)
		for i in 24:
			var ta := TAU * float(i) / 24.0
			var inner := r - (10.0 if i % 3 == 0 else 6.0)
			draw_line(c + Vector2(cos(ta), sin(ta)) * inner,
				c + Vector2(cos(ta), sin(ta)) * r,
				Color(accent.r, accent.g, accent.b, a * 0.8), 1.3, true)
		# «Рунные» точки идут против вращения кольца
		for i in 9:
			var ra := TAU * float(i) / 9.0 - rotation * 2.1
			var p := c + Vector2(cos(ra), sin(ra)) * (r - 15.0)
			draw_circle(p, 1.4 + fill * 0.9,
				Color(1.0, 0.97, 0.88, 0.18 + fill * 0.3 + flash * 0.35))
