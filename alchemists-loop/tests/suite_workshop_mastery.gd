extends RefCounted

static func run(g: Game) -> void:
	Selftest.check("mastery_module_exists", g.get("_workshop") != null)
	var path := "res://game/lab/workshop.gd"
	Selftest.check("mastery_model_script_exists", FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		return
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		Selftest.check("mastery model instantiates", false)
		return
	var fixture = load("res://tests/workshop_fixture.gd").new(g)
	fixture.prepare_production()
	var w = script.new(g)
	Selftest.check("mastery starts locked without retroactive xp", not w.unlocked and w.xp == 0)
	Selftest.check("mastery locked synthesis earns zero", w.on_synthesis("steam") == 0)
	var person_depth: int = g._engine._content_layer("person")
	Selftest.check("person opens before its own mastery award", w.on_synthesis("person") == mini(person_depth, 6)
		and w.unlocked and w.xp == mini(person_depth, 6))
	w.xp = 0
	for item in ["steam", "brick", "tool"]:
		w.on_synthesis(item)
	Selftest.check("actual depth 1 2 4 sums seven", w.xp == 7)
	var xp_before: int = w.xp
	Selftest.check("base unknown and sentinel outputs earn zero", w.on_synthesis("fire") == 0
		and w.on_synthesis("no_workshop_recipe") == 0 and w.xp == xp_before)
	g.ITEMS["st_bad_depth"] = {"name": "Bad depth"}
	for bad in [0, -1, 1 << 29, "6", 2.5, true]:
		g._online._server_layers["st_bad_depth"] = bad
		Selftest.check("invalid mastery depth rejected " + str(bad), w.on_synthesis("st_bad_depth") == 0)
	g._online._server_layers["st_bad_depth"] = 12
	Selftest.check("valid deep output awards capped six", w.on_synthesis("st_bad_depth") == 6)
	w.rank = 2
	w.autonomy_level = 1
	w.lines[0]["phase_seconds"] = 17.0
	w.lines[0]["queue"] = [{"id": "j_saved", "target": "brick", "mode": "batch", "amount": 4,
		"produced": 2, "status": "running", "reason": "", "route_operations": 1}]
	var saved: Dictionary = w.export_state()
	var restored = script.new(g)
	var result: Dictionary = restored.import_state(JSON.parse_string(JSON.stringify(saved)), {})
	Selftest.check("mastery v1 JSON roundtrip", result.get("ok", false) and restored.xp == w.xp
		and restored.rank == 2 and restored.autonomy_level == 1 and restored.lines[0]["queue"][0]["produced"] == 2)
	var archive_rank: int = g._engine.mastery_rank
	restored.reset_prestige()
	Selftest.check("model prestige preserves equipment and clears world work", restored.unlocked
		and restored.xp == w.xp and restored.rank == 2 and restored.autonomy_level == 1
		and restored.lines[0]["queue"].is_empty() and restored.lines[0]["phase_seconds"] == 0.0
		and g._engine.mastery_rank == archive_rank)
	restored.reset_new_game()
	Selftest.check("model new game clears all mastery", not restored.unlocked and restored.xp == 0
		and restored.rank == 0 and restored.autonomy_level == 0 and restored.lines.size() == 1)
	if g.get("_workshop") != null:
		await _integration(g, fixture)
	fixture.finish()

static func _integration(g: Game, fixture) -> void:
	var w = g.get("_workshop")
	w.reset_new_game()
	fixture.prepare_production()
	g._engine.inventory["life"] = 1
	g._engine.inventory["clay"] = 1
	var person := g._engine._commit_brew("life", "clay")
	Selftest.check("mastery_new_discovery_once", not person.get("failed", true) and w.unlocked
		and w.xp == mini(g._engine._content_layer("person"), 6))
	var first_xp: int = w.xp
	g._engine._grant_first_open("person")
	Selftest.check("mastery discovery popup grant cannot double award", w.xp == first_xp)
	fixture.prepare_production()
	w.unlocked = true
	w.xp = 0
	_register_chain(g)
	g._engine.mastery_rank = 0
	var plan: Dictionary = g._guild._plan_craft("st_w_depth4")
	Selftest.check("mastery real three-operation route is available", plan.get("ok", false) and plan.get("total", 0) == 3)
	if plan.get("ok", false):
		await g._engine._run_auto_plan("st_w_depth4", plan)
		Selftest.check("mastery_real_chain_sum", w.xp == 7
			and g._engine.inventory.get("st_w_depth4", 0) == 1 and g._engine._craft_job.is_empty())
		g._engine._record_blueprint("st_w_depth4", plan)
		Selftest.check("mastery full route completion cannot double award", w.xp == 7)
	fixture.prepare_production()
	w.unlocked = true
	w.xp = 0
	var cancel_after_two := func() -> void:
		if w.xp >= 3:
			g._engine._stop_auto()
	w.changed.connect(cancel_after_two)
	plan = g._guild._plan_craft("st_w_depth4")
	if plan.get("ok", false):
		await g._engine._run_auto_plan("st_w_depth4", plan)
		Selftest.check("mastery_cancel_keeps_completed", w.xp == 3
			and g._engine.inventory.get("st_w_depth2", 0) == 1 and g._engine.inventory.get("st_w_depth4", 0) == 0
			and g._engine._craft_job.get("completed", 0) == 2)
	w.changed.disconnect(cancel_after_two)
	fixture.prepare_production()
	w.unlocked = true
	w.xp = 0
	# Sources, spring, gifts and failed commits all exercise their real entry points.
	g._engine._collect("fire", true)
	g._engine.spring_on = true
	g._engine._spring_tick(Game.SPRING_INTERVAL)
	g._engine.upgrades["gift"] = 1
	g._engine._gift_tick(Game.GIFT_INTERVAL)
	g._engine.inventory["water"] = 0
	g._engine._commit_brew("fire", "water")
	Selftest.check("mastery_sources_gifts_fail_zero", w.xp == 0)
	_network(g, w)
	# Actual controller entry points, not calls to the model's reset helpers.
	w.xp = 777
	w.rank = 2
	w.autonomy_level = 1
	w.import_state({"version": 1, "unlocked": true, "xp": 777, "rank": 2, "autonomy_level": 1}, {})
	var id: String = w.lines[0]["id"]
	if w.has_method("enqueue"):
		w.enqueue(id, {"target": "steam", "mode": "batch", "amount": 3})
	w.lines[0]["phase_seconds"] = 12.5
	var expected: Dictionary = w.export_state()
	g._saves._save_frozen = false
	g._saves._save_game()
	# Saving is the authoritative online clock boundary; retain full equipment,
	# queue and phase equality while comparing its actually persisted timestamp.
	expected["last_simulated_at"] = g._saves._read_save(g.SAVE_PATH)["workshop"]["last_simulated_at"]
	g._saves._save_frozen = true
	w.reset_new_game()
	g._saves._load_game()
	Selftest.check("mastery_roundtrip_actual_save", w.export_state() == expected)
	for n in 35:
		g._engine.inventory["st_prestige_%d" % n] = 1
	g._hub._do_prestige()
	Selftest.check("mastery_actual_prestige_keeps_permanent_equipment", w.unlocked and w.xp == 777
		and w.rank == 2 and w.autonomy_level == 1 and w.lines[0]["queue"].is_empty()
		and w.lines[0]["phase_seconds"] == 0.0)
	# Independent reset precondition; an earlier failed load must not mask reset.
	w.unlocked = true
	w.xp = 333
	w.rank = 1
	g._init_new_game()
	Selftest.check("mastery_actual_new_game_clears_all", not w.unlocked and w.xp == 0
		and w.rank == 0 and w.autonomy_level == 0 and w.lines.size() == 1)

static func _register_chain(g: Game) -> void:
	var recipes := [
		{"a": "fire", "b": "water", "out": "st_w_depth1"},
		{"a": "st_w_depth1", "b": "earth", "out": "st_w_depth2"},
		{"a": "st_w_depth2", "b": "air", "out": "st_w_depth4"}]
	# Replace the pair in this fixture world; restore reinstates the original DAG.
	for recipe in recipes:
		var item: String = recipe["out"]
		g.ITEMS[item] = {"name": item, "color": "#778899", "g": "fire"}
		g._item_colors[item] = Color("#778899")
		g._online._server_layers[item] = int(item.right(1))
		for n in range(g.RECIPES.size() - 1, -1, -1):
			var existing: Dictionary = g.RECIPES[n]
			if g._pair_key(existing["a"], existing["b"]) == g._pair_key(recipe["a"], recipe["b"]):
				g.RECIPES.remove_at(n)
		g.RECIPES.append(recipe)
		g._engine.known_recipes[g._pair_key(recipe["a"], recipe["b"])] = true

static func _network(g: Game, w) -> void:
	var a := "fire"
	var b := "air"
	var pair: String = g._pair_key(a, b)
	var out := {"slug": "st_mastery_online", "name": "Mastery test", "color": "#778899", "layer": 4,
		"a": a, "b": b, "reused": true}
	var result := {"ok": true, "found": true, "status": "known", "out": out}
	g._online._register_pending_pair(a, b, false)
	g._online._on_net_pair_result(pair, result)
	Selftest.check("mastery confirmed online discovery awards exactly once", w.xp == 4)
	g._online._on_net_pair_result(pair, result)
	g._online._on_net_discover_result(pair, {"status": "created", "discovery": out})
	Selftest.check("mastery_network_duplicate_stale_zero", w.xp == 4)
	# Real paid experiment: correlation and pending guards still control award.
	g._engine.known_recipes.erase(pair)
	g._engine._experiment_last_at = 0.0
	g._engine._experiment_count = 0
	g._engine._experiment_day = ""
	var began: bool = g._engine._begin_experiment(a, b)
	Selftest.check("mastery paid experiment begins with real debit", began)
	if began:
		g._online._register_pending_pair(a, b, true)
		g._online._on_net_pair_result(pair, result)
		Selftest.check("mastery paid experiment awards once", w.xp == 8)
		g._online._on_net_pair_result(pair, result)
		Selftest.check("mastery paid experiment duplicate adds zero", w.xp == 8)
	var xp_before: int = w.xp
	g._online._register_pending_pair(a, b, false)
	g._online._pending_requests[pair]["at"] = Time.get_ticks_msec() - Online.PENDING_TTL_MSEC - 1
	g._online._on_net_pair_result(pair, result)
	Selftest.check("mastery expired online answer adds zero", w.xp == xp_before)
	for invalid_layer in [0, -1, 1 << 29, "6", 2.5, true]:
		var invalid_out := out.duplicate(true)
		invalid_out["layer"] = invalid_layer
		g._online._register_pending_pair(a, b, false)
		g._online._on_net_pair_result(pair, {"ok": true, "found": true, "status": "known", "out": invalid_out})
		Selftest.check("mastery invalid server response depth gives zero " + str(invalid_layer), w.xp == xp_before)
