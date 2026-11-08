extends VBoxContainer
class_name WorkshopView

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
	_upgrades_toggle.text = "Скрыть улучшения" if _upgrades.visible else "Улучшения · %s · %d линии" % [rules["name"], rules["lines"]]
	var locked := not workshop.unlocked or workshop.is_read_only()
	_buy_equipment.disabled = locked or next >= Workshop.Rules.RANKS.size()
	_buy_autonomy.disabled = locked or autonomy_next >= Workshop.Rules.AUTONOMY.size()
	# Shortage commands remain actionable and explain their current failure.
	# Planning does not inherit the XP/ether gate of equipment purchases.
	_plan_rank.disabled = locked or next >= Workshop.Rules.RANKS.size()
	_plan_autonomy.disabled = locked or autonomy_next >= Workshop.Rules.AUTONOMY.size()
	var known: Array[String] = []
	for item in g.ITEMS:
		if workshop.known_target_recipe(String(item)):
			known.append(String(item))
	known.sort()
	for i in _cards.size():
		_refresh_card(i, known, locked)
	_command_status.text = _status
	if locked and _status.is_empty():
		_command_status.text = "Сохранена новая версия Мастерской: обнови игру." if workshop.is_read_only() else "Мастерская откроется после Человека."
	_command_status.visible = not _command_status.text.is_empty()
	_experiment.visible = _experiment_needed or known.is_empty() or _needs_recipe_navigation()
	for button in _guide_buttons:
		button.disabled = locked or known.is_empty()
	_update_guide()
	_animate_cards()
	_live_hash = _resource_hash()
	_refreshing = false

func _build() -> void:
	name = "WorkshopView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_wallet = _label(self, "EtherWallet")
	_guide_toggle = _button(self, "GuideToggle", "Показать по шагам", _toggle_guide)
	_guide_steps = VBoxContainer.new()
	_guide_steps.name = "GuideSteps"
	_guide_steps.add_theme_constant_override("separation", 8)
	add_child(_guide_steps)
	var steps := HBoxContainer.new()
	_guide_steps.add_child(steps)
	_guide_buttons.append(_button(steps, "GuideRecipe", "1. Рецепт", _show_guide_step.bind(0)))
	_guide_buttons.append(_button(steps, "GuideAmount", "2. Количество", _show_guide_step.bind(1)))
	_guide_buttons.append(_button(steps, "GuideQueue", "3. Очередь", _show_guide_step.bind(2)))
	_guide_hint = _label(_guide_steps, "GuideHint")
	_guide_steps.hide()
	_command_status = _label(self, "CommandStatus")
	_experiment = _button(self, "OpenExperiment", "Открыть новый рецепт в Эксперименте", _open_experiment)
	_lines_box = VBoxContainer.new()
	_lines_box.name = "ProductionLines"
	_lines_box.add_theme_constant_override("separation", 12)
	add_child(_lines_box)
	for index in Workshop.Rules.RANKS.size():
		_build_card(index)
	_upgrades_toggle = _button(self, "ToggleUpgrades", "Улучшения", _toggle_upgrades)
	_upgrades = VBoxContainer.new()
	_upgrades.name = "WorkshopUpgrades"
	_upgrades.add_theme_constant_override("separation", 10)
	add_child(_upgrades)
	_heading = _label(_upgrades, "MasteryHeading", "Мастерство Мастерской", 22)
	_mastery = _label(_upgrades, "MasteryInfo")
	_mastery_bar = _progress_bar("MasteryProgress", 10.0)
	_upgrades.add_child(_mastery_bar)
	_label(_upgrades, "MasteryHint", "Создавай вещества — мастерство растёт, открывая новое оборудование.", 14)
	_equipment = _label(_upgrades, "EquipmentRecipe", "", 14)
	_equipment_orbs = _orb_flow(_upgrades, "EquipmentOrbs")
	_equipment_reason = _label(_upgrades, "EquipmentAvailability", "", 14)
	_buy_equipment = _button(_upgrades, "BuyEquipment", "Построить оборудование", _buy_rank)
	_plan_rank = _button(_upgrades, "PlanRankMaterials", "Изготовить недостающие материалы", _plan_materials.bind("rank"))
	_label(_upgrades, "AutonomyHeading", "Работа в отсутствие игрока", 20)
	_autonomy = _label(_upgrades, "AutonomyInfo", "", 14)
	_autonomy_orbs = _orb_flow(_upgrades, "AutonomyOrbs")
	_autonomy_reason = _label(_upgrades, "AutonomyAvailability", "", 14)
	_buy_autonomy = _button(_upgrades, "BuyAutonomy", "Продлить работу без меня", _buy_autonomy_command)
	_plan_autonomy = _button(_upgrades, "PlanAutonomyMaterials", "Изготовить материалы улучшения", _plan_materials.bind("autonomy"))
	_seal = _label(_upgrades, "ArchiveSeal", "", 13)
	_upgrades.hide()

func _toggle_upgrades() -> void:
	_upgrades.visible = not _upgrades.visible
	refresh()

func _toggle_guide() -> void:
	_guide_steps.visible = not _guide_steps.visible
	_guide_toggle.text = "Скрыть подсказки" if _guide_steps.visible else "Показать по шагам"
	_update_guide()

func _show_guide_step(step: int) -> void:
	_guide_step = step
	_update_guide()
	var control: Control = _cards[_guide_line][["target", "mode", "add"][step]]
	control.grab_focus()
	var ancestor := get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible(control)

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

func _build_card(index: int) -> void:
	var card := PanelContainer.new()
	card.name = "LineCard_%d" % (index + 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", g._panel_style(UIStyle.PANEL, 16))
	_lines_box.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(box)
	var info := _label(box, "LineInfo_%d" % (index + 1), "", 20)
	var state := _label(box, "LineState_%d" % (index + 1), "", 14)
	var suffix := "line_%d" % (index + 1)
	# Что сейчас крафтится и сколько этапа прошло: орб цели, полоса, подпись.
	var craft_row := HBoxContainer.new()
	craft_row.name = "CraftRow_" + suffix
	craft_row.add_theme_constant_override("separation", 8)
	box.add_child(craft_row)
	var orb_holder := Control.new()
	orb_holder.name = "CraftOrb_" + suffix
	orb_holder.custom_minimum_size = Vector2(36, 36)
	orb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_row.add_child(orb_holder)
	var progress := _progress_bar("CraftProgress_" + suffix, 12.0)
	progress.max_value = 1.0
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	craft_row.add_child(progress)
	var craft_status := _label(craft_row, "CraftStatus_" + suffix, "", 13)
	craft_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	craft_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	craft_status.custom_minimum_size.x = 78
	_label(box, "RecipeLabel_" + suffix, "Что изготовить", 14)
	var target := OptionButton.new()
	target.name = "Target_" + suffix
	target.custom_minimum_size = Vector2(0, 48)
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.fit_to_longest_item = false
	target.clip_text = true
	target.item_selected.connect(_input_changed.bind(index, 1))
	box.add_child(target)
	_label(box, "AmountLabel_" + suffix, "Сколько и как производить", 14)
	var row := HBoxContainer.new()
	box.add_child(row)
	var mode := OptionButton.new()
	mode.name = "Mode_" + suffix
	mode.add_item("Изготовить")
	mode.add_item("Держать запас")
	mode.custom_minimum_size = Vector2(0, 48)
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode.fit_to_longest_item = false
	mode.item_selected.connect(_input_changed.bind(index, 2))
	row.add_child(mode)
	var amount := SpinBox.new()
	amount.name = "Amount_" + suffix
	amount.min_value = 1
	amount.max_value = Game.CRAFT_INVENTORY_STACK_CAP
	amount.step = 1
	amount.value = 1
	amount.custom_minimum_size = Vector2(0, 48)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.value_changed.connect(_input_changed.bind(index, 2))
	row.add_child(amount)
	var mode_hint := _label(box, "ModeHint_" + suffix, "", 14)
	var quote := _label(box, "Quote_" + suffix, "", 14)
	var add := _button(box, "Add_" + suffix, "Добавить в очередь", _add_job.bind(index))
	var pause := _button(box, "Pause_" + suffix, "Пауза", _pause_line.bind(index))
	var queue := VBoxContainer.new()
	queue.name = "Queue_" + suffix
	box.add_child(queue)
	var details_toggle := _button(box, "Details_" + suffix, "Скорость и бонусы", _toggle_line_details.bind(index))
	var details := _label(box, "LineDetails_%d" % (index + 1), "", 13)
	details.hide()
	_cards.append({"card": card, "info": info, "state": state, "target": target, "mode": mode, "amount": amount,
		"mode_hint": mode_hint, "details": details, "details_toggle": details_toggle,
		"quote": quote, "add": add, "pause": pause, "queue": queue, "rows": {}, "signature": "", "targets": [], "recipe_needed": false,
		"craft_row": craft_row, "orb_holder": orb_holder, "progress": progress, "craft_status": craft_status,
		"orb_node": null, "orb_target": ""})
	_drafts.append({"target": "", "mode": "batch", "amount": 1})


func _progress_bar(node_name: String, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", _bar_style(UIStyle.PANEL_HI))
	bar.add_theme_stylebox_override("fill", _bar_style(UIStyle.TEAL))
	return bar


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
	var lbl := g._label("%d/%d" % [have, need], 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.tooltip_text = g._online._item_name(item_id)
	lbl.add_theme_color_override("font_color", UIStyle.DANGER if have < need else UIStyle.TEXT_DIM)
	row.add_child(lbl)


static func _status_color(status: String) -> Color:
	match status:
		"running":
			return UIStyle.TEAL
		"paused_user":
			return UIStyle.GOLD
		"waiting_ether":
			return UIStyle.GOLD_DIM
		"waiting_ingredients", "waiting_recipe":
			return Color(0.56, 0.48, 0.85)
		"waiting_inventory":
			return UIStyle.DANGER
		_:
			return UIStyle.LINE


## Полоса этапа и орб цели в карточках линий; ~15 раз в секунду из _process.
func _animate_cards() -> void:
	if not is_instance_valid(g) or workshop == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in _cards.size():
		var ui: Dictionary = _cards[i]
		var line := _line_for_card(i)
		var q: Array = line.get("queue", [])
		var row: Control = ui["craft_row"]
		row.visible = not q.is_empty()
		if q.is_empty():
			continue
		var job: Dictionary = q[0]
		var target := String(job.get("target", ""))
		var status := "paused_user" if line.get("paused", false) else String(job.get("status", "idle"))
		var interval: float = g._sigil.bench_interval(target)
		var frac := clampf(float(line.get("phase_seconds", 0.0)) / maxf(interval, 0.001), 0.0, 1.0)
		var bar: ProgressBar = ui["progress"]
		bar.value = frac
		bar.add_theme_stylebox_override("fill", _bar_style(_status_color(status)))
		var holder: Control = ui["orb_holder"]
		if ui["orb_target"] != target or not is_instance_valid(ui["orb_node"]):
			if is_instance_valid(ui["orb_node"]):
				(ui["orb_node"] as Node).queue_free()
			var orb: Control = g._engine._mini_orb(target, 36)
			holder.add_child(orb)
			orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			orb.pivot_offset = Vector2(18, 18)
			ui["orb_node"] = orb
			ui["orb_target"] = target
		var orb_node: Control = ui["orb_node"]
		orb_node.scale = Vector2.ONE * (1.0 + 0.12 * sin(t * 4.0)) if status == "running" else Vector2.ONE
		(ui["craft_status"] as Label).text = "%s · %d%%" % [g._online._item_name(target), int(round(frac * 100.0))]

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

func _button(parent: Node, node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Autowrap и ellipsis схлопывают минимальную ширину кнопки до отступов stylebox.
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	UIStyle.style_button(button, 0)
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
	ui["info"].text = "Линия %d · очередь %d/%d" % [index + 1, line.get("queue", []).size(), workshop.queue_capacity()]
	if unavailable:
		ui["info"].text = "Линия %d · Недоступна: %s" % [index + 1,
			"Мастерская закрыта" if locked else "построй ранг «%s»" % Workshop.Rules.RANKS[index]["name"]]
	ui["target"].visible = not unavailable
	ui["mode"].get_parent().visible = not unavailable
	ui["quote"].visible = not unavailable
	ui["pause"].visible = not unavailable and not line.get("queue", []).is_empty()
	ui["add"].visible = not unavailable
	ui["add"].disabled = unavailable or known.is_empty()
	ui["pause"].disabled = unavailable
	if unavailable:
		ui["recipe_needed"] = false
		ui["state"].text = ""
		_refresh_queue(index, {})
		return
	if ui["targets"] != known:
		ui["targets"] = known.duplicate()
		var pick: OptionButton = ui["target"]
		pick.clear()
		for item in known:
			pick.add_item(g._online._item_name(item))
			pick.set_item_metadata(pick.item_count - 1, item)
	if String(_drafts[index]["target"]).is_empty() and not known.is_empty():
		_drafts[index]["target"] = known[0]
	var target := String(_drafts[index]["target"])
	ui["target"].select(known.find(target))
	ui["mode"].select(1 if _drafts[index]["mode"] == "stock" else 0)
	ui["amount"].value = _drafts[index]["amount"]
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
			var info := _label(ui["queue"], "JobInfo_" + id, "", 14)
			var actions := HBoxContainer.new()
			ui["queue"].add_child(actions)
			var up := _button(actions, "Up_" + id, "↑", _move_job.bind(String(line["id"]), id, -1))
			var down := _button(actions, "Down_" + id, "↓", _move_job.bind(String(line["id"]), id, 1))
			_button(actions, "Remove_" + id, "Удалить", _remove_job.bind(String(line["id"]), id))
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

func _input_changed(_value: Variant, index: int, step: int) -> void:
	if _refreshing or is_queued_for_deletion():
		return
	var ui: Dictionary = _cards[index]
	var pick: OptionButton = ui["target"]
	_drafts[index]["target"] = String(pick.get_item_metadata(pick.selected)) if pick.selected >= 0 else ""
	_drafts[index]["mode"] = "stock" if ui["mode"].selected == 1 else "batch"
	_drafts[index]["amount"] = int(ui["amount"].value)
	_guide_line = index
	_guide_step = step
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
