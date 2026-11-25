extends RefCounted
class_name ProgressionScenario

const SCHEMA := 1
const VALID_SEGMENT_KINDS := ["active", "offline"]
const ACTIVE_POLICY := "session_balanced"
const ACTION_SECONDS := 1.0
const TIME_EPSILON := 0.000001


static func validate(raw: Variant) -> Array:
	var errors: Array = []
	if not raw is Dictionary:
		return ["scenario must be an object"]
	var document: Dictionary = raw
	var version: Variant = document.get("scenario", document.get("schema", null))
	if _is_bool_or_not_number(version) or int(version) != SCHEMA:
		errors.append("unsupported scenario schema")
	var segments: Variant = document.get("segments", null)
	if not segments is Array:
		errors.append("segments must be an array")
		return errors
	if (segments as Array).is_empty():
		errors.append("segments must not be empty")
	for index in range((segments as Array).size()):
		var raw_segment: Variant = (segments as Array)[index]
		if not raw_segment is Dictionary:
			errors.append("segments[%d] must be an object" % index)
			continue
		var segment: Dictionary = raw_segment
		var kind := String(segment.get("kind", ""))
		if not VALID_SEGMENT_KINDS.has(kind):
			errors.append("segments[%d] has unknown kind: %s" % [index, kind])
		var seconds: Variant = segment.get("seconds", null)
		if _is_bool_or_not_number(seconds) or not is_finite(float(seconds)) or float(seconds) < 0.0:
			errors.append("segments[%d].seconds must be finite and non-negative" % index)
		if segment.has("personal_experiment_outcomes"):
			errors.append_array(_validate_personal_experiment_outcomes(segment["personal_experiment_outcomes"], index, kind))
	return errors


static func _validate_personal_experiment_outcomes(raw: Variant, segment_index: int, kind: String) -> Array:
	var errors: Array = []
	var prefix := "segments[%d].personal_experiment_outcomes" % segment_index
	if kind != "active":
		errors.append(prefix + " requires an active segment")
	if not raw is Array:
		return [prefix + " must be an array"]
	for index in range((raw as Array).size()):
		var value: Variant = (raw as Array)[index]
		var item_prefix := "%s[%d]" % [prefix, index]
		if not value is Dictionary:
			errors.append(item_prefix + " must be an object")
			continue
		var outcome: Dictionary = value
		var status := String(outcome.get("status", ""))
		if status.is_empty():
			errors.append(item_prefix + ".status must be a non-empty string")
		for key in ["request_id", "target_id", "target_kind"]:
			if outcome.has(key) and not (outcome[key] is String):
				errors.append(item_prefix + "." + key + " must be a string")
		if status == "success":
			if not (outcome.get("output", "") is String) or String(outcome.get("output", "")).is_empty():
				errors.append(item_prefix + ".output must be a non-empty string")
			if outcome.has("cost"):
				var cost: Variant = outcome["cost"]
				if _is_bool_or_not_number(cost) or not is_finite(float(cost)) \
						or not is_equal_approx(float(cost), round(float(cost))) or float(cost) < 0.0:
					errors.append(item_prefix + ".cost must be a finite non-negative integer")
	return errors


static func parse(raw: Variant) -> Dictionary:
	var errors: Array = validate(raw)
	if not errors.is_empty():
		return {"valid": false, "scenario": SCHEMA, "schema": SCHEMA, "segments": [], "errors": errors}
	var source: Dictionary = raw
	var normalized: Dictionary = source.duplicate(true)
	normalized["scenario"] = SCHEMA
	normalized["schema"] = SCHEMA
	normalized["valid"] = true
	var segments: Array = []
	for raw_segment in source["segments"]:
		var segment: Dictionary = (raw_segment as Dictionary).duplicate(true)
		segment["kind"] = String(segment["kind"])
		segment["seconds"] = float(segment["seconds"])
		segments.append(segment)
	normalized["segments"] = segments
	return normalized


static func parse_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"valid": false, "scenario": SCHEMA, "schema": SCHEMA,
			"errors": ["scenario file not found: " + path]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"valid": false, "scenario": SCHEMA, "schema": SCHEMA,
			"errors": ["scenario file is not valid JSON: " + path]}
	return parse(parser.data)


static func load_scenario(path: String) -> Dictionary:
	return parse_file(path)


static func parse_scenario(raw: Variant) -> Dictionary:
	return parse(raw)


static func validate_scenario(raw: Variant) -> Array:
	return validate(raw)


static func load_from_path(path: String) -> Dictionary:
	return parse_file(path)


static func snapshot(game: Variant, clock: Variant = null) -> Dictionary:
	var engine: Variant = _member(game, "_engine", null)
	var inventory := _dict_copy(_member(engine, "inventory", {}))
	var items := _dict_copy(_member(game, "ITEMS", {}))
	var online: Variant = _member(game, "_online", null)
	var target := _dict_copy(_member(online, "_target_state", {}))
	var personal_experiment := {
		"target_kind": String(target.get("kind", "")),
		"target_status": String(target.get("status", "")),
		"successful_steps": int(target.get("successful_steps", 0)),
		"spent_ether": int(target.get("spent_ether", 0)),
		"attempts": int(target.get("attempts", 0)),
	}
	var server_elements := _dict_copy(_member(online, "_server_elements", {}))
	var discovered_ids: Array = []
	for raw_id in inventory:
		var id := String(raw_id)
		if items.has(id) and not server_elements.has(id):
			discovered_ids.append(id)
	discovered_ids.sort()

	var ether_current := int(_member(engine, "ether", 0))
	var ether_overflow := int(_member(engine, "ether_overflow", 0))
	var ether_cap := int(_call(engine, "_max_ether", ether_current))
	var ether_rate := float(_call(engine, "_ether_rate", 0.0))
	var item_upgrades := _dict_copy(_member(engine, "upgrades", {}))
	var spring_levels := _dict_copy(_member(engine, "spring_levels", {}))
	var mastery_rank := int(_member(engine, "mastery_rank", 0))

	var workshop: Variant = _member(game, "_workshop", null)
	var workshop_lines := _array_copy(_member(workshop, "lines", []))
	var workshop_queues: Array = []
	for raw_line in workshop_lines:
		if raw_line is Dictionary:
			var line: Dictionary = raw_line as Dictionary
			workshop_queues.append({
				"id": String(line.get("id", "")),
				"paused": bool(line.get("paused", false)),
				"phase_seconds": float(line.get("phase_seconds", 0.0)),
				"stage_credit": int(line.get("stage_credit", 0)),
				"queue": _array_copy(line.get("queue", [])),
			})
		else:
			workshop_queues.append(raw_line)
	var workshop_data := {
		"unlocked": bool(_member(workshop, "unlocked", false)),
		"rank": int(_member(workshop, "rank", 0)),
		"autonomy": int(_member(workshop, "autonomy_level", 0)),
		"autonomy_level": int(_member(workshop, "autonomy_level", 0)),
		"xp": int(_member(workshop, "xp", 0)),
		"queues": workshop_queues.duplicate(true),
		"lines": workshop_lines.duplicate(true),
		"last_simulated_at": float(_member(workshop, "last_simulated_at", 0.0)),
	}

	var retort: Variant = _member(game, "_retort", null)
	var retort_slots := _array_copy(_member(retort, "_retort_slots", []))
	var retort_essences := _dict_copy(_member(retort, "_essence_inv", {}))
	var retort_blends := _dict_copy(_member(retort, "_blend", {}))
	var retort_data := {
		"slots": retort_slots.duplicate(true),
		"essences": retort_essences.duplicate(true),
		"blends": retort_blends.duplicate(true),
		"levels": _dict_copy(_member(retort, "_cube_levels", {})),
		"queue": _array_copy(_member(retort, "_queue", [])),
		"queue_on": bool(_member(retort, "_queue_on", false)),
	}

	var sigil: Variant = _member(game, "_sigil", null)
	var sigil_copies: Dictionary = {}
	var server_collection := _dict_copy(_member(sigil, "_server_collection", {}))
	for raw_card_id in server_collection:
		var server_card_id := String(raw_card_id)
		var server_entry: Variant = server_collection[raw_card_id]
		if server_entry is Dictionary:
			sigil_copies[server_card_id] = int((server_entry as Dictionary).get("copies", 0))
		else:
			sigil_copies[server_card_id] = int(server_entry)
	var sigil_craft_records: Dictionary = {}
	var local_card_counts: Dictionary = {}
	var local_collection := _dict_copy(_member(sigil, "_collection", {}))
	for raw_craft_id in local_collection:
		var craft_id := String(raw_craft_id)
		var local_entry: Variant = local_collection[raw_craft_id]
		if not local_entry is Dictionary:
			continue
		var craft_record: Dictionary = (local_entry as Dictionary).duplicate(true)
		sigil_craft_records[craft_id] = craft_record
		var local_card_id := String(craft_record.get("card_id", ""))
		if local_card_id.is_empty():
			continue
		local_card_counts[local_card_id] = int(local_card_counts.get(local_card_id, 0)) + 1
	for local_card_id in local_card_counts:
		sigil_copies[local_card_id] = maxi(int(sigil_copies.get(local_card_id, 0)),
			int(local_card_counts[local_card_id]))
	var sigil_effects := {
		"speed": float(_call(sigil, "card_speed_bonus", 0.0)),
		"cap": int(_call(sigil, "card_cap_bonus", 0)),
		"autonomy": int(_call(sigil, "card_autonomy_bonus", 0)),
	}
	var sigils_data := {"copies": sigil_copies.duplicate(true), "effects": sigil_effects.duplicate(true)}

	var clock_data: Dictionary = {}
	if clock != null:
		var clock_snapshot: Variant = _call(clock, "snapshot", {})
		if clock_snapshot is Dictionary:
			clock_data = (clock_snapshot as Dictionary).duplicate(true)
	if clock_data.is_empty():
		clock_data = {"now": 0.0, "active_seconds": 0.0, "offline_seconds": 0.0,
			"active_player_seconds": 0.0, "simulated_real_seconds": 0.0}

	var gold := int(_member(engine, "sage_gold", 0))
	var upgrade_data := {"items": item_upgrades.duplicate(true), "spring": spring_levels.duplicate(true), "mastery": mastery_rank}
	return {
		"local_discovered_ids": discovered_ids.duplicate(true),
		"local_discovered_count": discovered_ids.size(),
		"local": {"discovered_ids": discovered_ids.duplicate(true), "discovered_count": discovered_ids.size()},
		"known_recipe_count": _dict_copy(_member(engine, "known_recipes", {})).size(),
		"ether": ether_current,
		"ether_current": ether_current,
		"ether_cap": ether_cap,
		"ether_overflow": ether_overflow,
		"ether_available": ether_current + ether_overflow,
		"ether_rate": ether_rate,
		"ether_state": {"current": ether_current, "cap": ether_cap, "overflow": ether_overflow,
			"available": ether_current + ether_overflow, "rate": ether_rate},
		"inventory": inventory.duplicate(true),
		"spring": {"on": bool(_member(engine, "spring_on", false)),
			"sources": _array_copy(_member(engine, "spring_sources", [])),
			"buffer": _dict_copy(_member(engine, "spring_buffer", {})),
			"levels": spring_levels.duplicate(true)},
		"unlocked_modes": _unlocked_modes(game),
		"upgrade_levels": upgrade_data.duplicate(true),
		"workshop": workshop_data.duplicate(true),
		"workshop_rank": workshop_data.rank,
		"workshop_autonomy": workshop_data.autonomy,
		"workshop_xp": workshop_data.xp,
		"workshop_queues": workshop_queues.duplicate(true),
		"retort": retort_data.duplicate(true),
		"retort_slots": retort_slots.duplicate(true),
		"retort_essences": retort_essences.duplicate(true),
		"retort_blends": retort_blends.duplicate(true),
		"sigils": sigils_data.duplicate(true),
		"sigil_copies": sigil_copies.duplicate(true),
		"sigil_effects": sigil_effects.duplicate(true),
		"sigil_craft_records": sigil_craft_records.duplicate(true),
		"personal_experiment": personal_experiment.duplicate(true),
		"prestige": gold,
		"gold": gold,
		"prestige_gold": gold,
		"clock": clock_data.duplicate(true),
		"clock_totals": clock_data.duplicate(true),
	}


static func deep_delta(before: Variant, after: Variant) -> Variant:
	if _is_number(before) and _is_number(after):
		var number_delta := float(after) - float(before)
		if typeof(before) == TYPE_INT and typeof(after) == TYPE_INT:
			return int(round(number_delta))
		return number_delta
	if before is Dictionary or after is Dictionary:
		var before_dict: Dictionary = before if before is Dictionary else {}
		var after_dict: Dictionary = after if after is Dictionary else {}
		var keys: Array = before_dict.keys()
		for key in after_dict:
			if not keys.has(key):
				keys.append(key)
		var result: Dictionary = {}
		for key in keys:
			var has_before := before_dict.has(key)
			var has_after := after_dict.has(key)
			var left: Variant = before_dict[key] if has_before else _zero_like(after_dict[key])
			var right: Variant = after_dict[key] if has_after else _zero_like(before_dict[key])
			var child: Variant = deep_delta(left, right)
			if not _empty_delta(child):
				result[key] = child
		return result
	if before is Array or after is Array:
		var before_array: Array = before if before is Array else []
		var after_array: Array = after if after is Array else []
		if before_array == after_array:
			return []
		var changes: Array = []
		var size := maxi(before_array.size(), after_array.size())
		for index in range(size):
			if index >= before_array.size():
				changes.append({"index": index, "added": _copy_value(after_array[index])})
			elif index >= after_array.size():
				changes.append({"index": index, "removed": _copy_value(before_array[index])})
			else:
				var child: Variant = deep_delta(before_array[index], after_array[index])
				if not _empty_delta(child):
					changes.append({"index": index, "delta": child})
		return changes
	if before == after:
		return null
	return _copy_value(after)


static func delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Variant = deep_delta(before, after)
	return result if result is Dictionary else {}


static func next_goals(game: Variant, profile: Variant = null) -> Array:
	var goals: Array = []
	if game == null:
		return goals
	var engine: Variant = _member(game, "_engine", null)
	var inventory := _dict_copy(_member(engine, "inventory", {}))
	var available_ether := int(_member(engine, "ether", 0)) + int(_member(engine, "ether_overflow", 0))
	var online: Variant = _member(game, "_online", null)
	var target := _dict_copy(_member(online, "_target_state", {}))
	var target_id := String(target.get("id", ""))
	if not target_id.is_empty() and String(target.get("status", "")) == "active" \
			and bool(_profile_value(profile, "personal_experiment.enabled", true)):
		var cost := int(_profile_value(profile, "personal_experiment.cost", _profile_value(profile, "discovery.cost", 12)))
		var cooldown := maxf(0.0, float(_call(engine, "_experiment_cooldown_remaining", 0.0)))
		var reason := "available"
		var missing: Dictionary = {}
		if cooldown > TIME_EPSILON:
			reason = "cooldown"
			missing["seconds"] = cooldown
		elif available_ether < cost:
			reason = "ether"
			missing["ether"] = cost - available_ether
		goals.append({"id": "personal-experiment/" + target_id, "kind": "personal_experiment",
			"available": reason == "available", "missing": missing, "reason": reason,
			"target_kind": String(target.get("kind", "")), "cost": cost})
	var upgrade_items: Array = _array_copy(_profile_value(profile, "upgrades.items", []))
	for upgrade_value in upgrade_items:
		if not upgrade_value is Dictionary:
			continue
		var upgrade: Dictionary = upgrade_value
		var id := String(upgrade.get("id", ""))
		if id.is_empty():
			continue
		var level := int(_dict_copy(_member(engine, "upgrades", {})).get(id, 0))
		var maximum := int(upgrade.get("max", level))
		if level >= maximum:
			continue
		var unlocked_id := String(upgrade.get("unlock", ""))
		var unlocked := unlocked_id.is_empty() or inventory.has(unlocked_id)
		var cost: int = int(upgrade.get("base", 0))
		if engine is Object and (engine as Object).has_method("_up_cost_at"):
			cost = int(engine.call("_up_cost_at", id, level))
		var missing: Dictionary = {}
		var reason := "available"
		if not unlocked:
			reason = "not_unlocked"
			missing["unlock"] = unlocked_id
		elif available_ether < cost:
			reason = "ether"
			missing["ether"] = cost - available_ether
		goals.append({"id": "upgrade/" + id, "kind": "upgrade", "level": level + 1,
			"available": unlocked and available_ether >= cost, "missing": missing, "reason": reason})

	var items := _dict_copy(_member(game, "ITEMS", {}))
	var recipes: Array = _array_copy(_member(game, "RECIPES", []))
	var known := _dict_copy(_member(engine, "known_recipes", {}))
	for raw_recipe in recipes:
		if not raw_recipe is Dictionary:
			continue
		var recipe: Dictionary = raw_recipe
		var output := String(recipe.get("out", ""))
		var key := _pair_key(game, String(recipe.get("a", "")), String(recipe.get("b", "")))
		if output.is_empty() or inventory.has(output) or known.has(key):
			continue
		if not items.has(String(recipe.get("a", ""))) or not items.has(String(recipe.get("b", ""))):
			continue
		var ingredients: Dictionary = {}
		for ingredient in [String(recipe.get("a", "")), String(recipe.get("b", ""))]:
			ingredients[ingredient] = int(ingredients.get(ingredient, 0)) + 1
		var missing_ingredients: Dictionary = {}
		for ingredient in ingredients:
			var shortage := int(ingredients[ingredient]) - int(inventory.get(ingredient, 0))
			if shortage > 0:
				missing_ingredients[ingredient] = shortage
		var cost := int(_profile_value(profile, "discovery.cost", 12))
		var reason := "available"
		var missing := missing_ingredients.duplicate()
		if not inventory.has(String(recipe.a)) or not inventory.has(String(recipe.b)):
			reason = "recipe"
		elif not missing_ingredients.is_empty():
			reason = "ingredients"
		elif available_ether < cost:
			reason = "ether"
			missing["ether"] = cost - available_ether
		elif float(_call(engine, "_experiment_cooldown_remaining", 0.0)) > TIME_EPSILON:
			reason = "cooldown"
			missing["seconds"] = float(_call(engine, "_experiment_cooldown_remaining", 0.0))
		goals.append({"id": "discovery/" + output, "kind": "discovery", "available": reason == "available",
			"missing": missing, "reason": reason, "recipe": recipe.duplicate(true), "cost": cost})

	var workshop: Variant = _member(game, "_workshop", null)
	if workshop != null:
		var rank := int(_member(workshop, "rank", 0))
		var autonomy := int(_member(workshop, "autonomy_level", 0))
		var rank_table: Array = _array_copy(_call(workshop, "_ranks", []))
		if rank + 1 < rank_table.size():
			var rank_price: Dictionary = rank_table[rank + 1] if rank_table[rank + 1] is Dictionary else {}
			goals.append(_equipment_goal("workshop/rank/%d" % (rank + 1), "workshop_rank", rank + 1,
				workshop, rank_price, available_ether))
		var autonomy_table: Array = _array_copy(_call(workshop, "_autonomy", []))
		if autonomy + 1 < autonomy_table.size():
			var autonomy_price: Dictionary = autonomy_table[autonomy + 1] if autonomy_table[autonomy + 1] is Dictionary else {}
			goals.append(_equipment_goal("workshop/autonomy/%d" % (autonomy + 1), "workshop_autonomy", autonomy + 1,
				workshop, autonomy_price, available_ether))
	if game is Node and game.has_method("game_now"):
		var live: Variant = game
		var spring_script: Script = load("res://game/data/spring_balance.gd")
		for axis in ["speed", "volume", "sources", "offline"]:
			var table: Array = spring_script.axis_table(live.balance, axis)
			var level := int(live._engine.spring_levels.get(axis, 0))
			if level < table.size():
				var goal := _priced_goal(live, "spring/" + axis, "spring_upgrade", table[level], live._engine._mode_unlocked("spring"))
				goal["level"] = level + 1
				for req in table[level].get("req", {}):
					if int(live._engine.spring_levels.get(req, 0)) < int(table[level].req[req]):
						goal.reason = "not_unlocked"
						goal.available = false
						goal.missing[req] = int(table[level].req[req]) - int(live._engine.spring_levels.get(req, 0))
				goals.append(goal)
		var retort_open: bool = live._engine._mode_unlocked("retort")
		var candidates: Array = live._retort._retort_candidates()
		var sub := ""
		for candidate in candidates:
			if int(live._engine._rarity_of(candidate).get("tier", 0)) <= live._retort._max_distill_tier():
				sub = candidate
				break
		var now: float = live.game_now()
		var free_slot := -1
		for i in live._retort._retort_slots_open():
			var slot: Dictionary = live._retort._retort_slots[i] if i < live._retort._retort_slots.size() else {}
			if String(slot.get("sub", "")).is_empty():
				free_slot = i
			else:
				var left := maxf(0.0, float(slot.get("started", 0)) + float(slot.get("dur", 0)) - now)
				goals.append({"id": "retort/collect/%d" % i, "kind": "retort_collect", "slot": i,
					"available": left <= TIME_EPSILON, "reason": "available" if left <= TIME_EPSILON else "cooldown",
					"missing": {} if left <= TIME_EPSILON else {"seconds": left}, "output": slot.get("essence", "")})
		var start_reason := "not_unlocked" if not retort_open else ("cooldown" if free_slot < 0 else ("ingredients" if sub.is_empty() else "available"))
		goals.append({"id": "retort/start", "kind": "retort_start", "available": start_reason == "available",
			"reason": start_reason, "missing": {} if start_reason == "available" else {start_reason: true}, "sub": sub, "slot": free_slot})
		for axis in live._retort.AXES:
			var table: Array = live._retort._axis_table(axis)
			var level: int = live._retort._level(axis)
			if level >= table.size():
				continue
			var goal := _priced_goal(live, "retort/" + axis, "retort_upgrade", table[level], retort_open)
			goal["level"] = level + 1
			for req in table[level].get("req", {}):
				if live._retort._level(req) < int(table[level].req[req]):
					goal.reason = "not_unlocked"
					goal.available = false
					goal.missing[req] = int(table[level].req[req]) - live._retort._level(req)
			goals.append(goal)
		if not live._retort._blend.is_empty():
			var left := maxf(0.0, float(live._retort._blend.get("started", 0)) + float(live._retort._blend.get("dur", 0)) - now)
			goals.append({"id": "retort/blend/collect", "kind": "blend_collect", "available": left <= TIME_EPSILON,
				"reason": "available" if left <= TIME_EPSILON else "cooldown", "missing": {"seconds": left}})
		else:
			var blend_recipes: Dictionary = load("res://game/data/retort_balance.gd").BLEND_RECIPES
			for element in live._retort.ELEMENTS:
				var cost := {}
				for id in blend_recipes[element]:
					cost[id] = int(cost.get(id, 0)) + 1
				goals.append(_priced_goal(live, "retort/blend/" + element, "blend_start", {"essences": cost}, retort_open and live._retort._level("blend") > 0))
		for craft in live._sigil._daily_crafts:
			var materials := {}
			for ingredient in craft.get("ingredients", []):
				materials[ingredient.item_id] = int(materials.get(ingredient.item_id, 0)) + int(ingredient.qty)
			var goal := _priced_goal(live, "sigil/" + String(craft.id), "sigil",
				{"ether": live._sigil_ui._sigil_ether_cost(craft), "materials": materials}, true)
			goal["card_id"] = craft.get("card_id", "")
			goal["name"] = craft.get("fallback_name", craft.id)
			goals.append(goal)
		if live._sigil._daily_crafts.is_empty():
			goals.append({"id": "sigil/local-offer", "kind": "sigil", "available": false,
				"reason": "not_unlocked", "missing": {"offer": true}})
	return goals


static func _priced_goal(game: Variant, id: String, kind: String, price: Dictionary, unlocked: bool) -> Dictionary:
	var missing := {}
	var reason := "available"
	for item in price.get("materials", {}):
		var shortage := int(price.materials[item]) - int(game._engine.inventory.get(item, 0))
		if shortage > 0:
			missing[item] = shortage
			reason = "ingredients"
	for essence in price.get("essences", {}):
		var shortage: int = int(price.essences[essence]) - game._retort.essence_count(essence)
		if shortage > 0:
			missing[essence] = shortage
			reason = "ingredients"
	var ether_short: int = int(price.get("ether", 0)) - game._engine._available_ether()
	if ether_short > 0:
		missing["ether"] = ether_short
		if reason == "available":
			reason = "ether"
	if not unlocked:
		reason = "not_unlocked"
		missing["unlock"] = true
	return {"id": id, "kind": kind, "available": reason == "available", "missing": missing,
		"reason": reason, "price": price.duplicate(true)}


static func _unlocked_modes(game: Variant) -> Array:
	var result: Array = []
	if game is Node and game.has_method("game_now"):
		for key in ["spring", "bench", "retort", "letters", "atlas"]:
			if game._engine._mode_unlocked(key):
				result.append(key)
	return result


static func extract_next_goals(game: Variant, profile: Variant = null) -> Array:
	return next_goals(game, profile)


static func run(game: Variant, profile: Variant, seed_value: int, scenario: Variant,
		clock: Variant = null, segment_executor: Variant = null, progress_callback: Callable = Callable()) -> Dictionary:
	var parsed: Dictionary
	if scenario is String:
		parsed = parse_file(String(scenario))
	else:
		parsed = parse(scenario)
	if not bool(parsed.get("valid", false)):
		return {"scenario": SCHEMA, "schema": SCHEMA, "seed": seed_value,
			"profile": _profile_metadata(profile), "segments": [], "verdict": "invalid",
			"errors": _array_copy(parsed.get("errors", []))}
	var before_all: Dictionary = snapshot(game, clock)
	var planned_seconds := 0.0
	for planned in parsed.segments:
		planned_seconds += float(planned.seconds)
	_publish_progress(game, clock, parsed, 0, 0.0, planned_seconds, "scenario started", progress_callback)
	var segment_results: Array = []
	var session_counters: Dictionary = _new_session_counters()
	var session_events: Array = []
	var session_stalls: Array = []
	var segment_index := 0
	for raw_segment in parsed["segments"]:
		var segment: Dictionary = raw_segment
		var before: Dictionary = snapshot(game, clock)
		var execution_context := {
			"game": game,
			"profile": profile,
			"seed": seed_value,
			"scenario": parsed.duplicate(true),
			"segment": segment.duplicate(true),
			"segment_index": segment_index,
			"clock": clock,
			"before": before.duplicate(true),
			"progress": func(event): _publish_progress(game, clock, parsed, segment_index,
				float(before.clock.simulated_real_seconds) - float(before_all.clock.simulated_real_seconds),
				planned_seconds, event, progress_callback),
		}
		var raw_execution: Variant = []
		if segment_executor is Callable:
			var callable: Callable = segment_executor
			if callable.is_valid():
				raw_execution = callable.call(execution_context)
		elif segment_executor is Object and (segment_executor as Object).has_method("execute_segment"):
			raw_execution = (segment_executor as Object).call("execute_segment", execution_context)
		elif String(segment.get("kind", "")) == "offline" and _active_policy_ready(game, clock):
			raw_execution = offline_segment(execution_context)
		elif String(segment.get("policy", "")) == ACTIVE_POLICY \
				or (segment_executor == null and String(segment.get("kind", "")) == "active" \
				and _active_policy_ready(game, clock)):
			raw_execution = session_balanced(execution_context)
		var execution: Dictionary = _normalize_segment_execution(raw_execution)
		var events: Array = _array_copy(execution.get("events", []))
		_accumulate_session_counters(session_counters, _dict_copy(execution.get("counters", {})))
		for event in events:
			session_events.append(_copy_value(event))
		for stall in _array_copy(execution.get("stalls", [])):
			session_stalls.append(_copy_value(stall))
		var after: Dictionary = snapshot(game, clock)
		var goals: Array = next_goals(game, profile)
		var blocked_goals: Array = []
		for goal_value in goals:
			var goal: Dictionary = goal_value
			if not bool(goal.get("available", false)):
				blocked_goals.append(goal.duplicate(true))
		var clock_before := _dict_copy(before.get("clock", {}))
		var clock_after := _dict_copy(after.get("clock", {}))
		segment_results.append({
			"kind": String(segment["kind"]),
			"seconds": float(segment["seconds"]),
			"before": before,
			"after": after,
			"delta": delta(before, after),
			"clock_delta": deep_delta(clock_before, clock_after),
			"events": events,
			"counters": _dict_copy(execution.get("counters", {})),
			"stalls": _array_copy(execution.get("stalls", [])),
			"ledger": _dict_copy(execution.get("ledger", {})),
			"policy": String(execution.get("policy", "")),
			"reason": String(execution.get("reason", "")),
			"blocked_goals": blocked_goals,
			"available_goals": goals,
			"offline_granted": _dict_copy(execution.get("offline_granted", {})),
			"offline_spent": _dict_copy(execution.get("offline_spent", {})),
			"production": _dict_copy(execution.get("production", {})),
			"new_elements": _array_difference(after.local_discovered_ids, before.local_discovered_ids),
			"new_unlocks": _array_difference(after.unlocked_modes, before.unlocked_modes),
		})
		segment_index += 1
		_publish_progress(game, clock, parsed, segment_index,
			float(after.clock.simulated_real_seconds) - float(before_all.clock.simulated_real_seconds),
			planned_seconds, "segment complete", progress_callback)
	var after_all: Dictionary = snapshot(game, clock)
	var available_goals: Array = next_goals(game, profile)
	var blocked_all: Array = []
	for goal_value in available_goals:
		var goal: Dictionary = goal_value
		if not bool(goal.get("available", false)):
			blocked_all.append(goal.duplicate(true))
	var errors: Array = []
	var complete := _active_policy_ready(game, clock)
	for result in segment_results:
		var actual := float(result.clock_delta.get(String(result.kind) + "_seconds", 0.0))
		if absf(actual - float(result.seconds)) > TIME_EPSILON:
			complete = false
		if not result.ledger.get("unexplained_resources", []).is_empty():
			errors.append("unexplained_resources")
		if String(result.kind) == "offline" and result.production.get("saved", true) == false:
			errors.append("offline_checkpoint_failed")
	return {
		"scenario": SCHEMA,
		"schema": SCHEMA,
		"scenario_name": String(parsed.get("name", "custom")),
		"definition": {"scenario": SCHEMA, "segments": _array_copy(parsed.segments)},
		"seed": seed_value,
		"runner_commit": "working-tree",
		"catalog_hash": _catalog_hash(game),
		"item_names": _item_names(game),
		"scope": {"policy": "Deterministic recipe-aware strategy, not an average human forecast",
			"sigils": "Four local fixture offers; no server catalog or chromatic generation",
			"time": "Virtual elapsed active/offline time; player_action_seconds counts modeled direct actions"},
		"profile": _profile_metadata(profile),
		"segments": segment_results,
		"before": before_all,
		"after": after_all,
		"delta": delta(before_all, after_all),
		"available_goals": available_goals,
		"blocked_goals": blocked_all,
		"time": after_all.get("clock", {}).duplicate(true),
		"session": {
			"policy": ACTIVE_POLICY,
			"counters": session_counters.duplicate(true),
			"events": session_events.duplicate(true),
			"stalls": session_stalls.duplicate(true),
		},
		"errors": errors,
		"verdict": "fail" if not errors.is_empty() else ("pass" if complete else "incomplete"),
		"state": "complete" if complete and errors.is_empty() else "incomplete",
	}


static func offline_segment(context: Dictionary) -> Dictionary:
	var game: Variant = context.game
	var clock: Variant = context.clock
	var seconds := float(context.segment.seconds)
	var ledger: Variant = load("res://tests/progression_ledger.gd").new()
	ledger.start(game)
	var previous: Variant = clock.ledger
	clock.ledger = ledger
	var start: float = clock.now()
	var ready_before := _ready_retort_slots(game, start)
	clock.replay_offline(start, start + seconds)
	var stats: Dictionary = game._saves._return_workshop.duplicate(true) if seconds > 0.0 else {}
	var retort: Dictionary = stats.get("retort", {})
	var outputs := {}
	var stalls: Array = []
	for line_id in stats.get("lines", {}):
		var info: Dictionary = stats.lines[line_id]
		for id in info.get("outputs", {}):
			outputs[id] = int(outputs.get(id, 0)) + int(info.outputs[id])
		var status := String(info.get("status", ""))
		if status.begins_with("waiting_"):
			stalls.append({"kind": "stall", "phase": "workshop", "reason": status.trim_prefix("waiting_"), "line": line_id})
		elif int(info.get("stages", 0)) >= game._workshop.offline_stage_limit() and int(info.get("queue_count", 0)) > 0:
			stalls.append({"kind": "stall", "phase": "workshop", "reason": "autonomy", "line": line_id})
	if float(stats.get("skipped_seconds", 0.0)) > TIME_EPSILON:
		stalls.append({"kind": "stall", "phase": "offline", "reason": "offline_cap"})
	stats["queued_outputs"] = outputs
	stats["retort_matured"] = maxi(0, _ready_retort_slots(game, clock.now()) - ready_before) + int(retort.get("collected", 0))
	stats["retort_collected"] = int(retort.get("collected", 0))
	stats["spring_window_seconds"] = float(load("res://game/data/spring_balance.gd").offline_windows(game.balance)[int(game._engine.spring_levels.get("offline", 0))])
	stats["offline_cap_seconds"] = float(game.balance.get_value("offline.cap_sec"))
	var granted := {"ether": int(stats.get("ether_gained", 0)), "spring_items": int(stats.get("spring_items", 0)),
		"inventory": {}, "essences": retort.get("essences", {}).duplicate(true)}
	var spent := {"ether": int(stats.get("ether_spent", 0)), "inventory": {}}
	for event in ledger.report().events:
		for id in event.deltas.get("inventory", {}):
			var amount := int(event.deltas.inventory[id])
			if amount > 0:
				granted.inventory[id] = int(granted.inventory.get(id, 0)) + amount
			elif amount < 0:
				spent.inventory[id] = int(spent.inventory.get(id, 0)) - amount
	clock.ledger = previous
	return {"policy": "production_offline", "events": [{"kind": "offline_replay", "at": clock.now(),
		"seconds": seconds, "ether_earned": granted.ether, "ether_spent": spent.ether}],
		"stalls": stalls, "ledger": ledger.report(), "production": stats,
		"offline_granted": granted, "offline_spent": spent,
		"reason": "offline_cap" if not stalls.is_empty() else "", "counters": {"offline_simulated_seconds": seconds}}


static func _ready_retort_slots(game: Variant, now: float) -> int:
	var result := 0
	for slot in game._retort._retort_slots:
		if not String(slot.get("sub", "")).is_empty() and float(slot.get("started", 0)) + float(slot.get("dur", 0)) <= now:
			result += 1
	return result


static func _catalog_hash(game: Variant) -> String:
	var ids: Array = _dict_copy(_member(game, "ITEMS", {})).keys()
	ids.sort()
	var recipes: Array = []
	for recipe in _array_copy(_member(game, "RECIPES", [])):
		recipes.append("%s=%s" % [_pair_key(game, String(recipe.a), String(recipe.b)), recipe.out])
	recipes.sort()
	return JSON.stringify([ids, recipes]).sha256_text()


static func _item_names(game: Variant) -> Dictionary:
	var result := {}
	var items := _dict_copy(_member(game, "ITEMS", {}))
	for id in items:
		result[id] = String(items[id].get("name", id))
	return result


static func _publish_progress(game: Variant, clock: Variant, parsed: Dictionary, index: int,
		completed_seconds: float, total_seconds: float, event: String, callback: Callable) -> void:
	if not callback.is_valid():
		return
	var snap := snapshot(game, clock)
	var elapsed := float(snap.clock.get("simulated_real_seconds", completed_seconds))
	var fraction := clampf(elapsed / total_seconds, 0.0, 1.0) if total_seconds > 0.0 else 1.0
	var status := {"schema": 1, "mode": "scenario", "phase": "scenario/%d/%d" % [mini(index + 1, parsed.segments.size()), parsed.segments.size()],
		"percent": fraction * 100.0, "phase_percent": fraction * 100.0,
		"completed": index, "total": parsed.segments.size(), "last_event": event,
		"last_discovered": event, "local_discovered_count": snap.local_discovered_count,
		"simulated_seconds": elapsed, "state": "running" if index < parsed.segments.size() else "complete"}
	callback.call(status)
	print("[PROGRESS] " + JSON.stringify(status))


static func _new_session_counters() -> Dictionary:
	return {
		"player_action_seconds": 0.0,
		"active_simulated_seconds": 0.0,
		"discoveries": 0,
		"brews": 0,
		"upgrade_purchases": 0,
		"contract_claims": 0,
		"achievement_updates": 0,
		"stalls": 0,
		"personal_experiment_attempts": 0,
		"personal_experiment_successes": 0,
		"personal_experiment_failures": 0,
		"personal_experiment_targets_allocated": 0,
		"personal_experiment_world_targets": 0,
		"personal_experiment_llm_targets": 0,
		"personal_experiment_completions": 0,
	}


static func _accumulate_session_counters(target: Dictionary, source: Dictionary) -> void:
	for key in ["player_action_seconds", "active_simulated_seconds"]:
		target[key] = float(target.get(key, 0.0)) + float(source.get(key, 0.0))
	for key in ["discoveries", "brews", "upgrade_purchases", "contract_claims", "achievement_updates", "stalls",
			"personal_experiment_attempts", "personal_experiment_successes", "personal_experiment_failures",
			"personal_experiment_targets_allocated", "personal_experiment_world_targets",
			"personal_experiment_llm_targets", "personal_experiment_completions"]:
		target[key] = int(target.get(key, 0)) + int(source.get(key, 0))


static func _normalize_segment_execution(raw_execution: Variant) -> Dictionary:
	if raw_execution is Dictionary:
		var result: Dictionary = (raw_execution as Dictionary).duplicate(true)
		result["events"] = _array_copy(result.get("events", []))
		result["counters"] = _dict_copy(result.get("counters", {}))
		result["stalls"] = _array_copy(result.get("stalls", []))
		result["ledger"] = _dict_copy(result.get("ledger", {}))
		return result
	return {"events": _array_copy(raw_execution), "counters": {}, "stalls": [], "ledger": {}}


static func session_balanced(context: Dictionary) -> Dictionary:
	var game: Variant = context.get("game", null)
	var profile: Variant = context.get("profile", null)
	var segment: Dictionary = _dict_copy(context.get("segment", {}))
	var clock: Variant = context.get("clock", null)
	var events: Array = []
	var stalls: Array = []
	var seconds: float = maxf(0.0, float(segment.get("seconds", 0.0)))
	var counters: Dictionary = _new_session_counters()
	if String(segment.get("kind", "")) != "active":
		return _session_stall_result("unsupported_segment_kind", "active", null, events, stalls, counters)
	if not _active_policy_ready(game, clock):
		return _session_stall_result("production_context_missing", "active", clock, events, stalls, counters)

	var ledger_script: Script = load("res://tests/progression_ledger.gd")
	var strategy_script: Script = load("res://tests/progression_strategy.gd")
	if ledger_script == null or strategy_script == null:
		return _session_stall_result("production_strategy_unavailable", "production", clock, events, stalls, counters)
	var ledger: Variant = ledger_script.new()
	ledger.start(game)
	var previous_ledger: Variant = _member(clock, "ledger", null)
	clock.set("ledger", ledger)
	var start_active := float(_member(clock, "active_seconds", 0.0))
	var start_player := float(_member(clock, "active_player_seconds", 0.0))
	var action_seconds := maxf(0.0, float(_profile_value(profile, "player.action_seconds", ACTION_SECONDS)))
	var targets := _session_targets(game, segment)
	var policy_reason := _run_personal_experiment_outcomes(game, profile, segment, clock, ledger,
		strategy_script, action_seconds, start_active + seconds, events, stalls)
	var initial_rewards := _settle_progression_rewards(game, profile, clock, ledger, events, start_active + seconds)
	if not bool(initial_rewards.get("ok", false)):
		policy_reason = "active_budget_before_contract_claim"
		_record_session_stall(stalls, events, policy_reason, "contracts", clock)
	while _active_elapsed(clock, start_active) + TIME_EPSILON < seconds and policy_reason.is_empty():
		var ready_rewards := _settle_progression_rewards(game, profile, clock, ledger, events, start_active + seconds)
		if not bool(ready_rewards.get("ok", false)):
			policy_reason = "active_budget_before_contract_claim"
			_record_session_stall(stalls, events, policy_reason, "contracts", clock)
			break
		var frontier: Dictionary = strategy_script.next_frontier(game, targets)
		if frontier.is_empty():
			policy_reason = "graph_no_reachable_frontier"
			_record_session_stall(stalls, events, policy_reason, "discovery", clock)
			break
		if not strategy_script.ensure_inputs(game, frontier, clock, ledger, start_active + seconds):
			policy_reason = _strategy_reason(strategy_script, "ingredients")
			_record_session_stall(stalls, events, policy_reason, "inputs", clock)
			break
		if _active_elapsed(clock, start_active) + TIME_EPSILON >= seconds:
			policy_reason = "active_budget_exhausted"
			_record_session_stall(stalls, events, policy_reason, "active", clock)
			break
		var known: bool = game._engine.known_recipes.has(String(frontier.get("key", "")))
		var cost: int = _frontier_cost(game, profile, frontier, known)
		var wait_seconds: float = _ether_wait_seconds(game, cost)
		if wait_seconds == INF:
			strategy_script.wait_ether(game, cost, clock, start_active + seconds)
			policy_reason = _strategy_reason(strategy_script, "ether")
			_record_session_stall(stalls, events, policy_reason, "ether", clock)
			break
		if _remaining_active_seconds(seconds, start_active, clock) + TIME_EPSILON < wait_seconds:
			policy_reason = "active_budget_before_ether"
			_record_session_stall(stalls, events, policy_reason, "ether", clock,
				{"required_seconds": wait_seconds})
			_advance_active_remaining(clock, seconds, start_active)
			break
		if not strategy_script.wait_ether(game, cost, clock, start_active + seconds):
			policy_reason = _strategy_reason(strategy_script, "ether")
			_record_session_stall(stalls, events, policy_reason, "ether", clock)
			break

		if _remaining_active_seconds(seconds, start_active, clock) + TIME_EPSILON < action_seconds:
			policy_reason = "active_budget_before_action"
			_record_session_stall(stalls, events, policy_reason, "action", clock,
				{"required_seconds": action_seconds})
			_advance_active_remaining(clock, seconds, start_active)
			break
		if action_seconds > TIME_EPSILON:
			clock.call("advance_active", action_seconds)
		clock.set("active_player_seconds", float(_member(clock, "active_player_seconds", 0.0)) + action_seconds)
		var operation_wait: float = _frontier_wait_seconds(game, frontier, known)
		if _remaining_active_seconds(seconds, start_active, clock) + TIME_EPSILON < operation_wait:
			policy_reason = "active_budget_before_cooldown" if not known else "active_budget_before_brew"
			_record_session_stall(stalls, events, policy_reason, "cooldown" if not known else "brew", clock,
				{"required_seconds": operation_wait})
			_advance_active_remaining(clock, seconds, start_active)
			break
		if operation_wait > TIME_EPSILON:
			clock.call("advance_active", operation_wait)
		var output := String(frontier.get("out", ""))
		if not strategy_script.discover_and_brew(game, frontier, ledger):
			policy_reason = _strategy_reason(strategy_script, "production")
			_record_session_stall(stalls, events, policy_reason, "production", clock)
			break
		var action_kind := "brew" if known else "discovery"
		events.append({"kind": action_kind, "operation": "discover_and_brew", "output": output,
			"pair": String(frontier.get("key", "")), "at": _clock_now(clock),
			"player_action_seconds": action_seconds})
		_purchase_affordable_upgrades(game, profile, ledger, events, clock)
		_settle_ready_contracts(game, profile, clock, ledger, events, start_active + seconds)
		if context.get("progress") is Callable:
			context.progress.call(output)

	if _active_elapsed(clock, start_active) + TIME_EPSILON < seconds:
		_advance_active_remaining(clock, seconds, start_active)
	var ledger_report: Dictionary = ledger.report()
	var ledger_counters: Dictionary = _dict_copy(ledger_report.get("counters", {}))
	counters["player_action_seconds"] = float(_member(clock, "active_player_seconds", 0.0)) - start_player
	counters["active_simulated_seconds"] = _active_elapsed(clock, start_active)
	counters["discoveries"] = int(ledger_counters.get("discoveries", 0))
	counters["brews"] = int(ledger_counters.get("brews", 0))
	counters["upgrade_purchases"] = int(ledger_counters.get("upgrade_purchases", 0))
	counters["contract_claims"] = int(ledger_counters.get("contract_claims", 0))
	counters["achievement_updates"] = int(ledger_counters.get("achievement_updates", 0))
	counters["personal_experiment_attempts"] = int(ledger_counters.get("personal_experiment_attempts", 0))
	counters["personal_experiment_successes"] = int(ledger_counters.get("personal_experiment_successes", 0))
	counters["personal_experiment_failures"] = int(ledger_counters.get("personal_experiment_failures", 0))
	counters["personal_experiment_targets_allocated"] = int(ledger_counters.get("personal_experiment_targets_allocated", 0))
	counters["personal_experiment_world_targets"] = int(ledger_counters.get("personal_experiment_world_targets", 0))
	counters["personal_experiment_llm_targets"] = int(ledger_counters.get("personal_experiment_llm_targets", 0))
	counters["personal_experiment_completions"] = int(ledger_counters.get("personal_experiment_completions", 0))
	counters["stalls"] = stalls.size()
	clock.set("ledger", previous_ledger)
	return {"policy": ACTIVE_POLICY, "events": events, "stalls": stalls, "counters": counters,
		"ledger": ledger_report, "reason": policy_reason}


static func _run_personal_experiment_outcomes(game: Variant, profile: Variant, segment: Dictionary,
		clock: Variant, ledger: Variant, strategy_script: Script, action_seconds: float,
		active_deadline: float, events: Array, stalls: Array) -> String:
	var engine: Variant = _member(game, "_engine", null)
	var cooldown_seconds := float(_profile_value(profile, "discovery.cooldown_sec", 1.0))
	for raw_outcome in _array_copy(segment.get("personal_experiment_outcomes", [])):
		if not raw_outcome is Dictionary:
			continue
		var now := _clock_now(clock)
		var cooldown := maxf(0.0, float(_member(engine, "_experiment_last_at", 0.0)) + cooldown_seconds - now)
		var required := cooldown + action_seconds
		if float(_member(clock, "active_seconds", 0.0)) + required > active_deadline + TIME_EPSILON:
			clock.call("advance_active", maxf(0.0, active_deadline - float(_member(clock, "active_seconds", 0.0))))
			_record_session_stall(stalls, events, "active_budget_before_personal_experiment",
				"personal_experiment", clock, {"required_seconds": required})
			return "active_budget_before_personal_experiment"
		if cooldown > TIME_EPSILON:
			clock.call("advance_active", cooldown)
		if action_seconds > TIME_EPSILON:
			clock.call("advance_active", action_seconds)
		clock.set("active_player_seconds", float(_member(clock, "active_player_seconds", 0.0)) + action_seconds)
		var outcome: Dictionary = raw_outcome
		strategy_script.call("apply_experiment_outcome", game, outcome, ledger)
		if String(strategy_script.last_reason) == "duplicate":
			continue
		engine.set("_experiment_last_at", _clock_now(clock))
		var ledger_events: Array = ledger.report().get("events", [])
		if not ledger_events.is_empty():
			var latest: Variant = ledger_events[ledger_events.size() - 1]
			if latest is Dictionary and String((latest as Dictionary).get("kind", "")) == "personal_experiment":
				events.append((latest as Dictionary).duplicate(true))
	return ""


static func _settle_progression_rewards(game: Variant, profile: Variant, clock: Variant, ledger: Variant,
		events: Array, active_deadline: float) -> Dictionary:
	var result := _settle_ready_contracts(game, profile, clock, ledger, events, active_deadline)
	return {"ok": bool(result.get("ok", false)), "contract_claims": int(result.get("claims", 0)),
		"achievement_updates": 0}


static func _settle_ready_contracts(game: Variant, profile: Variant, clock: Variant, ledger: Variant,
		events: Array, active_deadline: float) -> Dictionary:
	var contracts: Variant = _member(game, "_contracts", null)
	if not contracts is Object or not (contracts as Object).has_method("all_contracts"):
		return {"ok": true, "claims": 0}
	var claims := 0
	var action_seconds := maxf(0.0, float(_profile_value(profile, "player.action_seconds", ACTION_SECONDS)))
	var now := Time.get_datetime_dict_from_unix_time(int(_clock_now(clock)))
	var now_unix := int(_clock_now(clock))
	var contracts_list: Array = _array_copy((contracts as Object).call("all_contracts", now))
	for raw_contract in contracts_list:
		if not raw_contract is Dictionary:
			continue
		var contract: Dictionary = raw_contract
		var id := String(contract.get("id", ""))
		if id.is_empty() or not (contracts as Object).has_method("is_ready") or not bool((contracts as Object).call("is_ready", id, now)):
			continue
		if float(_member(clock, "active_seconds", 0.0)) + action_seconds > active_deadline + TIME_EPSILON:
			return {"ok": false, "claims": claims}
		if action_seconds > TIME_EPSILON:
			clock.call("advance_active", action_seconds)
		clock.set("active_player_seconds", float(_member(clock, "active_player_seconds", 0.0)) + action_seconds)
		var result: Variant = ledger.perform(game, "contract_claim:" + id,
			func(): return (contracts as Object).call("claim", id, now, now_unix))
		if not result is Dictionary or not bool((result as Dictionary).get("ok", false)):
			continue
		ledger.increment_counter("contract_claims")
		claims += 1
		events.append({"kind": "contract_claim", "id": id, "at": _clock_now(clock),
			"player_action_seconds": action_seconds, "materials": _dict_copy((result as Dictionary).get("materials", {}))})
	return {"ok": true, "claims": claims}


static func _session_stall_result(reason: String, phase: String, clock: Variant, events: Array,
		stalls: Array, counters: Dictionary) -> Dictionary:
	_record_session_stall(stalls, events, reason, phase, clock)
	counters["stalls"] = stalls.size()
	return {"policy": ACTIVE_POLICY, "events": events, "stalls": stalls, "counters": counters,
		"ledger": {}, "reason": reason}


static func _active_policy_ready(game: Variant, clock: Variant) -> bool:
	return game is Object and clock is Object and (game as Object).has_method("game_now") \
		and (clock as Object).has_method("advance_active") and (clock as Object).has_method("snapshot") \
		and _member(game, "_engine", null) != null and _member(game, "_online", null) != null


static func _session_targets(game: Variant, segment: Dictionary) -> Dictionary:
	var raw_targets: Variant = segment.get("targets", segment.get("target_ids", null))
	var targets: Dictionary = {}
	if raw_targets is Dictionary:
		for raw_id in raw_targets:
			targets[String(raw_id)] = bool(raw_targets[raw_id])
	elif raw_targets is Array:
		for raw_id in raw_targets:
			targets[String(raw_id)] = true
	else:
		var items := _dict_copy(_member(game, "ITEMS", {}))
		for raw_id in items:
			targets[String(raw_id)] = true
	return targets


static func _frontier_cost(game: Variant, profile: Variant, frontier: Dictionary, known: bool) -> int:
	if known:
		var engine: Variant = _member(game, "_engine", null)
		if engine is Object and (engine as Object).has_method("_pair_cost"):
			return int(engine.call("_pair_cost", String(frontier.get("a", "")), String(frontier.get("b", ""))))
		return 0
	return int(_profile_value(profile, "discovery.cost", 12))


static func _frontier_wait_seconds(game: Variant, frontier: Dictionary, known: bool) -> float:
	var engine: Variant = _member(game, "_engine", null)
	if not engine is Object:
		return 0.0
	if known:
		return maxf(0.0, float(_call(engine, "_brew_time", 0.0)))
	return maxf(0.0, float(_call(engine, "_experiment_cooldown_remaining", 0.0)))


static func _ether_wait_seconds(game: Variant, cost: int) -> float:
	var engine: Variant = _member(game, "_engine", null)
	if not engine is Object:
		return INF
	var available := int(_call(engine, "_available_ether", int(_member(engine, "ether", 0)) + int(_member(engine, "ether_overflow", 0))))
	if available >= cost:
		return 0.0
	var rate := float(_call(engine, "_ether_rate", 0.0))
	if rate <= 0.0:
		return INF
	return ceil(float(cost - available) / rate) + 1.0


static func _remaining_active_seconds(seconds: float, start_active: float, clock: Variant) -> float:
	return maxf(0.0, seconds - _active_elapsed(clock, start_active))


static func _active_elapsed(clock: Variant, start_active: float) -> float:
	return maxf(0.0, float(_member(clock, "active_seconds", 0.0)) - start_active)


static func _advance_active_remaining(clock: Variant, seconds: float, start_active: float) -> void:
	var remaining := _remaining_active_seconds(seconds, start_active, clock)
	if remaining > TIME_EPSILON:
		clock.call("advance_active", remaining)


static func _clock_now(clock: Variant) -> float:
	return float(_call(clock, "now", 0.0))


static func _strategy_reason(strategy_script: Script, fallback: String) -> String:
	var reason := String(strategy_script.get("last_reason"))
	return fallback if reason.is_empty() else reason


static func _record_session_stall(stalls: Array, events: Array, reason: String, phase: String,
		clock: Variant, details: Dictionary = {}) -> void:
	var entry := {"kind": "stall", "phase": phase, "reason": reason,
		"at": _clock_now(clock) if clock != null else 0.0}
	for key in details:
		entry[key] = _copy_value(details[key])
	stalls.append(entry.duplicate(true))
	events.append(entry.duplicate(true))


static func _purchase_affordable_upgrades(game: Variant, profile: Variant, ledger: Variant, events: Array,
		clock: Variant) -> int:
	var purchased := 0
	var engine: Variant = _member(game, "_engine", null)
	if not engine is Object:
		return 0
	var upgrade_defs: Array = _profile_value(profile, "upgrades.items", [])
	if upgrade_defs.is_empty():
		var balance: Variant = _member(game, "balance", null)
		if balance is Object and (balance as Object).has_method("get_value"):
			upgrade_defs = _array_copy(balance.call("get_value", "upgrades.items", []))
	if engine.has_method("_buy_upgrade"):
		for raw_upgrade in upgrade_defs:
			if not raw_upgrade is Dictionary:
				continue
			var upgrade: Dictionary = raw_upgrade
			var id := String(upgrade.get("id", ""))
			var maximum := int(upgrade.get("max", 0))
			if id.is_empty() or maximum <= 0:
				continue
			while int(engine.call("_up_lvl", id)) < maximum:
				var level := int(engine.call("_up_lvl", id))
				if engine.has_method("_up_unlocked") and not bool(engine.call("_up_unlocked", id)):
					break
				var cost := int(engine.call("_up_cost_at", id, level)) if engine.has_method("_up_cost_at") else int(upgrade.get("base", 0))
				if _available_ether(game) < cost:
					break
				var result: Variant = ledger.perform(game, "ether_purchase:" + id,
					func(): return engine.call("_buy_upgrade", id))
				if not bool(result):
					break
				purchased += 1
				ledger.increment_counter("upgrade_purchases")
				events.append({"kind": "upgrade", "upgrade": id, "level": int(engine.call("_up_lvl", id)),
					"at": _clock_now(clock)})
	if engine.has_method("spring_purchase") and engine.get("spring_levels") is Dictionary:
		var balance_for_spring: Variant = _member(game, "balance", null)
		if balance_for_spring is Object:
			for axis in ["speed", "volume", "sources", "offline"]:
				var spring_script: Script = load("res://game/data/spring_balance.gd")
				var table: Array = spring_script.axis_table(balance_for_spring, axis) if spring_script != null else []
				while int(engine.spring_levels.get(axis, 0)) < table.size():
					var level := int(engine.spring_levels.get(axis, 0))
					var price: Dictionary = table[level] if table[level] is Dictionary else {}
					if not _price_affordable(game, price):
						break
					var spring_result: Variant = ledger.perform(game, "spring_purchase:" + axis,
						func(): return engine.call("spring_purchase", axis))
					if not spring_result is Dictionary or not bool((spring_result as Dictionary).get("ok", false)):
						break
					purchased += 1
					ledger.increment_counter("upgrade_purchases")
					events.append({"kind": "upgrade", "upgrade": "spring/%s/%d" % [axis, level + 1],
						"level": int(engine.spring_levels.get(axis, 0)), "at": _clock_now(clock)})
	var workshop: Variant = _member(game, "_workshop", null)
	if workshop is Object and bool(_member(workshop, "unlocked", false)):
		if workshop.has_method("_ranks") and workshop.has_method("buy_rank"):
			var rank := int(_member(workshop, "rank", 0))
			var ranks: Array = workshop.call("_ranks")
			if rank + 1 < ranks.size() and ranks[rank + 1] is Dictionary:
				var rank_price: Dictionary = ranks[rank + 1]
				if int(_member(workshop, "xp", 0)) >= int(rank_price.get("xp", 0)) and _price_affordable(game, rank_price):
					var rank_result: Variant = ledger.perform(game, "workshop_rank",
						func(): return workshop.call("buy_rank", rank + 1))
					if rank_result is Dictionary and bool((rank_result as Dictionary).get("ok", false)):
						purchased += 1
						ledger.increment_counter("upgrade_purchases")
						events.append({"kind": "upgrade", "upgrade": "workshop/rank", "level": int(workshop.get("rank")),
							"at": _clock_now(clock)})
		if workshop.has_method("_autonomy") and workshop.has_method("buy_autonomy"):
			var autonomy := int(_member(workshop, "autonomy_level", 0))
			var autonomy_table: Array = workshop.call("_autonomy")
			if autonomy + 1 < autonomy_table.size() and autonomy_table[autonomy + 1] is Dictionary:
				var autonomy_price: Dictionary = autonomy_table[autonomy + 1]
				if _price_affordable(game, autonomy_price):
					var autonomy_result: Variant = ledger.perform(game, "workshop_autonomy",
						func(): return workshop.call("buy_autonomy"))
					if autonomy_result is Dictionary and bool((autonomy_result as Dictionary).get("ok", false)):
						purchased += 1
						ledger.increment_counter("upgrade_purchases")
						events.append({"kind": "upgrade", "upgrade": "workshop/autonomy",
							"level": int(workshop.get("autonomy_level")), "at": _clock_now(clock)})
	return purchased


static func _price_affordable(game: Variant, price: Dictionary) -> bool:
	if _available_ether(game) < int(price.get("ether", 0)):
		return false
	var engine: Variant = _member(game, "_engine", null)
	var inventory := _dict_copy(_member(engine, "inventory", {}))
	for item in price.get("materials", {}):
		if int(inventory.get(item, 0)) < int(price.materials[item]):
			return false
	return true


static func _available_ether(game: Variant) -> int:
	var engine: Variant = _member(game, "_engine", null)
	return int(_call(engine, "_available_ether", int(_member(engine, "ether", 0)) + int(_member(engine, "ether_overflow", 0))))


static func _equipment_goal(id: String, kind: String, level: int, workshop: Variant, price: Dictionary, available_ether: int) -> Dictionary:
	var missing: Dictionary = {}
	var reason := "available"
	var rank := int(_member(workshop, "rank", 0))
	var unlocked := bool(_member(workshop, "unlocked", false))
	if not unlocked:
		reason = "not_unlocked"
		missing["workshop"] = true
	if int(price.get("ether", 0)) > available_ether:
		reason = "ether"
		missing["ether"] = int(price.get("ether", 0)) - available_ether
	var engine: Variant = _member(workshop, "g", null)
	var inventory := _dict_copy(_member(_member(engine, "_engine", null), "inventory", {}))
	for item in price.get("materials", {}):
		var shortage := int(price.materials[item]) - int(inventory.get(item, 0))
		if shortage > 0:
			reason = "ingredients"
			missing[String(item)] = shortage
	if workshop is Object and workshop.has_method("rank_availability"):
		var check: Dictionary = workshop.rank_availability(level) if kind == "workshop_rank" else workshop.autonomy_availability()
		if not check.get("ok", false):
			var code := String(check.get("code", "locked"))
			reason = {"materials": "ingredients", "xp": "mastery", "locked": "not_unlocked", "busy": "cooldown"}.get(code, code)
	return {"id": id, "kind": kind, "level": level, "available": reason == "available",
		"missing": missing, "reason": reason, "price": price.duplicate(true), "rank": rank}


static func _profile_metadata(profile: Variant) -> Dictionary:
	if profile == null:
		return {}
	if profile is Dictionary:
		return (profile as Dictionary).duplicate(true)
	if profile is Object and (profile as Object).has_method("metadata"):
		var metadata: Variant = profile.call("metadata")
		return metadata.duplicate(true) if metadata is Dictionary else {}
	return {}


static func _profile_value(profile: Variant, path: String, fallback: Variant) -> Variant:
	if profile == null:
		return _copy_value(fallback)
	if profile is Dictionary:
		var current: Variant = profile
		for part in path.split("."):
			if not current is Dictionary or not (current as Dictionary).has(part):
				return _copy_value(fallback)
			current = (current as Dictionary)[part]
		return _copy_value(current)
	if profile is Object and (profile as Object).has_method("get_value"):
		return _copy_value(profile.call("get_value", path, fallback))
	return _copy_value(fallback)


static func _pair_key(game: Variant, a: String, b: String) -> String:
	if game is Object and (game as Object).has_method("_pair_key"):
		return String(game.call("_pair_key", a, b))
	var pair := [a, b]
	pair.sort()
	return String(pair[0]) + "|" + String(pair[1])


static func _member(target: Variant, property: String, fallback: Variant) -> Variant:
	if target == null:
		return fallback
	if target is Dictionary:
		return (target as Dictionary).get(property, fallback)
	if target is Object:
		var value: Variant = (target as Object).get(property)
		return fallback if value == null else value
	return fallback


static func _call(target: Variant, method: String, fallback: Variant) -> Variant:
	if target is Object and (target as Object).has_method(method):
		return (target as Object).call(method)
	return fallback


static func _dict_copy(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _array_copy(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []


static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_bool_or_not_number(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL or not _is_number(value)


static func _zero_like(value: Variant) -> Variant:
	if _is_number(value):
		return 0.0 if typeof(value) == TYPE_FLOAT else 0
	if value is Dictionary:
		return {}
	if value is Array:
		return []
	return null


static func _empty_delta(value: Variant) -> bool:
	if value == null:
		return true
	if value is Dictionary or value is Array:
		return value.is_empty()
	if _is_number(value):
		return is_zero_approx(float(value))
	return false


static func _array_difference(source: Array, other: Array) -> Array:
	var remaining := other.duplicate(true)
	var difference: Array = []
	for value in source:
		var index := remaining.find(value)
		if index >= 0:
			remaining.remove_at(index)
		else:
			difference.append(_copy_value(value))
	return difference
