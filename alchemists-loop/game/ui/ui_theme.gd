class_name UiTheme
extends RefCounted
## Централизованный Theme ТОЛЬКО для меню вкладок (+ базовый шрифт игры,
## чтобы подмена theme не сбросила Manrope). Остальной UI откатан к исходному
## оформлению до следующей итерации редизайна.

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

static func build() -> Theme:
	var th := Theme.new()
	var fr := fonts()
	# Повторяем базу исходной темы игры (main.gd::_build_ui), чтобы подмена
	# theme не изменила шрифт остального UI.
	if fr[0] != null:
		th.default_font = fr[0]
	th.default_font_size = 16

	# Вкладки: pill-сегмент. Кегль 11 SemiBold + иконка 16 px подобраны так,
	# чтобы 6 разделов помещались на 540 px без обрезки («Инструменты» целиком).
	th.set_stylebox("tab_selected", "TabContainer", UiStyle.tab(true))
	th.set_stylebox("tab_unselected", "TabContainer", UiStyle.tab(false))
	th.set_stylebox("tab_hovered", "TabContainer", UiStyle.tab_hover())
	th.set_stylebox("tab_disabled", "TabContainer", UiStyle.tab(false))
	th.set_stylebox("panel", "TabContainer", UiStyle.tab_bar())
	th.set_color("font_selected_color", "TabContainer", T.c(T.ACCENT))
	th.set_color("font_unselected_color", "TabContainer", T.c(T.INK2))
	th.set_color("font_hovered_color", "TabContainer", T.c(T.INK1))
	th.set_color("font_outline_color", "TabContainer", Color(0, 0, 0, 0))
	var fsemi := font(2)
	if fsemi != null:
		th.set_font("font", "TabContainer", fsemi)
	th.set_font_size("font_size", "TabContainer", int(T.T_TAB[0]))
	th.set_constant("tab_hseparation", "TabContainer", 1)
	th.set_constant("tab_vseparation", "TabContainer", 0)
	th.set_constant("side_margin", "TabContainer", 0)
	th.set_constant("icon_separation", "TabContainer", 4)
	return th
