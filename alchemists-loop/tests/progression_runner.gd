extends RefCounted
class_name ProgressionRunner

var game: Game
var clock: ProgressionClock
var ledger: ProgressionLedger
var phases: Dictionary = {}
var seed_value := 0
var profile: BalanceProfile
var progress_path := "res://.godot/progression-progress.json"
var report_path := ""
var _progress: Dictionary = {}
var _last_discovered := ""
var _progress_write_failed := false
var upgrade_targets: Array = []
var sigil_targets: Array = []
var prestige_proof := false
var reload_proof := false
var replay_proof := false
var retort_queue_proof := false
var first_workshop_seconds := -1.0
var first_retort_seconds := -1.0
var fixture: RefCounted
var stalls: Array = []
var wall_budget_ms := 90000
var _started_ms := Time.get_ticks_msec()

func _expired() -> bool:
	return Time.get_ticks_msec() - _started_ms >= wall_budget_ms

func _init(target_game: Game, seed_input: int = 1, active_profile: BalanceProfile = null) -> void:
	game = target_game
	seed_value = seed_input
	profile = active_profile if active_profile != null else BalanceConfig.baseline()
	game.balance = profile
	clock = ProgressionClock.new(game)
	ledger = ProgressionLedger.new()
	seed(seed_value)

func run_profile(profile_path: String, seed_input: int) -> Dictionary:
	var resolved := BalanceConfig.load_profile_json(profile_path) if not profile_path.is_empty() else BalanceConfig.baseline()
	if resolved == null:
		return {"verdict": "fail", "reason": "invalid_profile"}
	seed_value = seed_input
	profile = resolved
	game.balance = resolved
	return run_phases()

func advance_active(seconds: float) -> Dictionary:
	clock.advance_active(seconds)
	return {"ok": true, "seconds": seconds}

func replay_offline(from_ts: float, to_ts: float) -> Dictionary:
	clock.replay_offline(from_ts, to_ts)
	return {"ok": true, "from": from_ts, "to": to_ts}

func catalog_hash() -> String:
	var ids: Array = game.ITEMS.keys()
	ids.sort()
	var recipes: Array = []
	for recipe in game.RECIPES:
		recipes.append("%s=%s" % [game._pair_key(String(recipe.a), String(recipe.b)), recipe.out])
	recipes.sort()
	return JSON.stringify([ids, recipes]).sha256_text()

func run_idle_until(predicate: Callable, max_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < max_seconds:
		if predicate.call():
			return true
		var step := minf(10.0, max_seconds - elapsed)
		clock.advance_active(step)
		elapsed += step
	return bool(predicate.call())

func run_retort_until(predicate: Callable, max_seconds: float) -> bool:
	return run_idle_until(predicate, max_seconds)

func retort_snapshot() -> Dictionary:
	return {"levels": game._retort._cube_levels.duplicate(true),
		"essences": game._retort._essence_inv.duplicate(true), "codex": game._retort._essence_codex.duplicate(true)}

func buy_available_spring_upgrades() -> int:
	var bought := 0
	for axis in ["speed", "volume", "sources", "offline"]:
		while game._engine.spring_levels.get(axis, 0) < SpringBalance.axis_table(profile, axis).size():
			var result: Dictionary = ledger.perform(game, "spring_purchase:" + axis, func(): return game._engine.spring_purchase(axis))
			if not result.get("ok", false):
				break
			bought += 1
			ledger.increment_counter("spring_upgrades")
	return bought

func buy_available_workshop_upgrades() -> int:
	var bought := 0
	while game._workshop.rank + 1 < game._workshop._ranks().size():
		var result: Dictionary = ledger.perform(game, "workshop_rank", func(): return game._workshop.buy_rank(game._workshop.rank + 1))
		if not result.get("ok", false):
			break
		bought += 1
		ledger.increment_counter("workshop_rank_upgrades")
	while game._workshop.autonomy_level + 1 < game._workshop._autonomy().size():
		var result: Dictionary = ledger.perform(game, "workshop_autonomy", func(): return game._workshop.buy_autonomy())
		if not result.get("ok", false):
			break
		bought += 1
		ledger.increment_counter("workshop_autonomy_upgrades")
	return bought

func buy_available_ether_upgrades() -> int:
	var bought := 0
	for upgrade in profile.get_value("upgrades.items", []):
		var id := String(upgrade.id)
		while game._engine._up_unlocked(id) and game._engine._up_lvl(id) < int(upgrade.max):
			if not ledger.perform(game, "ether_purchase:" + id, func(): return game._engine._buy_upgrade(id)):
				break
			bought += 1
			ledger.increment_counter("ether_upgrades")
	return bought

func buy_available_retort_upgrades() -> int:
	var bought := 0
	for axis in game._retort._cube_levels:
		while game._retort._level(axis) < game._retort._axis_table(axis).size():
			var result: Dictionary = ledger.perform(game, "retort_purchase:" + axis, func(): return game._retort.cube_purchase(axis))
			if not result.get("ok", false):
				break
			bought += 1
			ledger.increment_counter("retort_axes_upgraded")
	return bought

func produce_materials_for(target: Dictionary) -> bool:
	return ProgressionStrategy.ensure_stock(game, String(target.get("item", target.get("out", ""))), int(target.get("amount", 1)), clock, ledger)

func _prepare_cost(price: Dictionary) -> bool:
	for item in price.get("materials", {}):
		if not produce_materials_for({"item": item, "amount": int(price.materials[item])}):
			return false
	return ProgressionStrategy.wait_ether(game, int(price.get("ether", 0)), clock)

func _enumerate_upgrades() -> Array:
	var targets: Array = []
	for axis in ["speed", "volume", "sources", "offline"]:
		var table := SpringBalance.axis_table(profile, axis)
		for i in range(table.size()):
			targets.append({"id": "spring/%s/%d" % [axis, i + 1], "kind": "spring", "axis": axis,
				"level": i + 1, "price": table[i], "complete": int(game._engine.spring_levels[axis]) > i})
	for upgrade in profile.get_value("upgrades.items", []):
		for i in range(int(upgrade.max)):
			targets.append({"id": "ether/%s/%d" % [upgrade.id, i + 1], "kind": "ether", "axis": upgrade.id,
				"level": i + 1, "price": {"ether": game._engine._up_cost_at(upgrade.id, i)},
				"complete": game._engine._up_lvl(upgrade.id) > i})
	for kind in ["rank", "autonomy"]:
		var table: Array = game._workshop._ranks() if kind == "rank" else game._workshop._autonomy()
		var level: int = game._workshop.rank if kind == "rank" else game._workshop.autonomy_level
		for i in range(1, table.size()):
			targets.append({"id": "workshop/%s/%d" % [kind, i], "kind": kind, "level": i,
				"price": table[i], "complete": level >= i})
	# Infinite seal purchases are not finite targets; their finite stage thresholds are.
	for rank in Game.MASTERY_STAGE_RANKS:
		targets.append({"id": "mastery/%d" % rank, "kind": "mastery", "level": rank,
			"price": {}, "complete": game._engine.mastery_rank >= int(rank)})
	for axis in game._retort._cube_levels:
		var table: Array = game._retort._axis_table(axis)
		for i in range(table.size()):
			targets.append({"id": "retort/%s/%d" % [axis, i + 1], "kind": "retort", "axis": axis,
				"level": i + 1, "price": table[i], "complete": game._retort._level(axis) > i})
	return targets

func _publish_targets(phase: String, event: String) -> void:
	var relevant := _enumerate_upgrades().filter(func(t): return (t.kind == "retort") == (phase == "retort"))
	update_progress(phase, relevant.filter(func(t): return t.complete).size(), relevant.size(), event)

func _economy() -> bool:
	_publish_targets("idle", "purchasing finite upgrades")
	for sweep in range(3):
		var bought := 0
		upgrade_targets = _enumerate_upgrades()
		for target in upgrade_targets:
			if _expired():
				target["reason"] = "wall_execution_budget_exhausted"
				continue
			if target.complete or target.kind == "retort":
				continue
			var ok := false
			var price: Dictionary = target.price
			if target.kind == "mastery":
				for i in range(maxi(0, int(target.level) - game._engine.mastery_rank)):
					if not ProgressionStrategy.wait_ether(game, game._engine._mastery_cost(), clock):
						break
					if not ledger.perform(game, "mastery_purchase", func(): return game._engine._buy_mastery()):
						break
				ok = game._engine.mastery_rank >= int(target.level)
			elif _prepare_cost(price):
				match target.kind:
					"spring":
						ok = bool(ledger.perform(game, "spring_purchase:" + String(target.axis), func(): return game._engine.spring_purchase(target.axis)).get("ok", false))
					"ether":
						ok = bool(ledger.perform(game, "ether_purchase:" + String(target.axis), func(): return game._engine._buy_upgrade(target.axis)))
					"rank":
						for batch in range(100):
							if game._workshop.xp >= int(price.get("xp", 0)):
								break
							if not produce_materials_for({"item": "steam", "amount": int(game._engine.inventory.get("steam", 0)) + 1}):
								break
						ok = bool(ledger.perform(game, "workshop_rank", func(): return game._workshop.buy_rank(int(target.level))).get("ok", false))
					"autonomy":
						ok = bool(ledger.perform(game, "workshop_autonomy", func(): return game._workshop.buy_autonomy()).get("ok", false))
			if ok:
				bought += 1
			else:
				target["reason"] = ProgressionStrategy.last_reason if not ProgressionStrategy.last_reason.is_empty() else "production_purchase_gate"
			_publish_targets("idle", String(target.id))
		if bought == 0:
			break
	upgrade_targets = _merge_target_reasons(upgrade_targets, _enumerate_upgrades())
	return upgrade_targets.filter(func(t): return not t.complete and t.kind != "retort").is_empty()

func _merge_target_reasons(old: Array, fresh: Array) -> Array:
	for target in fresh:
		if not target.complete:
			target["reason"] = "production_purchase_gate"
			for previous in old:
				if previous.id == target.id:
					target["reason"] = previous.get("reason", target.reason)
	return fresh

func _discovery(targets: Dictionary, budget: int, phase: String = "discovery") -> bool:
	var completed := _known_targets(targets)
	update_progress(phase, completed, targets.size(), "frontier")
	for step in range(budget):
		if _expired():
			return _stall("discovery", "wall_execution_budget_exhausted")
		if completed == targets.size():
			break
		var frontier := ProgressionStrategy.next_frontier(game, targets)
		if frontier.is_empty():
			return _stall("discovery", "graph_no_reachable_frontier")
		if not ProgressionStrategy.ensure_inputs(game, frontier, clock, ledger):
			return _stall("discovery", ProgressionStrategy.last_reason)
		var known := game._engine.known_recipes.has(frontier.key)
		# Preparing B may consume a previously prepared A as an intermediate.
		# Reconcile both quantities immediately before the transaction.
		if not ProgressionStrategy.ensure_inputs(game, frontier, clock, ledger):
			return _stall("discovery", ProgressionStrategy.last_reason)
		var cost: int = game._engine._pair_cost(frontier.a, frontier.b) if known else int(profile.get_value("discovery.cost", Game.EXPERIMENT_COST))
		if not ProgressionStrategy.wait_ether(game, cost, clock):
			return _stall("discovery", ProgressionStrategy.last_reason)
		if not known:
			if game._engine._experiment_remaining() == 0:
				var next_day: float = (floor(clock.now() / 86400.0) + 1.0) * 86400.0
				clock.replay_offline(clock.now(), next_day)
			clock.advance_active(game._engine._experiment_cooldown_remaining())
		else:
			clock.advance_active(game._engine._brew_time())
		if not ProgressionStrategy.discover_and_brew(game, frontier, ledger):
			return _stall("discovery", ProgressionStrategy.last_reason)
		clock.active_player_seconds += 1.0
		if game._workshop.unlocked and first_workshop_seconds < 0.0:
			first_workshop_seconds = clock.active_seconds + clock.offline_seconds
		completed = _known_targets(targets)
		if not game._saves._save_game():
			return _stall("discovery", "checkpoint_save_failed")
		_last_discovered = String(frontier.out)
		update_progress(phase, completed, targets.size(), "discovered " + _last_discovered)
	return completed == targets.size()

func _ensure_essence(id: String, amount: int, depth: int = 0) -> bool:
	if game._retort.essence_count(id) >= amount:
		return true
	if depth > 4 or _expired():
		ProgressionStrategy.last_reason = "retort_recursion_or_wall_budget_exhausted"
		return false
	if id.begins_with("blend-"):
		var element := id.trim_prefix("blend-")
		while game._retort.essence_count(id) < amount:
			if _expired():
				ProgressionStrategy.last_reason = "wall_execution_budget_exhausted"
				return false
			for ingredient in RetortBalance.BLEND_RECIPES.get(element, []):
				if not _ensure_essence(ingredient, 1, depth + 1):
					return false
			if not produce_blends_for({element: 1}):
				return false
		return true
	var candidates: Array = []
	for sub in game.ITEMS:
		if game._engine.inventory.has(sub) and game._retort.essence_of(sub) == id:
			candidates.append(sub)
	candidates.sort()
	for sub in candidates:
		if int(game._engine._rarity_of(sub).get("tier", 0)) > game._retort._max_distill_tier():
			continue
		while game._retort.essence_count(id) < amount:
			if _expired():
				ProgressionStrategy.last_reason = "wall_execution_budget_exhausted"
				return false
			if not produce_materials_for({"item": sub, "amount": 1}):
				break
			if not ledger.perform(game, "retort_start", func(): return game._retort._retort_start(0, sub, clock.now()), {"inventory": {sub: -1}}):
				break
			var early: Dictionary = ledger.perform(game, "retort_early_collect", func(): return game._retort._retort_collect(0, clock.now()))
			if early.get("ok", false):
				return _stall("retort", "early_collection_accepted")
			var duration := float(game._retort._retort_slot(0).get("dur", 0.0))
			if game._engine.spring_on:
				var screen := SpringScreen.new()
				screen._game = game
				screen._on_toggle()
				screen.free()
			clock.replay_offline(clock.now(), clock.now() + duration)
			var result: Dictionary = ledger.perform(game, "retort_collect", func(): return game._retort._retort_collect(0, clock.now()), {"essences": {id: 1}})
			if not result.get("ok", false):
				return false
			if first_retort_seconds < 0.0:
				first_retort_seconds = clock.active_seconds + clock.offline_seconds
			ledger.increment_counter("distillations")
			_publish_targets("retort", "distilled " + id)
		if game._retort.essence_count(id) >= amount:
			return true
	ProgressionStrategy.last_reason = "essence_tier_or_material_gate:" + id
	return false

func produce_blends_for(target_essences: Dictionary) -> bool:
	for element in target_essences:
		var cost := {}
		for id in RetortBalance.BLEND_RECIPES[element]:
			cost[id] = int(cost.get(id, 0)) - 1
		if not ledger.perform(game, "blend_start", func(): return game._retort.blend_start(element, clock.now()), {"essences": cost}):
			return false
		clock.replay_offline(clock.now(), clock.now() + float(game._retort._blend.get("dur", 0.0)))
		var result: Dictionary = ledger.perform(game, "blend_collect", func(): return game._retort.blend_collect(clock.now()), {"essences": {"blend-" + String(element): 1}})
		if not result.get("ok", false) or result.get("essence") != "blend-" + String(element):
			return false
		ledger.increment_counter("blends")
		_publish_targets("retort", "blended " + String(element))
	return true

func _retort_progression() -> bool:
	_publish_targets("retort", "purchasing essence axes")
	var purchase_limit := _enumerate_upgrades().filter(func(t): return t.kind == "retort").size()
	for sweep in range(purchase_limit):
		var bought := 0
		for axis in game._retort._cube_levels:
			var table: Array = game._retort._axis_table(axis)
			var level := game._retort._level(axis)
			if level >= table.size():
				continue
			var price: Dictionary = table[level]
			var allowed := true
			for req in price.get("req", {}):
				allowed = allowed and game._retort._level(req) >= int(price.req[req])
			if not allowed:
				continue
			for essence in price.get("essences", {}):
				if not _ensure_essence(essence, int(price.essences[essence])):
					_stall("retort", "%s/%d:%s:%s" % [axis, level + 1, essence, ProgressionStrategy.last_reason])
					allowed = false
					break
			if allowed:
				var result: Dictionary = ledger.perform(game, "retort_purchase:" + axis, func(): return game._retort.cube_purchase(axis))
				if result.get("ok", false):
					bought += 1
			_publish_targets("retort", "axis " + String(axis))
		if bought == 0:
			break
	upgrade_targets = _merge_target_reasons(upgrade_targets, _enumerate_upgrades())
	return upgrade_targets.filter(func(t): return t.kind == "retort" and not t.complete).is_empty()

func _retort_queue_check() -> bool:
	if game._retort._level("queue") == 0:
		return false
	if not produce_materials_for({"item": "fire", "amount": game._retort._retort_slots_open()}):
		return false
	if game._engine.spring_on:
		var screen := SpringScreen.new()
		screen._game = game
		screen._on_toggle()
		screen.free()
	var before: int = game._retort.essence_count("fire-0")
	if not game._retort.queue_set([{"sub": "fire"}]):
		return false
	game._retort.queue_toggle(true)
	clock.advance_active(0.0)
	var started := 0
	var duration := 0.0
	for slot in range(Game.RETORT_SLOT_MAX):
		if game._retort._retort_busy(slot):
			started += 1
			duration = maxf(duration, float(game._retort._retort_slot(slot).dur))
	game._retort.queue_set([])
	clock.replay_offline(clock.now(), clock.now() + duration)
	game._retort.queue_toggle(false)
	retort_queue_proof = started > 0 and game._retort.essence_count("fire-0") == before + started
	for slot in range(Game.RETORT_SLOT_MAX):
		retort_queue_proof = retort_queue_proof and not game._retort._retort_busy(slot)
	ledger.increment_counter("retort_queue_collections", started if retort_queue_proof else 0)
	return retort_queue_proof

func _effects() -> Dictionary:
	return {"speed": game._sigil.card_speed_bonus(), "cap": game._sigil.card_cap_bonus(), "autonomy": game._sigil.card_autonomy_bonus()}

func craft_available_sigils() -> int:
	var crafted := 0
	update_progress("sigil", 0, game._sigil._daily_crafts.size(), "crafting offered sigils")
	for craft in game._sigil._daily_crafts:
		var target := {"id": craft.id, "card_id": craft.card_id, "complete": false, "reason": "pending"}
		sigil_targets.append(target)
		if game._sigil.card(craft.card_id).is_empty():
			target.reason = "catalog_missing"
			continue
		var prepared := true
		for ingredient in craft.ingredients:
			if not produce_materials_for({"item": ingredient.item_id, "amount": ingredient.qty}):
				prepared = false
				break
		if not prepared or not ProgressionStrategy.wait_ether(game, game._sigil_ui._sigil_ether_cost(craft), clock):
			target.reason = ProgressionStrategy.last_reason
			continue
		var before := _effects()
		var copies := game._sigil.copies_of(craft.card_id)
		var debit := {}
		for ingredient in craft.ingredients:
			debit[ingredient.item_id] = int(debit.get(ingredient.item_id, 0)) - int(ingredient.qty)
		var started := bool(ledger.perform(game, "sigil_craft", func(): return game._sigil_ui.begin_sigil_craft(craft),
			{"ether": -game._sigil_ui._sigil_ether_cost(craft), "inventory": debit}))
		var after := _effects()
		var receipt := game._sigil_ui._pending_craft_result
		var confirmed: bool = started and receipt.get("craft_id", "") == craft.id \
			and game._sigil_ui._sigil_pending_craft.is_empty() \
			and game._sigil.copies_of(craft.card_id) == copies + 1
		target.complete = confirmed and after.speed > before.speed and after.cap >= before.cap and after.autonomy >= before.autonomy
		target.reason = "confirmed_receipt_collection_effects" if target.complete else "unconfirmed_receipt_collection_or_effects"
		target["before_effects"] = before
		target["after_effects"] = after
		if target.complete:
			crafted += 1
			ledger.increment_counter("sigils_crafted")
		update_progress("sigil", crafted, game._sigil._daily_crafts.size(), String(craft.id))
	return crafted

func _persistent() -> Dictionary:
	return {"retort": retort_snapshot(), "xp": game._workshop.xp,
		"rank": game._workshop.rank, "autonomy": game._workshop.autonomy_level,
		"mastery": game._engine.mastery_rank, "gold": game._engine.sage_gold}

func _prestige_cycle() -> bool:
	update_progress("prestige", 0, 1, "checking keep/reset and reload")
	var gain := game._hub._prestige_gain()
	if gain <= 0:
		return _stall("prestige", "insufficient_discoveries_for_prestige")
	if not game._saves._save_game():
		return _stall("prestige", "pre_prestige_save_failed")
	var before := _persistent()
	ledger.perform(game, "prestige", func(): game._hub._do_prestige())
	var after := _persistent()
	var reset := game._engine.inventory.size() == 4 and game._engine.upgrades.is_empty() \
		and game._engine.known_recipes.size() == 2 and game._engine._craft_job.is_empty()
	for line in game._workshop.lines:
		reset = reset and line["queue"].is_empty()
	var keep: bool = before.retort == after.retort and before.xp == after.xp and before.rank == after.rank \
		and before.autonomy == after.autonomy and before.mastery == after.mastery and after.gold == before.gold + gain
	var snapshot := ledger.snapshot(game)
	ledger.perform(game, "prestige_reload", func(): game._saves._load_game())
	reload_proof = snapshot == ledger.snapshot(game) and _persistent().gold == after.gold
	prestige_proof = reset and keep and reload_proof
	ledger.increment_counter("prestige_count", 1 if prestige_proof else 0)
	return prestige_proof

func _replay_check() -> bool:
	if not game._saves._save_game():
		return false
	var from := clock.now()
	clock.replay_offline(from, from + 120.0)
	var first := ledger.snapshot(game)
	var watermark := game._workshop.last_simulated_at
	clock.replay_offline(from, from + 120.0)
	var repeated: Dictionary = ledger.perform(game, "repeat_scheduler_replay", func(): return game._workshop_scheduler.replay_offline(from, from + 120.0))
	var reversed: Dictionary = ledger.perform(game, "reverse_scheduler_replay", func(): return game._workshop_scheduler.replay_offline(from, from - 1.0))
	clock.replay_offline(from, from - 1.0)
	replay_proof = first == ledger.snapshot(game) and game._workshop.last_simulated_at == watermark \
		and float(repeated.get("simulated_seconds", -1)) == 0.0 and int(repeated.get("events", -1)) == 0 \
		and float(reversed.get("simulated_seconds", -1)) == 0.0 and int(reversed.get("events", -1)) == 0
	return replay_proof

func run_phases(target_ids: Dictionary = {}, max_discoveries: int = 200, _idle_seconds: float = 10.0) -> Dictionary:
	phases.clear()
	if not game._selftest or game._online._net_enabled:
		_finish_phase("bootstrap/catalog", 0, 1, "fail", "isolation_required")
		return report("fail")
	var targets := target_ids.duplicate(true)
	if targets.is_empty():
		for id in game.ITEMS:
			if not game._online._server_elements.has(id):
				targets[id] = true
	for id in targets:
		if not game.ITEMS.has(id) or game._online._server_elements.has(id):
			_finish_phase("bootstrap/catalog", 0, 1, "fail", "graph_unknown_targets")
			return report("fail")
	if target_ids.is_empty() and targets.size() != 200:
		_finish_phase("bootstrap/catalog", 0, 1, "fail", "catalog_not_200")
		return report("fail")
	if clock.now() == 0.0:
		clock.set_virtual_epoch(1794614400.0)
	ledger.start(game)
	clock.ledger = ledger
	_finish_phase("bootstrap/catalog", 1, 1, "pass", "isolated_catalog_validated")
	var discovered := _discovery(targets, max_discoveries)
	_finish_phase("discovery", _known_targets(targets), targets.size(), "pass" if discovered else "fail", "all_targets_known" if discovered else _last_stall("discovery"))
	if not discovered:
		for phase in ["idle", "retort", "sigil", "prestige", "post_prestige_discovery", "proof"]:
			phases[phase] = {"completed": 0, "total": 1, "state": "incomplete", "reason": "discovery_incomplete"}
		update_progress("discovery", _known_targets(targets), targets.size(), _last_stall("discovery"), "fail")
		return report("fail")
	var economy := _economy()
	_finish_phase("idle", upgrade_targets.filter(func(t): return t.kind != "retort" and t.complete).size(), upgrade_targets.filter(func(t): return t.kind != "retort").size(), "pass" if economy else "fail", "finite_targets_purchased" if economy else "finite_purchase_targets_blocked")
	var retort_ok := _retort_progression()
	retort_ok = _retort_queue_check() and retort_ok
	_finish_phase("retort", upgrade_targets.filter(func(t): return t.kind == "retort" and t.complete).size(), upgrade_targets.filter(func(t): return t.kind == "retort").size(), "pass" if retort_ok else "fail", "retort_axes_complete" if retort_ok else "essence_tier_or_purchase_gate")
	fixture = load("res://tests/progression_sigil_fixture.gd").new()
	fixture.install(game)
	fixture.mode = String(game.get_meta("progression_sigil_mode", "success"))
	var crafted := craft_available_sigils()
	_finish_phase("sigil", crafted, fixture.crafts.size(), "pass" if crafted == fixture.crafts.size() else "fail", "receipt_collection_effects_verified" if crafted == fixture.crafts.size() else "sigil_resource_or_receipt_blocked")
	var prestige := _prestige_cycle()
	_finish_phase("prestige", 1 if prestige else 0, 1, "pass" if prestige else "fail", "keep_reset_reload_verified" if prestige else "prestige_keep_reset_reload_failed")
	if prestige:
		var reopened := _discovery(targets, max_discoveries, "post_prestige_discovery")
		_finish_phase("post_prestige_discovery", _known_targets(targets), targets.size(), "pass" if reopened else "fail", "real_reopen" if reopened else _last_stall("discovery"))
		var rebuilt := _economy()
		_finish_phase("idle", upgrade_targets.filter(func(t): return t.kind != "retort" and t.complete).size(), upgrade_targets.filter(func(t): return t.kind != "retort").size(), "pass" if rebuilt else "fail", "finite_targets_purchased" if rebuilt else "finite_purchase_targets_blocked")
	var replay := _replay_check()
	ledger.reconcile(game)
	var recipes := _recipe_counts()
	var pending := not game._engine._experiment_pending_pair.is_empty() or not game._sigil_ui._sigil_pending_craft.is_empty()
	for line in game._workshop.lines:
		pending = pending or not line["queue"].is_empty()
	for slot in range(Game.RETORT_SLOT_MAX):
		pending = pending or game._retort._retort_busy(slot)
	pending = pending or not game._retort._blend.is_empty()
	var complete: bool = target_ids.is_empty() and _known_targets(targets) == 200 and recipes.completed == recipes.total \
		and upgrade_targets.all(func(t): return t.complete) and sigil_targets.all(func(t): return t.complete) \
		and prestige_proof and reload_proof and replay and retort_queue_proof and ledger.unexplained.is_empty() and not pending \
		and clock.active_seconds + clock.offline_seconds > 3600.0
	_finish_phase("proof", 1 if complete else 0, 1, "pass" if complete else "fail", "all_proofs_pass" if complete else "incomplete_targets_or_persistence_or_conservation")
	fixture.manager.transport = Callable()
	var verdict := "pass" if complete and not _progress_write_failed else "fail"
	update_progress("finished", _known_targets(targets), targets.size(), "all_proofs_pass" if verdict == "pass" else "bounded_incomplete", verdict)
	return report(verdict)

func _recipe_counts() -> Dictionary:
	var completed := 0
	for recipe in game.RECIPES:
		if game._engine.known_recipes.has(game._pair_key(String(recipe.a), String(recipe.b))):
			completed += 1
	return {"completed": completed, "total": game.RECIPES.size()}

func _known_targets(targets: Dictionary) -> int:
	return targets.keys().filter(func(id): return game.ITEMS.has(id) and game._engine.inventory.has(id)).size()

func _stall(phase: String, reason: String) -> bool:
	stalls.append({"phase": phase, "reason": reason, "at": clock.now()})
	return false

func _last_stall(phase: String) -> String:
	for i in range(stalls.size() - 1, -1, -1):
		if stalls[i].phase == phase:
			return stalls[i].reason
	return "operation_budget_exhausted"

func _finish_phase(phase: String, completed: int, total: int, state: String, reason: String) -> void:
	phases[phase] = {"completed": completed, "total": total, "state": state, "reason": reason}
	update_progress(phase, completed, total, reason, state)

func update_progress(phase: String, completed: int, total: int, last_event: String, state: String = "running") -> bool:
	var phase_percent := clampf(100.0 * completed / total, 0.0, 100.0) if total > 0 else 0.0
	var passed := phases.values().filter(func(p): return p.state == "pass").size()
	var overall := minf(99.0, 100.0 * passed / 8.0)
	if phase == "finished" and state == "pass":
		overall = 100.0
	_progress = {"schema": 1, "phase": phase, "completed": clampi(completed, 0, maxi(0, total)),
		"total": maxi(0, total), "percent": overall, "phase_percent": phase_percent,
		"last_event": last_event, "last_discovered": _last_discovered, "simulated_seconds": clock.active_seconds + clock.offline_seconds,
		"updated_at": Time.get_unix_time_from_system(), "state": state, "verdict": state}
	print("[PROGRESS] " + JSON.stringify(_progress))
	var written := write_progress()
	_progress_write_failed = _progress_write_failed or not written
	return written

func progress_snapshot() -> Dictionary:
	return _progress.duplicate(true)

func write_progress(path: String = "") -> bool:
	return ProgressionReport.write_atomic(progress_path if path.is_empty() else path, progress_snapshot())

func report(verdict: String = "fail") -> Dictionary:
	if verdict == "pass" and (not prestige_proof or not reload_proof or not replay_proof
			or phases.get("proof", {}).get("state", "fail") != "pass" or _progress_write_failed):
		verdict = "fail"
	var targets := {}
	for id in game.ITEMS:
		if not game._online._server_elements.has(id):
			targets[id] = true
	var result := ProgressionReport.make(seed_value, profile, catalog_hash(), clock, ledger, phases, verdict)
	result["state"] = verdict
	result["progress"] = progress_snapshot()
	result["progress_write_failed"] = _progress_write_failed
	result["metrics"] = {"local_elements": {"completed": _known_targets(targets), "total": 200},
		"recipes": _recipe_counts(), "uncompleted_upgrades": upgrade_targets.filter(func(t): return not t.complete).size(),
		"uncompleted_sigil_targets": sigil_targets.filter(func(t): return not t.complete).size(),
		"prestige_proof": prestige_proof, "reload_proof": reload_proof, "replay_proof": replay_proof,
		"retort_queue_proof": retort_queue_proof,
		"unexplained_resources": ledger.unexplained.size(),
		"simulated_real_seconds": clock.active_seconds + clock.offline_seconds,
		"active_player_seconds": clock.active_player_seconds, "first_workshop_seconds": first_workshop_seconds,
		"first_retort_seconds": first_retort_seconds, "ether_deficit_at_completion": 0 if verdict == "pass" else null,
		"sigil_effects_active": _effects()}
	result["upgrade_targets"] = upgrade_targets.duplicate(true)
	result["sigil_targets"] = sigil_targets.duplicate(true)
	result["stalls"] = stalls.duplicate(true)
	result["scope"] = {"sigils": {"tested": ["common", "rare", "epic", "legendary"],
		"out_of_scope": ["chromatic network generation", "server collection milestones"]},
		"balance_timing": "one feasible strategy, not a shortest-path lower bound"}
	return result
