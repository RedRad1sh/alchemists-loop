extends RefCounted
class_name HudBar
# Компактный HUD (концепт concepts/ui-lab-main-paging.png): одна строка
# «аватар · эфир-капсула с кап-баром · доход · действия» + строка цели.
# Переиспользует существующие узлы/поля Game, чтобы контракты тестов
# (_me_avatar, _social_btn, _ether_label, _quest_label…) не разъехались.

var g: Game
var cap_bar: ProgressBar = null
var rate_chip: Label = null


func build(game: Game, root: VBoxContainer) -> void:
	g = game
	var row := HBoxContainer.new()
	row.name = "HudRow"
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	# аватар → профиль
	var me_btn := g._header_button(0)
	me_btn.tooltip_text = "Профиль: твоё имя и аватар"
	me_btn.pressed.connect(g._hub._open_profile)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me_btn.add_child(cc)
	g._me_avatar = g._make_avatar(g._online._net_nick, 24)
	cc.add_child(g._me_avatar)
	row.add_child(me_btn)

	# эфир-капсула: крупное золото + тонкий кап-бар
	var capsule := PanelContainer.new()
	capsule.name = "EtherCapsule"
	capsule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capsule.add_theme_stylebox_override("panel",
			UIStyle.box(Color(0.05, 0.08, 0.12, 0.92), UIStyle.GOLD_DIM, 14, 2))
	row.add_child(capsule)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 3)
	ccol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capsule.add_child(ccol)
	g._engine._ether_label = g._label("", 18)
	g._engine._ether_label.add_theme_color_override("font_color", UIStyle.GOLD)
	g._engine._ether_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g._engine._ether_label.clip_text = true
	g._engine._ether_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ccol.add_child(g._engine._ether_label)
	cap_bar = ProgressBar.new()
	cap_bar.custom_minimum_size = Vector2(0, 6)
	cap_bar.show_percentage = false
	cap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.16, 0.2, 0.25, 0.9)
	pb_bg.set_corner_radius_all(3)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.37, 0.89, 0.84, 0.95)
	pb_fill.set_corner_radius_all(3)
	cap_bar.add_theme_stylebox_override("background", pb_bg)
	cap_bar.add_theme_stylebox_override("fill", pb_fill)
	ccol.add_child(cap_bar)

	# доход в секунду — отдельный чип (как «profit per hour» референсов)
	rate_chip = g._label("", 13)
	rate_chip.add_theme_color_override("font_color", UIStyle.TEAL)
	rate_chip.tooltip_text = "Пассивный доход эфира в секунду"
	row.add_child(rate_chip)

	# задания/достижения — золотая звезда
	var quests_btn := g._header_button(2)
	UIIcon.into_button(quests_btn, "star", 24, Color("2a1d05"))
	quests_btn.tooltip_text = "Задания Светика, достижения, комплекты, заказы"
	quests_btn.pressed.connect(g._progress_ui._open_progress_popup)
	row.add_child(quests_btn)

	# Аркан Сигилов — таро-кнопка (в сцену переедет этапом позже)
	var sigil_btn := g._tarot_button()
	g._sigil_header_btn = sigil_btn
	sigil_btn.tooltip_text = "Аркан Сигилов: ежедневные крафты"
	sigil_btn.pressed.connect(g._sigil_ui._open_sigil_modal)
	row.add_child(sigil_btn)

	# улучшения — trend_up (текст-счётчик доступных ставит core._refresh_header)
	var up_icon := UIIcon.texture("trend_up")
	g._hub._up_btn = g._header_button(0)
	if up_icon != null:
		g._hub._up_btn.icon = up_icon
	else:
		g._hub._up_btn.text = "▲"
	g._hub._up_btn.tooltip_text = "Улучшения"
	g._hub._up_btn.pressed.connect(g._hub._open_upgrades)
	row.add_child(g._hub._up_btn)

	# колокольчик — журнал событий
	var log_btn := g._header_button(0)
	UIIcon.into_button(log_btn, "mail", 24)
	log_btn.tooltip_text = "Журнал событий"
	log_btn.pressed.connect(g._hub._open_journal)
	row.add_child(log_btn)

	# сумка — лавка
	var pouch_btn := g._header_button(0)
	UIIcon.into_button(pouch_btn, "bag", 24)
	pouch_btn.tooltip_text = "Лавка: покупки, награды за просмотр и приватность"
	pouch_btn.pressed.connect(g._shop.open)
	row.add_child(pouch_btn)

	# звук
	g._sound_btn = g._header_button(0)
	UIIcon.into_button(g._sound_btn, "volume", 24)
	g._sound_btn.tooltip_text = "Настройки звука"
	g._sound_btn.pressed.connect(g._hub._open_settings)
	row.add_child(g._sound_btn)

	# строка цели: квест-чип + коллекция + быстрые «Дом/Друзья»
	var row2 := HBoxContainer.new()
	row2.name = "GoalRow"
	row2.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row2.add_theme_constant_override("separation", 8)
	root.add_child(row2)
	g._guild._quest_label = Button.new()
	g._guild._quest_label.name = "QuestChip"
	g._guild._quest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g._guild._quest_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	g._guild._quest_label.flat = true
	g._guild._quest_label.add_theme_font_size_override("font_size", 13)
	g._guild._quest_label.add_theme_color_override("font_color", UIStyle.GOLD)
	g._guild._quest_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	g._guild._quest_label.tooltip_text = "Нажми, чтобы открыть задания и достижения"
	g._guild._quest_label.pressed.connect(g._progress_ui._open_progress_popup)
	row2.add_child(g._guild._quest_label)
	g._engine._collection_label = g._label("", 12)
	g._engine._collection_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	g._engine._collection_label.clip_text = true
	g._engine._collection_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row2.add_child(g._engine._collection_label)
	var home_btn := g._small_button("Дом", Vector2(70, 34), 2)
	home_btn.tooltip_text = "Дом Светика: построй домик, обставь его, смени тему и ауру"
	home_btn.pressed.connect(g._home._open_workshop)
	row2.add_child(home_btn)
	g._social_btn = g._small_button("Друзья", Vector2(88, 34), 2)
	g._social_btn.tooltip_text = "Друзья, заявки и личные сообщения"
	g._social_btn.pressed.connect(g._open_social)
	row2.add_child(g._social_btn)
