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
	var debit := {output: 1}
	if known_before:
		debit[a] = int(debit.get(a, 0)) - 1
		debit[b] = int(debit.get(b, 0)) - 1
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

static func apply_experiment_outcome(game: Game, outcome: Dictionary, ledger: ProgressionLedger) -> bool:
	var status := String(outcome.get("status", ""))
	var request_id := String(outcome.get("request_id", ""))
	var operation_id := "" if request_id.is_empty() else "personal_experiment:" + request_id
	if not request_id.is_empty():
		for event_value in ledger.report().get("events", []):
			if event_value is Dictionary and String((event_value as Dictionary).get("operation_id", "")) == operation_id:
				last_reason = "duplicate"
				return false
	var target: Dictionary = game._online._target_state.duplicate(true)
	var target_mode := outcome.has("target_id")
	var target_id := String(outcome.get("target_id", ""))
	var target_matches := not target_mode
	if target_mode:
		target_matches = not target_id.is_empty() and String(target.get("id", "")) == target_id \
			and String(target.get("status", "")) == "active"
		if outcome.has("target_kind"):
			target_matches = target_matches and String(outcome["target_kind"]) == String(target.get("kind", ""))
	var target_kind := String(outcome.get("target_kind", target.get("kind", "")))
	var result_kind := String(outcome.get("result_kind", "reused" if bool(outcome.get("reused", false)) \
		else ("known" if String(outcome.get("server_status", "")) == "known" else "created")))
	var acquired := bool(outcome.get("acquired", true))
	var acquired_valid := not outcome.has("acquired") or outcome["acquired"] is bool
	var before_ether := game._engine._available_ether()
	var succeeded := false
	var charged := 0
	var rejection := ""
	if not target_matches:
		rejection = "target_mismatch"
	elif status == "success":
		var output := String(outcome.get("output", ""))
		var default_cost := int(game.balance.get_value("personal_experiment.cost",
			game.balance.get_value("discovery.cost", Game.EXPERIMENT_COST)))
		var raw_cost: Variant = outcome.get("cost", default_cost)
		var cost_valid := typeof(raw_cost) == TYPE_INT or typeof(raw_cost) == TYPE_FLOAT
		if cost_valid:
			cost_valid = not is_nan(float(raw_cost)) and not is_inf(float(raw_cost)) \
				and is_equal_approx(float(raw_cost), round(float(raw_cost))) and float(raw_cost) >= 0.0
		var cost := int(raw_cost) if cost_valid else -1
		if result_kind not in ["created", "known", "reused"]:
			rejection = "invalid_result_kind"
		elif not acquired_valid or not acquired:
			rejection = "not_acquired"
		elif output.is_empty() or not game.ITEMS.has(output):
			rejection = "invalid_output"
		elif int(game._engine.inventory.get(output, 0)) >= Game.CRAFT_INVENTORY_STACK_CAP:
			rejection = "inventory_cap"
		elif not cost_valid:
			rejection = "invalid_cost"
		elif game._engine._available_ether() < cost:
			rejection = "insufficient_ether"
		else:
			var contract := {"ether": -cost, "inventory": {output: 1}}
			succeeded = bool(ledger.perform(game, "personal_experiment", func():
				if not game._engine._spend_ether(cost):
					return false
				game._engine.inventory[output] = int(game._engine.inventory.get(output, 0)) + 1
				return true, contract))
			if succeeded:
				charged = cost
				last_reason = "accepted"
			else:
				rejection = "commit_failed"
	else:
		last_reason = "unsuccessful:" + status
		ledger.reconcile(game)
	if not rejection.is_empty():
		last_reason = rejection
		ledger.reconcile(game)
	if target_mode and target_matches:
		_advance_personal_target(game, target, outcome, succeeded, charged, result_kind, ledger)
	ledger.increment_counter("personal_experiment_attempts")
	ledger.increment_counter("personal_experiment_successes" if succeeded else "personal_experiment_failures")
	ledger.record({
		"operation_id": operation_id,
		"kind": "personal_experiment",
		"status": status,
		"accepted": succeeded,
		"target_kind": target_kind,
		"result_kind": result_kind,
		"ether_delta": game._engine._available_ether() - before_ether,
		"deltas": {},
		"at": game.game_now(),
	})
	return succeeded


static func _advance_personal_target(game: Game, target: Dictionary, outcome: Dictionary, accepted: bool,
		charged: int, result_kind: String, ledger: ProgressionLedger) -> void:
	var next_target: Dictionary = target.duplicate(true)
	next_target["attempts"] = int(target.get("attempts", 0)) + 1
	if accepted:
		next_target["successful_steps"] = int(target.get("successful_steps", 0)) + 1
		next_target["spent_ether"] = int(target.get("spent_ether", 0)) + charged
		var completed := false
		var kind := String(target.get("kind", ""))
		if kind == "world":
			completed = String(outcome.get("output", "")) == String(target.get("slug", ""))
		elif kind == "llm" and result_kind == "created" and bool(outcome.get("acquired", false)):
			completed = _normalized_personal_name(String(outcome.get("output_name", ""))) \
				== _normalized_personal_name(String(target.get("name", "")))
		if completed:
			next_target["status"] = "completed"
			next_target["completed"] = true
			next_target["next_eligible_week"] = next_personal_week(String(outcome.get("cycle_week",
				String(target.get("cycle_week", "")))))
			ledger.increment_counter("personal_experiment_completions")
	game._online._target_state = next_target


static func personal_target_bucket(device_id: String, cycle_week: String, sequence: int) -> int:
	var value := "%s|%s|%d" % [device_id, cycle_week, sequence]
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	var digest := context.finish()
	var bucket := 0
	for byte in digest:
		bucket = (bucket * 256 + int(byte)) % 100
	return bucket


static func choose_personal_target_kind(device_id: String, cycle_week: String, sequence: int,
		world_available: bool) -> String:
	if not world_available:
		return "llm"
	return "world" if personal_target_bucket(device_id, cycle_week, sequence) < 80 else "llm"


static func personal_target_plan(device_id: String, cycle_week: String, sequence: int,
		world_frontier: Array) -> Dictionary:
	var candidates: Array = []
	for raw_slug in world_frontier:
		var slug := String(raw_slug)
		if not slug.is_empty() and not candidates.has(slug):
			candidates.append(slug)
	candidates.sort()
	var bucket := personal_target_bucket(device_id, cycle_week, sequence)
	if candidates.is_empty() or bucket >= 80:
		return {"kind": "llm", "slug": "", "bucket": bucket}
	return {"kind": "world", "slug": String(candidates[bucket % candidates.size()]), "bucket": bucket}


static func allocate_personal_target(game: Game, device_id: String, cycle_week: String, sequence: int,
		world_frontier: Array, ledger: ProgressionLedger) -> Dictionary:
	var current: Dictionary = game._online._target_state.duplicate(true)
	if not String(current.get("id", "")).is_empty():
		if String(current.get("status", "")) == "active":
			return current
		if String(current.get("status", "")) not in ["completed", "waiting_next_slot"]:
			return {}
		var next_eligible := String(current.get("next_eligible_week", ""))
		if not next_eligible.is_empty() and cycle_week < next_eligible:
			return {}
	var plan := personal_target_plan(device_id, cycle_week, sequence, world_frontier)
	var kind := String(plan.get("kind", ""))
	var slug := String(plan.get("slug", ""))
	var item: Dictionary = game.ITEMS.get(slug, {})
	var target := {
		"id": "sim-personal-%d-%s" % [sequence, kind],
		"kind": kind,
		"slug": slug,
		"name": String(item.get("name", slug)) if kind == "world" else "Синтетическая LLM цель",
		"hint": "Открой это вещество в новом эксперименте." if kind == "world" else "Завершите персональную LLM-цель.",
		"status": "active",
		"cycle_week": cycle_week,
		"attempts": 0,
		"successful_steps": 0,
		"spent_ether": 0,
		"next_eligible_week": "",
		"completed": false,
		"generation": int(current.get("generation", 0)) + 1,
	}
	game._online._target_state = target
	ledger.increment_counter("personal_experiment_targets_allocated")
	ledger.increment_counter("personal_experiment_%s_targets" % kind)
	ledger.reconcile(game)
	return target


static func next_personal_week(cycle_week: String) -> String:
	var parts := cycle_week.split("-W", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return ""
	var year := int(parts[0])
	var week := int(parts[1])
	if year < 1 or week < 1 or week > _weeks_in_iso_year(year):
		return ""
	week += 1
	if week > _weeks_in_iso_year(year):
		year += 1
		week = 1
	return "%04d-W%02d" % [year, week]


static func _weeks_in_iso_year(year: int) -> int:
	var weekday := _iso_weekday(_date_unix(year, 1, 1))
	if weekday == 4 or weekday == 3 and year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
		return 53
	return 52


static func _date_unix(year: int, month: int, day: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0}))


static func _iso_weekday(unix_time: int) -> int:
	return (int(unix_time / 86400) + 3) % 7 + 1


static func _normalized_personal_name(value: String) -> String:
	var normalized := value.strip_edges().to_lower().replace("ё", "е")
	for whitespace in ["\r", "\n", "\t", "\v", "\f", "\u00A0", "\u202F"]:
		normalized = normalized.replace(whitespace, " ")
	return " ".join(normalized.split(" ", false))


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
