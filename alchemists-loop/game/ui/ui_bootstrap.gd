class_name UiBootstrap
extends RefCounted
## Единственная точка подключения дизайн-системы к существующему UI.
## Вызывается один раз из Game._build_ui(): ставит централизованный Theme и
## чинит шапку/строку ресурсов/вкладки БЕЗ правок логики модулей (UX-01…08).

const T := DesignTokens

const HEADER_ICONS := ["star", "trend_up", "volume", "book"]
const TAB_ICONS := ["flask", "cauldron", "globe", "home", "trophy", "sliders"]

static func apply(game: Control) -> void:
	if not UiTheme.enabled or game == null:
		return
	game.theme = UiTheme.build()
	var root := game.get_node_or_null("Margin/Root") as Control
	if root == null:
		return
	_restyle_header(root)
	_restyle_resource_row(root)
	_tab_icons(root)

# ---------- шапка: иконки вместо глифов, тач 44 px, бейдж-компонент ----------
static func _restyle_header(root: Control) -> void:
	var head := root.get_child(0) as HBoxContainer
	if head == null:
		return
	head.add_theme_constant_override("separation", T.SP_2)
	var icon_idx := 0
	for child in head.get_children():
		var btn := child as Button
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(T.HIT_HEAD, T.HIT_HEAD)
		_apply_button_skin(btn, 0)
		if icon_idx < HEADER_ICONS.size():
			UiIcon.into_button(btn, HEADER_ICONS[icon_idx], 20, T.c(T.INK1))
		icon_idx += 1

# ---------- строка ресурсов: KPI-чип эфира + равные веса «Дом/Лавка» ----------
static func _restyle_resource_row(root: Control) -> void:
	var row := root.get_child(1) as HBoxContainer
	if row == null:
		return
	row.add_theme_constant_override("separation", T.SP_2)
	var bolt := UiIcon.make("bolt", 18, T.c(T.ACCENT))
	row.add_child(bolt)
	row.move_child(bolt, 0)
	var labels := ["Дом", "Лавка"]
	var icons := ["home", "bag"]
	var li := 0
	for child in row.get_children():
		var btn := child as Button
		if btn == null or li >= 2:
			continue
		btn.custom_minimum_size = Vector2(96, 40)
		_apply_button_skin(btn, 0)
		_icon_label(btn, icons[li], labels[li])
		li += 1

static func _icon_label(btn: Button, icon: String, text: String) -> void:
	btn.text = ""
	var old := btn.get_node_or_null("IconLabel")
	if old != null:
		old.queue_free()
	var center := CenterContainer.new()
	center.name = "IconLabel"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	hbox.add_child(UiIcon.make(icon, 16, T.c(T.INK1)))
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", int(T.T_BTN_SM[0]))
	lbl.add_theme_color_override("font_color", T.c(T.INK1))
	var f := UiTheme.font(2)
	if f != null:
		lbl.add_theme_font_override("font", f)
	hbox.add_child(lbl)
	center.add_child(hbox)
	btn.add_child(center)

# ---------- вкладки: иконки разделов ----------
static func _tab_icons(root: Control) -> void:
	var tabs := root.get_node_or_null("Tabs") as TabContainer
	if tabs == null:
		return
	for i in mini(tabs.get_tab_count(), TAB_ICONS.size()):
		var tex := UiIcon.texture(TAB_ICONS[i])
		if tex != null:
			tabs.set_tab_icon(i, tex)

# ---------- общая обвязка кнопки токенами ----------
static func _apply_button_skin(btn: Button, kind: int) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(st, UiStyle.button(kind, st))
	btn.add_theme_stylebox_override("focus", UiStyle.button_focus())
	var fg := T.c(T.INK1)
	if kind == 1:
		fg = T.c(T.ACCENT_INK)
	elif kind == 2:
		fg = T.c(T.GOLD_INK)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)

## Бейдж доступных улучшений: пилюля вместо «▲N» в тексте кнопки (UX-02).
static func set_upgrades_badge(btn: Button, count: int) -> void:
	if btn == null:
		return
	UiIcon.badge(btn, count)
	if UiTheme.enabled:
		btn.text = ""
		if btn.get_node_or_null("IconCenter") == null:
			UiIcon.into_button(btn, "trend_up", 20, T.c(T.INK1))
