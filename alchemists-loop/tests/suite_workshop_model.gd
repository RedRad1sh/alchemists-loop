extends RefCounted
const Model = preload("res://game/lab/workshop.gd")
const Fixture = preload("res://tests/workshop_fixture.gd")

static func run(g: Game) -> void:
	var fixture := Fixture.new(g)
	fixture.prepare_production()
	var w := Model.new(g)
	Selftest.check("workshop purchases API exists", w.has_method("buy_rank") and w.has_method("buy_autonomy"))
	Selftest.check("workshop queue API exists", w.has_method("enqueue") and w.has_method("reorder")
		and w.has_method("remove_job") and w.has_method("set_line_paused"))
	if w.has_method("buy_rank"):
		_purchases(g, w)
	if w.has_method("enqueue"):
		_queues(g, w)
	_imports(g, w)
	fixture.finish()

static func _purchases(g: Game, w) -> void:
	w.reset_new_game()
	w.xp = 1000
	stock_equipment(g)
	var stock := g._engine.inventory.duplicate(true)
	Selftest.check("locked equipment purchase refuses", not w.buy_rank(1).get("ok", false)
		and g._engine.inventory == stock)
	w.unlocked = true
	Selftest.check("rank cannot skip previous equipment", not w.buy_rank(2).get("ok", false) and w.rank == 0)
	for next in range(1, 4):
		var recipe: Dictionary = WorkshopBalance.RANKS[next]
		w.xp = int(recipe["xp"]) - 1
		stock_equipment(g)
		g._engine.ether = int(recipe["ether"])
		g._engine.ether_overflow = 0
		stock = g._engine.inventory.duplicate(true)
		Selftest.check("rank %d below XP threshold refuses atomically" % next,
			not w.buy_rank(next).get("ok", false) and g._engine.inventory == stock
			and g._engine.ether == int(recipe["ether"]))
		w.xp += 1
		var material: String = recipe["materials"].keys()[0]
		g._engine.inventory[material] = int(recipe["materials"][material]) - 1
		stock = g._engine.inventory.duplicate(true)
		Selftest.check("rank %d material shortage spends nothing" % next,
			not w.buy_rank(next).get("ok", false) and g._engine.inventory == stock
			and g._engine.ether == int(recipe["ether"]))
		stock_equipment(g)
		g._engine.ether -= 1
		Selftest.check("rank %d ether shortage spends nothing" % next,
			not w.buy_rank(next).get("ok", false) and g._engine.inventory[material] == 100)
		var known := g._engine.known_recipes.duplicate()
		for r in g.RECIPES:
			if r["out"] == material:
				g._engine.known_recipes.erase(g._pair_key(r["a"], r["b"]))
		g._engine.ether = int(recipe["ether"])
		Selftest.check("rank %d gifted material does not replace recipe" % next,
			not w.buy_rank(next).get("ok", false) and w.rank == next - 1)
		g._engine.known_recipes = known
		g._engine.ether = 10
		g._engine.ether_overflow = int(recipe["ether"]) - 10
		Selftest.check("rank %d exact threshold buys from reserve without spending XP" % next,
			w.buy_rank(next).get("ok", false) and w.rank == next and w.xp == int(recipe["xp"])
			and g._engine._available_ether() == 0 and w.line_count() == next + 1
			and w.queue_capacity() == next + 1 and w.lines.size() == next + 1)
		var correct := true
		for item in recipe["materials"]:
			correct = correct and g._engine.inventory[item] == 100 - int(recipe["materials"][item])
		Selftest.check("rank %d spends each material exactly once" % next, correct)
		stock = g._engine.inventory.duplicate(true)
		Selftest.check("rank %d duplicate purchase cannot charge twice" % next,
			not w.buy_rank(next).get("ok", false) and g._engine.inventory == stock)
	Selftest.check("rank above maximum refuses", not w.buy_rank(4).get("ok", false))
	w.reset_new_game()
	w.unlocked = true
	stock_equipment(g)
	g._engine.ether = 2000
	Selftest.check("autonomy requires equipment rank", not w.buy_autonomy().get("ok", false)
		and w.offline_stage_limit() == 60)
	w.rank = 1
	Selftest.check("first autonomy buys exact materials and ether", w.buy_autonomy().get("ok", false)
		and w.autonomy_level == 1 and w.offline_stage_limit() == 120
		and g._engine.ether == 1850 and g._engine.inventory["glass"] == 85
		and g._engine.inventory["metal"] == 90)
	Selftest.check("second autonomy requires engineer", not w.buy_autonomy().get("ok", false))
	w.rank = 2
	Selftest.check("second autonomy buys exact materials and ether", w.buy_autonomy().get("ok", false)
		and w.offline_stage_limit() == 240 and g._engine.ether == 1550
		and g._engine.inventory["tool"] == 85 and g._engine.inventory["crystal"] == 90)
	Selftest.check("maximum autonomy cannot buy twice", not w.buy_autonomy().get("ok", false))
	w.reset_new_game()
	w.unlocked = true
	w.xp = 100
	stock_equipment(g)
	g._engine.ether = 1000
	if g._engine.has_method("_resource_mutation_allowed"):
		var old_busy: Variant = g._engine.get("_resource_commit_busy")
		g._engine.set("_resource_commit_busy", true)
		Selftest.check("equipment honors synchronous Core resource guard", not w.buy_rank(1).get("ok", false)
			and g._engine.ether == 1000 and g._engine.inventory["brick"] == 100)
		g._engine.set("_resource_commit_busy", old_busy)

static func stock_equipment(g: Game) -> void:
	for item in ["brick", "metal", "glass", "tool", "crystal", "gold"]:
		g._engine.inventory[item] = 100

static func _queues(g: Game, w) -> void:
	w.reset_new_game()
	var id: String = w.lines[0]["id"]
	Selftest.check("locked workshop rejects queue", not w.enqueue(id, job("steam", 1)).get("ok", false))
	w.unlocked = true
	for amount in ["1", 1.0, 1.5, true, -1, 0, Game.CRAFT_INVENTORY_STACK_CAP + 1]:
		Selftest.check("queue rejects command amount " + str(amount), not w.enqueue(id, job("steam", amount)).get("ok", false))
	Selftest.check("queue rejects invalid line target and mode", not w.enqueue("missing", job("steam", 1)).get("ok", false)
		and not w.enqueue(id, job("fire", 1)).get("ok", false)
		and not w.enqueue(id, job("unknown", 1)).get("ok", false)
		and not w.enqueue(id, {"target": "steam", "amount": 1, "mode": "wrong"}).get("ok", false))
	var stock := g._engine.inventory.duplicate(true)
	var ether: int = g._engine._available_ether()
	var queued: Dictionary = w.enqueue(id, job("steam", Game.CRAFT_INVENTORY_STACK_CAP))
	Selftest.check("queue spends no inputs and accepts global stack cap", queued.get("ok", false)
		and g._engine.inventory == stock and g._engine._available_ether() == ether
		and w.lines[0]["queue"].size() == 1 and w.lines[0]["queue"][0]["produced"] == 0)
	Selftest.check("active job counts toward queue capacity", not w.enqueue(id, job("stone", 1)).get("ok", false))
	w.lines[0]["queue"][0]["produced"] = 1
	g._engine.inventory["steam"] = 1
	var job_id: String = w.lines[0]["queue"][0]["id"]
	Selftest.check("remove retains actual output", w.remove_job(id, job_id)
		and g._engine.inventory["steam"] == 1 and w.lines[0]["queue"].is_empty())
	Selftest.check("remove unknown IDs refuses", not w.remove_job("missing", job_id) and not w.remove_job(id, "missing"))
	for r in range(4):
		w.import_state({"version": 1, "unlocked": true, "rank": r}, {})
		id = w.lines[0]["id"]
		for n in r + 1:
			Selftest.check("rank %d queue slot %d is available" % [r, n], w.enqueue(id, job("steam", 1)).get("ok", false))
		Selftest.check("rank %d capacity boundary refuses" % r, not w.enqueue(id, job("stone", 1)).get("ok", false))
	w.import_state({"version": 1, "unlocked": true, "rank": 2}, {})
	id = w.lines[0]["id"]
	w.enqueue(id, {"id": "j_one", "target": "steam", "mode": "batch", "amount": 3})
	w.enqueue(id, {"id": "j_two", "target": "stone", "mode": "stock", "amount": 5})
	Selftest.check("duplicate and invalid job IDs refuse", not w.enqueue(id, {"id": "j_one", "target": "brick", "mode": "batch", "amount": 1}).get("ok", false)
		and not w.enqueue(id, {"id": "../bad", "target": "brick", "mode": "batch", "amount": 1}).get("ok", false))
	Selftest.check("queue reorders stable jobs", w.reorder(id, 0, 1) and w.lines[0]["queue"][0]["id"] == "j_two")
	Selftest.check("queue reorder invalid indices refuse", not w.reorder(id, -1, 0) and not w.reorder(id, 0, 2))
	Selftest.check("line pauses and resumes independently", w.set_line_paused(id, true)
		and w.lines[0]["paused"] and not w.lines[1]["paused"] and w.set_line_paused(id, false))
	var snapshot: Dictionary = w.export_state()
	var restored := Model.new(g)
	restored.import_state(JSON.parse_string(JSON.stringify(snapshot)), {})
	Selftest.check("queue stable IDs modes and order survive JSON", restored.lines[0]["queue"][0]["id"] == "j_two"
		and restored.lines[0]["queue"][0]["mode"] == "stock" and restored.lines[0]["queue"][1]["id"] == "j_one")

static func job(target: String, amount: Variant) -> Dictionary:
	return {"target": target, "mode": "batch", "amount": amount}

static func _imports(g: Game, w) -> void:
	g._engine.inventory["person"] = 1
	w.import_state(null, {"bench_target": "steam", "bench_on": true, "last_ts": 1234.5,
		"craft_job": {"item": "brick"}, "successes": 9999})
	Selftest.check("legacy opens without retroactive mastery", w.unlocked and w.xp == 0 and w.rank == 0
		and w.autonomy_level == 0 and w.lines.size() == 1 and w.last_simulated_at == 1234.5)
	Selftest.check("legacy bench migrates once to stock global cap without craft duplicate",
		w.lines[0]["queue"].size() == 1 and w.lines[0]["queue"][0]["target"] == "steam"
		and w.lines[0]["queue"][0]["mode"] == "stock"
		and w.lines[0]["queue"][0]["amount"] == Game.CRAFT_INVENTORY_STACK_CAP)
	var saved: Dictionary = w.export_state()
	w.import_state(saved, {"bench_target": "stone", "bench_on": true})
	Selftest.check("v1 never repeats legacy migration", w.lines[0]["queue"].size() == 1
		and w.lines[0]["queue"][0]["target"] == "steam")
	w.import_state({"version": 1, "xp": -8, "rank": "3", "autonomy_level": 1.5, "scheduler_cursor": -1,
		"last_simulated_at": "1000", "lines": [{"id": "../bad", "phase_seconds": -1,
		"stage_credit": -2, "queue": []}]}, {})
	Selftest.check("malformed v1 integers default without reward clamp", w.xp == 0 and w.rank == 0
		and w.autonomy_level == 0 and w.scheduler_cursor == 0 and w.lines[0]["stage_credit"] == 0
		and w.lines[0]["phase_seconds"] == 0.0 and w.lines[0]["id"] == "line_1"
		and w.last_simulated_at > 0.0)
	var blocked := {"id": "j_unknown", "target": "future_material", "mode": "batch", "amount": 4.0,
		"produced": 2.0, "status": "running", "reason": "", "route_operations": 9.0}
	w.import_state({"version": 1.0, "unlocked": true, "xp": 100.0, "rank": 1.0,
		"lines": [{"id": "line_custom", "stage_credit": 999, "queue": [blocked]}]}, {})
	Selftest.check("saved integer JSON floats accepted", w.xp == 100 and w.rank == 1)
	Selftest.check("invalid saved target waits without losing progress", w.lines[0]["queue"][0]["status"] == "waiting_recipe"
		and w.lines[0]["queue"][0]["produced"] == 2 and w.lines[0]["queue"][0]["route_operations"] == 9)
	Selftest.check("invalid stage credit cannot mint a ready stage", w.lines[0]["stage_credit"] == 0)
	var duplicate_job := {"id": "same_job", "target": "steam", "mode": "batch", "amount": 3,
		"produced": 8, "route_operations": -1}
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "scheduler_cursor": 99,
		"lines": [{"id": "same_line", "phase_seconds": 999, "queue": [duplicate_job, duplicate_job, duplicate_job]},
		{"id": "same_line", "queue": [duplicate_job]}]}, {})
	Selftest.check("loaded line and job IDs are unique and queues bounded", w.lines[0]["id"] != w.lines[1]["id"]
		and w.lines[0]["queue"].size() == 2 and w.lines[0]["queue"][0]["id"] != w.lines[0]["queue"][1]["id"]
		and w.lines[0]["queue"][0]["id"] != w.lines[1]["queue"][0]["id"])
	Selftest.check("malformed batch progress cannot finish unproduced outputs", w.lines[0]["queue"][0]["produced"] == 0
		and w.lines[0]["queue"][0]["route_operations"] == 0 and w.scheduler_cursor == 0
		and w.lines[0]["phase_seconds"] == 0.0)
	var future := {"version": 5, "unlocked": true, "xp": 1000, "future_nested": {"unknown": [1, 2, {"x": "y"}]},
		"lines": [{"custom": "schema"}]}
	var original := future.duplicate(true)
	var observed: Array = []
	var observe_import := func() -> void:
		observed.append(w.export_state())
	w.changed.connect(observe_import)
	Selftest.check("future version becomes read only", not w.import_state(future, {}).get("ok", true) and w.is_read_only())
	w.changed.disconnect(observe_import)
	Selftest.check("import publishes only the complete supported or passthrough state", observed.size() == 1
		and observed[0] == original)
	future["future_nested"]["unknown"].append(99)
	var exported: Dictionary = w.export_state()
	exported["future_nested"]["unknown"].append(88)
	Selftest.check("future version deep passthrough is immutable", w.export_state() == original and w.on_synthesis("person") == 0)
	if w.has_method("buy_rank"):
		Selftest.check("future purchase commands refuse", not w.buy_rank(1).get("ok", false) and not w.buy_autonomy().get("ok", false))
	if w.has_method("enqueue"):
		Selftest.check("future queue commands refuse", not w.enqueue("line_1", job("steam", 1)).get("ok", false)
			and not w.remove_job("line_1", "j") and not w.reorder("line_1", 0, 0) and not w.set_line_paused("line_1", true))
	w.reset_prestige()
	Selftest.check("future prestige retains unsupported source", w.export_state() == original)
	w.reset_new_game()
	Selftest.check("explicit new game clears unsupported source", not w.is_read_only() and w.export_state()["version"] == 1)
