class_name UiBootstrap
extends RefCounted
## Точка подключения оставшейся части редизайна: меню вкладок (pill-сегмент
## с иконками) и сет иконок. Вызывается один раз из Game._build_ui().
## Всё остальное оформление — исходное, до следующей итерации.

const TAB_ICONS := ["flask", "cauldron", "globe", "home", "trophy", "sliders"]

static func apply(game: Control) -> void:
	if not UiTheme.enabled or game == null:
		return
	game.theme = UiTheme.build()
	var root := game.get_node_or_null("Margin/Root") as Control
	if root == null:
		return
	var tabs := root.get_node_or_null("Tabs") as TabContainer
	if tabs == null:
		return
	for i in mini(tabs.get_tab_count(), TAB_ICONS.size()):
		var tex := UiIcon.texture(TAB_ICONS[i], true)
		if tex != null:
			tabs.set_tab_icon(i, tex)
