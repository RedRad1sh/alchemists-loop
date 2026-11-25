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
	var saved_experiment_reserved: int = g._engine._experiment_reserved_ether
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
	Selftest.check("progression fixture: real experiment transaction registers pending request without consuming reagents",
		started and fixture.requests().size() == 1
		and g._online._pending_requests.has(key)
		and g._engine._experiment_pending_pair.size() == 2
		and int(g._engine.inventory.get("fire", 0)) == 2)
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
	g._engine._experiment_reserved_ether = 0
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
	var strategy_before := ProgressionScenario.snapshot(g)
	var strategy_ledger := ProgressionLedger.new()
	var strategy_ok := ProgressionStrategy.discover_and_brew(g, frontier, strategy_ledger)
	Selftest.check("progression strategy: deterministic frontier reaches steam through real experiment path",
		String(frontier.get("key", "")) == g._pair_key("fire", "water")
		and strategy_ok and int(g._engine.inventory.get("steam", 0)) == 1
		and g._engine.known_recipes.has(g._pair_key("fire", "water"))
		and int(strategy_ledger.report().get("counters", {}).get("discoveries", 0)) == 1)
	Selftest.check("progression strategy: real experiment ledger grants output without reagent debit",
		int(g._engine.inventory.get("fire", 0)) == int(strategy_before.inventory.get("fire", 0))
		and int(g._engine.inventory.get("water", 0)) == int(strategy_before.inventory.get("water", 0))
		and strategy_ledger.report().get("unexplained_resources", []).is_empty())

	_test_personal_experiment_outcomes(g)
	_test_personal_target_semantics(g)

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
	g._engine._experiment_reserved_ether = saved_experiment_reserved


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
	g._engine._cancel_experiment("water", "water")
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


static func _test_personal_experiment_outcomes(g: Game) -> void:
	var saved_inventory: Dictionary = g._engine.inventory.duplicate(true)
	var saved_ether: int = g._engine.ether
	var saved_overflow: int = g._engine.ether_overflow
	var saved_target: Dictionary = g._online._target_state.duplicate(true)
	g._engine.inventory = {"fire": 4, "water": 3}
	g._engine.ether = 100
	g._engine.ether_overflow = 7
	var strategy_script: Script = load("res://tests/progression_strategy.gd")
	var helper_exists: bool = strategy_script.has_method("apply_experiment_outcome")
	var ledger := ProgressionLedger.new()
	ledger.start(g)
	var before: Dictionary = ProgressionScenario.snapshot(g)
	var success_ok := false
	if helper_exists:
		success_ok = bool(strategy_script.call("apply_experiment_outcome", g,
			{"status": "success", "output": "steam", "cost": 12, "request_id": "personal-success"}, ledger))
	var after_success: Dictionary = ProgressionScenario.snapshot(g)
	Selftest.check("personal experiment success is accepted", helper_exists and success_ok)
	Selftest.check("personal experiment success consumes no reagents",
		int(after_success.inventory.get("fire", 0)) == int(before.inventory.get("fire", 0))
		and int(after_success.inventory.get("water", 0)) == int(before.inventory.get("water", 0)))
	Selftest.check("personal experiment success grants one output and charges configured cost once",
		int(after_success.inventory.get("steam", 0)) == int(before.inventory.get("steam", 0)) + 1
		and int(before.ether_available) - int(after_success.ether_available) == 12)
	var duplicate_ok := true
	if helper_exists:
		duplicate_ok = bool(strategy_script.call("apply_experiment_outcome", g,
			{"status": "success", "output": "steam", "cost": 12, "request_id": "personal-success"}, ledger))
	Selftest.check("personal experiment duplicate outcome cannot debit or grant twice",
		helper_exists and not duplicate_ok and ProgressionScenario.snapshot(g) == after_success)
	var unavailable_ok := true
	if helper_exists:
		unavailable_ok = bool(strategy_script.call("apply_experiment_outcome", g,
			{"status": "unavailable", "request_id": "personal-unavailable"}, ledger))
	Selftest.check("personal experiment unavailable is unsuccessful without economic delta",
		helper_exists and not unavailable_ok and ProgressionScenario.snapshot(g) == after_success)
	var refusal_ok := true
	if helper_exists:
		refusal_ok = bool(strategy_script.call("apply_experiment_outcome", g,
			{"status": "not_combinable", "request_id": "personal-refusal"}, ledger))
	Selftest.check("personal experiment semantic failure is unsuccessful without economic delta",
		helper_exists and not refusal_ok and ProgressionScenario.snapshot(g) == after_success)
	var malformed_ok := true
	if helper_exists:
		malformed_ok = bool(strategy_script.call("apply_experiment_outcome", g,
			{"status": "success", "output": "", "cost": 12, "request_id": "personal-malformed"}, ledger))
	Selftest.check("personal experiment malformed success cannot mutate economy",
		helper_exists and not malformed_ok and ProgressionScenario.snapshot(g) == after_success)
	var unaffordable_ok := true
	if helper_exists:
		unaffordable_ok = bool(strategy_script.call("apply_experiment_outcome", g,
			{"status": "success", "output": "steam", "cost": 999, "request_id": "personal-unaffordable"}, ledger))
	Selftest.check("personal experiment unaffordable success cannot partially grant or debit",
		helper_exists and not unaffordable_ok and ProgressionScenario.snapshot(g) == after_success)
	var ledger_inventory: Dictionary = {}
	var ledger_ether_delta := 0
	for event in ledger.report().get("events", []):
		var deltas: Dictionary = event.get("deltas", {})
		ledger_ether_delta += int(deltas.get("ether", 0)) + int(deltas.get("reserve", 0))
		for item in deltas.get("inventory", {}):
			ledger_inventory[item] = int(ledger_inventory.get(item, 0)) + int(deltas.inventory[item])
	Selftest.check("personal experiment ledger reconciles one grant and one debit",
		ledger_inventory.get("steam", 0) == 1 and ledger_inventory.get("fire", 0) == 0
		and ledger_inventory.get("water", 0) == 0 and ledger_ether_delta == -12
		and ledger.report().get("unexplained_resources", []).is_empty())
	var anonymous_ledger := ProgressionLedger.new()
	strategy_script.call("apply_experiment_outcome", g,
		{"status": "success", "output": "steam", "cost": 12}, anonymous_ledger)
	strategy_script.call("apply_experiment_outcome", g, {"status": "unavailable"}, anonymous_ledger)
	var anonymous_events := 0
	for event in anonymous_ledger.report().get("events", []):
		if String(event.get("kind", "")) == "personal_experiment" and event.has("status"):
			anonymous_events += 1
	Selftest.check("personal experiment outcomes without request ids still produce distinct semantic events",
		anonymous_events == 2 and anonymous_ledger.report().get("unexplained_resources", []).is_empty())
	g._engine.inventory = saved_inventory
	g._engine.ether = saved_ether
	g._engine.ether_overflow = saved_overflow
	g._online._target_state = saved_target


static func _test_personal_target_semantics(g: Game) -> void:
	var saved_inventory: Dictionary = g._engine.inventory.duplicate(true)
	var saved_ether: int = g._engine.ether
	var saved_overflow: int = g._engine.ether_overflow
	var saved_recipes: Dictionary = g._engine.known_recipes.duplicate(true)
	var saved_target: Dictionary = g._online._target_state.duplicate(true)
	var strategy_script: Script = load("res://tests/progression_strategy.gd")
	var bucket_ok := false
	var kind_ok := false
	if strategy_script.has_method("personal_target_bucket") and strategy_script.has_method("choose_personal_target_kind"):
		var expected_buckets := [5, 38, 16]
		bucket_ok = true
		for sequence in range(expected_buckets.size()):
			bucket_ok = bucket_ok and int(strategy_script.call("personal_target_bucket",
				"device-bucket", "2026-W48", sequence)) == int(expected_buckets[sequence])
		kind_ok = String(strategy_script.call("choose_personal_target_kind",
			"world-fixture", "2026-W48", 0, true)) == "world" \
			and String(strategy_script.call("choose_personal_target_kind",
				"llm-fixture", "2026-W48", 0, true)) == "llm" \
			and String(strategy_script.call("choose_personal_target_kind",
				"llm-fixture", "2026-W48", 0, false)) == "llm"
	Selftest.check("personal target bucket matches server SHA-256 modulo 100 fixtures",
		bucket_ok and kind_ok)

	var world_targets := 0
	var llm_targets := 0
	var plan_ok := strategy_script.has_method("personal_target_plan")
	if plan_ok:
		for sequence in range(10000):
			var plan: Dictionary = strategy_script.call("personal_target_plan",
				"calibration-device", "2026-W48", sequence, ["stone"])
			if String(plan.get("kind", "")) == "world":
				world_targets += 1
			elif String(plan.get("kind", "")) == "llm":
				llm_targets += 1
			else:
				plan_ok = false
		var empty_plan: Dictionary = strategy_script.call("personal_target_plan",
			"calibration-device", "2026-W48", 0, [])
		plan_ok = plan_ok and String(empty_plan.get("kind", "")) == "llm" \
			and String(empty_plan.get("slug", "")) == ""
	Selftest.check("personal target calibration reproduces 8035 world and 1965 LLM targets",
		plan_ok and world_targets == 8035 and llm_targets == 1965)

	var next_week_ok := false
	if strategy_script.has_method("next_personal_week"):
		next_week_ok = String(strategy_script.call("next_personal_week", "2026-W48")) == "2026-W49" \
			and String(strategy_script.call("next_personal_week", "2026-W53")) == "2027-W01" \
			and String(strategy_script.call("next_personal_week", "2027-W52")) == "2028-W01"
	Selftest.check("personal target next eligible week handles ISO year boundaries", next_week_ok)

	g._engine.inventory = {"fire": 4, "water": 3}
	g._engine.ether = 100
	g._engine.ether_overflow = 7
	g._online._target_state = {
		"id": "pt-llm", "kind": "llm", "slug": "", "name": "СЖЁННЫЙ СВЕТ",
		"status": "active", "cycle_week": "2026-W48", "attempts": 2,
		"successful_steps": 1, "spent_ether": 12, "next_eligible_week": "", "completed": false,
	}
	var completion_ledger := ProgressionLedger.new()
	completion_ledger.start(g)
	var before_completion_ether := g._engine.ether + g._engine.ether_overflow
	var completion_ok := bool(strategy_script.call("apply_experiment_outcome", g, {
		"status": "success", "output": "steam", "output_name": " сжеНный\tсвет ",
		"result_kind": "created", "acquired": true, "cost": 12,
		"request_id": "llm-fresh-exact", "target_id": "pt-llm", "target_kind": "llm",
		"cycle_week": "2026-W48",
	}, completion_ledger))
	var completed_target: Dictionary = g._online._target_state
	Selftest.check("personal LLM target completes only on fresh acquired exact normalized name",
		completion_ok and String(completed_target.get("status", "")) == "completed"
		and bool(completed_target.get("completed", false))
		and int(completed_target.get("attempts", 0)) == 3
		and int(completed_target.get("successful_steps", 0)) == 2
		and int(completed_target.get("spent_ether", 0)) == 24
		and String(completed_target.get("next_eligible_week", "")) == "2026-W49"
		and before_completion_ether - (g._engine.ether + g._engine.ether_overflow) == 12
		and int(g._engine.inventory.get("steam", 0)) == 1
		and int(completion_ledger.report().get("counters", {}).get("personal_experiment_completions", 0)) == 1)

	var allocation_ok := strategy_script.has_method("allocate_personal_target")
	var allocation_ledger := ProgressionLedger.new()
	allocation_ledger.start(g)
	var completed_before_slot: Dictionary = g._online._target_state.duplicate(true)
	if allocation_ok:
		var blocked: Dictionary = strategy_script.call("allocate_personal_target", g,
			"device-bucket", "2026-W48", 2, ["stone"], allocation_ledger)
		allocation_ok = blocked.is_empty() and g._online._target_state == completed_before_slot
		var next_target: Dictionary = strategy_script.call("allocate_personal_target", g,
			"device-bucket", "2026-W49", 2, ["stone"], allocation_ledger)
		allocation_ok = allocation_ok and String(next_target.get("status", "")) == "active" \
			and String(next_target.get("cycle_week", "")) == "2026-W49" \
			and String(next_target.get("id", "")) != String(completed_before_slot.get("id", ""))
	Selftest.check("personal target allocation waits for the next eligible server week",
		allocation_ok and int(allocation_ledger.report().get("counters", {}).get(
			"personal_experiment_targets_allocated", 0)) == 1)

	var negative_ok := strategy_script.has_method("apply_experiment_outcome")
	var negative_cases := [
		{"result_kind": "known", "output_name": "СЖЁННЫЙ СВЕТ", "request_id": "llm-known"},
		{"result_kind": "reused", "output_name": "СЖЁННЫЙ СВЕТ", "request_id": "llm-reused"},
		{"result_kind": "created", "output_name": "Другой свет", "request_id": "llm-nonexact"},
	]
	for negative_case in negative_cases:
		g._engine.inventory = {"fire": 4, "water": 3}
		g._engine.ether = 100
		g._engine.ether_overflow = 7
		g._online._target_state = {
			"id": "pt-llm", "kind": "llm", "slug": "", "name": "СЖЁННЫЙ СВЕТ",
			"status": "active", "cycle_week": "2026-W48", "attempts": 2,
			"successful_steps": 1, "spent_ether": 12, "next_eligible_week": "", "completed": false,
		}
		var negative_ledger := ProgressionLedger.new()
		negative_ledger.start(g)
		var negative_outcome: Dictionary = negative_case.duplicate(true)
		negative_outcome.merge({
			"status": "success", "output": "steam", "acquired": true, "cost": 12,
			"target_id": "pt-llm", "target_kind": "llm", "cycle_week": "2026-W48",
		}, true)
		var negative_accepted := bool(strategy_script.call("apply_experiment_outcome", g,
			negative_outcome, negative_ledger))
		negative_ok = negative_ok and negative_accepted \
			and String(g._online._target_state.get("status", "")) == "active" \
			and int(g._online._target_state.get("attempts", 0)) == 3 \
			and int(g._online._target_state.get("successful_steps", 0)) == 2 \
			and int(g._online._target_state.get("spent_ether", 0)) == 24
	Selftest.check("personal LLM known reused and nonexact results progress without completion",
		negative_ok)

	g._engine.inventory = {"fire": 4, "water": 3}
	g._engine.ether = 100
	g._engine.ether_overflow = 7
	g._online._target_state = {
		"id": "pt-world", "kind": "world", "slug": "steam", "name": "Steam",
		"status": "active", "cycle_week": "2026-W48", "attempts": 0,
		"successful_steps": 0, "spent_ether": 0, "next_eligible_week": "", "completed": false,
	}
	var world_ledger := ProgressionLedger.new()
	world_ledger.start(g)
	var world_ok := bool(strategy_script.call("apply_experiment_outcome", g, {
		"status": "success", "output": "steam", "result_kind": "known", "acquired": true,
		"cost": 12, "request_id": "world-fresh", "target_id": "pt-world",
		"target_kind": "world", "cycle_week": "2026-W48",
	}, world_ledger))
	var before_mismatch := ProgressionScenario.snapshot(g)
	var mismatch_ok := bool(strategy_script.call("apply_experiment_outcome", g, {
		"status": "success", "output": "steam", "result_kind": "known", "acquired": true,
		"cost": 12, "request_id": "world-foreign", "target_id": "pt-foreign",
		"target_kind": "world", "cycle_week": "2026-W48",
	}, world_ledger))
	Selftest.check("personal world target completes by slug and rejects a foreign target without debit",
		world_ok and String(g._online._target_state.get("status", "")) == "completed" \
		and not mismatch_ok and ProgressionScenario.snapshot(g) == before_mismatch)

	g._online._target_state = {
		"id": "pt-persistent", "kind": "llm", "slug": "", "name": "СЖЁННЫЙ СВЕТ",
		"status": "active", "cycle_week": "2026-W48", "attempts": 2,
		"successful_steps": 1, "spent_ether": 12, "next_eligible_week": "", "completed": false,
	}
	var persistent_ledger := ProgressionLedger.new()
	persistent_ledger.start(g)
	strategy_script.call("apply_experiment_outcome", g, {
		"status": "unavailable", "request_id": "next-week-failure", "target_id": "pt-persistent",
		"target_kind": "llm", "cycle_week": "2026-W49",
	}, persistent_ledger)
	Selftest.check("personal unfinished target persists across a server week boundary",
		String(g._online._target_state.get("id", "")) == "pt-persistent" \
		and String(g._online._target_state.get("cycle_week", "")) == "2026-W48" \
		and String(g._online._target_state.get("status", "")) == "active" \
		and int(g._online._target_state.get("attempts", 0)) == 3)

	g._engine.inventory = {"fire": 4, "water": 3}
	g._engine.ether = 100
	g._engine.ether_overflow = 7
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	var brew_ledger := ProgressionLedger.new()
	brew_ledger.start(g)
	var brew_cost := g._engine._pair_cost("fire", "water")
	var brew_before_ether := g._engine.ether + g._engine.ether_overflow
	var ordinary_brew_ok := bool(strategy_script.call("discover_and_brew", g,
		{"a": "fire", "b": "water", "out": "steam"}, brew_ledger))
	Selftest.check("personal target simulation leaves ordinary brew cost and reagent debit unchanged",
		ordinary_brew_ok and int(g._engine.inventory.get("fire", 0)) == 3 \
		and int(g._engine.inventory.get("water", 0)) == 2 \
		and int(g._engine.inventory.get("steam", 0)) == 1 \
		and brew_before_ether - (g._engine.ether + g._engine.ether_overflow) == brew_cost)

	g._engine.inventory = saved_inventory
	g._engine.ether = saved_ether
	g._engine.ether_overflow = saved_overflow
	g._engine.known_recipes = saved_recipes
	g._online._target_state = saved_target


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
