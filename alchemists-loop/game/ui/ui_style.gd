class_name UIStyle
extends RefCounted
# Единая визуальная система «мастерская алхимика»: тёплое дерево, латунь,
# бумага, чугун. Токены §3 спеки 2026-10-25; старые имена сохранены ради
# 54 вызовов, меняются только значения.

const INK := Color("14100e")
const NAVY := Color("1a1210")
const PANEL := Color("2a1d1e")
const PANEL_HI := Color("3d2b24")
const LINE := Color("5a3a25")
const WOOD_DEEP := Color("241610")
const WOOD := Color("2e1d15")
const WOOD_LIGHT := Color("5a3a26")
const PLASTER := Color("3a2e27")
const PLASTER_HI := Color("80644f")
const IRON := Color("2b2320")
const PAPER_HI := Color("efe0bd")
const PAPER := Color("c9ad7e")
const PAPER_LIT := Color("edc17c")
const PAPER_INK := Color("2a1d16")
const BRASS_HI := Color("e6b87a")
const BRASS := Color("c89060")
const BRASS_DIM := Color("8a5c38")
const FLAME := Color("f5c378")
const GLOW := Color("eeb36b")
const EMBER := Color("f7a76d")
const HIGHLIGHT := Color("fad69b")
const CREAM := Color("dabfa6")
const TEXT_DIM := Color("a98d74")
const TEXT_MUTED := Color("6e5c50")
const RUBY := Color("b4553f")
const LEAF := Color("6f8f5a")
const ARCANA := Color("8b6fa8")
const MAGIC := Color("7fa89a")

# Совместимость имён (§3): TEAL→GLOW, TEAL_DIM→BRASS_DIM, GOLD→BRASS_HI,
# GOLD_DIM→BRASS_DIM, TEXT→CREAM, DANGER→RUBY. TEAL в хроме больше не цвет.
const TEAL := GLOW
const TEAL_DIM := BRASS_DIM
const GOLD := BRASS_HI
const GOLD_DIM := BRASS_DIM
const TEXT := CREAM
const DANGER := RUBY

# Рунический display-шрифт (заголовок игры и названия карточек сигилов).
const RUNIC_PATH := "res://assets/fonts/Alchemist-Runic.ttf"
static var _runic: Font = null


## Рунический шрифт напрямую, минуя тему. Нужен там, где тема физически не
## достаёт: Godot не прокидывает её через узлы, которые не Control (SigilUI —
## простой Node), и обрывает на SubViewport, а в них рендерятся и карточки-PNG
## (sigil_render_service), и живая карточка фуллскрина. get_theme_font там
## возвращает не Manrope, а встроенный Open Sans.
static func runic() -> Font:
	if _runic == null and ResourceLoader.exists(RUNIC_PATH):
		_runic = load(RUNIC_PATH) as Font
		if _runic != null and ResourceLoader.exists("res://assets/fonts/Manrope-Bold.ttf"):
			var fb := load("res://assets/fonts/Manrope-Bold.ttf") as Font
			if fb != null and not _runic.fallbacks.has(fb):
				var arr := _runic.fallbacks.duplicate()
				arr.append(fb)
				_runic.fallbacks = arr
	return _runic


static func box(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


static func _margins(sb: StyleBox, l: float, t: float, r: float, b: float) -> void:
	sb.content_margin_left = l
	sb.content_margin_top = t
	sb.content_margin_right = r
	sb.content_margin_bottom = b


# ---------- панели ----------

## Панель страницы: тихая доска с латунной кромкой. bg/radius/border остаются
## в сигнатуре ради 54 вызовов; материал теперь задаёт текстура.
static func panel(_bg: Color = PANEL, _radius: int = 16,
		_border: Color = LINE) -> StyleBoxTexture:
	return UITheme.nine("frame_panel", Vector4(20, 20, 20, 20), Vector4(12, 10, 12, 10))


## Модалка: самая нарядная рама набора.
static func modal_panel(_accent: Color = GOLD) -> StyleBoxTexture:
	return UITheme.nine("frame_modal", Vector4(34, 34, 34, 34), Vector4(18, 16, 18, 16))


## Поле Эксперимента: мягкая тёмная вуаль с тонкой латунной кромкой поверх
## комнаты — центр прозрачнее, края гуще. Без текстуры — тёплое углубление.
static func arena_style() -> StyleBox:
	var sb := UITheme.nine("arena_table", Vector4(96, 96, 96, 96), Vector4.ZERO)
	if sb != null:
		return sb
	var flat := box(Color(INK, 0.94), Color(LINE, 0.65), 22, 1)
	flat.shadow_color = Color(WOOD_DEEP, 0.55)
	flat.shadow_size = 14
	_margins(flat, 0, 0, 0, 0)
	return flat


## Окно выбора реагента: та же доска, притемнённая, чтобы поле читалось сквозь.
static func picker_style() -> StyleBox:
	var sb := UITheme.nine("frame_panel", Vector4(20, 20, 20, 20),
		Vector4(10, 10, 10, 10), Color(0.42, 0.34, 0.28, 0.97))
	if sb != null:
		return sb
	var flat := box(Color(WOOD_DEEP, 0.72), Color(BRASS_DIM, 0.55), 20, 1)
	_margins(flat, 10, 10, 10, 10)
	return flat


# ---------- кнопки ----------

## kind: 0 — вторичная (дерево), 1 — основная (латунь), 2 — акцент (латунь).
## Нажатие сдвигает контент на 1 px вниз — тот же контракт, что у плашки доски.
static func style_button(b: Button, kind: int = 0, _radius: int = 11) -> void:
	var tex_name := "btn_brass" if kind != 0 else "btn_wood"
	var m := Vector4(24, 14, 24, 14)
	var c := Vector4(10, 10, 10, 10)
	var states := UITheme.nine_hv(tex_name, m, c)
	if states.is_empty():
		# nine_hv вернул {} — текстуры нет (контракт промаха Task 3). Без guard
		# states["normal"] дал бы invalid-key в рантайме; промах = «ничего не
		# ставим», кнопка остаётся на дефолтной теме.
		return
	var disabled := UITheme.nine(tex_name, m, c, Color(0.55, 0.50, 0.47, 0.85))
	b.add_theme_stylebox_override("normal", states["normal"])
	b.add_theme_stylebox_override("hover", states["hover"])
	b.add_theme_stylebox_override("pressed", states["pressed"])
	b.add_theme_stylebox_override("hover_pressed", states["pressed"])
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := PAPER_INK if kind != 0 else CREAM
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_hover_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", TEXT_MUTED)


## Компактная ячейка реагента: углубление well_slot.
static func style_cell(btn: Button, hint: bool = false, alpha: float = 0.7) -> void:
	var a := clampf(alpha, 0.55, 1.0)
	var m := Vector4(20, 20, 20, 20)
	var c := Vector4(8, 8, 8, 8)
	var tint := Color(1.0, 0.94, 0.84, a) if hint else Color(1.0, 1.0, 1.0, a)
	var hover := Color(1.10, 1.06, 0.98, a) if hint else Color(1.10, 1.10, 1.10, a)
	var n := UITheme.nine("well_slot", m, c, tint)
	var h := UITheme.nine("well_slot", m, c, hover)
	var p := UITheme.nine("well_slot", m, Vector4(8, 7, 8, 9), Color(0.88, 0.86, 0.84, a))
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", BRASS_HI if hint else CREAM)


## Строка списка (улучшения, крафты): доска, контент не ближе 12/10.
static func style_row(b: Button) -> void:
	var m := Vector4(20, 20, 20, 20)
	var c := Vector4(12, 10, 12, 10)
	var n := UITheme.nine("frame_panel", m, c)
	var h := UITheme.nine("frame_panel", m, c, Color(1.08, 1.08, 1.08, 1.0))
	var p := UITheme.nine("frame_panel", m, Vector4(12, 9, 12, 11), Color(0.90, 0.90, 0.90, 1.0))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", CREAM)
	b.add_theme_color_override("font_pressed_color", CREAM)


## Счётчик на иконке (непрочитанное, заявки): рубиновая пилюля, скрыта при нуле.
static func count_badge() -> Label:
	var badge := Label.new()
	badge.name = "Badge"
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", CREAM)
	var sb := box(RUBY, Color(PAPER_INK, 0.9), 8, 1)
	_margins(sb, 4, 0, 4, 0)
	badge.add_theme_stylebox_override("normal", sb)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	return badge


## Вывеска заголовка: plaque_title, текст держится вне угловых полей.
static func title_plaque() -> StyleBoxTexture:
	return UITheme.nine("plaque_title", Vector4(64, 18, 64, 18), Vector4(36, 12, 36, 12))


# ---------- вкладки ----------

static func _tab_flat(bg: Color, edge: Color, underline: int) -> StyleBoxFlat:
	var sb := box(bg, edge, 10, 0)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.border_width_bottom = underline
	_margins(sb, 6, 13, 6, 13)
	return sb


static func style_tabs(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("tab_selected",
		UITheme.nine("tab_active", Vector4(22, 12, 22, 12), Vector4(8, 13, 8, 13)))
	# Неактивные вкладки — деревянная направляющая tab_rail, а не заливка.
	var rail := UITheme.nine("tab_rail", Vector4(24, 10, 24, 10), Vector4(6, 13, 6, 13))
	var rail_hover := UITheme.nine("tab_rail", Vector4(24, 10, 24, 10), Vector4(6, 13, 6, 13),
		Color(1.16, 1.10, 1.02, 1.0))
	var rail_disabled := UITheme.nine("tab_rail", Vector4(24, 10, 24, 10), Vector4(6, 13, 6, 13),
		Color(0.62, 0.58, 0.55, 0.85))
	tabs.add_theme_stylebox_override("tab_unselected",
		rail if rail != null else _tab_flat(Color(WOOD_DEEP, 0.78), Color(0, 0, 0, 0), 0))
	tabs.add_theme_stylebox_override("tab_hovered",
		rail_hover if rail_hover != null else _tab_flat(Color(WOOD, 0.90), LINE, 2))
	tabs.add_theme_stylebox_override("tab_disabled",
		rail_disabled if rail_disabled != null else _tab_flat(Color(WOOD_DEEP, 0.45), Color(0, 0, 0, 0), 0))
	var tab_focus := box(Color(0, 0, 0, 0), Color(BRASS_HI, 0.9), 12, 2)
	tab_focus.corner_radius_bottom_left = 0
	tab_focus.corner_radius_bottom_right = 0
	tab_focus.set_expand_margin_all(2.0)
	tabs.add_theme_stylebox_override("tab_focus", tab_focus)
	tabs.add_theme_color_override("font_selected_color", CREAM)
	tabs.add_theme_color_override("font_unselected_color", TEXT_DIM)
	tabs.add_theme_color_override("font_hovered_color", CREAM)
	tabs.add_theme_color_override("font_disabled_color", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.4))
	# Панель вкладок больше не StyleBoxFlat: corner_radius здесь не мутируется.
	set_tabs_panel_bare(tabs, false)


## Панель вкладок: на стартовом экране рамку снимаем — плита комнаты служит
## фоном всей страницы, а не картиной в рамке интерфейса.
static func set_tabs_panel_bare(tabs: TabContainer, bare: bool) -> void:
	if tabs == null:
		return
	if bare:
		tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		return
	tabs.add_theme_stylebox_override("panel",
		UITheme.nine("frame_panel", Vector4(20, 20, 20, 20), Vector4(12, 10, 12, 10)))


# ---------- глобальная тема ----------

static func apply_theme(th: Theme) -> void:
	th.set_color("font_color", "Label", CREAM)
	# LineEdit — поле материала.
	var le_n := UITheme.nine("field", Vector4(18, 12, 18, 12), Vector4(12, 8, 12, 8))
	var le_f := UITheme.nine("field", Vector4(18, 12, 18, 12), Vector4(12, 8, 12, 8),
		Color(1.14, 1.08, 0.94, 1.0))
	th.set_stylebox("normal", "LineEdit", le_n)
	th.set_stylebox("focus", "LineEdit", le_f)
	th.set_color("font_color", "LineEdit", CREAM)
	th.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.7))
	th.set_color("caret_color", "LineEdit", BRASS_HI)
	th.set_color("selection_color", "LineEdit", Color(BRASS, 0.30))
	# ProgressBar — пламя по углублению.
	var pb_bg := box(Color(WOOD_DEEP, 0.95), Color(LINE, 0.6), 6)
	var pb_fill := box(FLAME, Color(FLAME, 0.9), 6, 0)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fill)
	# Скроллбары.
	for bar in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", bar, StyleBoxEmpty.new())
		th.set_stylebox("scroll_focus", bar, StyleBoxEmpty.new())
		th.set_stylebox("grabber", bar, box(Color(BRASS_DIM, 0.45), Color(0, 0, 0, 0), 4, 0))
		th.set_stylebox("grabber_highlight", bar, box(Color(BRASS, 0.65), Color(0, 0, 0, 0), 4, 0))
		th.set_stylebox("grabber_pressed", bar, box(BRASS_HI, Color(0, 0, 0, 0), 4, 0))
	# Тултип.
	var tip := UITheme.nine("field", Vector4(18, 12, 18, 12), Vector4(10, 6, 10, 6))
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", CREAM)
