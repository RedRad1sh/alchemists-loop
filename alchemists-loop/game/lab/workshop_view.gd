extends VBoxContainer
class_name WorkshopView

var g: Game
var workshop: Workshop
var _cards: Array = []
var _drafts: Array = []
var _refresh_pending := false
var _refreshing := false
var _poll_seconds := 0.0
var _live_hash := 0
var _status := ""
var _experiment_needed := false
var _heading: Label
var _mastery: Label
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
	if not is_instance_valid(g) or workshop == null or is_queued_for_deletion() or _cards.is_empty():
		return
	_refreshing = true
	var rules: Dictionary = Workshop.Rules.RANKS[workshop.rank]
	var next := workshop.rank + 1
	_mastery.text = "Ранг: %s · мастерство %d" % [rules["name"], workshop.xp]
	if next < Workshop.Rules.RANKS.size():
		var upgrade: Dictionary = Workshop.Rules.RANKS[next]
		_mastery.text += " / %d до ранга «%s». Мастерство не расходуется." % [upgrade["xp"], upgrade["name"]]
		_equipment.text = "Следующее оборудование: %s" % _recipe_text(upgrade)
		_equipment_reason.text = String(workshop.rank_availability(next).get("reason", ""))
	else:
		_mastery.text += ". Оборудование максимального ранга; мастерство сохраняется."
		_equipment.text = "Оборудование полностью построено."
		_equipment_reason.text = ""
	var autonomy_next := workshop.autonomy_level + 1
	_autonomy.text = "Автономность %d · до %d офлайн-этапов на линию." % [workshop.autonomy_level, workshop.offline_stage_limit()]
	if autonomy_next < Workshop.Rules.AUTONOMY.size():
		var upgrade: Dictionary = Workshop.Rules.AUTONOMY[autonomy_next]
		_autonomy.text += "\nСледующий предел: %d этапов · ранг «%s».\n%s" % [upgrade["stages"], Workshop.Rules.RANKS[int(upgrade["rank"])]["name"], _recipe_text(upgrade)]
		_autonomy_reason.text = String(workshop.autonomy_availability().get("reason", ""))
	else:
		_autonomy_reason.text = "Достигнут максимальный предел автономности."
	_seal.text = "Архивная печать — отдельное улучшение: 3/4/5 операций за этап; сейчас %d (ранг печати %d). Это не мастерство Мастерской." % [g._engine._stage_ops(), g._engine.mastery_rank]
	_wallet.text = "Эфир: %d активного + %d резерва = %d доступно. Расход проверяется перед каждой операцией." % [g._engine.ether, g._engine.ether_overflow, g._engine._available_ether()]
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
	_experiment.visible = _experiment_needed or known.is_empty() or _needs_recipe_navigation()
	_live_hash = _resource_hash()
	_refreshing = false

func _build() -> void:
	name = "WorkshopView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_heading = _label(self, "MasteryHeading", "Мастерство Мастерской", 22)
	_mastery = _label(self, "MasteryInfo")
	_equipment = _label(self, "EquipmentRecipe")
	_equipment_reason = _label(self, "EquipmentAvailability")
	_buy_equipment = _button(self, "BuyEquipment", "Построить оборудование", _buy_rank)
	_plan_rank = _button(self, "PlanRankMaterials", "Запланировать материалы оборудования", _plan_materials.bind("rank"))
	_autonomy = _label(self, "AutonomyInfo")
	_autonomy_reason = _label(self, "AutonomyAvailability")
	_buy_autonomy = _button(self, "BuyAutonomy", "Улучшить автономность", _buy_autonomy_command)
	_plan_autonomy = _button(self, "PlanAutonomyMaterials", "Запланировать материалы автономности", _plan_materials.bind("autonomy"))
	_seal = _label(self, "ArchiveSeal", "", 13)
	_wallet = _label(self, "EtherWallet")
	_command_status = _label(self, "CommandStatus")
	_experiment = _button(self, "OpenExperiment", "Открыть Эксперимент: исследовать рецепт", _open_experiment)
	for index in Workshop.Rules.RANKS.size():
		_build_card(index)

func _build_card(index: int) -> void:
	var card := PanelContainer.new()
	card.name = "LineCard_%d" % (index + 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.07, 0.10, 0.15, 0.88), 16))
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(box)
	var info := _label(box, "LineInfo_%d" % (index + 1))
	var state := _label(box, "LineState_%d" % (index + 1))
	var suffix := "line_%d" % (index + 1)
	var target := OptionButton.new()
	target.name = "Target_" + suffix
	target.custom_minimum_size = Vector2(0, 48)
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.fit_to_longest_item = false
	target.clip_text = true
	target.item_selected.connect(_input_changed.bind(index))
	box.add_child(target)
	var row := HBoxContainer.new()
	box.add_child(row)
	var mode := OptionButton.new()
	mode.name = "Mode_" + suffix
	mode.add_item("Партия N")
	mode.add_item("Запас N")
	mode.custom_minimum_size = Vector2(0, 48)
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode.fit_to_longest_item = false
	mode.item_selected.connect(_input_changed.bind(index))
	row.add_child(mode)
	var amount := SpinBox.new()
	amount.name = "Amount_" + suffix
	amount.min_value = 1
	amount.max_value = Game.CRAFT_INVENTORY_STACK_CAP
	amount.step = 1
	amount.value = 1
	amount.custom_minimum_size = Vector2(0, 48)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.value_changed.connect(_input_changed.bind(index))
	row.add_child(amount)
	var quote := _label(box, "Quote_" + suffix, "", 13)
	var add := _button(box, "Add_" + suffix, "Добавить в очередь", _add_job.bind(index))
	var pause := _button(box, "Pause_" + suffix, "Приостановить линию", _pause_line.bind(index))
	var queue := VBoxContainer.new()
	queue.name = "Queue_" + suffix
	box.add_child(queue)
	_cards.append({"info": info, "state": state, "target": target, "mode": mode, "amount": amount,
		"quote": quote, "add": add, "pause": pause, "queue": queue, "rows": {}, "signature": "", "targets": [], "recipe_needed": false})
	_drafts.append({"target": "", "mode": "batch", "amount": 1})

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
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_button(button, 0)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _recipe_text(recipe: Dictionary) -> String:
	var pieces := PackedStringArray()
	for item in recipe["materials"]:
		pieces.append("%s ×%d (есть %d)" % [g._online._item_name(item), recipe["materials"][item], g._engine.inventory.get(item, 0)])
	pieces.append("%d эфира, включая резерв" % int(recipe["ether"]))
	return " · ".join(pieces)

func _line_for_card(index: int) -> Dictionary:
	return workshop.lines[index] if index < workshop.line_count() and index < workshop.lines.size() else {}

func _refresh_card(index: int, known: Array[String], locked: bool) -> void:
	var ui: Dictionary = _cards[index]
	var line := _line_for_card(index)
	var unavailable := locked or line.is_empty()
	ui["info"].text = "Линия %d · очередь %d/%d" % [index + 1, line.get("queue", []).size(), workshop.queue_capacity()]
	if unavailable:
		ui["info"].text = "Линия %d · Недоступна: %s" % [index + 1,
			"Мастерская закрыта" if locked else "построй ранг «%s»" % Workshop.Rules.RANKS[index]["name"]]
	ui["target"].visible = not unavailable
	ui["mode"].get_parent().visible = not unavailable
	ui["quote"].visible = not unavailable
	ui["pause"].visible = not unavailable
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
	ui["state"].text = "%s · этап каждые %.1f с (%s) · %s.\nГотовность этапа: %.1f/%.1f с · %d операций/этап." % [
		"Пауза игрока" if line["paused"] else "Линия включена", interval, speed, discount,
		float(line.get("phase_seconds", 0.0)), interval, g._engine._stage_ops()]
	ui["pause"].text = "Возобновить линию" if line["paused"] else "Приостановить линию"
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
		row["info"].text = "%d. %s · %s\n%s · выполнено операций: %d" % [i + 1, g._online._item_name(target), mode, _status_name(String(job["status"])), job.get("route_operations", 0)]
		if not String(job.get("reason", "")).is_empty():
			row["info"].text += "\n" + String(job["reason"])
		row["up"].disabled = i == 0
		row["down"].disabled = i == jobs.size() - 1

func _update_quote(index: int) -> void:
	var draft: Dictionary = _drafts[index]
	var quote := workshop.job_preview(String(draft["target"]), String(draft["mode"]), int(draft["amount"]))
	var label: Label = _cards[index]["quote"]
	_cards[index]["recipe_needed"] = not quote["ok"] and quote.get("code", "") == "recipe"
	if not quote["ok"]:
		label.text = "Оценка недоступна: " + String(quote["reason"])
		return
	label.text = "Следующая операция: %d эфира. Оценка %d единиц: %d операций, %d эфира.\n%s · общий запас цели: %d. Оценка пересчитывается; ресурсы не резервируются." % [quote["next_ether"], quote["units"], quote["operations"], quote["ether"],
		"чертёж −%d%%" % int(round((1.0 - float(quote["discount"])) * 100.0)) if float(quote["discount"]) < 1.0 else "без скидки чертежа", g._engine.inventory.get(draft["target"], 0)]
	if not String(quote["reason"]).is_empty():
		label.text += "\n" + String(quote["reason"])

static func _status_name(status: String) -> String:
	return {"idle": "В очереди", "running": "Производство", "paused_user": "Пауза игрока",
		"waiting_ether": "Ждёт эфира", "waiting_ingredients": "Ждёт ингредиентов",
		"waiting_recipe": "Ждёт открытия рецепта", "waiting_inventory": "Ждёт места в запасе"}.get(status, status)

func _input_changed(_value: Variant, index: int) -> void:
	if _refreshing or is_queued_for_deletion():
		return
	var ui: Dictionary = _cards[index]
	var pick: OptionButton = ui["target"]
	_drafts[index]["target"] = String(pick.get_item_metadata(pick.selected)) if pick.selected >= 0 else ""
	_drafts[index]["mode"] = "stock" if ui["mode"].selected == 1 else "batch"
	_drafts[index]["amount"] = int(ui["amount"].value)
	_update_quote(index)
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
	_complete(workshop.enqueue(String(line["id"]), _drafts[index]))

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
	_experiment.visible = _experiment_needed or _needs_recipe_navigation()
	_schedule_refresh()

func _open_experiment() -> void:
	if is_instance_valid(g._tabs_ref):
		g._tabs_ref.current_tab = Game.TAB_EXPERIMENT

func _schedule_refresh() -> void:
	if _refresh_pending or not is_inside_tree() or is_queued_for_deletion():
		return
	_refresh_pending = true
	call_deferred("refresh")

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
	if _poll_seconds >= 0.5 and is_instance_valid(g) and workshop != null:
		_poll_seconds = 0.0
		if _live_hash != _resource_hash():
			_schedule_refresh()
