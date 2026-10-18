extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")

static func run(g: Game) -> void:
	var before := Selftest._total
	var failures := Selftest._fails
	var fixture := Fixture.new(g)
	fixture.capture(g._workshop_scheduler)
	fixture.prepare_production()
	g._engine.inventory["fish"] = 0
	g._engine.inventory["clay"] = 0
	g._sigil._milestones_claimed.clear()
	var w: Workshop = g._workshop
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 100})
	g._pages._ensure_modes()
	var page: Node = g._pages._mode_pages.get("bench")
	var view: Node = page.find_child("WorkshopView", true, false) if is_instance_valid(page) else null
	Selftest.check("pages production embeds real WorkshopView", is_instance_valid(view)
		and view.get("workshop") == w and view.get("g") == g)
	if is_instance_valid(view):
		var ancestor := view.get_parent()
		while ancestor != null and not ancestor is ScrollContainer:
			ancestor = ancestor.get_parent()
		Selftest.check("pages production uses existing outer scroll", ancestor is ScrollContainer
			and ancestor == g._tabs_ref.get_child(Game.TAB_TOOLS) and view.get_parent() == page)
	w.enqueue(w.lines[0]["id"], {"target": "steam", "mode": "batch", "amount": 6})
	w.lines[0]["phase_seconds"] = 17.0
	var retained := w.export_state()
	g._pages._select_mode("bench")
	g._pages._select_mode("letters")
	Selftest.check("pages tool switch actually selects another mode", g._pages._tools_sel == "letters")
	g._pages._select_mode("bench")
	Selftest.check("pages switching tools retains actual queue and phase", w.export_state() == retained)
	Selftest.check("pages switching tools retains production view", is_instance_valid(page)
		and page.find_child("WorkshopView", true, false) == view)
	Selftest.check("pages legacy adapter API exists", g._pages.has_method("_sync_legacy_bench"))
	if g._pages.has_method("_sync_legacy_bench"):
		_legacy(g, w)
		_refusals(g, w)
	_permanent(g, w)
	await _freed_controls(g, w)
	fixture.finish()
	if is_instance_valid(view):
		view.call("refresh")
	print("WORKSHOP_PAGES_CHECKS: %d/%d" % [Selftest._total - before - (Selftest._fails - failures), Selftest._total - before])

static func _sync(g: Game) -> bool:
	return bool(g._pages.call("_sync_legacy_bench"))

static func _legacy(g: Game, w: Workshop) -> void:
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 100})
	w.enqueue("line_1", {"target": "dust", "mode": "batch", "amount": 4})
	w.enqueue("line_1", {"target": "stone", "mode": "batch", "amount": 2})
	w.enqueue("line_2", {"target": "steam", "mode": "batch", "amount": 4})
	var tail: Dictionary = w.lines[0]["queue"][1].duplicate(true)
	var other: Dictionary = w.lines[1].duplicate(true)
	g._pages._bench_target = "stale_legacy_target"
	g._pages._bench_on = true
	g._pages._on_bench_pick("steam")
	var line: Dictionary = w.lines[0]
	var job: Dictionary = line["queue"][0]
	Selftest.check("pages legacy pick replaces first-line command at global cap", job["target"] == "steam"
		and job["mode"] == "stock" and job["amount"] == Game.CRAFT_INVENTORY_STACK_CAP
		and line["queue"].size() == 2 and line["queue"][1] == tail and w.lines[1] == other)
	line["phase_seconds"] = 19.0
	job["route_operations"] = 2
	var stable_id := String(job["id"])
	Selftest.check("pages repeated legacy sync succeeds", _sync(g))
	Selftest.check("pages legacy sync retains stable ID phase and real route", job["id"] == stable_id
		and line["phase_seconds"] == 19.0 and job["route_operations"] == 2)
	# Toggle resolves the active first-line job, not a stale independent target.
	g._pages._bench_target = "dust"
	g._pages._bench_on = false
	g._pages._toggle_bench()
	Selftest.check("pages legacy toggle pauses actual first line", line["paused"]
		and g._pages._bench_target == "steam" and not g._pages._bench_on and w.lines[1] == other)
	g._pages._toggle_bench()
	Selftest.check("pages legacy toggle resumes same ID and phase", not line["paused"]
		and job["id"] == stable_id and line["phase_seconds"] == 19.0)
	# Direct old tick calls the existing scheduler; production never awaits a timer.
	w.import_state({"version": 1, "unlocked": true, "xp": 0})
	g._engine.inventory = {"fire": 20, "water": 20, "earth": 20, "air": 20, "steam": 0}
	g._engine.ether = 1000
	g._engine.ether_overflow = 0
	g._engine.mastery_rank = 0
	g._engine._blueprints.clear()
	g._pages._bench_target = "steam"
	g._pages._bench_on = true
	g._pages._bench_tick(39.0)
	Selftest.check("pages legacy tick shares scheduler phase without busy mutex", w.lines[0]["phase_seconds"] == 39.0
		and g._engine.inventory["steam"] == 0 and not g._pages._bench_busy and g._engine._resource_mutation_allowed())
	g._pages._bench_tick(1.0)
	Selftest.check("pages legacy tick executes one synchronous stage", g._engine.inventory["steam"] == 3
		and g._engine.inventory["fire"] == 17 and g._engine.inventory["water"] == 17 and w.xp == 3
		and g._engine.ether < 1000 and not g._engine.brewing and not g._pages._bench_busy)
	g._workshop_scheduler.call("advance", 0.0)
	Selftest.check("pages direct scheduler sees no second legacy executor", g._engine.inventory["steam"] == 3
		and w.lines[0]["queue"].size() == 1 and g._engine._resource_mutation_allowed())
	g._engine.inventory["steam"] = Game.CRAFT_INVENTORY_STACK_CAP
	var inputs := g._engine.inventory.duplicate(true)
	g._pages._bench_tick(40.0)
	Selftest.check("pages legacy stock respects real global cap", g._engine.inventory == inputs
		and w.lines[0]["queue"][0]["status"] == "waiting_inventory")
	# Regular Game processing must never remap stale legacy fields over new queues.
	w.import_state({"version": 1, "unlocked": true, "rank": 1})
	w.enqueue("line_1", {"target": "dust", "mode": "batch", "amount": 6})
	w.enqueue("line_2", {"target": "stone", "mode": "batch", "amount": 6})
	g._engine.inventory["dust"] = 0
	g._engine.inventory["stone"] = 0
	g._pages._bench_target = "steam"
	g._pages._bench_on = true
	g._process(40.0)
	Selftest.check("pages regular scheduler retains new queues despite stale legacy fields", w.lines[0]["queue"][0]["target"] == "dust"
		and w.lines[1]["queue"][0]["target"] == "stone" and g._engine.inventory["dust"] == 3 and g._engine.inventory["stone"] == 3)

static func _refusals(g: Game, w: Workshop) -> void:
	w.import_state({"version": 1, "unlocked": true})
	w.enqueue("line_1", {"target": "steam", "mode": "batch", "amount": 3})
	var known := g._engine.known_recipes.duplicate(true)
	for target in ["unknown_target", "fire", "steam"]:
		if target == "steam":
			g._engine.known_recipes.clear()
		g._pages._bench_target = target
		g._pages._bench_on = true
		var before := w.export_state()
		var inventory := g._engine.inventory.duplicate(true)
		Selftest.check("pages legacy rejects unavailable target " + target, not _sync(g)
			and w.export_state() == before and g._engine.inventory == inventory)
		g._pages._on_bench_pick(target)
		Selftest.check("pages legacy invalid pick does not change model " + target, w.export_state() == before)
	g._engine.known_recipes = known
	w.reset_new_game()
	g._engine.inventory.erase("person")
	g._pages._bench_target = "steam"
	var locked := w.export_state()
	Selftest.check("pages legacy locked entry leaves model unchanged", not _sync(g) and w.export_state() == locked)
	g._engine.inventory["person"] = 0
	Selftest.check("pages legacy Person unlocks without retroactive mastery", _sync(g) and w.unlocked and w.xp == 0)
	var future := {"version": 99, "unlocked": true, "xp": 999, "lines": [{"opaque": "keep"}]}
	w.import_state(future)
	g._engine.inventory.erase("person")
	Selftest.check("pages unsupported state keeps production entry visible", g._engine._mode_unlocked("bench"))
	Selftest.check("pages legacy future version is preserved", not _sync(g) and w.export_state() == future)
	g._pages._ensure_modes()
	var page: Node = g._pages._mode_pages.get("bench")
	var view: Node = page.find_child("WorkshopView", true, false) if is_instance_valid(page) else null
	if is_instance_valid(view):
		view.call("refresh")
		var reason := view.find_child("CommandStatus", true, false) as Label
		Selftest.check("pages unsupported state shows visible update reason", is_instance_valid(reason) and reason.text.contains("новая версия"))

static func _permanent(g: Game, w: Workshop) -> void:
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 160})
	w.enqueue("line_1", {"target": "steam", "mode": "batch", "amount": 1})
	w.reset_prestige()
	g._engine.inventory.erase("person")
	Selftest.check("pages permanent unlock remains after prestige without Person", g._engine._mode_unlocked("bench")
		and w.unlocked and w.rank == 1 and w.xp == 160 and w.lines[0]["queue"].is_empty())
	w.reset_new_game()
	Selftest.check("pages fresh world requires initial Person", not g._engine._mode_unlocked("bench"))
	g._engine.inventory["person"] = 0
	Selftest.check("pages initial legacy Person still satisfies mode gate", g._engine._mode_unlocked("bench"))

static func _freed_controls(g: Game, w: Workshop) -> void:
	w.import_state({"version": 1, "unlocked": true})
	var local := Pages.new(g)
	var container := VBoxContainer.new()
	g.add_child(container)
	local._build_bench_page(container)
	var view: Node = container.find_child("WorkshopView", true, false)
	Selftest.check("pages rebuilt screen binds same persistent model", is_instance_valid(view) and view.get("workshop") == w)
	var before := w.export_state()
	container.queue_free()
	await g.get_tree().process_frame
	w.changed.emit()
	local._refresh_mode_pages()
	Selftest.check("pages refresh safely ignores freed production controls", w.export_state() == before and not is_instance_valid(view))
