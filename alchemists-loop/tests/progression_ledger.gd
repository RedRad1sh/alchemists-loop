extends RefCounted
class_name ProgressionLedger

var _events: Array = []
var _counters: Dictionary = {}
var _resources: Dictionary = {}
var _operation_ids: Dictionary = {}
var _expected: Dictionary = {}
var unexplained: Array = []

func snapshot(game: Game) -> Dictionary:
	var essences := {}
	for id in game._retort._essence_inv:
		essences[id] = game._retort.essence_count(id)
	return {"ether": game._engine.ether, "reserve": game._engine.ether_overflow,
		"inventory": game._engine.inventory.duplicate(true), "essences": essences}

func start(game: Game) -> void:
	_expected = snapshot(game)

func reconcile(game: Game) -> void:
	var actual := snapshot(game)
	if not _expected.is_empty() and actual != _expected:
		unexplained.append({"expected": _expected.duplicate(true), "actual": actual})
	_expected = actual

func perform(game: Game, source: String, action: Callable, contract: Dictionary = {}) -> Variant:
	reconcile(game)
	var before := snapshot(game)
	var before_cap := int(game._engine._max_ether())
	var before_rate := float(game._engine._ether_rate())
	var price := _price(game, source)
	var achievements := game._progress_ui._ach_done.duplicate()
	var sets := game._progress_ui._set_done.duplicate()
	var milestones := game._engine._milestones_done.duplicate()
	var companion_level := game._spirit._companion_level
	var result: Variant = action.call()
	var after := snapshot(game)
	var after_cap := int(game._engine._max_ether())
	var after_rate := float(game._engine._ether_rate())
	_validate_operation(game, source, before, after, result, price, achievements, sets, milestones, companion_level, contract)
	var achievement_ids: Array = []
	var achievement_ether := 0
	for achievement in Game.ACHIEVEMENTS:
		var achievement_id := String(achievement.get("id", ""))
		if not achievements.has(achievement_id) and game._progress_ui._ach_done.has(achievement_id):
			achievement_ids.append(achievement_id)
			achievement_ether += int(achievement.get("ether", 0))
	if not achievement_ids.is_empty():
		increment_counter("achievement_updates", achievement_ids.size())
	var delta := int(after["ether"]) + int(after["reserve"]) - int(before["ether"]) - int(before["reserve"])
	add_resource_delta("ether_earned" if delta >= 0 else "ether_spent", abs(delta))
	var deltas := {"ether": int(after.ether) - int(before.ether), "reserve": int(after.reserve) - int(before.reserve)}
	for resource in ["inventory", "essences"]:
		var changes := {}
		var keys: Array = (before[resource] as Dictionary).keys()
		for key in (after[resource] as Dictionary).keys():
			if not keys.has(key):
				keys.append(key)
		for key in keys:
			var amount := int(after[resource].get(key, 0)) - int(before[resource].get(key, 0))
			if amount != 0:
				changes[key] = amount
		deltas[resource] = changes
	if before != after or not source.begins_with("scheduler") and not source.begins_with("retort_active"):
		var event := {"operation_id": "%s:%d" % [source, _events.size()], "kind": source,
			"at": game.game_now(), "deltas": deltas,
			"ether_cap_delta": after_cap - before_cap,
			"ether_rate_delta": after_rate - before_rate,
			"achievement_ids": achievement_ids,
			"achievement_ether": achievement_ether,
			"achievement_cap_delta": after_cap - before_cap if not achievement_ids.is_empty() else 0,
			"achievement_regen_delta": after_rate - before_rate if not achievement_ids.is_empty() else 0,
			"contract_cap_delta": after_cap - before_cap if source.begins_with("contract_claim:") and achievement_ids.is_empty() else 0,
			"contract_regen_delta": after_rate - before_rate if source.begins_with("contract_claim:") and achievement_ids.is_empty() else 0}
		if source.begins_with("contract_claim:") and result is Dictionary:
			var reward: Dictionary = result
			event["board_materials"] = reward.get("materials", {}).duplicate(true)
			event["board_buff"] = String(reward.get("buff", ""))
			event["board_decor"] = String(reward.get("decor", ""))
			event["board_duration"] = int(reward.get("duration", 0))
			event["board_power"] = float(reward.get("power", 0.0))
		record(event)
	_expected = after
	return result


func _price(game: Game, source: String) -> Dictionary:
	var axis := source.get_slice(":", 1)
	if source.begins_with("spring_purchase:"):
		var table := SpringBalance.axis_table(game.balance, axis)
		var level := int(game._engine.spring_levels.get(axis, 0))
		return table[level] if level < table.size() else {}
	if source.begins_with("ether_purchase:"):
		return {"ether": game._engine._up_cost(axis)}
	if source == "mastery_purchase":
		return {"ether": game._engine._mastery_cost()}
	if source == "workshop_rank":
		var table: Array = game._workshop._ranks()
		return table[game._workshop.rank + 1] if game._workshop.rank + 1 < table.size() else {}
	if source == "workshop_autonomy":
		var table: Array = game._workshop._autonomy()
		return table[game._workshop.autonomy_level + 1] if game._workshop.autonomy_level + 1 < table.size() else {}
	if source.begins_with("retort_purchase:"):
		var table := game._retort._axis_table(axis)
		var level := game._retort._level(axis)
		return table[level] if level < table.size() else {}
	return {}

func _validate_operation(game: Game, source: String, before: Dictionary, after: Dictionary, result: Variant,
		price: Dictionary, achievements: Dictionary, sets: Dictionary, milestones: Dictionary,
		companion_level: int, contract: Dictionary) -> void:
	var ether := 0
	var inventory := {}
	var essences := {}
	var ok: bool = result == true if result is bool else result is Dictionary and result.get("ok", false)
	if source.begins_with("scheduler") or source == "save_offline_replay":
		var stats: Dictionary = game._saves._return_workshop if source == "save_offline_replay" else result
		ether = int(stats.get("ether_gained", 0)) - int(stats.get("ether_spent", 0))
		inventory = stats.get("inventory_deltas", {}).duplicate()
		var retort: Dictionary = stats.get("retort", {})
		essences = retort.get("essences", {}).duplicate()
		for id in retort.get("inventory", {}):
			inventory[id] = int(inventory.get(id, 0)) + int(retort.inventory[id])
		if stats.get("status", "") in ["event_limit", "invalid_event"]:
			unexplained.append({"source": source, "reason": "scheduler_incomplete"})
	elif source.begins_with("repeat_scheduler") or source.begins_with("reverse_scheduler") or source == "prestige_reload":
		pass
	elif source == "prestige":
		for id in before.inventory:
			inventory[id] = -int(before.inventory[id])
		for id in Game.BASE_IDS:
			inventory[id] = int(inventory.get(id, 0)) + 3
		ether = int(game.balance.get_value("ether.start_ether")) - int(before.ether)
	elif not price.is_empty():
		if ok:
			ether = -int(price.get("ether", 0))
			for id in price.get("materials", {}):
				inventory[id] = -int(price.materials[id])
			for id in price.get("essences", {}):
				essences[id] = -int(price.essences[id])
	elif source.begins_with("contract_claim:"):
		if ok:
			inventory = (result as Dictionary).get("materials", {}).duplicate(true)
	elif source == "experiment":
		if ok:
			var output := String(contract.get("output", ""))
			var experiment_cost := int(game.balance.get_value("discovery.cost"))
			ether = -experiment_cost
			if not output.is_empty() and not before.inventory.has(output) \
					and not (game._selftest and not game.has_meta("progression_driver")):
				var rarity: Dictionary = game._engine._rarity_of(output)
				ether += int(rarity.get("bounty", 0))
				for milestone in Game.MILESTONES:
					var milestone_id := int(milestone)
					if game._engine._milestones_done.has(milestone_id) and not milestones.has(milestone_id):
						ether += int(game._engine._milestone_reward(milestone_id))
			inventory = contract.get("inventory", {}).duplicate()
	elif source.begins_with("manual_source:"):
		var amount := 1
		if game._engine._source_boost_until > Time.get_unix_time_from_system():
			amount += 1
		if game._engine._source_taps % maxi(2, 8 - game._engine._up_lvl("source_yield")) == 0:
			amount += 1
		inventory[source.get_slice(":", 1)] = amount
	elif not contract.is_empty():
		var success: bool = ok or source == "manual_brew" and result is Dictionary and not result.get("failed", true)
		if success:
			if source == "manual_brew" and result is Dictionary:
				ether = -int((result as Dictionary).get("ether_spent", 0))
				var output := String((result as Dictionary).get("output", ""))
				if not output.is_empty() and not before.inventory.has(output):
					var rarity: Dictionary = game._engine._rarity_of(output)
					ether += int(rarity.get("bounty", 0))
					for milestone in (result as Dictionary).get("milestones", []):
						ether += int(game._engine._milestone_reward(int(milestone)))
			else:
				ether = int(contract.get("ether", 0))
			inventory = contract.get("inventory", {}).duplicate()
			essences = contract.get("essences", {}).duplicate()
	elif source.begins_with("retort_active") and result is Dictionary:
		inventory = result.get("inventory", {})
		essences = result.get("essences", {})
	elif source == "retort_early_collect":
		pass
	else:
		unexplained.append({"source": source, "reason": "missing_operation_contract"})
	for achievement in Game.ACHIEVEMENTS:
		var id := String(achievement.id)
		if not achievements.has(id) and game._progress_ui._ach_done.has(id):
			ether += int(achievement.get("ether", 0))
	for category in Game.CATEGORY_SETS:
		if not sets.has(category.cat) and game._progress_ui._set_done.has(category.cat):
			ether += int(category.ether)
	if game._spirit._companion_level > companion_level:
		ether += 20 * game._spirit._companion_level
	var actual_ether := int(after.ether) + int(after.reserve) - int(before.ether) - int(before.reserve)
	if actual_ether != ether:
		unexplained.append({"source": source, "resource": "ether", "expected_delta": ether, "actual_delta": actual_ether})
	for resource in ["inventory", "essences"]:
		var expected: Dictionary = inventory if resource == "inventory" else essences
		var keys: Array = before[resource].keys()
		for id in after[resource]:
			if not keys.has(id): keys.append(id)
		for id in expected:
			if not keys.has(id): keys.append(id)
		for id in keys:
			var actual := int(after[resource].get(id, 0)) - int(before[resource].get(id, 0))
			if actual != int(expected.get(id, 0)):
				unexplained.append({"source": source, "resource": resource, "item": id,
					"expected_delta": int(expected.get(id, 0)), "actual_delta": actual})

func record(event: Dictionary) -> void:
	var operation_id := String(event.get("operation_id", ""))
	if operation_id != "":
		if _operation_ids.has(operation_id):
			push_error("ProgressionLedger duplicate operation id: " + operation_id)
			return
		_operation_ids[operation_id] = true
	_events.append(event.duplicate(true))


func increment_counter(name: String, amount: int = 1) -> void:
	_counters[name] = int(_counters.get(name, 0)) + amount


func add_resource_delta(name: String, amount: float) -> void:
	_resources[name] = float(_resources.get(name, 0.0)) + amount


func report() -> Dictionary:
	return {"events": _events.duplicate(true), "counters": _counters.duplicate(true),
		"resources": _resources.duplicate(true), "operation_count": _operation_ids.size(),
		"unexplained_resources": unexplained.duplicate(true)}
