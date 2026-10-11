extends RefCounted

# A synchronous debit callback exercises the real Core transaction, including
# its own spend. No production test switch or replacement resource arithmetic.
class ReentrantCore extends Core:
	var debit_callback: Callable
	var probing := false
	func _init(game: Game) -> void:
		super(game)
	func _spend_ether(amount: int) -> bool:
		if not probing and debit_callback.is_valid():
			probing = true
			debit_callback.call()
			probing = false
		return super(amount)

static func run(g: Game) -> void:
	var has_context := false
	for method in g._engine.get_method_list():
		if String(method.get("name", "")) == "_commit_brew":
			has_context = (method.get("args", []) as Array).size() == 3
	Selftest.check("context commit accepts explicit transaction context", has_context)
	Selftest.check("context synchronous resource guard exists", g._engine.has_method("_resource_mutation_allowed"))
	if not has_context:
		return
	var objects: Array = [g._engine, g._online, g._retention, g._riddles,
		g._guild, g._spirit, g._progress_ui, g._hub, g._saves, g._sigil_ui, Net]
	var workshop = g.get("_workshop")
	if workshop != null:
		objects.append(workshop)
	var snapshots: Array = []
	for object in objects:
		snapshots.append(_snapshot(object))
	var processing := g.is_processing()
	var selftest := g._selftest
	var recipes := g.RECIPES.duplicate(true)
	g.set_process(false)
	g._saves._save_frozen = true
	g._online._net_enabled = false
	# Keep any unexpected telemetry in memory; never issue real HTTP.
	Net._inflight = {"kind": "context_fixture_blocker"}
	Net._queue.clear()
	if workshop != null:
		workshop.set("unlocked", true)
	else:
		print("CONTEXT MASTERY PENDING: model/main wiring absent; XP integration not verified")
	_test_resources(g, workshop)
	_test_invalid_context(g, workshop)
	_test_reentrant(g)
	_test_offline(g)
	g._selftest = selftest
	g.RECIPES = recipes
	for i in objects.size():
		_restore(objects[i], snapshots[i])
	g.set_process(processing)
	g._engine._refresh()
	Selftest.check("context fixture restores resource and gameplay snapshots",
		_snapshot(g._engine) == snapshots[0] and _snapshot(g._retention) == snapshots[2]
		and _snapshot(g._saves) == snapshots[8] and _snapshot(Net) == snapshots[10])

static func _context(source := "workshop", discount: Variant = 1.0) -> Dictionary:
	return {"source": source, "production": source != "manual", "discount": discount}

static func _seed(g: Game, fire := 2, water := 2, energy := 100) -> void:
	g._engine.inventory = {"fire": fire, "water": water, "steam": 0}
	g._engine.known_recipes = {g._pair_key("fire", "water"): true}
	g._engine.ether = energy
	g._engine.ether_overflow = 0
	g._engine._production_discount = 1.0

static func _commit(g: Game, a: String, b: String, context: Dictionary) -> Dictionary:
	return g._engine.call("_commit_brew", a, b, context)

static func _xp(workshop) -> int:
	return int(workshop.get("xp")) if workshop != null else 0

static func _allowed(g: Game) -> bool:
	return g._engine.has_method("_resource_mutation_allowed") \
		and bool(g._engine.call("_resource_mutation_allowed"))

static func _test_resources(g: Game, workshop) -> void:
	_seed(g, 1, 1)
	var xp := _xp(workshop)
	var first := _commit(g, "fire", "water", _context())
	var after := _snapshot(g._engine)
	var second := _commit(g, "fire", "water", _context())
	Selftest.check("context two sequential commits consume last inputs once",
		not bool(first.get("failed", true)) and bool(second.get("failed", false))
		and int(g._engine.inventory.get("steam", 0)) == 1 and _snapshot(g._engine) == after)
	Selftest.check("context confirmed output reports ether and mastery",
		int(first.get("ether_spent", -1)) == 12
		and int(first.get("mastery_awarded", -1)) == (1 if workshop != null else 0)
		and _xp(workshop) == xp + (1 if workshop != null else 0))
	Selftest.check("context rejected commit reports zero debit and mastery",
		int(second.get("ether_spent", -1)) == 0 and int(second.get("mastery_awarded", -1)) == 0 and _allowed(g))

	_seed(g)
	g._engine._production_discount = 0.8
	var discounted := _commit(g, "fire", "water", _context("workshop", 0.9))
	var ordinary := _commit(g, "fire", "water", _context("manual"))
	Selftest.check("context discount 0.9 costs 11 then explicit manual costs 12",
		int(discounted.get("ether_spent", -1)) == 11 and int(ordinary.get("ether_spent", -1)) == 12
		and g._engine.ether == 77 and g._engine._production_discount == 0.8
		and g._engine._pair_cost("fire", "water") == 12)
	_seed(g)
	g._engine._production_discount = 0.8
	var legacy: Dictionary = g._engine._commit_brew("fire", "water")
	Selftest.check("context empty retains legacy production discount", not bool(legacy.get("failed", true))
		and g._engine.ether == 90 and _allowed(g))

	for shortage in ["fire", "water", "ether", "discovery", "inventory", "recipe", "unknown"]:
		_seed(g)
		match shortage:
			"fire": g._engine.inventory["fire"] = 0
			"water": g._engine.inventory["water"] = 0
			"ether": g._engine.ether = 11
			"discovery":
				g._engine.inventory.erase("steam")
				g._engine.ether = 15
			"inventory": g._engine.inventory["steam"] = Game.CRAFT_INVENTORY_STACK_CAP
			"recipe": g._engine.known_recipes.clear()
		var a := "fire"
		var b := "fire" if shortage == "unknown" else "water"
		var before := _snapshot(g._engine)
		xp = _xp(workshop)
		var result := _commit(g, a, b, _context())
		Selftest.check("context " + shortage + " rejects without partial resource or XP debit",
			bool(result.get("failed", false)) and int(result.get("ether_spent", -1)) == 0
			and int(result.get("mastery_awarded", -1)) == 0 and _snapshot(g._engine) == before
			and _xp(workshop) == xp and Net._queue.is_empty() and _allowed(g))

	_seed(g, 1, 1, 5)
	g._engine.inventory.erase("steam")
	g._engine.ether_overflow = 11
	var reserve := _commit(g, "fire", "water", _context())
	Selftest.check("context real discovery price uses active plus reserve",
		not bool(reserve.get("failed", true)) and int(reserve.get("ether_spent", -1)) == 16
		and g._engine.ether == 0 and g._engine.ether_overflow == 0 and _allowed(g))

	# A known two-identical-input recipe is legal; it requires exactly two.
	g.RECIPES.append({"a": "fire", "b": "fire", "out": "steam"})
	for quantity in [1, 2]:
		_seed(g, quantity)
		g._engine.known_recipes[g._pair_key("fire", "fire")] = true
		var identical := _commit(g, "fire", "fire", _context())
		Selftest.check("context identical pair requires exactly two at stock " + str(quantity),
			bool(identical.get("failed", false)) == (quantity == 1)
			and int(g._engine.inventory["fire"]) == (1 if quantity == 1 else 0)
			and int(g._engine.inventory["steam"]) == (0 if quantity == 1 else 1) and _allowed(g))
	g.RECIPES.pop_back()
	_seed(g, 2)
	var failed: Dictionary = g._engine._commit_brew("fire", "fire")
	Selftest.check("context legacy manual unknown fallback retains debit and refund",
		bool(failed.get("failed", false)) and g._engine.inventory["fire"] == 0
		and g._engine.ether == 100 - Game.BREW_COST + Game.FAILURE_REFUND and _allowed(g))

static func _test_invalid_context(g: Game, workshop) -> void:
	var invalid: Array = []
	for discount in [0.0, -0.1, 1.01, NAN, INF, "0.9", true, null]:
		invalid.append(_context("workshop", discount))
	for source in ["", "gift", "offline", 12, true]:
		invalid.append({"source": source, "production": true, "discount": 1.0})
	invalid.append({"source": "workshop", "production": "true", "discount": 1.0})
	invalid.append({"source": "workshop", "production": false, "discount": 1.0})
	invalid.append({"source": "manual", "production": true, "discount": 1.0})
	invalid.append({"source": "workshop", "production": true})
	invalid.append({"discount": 0.9})
	for i in invalid.size():
		_seed(g)
		var before := _snapshot(g._engine)
		var xp := _xp(workshop)
		var result := _commit(g, "fire", "water", invalid[i])
		Selftest.check("context invalid fields fail closed " + str(i), bool(result.get("failed", false))
			and int(result.get("ether_spent", -1)) == 0 and int(result.get("mastery_awarded", -1)) == 0
			and _snapshot(g._engine) == before and _xp(workshop) == xp and _allowed(g))

static func _test_reentrant(g: Game) -> void:
	var core := g._engine
	var probe := ReentrantCore.new(g)
	_restore(probe, _snapshot(core))
	g._engine = probe
	_seed(g, 5, 5, 1000)
	probe.upgrades.clear()
	probe.mastery_rank = 0
	var observed := {}
	var screen := Control.new()
	g._sigil_ui.add_child(screen)
	g._sigil_ui._sigil_craft_screen = screen
	g._sigil_ui._sigil_pending_craft.clear()
	probe.debit_callback = func() -> void:
		observed["guard"] = not _allowed(g)
		observed["nested"] = _commit(g, "fire", "water", _context())
		observed["upgrade"] = probe._buy_upgrade("ether_regen")
		observed["mastery"] = probe._buy_mastery()
		var ether_before := probe._available_ether()
		var fire_before := int(probe.inventory.get("fire", 0))
		g._sigil_ui._on_sigil_board_confirmed({"id": "context_guard", "ether_cost": 12,
			"ingredients": [{"item_id": "fire", "qty": 1}]})
		observed["sigil"] = probe._available_ether() == ether_before \
			and int(probe.inventory.get("fire", 0)) == fire_before and g._sigil_ui._sigil_pending_craft.is_empty()
	var result := _commit(g, "fire", "water", _context())
	Selftest.check("context guard held before synchronous debit callback", bool(observed.get("guard", false)))
	Selftest.check("context reentrant craft and purchases cannot spend", bool((observed.get("nested", {}) as Dictionary).get("failed", false))
		and observed.get("upgrade", true) == false and observed.get("mastery", true) == false
		and probe.upgrades.is_empty() and probe.mastery_rank == 0)
	Selftest.check("context sigil confirmation cannot debit inside callback", bool(observed.get("sigil", false)))
	Selftest.check("context own spend succeeds and guard releases after callback", not bool(result.get("failed", true))
		and int(result.get("ether_spent", -1)) == 12 and probe.ether == 988 and _allowed(g))
	probe.debit_callback = Callable()
	g._sigil_ui._close_sigil_craft_screen()
	g._sigil_ui._close_sigil_craft_ritual()
	g._sigil_ui._sigil_pending_craft.clear()
	Net._queue.clear()
	g._engine = core

static func _test_offline(g: Game) -> void:
	_seed(g, 2, 2, 1000)
	g._online._net_enabled = true
	g._online._device_id = "context_fixture"
	Net._available = true
	Net._queue.clear()
	g._riddles._letter_today = {"solved": false}
	g._riddles._atlas_today = {"solved_by_me": false}
	g._riddles._letter_pending.clear()
	g._riddles._atlas_pending.clear()
	g._retention._circle_disc_day = g._retention._circle_today()
	g._retention._circle_disc = 0
	var quest_before := int(g._guild._quest_brew.get("steam", 0))
	g._selftest = false
	var first := _commit(g, "fire", "water", _context("offline_workshop"))
	var second := _commit(g, "fire", "water", _context("offline_workshop"))
	g._selftest = true
	Selftest.check("context offline suppresses per-operation HTTP without changing network state",
		not bool(first.get("failed", true)) and not bool(second.get("failed", true))
		and Net._queue.is_empty() and g._online._net_enabled)
	Selftest.check("context offline retains local quests and Circle per real output",
		int(g._guild._quest_brew.get("steam", 0)) == quest_before + 2 and g._retention._circle_disc == 2)
	Selftest.check("context offline retains deduplicated deferred riddle work",
		g._riddles._letter_pending == [g._pair_key("fire", "water")]
		and g._riddles._atlas_pending == [g._pair_key("fire", "water")])
	var blueprint_xp := _xp(g.get("_workshop"))
	g._engine._record_blueprint("steam", {"total": 1, "ops": []})
	Selftest.check("context blueprint recording adds no duplicate mastery",
		g._engine._blueprints.has("steam") and _xp(g.get("_workshop")) == blueprint_xp and _allowed(g))
	Net._queue.clear()

static func _snapshot(object: Object) -> Dictionary:
	var state := {}
	for property in object.get_property_list():
		var name := String(property.get("name", ""))
		if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE and name not in ["g", "main"]:
			var value = object.get(name)
			state[name] = value.duplicate(true) if value is Dictionary or value is Array else value
	return state

static func _restore(object: Object, state: Dictionary) -> void:
	for name in state:
		var value = state[name]
		object.set(name, value.duplicate(true) if value is Dictionary or value is Array else value)
