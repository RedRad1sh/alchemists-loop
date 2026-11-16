extends RefCounted
class_name ProgressionStrategy

static var last_reason := ""
const TIME_EPSILON := 0.000001

static func next_frontier(game: Game, target_ids: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for raw in game.RECIPES:
		var recipe: Dictionary = raw
		var out := String(recipe.get("out", ""))
		if not target_ids.has(out) or game._engine.inventory.has(out):
			continue
		var a := String(recipe.get("a", ""))
		var b := String(recipe.get("b", ""))
		if not game._engine.inventory.has(a) or not game._engine.inventory.has(b):
			continue
		var candidate := {"a": a, "b": b, "out": out,
			"key": game._pair_key(a, b), "layer": game._engine._content_layer(out)}
		if best.is_empty() or _less(candidate, best):
			best = candidate
	return best

static func ensure_inputs(game: Game, recipe: Dictionary, clock: ProgressionClock, ledger: ProgressionLedger,
		active_deadline: float = -1.0) -> bool:
	var needs := {}
	for input_id in [String(recipe.get("a", "")), String(recipe.get("b", ""))]:
		needs[input_id] = int(needs.get(input_id, 0)) + 1
	var ordered: Array = needs.keys()
	ordered.sort_custom(func(a, b): return game._engine._content_layer(String(a)) > game._engine._content_layer(String(b)))
	for id in ordered:
		if not ensure_stock(game, String(id), int(needs[id]), clock, ledger, 0, active_deadline):
			return false
	return true

static func ensure_stock(game: Game, id: String, amount: int, clock: ProgressionClock, ledger: ProgressionLedger,
		depth: int = 0, active_deadline: float = -1.0) -> bool:
	if depth > 64 or amount > Game.CRAFT_INVENTORY_STACK_CAP or not game.ITEMS.has(id):
		last_reason = "invalid_or_cyclic_material_target:" + id
		return false
	if int(game._engine.inventory.get(id, 0)) >= amount:
		return true
	if active_deadline >= 0.0 and clock.active_seconds >= active_deadline - TIME_EPSILON:
		last_reason = "active_budget_before_inputs:" + id
		return false
	if id in Game.BASE_IDS:
		if not game._engine._mode_unlocked("spring"):
			for attempt in range(amount):
				if int(game._engine.inventory.get(id, 0)) >= amount:
					return true
				if not _can_advance(clock, 1.0, active_deadline):
					last_reason = "active_budget_before_inputs:" + id
					return false
				ledger.perform(game, "manual_source:" + id, func(): game._engine._collect(id, true))
				clock.active_player_seconds += 1.0
				clock.advance_active(1.0)
		else:
			# Existing UI command handlers are the authoritative source switch.
			var screen := SpringScreen.new()
			screen._game = game
			if not game._engine.spring_sources.has(id):
				screen._on_source_tapped(null, id)
			if not game._engine.spring_on:
				screen._on_toggle()
			screen.free()
			for attempt in range(amount + 1):
				if int(game._engine.inventory.get(id, 0)) >= amount:
					return true
				var before := int(game._engine.inventory.get(id, 0))
				var spring_interval := game._engine.spring_interval()
				if not _can_advance(clock, spring_interval, active_deadline):
					last_reason = "active_budget_before_inputs:" + id
					return false
				clock.advance_active(spring_interval)
				if int(game._engine.inventory.get(id, 0)) == before:
					last_reason = "spring_buffer_or_stack_cap:" + id
					return false
		return int(game._engine.inventory.get(id, 0)) >= amount
	var source := _recipe_for_output(game, id)
	if source.is_empty() or not game._engine.known_recipes.has(game._pair_key(String(source.a), String(source.b))):
		last_reason = "unknown_material_recipe:" + id
		return false
	var missing := amount - int(game._engine.inventory.get(id, 0))
	for unit in range(missing):
		var needs := {}
		for input in [String(source.a), String(source.b)]:
			needs[input] = int(needs.get(input, 0)) + 1
		var inputs: Array = needs.keys()
		inputs.sort_custom(func(a, b): return game._engine._content_layer(String(a)) > game._engine._content_layer(String(b)))
		for input in inputs:
			if not ensure_stock(game, input, int(needs[input]), clock, ledger, depth + 1, active_deadline):
				return false
		# Validate the production planner after earned base stock exists. Never
		# accept base_add as a grant (it is only a requirement in this contract).
		var plan: Dictionary = game._guild._plan_craft(id, 1)
		if not bool(plan.get("ok", false)):
			last_reason = "planner:" + String(plan.get("reason", ""))
			return false
		if game._workshop.unlocked:
			game._workshop.materialize_lines()
			var line: Dictionary = game._workshop.lines[0]
			if not line["queue"].is_empty():
				last_reason = "workshop_queue_busy"
				return false
			var queued: Dictionary = game._workshop.enqueue(String(line.id), {"target": id, "mode": "batch", "amount": 1})
			if not queued.get("ok", false):
				last_reason = "workshop_enqueue:" + String(queued.get("reason", ""))
				return false
			var before := int(game._engine.inventory.get(id, 0))
			for tick in range(120):
				if not _can_advance(clock, 10.0, active_deadline):
					last_reason = "active_budget_before_inputs:" + id
					return false
				clock.advance_active(10.0)
				if int(game._engine.inventory.get(id, 0)) > before:
					break
			if not line["queue"].is_empty():
				last_reason = "workshop_stall:" + String(line["queue"][0].get("reason", ""))
				return false
		else:
			var cost := game._engine._pair_cost(String(source.a), String(source.b))
			if not wait_ether(game, cost, clock, active_deadline):
				return false
			var brew_time := game._engine._brew_time()
			if not _can_advance(clock, brew_time, active_deadline):
				last_reason = "active_budget_before_inputs:" + id
				return false
			clock.advance_active(brew_time)
			if not discover_and_brew(game, source, ledger):
				return false
	return int(game._engine.inventory.get(id, 0)) >= amount

static func wait_ether(game: Game, cost: int, clock: ProgressionClock, active_deadline: float = -1.0) -> bool:
	if game._engine._available_ether() >= cost:
		return true
	if cost > game._engine._max_ether() + game._engine.ether_overflow:
		last_reason = "ether_cost_exceeds_cap:%d/%d" % [cost, game._engine._max_ether()]
		return false
	var rate := game._engine._ether_rate()
	if rate <= 0.0:
		last_reason = "ether_no_regeneration"
		return false
	var wait_seconds: float = ceil(float(cost - game._engine._available_ether()) / rate) + 1.0
	if not _can_advance(clock, wait_seconds, active_deadline):
		last_reason = "active_budget_before_ether"
		return false
	clock.advance_active(wait_seconds)
	return game._engine._available_ether() >= cost

static func discover_and_brew(game: Game, target: Dictionary, ledger: ProgressionLedger) -> bool:
	var a := String(target.get("a", ""))
	var b := String(target.get("b", ""))
	if a.is_empty() or b.is_empty() or not game._online._has_ingredients(a, b):
		last_reason = "insufficient_brew_inputs"
		return false
	var output := String(target.get("out", ""))
	var known_before := game._engine.known_recipes.has(game._pair_key(a, b))
	var before := int(game._engine.inventory.get(output, 0))
	var succeeded := false
	var debit := {a: -1}
	debit[b] = int(debit.get(b, 0)) - 1
	debit[output] = int(debit.get(output, 0)) + 1
	var cost := game._engine._pair_cost(a, b) if known_before else int(game.balance.get_value("discovery.cost"))
	var reward := 0
	if not game._engine.inventory.has(output) and (not game._selftest or game.has_meta("progression_driver")):
		var layer := game._engine._content_layer(output)
		var tier := 0 if layer <= 0 else (1 if layer <= 2 else (2 if layer <= 4 else (3 if layer == 5 else 4)))
		reward += int(game.balance.get_value("discovery.bounties")[tier])
		for threshold in Game.MILESTONES:
			if game._engine.inventory.size() + 1 >= int(threshold) and not game._engine._milestones_done.has(int(threshold)):
				reward += game._engine._milestone_reward(int(threshold))
	var contract := {"inventory": debit, "output": output}
	if known_before:
		contract["ether"] = -cost
	if not known_before:
		succeeded = bool(ledger.perform(game, "experiment", func(): return game._online._start_experiment(a, b), contract))
	else:
		var result: Dictionary = ledger.perform(game, "manual_brew", func():
			return game._engine._commit_brew(a, b, {"source": "manual", "production": false, "discount": 1.0}), contract)
		succeeded = not bool(result.get("failed", true))
	if not succeeded or int(game._engine.inventory.get(output, 0)) <= before:
		last_reason = "unconfirmed_brew:" + game._engine.status_text
		return false
	ledger.increment_counter("discoveries" if not known_before else "brews")
	return game._engine.known_recipes.has(game._pair_key(a, b))

static func _can_advance(clock: ProgressionClock, seconds: float, active_deadline: float) -> bool:
	return active_deadline < 0.0 or clock.active_seconds + seconds <= active_deadline + TIME_EPSILON

static func _recipe_for_output(game: Game, output: String) -> Dictionary:
	for raw in game.RECIPES:
		var recipe: Dictionary = raw
		if String(recipe.get("out", "")) == output:
			return recipe.duplicate(true)
	return {}

static func _less(left: Dictionary, right: Dictionary) -> bool:
	var ll := int(left.get("layer", 0))
	var rl := int(right.get("layer", 0))
	if ll != rl:
		return ll < rl
	return String(left.get("key", "")) < String(right.get("key", ""))
