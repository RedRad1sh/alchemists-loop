class_name UIWidgets
extends RefCounted
# Готовые блоки для списков (задания, комплекты, заказы, круг, неделя):
# вместо голых Label — карточка с заголовком, подписью и прогресс-баром.

## Карточка-контейнер. Возвращает PanelContainer; наполняйте через get_meta("body").
static func card(accent: Color = UIStyle.LINE, done: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := Color(0.07, 0.12, 0.18, 0.85)
	var edge := accent
	if done:
		bg = Color(0.06, 0.12, 0.11, 0.80)
		edge = Color(UIStyle.TEAL_DIM.r, UIStyle.TEAL_DIM.g, UIStyle.TEAL_DIM.b, 0.7)
	var sb := UIStyle.box(bg, Color(edge.r, edge.g, edge.b, 0.65), 12, 1)
	sb.border_width_left = 4  # цветная полоса слева — быстро читается состояние
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 9.0
	p.add_theme_stylebox_override("panel", sb)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(body)
	p.set_meta("body", body)
	return p


## Строка прогресса: заголовок (+ значок ✓/•), подпись, бар и значение справа.
## target <= 0 — бара нет (просто информационная карточка).
static func progress_row(g: Game, title: String, sub: String, cur: int, target: int,
		done: bool = false, accent: Color = UIStyle.GOLD, reward: String = "") -> PanelContainer:
	var p := card(accent, done)
	var body: VBoxContainer = p.get_meta("body")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head)
	var t := g._label(("✓  " if done else "") + title, 14)
	t.add_theme_color_override("font_color", UIStyle.TEAL if done else UIStyle.TEXT)
	if g._font_semi != null:
		t.add_theme_font_override("font", g._font_semi)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if reward != "":
		var r := g._label(reward, 12)
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		r.add_theme_color_override("font_color", UIStyle.GOLD if not done else UIStyle.TEXT_DIM)
		r.size_flags_horizontal = Control.SIZE_SHRINK_END
		head.add_child(r)
	if sub != "":
		var s := g._label(sub, 11)
		s.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		body.add_child(s)
	if target > 0:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(row)
		var bar := ProgressBar.new()
		bar.name = "ProgressBar"
		bar.max_value = float(target)
		bar.value = float(clampi(cur, 0, target))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill_col := UIStyle.TEAL if done else accent
		bar.add_theme_stylebox_override("fill", UIStyle.box(fill_col, Color(0, 0, 0, 0), 4, 0))
		bar.add_theme_stylebox_override("background",
			UIStyle.box(Color(0.03, 0.05, 0.08, 0.9), Color(UIStyle.LINE.r, UIStyle.LINE.g, UIStyle.LINE.b, 0.5), 4, 1))
		row.add_child(bar)
		var v := g._label("%d/%d" % [mini(cur, target), target], 11)
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		v.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(v)
	return p


## Заголовок секции с линией: «ЗАДАНИЯ СВЕТИКА ————».
static func section(g: Game, text: String, accent: Color = UIStyle.GOLD) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := g._label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.add_theme_color_override("font_color", accent)
	if g._font_semi != null:
		l.add_theme_font_override("font", g._font_semi)
	h.add_child(l)
	var line := ColorRect.new()
	line.color = Color(accent.r, accent.g, accent.b, 0.30)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h


## Пустое состояние: «Заказы появятся завтра».
static func empty(g: Game, text: String) -> Control:
	var p := card(UIStyle.LINE)
	var body: VBoxContainer = p.get_meta("body")
	var l := g._label(text, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	body.add_child(l)
	return p


## Информационная плашка-баннер (бонусы, «получен!»).
static func banner(g: Game, text: String, accent: Color = UIStyle.GOLD) -> Control:
	var sb := UIStyle.box(Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.9),
		Color(accent.r, accent.g, accent.b, 0.8), 12, 1)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := g._label(text, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", accent.lightened(0.2))
	p.add_child(l)
	return p
