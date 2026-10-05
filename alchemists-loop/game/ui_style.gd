class_name UIStyle
extends RefCounted
# Единая визуальная система «ночная лаборатория алхимика».
# Бирюза = магия/действие, золото = выбор/акцент, тёмно-синий = материя.
# Всё на StyleBoxFlat: без текстур, тот же вид на любом DPI.

const INK := Color("060a11")
const NAVY := Color("0b121c")
const PANEL := Color("111c2a")
const PANEL_HI := Color("1a2a3c")
const LINE := Color("2b4254")
const TEAL := Color("5fe3d6")
const TEAL_DIM := Color("2c8a86")
const GOLD := Color("f2c85b")
const GOLD_DIM := Color("9a7a26")
const TEXT := Color("e8f2f6")
const TEXT_DIM := Color("8ea3b1")
const DANGER := Color("e8695a")


static func box(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


static func _margins(sb: StyleBoxFlat, l: float, t: float, r: float, b: float) -> void:
	sb.content_margin_left = l
	sb.content_margin_top = t
	sb.content_margin_right = r
	sb.content_margin_bottom = b


# ---------- панели ----------

## Обычная панель страницы: мягкая тень + тонкая рамка.
static func panel(bg: Color = PANEL, radius: int = 16, border: Color = LINE) -> StyleBoxFlat:
	var sb := box(bg, Color(border.r, border.g, border.b, 0.75), radius)
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	_margins(sb, 12, 10, 12, 10)
	return sb


## Модальное окно: плотный фон, рамка в цвет акцента, глубокая тень.
static func modal_panel(accent: Color = GOLD) -> StyleBoxFlat:
	var sb := box(Color(0.055, 0.08, 0.12, 0.985), Color(accent.r, accent.g, accent.b, 0.70), 22, 2)
	sb.shadow_color = Color(0, 0, 0, 0.60)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 8)
	_margins(sb, 18, 16, 18, 16)
	return sb


## Поле Эксперимента (под ним рисуется шейдер UIFx.field_decor).
static func arena_style() -> StyleBoxFlat:
	var sb := box(Color(0.03, 0.05, 0.085, 0.94), Color(TEAL_DIM.r, TEAL_DIM.g, TEAL_DIM.b, 0.45), 22, 1)
	sb.shadow_color = Color(0.05, 0.35, 0.35, 0.20)
	sb.shadow_size = 14
	_margins(sb, 0, 0, 0, 0)
	return sb


## Полупрозрачное окно выбора реагента.
static func picker_style() -> StyleBoxFlat:
	var sb := box(Color(0.03, 0.06, 0.10, 0.55), Color(TEAL.r, TEAL.g, TEAL.b, 0.45), 20, 1)
	_margins(sb, 10, 10, 10, 10)
	return sb


# ---------- кнопки ----------

static func _btn_box(bg: Color, edge: Color, radius: int, lip: int, top: float, bottom: float) -> StyleBoxFlat:
	var sb := box(bg, edge, radius, 1)
	# Нижний кант толще — кнопка выглядит «нажимаемой».
	sb.border_width_bottom = lip
	_margins(sb, 12, top, 12, bottom)
	return sb


## kind: 0 — вторичная, 1 — основная (бирюза), 2 — золото.
static func style_button(b: Button, kind: int = 0, radius: int = 11) -> void:
	var base: Color
	var edge: Color
	var fg: Color
	var press_bg: Color
	var press_edge: Color
	var press_fg: Color
	match kind:
		1:
			base = Color("145a58")
			edge = TEAL
			fg = Color("effffd")
			press_bg = Color("0d3d3c")
			press_edge = TEAL
			press_fg = fg
		2:
			base = Color("d9a93a")
			edge = Color("ffe08a")
			fg = Color("2a1d05")
			press_bg = Color("a9801f")
			press_edge = GOLD
			press_fg = fg
		_:
			base = PANEL_HI
			edge = LINE
			fg = TEXT
			# Для toggle-чипов «нажато» читается как включено: бирюзовая рамка.
			press_bg = Color("14343c")
			press_edge = TEAL
			press_fg = TEAL
	var normal := _btn_box(base, edge, radius, 3, 5, 8)
	var hover := _btn_box(base.lightened(0.12), edge.lightened(0.15), radius, 3, 5, 8)
	var pressed := _btn_box(press_bg, press_edge, radius, 1, 7, 6)
	var disabled := _btn_box(
		Color(base.r * 0.45 + 0.03, base.g * 0.45 + 0.04, base.b * 0.45 + 0.05, 0.85),
		Color(LINE.r, LINE.g, LINE.b, 0.5), radius, 1, 5, 8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg.lightened(0.1))
	b.add_theme_color_override("font_pressed_color", press_fg)
	b.add_theme_color_override("font_hover_pressed_color", press_fg)
	b.add_theme_color_override("font_disabled_color", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.55))


## Компактная ячейка реагента (Эксперимент и Лаборатория).
static func style_cell(btn: Button, hint: bool = false, alpha: float = 0.7) -> void:
	var bg := Color(0.06, 0.12, 0.18, alpha)
	var edge := Color(0.20, 0.34, 0.42, 0.75)
	if hint:
		bg = Color(0.20, 0.16, 0.08, alpha)
		edge = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
	var n := box(bg, edge, 12, 2 if hint else 1)
	var h := box(bg.lightened(0.12), Color(TEAL.r, TEAL.g, TEAL.b, 0.8), 12, 1)
	var p := box(bg.darkened(0.2), TEAL, 12, 2)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# ---------- вкладки ----------

static func _tab_box(bg: Color, edge: Color, underline: int) -> StyleBoxFlat:
	var sb := box(bg, edge, 10, 0)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.border_width_bottom = underline
	_margins(sb, 9, 8, 9, 8)
	return sb


static func style_tabs(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("tab_selected", _tab_box(PANEL_HI, GOLD, 3))
	tabs.add_theme_stylebox_override("tab_unselected", _tab_box(Color(0.03, 0.05, 0.08, 0.55), Color(0, 0, 0, 0), 0))
	tabs.add_theme_stylebox_override("tab_hovered", _tab_box(Color(0.08, 0.13, 0.20, 0.85), LINE, 2))
	tabs.add_theme_stylebox_override("tab_disabled", _tab_box(Color(0.03, 0.05, 0.08, 0.3), Color(0, 0, 0, 0), 0))
	# Видимый фокус-ободок (доступность: навигация с клавиатуры/геймпада):
	# бирюзовая рамка чуть вокруг вкладки, форма как у tab-бокса — скруглённый
	# верх и прямой низ. StyleBoxEmpty прятал фокус (Godot документирует это).
	var tab_focus := box(Color(0, 0, 0, 0), Color(TEAL.r, TEAL.g, TEAL.b, 0.9), 12, 2)
	tab_focus.corner_radius_bottom_left = 0
	tab_focus.corner_radius_bottom_right = 0
	tab_focus.set_expand_margin_all(2.0)
	tabs.add_theme_stylebox_override("tab_focus", tab_focus)
	tabs.add_theme_color_override("font_selected_color", TEXT)
	tabs.add_theme_color_override("font_unselected_color", TEXT_DIM)
	tabs.add_theme_color_override("font_hovered_color", TEXT)
	tabs.add_theme_color_override("font_disabled_color", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.4))
	var pan := panel(Color(0.08, 0.12, 0.18, 0.55), 14)
	pan.corner_radius_top_left = 4
	tabs.add_theme_stylebox_override("panel", pan)


# ---------- глобальная тема ----------

static func apply_theme(th: Theme) -> void:
	th.set_color("font_color", "Label", TEXT)
	# LineEdit
	var le_n := box(Color(0.04, 0.07, 0.11, 0.92), LINE, 10)
	_margins(le_n, 12, 8, 12, 8)
	var le_f := box(Color(0.05, 0.09, 0.14, 0.97), TEAL_DIM, 10, 2)
	_margins(le_f, 11, 7, 11, 7)
	th.set_stylebox("normal", "LineEdit", le_n)
	th.set_stylebox("focus", "LineEdit", le_f)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.7))
	th.set_color("caret_color", "LineEdit", TEAL)
	th.set_color("selection_color", "LineEdit", Color(TEAL.r, TEAL.g, TEAL.b, 0.30))
	# ProgressBar
	var pb_bg := box(Color(0.05, 0.08, 0.12, 0.95), Color(LINE.r, LINE.g, LINE.b, 0.6), 6)
	var pb_fill := box(TEAL, TEAL.lightened(0.25), 6, 0)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fill)
	# Тонкие скроллбары
	for bar in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", bar, StyleBoxEmpty.new())
		th.set_stylebox("scroll_focus", bar, StyleBoxEmpty.new())
		th.set_stylebox("grabber", bar, box(Color(TEAL_DIM.r, TEAL_DIM.g, TEAL_DIM.b, 0.45), Color(0, 0, 0, 0), 4, 0))
		th.set_stylebox("grabber_highlight", bar, box(Color(TEAL.r, TEAL.g, TEAL.b, 0.65), Color(0, 0, 0, 0), 4, 0))
		th.set_stylebox("grabber_pressed", bar, box(TEAL, Color(0, 0, 0, 0), 4, 0))
	# Тултипы
	var tip := box(Color(0.04, 0.07, 0.11, 0.97), Color(LINE.r, LINE.g, LINE.b, 0.9), 8)
	_margins(tip, 10, 6, 10, 6)
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", TEXT)
