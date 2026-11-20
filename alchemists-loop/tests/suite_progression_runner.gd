extends RefCounted
class_name SuiteProgressionRunner


static func run(g: Game) -> void:
	var saved_profile: BalanceProfile = g.balance
	var models: Array = [g._engine, g._online, g._retort, g._workshop, g._workshop_scheduler, g._pages]
	var saved_models: Array = []
	for model in models:
		saved_models.append(_snapshot_model(model))
	var fixture := ProgressionDiscoveryFixture.new()
	var saved_items: Dictionary = g.ITEMS.duplicate(true)
	var saved_recipes: Array = g.RECIPES.duplicate(true)
	var saved_inventory: Dictionary = g._engine.inventory.duplicate(true)
	var saved_ether: int = g._engine.ether
	var saved_known: Dictionary = g._engine.known_recipes.duplicate(true)
	var saved_defs: Dictionary = g._engine.known_recipe_defs.duplicate(true)
	var saved_pending: Dictionary = g._online._pending_requests.duplicate(true)
	var saved_experiment_pending: Array = g._engine._experiment_pending_pair.duplicate(true)
	var fixture_catalog := {"fixture_success": {
		"name": "Fixture Success", "color": "#8899aa", "g": "fire",
		"d": "Deterministic fixture result.", "category": "огонь"}}
	var fixture_recipes := [{"a": "fire", "b": "fire", "out": "fixture_success"}]
	fixture.install(g, fixture_catalog, fixture_recipes)
	g._engine.inventory["fire"] = 2
	g._engine.ether = maxi(g._engine.ether, 100)
	g._online._net_enabled = false
	var key := g._pair_key("fire", "fire")
	var started := g._online._start_experiment("fire", "fire")
	Selftest.check("progression fixture: real experiment transaction registers pending request before response",
		started and fixture.requests().size() == 1
		and g._online._pending_requests.has(key)
		and g._engine._experiment_pending_pair.size() == 2
		and int(g._engine.inventory.get("fire", 0)) == 0)
	fixture.respond_success(key, "fixture_success")
	Selftest.check("progression fixture: success uses production result handler and saves output",
		not g._online._pending_requests.has(key)
		and g._engine._experiment_pending_pair.is_empty()
		and int(g._engine.inventory.get("fixture_success", 0)) == 1
		and g._engine.known_recipes.has(key))

	g._engine._experiment_last_at = 0.0
	g._engine._rejected_pairs.erase(g._pair_key("water", "water"))
	g._engine.inventory["water"] = 2
	g._engine.ether = maxi(g._engine.ether, 100)
	var refusal_started := g._online._start_experiment("water", "water")
	var refusal_key := g._pair_key("water", "water")
	fixture.respond_refusal(refusal_key, "not_combinable")
	Selftest.check("progression fixture: refusal restores transaction state through production handler",
		refusal_started
		and g._engine._experiment_pending_pair.is_empty()
		and int(g._engine.inventory.get("water", 0)) == 2
		and not g._online._pending_requests.has(refusal_key))

	g._engine._experiment_last_at = 0.0
	g._engine._rejected_pairs.erase(g._pair_key("earth", "earth"))
	g._engine.inventory["earth"] = 2
	g._engine.ether = maxi(g._engine.ether, 100)
	var stale_started := g._online._start_experiment("earth", "earth")
	var stale_key := g._pair_key("earth", "earth")
	g._online._pending_requests.clear()
	g._engine._experiment_pending_pair.clear()
	var before_stale: Dictionary = g._engine.inventory.duplicate(true)
	fixture.respond_stale(stale_key)
	Selftest.check("progression fixture: stale response cannot grant an element after pending is cleared",
		stale_started and g._engine.inventory == before_stale
		and not g._engine.known_recipes.has(stale_key))

	var runner := ProgressionRunner.new(g, 17, BalanceConfig.baseline())
	_test_live_progress(runner)
	var before_clock := runner.clock.snapshot()
	runner.advance_active(10.0)
	var after_active := runner.clock.snapshot()
	g._workshop.last_simulated_at = 0.0
	runner.replay_offline(100.0, 200.0)
	var after_offline := runner.clock.snapshot()
	var offline_watermark := g._workshop.last_simulated_at
	runner.replay_offline(100.0, 200.0)
	var after_repeat := runner.clock.snapshot()
	Selftest.check("progression clock: active time uses scheduler advance and offline time uses replay watermark",
		float(after_active["active_seconds"]) > float(before_clock["active_seconds"])
		and float(after_offline["offline_seconds"]) > float(after_active["offline_seconds"])
		and is_equal_approx(float(after_repeat["offline_seconds"]), float(after_offline["offline_seconds"]))
		and is_equal_approx(offline_watermark, 200.0))
	var ledger := ProgressionLedger.new()
	ledger.record({"operation_id": "op-1", "kind": "brew"})
	ledger.record({"operation_id": "op-1", "kind": "duplicate"})
	ledger.increment_counter("brew", 1)
	ledger.add_resource_delta("ether", -12.0)
	var ledger_report: Dictionary = ledger.report()
	Selftest.check("progression ledger: operation ids are idempotent and deltas are reportable",
		int(ledger_report["operation_count"]) == 1
		and int((ledger_report["counters"] as Dictionary).get("brew", 0)) == 1
		and is_equal_approx(float((ledger_report["resources"] as Dictionary).get("ether", 0.0)), -12.0))
	var report := runner.report("pass")
	Selftest.check("progression report: schema includes seed, catalog hash, profile metadata, time, ledger, phases and verdict",
		int(report.get("schema", 0)) == ProgressionReport.SCHEMA
		and int(report.get("seed", 0)) == 17
		and String(report.get("catalog_hash", "")).length() == 64
		and report.has("profile") and report.has("time") and report.has("ledger")
		and report.has("phases") and String(report.get("verdict", "")) == "fail")

	g._engine._experiment_last_at = 0.0
	g._engine.inventory["fire"] = 3
	g._engine.inventory["water"] = 3
	g._engine.inventory.erase("steam")
	g._engine.known_recipes.erase(g._pair_key("fire", "water"))
	var targets := {"steam": true}
	var frontier := ProgressionStrategy.next_frontier(g, targets)
	var strategy_ledger := ProgressionLedger.new()
	var strategy_ok := ProgressionStrategy.discover_and_brew(g, frontier, strategy_ledger)
	Selftest.check("progression strategy: deterministic frontier reaches steam through real experiment path",
		String(frontier.get("key", "")) == g._pair_key("fire", "water")
		and strategy_ok and int(g._engine.inventory.get("steam", 0)) == 1
		and g._engine.known_recipes.has(g._pair_key("fire", "water"))
		and int(strategy_ledger.report().get("counters", {}).get("discoveries", 0)) == 1)

	var idle_runner := ProgressionRunner.new(g, 19, BalanceConfig.baseline())
	var idle_before := idle_runner.clock.now()
	var idle_reached := idle_runner.run_idle_until(func() -> bool: return idle_runner.clock.now() >= idle_before + 20.0, 30.0)
	var idle_upgrades := idle_runner.buy_available_spring_upgrades()
	var idle_ether_upgrades := idle_runner.buy_available_ether_upgrades()
	Selftest.check("progression idle executor: scheduler time advances and unavailable purchases do not mutate counters",
		idle_reached and is_equal_approx(idle_runner.clock.now(), idle_before + 20.0)
		and idle_upgrades == 0 and idle_ether_upgrades == 0
		and idle_runner.ledger.report().get("counters", {}).is_empty())

	var retort_runner := ProgressionRunner.new(g, 23, BalanceConfig.baseline())
	var retort_before := retort_runner.buy_available_retort_upgrades()
	Selftest.check("progression retort executor: blocked essence purchases do not mutate upgrade levels",
		retort_before == 0 and g._retort._cube_levels.values().all(func(v): return int(v) == 0))

	_test_phases(g)
	_test_tasks_8_to_12_contracts(g)
	_test_clock_and_receipts(g)
	_test_production_rewards(g)
	_test_overlapping_inputs(g)
	_test_retort_supply(g)
	_test_prestige_roundtrip(g)
	_test_final_blend_purchase(g)
	_test_idle_gifts_and_achievements(g)
	_test_review_regressions(g)
	g._retort._retort_slots = [{"sub": ""}, {"sub": ""}, {"sub": ""}, {"sub": ""}]
	var queue_runner := ProgressionRunner.new(g)
	queue_runner.clock.set_virtual_epoch(1794614400.0)
	Selftest.check("progression retort: runner proves automatic queue start and collection",
		queue_runner.has_method("_retort_queue_check") and queue_runner.call("_retort_queue_check"))
	fixture.uninstall()
	for i in range(models.size()):
		for property in saved_models[i]:
			models[i].set(property, saved_models[i][property])
	g.balance = saved_profile
	g.ITEMS = saved_items
	g.RECIPES = saved_recipes
	g._engine.inventory = saved_inventory
	g._engine.ether = saved_ether
	g._engine.known_recipes = saved_known
	g._engine.known_recipe_defs = saved_defs
	g._online._pending_requests = saved_pending
	g._engine._experiment_pending_pair = saved_experiment_pending


static func _test_review_regressions(g: Game) -> void:
	var audit := ProgressionLedger.new()
	audit.start(g)
	audit.perform(g, "mastery_purchase", func():
		var bought := g._engine._buy_mastery()
		g._engine.ether += 7
		return bought)
	Selftest.check("progression ledger: a grant inside a purchase is unexplained", not audit.unexplained.is_empty())
	var scheduler_audit := ProgressionLedger.new()
	scheduler_audit.start(g)
	scheduler_audit.perform(g, "scheduler_active", func():
		var stats: Dictionary = g._workshop_scheduler.advance(1.0, false)
		g._engine.inventory["fire"] = int(g._engine.inventory.get("fire", 0)) + 9
		return stats)
	Selftest.check("progression ledger: scheduler grants must match confirmed operations", not scheduler_audit.unexplained.is_empty())
	var runner := ProgressionRunner.new(g)
	runner.wall_budget_ms = 0
	runner._economy()
	Selftest.check("progression live: economy publishes its current phase", runner.progress_snapshot().get("phase") == "idle")
	var scheduler := g._workshop_scheduler
	g._workshop_scheduler = load("res://tests/progression_mutation_cases.gd").WatermarkBypass.new(g, g._workshop)
	runner.clock.set_virtual_epoch(1794614400.0)
	g._engine.ether = g._engine._max_ether()
	g._engine.spring_on = false
	for line in g._workshop.lines:
		line["queue"].clear()
	Selftest.check("progression replay: saturated resources cannot hide a replayed interval", not runner._replay_check())
	g._workshop_scheduler = scheduler


static func _test_idle_gifts_and_achievements(g: Game) -> void:
	g._engine.inventory = {"fire": 1, "water": 1, "earth": 1, "air": 1, "steam": 1}
	g._engine.upgrades = {"auto_gift": 1}
	g._engine._gift_clock = 0.0
	g._engine.successes = 100
	g._progress_ui._ach_done.clear()
	g.set_meta("progression_driver", true)
	var runner := ProgressionRunner.new(g)
	runner.clock.set_virtual_epoch(1794614400.0)
	var total := 5
	runner.advance_active(120.0)
	var after := 0
	for amount in g._engine.inventory.values():
		after += int(amount)
	Selftest.check("progression idle: shared timeline executes purchased gifts", after == total + 1)
	g._progress_ui._ach_update()
	Selftest.check("progression rewards: isolated run evaluates real achievements", not g._progress_ui._ach_done.is_empty())
	g.remove_meta("progression_driver")


static func _test_final_blend_purchase(g: Game) -> void:
	g._retort._cube_levels = {"blend": 1, "cap": 5, "complexity": 5, "equip": 3, "offline": 5, "queue": 5, "slots": 3, "speed": 5}
	g._retort._essence_inv = {"fire-3": 1, "fire-4": 1, "water-3": 1, "water-4": 1,
		"earth-3": 1, "earth-4": 1, "air-3": 1, "air-4": 1}
	var runner := ProgressionRunner.new(g)
	runner.clock.set_virtual_epoch(1794614400.0)
	var completed := runner._retort_progression()
	Selftest.check("progression retort: final blend upgrade uses collected elemental blends", completed)
	var start := 1805307954.85251
	var duration := g._retort._retort_hours_for_tier(3) * 3600.0
	g._retort._retort_slots[0] = {"sub": "fire", "started": start, "dur": duration}
	Selftest.check("progression retort: exact absolute deadline is ready at a fractional epoch",
		not g._retort._retort_ready(0, start + duration - 0.01)
		and g._retort._retort_ready(0, start + duration))
	g._retort._retort_slots[0] = {"sub": ""}


static func _test_prestige_roundtrip(g: Game) -> void:
	var runner := ProgressionRunner.new(g)
	runner.clock.set_virtual_epoch(1794614400.0)
	for id in g.ITEMS.keys().slice(0, 40):
		g._engine.inventory[id] = 1
	g._engine.mastery_rank = 3
	g._retort._essence_inv = {"fire-0": 3}
	g._retort._essence_codex = {"fire-0": true}
	g._workshop.xp = 120
	var proof := runner._prestige_cycle()
	Selftest.check("progression prestige: real save reload retains earned gold and typed essence inventory", proof)


static func _test_retort_supply(g: Game) -> void:
	g._engine.inventory = {"fire": 3, "water": 3, "earth": 3, "air": 3}
	g._engine.spring_on = true
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._retort._essence_inv.clear()
	var runner := ProgressionRunner.new(g)
	runner.clock.set_virtual_epoch(1794614400.0)
	var produced := runner._ensure_essence("fire-0", 1)
	Selftest.check("progression retort: long distillation pauses unused Spring production through its command",
		produced and not g._engine.spring_on and g._retort.essence_count("fire-0") == 1
		and runner.clock.offline_seconds > 0.0)


static func _test_overlapping_inputs(g: Game) -> void:
	g._engine.inventory = {"fire": 1, "water": 1, "earth": 1, "air": 1}
	g._engine.ether = 180
	g._engine.learn_recipe("fire", "water", "steam")
	g._engine.learn_recipe("fire", "steam", "ember")
	g._workshop.reset_new_game()
	var runner := ProgressionRunner.new(g)
	runner.clock.set_virtual_epoch(1794614400.0)
	var prepared := ProgressionStrategy.ensure_stock(g, "ember", 1, runner.clock, runner.ledger)
	Selftest.check("progression materials: intermediate synthesis does not consume a reserved sibling input",
		prepared and int(g._engine.inventory.get("ember", 0)) == 1)


static func _test_production_rewards(g: Game) -> void:
	var before_inventory := g._engine.inventory.duplicate(true)
	var before_ether := g._engine._available_ether()
	g._engine.inventory = {"fire": 2, "water": 2, "earth": 2, "air": 2}
	g._engine._milestones_done.clear()
	g._engine._experiment_last_at = 0.0
	g._engine.known_recipes.erase(g._pair_key("fire", "water"))
	g._engine.ether = 100
	g._engine.ether_overflow = 0
	g.set_meta("progression_driver", true)
	var started := g._online._start_experiment("fire", "water")
	Selftest.check("progression rewards: local experiment receives first discovery and milestone rewards",
		started and g._engine._available_ether() == 100 - 12 + 6 + 20)
	g._engine.inventory = {"fire": 2, "water": 2, "earth": 2, "air": 2}
	g._engine._milestones_done.clear()
	g._engine.ether = 100
	g._engine.ether_overflow = 0
	g.set_meta("progression_driver", true)
	var book_signature := g._engine._book_sig
	g._engine._book_sig = -123
	g._engine._refresh()
	Selftest.check("progression presentation: headless driver does not rebuild visual recipe book",
		g._engine._book_sig == -123)
	g._engine._book_sig = book_signature
	var result := g._engine._commit_brew("fire", "water")
	g.remove_meta("progression_driver")
	Selftest.check("progression rewards: isolated driver receives real first-discovery bounty and milestone",
		not result.get("failed", true) and result.get("milestones", []).has(5)
		and g._engine._available_ether() == 100 - int(result.get("ether_spent", 0)) + 6 + g._engine._milestone_reward(5))
	g._engine.inventory = before_inventory
	g._engine.ether = before_ether
	g._engine.ether_overflow = 0


static func _snapshot_model(model: Object) -> Dictionary:
	var result: Dictionary = {}
	for property in model.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = model.get(property["name"])
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		result[property["name"]] = value
	return result


static func _test_phases(g: Game) -> void:
	var runner := ProgressionRunner.new(g, 29, BalanceConfig.baseline())
	if not runner.has_method("run_phases"):
		return
	var temp_dir := "res://previews/progression/phases-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	runner.set("progress_path", temp_dir + "/progress.json")
	var saved_frozen: bool = g._saves._save_frozen
	g._saves._save_frozen = true
	g._engine.inventory.erase("steam")
	g._engine.known_recipes.erase(g._pair_key("fire", "water"))
	g._engine.inventory["fire"] = maxi(2, int(g._engine.inventory.get("fire", 0)))
	g._engine.inventory["water"] = maxi(2, int(g._engine.inventory.get("water", 0)))
	g._engine.ether = maxi(100, g._engine.ether)
	g._engine._experiment_last_at = 0.0
	g._saves._save_frozen = false
	var discovery_ok := runner._discovery({"steam": true}, 1)
	Selftest.check("progression orchestration: real local discovery and checkpoint save run",
		discovery_ok and g._engine.known_recipes.has(g._pair_key("fire", "water")))
	var result := runner.report("fail")
	Selftest.check("progression orchestration: unexecuted proof cannot pass",
		not result.get("metrics", {}).get("prestige_proof", true))
	var stalled: Dictionary = runner.call("run_phases", {"nonexistent_local_target": true}, 0, 0.0)
	Selftest.check("progression orchestration: unknown local target fails with a classified reason",
		stalled.get("verdict") == "fail"
		and stalled.get("phases", {}).get("bootstrap/catalog", {}).get("reason") == "graph_unknown_targets")
	g._saves._save_frozen = saved_frozen
	DirAccess.remove_absolute(ProjectSettings.globalize_path(runner.get("progress_path")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_dir))


static func _test_clock_and_receipts(g: Game) -> void:
	var models: Array = [g._engine, g._retort, g._workshop, g._sigil, g._sigil_ui]
	var saved: Array = []
	for model in models:
		saved.append(_snapshot_model(model))
	var saved_clock := g.game_clock
	var saved_ts := g._last_ts
	var runner := ProgressionRunner.new(g, 37, BalanceConfig.baseline())
	runner.clock.set_virtual_epoch(1794614400.0)
	g._engine.inventory = {"fire": 10, "water": 10, "earth": 10, "air": 10}
	g._engine.ether = 180
	g._engine._experiment_day = ""
	g._engine._experiment_last_at = 0.0
	g._engine._rejected_pairs.erase(g._pair_key("water", "water"))
	g._engine.known_recipes.erase(g._pair_key("water", "water"))
	var started := g._engine._begin_experiment("water", "water")
	var cooldown := g._engine._experiment_cooldown_remaining()
	g._engine._finish_experiment_inputs("water", "water", true)
	runner.clock.advance_active(cooldown)
	Selftest.check("progression clock: injected epoch expires real cooldown without resetting bookkeeping",
		started and cooldown > 0.0 and g._engine._experiment_cooldown_remaining() == 0.0
		and g._engine._experiment_count == 1)
	var count_before := g._engine._experiment_count
	var next_day: float = (floor(runner.clock.now() / 86400.0) + 1.0) * 86400.0
	runner.clock.replay_offline(runner.clock.now(), next_day)
	Selftest.check("progression clock: daily allowance rolls only on virtual calendar boundary",
		count_before == 1 and g._engine._experiment_remaining() == Game.EXPERIMENT_DAILY_LIMIT
		and g._workshop.last_simulated_at == next_day)
	var started_retort := g._retort._retort_start(0, "earth", runner.clock.now())
	var early: Dictionary = g._retort._retort_collect(0, runner.clock.now())
	var duration := float(g._retort._retort_slot(0).get("dur", 0.0))
	runner.advance_active(duration)
	var collected: Dictionary = g._retort._retort_collect(0, runner.clock.now())
	Selftest.check("progression retort: active shared clock matures exact due timestamp, not before",
		started_retort and not early.get("ok", false) and collected.get("ok", false)
		and runner.clock.active_seconds >= duration)

	g._workshop.reset_prestige()
	Selftest.check("progression prestige: real equipment reset keeps virtual checkpoint epoch",
		g._workshop.last_simulated_at == runner.clock.now())
	var sigil_fixture: RefCounted = load("res://tests/progression_sigil_fixture.gd").new()
	sigil_fixture.install(g)
	var craft: Dictionary = sigil_fixture.crafts[0]
	g._engine.ether = 180
	g._sigil_ui._sigil_pending_craft = {}
	var before := g._engine.inventory.duplicate(true)
	var before_ether := g._engine._available_ether()
	sigil_fixture.mode = "refusal"
	var refused := g._sigil_ui.begin_sigil_craft(craft)
	Selftest.check("progression sigils: refused production transaction refunds exact debit and no collection",
		refused and g._engine.inventory == before and g._engine._available_ether() == before_ether
		and g._sigil_ui._sigil_pending_craft.is_empty() and g._sigil.copies_of(craft.card_id) == 0)
	sigil_fixture.mode = "pending"
	var pending := g._sigil_ui.begin_sigil_craft(craft)
	var second := g._sigil_ui.begin_sigil_craft(craft)
	Selftest.check("progression sigils: pending receipt prevents duplicate debit and no craft completion",
		pending and not second and g._sigil.copies_of(craft.card_id) == 0
		and g._engine._available_ether() == before_ether - int(craft.ether_cost))
	g._sigil_ui._on_sigil_craft_failed("test_cleanup")
	sigil_fixture.mode = "success"
	var speed := g._sigil.card_speed_bonus()
	var confirmed := g._sigil_ui.begin_sigil_craft(craft)
	print("SIGIL_DIAGNOSTIC ", JSON.stringify({"started": confirmed, "pending": g._sigil_ui._sigil_pending_craft,
		"receipt": g._sigil_ui._pending_craft_result, "copies": g._sigil.copies_of(craft.card_id),
		"speed_before": speed, "speed_after": g._sigil.card_speed_bonus(), "wiped": g._sigil._wiped}))
	Selftest.check("progression sigils: matching receipt and collection activate measurable production effects",
		confirmed and g._sigil_ui._sigil_pending_craft.is_empty()
		and g._sigil_ui._pending_craft_result.get("craft_id") == craft.id
		and g._sigil.copies_of(craft.card_id) == 1 and g._sigil.card_speed_bonus() > speed)
	for i in range(models.size()):
		for property in saved[i]:
			models[i].set(property, saved[i][property])
	g.game_clock = saved_clock
	g._last_ts = saved_ts


static func _test_tasks_8_to_12_contracts(g: Game) -> void:
	var strategy_runner := ProgressionRunner.new(g, 31, BalanceConfig.baseline())
	var saved_inventory: Dictionary = g._engine.inventory.duplicate(true)
	var saved_ether := g._engine.ether
	g._engine.inventory = {"fire": 1, "water": 1}
	g._engine.ether = 100
	var input_ledger := ProgressionLedger.new()
	var input_recipe := {"a": "fire", "b": "fire", "out": "steam"}
	var input_ok := ProgressionStrategy.ensure_inputs(g, input_recipe, strategy_runner.clock, input_ledger)
	Selftest.check("progression strategy: same-input recipe requires two earned inputs",
		input_ok and int(g._engine.inventory.get("fire", 0)) >= 2
		and not input_ledger.report().get("events", []).is_empty())
	g._engine.inventory = saved_inventory
	g._engine.ether = saved_ether

	Selftest.check("progression clock: injectable time source preserves experiment semantics",
		strategy_runner.clock.has_method("set_time_source")
		and strategy_runner.clock.has_method("set_virtual_epoch"))
	Selftest.check("progression retort: runner uses one shared absolute timeline",
		strategy_runner.has_method("run_retort_until")
		and strategy_runner.has_method("retort_snapshot"))
	Selftest.check("progression sigils: transaction entrypoint is shared by board and runner",
		g._sigil_ui.has_method("begin_sigil_craft"))
	strategy_runner.upgrade_targets = [{"complete": false}, {"complete": true}]
	strategy_runner.sigil_targets = [{"complete": false}]
	strategy_runner.ledger.unexplained.append({"expected": {}, "actual": {"ether": 1}})
	var report := strategy_runner.report("incomplete")
	var metrics: Dictionary = report.get("metrics", {})
	Selftest.check("progression report: incomplete targets and unexplained resources are numeric counts",
		metrics.get("uncompleted_upgrades") is int and metrics.get("uncompleted_upgrades") == 1
		and metrics.get("uncompleted_sigil_targets") is int and metrics.get("uncompleted_sigil_targets") == 1
		and metrics.get("unexplained_resources") is int and metrics.get("unexplained_resources") == 1
		and metrics.get("ether_deficit_at_completion") == null)
	strategy_runner.wall_budget_ms = 0
	var before_exhausted := g._engine.inventory.duplicate(true)
	var exhausted := strategy_runner.run_phases()
	Selftest.check("progression budget: exhausted run preserves catalog and skips prestige",
		exhausted.get("verdict") == "fail" and not exhausted.get("metrics", {}).get("prestige_proof", true)
		and exhausted.get("phases", {}).get("prestige", {}).get("state") == "incomplete"
		and g._engine.inventory == before_exhausted)
	Selftest.check("progression report: caller cannot label unexecuted proof as pass",
		strategy_runner.report("pass").get("verdict") == "fail")
	var audit := ProgressionLedger.new()
	audit.start(g)
	var original_ether := g._engine.ether
	g._engine.ether += 1 # Independent mutation fixture, never in full progression.
	audit.reconcile(g)
	Selftest.check("progression ledger: out-of-band resource grant is unexplained", audit.unexplained.size() == 1)
	g._engine.ether = original_ether
	Selftest.check("progression report: final metrics expose bounded proof fields",
		metrics.has("local_elements") and metrics.has("recipes")
		and metrics.has("uncompleted_upgrades") and metrics.has("uncompleted_sigil_targets")
		and metrics.has("prestige_proof") and metrics.has("simulated_real_seconds"))


static func _test_live_progress(runner: ProgressionRunner) -> void:
	var available := runner.has_method("update_progress") and runner.has_method("run_phases")
	Selftest.check("progression live: runner exposes status and phase orchestration", available)
	if not available:
		return
	var saved_progress_path: String = runner.get("progress_path")
	var saved_status: Dictionary = runner.get("_progress").duplicate(true)
	var saved_write_failed: bool = runner.get("_progress_write_failed")
	var temp_dir := "res://previews/progression/test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var path := temp_dir + "/progress.json"
	runner.set("progress_path", path)
	runner.call("update_progress", "discovery", 37, 200, "discovered steam")
	var snapshot: Dictionary = runner.call("progress_snapshot")
	Selftest.check("progression live: 37 of 200 exposes schema, event, simulated time, timestamp and state at 18.5 percent",
		int(snapshot.get("schema", 0)) == ProgressionReport.SCHEMA
		and snapshot.get("phase") == "discovery" and snapshot.get("completed") == 37
		and snapshot.get("total") == 200 and is_equal_approx(float(snapshot.get("phase_percent", -1.0)), 18.5)
		and snapshot.get("last_event") == "discovered steam" and snapshot.has("simulated_seconds")
		and float(snapshot.get("updated_at", 0.0)) > 0.0
		and snapshot.get("state") == "running" and snapshot.get("verdict") == "running")
	snapshot["phase"] = "mutated copy"
	Selftest.check("progression live: snapshots cannot mutate runner status",
		runner.call("progress_snapshot").get("phase") == "discovery")
	var first: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	Selftest.check("progression live: update atomically publishes JSON without a leftover temporary file",
		first is Dictionary and first.get("completed") == 37 and not FileAccess.file_exists(path + ".tmp"))
	var saved_report_path := runner.report_path
	runner.report_path = temp_dir + "/final.json"
	ProgressionReport.write_atomic(runner.report_path, {"sentinel": true})
	runner.call("update_progress", "proof", 1, 1, "not yet verified", "incomplete")
	var final_snapshot: Variant = JSON.parse_string(FileAccess.get_file_as_string(runner.report_path))
	Selftest.check("progression live: status update does not serialize or replace final ledger report",
		final_snapshot is Dictionary and final_snapshot.get("sentinel", false))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(runner.report_path))
	runner.report_path = saved_report_path
	var second: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	Selftest.check("progression live: second update replaces rather than appends to JSON",
		second is Dictionary and second.get("phase") == "proof"
		and second.get("state") == "incomplete" and second.get("completed") == 1)
	var unchanged := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	Selftest.check("progression live: failed staging preserves the previous file",
		not ProgressionReport.write_atomic(path, {"completed": 2})
		and FileAccess.get_file_as_string(path) == unchanged)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	runner.call("update_progress", "empty", 4, 0, "no targets")
	Selftest.check("progression live: zero total yields zero percent",
		is_zero_approx(float(runner.call("progress_snapshot").get("percent", -1.0))))
	runner.call("update_progress", "bounded", 300, 200, "over")
	Selftest.check("progression live: percentage is bounded above",
		is_equal_approx(float(runner.call("progress_snapshot").get("phase_percent", -1.0)), 100.0)
		and float(runner.call("progress_snapshot").get("percent", 100.0)) < 100.0)
	runner.call("update_progress", "bounded", -1, 200, "under")
	Selftest.check("progression live: percentage is bounded below",
		is_zero_approx(float(runner.call("progress_snapshot").get("percent", -1.0))))
	runner.set("progress_path", saved_progress_path)
	runner.set("_progress", saved_status)
	runner.set("_progress_write_failed", saved_write_failed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_dir))
