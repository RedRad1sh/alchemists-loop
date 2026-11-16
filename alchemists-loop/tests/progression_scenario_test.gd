extends SceneTree

const Scenario = preload("res://tests/progression_scenario.gd")

var _failures := 0
var _checks := 0
var _executor_calls := 0


class FakeEngine extends RefCounted:
	var inventory: Dictionary = {"fire": 2, "water": 1}
	var known_recipes: Dictionary = {"fire|water": true}
	var ether := 42
	var ether_overflow := 7
	var upgrades: Dictionary = {"brew_speed": 1}
	var spring_levels: Dictionary = {"speed": 2, "volume": 1}
	var mastery_rank := 3
	var sage_gold := 4

	func _max_ether() -> int:
		return 180


class FakeWorkshop extends RefCounted:
	var unlocked := true
	var rank := 2
	var autonomy_level := 1
	var xp := 275
	var lines: Array = [{"id": "line_1", "queue": [{"target": "steam", "produced": 2}]}, {"id": "line_2", "queue": []}]
	var last_simulated_at := 1234.0


class AvailabilityWorkshop extends FakeWorkshop:
	var g: Variant = null
	var rank_check: Dictionary = {"ok": true, "reason": ""}
	var autonomy_check: Dictionary = {"ok": true, "reason": ""}

	func rank_availability(_level: int) -> Dictionary:
		return rank_check

	func autonomy_availability() -> Dictionary:
		return autonomy_check

	func _ranks() -> Array:
		return [{}, {"name": "Мастер", "xp": 100, "materials": {"brick": 20}, "ether": 10}]

	func _autonomy() -> Array:
		return [{}, {"rank": 1, "materials": {"metal": 5}, "ether": 10}]


class FakeRetort extends RefCounted:
	var _retort_slots: Array = [{"sub": "fire", "started": 100.0, "dur": 60.0}, {"sub": ""}]
	var _essence_inv: Dictionary = {"fire-0": 3}
	var _essence_codex: Dictionary = {"fire-0": true}
	var _cube_levels: Dictionary = {"speed": 1, "cap": 2}
	var _blend: Dictionary = {"out": "blend-fire", "dur": 120.0}


class FakeSigil extends RefCounted:
	var _server_collection: Dictionary = {"card_common": {"copies": 1, "rarity": "common"}}
	var _collection: Dictionary = {
		"craft_common_a": {"card_id": "card_common", "seed": 1, "rarity": "common"},
		"craft_common_b": {"card_id": "card_common", "seed": 2, "rarity": "common"},
		"craft_local_a": {"card_id": "card_local", "seed": 3, "rarity": "rare"},
		"craft_local_b": {"card_id": "card_local", "seed": 4, "rarity": "rare"},
	}
	var _server_extras: Array = []

	func card_speed_bonus() -> float:
		return 25.0

	func card_cap_bonus() -> int:
		return 3

	func card_autonomy_bonus() -> int:
		return 1


class FakeClock extends RefCounted:
	var _now := 1000.0
	var active_seconds := 0.0
	var offline_seconds := 0.0

	func advance(kind: String, seconds: float) -> void:
		_now += seconds
		if kind == "active":
			active_seconds += seconds
		else:
			offline_seconds += seconds

	func snapshot() -> Dictionary:
		return {
			"now": _now,
			"active_seconds": active_seconds,
			"offline_seconds": offline_seconds,
			"active_player_seconds": active_seconds,
			"simulated_real_seconds": active_seconds + offline_seconds,
		}


class FakeGame extends RefCounted:
	var ITEMS: Dictionary = {"fire": {}, "water": {}, "steam": {}, "stone": {}}
	var RECIPES: Array = [{"a": "fire", "b": "water", "out": "steam"}]
	var _engine := FakeEngine.new()
	var _workshop := FakeWorkshop.new()
	var _retort := FakeRetort.new()
	var _sigil := FakeSigil.new()
	var _last_ts := 1234.0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_default_scenario_parses()
	_test_snapshot_shape_and_isolation()
	_test_sigil_craft_ids_normalize_to_card_ids()
	_test_run_executes_injected_segment_hook()
	_test_signed_deep_delta()
	_test_next_goal_extraction()
	_test_workshop_goal_reason_vocabulary()
	_test_invalid_segment_rejection()
	_test_run_report_shape()
	await _test_real_action_delay_and_contract_claim()
	await _test_real_active_session_policy()
	await _test_active_session_budget_boundary()
	await _test_real_offline_segment()
	print("PROGRESSION_SCENARIO_TEST checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("[OK] " + name)
	else:
		_failures += 1
		push_error("[FAIL] " + name)


func _test_default_scenario_parses() -> void:
	var text := FileAccess.get_file_as_string("res://tools/progression_scenarios/1h-active-5h-offline-1h-active.json")
	var raw: Variant = JSON.parse_string(text)
	var parsed: Dictionary = Scenario.parse(raw)
	var segments: Array = parsed.get("segments", [])
	_check("default scenario has schema 1", int(parsed.get("scenario", 0)) == 1)
	_check("default scenario parses three segments", segments.size() == 3)
	_check("default scenario preserves active/offline order", segments.size() == 3
		and segments[0].get("kind") == "active"
		and segments[1].get("kind") == "offline"
		and segments[2].get("kind") == "active")
	_check("default scenario uses one/five/one hour durations", segments.size() == 3
		and is_equal_approx(float(segments[0].get("seconds", -1)), 3600.0)
		and is_equal_approx(float(segments[1].get("seconds", -1)), 18000.0)
		and is_equal_approx(float(segments[2].get("seconds", -1)), 3600.0))


func _test_snapshot_shape_and_isolation() -> void:
	var game := FakeGame.new()
	var before: Dictionary = Scenario.snapshot(game)
	var expected_fields := [
		"local_discovered_ids", "local_discovered_count", "known_recipe_count",
		"ether", "ether_cap", "ether_overflow", "inventory", "upgrade_levels",
		"workshop", "retort", "sigils", "prestige", "gold", "clock"
	]
	var fields_present: bool = true
	for field in expected_fields:
		fields_present = fields_present and before.has(field)
	_check("snapshot exposes the player-facing state sections", fields_present)
	_check("snapshot counts local discoveries from positive inventory", before.local_discovered_count == 2
		and (before.local_discovered_ids as Array).has("fire")
		and (before.local_discovered_ids as Array).has("water"))
	_check("snapshot captures ether cap and overflow", before.ether == 42
		and before.ether_cap == 180 and before.ether_overflow == 7)
	_check("snapshot captures workshop and retort state", before.workshop.rank == 2
		and before.workshop.queues.size() == 2
		and before.retort.slots.size() == 2
		and before.retort.essences.get("fire-0") == 3
		and before.retort.blends.out == "blend-fire")
	_check("snapshot captures sigil copies, effects and prestige gold", before.sigils.copies.card_common == 2
		and before.sigils.effects.speed == 25.0
		and before.sigils.effects.cap == 3
		and before.prestige == 4 and before.gold == 4)

	(before.inventory as Dictionary)["fire"] = 999
	(before.workshop.queues as Array)[0]["queue"].clear()
	(before.retort.essences as Dictionary)["fire-0"] = 999
	(before.sigils.copies as Dictionary)["card_common"] = 999
	var after: Dictionary = Scenario.snapshot(game)
	_check("snapshot returns deep copies without mutating game state", after.inventory.fire == 2
		and after.workshop.queues[0].queue.size() == 1
		and after.retort.essences["fire-0"] == 3
		and after.sigils.copies["card_common"] == 2)


func _test_sigil_craft_ids_normalize_to_card_ids() -> void:
	var game := FakeGame.new()
	var result: Dictionary = Scenario.snapshot(game)
	var copies: Dictionary = result.get("sigil_copies", {})
	var craft_records: Dictionary = result.get("sigil_craft_records", {})
	_check("sigil copies use card ids and count local craft records", copies.get("card_common", 0) == 2
		and copies.get("card_local", 0) == 2
		and not copies.has("craft_common_a")
		and not copies.has("craft_local_a"))
	_check("sigil snapshot preserves craft records separately", craft_records.size() == 4
		and craft_records.get("craft_local_a", {}).get("card_id", "") == "card_local")


func _execute_test_segment(context: Dictionary) -> Array:
	_executor_calls += 1
	var segment: Dictionary = context.get("segment", {})
	var clock: FakeClock = context.get("clock") as FakeClock
	clock.advance(str(segment.get("kind", "")), float(segment.get("seconds", 0.0)))
	var game: FakeGame = context.get("game") as FakeGame
	game._engine.inventory["steam"] = int(game._engine.inventory.get("steam", 0)) + 1
	return [{"kind": segment.get("kind", ""), "seconds": segment.get("seconds", 0.0)}]


func _test_run_executes_injected_segment_hook() -> void:
	_executor_calls = 0
	var game := FakeGame.new()
	var clock := FakeClock.new()
	var scenario := {"scenario": 1, "segments": [
		{"kind": "active", "seconds": 5},
		{"kind": "offline", "seconds": 7},
	]}
	var report: Dictionary = Scenario.run(game, null, 19, scenario, clock,
		Callable(self, "_execute_test_segment"))
	var segments: Array = report.get("segments", [])
	var first: Dictionary = segments[0] if segments.size() > 0 else {}
	var second: Dictionary = segments[1] if segments.size() > 1 else {}
	_check("run invokes the injected executor once per segment", _executor_calls == 2)
	_check("run passes the live clock into snapshots", first.get("before", {}).get("clock", {}).get("now", 0.0) == 1000.0
		and first.get("after", {}).get("clock", {}).get("now", 0.0) == 1005.0)
	_check("run reports nonzero per-segment clock progression", first.get("clock_delta", {}).get("active_seconds", 0.0) == 5.0
		and second.get("clock_delta", {}).get("offline_seconds", 0.0) == 7.0)
	_check("run reports hook-owned state mutation and events", first.get("delta", {}).get("inventory", {}).get("steam", 0) == 1
		and second.get("delta", {}).get("inventory", {}).get("steam", 0) == 1
		and first.get("events", []).size() == 1
		and report.get("after", {}).get("clock", {}).get("simulated_real_seconds", 0.0) == 12.0)


func _test_signed_deep_delta() -> void:
	var before := {"ether": 50, "inventory": {"fire": 2, "water": 1}, "workshop": {"rank": 1, "queues": [{"target": "steam"}]}}
	var after := {"ether": 41, "inventory": {"fire": 1, "steam": 2}, "workshop": {"rank": 2, "queues": []}}
	var delta: Dictionary = Scenario.deep_delta(before, after)
	_check("delta keeps signed scalar changes", delta.ether == -9 and delta.workshop.rank == 1)
	_check("delta keeps signed inventory changes including added and removed ids", delta.inventory.fire == -1
		and delta.inventory.water == -1 and delta.inventory.steam == 2)
	_check("delta recursively compares nested arrays and dictionaries", delta.workshop.queues is Array
		and delta.workshop.queues.size() == 1)
	_check("delta alias returns the same deep signed contract", Scenario.delta(before, after) == delta)


func _test_next_goal_extraction() -> void:
	var game := FakeGame.new()
	var before: Dictionary = Scenario.snapshot(game)
	var profile := {"upgrades": {"items": [{"id": "brew_speed", "base": 100, "max": 2, "unlock": "steam"}]}}
	var goals: Array = Scenario.next_goals(game, profile)
	_check("next-goal extraction returns a blocked finite upgrade", goals.size() > 0
		and goals[0].get("id") == "upgrade/brew_speed"
		and not goals[0].get("available", true)
		and goals[0].get("reason") == "not_unlocked")
	_check("next-goal extraction does not mutate the game snapshot", Scenario.snapshot(game) == before)


func _test_workshop_goal_reason_vocabulary() -> void:
	var vocabulary := ["available", "ether", "ingredients", "cooldown", "not_unlocked", "mastery", "autonomy", "rank", "recipe"]
	var workshop := AvailabilityWorkshop.new()
	workshop.g = FakeGame.new()
	var price := {"ether": 10, "materials": {"brick": 20}}
	var cases := [
		{"code": "materials", "message": "Не хватает Кирпич: нужно ×20.", "kind": "workshop_rank", "expected": "ingredients"},
		{"code": "rank", "message": "Нужен ранг «Мастер».", "kind": "workshop_autonomy", "expected": "rank"},
		{"code": "xp", "message": "Нужно 300 мастерства Мастерской.", "kind": "workshop_rank", "expected": "mastery"},
		{"code": "locked", "message": "Мастерская откроется после Человека.", "kind": "workshop_rank", "expected": "not_unlocked"},
		{"code": "busy", "message": "Котёл занят: дождись завершения текущей операции.", "kind": "workshop_rank", "expected": "cooldown"},
	]
	for case in cases:
		var failure := {"ok": false, "code": String(case.code), "reason": String(case.message)}
		if String(case.kind) == "workshop_rank":
			workshop.rank_check = failure
		else:
			workshop.autonomy_check = failure
		var goal: Dictionary = Scenario._equipment_goal("workshop/test/1", String(case.kind), 1, workshop, price, 100)
		_check("workshop goal reason is vocabulary code for " + String(case.code),
			String(goal.get("reason", "")) == String(case.expected))
		var missing: Dictionary = goal.get("missing", {})
		var textual := false
		for key in missing:
			if missing[key] is String:
				textual = true
		_check("workshop goal missing carries no free text for " + String(case.code), not textual)
	var game := FakeGame.new()
	var availability := AvailabilityWorkshop.new()
	availability.g = game
	availability.rank = 0
	availability.autonomy_level = 0
	availability.rank_check = {"ok": false, "code": "materials", "reason": "Не хватает Кирпич: нужно ×20."}
	game._workshop = availability
	var goals: Array = Scenario.next_goals(game, {})
	var all_in_vocabulary := true
	for goal in goals:
		if not vocabulary.has(String(goal.get("reason", ""))):
			all_in_vocabulary = false
	_check("next_goals emits only vocabulary reasons", goals.size() > 0 and all_in_vocabulary)


func _test_invalid_segment_rejection() -> void:
	var unknown := {"scenario": 1, "segments": [{"kind": "sleep", "seconds": 10}]}
	var negative := {"scenario": 1, "segments": [{"kind": "active", "seconds": -1}]}
	var unknown_errors: Array = Scenario.validate(unknown)
	var negative_errors: Array = Scenario.validate(negative)
	_check("parser rejects unknown segment kinds", not unknown_errors.is_empty()
		and not Scenario.parse(unknown).get("valid", true))
	_check("parser rejects negative segment seconds", not negative_errors.is_empty()
		and not Scenario.parse(negative).get("valid", true))


func _test_real_active_session_policy() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game: Node = scene.instantiate()
	game.set_meta("progression_driver", true)
	game.game_clock = func(): return 1794614400.0
	game.balance = BalanceConfig.baseline()
	game.SAVE_PATH = "user://progression_scenario_test_save.json"
	game.TEMP_PATH = "user://progression_scenario_test_save.tmp"
	game.BACKUP_PATH = "user://progression_scenario_test_save.bak"
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var clock: RefCounted = load("res://tests/progression_clock.gd").new(game)
	clock.set_virtual_epoch(1794614400.0)
	var scenario := {"scenario": 1, "segments": [{"kind": "active", "seconds": 600.0,
		"policy": "session_balanced", "targets": ["clay"]}]}
	game._engine.known_recipes.erase(game._pair_key("earth", "water"))
	game._engine.known_recipe_defs.erase(game._pair_key("earth", "water"))
	var achievements_before: Dictionary = game._progress_ui._ach_done.duplicate(true)
	var before: Dictionary = Scenario.snapshot(game, clock)
	var report: Dictionary = Scenario.run(game, BalanceConfig.baseline(), 31, scenario, clock)
	var segment: Dictionary = report.get("segments", [])[0]
	var after: Dictionary = segment.get("after", {})
	var events: Array = segment.get("events", [])
	var counters: Dictionary = segment.get("counters", {})
	var ledger: Dictionary = segment.get("ledger", {})
	var delta_data: Dictionary = segment.get("delta", {})
	var inventory_delta: Dictionary = delta_data.get("inventory", {})
	var production_event: Dictionary = {}
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if ["discovery", "brew"].has(String(event.get("kind", ""))):
			production_event = event
			break
	var production_output := String(production_event.get("output", ""))
	var production_delta := int(inventory_delta.get(production_output, 0))
	var local_progression := int(after.get("local_discovered_count", 0)) > int(before.get("local_discovered_count", 0))
	var recipe_progression := int(after.get("known_recipe_count", 0)) > int(before.get("known_recipe_count", 0))
	var ledger_counters: Dictionary = ledger.get("counters", {})
	var production_ledger_event: Dictionary = {}
	var has_direct_grant := false
	for ledger_event_value in ledger.get("events", []):
		if not ledger_event_value is Dictionary:
			continue
		var ledger_event: Dictionary = ledger_event_value
		var ledger_kind := String(ledger_event.get("kind", ""))
		if ["manual_brew", "experiment"].has(ledger_kind) and production_ledger_event.is_empty():
			production_ledger_event = ledger_event
		if ["base_add", "direct_grant", "grant"].has(ledger_kind):
			has_direct_grant = true
	var production_ledger_delta: Dictionary = production_ledger_event.get("deltas", {}).get("inventory", {})
	var expected_ledger_kind := "experiment" if production_event.get("kind", "") == "discovery" else "manual_brew"
	var ledger_inventory_delta: Dictionary = {}
	var ledger_available_ether_delta := 0
	for ledger_event_value in ledger.get("events", []):
		if not ledger_event_value is Dictionary:
			continue
		var ledger_deltas: Dictionary = (ledger_event_value as Dictionary).get("deltas", {})
		ledger_available_ether_delta += int(ledger_deltas.get("ether", 0)) + int(ledger_deltas.get("reserve", 0))
		for item in ledger_deltas.get("inventory", {}):
			ledger_inventory_delta[item] = int(ledger_inventory_delta.get(item, 0)) + int(ledger_deltas.inventory[item])
	var resource_ledger_reconciled := ledger_inventory_delta == inventory_delta \
		and ledger_available_ether_delta == int(delta_data.get("ether", 0)) + int(delta_data.get("ether_overflow", 0))
	var stalls: Array = segment.get("stalls", [])
	var has_frontier_stall := false
	for stall_value in stalls:
		if stall_value is Dictionary and stall_value.get("reason", "") == "graph_no_reachable_frontier":
			has_frontier_stall = true
			break
	print("ACTIVE_REPORT " + JSON.stringify({"delta": delta_data, "events": events,
		"counters": counters, "ledger": ledger, "stalls": stalls, "policy": segment.get("policy", ""),
		"reason": segment.get("reason", "")}))
	_check("session_balanced active segment performs a real discovery", production_event.size() > 0
		and production_event.get("kind", "") == "discovery"
		and production_event.get("operation", "") == "discover_and_brew"
		and production_output == "clay")
	_check("session_balanced records positive output and player-visible progression", production_delta > 0
		and local_progression and recipe_progression)
	_check("session_balanced consumes real inputs rather than granting output directly", int(inventory_delta.get("earth", 0)) < 0
		and int(inventory_delta.get("water", 0)) < 0
		and int(production_ledger_delta.get("earth", 0)) < 0
		and int(production_ledger_delta.get("water", 0)) < 0
		and int(production_ledger_delta.get(production_output, 0)) > 0
		and not has_direct_grant
		and production_ledger_event.get("kind", "") == expected_ledger_kind
		and not production_ledger_event.is_empty()
		and int(ledger.get("operation_count", 0)) > 0)
	var allowed_delta_sections := ["clock", "clock_totals", "ether", "ether_current", "ether_cap", "ether_overflow",
		"ether_available", "ether_rate", "ether_state", "inventory", "known_recipe_count", "local", "local_discovered_count",
		"local_discovered_ids", "upgrade_levels", "workshop"]
	var only_production_backed_sections := true
	for section in delta_data:
		if not allowed_delta_sections.has(String(section)):
			only_production_backed_sections = false
	_check("session_balanced changes only production-backed player state", only_production_backed_sections
		and not delta_data.has("sigils") and not delta_data.has("prestige")
		and not delta_data.has("gold") and not delta_data.has("retort"))
	_check("session_balanced reconciles every visible resource delta with ledger transactions", resource_ledger_reconciled
		and ledger.get("unexplained_resources", []) is Array
		and (ledger.get("unexplained_resources", []) as Array).is_empty())
	var expected_levels: Dictionary = (before.get("upgrade_levels", {}) as Dictionary).duplicate(true)
	var paid_upgrades: Array = []
	var purchases_reconciled := true
	var purchase_net_delta := 0
	var purchase_cost := 0
	for transaction in ledger.get("events", []):
		var kind := String(transaction.get("kind", ""))
		if not kind.begins_with("ether_purchase:"):
			purchases_reconciled = purchases_reconciled and ["experiment", "scheduler_active", "retort_active"].has(kind)
			continue
		var id := kind.trim_prefix("ether_purchase:")
		var level := int(expected_levels.items.get(id, 0))
		var price := int(game._engine._up_cost_at(id, level))
		var charged: Dictionary = transaction.get("deltas", {})
		purchase_net_delta += int(charged.get("ether", 0)) + int(charged.get("reserve", 0))
		purchase_cost += price
		expected_levels.items[id] = level + 1
		paid_upgrades.append({"upgrade": id, "level": level + 1})
	var purchase_rewards := 0
	for achievement in game.ACHIEVEMENTS:
		var id := String(achievement.get("id", ""))
		if not achievements_before.has(id) and game._progress_ui._ach_done.has(id):
			purchase_rewards += int(achievement.get("ether", 0))
	purchases_reconciled = purchases_reconciled and purchase_net_delta == -purchase_cost + purchase_rewards
	var reported_upgrades: Array = []
	for event in events:
		if event.get("kind", "") == "upgrade":
			reported_upgrades.append({"upgrade": event.get("upgrade", ""), "level": event.get("level", 0)})
	_check("session_balanced backs every upgrade level with an exact paid transaction", purchases_reconciled
		and after.get("upgrade_levels", {}) == expected_levels and reported_upgrades == paid_upgrades
		and int(counters.get("upgrade_purchases", 0)) == paid_upgrades.size())
	var expected_workshop: Dictionary = (before.get("workshop", {}) as Dictionary).duplicate(true)
	expected_workshop["last_simulated_at"] = float(after.get("clock", {}).get("now", 0.0))
	_check("discovery session changes no Workshop state except the scheduler watermark",
		after.get("workshop", {}) == expected_workshop)
	_check("session_balanced uses ledger discovery and brew counters", int(counters.get("discoveries", 0)) == int(ledger_counters.get("discoveries", 0))
		and int(counters.get("brews", 0)) == int(ledger_counters.get("brews", 0))
		and int(counters.get("discoveries", 0)) + int(counters.get("brews", 0)) >= 1)
	var clock_delta: Dictionary = segment.get("clock_delta", {})
	_check("session_balanced advances supplied virtual clock and action counters", float(clock_delta.get("active_seconds", 0.0)) > 0.0
		and is_equal_approx(float(counters.get("active_simulated_seconds", 0.0)), float(clock_delta.get("active_seconds", 0.0)))
		and float(clock_delta.get("active_player_seconds", 0.0)) > 0.0
		and is_equal_approx(float(counters.get("player_action_seconds", 0.0)), float(clock_delta.get("active_player_seconds", 0.0))))
	_check("session_balanced ledger has no unexplained production deltas", ledger.get("unexplained_resources", []) is Array
		and (ledger.get("unexplained_resources", []) as Array).is_empty())
	_check("session_balanced reports explicit policy and actual stalls", segment.get("policy", "") == "session_balanced"
		and segment.get("reason", "") == "graph_no_reachable_frontier"
		and not stalls.is_empty() and has_frontier_stall)
	game.queue_free()
	await process_frame


func _test_active_session_budget_boundary() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game: Node = scene.instantiate()
	game.set_meta("progression_driver", true)
	game.game_clock = func(): return 1794614400.0
	game.balance = BalanceConfig.baseline()
	game.SAVE_PATH = "user://progression_scenario_budget_test_save.json"
	game.TEMP_PATH = "user://progression_scenario_budget_test_save.tmp"
	game.BACKUP_PATH = "user://progression_scenario_budget_test_save.bak"
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var clock: RefCounted = load("res://tests/progression_clock.gd").new(game)
	clock.set_virtual_epoch(1794614400.0)
	game._engine.inventory["fire"] = 0
	game._engine.inventory["water"] = 0
	var scenario := {"scenario": 1, "segments": [{"kind": "active", "seconds": 1.0,
		"policy": "session_balanced", "targets": ["steam"]}]}
	var report: Dictionary = Scenario.run(game, BalanceConfig.baseline(), 37, scenario, clock)
	var segment: Dictionary = report.get("segments", [])[0]
	var clock_delta: Dictionary = segment.get("clock_delta", {})
	var budget_stall := String(segment.get("reason", ""))
	_check("session_balanced reaches input preparation before the active budget closes",
		budget_stall.begins_with("active_budget_before_inputs:"))
	_check("session_balanced never exceeds active segment budget while preparing inputs",
		is_equal_approx(float(clock_delta.get("active_seconds", -1.0)), 1.0)
		and float(clock_delta.get("active_seconds", 0.0)) <= 1.0 + Scenario.TIME_EPSILON)
	var strategy: Script = load("res://tests/progression_strategy.gd")
	var ledger: RefCounted = load("res://tests/progression_ledger.gd").new()
	ledger.start(game)
	clock.ledger = ledger
	var recursive_start := float(clock.active_seconds)
	var before_recursive: Dictionary = Scenario.snapshot(game, clock)
	var prepared: bool = strategy.ensure_inputs(game, {"a": "steam", "b": "air", "out": "cloud"},
		clock, ledger, recursive_start + 0.5)
	_check("recursive input production respects a nonzero active deadline", not prepared
		and String(strategy.last_reason).begins_with("active_budget_before_inputs:")
		and float(clock.active_seconds) - recursive_start <= 0.5 + Scenario.TIME_EPSILON)
	_check("recursive input production cannot collect or brew after the budget closes",
		Scenario.snapshot(game, clock) == before_recursive and ledger.report().get("events", []).is_empty())
	clock.ledger = null
	game.queue_free()
	await process_frame


func _test_real_offline_segment() -> void:
	var deltas: Array = []
	for repeat in range(2):
		var game: Node = load("res://main.tscn").instantiate()
		game.set_meta("progression_driver", true)
		game.game_clock = func(): return 1794614400.0
		game.balance = BalanceConfig.baseline()
		game.SAVE_PATH = "user://scenario_offline_%d.json" % repeat
		game.TEMP_PATH = "user://scenario_offline_%d.tmp" % repeat
		game.BACKUP_PATH = "user://scenario_offline_%d.bak" % repeat
		root.add_child(game)
		await process_frame
		game.set_process(false)
		var clock: RefCounted = load("res://tests/progression_clock.gd").new(game)
		clock.set_virtual_epoch(1794614400.0)
		var report: Dictionary = Scenario.run(game, game.balance, 31,
			{"scenario": 1, "segments": [{"kind": "offline", "seconds": 18000.0}]}, clock)
		var segment: Dictionary = report.segments[0]
		_check("five-hour offline advances virtual time through save replay",
			is_equal_approx(float(segment.clock_delta.get("offline_seconds", 0.0)), 18000.0)
			and is_equal_approx(clock.now(), 1794632400.0)
			and segment.ledger.get("events", []).size() == 1
			and segment.ledger.events[0].kind == "save_offline_replay")
		_check("offline summary reports actual earned ether without direct grants",
			int(segment.delta.get("ether", 0)) == 80
			and int(segment.get("offline_granted", {}).get("ether", 0)) == 80
			and int(segment.get("offline_spent", {}).get("ether", -1)) == 0
			and segment.ledger.get("unexplained_resources", ["missing"]).is_empty()
			and report.get("verdict", "") == "pass")
		var before_repeat: Dictionary = Scenario.snapshot(game, clock)
		clock.replay_offline(1794614400.0, 1794632400.0)
		_check("repeating an already consumed offline window is idempotent",
			Scenario.snapshot(game, clock) == before_repeat)
		var kinds: Array = []
		for goal in report.get("available_goals", []):
			kinds.append(goal.kind)
		_check("next goals include finite Retort and local sigil actions",
			kinds.has("retort_start") and kinds.has("sigil"))
		deltas.append(segment.delta)
		game.queue_free()
		await process_frame
	_check("offline replay is deterministic from the same initial state", deltas[0] == deltas[1])


func _test_run_report_shape() -> void:
	var game := FakeGame.new()
	var scenario := {"scenario": 1, "segments": [{"kind": "active", "seconds": 5}, {"kind": "offline", "seconds": 10}]}
	var report: Dictionary = Scenario.run(game, null, 17, scenario)
	var segments: Array = report.get("segments", [])
	var fields_present: bool = report.get("scenario") == 1 and segments.size() == 2
	for segment in segments:
		for field in ["kind", "seconds", "before", "after", "delta", "clock_delta", "events", "counters", "stalls", "ledger", "policy", "reason", "blocked_goals"]:
			fields_present = fields_present and segment.has(field)
	_check("run returns scenario schema 1 and complete segment results", fields_present)
	_check("run preserves the declared scenario timeline without mutating the fake game", report.get("before") == report.get("after"))
	_check("run is deterministic for the same fake state and seed", report == Scenario.run(FakeGame.new(), null, 17, scenario))


func _test_real_action_delay_and_contract_claim() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game: Node = scene.instantiate()
	game.set_meta("progression_driver", true)
	game.game_clock = func(): return 1794614400.0
	game.balance = BalanceConfig.baseline()
	game.SAVE_PATH = "user://progression_scenario_action_claim_save.json"
	game.TEMP_PATH = "user://progression_scenario_action_claim_save.tmp"
	game.BACKUP_PATH = "user://progression_scenario_action_claim_save.bak"
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var clock: RefCounted = load("res://tests/progression_clock.gd").new(game)
	clock.set_virtual_epoch(1794614400.0)
	var virtual_now := Time.get_datetime_dict_from_unix_time(1794614400)
	game._contracts.ensure_period(virtual_now)
	var daily: Array = game._contracts.daily(virtual_now)
	var contract: Dictionary = daily[0] if not daily.is_empty() else {}
	var contract_id := String(contract.get("id", ""))
	if not contract_id.is_empty():
		game._contracts._contracts_daily_prog[contract_id] = int(contract.get("goal", 0))
	var report: Dictionary = Scenario.run(game, game.balance, 31,
		{"scenario": 1, "segments": [{"kind": "active", "seconds": 600.0,
			"policy": "session_balanced", "targets": ["dust"]}]}, clock)
	var segment: Dictionary = report.get("segments", [])[0]
	var before_now := float(segment.get("before", {}).get("clock", {}).get("now", 0.0))
	var first_action_at := INF
	for event_value in segment.get("events", []):
		if event_value is Dictionary and ["discovery", "brew"].has(String(event_value.get("kind", ""))):
			first_action_at = float(event_value.get("at", INF))
			break
	var claim_event := false
	for event_value in segment.get("ledger", {}).get("events", []):
		if event_value is Dictionary and String(event_value.get("kind", "")).begins_with("contract_claim:"):
			claim_event = true
	_check("player action consumes virtual active time before production event",
			first_action_at >= before_now + Scenario.ACTION_SECONDS - Scenario.TIME_EPSILON)
	_check("ready contract is settled through the real claim API",
			not contract_id.is_empty() and game._contracts._contracts_daily_done.has(contract_id) and claim_event)
	_check("contract reward changes are reconciled by the ledger",
		segment.get("ledger", {}).get("unexplained_resources", ["missing"]).is_empty())
	game.queue_free()
	await process_frame
