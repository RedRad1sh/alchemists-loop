extends VBoxContainer
class_name WorkshopView
## Экран Мастерской: живая сцена станций, вкладки линий, карточка выбранной
## линии (текущее задание на записке, очередь, новое задание плитками) и
## свёрнутые улучшения. Логика команд — Workshop; здесь только отображение.

const WorkshopSceneScript = preload("res://game/lab/workshop_scene.gd")
const Kit = preload("res://game/ui/menu_kit.gd")
const NOTE_PATCH := 21
const NOTE_PAD := 27
const TILE_MIN_W := 96.0

var g: Game
var workshop: Workshop
var _cards: Array = []
var _drafts: Array = []
var _refresh_pending := false
var _refreshing := false
var _stale_while_hidden := false
var _poll_seconds := 0.0
var _anim_seconds := 0.0
var _live_hash := 0
var _status := ""
var _experiment_needed := false
var _selected_line := 0
## Раздел экрана: «lines» — сцена и очередь, «compose» — новое задание,
## «equip» — оборудование. Разделы не складываются в одно полотно.
var _section := "lines"
var _section_buttons := {}
var _scene: Control
var _tabs: HBoxContainer
var _tab_buttons: Array[Button] = []
var _heading: Label
var _mastery: Label
var _mastery_bar: ProgressBar
var _equipment_orbs: HFlowContainer
var _autonomy_orbs: HFlowContainer
var _equipment: Label
var _equipment_reason: Label
var _autonomy: Label
var _autonomy_reason: Label
var _seal: Label
var _wallet: Label
var _command_status: Label
var _buy_equipment: Button
var _buy_autonomy: Button
var _plan_rank: Button
var _plan_autonomy: Button
var _experiment: Button
var _lines_box: VBoxContainer
var _upgrades: VBoxContainer
var _upgrades_toggle: Button
var _guide_toggle: Button
var _guide_steps: VBoxContainer
var _guide_hint: Label
var _guide_buttons: Array[Button] = []
var _guide_step := 0
var _guide_line := 0

func setup(game: Game, model: Workshop) -> void:
	_disconnect_model()
	g = game
	workshop = model
	if _cards.is_empty():
		_build()
	_connect_model()
	refresh()

func refresh() -> void:
	_refresh_pending = false
	_stale_while_hidden = false
	if not is_instance_valid(g) or workshop == null or is_queued_for_deletion() or _cards.is_empty():
		return
	_refreshing = true
	while _cards.size() < workshop.line_count():
		_build_card(_cards.size())
	var rules: Dictionary = Workshop.Rules.RANKS[workshop.rank]
	var next := workshop.rank + 1
	_mastery.text = "%s · мастерство %d" % [rules["name"], workshop.xp]
	if next < Workshop.Rules.RANKS.size():
		var upgrade: Dictionary = Workshop.Rules.RANKS[next]
		_mastery.text += " / %d до ранга «%s»" % [upgrade["xp"], upgrade["name"]]
		var prev_xp := int(rules["xp"])
		_mastery_bar.max_value = maxf(1.0, float(int(upgrade["xp"]) - prev_xp))
		_mastery_bar.value = clampf(float(workshop.xp - prev_xp), 0.0, _mastery_bar.max_value)
		_mastery_bar.visible = true
		_equipment.text = "Для постройки:\n%s" % _recipe_text(upgrade)
		_refresh_material_orbs(_equipment_orbs, upgrade.get("materials", {}))
		_equipment_reason.text = String(workshop.rank_availability(next).get("reason", ""))
		_buy_equipment.text = "Построить: %d линии · очередь по %d" % [upgrade["lines"], upgrade["capacity"]]
	else:
		_mastery_bar.visible = false
		_equipment.text = "Оборудование полностью построено."
		_refresh_material_orbs(_equipment_orbs, {})
		_equipment_reason.text = ""
	_mastery.tooltip_text = "Создавай вещества, чтобы набирать мастерство. При постройке оно не расходуется."
	var autonomy_next := workshop.autonomy_level + 1
	_autonomy.text = "Работа без тебя: до %d этапов на линию" % workshop.offline_stage_limit()
	if autonomy_next < Workshop.Rules.AUTONOMY.size():
		var upgrade: Dictionary = Workshop.Rules.AUTONOMY[autonomy_next]
		_autonomy.text += "\nУлучшение: до %d этапов\n%s" % [upgrade["stages"], _recipe_text(upgrade)]
		_refresh_material_orbs(_autonomy_orbs, upgrade.get("materials", {}))
		_autonomy_reason.text = String(workshop.autonomy_availability().get("reason", ""))
	else:
		_refresh_material_orbs(_autonomy_orbs, {})
		_autonomy_reason.text = "Автономность улучшена до предела."
	_seal.text = "Архивная печать: %d операций за этап (3/4/5)" % g._engine._stage_ops()
	_seal.tooltip_text = "Печать улучшается отдельно от оборудования мастерской. Ранг печати: %d." % g._engine.mastery_rank
	_wallet.text = "Доступно эфира: %d" % g._engine._available_ether()
	_wallet.tooltip_text = "%d активного + %d резерва. Списывается по мере работы; очередь не резервирует ресурсы." % [g._engine.ether, g._engine.ether_overflow]
	_upgrades_toggle.tooltip_text = "%s · %d линии" % [rules["name"], rules["lines"]]
	var locked := not workshop.unlocked or workshop.is_read_only()
	_buy_equipment.disabled = locked or next >= Workshop.Rules.RANKS.size()
	_buy_autonomy.disabled = locked or autonomy_next >= Workshop.Rules.AUTONOMY.size()
	# Shortage commands remain actionable and explain their current failure.
	# Planning does not inherit the XP/ether gate of equipment purchases.
	_plan_rank.disabled = locked or next >= Workshop.Rules.RANKS.size()
	_plan_autonomy.disabled = locked or autonomy_next >= Workshop.Rules.AUTONOMY.size()
	var known := _known_targets()
	for i in _cards.size():
		_refresh_card(i, known, locked)
	_command_status.text = _status
	if locked and _status.is_empty():
		_command_status.text = "Сохранена новая версия Мастерской: обнови игру." if workshop.is_read_only() else "Мастерская откроется после Человека."
	_command_status.visible = not _command_status.text.is_empty()
	_experiment.visible = _experiment_needed or known.is_empty() or _needs_recipe_navigation()
	for button in _guide_buttons:
		button.disabled = locked or known.is_empty()
	(_section_buttons["compose"] as Button).disabled = locked or known.is_empty()
	if _line_for_card(_selected_line).is_empty():
		_selected_line = 0
	_sync_selection()
	_update_guide()
	_animate_cards()
	_live_hash = _resource_hash()
	_refreshing = false

## Известные цели производства: от простых к сложным, как в книге рецептов.
func _known_targets() -> Array[String]:
	var known: Array[String] = []
	for item in g.ITEMS:
		if workshop.known_target_recipe(String(item)):
			known.append(String(item))
	known.sort_custom(func(x: String, y: String) -> bool:
		var lx: int = g._engine._layer_of(x)
		var ly: int = g._engine._layer_of(y)
		if lx != ly:
			return lx < ly
		return x < y)
	return known

func _build() -> void:
	name = "WorkshopView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.name = "WorkshopTopBar"
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var purse := PanelContainer.new()
	purse.name = "EtherPurse"
	purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purse.add_theme_stylebox_override("panel", _well_style(Vector4(12, 6, 12, 6)))
	bar.add_child(purse)
	var purse_row := HBoxContainer.new()
	purse_row.add_theme_constant_override("separation", 8)
	purse_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse.add_child(purse_row)
	purse_row.add_child(UIIcon.make("hud_ether_crystal", 22, UIStyle.BRASS_HI))
	_wallet = _label(purse_row, "EtherWallet", "", 15)
	_wallet.autowrap_mode = TextServer.AUTOWRAP_OFF
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wallet.add_theme_color_override("font_color", UIStyle.PAPER_HI)
	_wallet.mouse_filter = Control.MOUSE_FILTER_PASS
	_guide_toggle = _button(bar, "GuideToggle", "Показать по шагам", _toggle_guide)
	_guide_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	_guide_toggle.custom_minimum_size = Vector2(48, 48)
	_guide_toggle.tooltip_text = "Показать по шагам"
	UIIcon.into_button(_guide_toggle, "info", 22, UIStyle.CREAM)
	_guide_steps = VBoxContainer.new()
	_guide_steps.name = "GuideSteps"
	_guide_steps.add_theme_constant_override("separation", 8)
	add_child(_guide_steps)
	var steps := HBoxContainer.new()
	_guide_steps.add_child(steps)
	_guide_buttons.append(_button(steps, "GuideRecipe", "1. Рецепт", _show_guide_step.bind(0)))
	_guide_buttons.append(_button(steps, "GuideAmount", "2. Количество", _show_guide_step.bind(1)))
	_guide_buttons.append(_button(steps, "GuideQueue", "3. Очередь", _show_guide_step.bind(2)))
	_guide_hint = _label(_guide_steps, "GuideHint", "", 14)
	_guide_hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_guide_steps.hide()
	_command_status = _label(self, "CommandStatus", "", 14)
	_command_status.add_theme_color_override("font_color", UIStyle.HIGHLIGHT)
	_experiment = _button(self, "OpenExperiment", "Открыть новый рецепт в Эксперименте", _open_experiment)
	var sections := HBoxContainer.new()
	sections.name = "WorkshopSections"
	sections.add_theme_constant_override("separation", 6)
	add_child(sections)
	_section_buttons["lines"] = _button(sections, "SectionLines", "Линии", _show_section.bind("lines"))
	_section_buttons["compose"] = _button(sections, "SectionCompose", "Новое задание", _show_section.bind("compose"))
	sections.resized.connect(_fit_row.bind(sections))
	_scene = WorkshopSceneScript.new()
	_scene.call("setup", g)
	_scene.connect("station_pressed", _select_line)
	add_child(_scene)
	_tabs = HBoxContainer.new()
	_tabs.name = "LineTabs"
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	_lines_box = VBoxContainer.new()
	_lines_box.name = "ProductionLines"
	_lines_box.add_theme_constant_override("separation", 0)
	add_child(_lines_box)
	# Placeholder'ы рангов сохраняют стабильные LineCard_1..4; refresh выше
	# достраивает дополнительные карточки уже по фактическому line_count().
	for index in maxi(workshop.line_count(), Workshop.Rules.RANKS.size()):
		_build_card(index)
	_upgrades_toggle = _button(sections, "ToggleUpgrades", "Улучшения", _toggle_upgrades)
	_section_buttons["equip"] = _upgrades_toggle
	var upgrades_panel := PanelContainer.new()
	upgrades_panel.name = "UpgradesPanel"
	upgrades_panel.add_theme_stylebox_override("panel", UIStyle.panel())
	add_child(upgrades_panel)
	_upgrades = VBoxContainer.new()
	_upgrades.name = "WorkshopUpgrades"
	_upgrades.add_theme_constant_override("separation", 10)
	upgrades_panel.add_child(_upgrades)
	_upgrades.visibility_changed.connect(func() -> void: upgrades_panel.visible = _upgrades.visible)
	_heading = _label(_upgrades, "MasteryHeading", "Мастерство Мастерской", 20)
	_heading.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	_mastery = _label(_upgrades, "MasteryInfo", "", 15)
	_mastery_bar = _progress_bar("MasteryProgress", 14.0)
	_upgrades.add_child(_mastery_bar)
	_dim(_label(_upgrades, "MasteryHint", "Создавай вещества — мастерство растёт, открывая новое оборудование.", 13))
	_upgrades.add_child(_divider())
	_equipment = _label(_upgrades, "EquipmentRecipe", "", 14)
	_equipment_orbs = _orb_flow(_upgrades, "EquipmentOrbs")
	_equipment_reason = _dim(_label(_upgrades, "EquipmentAvailability", "", 13))
	_buy_equipment = _button(_upgrades, "BuyEquipment", "Построить оборудование", _buy_rank, 1)
	_plan_rank = _button(_upgrades, "PlanRankMaterials", "Изготовить недостающие материалы", _plan_materials.bind("rank"))
	_upgrades.add_child(_divider())
	var autonomy_head := _label(_upgrades, "AutonomyHeading", "Работа в отсутствие игрока", 18)
	autonomy_head.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	_autonomy = _label(_upgrades, "AutonomyInfo", "", 14)
	_autonomy_orbs = _orb_flow(_upgrades, "AutonomyOrbs")
	_autonomy_reason = _dim(_label(_upgrades, "AutonomyAvailability", "", 13))
	_buy_autonomy = _button(_upgrades, "BuyAutonomy", "Продлить работу без меня", _buy_autonomy_command, 1)
	_plan_autonomy = _button(_upgrades, "PlanAutonomyMaterials", "Изготовить материалы улучшения", _plan_materials.bind("autonomy"))
	_seal = _dim(_label(_upgrades, "ArchiveSeal", "", 13))
	# Длинные команды оборудования переносятся по словам: в вертикальном
	# столбце перенос не схлопывает кнопку, а ширину страницы держит экран.
	for wide in [_buy_equipment, _plan_rank, _buy_autonomy, _plan_autonomy]:
		wide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wide.custom_minimum_size.x = 0
	_upgrades.hide()
	upgrades_panel.hide()
	_fit_row(sections)
	_apply_section()
	var tail := Control.new()
	tail.name = "BottomSpacer"
	tail.custom_minimum_size = Vector2(0, 16)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tail)

func _toggle_upgrades() -> void:
	_show_section("lines" if _section == "equip" else "equip")

## Разделы экрана как вкладки Реторты: видна одна страница, а не всё сразу.
func _show_section(key: String) -> void:
	_section = key
	_apply_section()
	refresh()

func _apply_section() -> void:
	if _upgrades == null:
		return
	_upgrades.visible = _section == "equip"
	_scene.visible = _section == "lines"
	_tabs.visible = _section != "equip"
	_lines_box.visible = _section != "equip"
	for ui in _cards:
		var on_lines := _section == "lines"
		(ui["composer"] as Control).visible = _section == "compose"
		(ui["queue"] as Control).visible = on_lines
		# Новое задание открывается вкладкой раздела; дубль в карточке не нужен.
		(ui["new_job"] as Control).visible = false
		(ui["details_toggle"] as Control).visible = on_lines
		if not on_lines:
			(ui["note"] as Control).visible = false
			(ui["queue_head"] as Control).visible = false
			(ui["details"] as Control).visible = false
	for k in _section_buttons:
		_mark(_section_buttons[k], k == _section)

func _toggle_guide() -> void:
	_guide_steps.visible = not _guide_steps.visible
	_guide_toggle.tooltip_text = "Скрыть подсказки" if _guide_steps.visible else "Показать по шагам"
	_update_guide()

func _show_guide_step(step: int) -> void:
	_guide_step = step
	_select_line(_guide_line)
	_set_composer(_guide_line, true)
	_update_guide()
	var control := _guide_control(_guide_line, step)
	if control == null:
		return
	control.grab_focus()
	var ancestor := get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible(control)

## Шаг подсказки указывает на настоящий элемент: плитку рецепта, режим, кнопку.
func _guide_control(index: int, step: int) -> Control:
	var ui: Dictionary = _cards[index]
	if step == 0:
		var tiles: Dictionary = ui["tiles"]
		var target := String(_drafts[index]["target"])
		if tiles.has(target):
			return tiles[target]
		return null if tiles.is_empty() else tiles.values()[0]
	if step == 1:
		return ui["mode_stock"] if _drafts[index]["mode"] == "stock" else ui["mode_batch"]
	return ui["add"]

func _update_guide() -> void:
	var draft: Dictionary = _drafts[_guide_line]
	var prefix := "Линия %d. " % (_guide_line + 1)
	if not workshop.unlocked or workshop.is_read_only():
		_guide_hint.text = _command_status.text
	elif not workshop.known_target_recipe(String(draft["target"])):
		_guide_hint.text = "Открой рецепт в Эксперименте — затем его можно будет производить здесь."
	elif _guide_step == 0:
		_guide_hint.text = prefix + "Выбери, что изготовить. Здесь только уже открытые рецепты."
	elif _guide_step == 1:
		_guide_hint.text = prefix + "«Изготовить» делает новую партию. «Держать запас» пополняет вещество после расхода. Укажи количество справа."
	elif _guide_step == 2:
		var goal := "Изготовить %d шт." % draft["amount"] if draft["mode"] == "batch" else "Поддерживать %d шт. в общем запасе." % draft["amount"]
		_guide_hint.text = prefix + goal + " Нажми «Добавить в очередь». Ресурсы списываются по мере работы."
	else:
		var line := _line_for_card(_guide_line)
		if line.get("queue", []).is_empty():
			_guide_hint.text = prefix + "Задание снято. Нажми «Добавить в очередь», чтобы снова запустить линию."
		elif line.get("paused", false):
			_guide_hint.text = prefix + "Задание добавлено. Нажми «Продолжить», когда захочешь запустить линию."
		else:
			_guide_hint.text = prefix + "Задание добавлено. Мастерская работает сама; результат появится в инвентаре."

## Вкладка и страница линии; карточка внутри страницы видна, только пока линия
## существует, страница — пока линия выбрана.
func _build_card(index: int) -> void:
	var suffix := "line_%d" % (index + 1)
	var tab := _button(_tabs, "LineTab_%d" % (index + 1), WorkshopSceneScript.roman(index), _select_line.bind(index))
	tab.toggle_mode = true
	tab.custom_minimum_size = Vector2(56, 48)
	if _tabs.get_child_count() == 1:
		_tabs.resized.connect(_fit_row.bind(_tabs))
	_tab_buttons.append(tab)
	var page := VBoxContainer.new()
	page.name = "LinePage_%d" % (index + 1)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines_box.add_child(page)
	var card := PanelContainer.new()
	card.name = "LineCard_%d" % (index + 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", g._panel_style(UIStyle.PANEL, 16))
	page.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var info := _label(head, "LineInfo_%d" % (index + 1), "", 16)
	info.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pause := _button(head, "Pause_" + suffix, "Пауза", _pause_line.bind(index))
	pause.size_flags_horizontal = Control.SIZE_SHRINK_END
	pause.add_theme_font_size_override("font_size", 14)
	# Текущее задание — записка на бумаге: орб цели, полоса этапа, состояние.
	var note := PanelContainer.new()
	note.name = "JobNote_" + suffix
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_stylebox_override("panel", _paper_style())
	box.add_child(note)
	var note_box := VBoxContainer.new()
	note_box.add_theme_constant_override("separation", 6)
	note.add_child(note_box)
	var craft_row := HBoxContainer.new()
	craft_row.name = "CraftRow_" + suffix
	craft_row.add_theme_constant_override("separation", 10)
	note_box.add_child(craft_row)
	var orb_holder := Control.new()
	orb_holder.name = "CraftOrb_" + suffix
	orb_holder.custom_minimum_size = Vector2(48, 48)
	orb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_row.add_child(orb_holder)
	var craft_col := VBoxContainer.new()
	craft_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_col.alignment = BoxContainer.ALIGNMENT_CENTER
	craft_col.add_theme_constant_override("separation", 4)
	craft_row.add_child(craft_col)
	var craft_status := _ink(_label(craft_col, "CraftStatus_" + suffix, "", 17))
	craft_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	craft_status.clip_text = true
	var progress := _progress_bar("CraftProgress_" + suffix, 16.0)
	progress.max_value = 1.0
	craft_col.add_child(progress)
	var state := _ink(_label(note_box, "LineState_%d" % (index + 1), "", 14))
	# Очередь: латунные гнёзда с орбом, подписью и короткими действиями.
	var queue_head := _dim(_label(box, "QueueLabel_" + suffix, "Очередь", 14))
	var queue := VBoxContainer.new()
	queue.name = "Queue_" + suffix
	queue.add_theme_constant_override("separation", 6)
	box.add_child(queue)
	var new_job := _button(box, "NewJob_" + suffix, "Новое задание", _toggle_composer.bind(index), 1)
	# Новое задание: плитки рецептов, режим, количество, оценка и запуск.
	var composer := VBoxContainer.new()
	composer.name = "Composer_" + suffix
	composer.add_theme_constant_override("separation", 8)
	box.add_child(composer)
	_dim(_label(composer, "RecipeLabel_" + suffix, "Что изготовить", 14))
	var grid := GridContainer.new()
	grid.name = "Recipes_" + suffix
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.add_child(grid)
	grid.resized.connect(_fit_grid.bind(grid))
	_dim(_label(composer, "AmountLabel_" + suffix, "Сколько и как производить", 14))
	var modes := HBoxContainer.new()
	modes.name = "Mode_" + suffix
	modes.add_theme_constant_override("separation", 6)
	composer.add_child(modes)
	var group := ButtonGroup.new()
	var mode_batch := _button(modes, "ModeBatch_" + suffix, "Изготовить", _set_mode.bind(index, "batch"))
	var mode_stock := _button(modes, "ModeStock_" + suffix, "Держать запас", _set_mode.bind(index, "stock"))
	for b in [mode_batch, mode_stock]:
		(b as Button).toggle_mode = true
		(b as Button).button_group = group
	modes.resized.connect(_fit_row.bind(modes))
	var stepper := HBoxContainer.new()
	stepper.name = "Stepper_" + suffix
	stepper.add_theme_constant_override("separation", 6)
	composer.add_child(stepper)
	var minus := _button(stepper, "AmountMinus_" + suffix, "−", _step_amount.bind(index, -1))
	minus.custom_minimum_size = Vector2(56, 48)
	minus.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var amount_box := PanelContainer.new()
	amount_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_box.add_theme_stylebox_override("panel", _well_style(Vector4(8, 4, 8, 4)))
	stepper.add_child(amount_box)
	var amount := _label(amount_box, "Amount_" + suffix, "1", 20)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount.add_theme_color_override("font_color", UIStyle.PAPER_HI)
	var plus := _button(stepper, "AmountPlus_" + suffix, "+", _step_amount.bind(index, 1))
	plus.custom_minimum_size = Vector2(56, 48)
	plus.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var most := _button(stepper, "AmountMax_" + suffix, "Макс", _max_amount.bind(index))
	most.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var mode_hint := _dim(_label(composer, "ModeHint_" + suffix, "", 13))
	var quote := _label(composer, "Quote_" + suffix, "", 15)
	quote.add_theme_color_override("font_color", UIStyle.PAPER_HI)
	var add := _button(composer, "Add_" + suffix, "Добавить в очередь", _add_job.bind(index), 2)
	composer.hide()
	var details_toggle := _button(box, "Details_" + suffix, "Скорость и бонусы", _toggle_line_details.bind(index))
	var details := _dim(_label(box, "LineDetails_%d" % (index + 1), "", 13))
	details.hide()
	_cards.append({"card": card, "page": page, "tab": tab, "info": info, "state": state, "pause": pause,
		"note": note, "queue_head": queue_head, "queue": queue, "new_job": new_job, "composer": composer,
		"grid": grid, "tiles": {}, "stock_labels": {}, "mode_batch": mode_batch, "mode_stock": mode_stock,
		"amount": amount, "minus": minus, "plus": plus, "max": most,
		"mode_hint": mode_hint, "details": details, "details_toggle": details_toggle,
		"quote": quote, "add": add, "rows": {}, "signature": "", "targets": [], "recipe_needed": false,
		"craft_row": craft_row, "orb_holder": orb_holder, "progress": progress, "craft_status": craft_status,
		"orb_node": null, "orb_target": ""})
	_drafts.append({"target": "", "mode": "batch", "amount": 1})

## Колонки сетки по ширине: плитка не уже TILE_MIN_W, от 3 до 5 в ряд.
func _fit_grid(grid: GridContainer) -> void:
	var w := grid.size.x
	if w <= 0.0:
		return
	var cols := clampi(int(floor((w + 6.0) / (TILE_MIN_W + 6.0))), 3, 5)
	if grid.columns != cols:
		grid.columns = cols

func _rebuild_tiles(index: int, known: Array[String]) -> void:
	var ui: Dictionary = _cards[index]
	var grid: GridContainer = ui["grid"]
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var tiles := {}
	var stock_labels := {}
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for item in known:
		var tile := Button.new()
		tile.name = "Recipe_line_%d_%s" % [index + 1, item]
		tile.toggle_mode = true
		tile.button_group = group
		tile.custom_minimum_size = Vector2(0, 100)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.set_meta("item", item)
		tile.tooltip_text = g._online._item_name(item)
		UIStyle.style_cell(tile, false, 0.9)
		# Выбранная плитка — латунная кромка, как у активной вкладки комнаты.
		var lit := UIStyle.box(Color(UIStyle.BRASS_DIM, 0.28), UIStyle.BRASS_HI, 10, 2)
		tile.add_theme_stylebox_override("pressed", lit)
		tile.add_theme_stylebox_override("hover_pressed", lit)
		tile.pressed.connect(_pick_recipe.bind(index, item))
		grid.add_child(tile)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		tile.add_child(col)
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var orb_box := CenterContainer.new()
		orb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(orb_box)
		orb_box.add_child(g._engine._mini_orb(item, 42))
		var title := _label(col, "Name", g._online._item_name(item), 13)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.add_theme_color_override("font_color", UIStyle.CREAM)
		var stock := _label(col, "Stock", "", 12)
		stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stock.autowrap_mode = TextServer.AUTOWRAP_OFF
		stock.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		tiles[item] = tile
		stock_labels[item] = stock
	ui["tiles"] = tiles
	ui["stock_labels"] = stock_labels
	_fit_grid(grid)

## Выбранный переключатель — латунь, остальные — дерево (как вкладки игры).
func _mark(button: Button, chosen: bool) -> void:
	button.set_pressed_no_signal(chosen)
	if bool(button.get_meta("chosen", not chosen)) != chosen:
		button.set_meta("chosen", chosen)
		UIStyle.style_button(button, 1 if chosen else 0)
		# Нажатое состояние совпадает с обычным: выбор показывает материал.
		button.add_theme_stylebox_override("pressed", button.get_theme_stylebox("normal"))
		button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("hover"))
		_soft_disabled(button)

## Недоступная кнопка блекнет на своём материале: тёмная выглядела нажатой,
## а знак на ней пропадал.
func _soft_disabled(button: Button) -> void:
	var normal := button.get_theme_stylebox("normal")
	if normal is StyleBoxTexture:
		var faded := (normal as StyleBoxTexture).duplicate() as StyleBoxTexture
		faded.modulate_color = Color(0.8, 0.78, 0.76, 0.7)
		button.add_theme_stylebox_override("disabled", faded)
	button.add_theme_color_override("font_disabled_color", Color(UIStyle.CREAM, 0.55))

func _fit_row(row: Control) -> void:
	var narrow := row.get_viewport_rect().size.x < 420.0 if row.is_inside_tree() else false
	for child in row.get_children():
		var b := child as Button
		if b == null:
			continue
		b.add_theme_font_size_override("font_size", 14 if narrow else 16)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size.x = 48

func _toggle_composer(index: int) -> void:
	_set_composer(index, _section != "compose")

func _set_composer(index: int, open: bool) -> void:
	if index != _selected_line:
		_select_line(index)
	_section = "compose" if open else "lines"
	_apply_section()

func _select_line(index: int) -> void:
	if index < 0 or index >= _cards.size() or _line_for_card(index).is_empty():
		_sync_selection()
		return
	_selected_line = index
	_guide_line = index
	_sync_selection()
	_update_guide()

func _sync_selection() -> void:
	for i in _cards.size():
		var ui: Dictionary = _cards[i]
		(ui["page"] as Control).visible = i == _selected_line
		var tab: Button = ui["tab"]
		_mark(tab, i == _selected_line)
	_push_scene()

## Станции сцены: состояние, цель и доля этапа каждой линии, включая закрытые.
func _push_scene() -> void:
	if not is_instance_valid(_scene) or workshop == null:
		return
	var data: Array = []
	var count := maxi(workshop.line_count(), Workshop.Rules.RANKS.size())
	var locked := not workshop.unlocked or workshop.is_read_only()
	for i in mini(count, _cards.size()):
		var line := _line_for_card(i)
		var roman := WorkshopSceneScript.roman(i)
		if locked or line.is_empty():
			var rank_name := String(Workshop.Rules.RANKS[mini(i, Workshop.Rules.RANKS.size() - 1)]["name"])
			data.append({"status": "locked", "target": "", "frac": 0.0, "text": "%s · %s" % [roman, rank_name]})
			continue
		var q: Array = line.get("queue", [])
		if q.is_empty():
			data.append({"status": "empty", "target": "", "frac": 0.0, "text": "%s · свободна" % roman})
			continue
		var job: Dictionary = q[0]
		var target := String(job.get("target", ""))
		var status := "paused_user" if line.get("paused", false) else String(job.get("status", "idle"))
		var interval: float = g._sigil.bench_interval(target)
		var phase := float(line.get("phase_seconds", 0.0))
		var frac := clampf(phase / maxf(interval, 0.001), 0.0, 1.0)
		var text := "%s · %d с" % [roman, maxi(0, int(ceil(interval - phase)))]
		match status:
			"paused_user":
				text = "%s · пауза" % roman
			"waiting_ether":
				text = "%s · нет эфира" % roman
			"waiting_ingredients":
				text = "%s · нет сырья" % roman
			"waiting_recipe":
				text = "%s · нет рецепта" % roman
			"waiting_inventory":
				text = "%s · склад полон" % roman
		data.append({"status": status, "target": target, "frac": frac, "text": text})
	_scene.call("set_stations", data, _selected_line)

## Бумага записки: рваный край paper_note.png держится патчем 21 px при любой
## ширине, поле текста — ещё 6 px (как у записок обмена).
func _paper_style() -> StyleBox:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/contracts/paper_note.png") as Texture2D
	sb.set_texture_margin_all(NOTE_PATCH)
	sb.set_content_margin_all(NOTE_PAD)
	sb.content_margin_top = NOTE_PAD - 4
	sb.content_margin_bottom = NOTE_PAD - 4
	# Прозрачная кромка текстуры (~17 px) выходит за поле карточки: видимая
	# бумага встаёт вровень с остальным содержимым.
	sb.expand_margin_left = 14
	sb.expand_margin_right = 14
	return sb

## Углубление well_slot: кошелёк, счётчик количества, гнёзда очереди.
func _well_style(content: Vector4) -> StyleBox:
	var sb := UITheme.nine("well_slot", Vector4(20, 20, 20, 20), content, Color(1, 1, 1, 0.9))
	if sb != null:
		return sb
	var flat := UIStyle.box(UIStyle.WOOD_DEEP, UIStyle.LINE, 8, 1)
	flat.content_margin_left = content.x
	flat.content_margin_top = content.y
	flat.content_margin_right = content.z
	flat.content_margin_bottom = content.w
	return flat

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(UIStyle.BRASS_DIM, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func _dim(label: Label) -> Label:
	label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	return label

## Текст на бумаге — тёмными чернилами, как в записках доски.
func _ink(label: Label) -> Label:
	label.add_theme_color_override("font_color", UIStyle.PAPER_INK)
	return label

## Полоса из кита HUD: тёмный жёлоб и тёплая заливка; цвет — состояние линии.
func _progress_bar(node_name: String, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := StyleBoxTexture.new()
	track.texture = Kit.texture("03_top_energy_bar_track.png")
	track.set_texture_margin_all(8)
	bar.add_theme_stylebox_override("background", track if track.texture != null else _bar_style(UIStyle.PANEL_HI))
	bar.add_theme_stylebox_override("fill", _fill_style(Color.WHITE))
	return bar

func _fill_style(tint: Color) -> StyleBox:
	var tex := Kit.texture("04_top_energy_bar_fill.png")
	if tex == null:
		return _bar_style(tint)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(6)
	sb.set_expand_margin_all(-2)
	sb.modulate_color = tint
	return sb

func _bar_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(5)
	return sb

func _orb_flow(parent: Node, node_name: String) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = node_name
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	return flow

func _refresh_material_orbs(container: HFlowContainer, materials: Dictionary) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	container.visible = not materials.is_empty()
	for item in materials:
		_orb_need(container, String(item), int(materials[item]))

## Орб материала с подписью «есть/нужно»; нехватка — красным.
func _orb_need(parent: Node, item_id: String, need: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	row.add_child(g._engine._mini_orb(item_id, 32))
	var have := int(g._engine.inventory.get(item_id, 0))
	var lbl := g._label("%d/%d" % [have, need], 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.tooltip_text = g._online._item_name(item_id)
	lbl.add_theme_color_override("font_color", UIStyle.DANGER if have < need else UIStyle.TEXT_DIM)
	row.add_child(lbl)

## Тон заливки этапа: тёплая латунь — работа, приглушённые тона — ожидание.
static func _status_color(status: String) -> Color:
	match status:
		"running":
			return Color.WHITE
		"paused_user":
			return Color(0.62, 0.58, 0.55)
		"waiting_ether":
			return Color(0.85, 0.72, 0.5)
		"waiting_ingredients", "waiting_recipe", "waiting_inventory":
			return Color(0.95, 0.5, 0.42)
		_:
			return Color(0.7, 0.66, 0.6)

## Полоса этапа, орб цели и станции сцены; ~15 раз в секунду из _process.
func _animate_cards() -> void:
	if not is_instance_valid(g) or workshop == null:
		return
	for i in _cards.size():
		var ui: Dictionary = _cards[i]
		var line := _line_for_card(i)
		var q: Array = line.get("queue", [])
		var note: Control = ui["note"]
		note.visible = not q.is_empty() and _section == "lines"
		if q.is_empty():
			continue
		var job: Dictionary = q[0]
		var target := String(job.get("target", ""))
		var status := "paused_user" if line.get("paused", false) else String(job.get("status", "idle"))
		var interval: float = g._sigil.bench_interval(target)
		var frac := clampf(float(line.get("phase_seconds", 0.0)) / maxf(interval, 0.001), 0.0, 1.0)
		var bar: ProgressBar = ui["progress"]
		bar.value = frac
		if String(bar.get_meta("status", "")) != status:
			bar.set_meta("status", status)
			bar.add_theme_stylebox_override("fill", _fill_style(_status_color(status)))
		var holder: Control = ui["orb_holder"]
		if ui["orb_target"] != target or not is_instance_valid(ui["orb_node"]):
			if is_instance_valid(ui["orb_node"]):
				(ui["orb_node"] as Node).queue_free()
			var orb: Control = g._engine._mini_orb(target, 48)
			holder.add_child(orb)
			orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			orb.pivot_offset = Vector2(24, 24)
			ui["orb_node"] = orb
			ui["orb_target"] = target
		(ui["craft_status"] as Label).text = "%s · %d%%" % [g._online._item_name(target), int(round(frac * 100.0))]
	_push_scene()

func _toggle_line_details(index: int) -> void:
	var ui: Dictionary = _cards[index]
	ui["details"].visible = not ui["details"].visible
	ui["details_toggle"].text = "Скрыть скорость и бонусы" if ui["details"].visible else "Скорость и бонусы"

func _label(parent: Node, node_name: String, text := "", font_size := 16) -> Label:
	var label := g._label(text, font_size)
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 0
	parent.add_child(label)
	return label

## kind: 0 — дерево (второстепенное), 1 — латунь, 2 — главная латунная кнопка.
func _button(parent: Node, node_name: String, text: String, action: Callable, kind := 0) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Autowrap и ellipsis схлопывают минимальную ширину кнопки до отступов stylebox.
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if kind == 2:
		Kit.cta(button)
		button.custom_minimum_size.y = 54
		button.add_theme_font_size_override("font_size", 18)
	else:
		UIStyle.style_button(button, kind)
		_soft_disabled(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _recipe_text(recipe: Dictionary) -> String:
	var pieces := PackedStringArray()
	for item in recipe["materials"]:
		pieces.append("%s ×%d (есть %d)" % [g._online._item_name(item), recipe["materials"][item], g._engine.inventory.get(item, 0)])
	pieces.append("%d эфира" % int(recipe["ether"]))
	return "\n".join(pieces)

func _line_for_card(index: int) -> Dictionary:
	return workshop.lines[index] if index < workshop.line_count() and index < workshop.lines.size() else {}

func _refresh_card(index: int, known: Array[String], locked: bool) -> void:
	var ui: Dictionary = _cards[index]
	var line := _line_for_card(index)
	var unavailable := locked or line.is_empty()
	ui["card"].visible = not unavailable
	var tab: Button = ui["tab"]
	tab.visible = not unavailable
	var q_now: Array = line.get("queue", [])
	var roman := WorkshopSceneScript.roman(index)
	tab.text = roman if q_now.is_empty() else "%s · %s" % [roman, g._online._item_name(String(q_now[0]["target"]))]
	ui["info"].text = "Линия %d · очередь %d/%d" % [index + 1, line.get("queue", []).size(), workshop.queue_capacity()]
	if unavailable:
		ui["info"].text = "Линия %d · Недоступна: %s" % [index + 1,
			"Мастерская закрыта" if locked else "построй ранг «%s»" % Workshop.Rules.RANKS[mini(index, Workshop.Rules.RANKS.size() - 1)]["name"]]
	ui["pause"].visible = not unavailable and not line.get("queue", []).is_empty()
	ui["add"].visible = not unavailable
	ui["add"].disabled = unavailable or known.is_empty()
	ui["new_job"].disabled = unavailable or known.is_empty()
	ui["pause"].disabled = unavailable
	if unavailable:
		ui["recipe_needed"] = false
		ui["state"].text = ""
		_refresh_queue(index, {})
		return
	if ui["targets"] != known:
		ui["targets"] = known.duplicate()
		_rebuild_tiles(index, known)
	if (String(_drafts[index]["target"]).is_empty() or not known.has(String(_drafts[index]["target"]))) and not known.is_empty():
		_drafts[index]["target"] = known[0]
	var target := String(_drafts[index]["target"])
	var tiles: Dictionary = ui["tiles"]
	for item in tiles:
		(tiles[item] as Button).set_pressed_no_signal(item == target)
		var have := int(g._engine.inventory.get(item, 0))
		var stock_label: Label = ui["stock_labels"][item]
		stock_label.text = "есть %d" % have
		stock_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM if have > 0 else UIStyle.TEXT_MUTED)
	_mark(ui["mode_batch"], _drafts[index]["mode"] != "stock")
	_mark(ui["mode_stock"], _drafts[index]["mode"] == "stock")
	(ui["mode_hint"] as Control).visible = _drafts[index]["mode"] == "stock"
	(ui["amount"] as Label).text = str(int(_drafts[index]["amount"]))
	(ui["minus"] as Button).disabled = int(_drafts[index]["amount"]) <= 1
	(ui["plus"] as Button).disabled = int(_drafts[index]["amount"]) >= Game.CRAFT_INVENTORY_STACK_CAP
	var active_target := target
	if not line["queue"].is_empty():
		active_target = String(line["queue"][0]["target"])
	var interval := g._sigil.bench_interval(active_target)
	var speed := "бонус комплекта сигилов ×2" if interval < Game.BENCH_INTERVAL else "базовая скорость"
	var discount := "чертёж −%d%%" % int(round((1.0 - Game.BLUEPRINT_DISCOUNT) * 100.0)) if g._engine._blueprints.has(active_target) else "без скидки чертежа"
	ui["details"].text = "Этап каждые %.1f с · %d операций\n%s · %s" % [interval, g._engine._stage_ops(), speed, discount]
	if known.is_empty():
		ui["state"].text = "Открой рецепт в Эксперименте, чтобы начать."
	elif line["queue"].is_empty():
		ui["state"].text = "Очередь пуста — выбери рецепт ниже."
	elif line["paused"]:
		ui["state"].text = "На паузе — нажми «Продолжить»."
	elif String(line["queue"][0].get("status", "")).begins_with("waiting_"):
		# Обратный отсчёт здесь врал: этап уже готов, но линии нечем работать.
		ui["state"].text = "%s · линия продолжит сама, когда появится нужное" % _status_name(String(line["queue"][0]["status"]))
	else:
		ui["state"].text = "%s · следующий этап через %d с" % [g._online._item_name(active_target), maxi(0, int(ceil(interval - float(line.get("phase_seconds", 0.0)))))]
	ui["pause"].text = "Продолжить" if line["paused"] else "Пауза"
	var empty: bool = line["queue"].is_empty()
	(ui["queue_head"] as Control).visible = not empty and _section == "lines"
	_update_quote(index)
	_refresh_queue(index, line)

func _refresh_queue(index: int, line: Dictionary) -> void:
	var ui: Dictionary = _cards[index]
	var jobs: Array = line.get("queue", [])
	var ids: Array = []
	for job in jobs:
		ids.append(job["id"])
	var signature := JSON.stringify(ids)
	if ui["signature"] != signature:
		ui["signature"] = signature
		ui["rows"].clear()
		for child in ui["queue"].get_children():
			ui["queue"].remove_child(child)
			child.queue_free()
		for job in jobs:
			var id := String(job["id"])
			var slot := PanelContainer.new()
			slot.name = "JobSlot_" + id
			slot.add_theme_stylebox_override("panel", _well_style(Vector4(10, 8, 8, 8)))
			ui["queue"].add_child(slot)
			# На узком экране действия встают отдельной строкой под текстом:
			# иначе три кнопки сжимали подпись в столбец и раздвигали страницу.
			var narrow := get_viewport_rect().size.x < 420.0 if is_inside_tree() else false
			var stack := VBoxContainer.new()
			stack.add_theme_constant_override("separation", 4)
			slot.add_child(stack)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			stack.add_child(row)
			var orb_box := CenterContainer.new()
			orb_box.custom_minimum_size = Vector2(36, 36)
			orb_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			orb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(orb_box)
			orb_box.add_child(g._engine._mini_orb(String(job["target"]), 32))
			var info := _label(row, "JobInfo_" + id, "", 14)
			info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			info.mouse_filter = Control.MOUSE_FILTER_PASS
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 4)
			if narrow:
				actions.alignment = BoxContainer.ALIGNMENT_END
				stack.add_child(actions)
			else:
				row.add_child(actions)
			var up := _icon_button(actions, "Up_" + id, "↑", "chevron_down", _move_job.bind(String(line["id"]), id, -1), true)
			var down := _icon_button(actions, "Down_" + id, "↓", "chevron_down", _move_job.bind(String(line["id"]), id, 1), false)
			_icon_button(actions, "Remove_" + id, "Удалить", "x", _remove_job.bind(String(line["id"]), id), false)
			ui["rows"][id] = {"info": info, "up": up, "down": down}
	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var id := String(job["id"])
		var row: Dictionary = ui["rows"][id]
		var target := String(job["target"])
		var mode := "партия %d/%d" % [job["produced"], job["amount"]] if job["mode"] == "batch" else "поддерживать общий запас %d/%d; произведено %d" % [g._engine.inventory.get(target, 0), job["amount"], job["produced"]]
		row["info"].text = "%d. %s · %s\n%s" % [i + 1, g._online._item_name(target), mode, _status_name(String(job["status"]))]
		row["info"].tooltip_text = "Выполнено операций: %d" % int(job.get("route_operations", 0))
		if not String(job.get("reason", "")).is_empty():
			row["info"].text += "\n" + String(job["reason"])
		row["up"].disabled = i == 0
		row["down"].disabled = i == jobs.size() - 1
		# Иконка недоступной стрелки тает вместе с кнопкой.
		(row["up"] as Control).modulate.a = 0.6 if i == 0 else 1.0
		(row["down"] as Control).modulate.a = 0.6 if i == jobs.size() - 1 else 1.0
		var tone := UIStyle.CREAM if i == 0 else UIStyle.TEXT_DIM
		(row["info"] as Label).add_theme_color_override("font_color", tone)

## Квадратная кнопка с иконкой; подпись остаётся подсказкой и для перевода.
func _icon_button(parent: Node, node_name: String, text: String, icon: String, action: Callable, flip: bool) -> Button:
	var button := _button(parent, node_name, text, action)
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = text
	UIIcon.into_button(button, icon, 18, UIStyle.CREAM)
	if flip:
		var center := button.get_node_or_null("IconCenter") as Control
		if center != null:
			for c in center.get_children():
				(c as TextureRect).flip_v = true
	return button

func _update_quote(index: int) -> void:
	var draft: Dictionary = _drafts[index]
	var stock := int(g._engine.inventory.get(draft["target"], 0))
	_cards[index]["mode_hint"].text = "Новая партия: %d шт." % draft["amount"] if draft["mode"] == "batch" else "Пополнять до %d шт. · сейчас в запасе %d" % [draft["amount"], stock]
	var quote := workshop.job_preview(String(draft["target"]), String(draft["mode"]), int(draft["amount"]))
	var label: Label = _cards[index]["quote"]
	_cards[index]["recipe_needed"] = not quote["ok"] and quote.get("code", "") == "recipe"
	label.tooltip_text = ""
	if not quote["ok"]:
		label.text = String(quote["reason"])
		return
	label.text = "Уже есть нужный запас." if int(quote["units"]) == 0 else "Изготовить %d шт. · примерно %d эфира" % [quote["units"], quote["ether"]]
	label.tooltip_text = "%d операций · следующая: %d эфира. Ресурсы списываются по мере работы; оценка может измениться." % [quote["operations"], quote["next_ether"]]
	if not String(quote["reason"]).is_empty():
		label.text += "\n" + String(quote["reason"])

static func _status_name(status: String) -> String:
	return {"idle": "В очереди", "running": "Производство", "paused_user": "Пауза игрока",
		"waiting_ether": "Ждёт эфира", "waiting_ingredients": "Ждёт ингредиентов",
		"waiting_recipe": "Ждёт открытия рецепта", "waiting_inventory": "Ждёт места в запасе"}.get(status, status)

func _pick_recipe(index: int, item: String) -> void:
	_drafts[index]["target"] = item
	_draft_changed(index, 1)

func _set_mode(index: int, mode: String) -> void:
	_drafts[index]["mode"] = mode
	_draft_changed(index, 2)

func _step_amount(index: int, delta: int) -> void:
	_drafts[index]["amount"] = clampi(int(_drafts[index]["amount"]) + delta, 1, Game.CRAFT_INVENTORY_STACK_CAP)
	_draft_changed(index, 2)

## «Макс»: партия до общего предела стека с учётом запаса, запас — сам предел.
func _max_amount(index: int) -> void:
	var cap := Game.CRAFT_INVENTORY_STACK_CAP
	var have := int(g._engine.inventory.get(String(_drafts[index]["target"]), 0))
	_drafts[index]["amount"] = cap if _drafts[index]["mode"] == "stock" else maxi(1, cap - have)
	_draft_changed(index, 2)

func _draft_changed(index: int, step: int) -> void:
	if _refreshing or is_queued_for_deletion():
		return
	_cards[index]["composer_touched"] = true
	_guide_line = index
	_guide_step = step
	var ui: Dictionary = _cards[index]
	var tiles: Dictionary = ui["tiles"]
	for item in tiles:
		(tiles[item] as Button).set_pressed_no_signal(item == _drafts[index]["target"])
	_mark(ui["mode_batch"], _drafts[index]["mode"] != "stock")
	_mark(ui["mode_stock"], _drafts[index]["mode"] == "stock")
	(ui["mode_hint"] as Control).visible = _drafts[index]["mode"] == "stock"
	(ui["amount"] as Label).text = str(int(_drafts[index]["amount"]))
	(ui["minus"] as Button).disabled = int(_drafts[index]["amount"]) <= 1
	(ui["plus"] as Button).disabled = int(_drafts[index]["amount"]) >= Game.CRAFT_INVENTORY_STACK_CAP
	_update_quote(index)
	_update_guide()
	_experiment.visible = _experiment_needed or _needs_recipe_navigation()

func _needs_recipe_navigation() -> bool:
	for ui in _cards:
		if ui["recipe_needed"]:
			return true
	for line in workshop.lines:
		for job in line["queue"]:
			if job.get("status", "") == "waiting_recipe":
				return true
	return false

func _add_job(index: int) -> void:
	var line := _line_for_card(index)
	if line.is_empty():
		_complete({"ok": false, "reason": "Эта производственная линия недоступна."})
		return
	var result := workshop.enqueue(String(line["id"]), _drafts[index])
	_guide_line = index
	if result.get("ok", false):
		_guide_step = 3
		result["reason"] = "Задание добавлено на линию %d." % (index + 1)
	_complete(result)
	_update_guide()

func _pause_line(index: int) -> void:
	var line := _line_for_card(index)
	var success := not line.is_empty() and workshop.set_line_paused(String(line["id"]), not bool(line["paused"]))
	_complete({"ok": success, "reason": "Состояние линии изменено." if success else "Эта линия недоступна."})

func _remove_job(line_id: String, id: String) -> void:
	var success := workshop.remove_job(line_id, id)
	_complete({"ok": success, "reason": "Задание удалено; произведённые материалы сохранены." if success else "Задание уже недоступно."})

func _move_job(line_id: String, id: String, offset: int) -> void:
	var line := workshop._line(line_id)
	if not line.is_empty():
		for i in line["queue"].size():
			if line["queue"][i]["id"] == id:
				var success := workshop.reorder(line_id, i, i + offset)
				_complete({"ok": success, "reason": "Порядок очереди изменён." if success else "Нельзя переместить задание дальше."})
				return
	_complete({"ok": false, "reason": "Задание уже недоступно."})

func _buy_rank() -> void:
	_complete(workshop.buy_rank(workshop.rank + 1))

func _buy_autonomy_command() -> void:
	_complete(workshop.buy_autonomy())

func _plan_materials(kind: String) -> void:
	_complete(workshop.queue_missing_materials(kind))

func _complete(result: Dictionary) -> void:
	_status = String(result.get("reason", ""))
	_experiment_needed = result.get("code", "") == "recipe"
	if result.get("ok", false):
		if _status.is_empty():
			_status = "Готово."
		if g._engine._resource_mutation_allowed():
			g._saves._save_game()
	_command_status.text = _status
	_command_status.visible = not _status.is_empty()
	_experiment.visible = _experiment_needed or _needs_recipe_navigation()
	_schedule_refresh()

func _open_experiment() -> void:
	if is_instance_valid(g._tabs_ref):
		g._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	g._pages._open_cauldron_screen()

func _schedule_refresh() -> void:
	if _refresh_pending or not is_inside_tree() or is_queued_for_deletion():
		return
	# Активная линия обновляет таймер каждый кадр, поэтому changed приходит
	# каждый кадр. Страницу под другой вкладкой TabContainer видно быть не может,
	# а пересбор подписей ради невидимого кадра стоит реальных кадров: копят
	# накопленное и рисуем одним проходом при первом показе.
	if not is_visible_in_tree():
		_stale_while_hidden = true
		return
	_refresh_pending = true
	call_deferred("refresh")

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and _stale_while_hidden:
		_stale_while_hidden = false
		refresh()

func _connect_model() -> void:
	if workshop != null and is_inside_tree() and not workshop.changed.is_connected(_schedule_refresh):
		workshop.changed.connect(_schedule_refresh)

func _disconnect_model() -> void:
	if workshop != null and workshop.changed.is_connected(_schedule_refresh):
		workshop.changed.disconnect(_schedule_refresh)

func _enter_tree() -> void:
	_connect_model()
	_schedule_refresh()

func _exit_tree() -> void:
	_disconnect_model()
	_refresh_pending = false

func _resource_hash() -> int:
	return hash([g._engine.inventory, g._engine.ether, g._engine.ether_overflow,
		g._engine.mastery_rank, g._engine._blueprints, g._sigil._milestones_claimed])

func _process(delta: float) -> void:
	# Resource arrivals do not always emit Workshop.changed. Poll only their
	# signature, never rebuild queues or write a save every frame.
	_poll_seconds += delta
	_anim_seconds += delta
	if _poll_seconds >= 0.5 and is_instance_valid(g) and workshop != null:
		_poll_seconds = 0.0
		if _live_hash != _resource_hash():
			_schedule_refresh()
	if _anim_seconds >= 0.066:
		_anim_seconds = 0.0
		if is_visible_in_tree():
			_animate_cards()
