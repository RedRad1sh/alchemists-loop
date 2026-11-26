extends RefCounted
## Котёл не зависает без сервера, эксперимент не требует копии вещества.

static func run(g: Game) -> void:
	var engine_state := {}
	for key in ["inventory", "known_recipes", "known_recipe_defs", "_rejected_pairs", "ether", "ether_overflow", "attempts", "successes", "_experiment_pending_pair", "_experiment_count", "_experiment_day", "_experiment_last_at", "status_text"]:
		var value = g._engine.get(key)
		engine_state[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	var enabled := g._online._net_enabled
	var available := Net._available
	var requests := g._online._pending_requests.duplicate(true)
	var inflight := Net._inflight.duplicate(true)
	var queue := Net._queue.duplicate(true)
	var xp := g._workshop.xp
	var unlocked := g._workshop.unlocked
	var cauldron := g._pages._experiment_cauldron_items.duplicate()
	var target_state: Dictionary = g._online._target_state.duplicate(true)
	g._online._target_state = {}
	g._online._net_enabled = true
	Net._available = true
	g._online._pending_requests.clear()
	g._engine._experiment_pending_pair.clear()
	g._engine.ether = 200
	g._engine.ether_overflow = 0
	g._engine._experiment_count = 0
	g._engine._rejected_pairs.clear()
	g._engine._experiment_last_at = 0.0
	g._engine.inventory["fire"] = 10
	g._engine.inventory["water"] = 10
	var key := g._pair_key("fire", "water")
	g._engine.known_recipes.erase(key)
	g._engine.known_recipe_defs.erase(key)
	g._online._on_net_rejected_result({"ok": true, "rejected": [key]})
	var steam_before := int(g._engine.inventory.get("steam", 0))
	g._pages._experiment_cauldron_items = ["fire", "water"]
	g._pages._experiment_launch_pair()
	Selftest.check("experiment local recipe overrides server rejection", int(g._engine.inventory.get("steam", 0)) == steam_before + 1)
	g._engine._rejected_pairs.erase(key)
	g._engine.known_recipes.erase(key)
	g._engine._experiment_last_at = 0.0
	g._pages._experiment_cauldron_items = ["fire", "water"]
	g._pages._experiment_launch_pair()
	Selftest.check("experiment local completion stays visible", g._pages._experiment_status.text == g._engine.status_text)
	var connected := not Net.pair_result.is_connected(g._online._on_net_pair_result)
	if connected:
		Net.pair_result.connect(g._online._on_net_pair_result)
	for kind in ["brew-check", "discover"]:
		g._engine._experiment_last_at = 0.0
		g._engine.known_recipes.erase(g._pair_key("glass", "steam"))
		g._engine.inventory["glass"] = 5
		g._engine.inventory["steam"] = 5
		var before := g._engine._available_ether()
		var began := g._engine._begin_experiment("glass", "steam")
		Selftest.check("experiment timeout fixture starts " + kind, began)
		g._online._register_pending_pair("glass", "steam", true)
		Net._inflight = {"kind": kind, "pair_key": g._pair_key("glass", "steam")}
		Net._queue.clear()
		var disc_connected := not Net.discover_result.is_connected(g._online._on_net_discover_result)
		if disc_connected:
			Net.discover_result.connect(g._online._on_net_discover_result)
		Net._on_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
		Selftest.check("experiment timeout refunds and unlocks " + kind, began
			and g._engine.inventory["glass"] == 5 and g._engine.inventory["steam"] == 5
			and g._engine._available_ether() == before
			and g._engine._experiment_pending_pair.is_empty() and g._online._pending_requests.is_empty())
		if disc_connected:
			Net.discover_result.disconnect(g._online._on_net_discover_result)
	g._engine._experiment_last_at = 0.0
	Net._inflight = {"kind": "sentinel"}
	Net._queue.clear()
	g._pages._experiment_cauldron_items = ["glass", "steam"]
	g._pages._experiment_launch_pair()
	Selftest.check("experiment offline rejection releases cauldron", g._pages._experiment_cauldron_items.is_empty())
	Selftest.check("experiment offline attempt probes server recovery", Net._queue.any(func(req): return req.get("kind", "") == "ping"))
	Net._queue.clear()
	Net._inflight = {"kind": "ping"}
	Net._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"ok":true}'.to_utf8_buffer())
	Net._inflight = {"kind": "sentinel"}
	g._engine._experiment_last_at = 0.0
	g._pages._experiment_cauldron_items = ["glass", "steam"]
	g._pages._experiment_launch_pair()
	Selftest.check("experiment can restart after connection recovers", Net._available
		and g._engine._experiment_pending_pair == ["glass", "steam"]
		and Net._queue.any(func(req): return req.get("kind", "") == "brew-check"))
	Net._queue.clear()
	Net._inflight = {"kind": "brew-check", "pair_key": g._pair_key("glass", "steam")}
	Net._on_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	Net._queue.clear()
	Net._inflight.clear()
	g._engine._experiment_last_at = 0.0
	g._engine._begin_experiment("glass", "steam")
	g._online._register_pending_pair("glass", "steam", true)
	g._online._pending_requests[g._pair_key("glass", "steam")]["at"] = Time.get_ticks_msec() - g._online.PENDING_TTL_MSEC - 1
	g._online._tick_pending_experiment()
	Selftest.check("experiment tick releases expired live request", g._engine._experiment_pending_pair.is_empty() and g._online._pending_requests.is_empty())

	# Для эксперимента копия вещества не нужна: достаточно, что оно открыто.
	g._engine._experiment_last_at = 0.0
	g._engine.known_recipes.erase(g._pair_key("glass", "steam"))
	g._engine.inventory["glass"] = 0
	g._engine.inventory["steam"] = 0
	Selftest.check("experiment accepts known reagent without a copy", g._pages._experiment_can_take("glass")
		and g._pages._experiment_reagent_ids(false).has("glass"))
	Net._available = true
	Net._queue.clear()
	Net._inflight = {"kind": "sentinel"}
	g._pages._experiment_cauldron_items = ["glass", "steam"]
	g._pages._experiment_launch_pair()
	Selftest.check("experiment with zero stock reaches the world", g._engine._experiment_pending_pair == ["glass", "steam"]
		and Net._queue.any(func(req): return req.get("kind", "") == "brew-check"))
	g._engine._cancel_experiment("glass", "steam")
	g._online._pending_requests.clear()
	Net._queue.clear()
	Net._inflight.clear()

	# Админ-команда give: вещества выдаются вместе с рецептами их получения.
	if g._admin != null:
		var inv_before: Dictionary = g._engine.inventory.duplicate(true)
		var known_before: Dictionary = g._engine.known_recipes.duplicate(true)
		var defs_before: Dictionary = g._engine.known_recipe_defs.duplicate(true)
		g._engine.inventory.erase("brick")
		g._engine.known_recipes.clear()
		g._engine.known_recipe_defs.clear()
		g._admin._on_command("give brick 3")
		Selftest.check("admin give grants element with its recipe", int(g._engine.inventory.get("brick", 0)) == 3
			and g._workshop.known_target_recipe("brick"))
		g._admin._on_command("give layer 1 2")
		Selftest.check("admin give layer grants first layer", int(g._engine.inventory.get("steam", 0)) >= 2
			and g._workshop.known_target_recipe("steam"))
		g._engine.inventory = inv_before
		g._engine.known_recipes = known_before
		g._engine.known_recipe_defs = defs_before
	if connected:
		Net.pair_result.disconnect(g._online._on_net_pair_result)
	for name in engine_state:
		g._engine.set(name, engine_state[name])
	g._online._net_enabled = enabled
	g._online._pending_requests = requests
	Net._available = available
	Net._inflight = inflight
	Net._queue.assign(queue)
	g._workshop.xp = xp
	g._workshop.unlocked = unlocked
	g._pages._experiment_cauldron_items.assign(cauldron)
	g._pages._refresh_experiment_cauldron()
	g._online._target_state = target_state
