class_name UiBootstrap
extends RefCounted
## Точка подключения оставшейся части редизайна: меню вкладок (pill-сегмент
## с иконками) и сет иконок. Вызывается один раз из Game._build_ui().
## Всё остальное оформление — исходное, до следующей итерации.

const TAB_ICONS := ["flask", "cauldron", "globe", "home", "trophy", "sliders"]

const HEADER_ICONS := ["star", "trend_up", "volume", "book"]

static func apply(game: Control) -> void:
	if not UiTheme.enabled or game == null:
		return
	game.theme = UiTheme.build()
	var root := game.get_node_or_null("Margin/Root") as Control
	if root == null:
		return
	_restyle_header(root)
	var tabs := root.get_node_or_null("Tabs") as TabContainer
	if tabs == null:
		return
	for i in mini(tabs.get_tab_count(), TAB_ICONS.size()):
		var tex := UiIcon.texture(TAB_ICONS[i], true)
		if tex != null:
			tabs.set_tab_icon(i, tex)


# Блок 1, вариант A (согласован по мок-кадру): иконки вместо глифов ✦▲♪Ж,
# тач 44×44. Цвета кнопок игры (gold/secondary) не меняются — только
# содержимое и размер. Бейдж счётчика — UiIcon.badge (исправленная пилюля).
static func _restyle_header(root: Control) -> void:
	var head := root.get_child(0) as HBoxContainer
	if head == null:
		return
	head.add_theme_constant_override("separation", 6)
	var kids := head.get_children()
	# порядок нод шапки: title, quests, up, sound, log, me
	for i in range(1, mini(kids.size(), 6)):
		var btn := kids[i] as Button
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(44, 44)
		if i - 1 < HEADER_ICONS.size():
			var gold := i == 1
			UiIcon.into_button(btn, HEADER_ICONS[i - 1], 20,
				DesignTokens.c(DesignTokens.GOLD_INK) if gold else DesignTokens.c(DesignTokens.INK1))
