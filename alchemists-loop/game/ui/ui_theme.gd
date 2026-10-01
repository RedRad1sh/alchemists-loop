class_name UiTheme
extends RefCounted
## Собирает централизованный Theme из токенов: один Theme на корне игры заменяет
## сотни точечных add_theme_*_override (см. анализ §2). Фолбэк: если шрифты или
## UiStyle недоступны — игра работает как раньше (Theme просто не ставится).

const T := DesignTokens

static var enabled := true
static var _fonts: Array = []

static func fonts() -> Array:
	if _fonts.is_empty():
		_fonts.resize(T.FONT_PATHS.size())
		for i in T.FONT_PATHS.size():
			var p: String = T.FONT_PATHS[i]
			_fonts[i] = load(p) if ResourceLoader.exists(p) else null
	return _fonts

static func font(idx: int) -> Font:
	var f := fonts()
	return f[idx] if idx < f.size() and f[idx] != null else null

static func _apply_role(th: Theme, type: String, role: Array, color: Color) -> void:
	th.set_font_size("font_size", type, int(role[0]))
	var f := font(int(role[1]))
	if f != null:
		th.set_font("font", type, f)
	th.set_color("font_color", type, color)

static func build() -> Theme:
	var th := Theme.new()
	var fr := fonts()
	if fr[0] != null:
		th.default_font = fr[0]
	th.default_font_size = int(T.T_BODY[0])

	# Label: роли по умолчанию — светлый чернильный текст.
	th.set_color("font_color", "Label", T.c(T.INK1))

	# Button: вторичный стиль по умолчанию; kind 1/2 ставятся фабрикой UiStyle.
	for st in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(st, "Button", UiStyle.button(0, st))
	th.set_stylebox("focus", "Button", UiStyle.button_focus())
	th.set_color("font_color", "Button", T.c(T.INK1))
	th.set_color("font_hover_color", "Button", T.c(T.INK1))
	th.set_color("font_pressed_color", "Button", T.c(T.INK1))
	th.set_color("font_disabled_color", "Button", T.c(T.INK3))
	th.set_color("font_focus_color", "Button", T.c(T.INK1))
	var fsemi := font(2)
	if fsemi != null:
		th.set_font("font", "Button", fsemi)
	th.set_font_size("font_size", "Button", int(T.T_BTN_SM[0]))

	# TabContainer: pill-сегмент вместо дефолтных прямоугольников Godot.
	th.set_stylebox("tab_selected", "TabContainer", UiStyle.tab(true))
	th.set_stylebox("tab_unselected", "TabContainer", UiStyle.tab(false))
	th.set_stylebox("tab_hovered", "TabContainer", UiStyle.tab_hover())
	th.set_stylebox("tab_disabled", "TabContainer", UiStyle.tab(false))
	th.set_stylebox("panel", "TabContainer", UiStyle.tab_bar())
	th.set_color("font_selected_color", "TabContainer", T.c(T.ACCENT))
	th.set_color("font_unselected_color", "TabContainer", T.c(T.INK2))
	th.set_color("font_hovered_color", "TabContainer", T.c(T.INK1))
	th.set_color("font_outline_color", "TabContainer", Color(0, 0, 0, 0))
	if fsemi != null:
		th.set_font("font", "TabContainer", fsemi)
	th.set_font_size("font_size", "TabContainer", int(T.T_TAB[0]))
	th.set_constant("tab_hseparation", "TabContainer", 4)
	th.set_constant("tab_vseparation", "TabContainer", 0)
	th.set_constant("side_margin", "TabContainer", 0)
	th.set_constant("icon_separation", "TabContainer", 6)

	# LineEdit: рамка, фокус-акцент, читаемый плейсхолдер.
	th.set_stylebox("normal", "LineEdit", UiStyle.input())
	th.set_stylebox("focus", "LineEdit", UiStyle.input_focus())
	th.set_stylebox("read_only", "LineEdit", UiStyle.input())
	th.set_color("font_color", "LineEdit", T.c(T.INK1))
	th.set_color("font_placeholder_color", "LineEdit", T.c(T.INK3))
	th.set_color("caret_color", "LineEdit", T.c(T.ACCENT))
	th.set_color("selection_color", "LineEdit", T.accent_soft(0.35))
	th.set_color("clear_button_color", "LineEdit", T.c(T.INK2))
	th.set_font_size("font_size", "LineEdit", int(T.T_BODY[0]))

	# ProgressBar: тонкая полоса с акцентным заполнением.
	th.set_stylebox("background", "ProgressBar", UiStyle.bar_bg())
	th.set_stylebox("fill", "ProgressBar", UiStyle.bar_fill())

	# PanelContainer: единая карточка.
	th.set_stylebox("panel", "PanelContainer", UiStyle.card())

	# ScrollBar: пилюля-ползунок, прозрачная дорожка.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0)
	var grab := StyleBoxFlat.new()
	grab.bg_color = T.c(T.LINE_STRONG, 0.9)
	grab.set_corner_radius_all(T.R_PILL)
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	var grab_h := grab.duplicate() as StyleBoxFlat
	grab_h.bg_color = T.c(T.ACCENT, 0.7)
	for sb_type in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", sb_type, track)
		th.set_stylebox("grabber", sb_type, grab)
		th.set_stylebox("grabber_highlight", sb_type, grab_h)
		th.set_constant("size", sb_type, 6)
	return th
