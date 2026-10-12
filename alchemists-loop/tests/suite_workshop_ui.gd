extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")

static func run(g: Game) -> void:
	var checks_before := Selftest._total
	var failures_before := Selftest._fails
	var path := "res://game/lab/workshop_view.gd"
	Selftest.check("workshop UI script exists", FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		return
	var script: Script = load(path)
	Selftest.check("workshop UI script loads", script != null and script.can_instantiate())
	if script == null or not script.can_instantiate():
		return
	var fixture := Fixture.new(g)
	fixture.prepare_production()
	g._sigil._milestones_claimed.clear()
	var w: Workshop = g._workshop
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 170})
	var view = script.new()
	g.add_child(view)
	view.setup(g, w)
	Selftest.check("workshop UI real add button exists", view.find_child("Add_line_1", true, false) is Button)
	await _screen(g, w, view)
	await _hidden_page(g, view)
	view.queue_free()
	await g.get_tree().process_frame
	await _materials(g, w, script)
	await _preview(g, w)
	fixture.finish()
	var checks := Selftest._total - checks_before
	print("WORKSHOP_UI_CHECKS: %d/%d" % [checks - (Selftest._fails - failures_before), checks])

static func _node(view: Node, node_name: String) -> Node:
	return view.find_child(node_name, true, false)

static func _text(view: Node, node_name: String) -> String:
	var node := _node(view, node_name)
	return node.text if node is Label else ""

static func _press(view: Node, node_name: String) -> bool:
	var button := _node(view, node_name) as Button
	Selftest.check("workshop real button " + node_name, button != null)
	if button == null:
		return false
	button.pressed.emit()
	return true

static func _choose(view: Node, line: String, target: String, amount: int, stock := false) -> bool:
	var pick := _node(view, "Target_" + line) as OptionButton
	var mode := _node(view, "Mode_" + line) as OptionButton
	var count := _node(view, "Amount_" + line) as SpinBox
	if pick == null or mode == null or count == null:
		return false
	for index in pick.item_count:
		if pick.get_item_metadata(index) == target:
			pick.select(index)
			pick.item_selected.emit(index)
			mode.select(1 if stock else 0)
			mode.item_selected.emit(mode.selected)
			count.value = amount
			return true
	return false

static func _screen(g: Game, w: Workshop, view: Node) -> void:
	Selftest.check("workshop heading names production mastery", _text(view, "MasteryHeading") == "Мастерство Мастерской")
	Selftest.check("workshop rank and next threshold visible", _text(view, "MasteryInfo").contains("Мастер")
		and _text(view, "MasteryInfo").contains("170") and _text(view, "MasteryInfo").contains("400"))
	var next: Dictionary = Workshop.Rules.RANKS[2]
	Selftest.check("workshop next equipment authoritative price visible", _text(view, "EquipmentRecipe").contains(str(next["ether"]))
		and _text(view, "EquipmentRecipe").contains("×25") and _text(view, "EquipmentRecipe").contains("×10"))
	Selftest.check("workshop Archive Seal is separate factual stage note", _text(view, "ArchiveSeal").contains("Архивная печать")
		and _text(view, "ArchiveSeal").contains("3/4/5") and _text(view, "ArchiveSeal").contains(str(g._engine._stage_ops())))
	var active := 0
	var locked := 0
	for index in range(1, 5):
		var card := _node(view, "LineCard_%d" % index)
		Selftest.check("workshop card %d visible" % index, card is PanelContainer)
		var add := _node(view, "Add_line_%d" % index) as Button
		if add != null and not add.disabled:
			active += 1
		elif _text(view, "LineInfo_%d" % index).contains("Недоступна"):
			locked += 1
	Selftest.check("workshop Master rank enables two of four cards", active == 2 and locked == 2)
	Selftest.check("workshop interval and concrete speed source rendered", _text(view, "LineState_1").contains("этап каждые")
		and _text(view, "LineState_1").contains("40.0") and _text(view, "LineState_1").contains("базовая скорость"))
	Selftest.check("workshop wallet shows active ether and reserve", _text(view, "EtherWallet").contains("активного")
		and _text(view, "EtherWallet").contains("резерва"))
	var targets := _node(view, "Target_line_1") as OptionButton
	var only_known := targets != null
	if targets != null:
		for i in targets.item_count:
			only_known = only_known and w.known_target_recipe(String(targets.get_item_metadata(i)))
	Selftest.check("workshop target picker contains known nonbase recipes only", only_known)
	var touch_safe := true
	for button in view.find_children("*", "Button", true, false):
		touch_safe = touch_safe and button.custom_minimum_size.y >= 48
	Selftest.check("workshop primary controls have at least 48px hit areas", touch_safe)
	Selftest.check("workshop selectable known nonbase target", _choose(view, "line_1", "steam", 3))
	var before := g._engine.inventory.duplicate(true)
	var ether := g._engine._available_ether()
	_press(view, "Add_line_1")
	Selftest.check("workshop add signal enqueues exact batch without spending", w.lines[0]["queue"].size() == 1
		and w.lines[0]["queue"][0]["amount"] == 3 and w.lines[0]["queue"][0]["mode"] == "batch"
		and g._engine.inventory == before and g._engine._available_ether() == ether)
	if w.lines[0]["queue"].is_empty():
		return
	await g.get_tree().process_frame
	Selftest.check("workshop refresh preserves executing controls", is_instance_valid(_node(view, "Add_line_1")))
	var first := String(w.lines[0]["queue"][0]["id"])
	_choose(view, "line_1", "stone", 5, true)
	_press(view, "Add_line_1")
	await g.get_tree().process_frame
	Selftest.check("workshop stock selector stores shared inventory threshold", w.lines[0]["queue"].size() == 2
		and w.lines[0]["queue"][1]["mode"] == "stock" and w.lines[0]["queue"][1]["amount"] == 5)
	if w.lines[0]["queue"].size() < 2:
		return
	var second := String(w.lines[0]["queue"][1]["id"])
	_press(view, "Up_" + second)
	Selftest.check("workshop reorder signal moves stable queued job", w.lines[0]["queue"][0]["id"] == second)
	await g.get_tree().process_frame
	_press(view, "Down_" + second)
	Selftest.check("workshop down signal restores order", w.lines[0]["queue"][0]["id"] == first)
	await g.get_tree().process_frame
	_press(view, "Pause_line_1")
	Selftest.check("workshop pause signal pauses one line", w.lines[0]["paused"] and not w.lines[1]["paused"])
	await g.get_tree().process_frame
	_press(view, "Pause_line_1")
	Selftest.check("workshop resume signal resumes line", not w.lines[0]["paused"])
	w.lines[0]["queue"][0]["produced"] = 2
	w.lines[0]["queue"][0]["status"] = "waiting_ether"
	w.lines[0]["queue"][0]["reason"] = "Нужно 12 эфира для следующей операции."
	w.changed.emit()
	await g.get_tree().process_frame
	Selftest.check("workshop model progress and specific reason rendered", _text(view, "JobInfo_" + first).contains("2/3")
		and _text(view, "JobInfo_" + first).contains("Нужно 12 эфира"))
	var row := _node(view, "JobInfo_" + first)
	view.refresh()
	Selftest.check("workshop refresh updates instead of rebuilding unchanged queue", _node(view, "JobInfo_" + first) == row)
	g._engine.inventory["steam"] = 2
	_press(view, "Remove_" + first)
	Selftest.check("workshop remove signal retains actual produced stock", w.lines[0]["queue"].size() == 1
		and w.lines[0]["queue"][0]["id"] == second and g._engine.inventory["steam"] == 2)
	await g.get_tree().process_frame
	w.xp = 400
	g._engine.inventory["glass"] = 24
	g._engine.inventory["tool"] = 10
	view.refresh()
	before = g._engine.inventory.duplicate(true)
	ether = g._engine._available_ether()
	_press(view, "BuyEquipment")
	Selftest.check("workshop shortage button gives reason without spending", w.rank == 1 and g._engine.inventory == before
		and g._engine._available_ether() == ether and _text(view, "CommandStatus").contains("Не хватает"))
	g._engine.inventory["glass"] = 25
	g._engine.ether = 10
	g._engine.ether_overflow = int(next["ether"]) - 10
	_press(view, "BuyEquipment")
	Selftest.check("workshop buy button spends actual recipe and reserve once", w.rank == 2 and w.xp == 400
		and g._engine.inventory["glass"] == 0 and g._engine.inventory["tool"] == 0 and g._engine._available_ether() == 0)
	await g.get_tree().process_frame
	g._engine.inventory["glass"] = 15
	g._engine.inventory["metal"] = 10
	g._engine.ether = int(Workshop.Rules.AUTONOMY[1]["ether"])
	_press(view, "BuyAutonomy")
	Selftest.check("workshop autonomy signal spends once and extends limit", w.autonomy_level == 1 and w.offline_stage_limit() == 120
		and g._engine.inventory["glass"] == 0 and g._engine.inventory["metal"] == 0)
	await g.get_tree().process_frame
	var jobs: Array = w.lines.duplicate(true)
	var script: Script = view.get_script()
	view.get_parent().remove_child(view)
	var replacement = script.new()
	g.add_child(replacement)
	replacement.setup(g, w)
	Selftest.check("workshop switching view retains queue", w.lines == jobs)
	var connection_count := w.changed.get_connections().size()
	replacement.queue_free()
	w.changed.emit()
	await g.get_tree().process_frame
	w.changed.emit()
	Selftest.check("workshop deleted view disconnects changed safely", w.changed.get_connections().size() < connection_count and w.lines == jobs)
	g.add_child(view)

static func _hidden_page(g: Game, view: Node) -> void:
	# Re-adding the view above arms one deferred refresh; consume it first,
	# otherwise it draws after the page is hidden and proves nothing.
	await g.get_tree().process_frame
	view.visible = false
	view._status = "Скрытая страница"
	view._schedule_refresh()
	await g.get_tree().process_frame
	Selftest.check("workshop hidden page skips the per frame model refresh",
		_text(view, "CommandStatus") != "Скрытая страница")
	view.visible = true
	Selftest.check("workshop page draws accumulated state when shown",
		_text(view, "CommandStatus") == "Скрытая страница")
	view._status = ""
	view.refresh()

static func _materials(g: Game, w: Workshop, script: Script) -> void:
	Selftest.check("workshop material planning API exists", w.has_method("queue_missing_materials") and w.has_method("missing_materials_preview"))
	if not w.has_method("queue_missing_materials") or not w.has_method("missing_materials_preview"):
		return
	w.import_state({"version": 1, "unlocked": true, "rank": 0, "xp": 0})
	g._engine.inventory["brick"] = 18
	g._engine.inventory["metal"] = 10
	var before := w.export_state()
	var preview: Dictionary = w.call("missing_materials_preview", "rank")
	Selftest.check("workshop preview allows preparing material below XP and mutates nothing", preview.get("ok", false) and w.export_state() == before)
	var observed: Array = []
	var observe := func() -> void: observed.append(w.lines.duplicate(true))
	w.changed.connect(observe)
	var inventory := g._engine.inventory.duplicate(true)
	var result: Dictionary = w.call("queue_missing_materials", "rank")
	Selftest.check("workshop only deficient material queued as full stock threshold", result.get("ok", false)
		and w.lines[0]["queue"].size() == 1 and w.lines[0]["queue"][0]["target"] == "brick"
		and w.lines[0]["queue"][0]["mode"] == "stock" and w.lines[0]["queue"][0]["amount"] == 20
		and g._engine.inventory == inventory and w.xp == 0 and observed.size() == 1)
	w.import_state({"version": 1, "unlocked": true, "rank": 0})
	g._engine.inventory["metal"] = 8
	before = w.export_state()
	observed.clear()
	result = w.call("queue_missing_materials", "rank")
	Selftest.check("workshop no room for all deficits leaves entire queue atomic", not result.get("ok", true)
		and result.get("code") == "capacity" and w.export_state() == before and observed.is_empty())
	w.import_state({"version": 1, "unlocked": true, "rank": 1})
	g._engine.inventory["glass"] = 14
	g._engine.inventory["metal"] = 9
	w.enqueue("line_1", {"target": "steam", "mode": "batch", "amount": 1})
	w.enqueue("line_1", {"target": "stone", "mode": "batch", "amount": 1})
	observed.clear()
	result = w.call("queue_missing_materials", "autonomy")
	Selftest.check("workshop deterministic distribution publishes complete two job plan once", result.get("ok", false)
		and observed.size() == 1 and w.lines[1]["queue"].size() == 2
		and w.lines[1]["queue"][0]["target"] == "glass" and w.lines[1]["queue"][0]["amount"] == 15
		and w.lines[1]["queue"][1]["target"] == "metal" and w.lines[1]["queue"][1]["amount"] == 10
		and observed[0] == w.lines)
	w.changed.disconnect(observe)
	w.import_state({"version": 1, "unlocked": true, "rank": 1})
	var view = script.new()
	g.add_child(view)
	view.setup(g, w)
	_press(view, "PlanAutonomyMaterials")
	Selftest.check("workshop real material button enqueues only missing stock targets", w.lines[0]["queue"].size() == 2
		and w.lines[0]["queue"][0]["target"] == "glass" and w.lines[0]["queue"][0]["amount"] == 15
		and w.lines[0]["queue"][1]["target"] == "metal" and w.lines[0]["queue"][1]["amount"] == 10)
	w.import_state({"version": 1, "unlocked": true, "rank": 1})
	view.refresh()
	# Preview is stale on purpose: inventory changed without a model signal.
	g._engine.inventory["glass"] = 15
	g._engine.inventory["metal"] = 10
	_press(view, "PlanAutonomyMaterials")
	Selftest.check("workshop material button recomputes current stock", w.lines[0]["queue"].is_empty()
		and w.lines[1]["queue"].is_empty() and _text(view, "CommandStatus").contains("уже"))
	var known := g._engine.known_recipes.duplicate()
	for recipe in g.RECIPES:
		if recipe["out"] == "glass":
			g._engine.known_recipes.erase(g._pair_key(recipe["a"], recipe["b"]))
	before = w.export_state()
	_press(view, "PlanAutonomyMaterials")
	Selftest.check("workshop unknown material refuses without exposing recipe", w.export_state() == before
		and _text(view, "CommandStatus").contains("Эксперимент"))
	_press(view, "OpenExperiment")
	Selftest.check("workshop unknown recipe action opens Experiment", g._tabs_ref.current_tab == Game.TAB_EXPERIMENT)
	g._engine.known_recipes = known
	_press(view, "PlanAutonomyMaterials")
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "lines": [{"id": "line_1", "queue": [
		{"id": "blocked_recipe", "target": "no_known_target", "mode": "batch", "amount": 1}]}]})
	view.refresh()
	Selftest.check("workshop waiting recipe job exposes actionable Experiment navigation",
		_node(view, "OpenExperiment").visible and _text(view, "JobInfo_blocked_recipe").contains("Ждёт открытия рецепта"))
	view.queue_free()
	await g.get_tree().process_frame
	w.import_state({"version": 1, "unlocked": true, "rank": 0})
	before = w.export_state()
	Selftest.check("workshop autonomy planning requires equipment rank", not w.call("queue_missing_materials", "autonomy").get("ok", true) and w.export_state() == before)
	w.unlocked = false
	before = w.export_state()
	Selftest.check("workshop locked material planning refuses", not w.call("queue_missing_materials", "rank").get("ok", true) and w.export_state() == before)
	w.import_state({"version": 99, "future": {"x": 1}})
	before = w.export_state()
	Selftest.check("workshop future version material planning is immutable", not w.call("queue_missing_materials", "rank").get("ok", true) and w.export_state() == before)

static func _preview(g: Game, w: Workshop) -> void:
	Selftest.check("workshop quote API exists", w.has_method("job_preview"))
	if not w.has_method("job_preview"):
		return
	w.import_state({"version": 1, "unlocked": true, "rank": 1})
	g._engine.inventory = {"fire": 100, "water": 100, "earth": 100, "air": 100, "clay": 1}
	g._engine._blueprints.clear()
	var inventory := g._engine.inventory.duplicate(true)
	var before := w.export_state()
	var quote: Dictionary = w.call("job_preview", "brick", "batch", 2)
	# Existing clay covers one brick; the second needs one extra clay operation.
	Selftest.check("workshop quantity quote uses shared intermediate stock rather than multiply", quote.get("ok", false)
		and quote.get("operations") == 3 and int(quote.get("ether", 0)) > 3 * Game.BREW_COST)
	Selftest.check("workshop quote does not spend or alter production context", g._engine.inventory == inventory and w.export_state() == before
		and g._engine._production_discount == 1.0)
	g._engine.inventory["steam"] = 2
	g._engine._blueprints["steam"] = {"discount": Game.BLUEPRINT_DISCOUNT}
	quote = w.call("job_preview", "steam", "stock", 3)
	Selftest.check("workshop stock quote only plans present deficit and real per pair discount", quote.get("units") == 1
		and quote.get("operations") == 1 and quote.get("ether") == g._engine._pair_cost("fire", "water", Game.BLUEPRINT_DISCOUNT)
		and quote.get("next_ether") == quote.get("ether"))
	quote = w.call("job_preview", "steam", "stock", 2)
	Selftest.check("workshop satisfied stock quote costs zero", quote.get("units") == 0 and quote.get("operations") == 0 and quote.get("ether") == 0)
