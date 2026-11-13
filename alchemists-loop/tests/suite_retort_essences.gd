extends RefCounted
class_name SuiteRetortEssences

static func _tier(id: String) -> int:
	var parts := id.split("-")
	return int(parts[1]) if parts.size() == 2 else 99

static func _write_save_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var err := file.get_error()
	file.close()
	return err == OK

static func run(g: Game) -> void:
	Selftest.check("essence fire base", g._retort.essence_of("fire") == "fire-0")
	var retort_hint := ""
	for mode in Modes.MODES:
		if String(mode.get("key", "")) == "retort":
			retort_hint = String(mode.get("hint", ""))
	Selftest.check("retort mode hint promises typed essences", retort_hint.contains("типизированные эссенции"))
	Selftest.check("mastery rank five points retort slots to cells axis",
		not g._hub._mastery_next_benefit(4).contains("четвёртый сосуд")
		and g._hub._mastery_next_benefit(4).contains("Ячейки"))
	Selftest.check("essence element from category", g._retort.essence_of("lava").begins_with("fire-")
		and g._retort.essence_of("ice").begins_with("water-") and g._retort.essence_of("steam").begins_with("air-"))
	Selftest.check("material clamped to common", _tier(g._retort.essence_of("crystal")) <= 2
		and _tier(g._retort.essence_of("gold")) <= 2)
	var rare_ok := true
	for m in RetortBalance.MATERIALS:
		if _tier(g._retort.essence_of(String(m))) >= 3:
			rare_ok = false
	Selftest.check("no rare essence from any upgrade material", rare_ok and RetortBalance.MATERIALS.size() == 9)
	Selftest.check("essence deterministic", g._retort.essence_of("sun") == g._retort.essence_of("sun"))

	var known_before: Dictionary = g._engine.known_recipes.duplicate(true)
	var layer_cache_before: Dictionary = g._engine._layer_cache.duplicate(true)
	var server_layers_before: Dictionary = g._online._server_layers.duplicate(true)
	for recipe in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(recipe["a"]), String(recipe["b"]))] = true
	g._engine._layer_cache.clear()
	g._online._server_layers.clear()
	var available := {}
	for raw_id in g.ITEMS:
		available[g._retort.essence_of(String(raw_id))] = true
	for element in ["fire", "water", "earth", "air"]:
		var inputs: Array = RetortBalance.BLEND_RECIPES[element]
		if available.has(inputs[0]) and available.has(inputs[1]):
			available["blend-" + element] = true
	var missing: Array = []
	var tables: Array = [RetortBalance.QUEUE, RetortBalance.OFFLINE, RetortBalance.SLOTS,
		RetortBalance.SPEED, RetortBalance.COMPLEXITY, RetortBalance.BLEND, RetortBalance.CAP, RetortBalance.EQUIP]
	for table in tables:
		for price in table:
			for id in price.get("essences", {}):
				if not available.has(id) and not missing.has(id):
					missing.append(id)
	g._engine.known_recipes = known_before
	g._engine._layer_cache = layer_cache_before
	g._online._server_layers = server_layers_before
	Selftest.check("all cube costs are reachable from local recipes", missing.is_empty())
	var saved_server_elements: Dictionary = g._online._server_elements.duplicate(true)
	var saved_server_layers: Dictionary = g._online._server_layers.duplicate(true)
	var server_slug := "__st_retort_server_fire"
	g._online._apply_server_element({"slug": server_slug, "name": "Серверный огонь", "category": "огонь", "layer": 5})
	var server_applied := g._retort.essence_of(server_slug) == "fire-3"
	var serialized_server := g._online._server_elements.duplicate(true)
	g._online._restore_server_elements(serialized_server)
	Selftest.check("server retort category survives registration and restore", server_applied
		and g._retort.essence_of(server_slug) == "fire-3")
	g._online._restore_server_elements(saved_server_elements)
	g._online._server_layers = saved_server_layers
	g._engine._layer_cache.erase(server_slug)

	# Task 7, Step 1: форма растёт от суммы уровней, материал — от глубоких осей.
	var sprite_a := {"queue": 0, "offline": 0, "slots": 0, "speed": 0, "complexity": 0, "blend": 0, "cap": 0, "equip": 0}
	Selftest.check("sprite stage 0 at start", RetortSprite.form_stage(sprite_a) == 0)
	var sprite_b := sprite_a.duplicate()
	sprite_b["queue"] = 6
	sprite_b["speed"] = 6
	sprite_b["offline"] = 6
	sprite_b["slots"] = 3
	Selftest.check("sprite stage grows", RetortSprite.form_stage(sprite_b) > RetortSprite.form_stage(sprite_a))
	Selftest.check("sprite material grows with depth", RetortSprite.material_tier({"complexity": 5, "blend": 3}) > RetortSprite.material_tier(sprite_a))

	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort._legacy_cap_bonus = 0
	g._retort._essence_add("fire-2", 3)
	Selftest.check("essence inv count", g._retort.essence_count("fire-2") == 3)
	Selftest.check("essence codex known", g._retort.essence_known("fire-2"))
	Selftest.check("essence unknown absent", not g._retort.essence_known("air-4"))
	Selftest.check("afford needs exact types", g._retort._essence_can_afford({"fire-2": 2})
		and not g._retort._essence_can_afford({"fire-2": 5}) and not g._retort._essence_can_afford({"water-2": 1}))
	g._retort._essence_spend({"fire-2": 2})
	Selftest.check("essence spend exact types", g._retort.essence_count("fire-2") == 1
		and g._retort.essence_known("fire-2"))

	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort.migrate_legacy_essences({"sun": "Солнце", "crystal": "Кристалл"})
	Selftest.check("migration codex", g._retort.essence_known(g._retort.essence_of("sun")))
	Selftest.check("migration inv", g._retort.essence_count(g._retort.essence_of("crystal")) == 1)
	Selftest.check("migration legacy cap", g._retort._legacy_cap_bonus == 2 * Game.RETORT_CAP_EACH)
	Selftest.check("cap bonus includes legacy", g._retort._essence_cap_bonus() >= 2 * Game.RETORT_CAP_EACH)

	# Настоящий JSON-roundtrip: три новых поля сохраняются, старый flat-словарь — нет.
	g._retort._essence_add("fire-2", 3)
	var frozen_before := g._saves._save_frozen
	g._saves._save_frozen = false
	var saved_ok := g._saves._save_game()
	var saved_text := FileAccess.get_file_as_string(g.SAVE_PATH)
	var parsed: Variant = JSON.parse_string(saved_text)
	var saved_data: Dictionary = parsed if parsed is Dictionary else {}
	Selftest.check("essence save fields replace legacy", saved_ok and saved_data.has("essence_inv")
		and saved_data.has("essence_codex") and saved_data.has("legacy_cap_bonus") and not saved_data.has("essences"))
	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort._legacy_cap_bonus = 0
	g._saves._load_game()
	Selftest.check("essence save roundtrip", g._retort.essence_count("fire-2") == 3
		and g._retort.essence_known(g._retort.essence_of("sun"))
		and g._retort._legacy_cap_bonus == 2 * Game.RETORT_CAP_EACH)

	# Сейв прежней версии: новых ключей нет, старый непустой словарь мигрирует при load.
	var legacy_data := saved_data.duplicate(true)
	legacy_data.erase("essence_inv")
	legacy_data.erase("essence_codex")
	legacy_data.erase("legacy_cap_bonus")
	legacy_data["essences"] = {"sun": "Солнце", "crystal": "Кристалл"}
	var legacy_written := _write_save_text(g.SAVE_PATH, JSON.stringify(legacy_data, "\t", true, true))
	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort._legacy_cap_bonus = 0
	g._saves._load_game()
	Selftest.check("save load migrates legacy essences", legacy_written
		and g._retort.essence_known(g._retort.essence_of("sun"))
		and g._retort.essence_count(g._retort.essence_of("crystal")) == 1
		and g._retort._legacy_cap_bonus == 2 * Game.RETORT_CAP_EACH)

	var cold_data := legacy_data.duplicate(true)
	cold_data["essences"] = {"sun": "Солнце"}
	cold_data["retort_slots"] = [{"sub": "sun", "name": "Солнце",
		"started": Time.get_unix_time_from_system(), "dur": 100000.0}]
	var cold_defs := {}
	var cold_keys: Array = []
	for recipe in g.RECIPES:
		var key := g._pair_key(String(recipe["a"]), String(recipe["b"]))
		cold_defs[key] = recipe.duplicate(true)
		cold_keys.append(key)
	cold_data["known_recipe_defs"] = cold_defs
	cold_data["known_recipes"] = cold_keys
	g._engine.known_recipes = {g._pair_key("fire", "water"): true, g._pair_key("earth", "fire"): true}
	g._engine._layer_cache.clear()
	var cold_written := _write_save_text(g.SAVE_PATH, JSON.stringify(cold_data, "\t", true, true))
	g._saves._load_game()
	Selftest.check("legacy retort migrates after recipe knowledge", cold_written
		and g._retort.essence_count("fire-2") == 1 and g._retort.essence_count("fire-4") == 0
		and String(g._retort._retort_slot(0).get("essence", "")) == "fire-2")

	# Возвращаем состояние roundtrip и проверяем реальную Перегонку, после чего
	# восстанавливаем мир из изолированного ST-файла для последующих сюитов.
	var restored := _write_save_text(g.SAVE_PATH, saved_text)
	g._saves._load_game()
	var inv_before: Dictionary = g._retort._essence_inv.duplicate(true)
	var codex_before: Dictionary = g._retort._essence_codex.duplicate(true)
	var legacy_before: int = g._retort._legacy_cap_bonus
	for raw_id in g.ITEMS:
		var id := String(raw_id)
		if not g._engine.inventory.has(id):
			g._engine.inventory[id] = 1
		if g._engine.inventory.size() >= Game.PRESTIGE_MIN:
			break
	g._hub._do_prestige()
	Selftest.check("prestige keeps essences", restored and g._retort.essence_known("fire-2")
		and g._retort._essence_inv == inv_before and g._retort._essence_codex == codex_before
		and g._retort._legacy_cap_bonus == legacy_before)
	_write_save_text(g.SAVE_PATH, saved_text)
	g._saves._load_game()

	# Не оставляем тестовый cap-бонус последующим сюитам.
	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort._legacy_cap_bonus = 0
	g._saves._save_game()
	g._saves._save_frozen = frozen_before

	# Task 3, Step 1: дистилляция v2.
	g._engine.mastery_rank = 0
	g._retort._cube_levels["complexity"] = 0 # max tier 1
	g._engine.inventory["sun"] = 1            # неизвестное/глубокое → tier 4
	Selftest.check("complexity gates high tier", not g._retort._retort_start(0, "sun"))
	g._retort._cube_levels["complexity"] = 4  # max tier 4
	g._engine.inventory["fire"] = 1
	Selftest.check("start base", g._retort._retort_start(0, "fire"))
	var ess := g._retort.essence_of("fire")
	var got := g._retort._retort_collect(0, Time.get_unix_time_from_system() + 9 * 3600)
	Selftest.check("collect yields typed essence", bool(got.get("ok", false))
		and String(got.get("essence", "")) == ess and g._retort.essence_count(ess) == 1
		and g._retort.essence_known(ess))
	g._retort._cube_levels["slots"] = 0
	Selftest.check("slots base 1", g._retort._retort_slots_open() == 1)
	g._retort._cube_levels["slots"] = 3
	Selftest.check("slots axis up to max", g._retort._retort_slots_open() == Game.RETORT_SLOT_MAX)
	var extended_id := "__st_retort_extended_fire"
	g.ITEMS[extended_id] = {"name": "Огненный механизм", "color": "#cc6633", "g": "fire",
		"d": "Мировое вещество для проверки дистилляции.", "category": "огонь"}
	g._online._server_layers[extended_id] = 6
	g._engine.inventory[extended_id] = 1
	g._retort._cube_levels["complexity"] = 5
	var extended_candidate := g._retort._retort_candidates().has(extended_id)
	var extended_started := g._retort._retort_start(0, extended_id)
	var extended_essence := g._retort.essence_of(extended_id)
	var extended_slot: Dictionary = g._retort._retort_slot(0)
	var extended_collect := g._retort._retort_collect(0,
		float(extended_slot.get("started", 0.0)) + float(extended_slot.get("dur", 0.0)))
	Selftest.check("extended substance is accepted by retort", not Modes.CATEGORY_OF.has(extended_id)
		and extended_candidate and extended_started
		and extended_essence == "fire-4" and String(extended_collect.get("essence", "")) == "fire-4"
		and g._retort.essence_count("fire-4") == 1)
	g._engine.inventory.erase(extended_id)
	g.ITEMS.erase(extended_id)
	g._online._server_layers.erase(extended_id)
	g._retort._essence_inv.erase("fire-4")
	g._retort._essence_codex.erase("fire-4")
	g._retort._retort_slots.clear()
	g._retort._cube_levels["complexity"] = 0
	g._retort._cube_levels["slots"] = 0
	g._saves._load_retort_slots_for_test([
		{"sub": "fire", "name": "Огонь", "essence": "fire-0", "started": 1.0, "dur": 1.0},
		{"sub": "water", "name": "Вода", "essence": "water-0", "started": 1.0, "dur": 1000000.0},
		{"sub": "earth", "name": "Земля", "essence": "earth-0", "started": 1.0, "dur": 1000000.0},
	])
	var occupied_collect: Dictionary = g._retort._retort_collect(0, 10.0)
	var occupied_cancel_water := g._retort._retort_cancel(1)
	var occupied_cancel_earth := g._retort._retort_cancel(2)
	Selftest.check("occupied migrated slots ignore slots gate", bool(occupied_collect.get("ok", false))
		and occupied_cancel_water and occupied_cancel_earth and not g._retort._retort_start(2, "fire", 10.0))
	g._retort._retort_slots.clear()

	# Task 4, Step 1: покупки за типизированные эссенции и sink капа.
	g._retort._essence_inv.clear()
	Selftest.check("no purchase without typed essences", not g._retort.cube_purchase("queue").get("ok", true))
	g._retort._essence_add("fire-0", 3); g._retort._essence_add("water-0", 3)
	Selftest.check("buy queue lvl1 spends essences", g._retort.cube_purchase("queue").get("ok", false)
		and g._retort._level("queue") == 1 and g._retort.essence_count("fire-0") == 0)
	var cap0: int = g._engine._max_ether()
	g._retort._essence_add("earth-2", 3); g._retort._essence_add("water-2", 3)
	Selftest.check("cap sink raises max ether", g._retort.cube_purchase("cap").get("ok", false)
		and g._engine._max_ether() == cap0 + int(RetortBalance.CAP[0]["cap"]))
	for e in ["fire-4", "water-4", "earth-4", "air-4"]: g._retort._essence_add(e, 2)
	g._retort._cube_levels["complexity"] = 3
	Selftest.check("blend gated by complexity 5", not g._retort.cube_purchase("blend").get("ok", true))
	g._retort._cube_levels["complexity"] = 5
	Selftest.check("blend unlocks at complexity 5", g._retort.cube_purchase("blend").get("ok", false))

	# Честный путь 0→5: каждая ступень покупается за свои эссенции, без прямой записи уровня.
	g._retort._essence_inv.clear()
	g._retort._cube_levels["complexity"] = 0
	g._retort._cube_levels["blend"] = 0
	var complexity_path := true
	for lvl in RetortBalance.COMPLEXITY.size():
		var price: Dictionary = RetortBalance.COMPLEXITY[lvl]
		for id in price.get("essences", {}):
			g._retort._essence_add(String(id), int(price["essences"][id]))
		complexity_path = bool(g._retort.cube_purchase("complexity").get("ok", false)) and complexity_path
	for id in RetortBalance.BLEND[0].get("essences", {}):
		g._retort._essence_add(String(id), int(RetortBalance.BLEND[0]["essences"][id]))
	var honest_blend := bool(g._retort.cube_purchase("blend").get("ok", false))
	Selftest.check("complexity purchase path unlocks blend", complexity_path
		and g._retort._level("complexity") == 5 and g._retort._max_distill_tier() == 4 and honest_blend)

	# Task 4, Step 5: sink мастерской.
	var lines0: int = g._workshop.line_count()
	var physical_lines0: int = g._workshop.lines.size()
	var workshop_unlocked0: bool = g._workshop.unlocked
	g._workshop.unlocked = true
	g._retort._essence_add("fire-3", 3); g._retort._essence_add("water-3", 3); g._retort._essence_add("earth-3", 3)
	Selftest.check("equip sink adds a workshop line", g._retort.cube_purchase("equip").get("ok", false)
		and g._workshop.line_count() == lines0 + 1)
	Selftest.check("equip materializes workshop lines", g._workshop.lines.size() == g._workshop.line_count())
	var equip_job: Dictionary = {}
	if g._workshop.lines.size() > physical_lines0:
		equip_job = g._workshop.enqueue(String(g._workshop.lines[physical_lines0].get("id", "")),
			{"target": "steam", "mode": "batch", "amount": 1})
	Selftest.check("equip new workshop line accepts a job", bool(equip_job.get("ok", false)))
	var workshop_view = g._pages._workshop_view
	if is_instance_valid(workshop_view):
		workshop_view.refresh()
	Selftest.check("workshop view materializes the equipped line", is_instance_valid(workshop_view)
		and workshop_view._cards.size() >= g._workshop.line_count()
		and physical_lines0 < workshop_view._cards.size()
		and workshop_view._cards[physical_lines0]["card"].visible)
	g._workshop.lines = g._workshop.lines.slice(0, physical_lines0)
	g._workshop.unlocked = workshop_unlocked0

	# Не оставляем уровни куба и тестовые эссенции последующим сюитам.
	for axis in g._retort._cube_levels:
		g._retort._cube_levels[axis] = 0
	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort._retort_slots.clear()

	# Task 5, Step 1: авто-очередь.
	g._retort._cube_levels["queue"] = 0 # глубина 1
	Selftest.check("queue depth limit", not g._retort.queue_set([{"sub": "fire"}, {"sub": "water"}]))
	Selftest.check("queue set within depth", g._retort.queue_set([{"sub": "fire"}]))
	var deep_program: Array = [{"sub": "fire", "nested": {"value": 1}}]
	g._retort.queue_set(deep_program)
	deep_program[0]["nested"]["value"] = 99
	Selftest.check("queue set deep-copies program", int(g._retort._queue[0]["nested"]["value"]) == 1)
	g._retort.queue_set([{"sub": "fire"}])
	g._engine.inventory["fire"] = 3
	g._retort.queue_toggle(true)
	g._retort._queue_advance()
	Selftest.check("auto-queue starts a distill", g._retort._retort_busy(0))
	g._retort._queue_advance(Time.get_unix_time_from_system() + 9 * 3600)
	Selftest.check("auto-queue collects essence", g._retort.essence_count(g._retort.essence_of("fire")) >= 1)
	g._engine.inventory["fire"] = 0
	g._retort._retort_cancel(0)
	g._engine.inventory["fire"] = 0 # отмена вернула вещество; для проверки ожидания запас пуст
	g._retort._queue_advance()
	Selftest.check("queue waits without substance, program kept", not g._retort._retort_busy(0)
		and g._retort._queue.size() == 1)
	g._retort._queue_window_start = Time.get_unix_time_from_system() - 100000.0 # > 8 ч окна
	g._engine.inventory["fire"] = 2
	g._retort._queue_advance()
	Selftest.check("live queue ignores expired offline window", g._retort._retort_busy(0))
	g._retort._retort_cancel(0)
	var session_from := Time.get_unix_time_from_system()
	g._retort._queue_window_start = session_from - 100000.0
	g._engine.inventory["fire"] = 2
	g._retort._queue_offline_replay(session_from, session_from + 3600.0)
	Selftest.check("offline window starts at offline replay", g._retort._retort_busy(0)
		and g._retort._queue_window_start == session_from)
	g._retort._retort_cancel(0)
	g._retort._queue_window_start = Time.get_unix_time_from_system() - 100000.0
	var offline_advance_available := false
	for method in g._retort.get_method_list():
		if String(method.get("name", "")) == "_queue_advance" and (method.get("args", []) as Array).size() >= 2:
			offline_advance_available = true
	if offline_advance_available:
		g._retort.call("_queue_advance", Time.get_unix_time_from_system(), true)
	Selftest.check("offline window stops offline queue advance", offline_advance_available and not g._retort._retort_busy(0))

	# Событийный replay: 24 часа окна при 8-часовой дистилляции дают три цикла.
	g._retort._retort_slots.clear()
	g._retort._essence_inv.clear()
	g._retort._cube_levels["offline"] = 2
	g._engine.inventory["fire"] = 20
	var replay_from := 1000000.0
	g._retort._queue_window_start = replay_from
	var replay_available := g._retort.has_method("_queue_offline_replay")
	if replay_available:
		g._retort.call("_queue_offline_replay", replay_from, replay_from + 72.0 * 3600.0)
	var replayed := g._retort.essence_count("fire-0")
	Selftest.check("offline replay preserves intermediate distills", replay_available
		and replayed > 1 and replayed <= 3 and int(g._engine.inventory.get("fire", 0)) >= 17)
	g._retort._cube_levels["offline"] = 0

	# Task 6, Step 1: детерминированный купаж во втором сосуде.
	g._retort._cube_levels["blend"] = 0
	Selftest.check("blend requires blend level", not g._retort.blend_start("fire"))
	g._retort._cube_levels["blend"] = 1
	g._retort._essence_inv.clear()
	Selftest.check("blend needs rare inputs", not g._retort.blend_start("fire"))
	g._retort._essence_add("fire-3", 1); g._retort._essence_add("fire-4", 1)
	Selftest.check("blend starts and spends inputs", g._retort.blend_start("fire")
		and g._retort.essence_count("fire-3") == 0 and g._retort.essence_count("fire-4") == 0)
	Selftest.check("blend not ready early", not g._retort.blend_ready())
	var bc := g._retort.blend_collect(Time.get_unix_time_from_system() + 13 * 3600)
	Selftest.check("blend yields compound essence", bool(bc.get("ok", false))
		and String(bc.get("essence", "")) == "blend-fire" and g._retort.essence_known("blend-fire"))
	Selftest.check("blend deterministic recipe", RetortBalance.BLEND_RECIPES["fire"] == ["fire-3", "fire-4"])
	g._retort._cube_levels["blend"] = 1
	var blend_hours_l1 := g._retort._blend_hours()
	g._retort._cube_levels["blend"] = 2
	Selftest.check("blend level two speeds up blending", g._retort._blend_hours() < blend_hours_l1)
	g._retort._cube_levels["blend"] = 1

	# Покупка → save → load: уровни куба, очередь и незавершённый купаж переживают JSON.
	g._retort._essence_add("fire-0", 3); g._retort._essence_add("water-0", 3)
	var cube_bought: bool = bool(g._retort.cube_purchase("queue").get("ok", false))
	g._retort._essence_add("fire-3", 1); g._retort._essence_add("fire-4", 1)
	var blend_now := Time.get_unix_time_from_system()
	var blend_restarted := g._retort.blend_start("fire", blend_now)
	g._retort.queue_set([{"sub": "fire"}])
	g._retort.queue_toggle(true)
	g._retort._queue_window_start = blend_now - 120.0
	var levels_before: Dictionary = g._retort._cube_levels.duplicate(true)
	var queue_before: Array = g._retort._queue.duplicate(true)
	var blend_before: Dictionary = g._retort._blend.duplicate(true)
	var window_before: float = g._retort._queue_window_start
	var batch_c_frozen := g._saves._save_frozen
	g._saves._save_frozen = false
	var batch_c_saved := g._saves._save_game()
	var batch_c_text := FileAccess.get_file_as_string(g.SAVE_PATH)
	var batch_c_parsed: Variant = JSON.parse_string(batch_c_text)
	var batch_c_data: Dictionary = batch_c_parsed if batch_c_parsed is Dictionary else {}
	Selftest.check("retort batch C save fields", batch_c_saved and batch_c_data.has("cube_levels")
		and batch_c_data.has("queue") and batch_c_data.has("queue_on")
		and batch_c_data.has("queue_cursor") and batch_c_data.has("queue_window_start")
		and batch_c_data.has("blend"))
	for axis in g._retort._cube_levels:
		g._retort._cube_levels[axis] = 0
	g._retort._queue.clear()
	g._retort._queue_on = false
	g._retort._queue_cursor = 0
	g._retort._queue_window_start = 0.0
	g._retort._blend.clear()
	g._saves._load_game()
	Selftest.check("cube levels save roundtrip", cube_bought and g._retort._cube_levels == levels_before
		and g._retort._level("queue") == 1 and g._retort._cube_levels.size() == 8)
	Selftest.check("queue save roundtrip", g._retort._queue == queue_before and g._retort._queue_on
		and g._retort._queue_cursor == 0 and g._retort._queue_window_start == window_before)
	Selftest.check("blend save roundtrip", blend_restarted and g._retort._blend == blend_before
		and g._retort.blend_ready(blend_now + 13 * 3600))

	var corrupt_retort := batch_c_data.duplicate(true)
	corrupt_retort["cube_levels"]["queue"] = 0 # глубина 1: валидный fire остаётся, хвост обрезан
	corrupt_retort["queue"] = ["строка", 7, {"sub": "__st_unknown_retort_substance"}, {"sub": "fire"}, {"sub": "water"}]
	corrupt_retort["queue_cursor"] = 99
	corrupt_retort["blend"] = {"out": "fire-0", "dur": 0}
	var corrupt_written := _write_save_text(g.SAVE_PATH, JSON.stringify(corrupt_retort, "\t", true, true))
	g._saves._load_game()
	g._retort._queue_advance()
	Selftest.check("corrupt retort save is fail-closed", corrupt_written
		and g._retort._queue == [{"sub": "fire"}] and g._retort._queue_cursor == 0
		and g._retort._blend.is_empty())
	_write_save_text(g.SAVE_PATH, batch_c_text)
	g._saves._load_game()

	# Перегонка сохраняет дерево куба так же, как инвентарь и кодекс эссенций.
	for raw_id in g.ITEMS:
		var id := String(raw_id)
		if not g._engine.inventory.has(id):
			g._engine.inventory[id] = 1
		if g._engine.inventory.size() >= Game.PRESTIGE_MIN:
			break
	g._hub._do_prestige()
	Selftest.check("prestige keeps cube levels", g._retort._cube_levels == levels_before)
	_write_save_text(g.SAVE_PATH, batch_c_text)
	g._saves._load_game()

	for axis in g._retort._cube_levels:
		g._retort._cube_levels[axis] = 0
	g._retort._queue.clear()
	g._retort._queue_on = false
	g._retort._queue_cursor = 0
	g._retort._queue_window_start = 0.0
	g._retort._blend.clear()
	g._retort._essence_inv.clear()
	g._retort._essence_codex.clear()
	g._retort._retort_slots.clear()
	g._saves._save_frozen = batch_c_frozen

	# Task 8: экран v2 — русские оси, гейт пикера и типизированный выход слота.
	Selftest.check("retort v2 axis titles", g._retort.has_method("_axis_title")
		and g._retort.call("_axis_title", "queue") == "Глубина очереди"
		and g._retort.call("_axis_title", "offline") == "Оффлайн-окно"
		and g._retort.call("_axis_title", "slots") == "Ячейки"
		and g._retort.call("_axis_title", "speed") == "Скорость"
		and g._retort.call("_axis_title", "complexity") == "Сложность"
		and g._retort.call("_axis_title", "blend") == "Купаж"
		and g._retort.call("_axis_title", "cap") == "Эссенциальная ёмкость"
		and g._retort.call("_axis_title", "equip") == "Эссенциальное оборудование")

	# Финальная компоновка: аппарат общий, сосуды выше купажа, очередь без висячих стрелок.
	var upgrades_tab := g._retort._retort_tab_buttons.get("tree") as Button
	Selftest.check("retort upgrades tab title", is_instance_valid(upgrades_tab) and upgrades_tab.text == "Улучшения")
	var shared_art := g._retort._retort_art_scene
	var art_inside_tab := false
	if is_instance_valid(shared_art):
		var ancestor := shared_art.get_parent()
		while ancestor != null:
			if g._retort._retort_pages.values().has(ancestor):
				art_inside_tab = true
				break
			ancestor = ancestor.get_parent()
	Selftest.check("retort apparatus is outside tab pages", is_instance_valid(shared_art) and not art_inside_tab)
	var art_visible_everywhere := is_instance_valid(shared_art)
	for tab in ["cube", "essences", "tree", "queue"]:
		g._retort._select_retort_tab(tab, false)
		var art_visible_on_tab := is_instance_valid(shared_art)
		var current := shared_art as Node
		while current != null:
			if current is CanvasItem and not current.visible:
				art_visible_on_tab = false
			if current.name == "RetortV2":
				break
			current = current.get_parent()
		art_visible_everywhere = art_visible_everywhere and art_visible_on_tab
	Selftest.check("retort apparatus is visible on every tab", art_visible_everywhere)
	var cube_page := g._retort._retort_pages.get("cube") as VBoxContainer
	var slots_panel := cube_page.find_child("Слотысосудов", true, false) if is_instance_valid(cube_page) else null
	var blend_panel := cube_page.find_child("Купаж", true, false) if is_instance_valid(cube_page) else null
	Selftest.check("retort slots precede blend on cube tab", is_instance_valid(slots_panel) and is_instance_valid(blend_panel)
		and slots_panel.get_parent() == cube_page and blend_panel.get_parent() == cube_page
		and slots_panel.get_index() < blend_panel.get_index())

	var queue_level_before: int = g._retort._cube_levels["queue"]
	var queue_before_layout: Array = g._retort._queue.duplicate(true)
	g._retort._cube_levels["queue"] = 1
	g._retort.queue_set([{"sub": "fire"}, {"sub": "water"}])
	g._retort._refresh_queue_editor()
	var rail_steps: Array = []
	for child in g._retort._queue_flow.get_children():
		if String(child.name).begins_with("RetortQueueStep"):
			rail_steps.append(child)
	var colored_liquids := rail_steps.size() == 2
	for i in rail_steps.size():
		var liquid := rail_steps[i].find_child("Liquid", true, false) as TextureRect
		var element := "fire" if i == 0 else "water"
		var expected := g._item_colors.get(element, Color.WHITE) as Color
		colored_liquids = colored_liquids and is_instance_valid(liquid) and liquid.texture != null and liquid.modulate == expected
	var queue_scroll := g._retort._queue_flow.get_parent() as ScrollContainer
	Selftest.check("retort queue is a horizontal rail of colored vessels", g._retort._queue_flow.get_class() == "HBoxContainer"
		and is_instance_valid(queue_scroll) and queue_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and queue_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and colored_liquids)
	var plain_art := rail_steps.size() == 2
	var manifold_steps := rail_steps.size() == 2
	for step in rail_steps:
		var vessel_sprite := step.find_child("Vessel", true, false) as TextureRect
		plain_art = plain_art and is_instance_valid(vessel_sprite) and vessel_sprite.texture != null \
			and vessel_sprite.texture.resource_path == "res://assets/retort/queue_round_flask.svg"
		var channel := step.find_child("Channel", true, false) as TextureRect
		var removes: Array = step.find_children("RetortQueueRemove*", "Button", true, false)
		manifold_steps = manifold_steps and step is Button and step.custom_minimum_size.x >= 100.0 \
			and is_instance_valid(channel) and channel.texture != null \
			and channel.texture.resource_path == "res://assets/retort/queue_channel.svg" and removes.is_empty()
	for child in g._retort._queue_flow.get_children():
		if child is TextureRect:
			manifold_steps = false
	manifold_steps = manifold_steps and queue_scroll.custom_minimum_size.y >= 128.0
	Selftest.check("retort queue uses plain round flask artwork", plain_art)
	Selftest.check("retort queue is one manifold without floating controls", manifold_steps)
	var queue_page := g._retort._retort_pages.get("queue") as VBoxContainer
	var edit_actions := queue_page.find_child("RetortQueueEditActions", true, false) as Control
	Selftest.check("retort queue shared edit panel starts hidden", is_instance_valid(edit_actions) and not edit_actions.visible)
	if g._retort.has_method("_queue_select"):
		g._retort.call("_queue_select", 1)
	var replace_btn := queue_page.find_child("RetortQueueReplace", true, false) as Button
	var shared_remove := queue_page.find_child("RetortQueueRemoveSelected", true, false) as Button
	Selftest.check("retort queue selection reveals shared edit actions", is_instance_valid(edit_actions) and edit_actions.visible
		and is_instance_valid(replace_btn) and replace_btn.text == "Заменить"
		and is_instance_valid(shared_remove) and shared_remove.text == "Убрать")
	Selftest.check("retort queue shared edit actions stay compact", is_instance_valid(edit_actions)
		and edit_actions.get_parent() is HBoxContainer and edit_actions.custom_minimum_size.y <= 30.0
		and replace_btn.custom_minimum_size.y <= 30.0 and shared_remove.custom_minimum_size.y <= 30.0)
	Selftest.check("retort queue edit buttons stack beside rail", is_instance_valid(edit_actions)
		and edit_actions.get_class() == "VBoxContainer" and edit_actions.get_parent() == queue_scroll.get_parent()
		and queue_scroll.get_index() < edit_actions.get_index() and replace_btn.get_parent() == edit_actions
		and shared_remove.get_parent() == edit_actions and replace_btn.get_index() < shared_remove.get_index())
	var selected_highlight := true
	var highlighted_count := 0
	for child in g._retort._queue_flow.get_children():
		if not String(child.name).begins_with("RetortQueueStep"):
			continue
		var selection := child.find_child("Selection", true, false) as TextureRect
		var should_highlight := child.name == "RetortQueueStep2"
		selected_highlight = selected_highlight and is_instance_valid(selection) and selection.texture != null \
			and selection.texture.resource_path == "res://assets/retort/queue_selection.svg" \
			and selection.visible == should_highlight
		if is_instance_valid(selection) and selection.visible:
			highlighted_count += 1
	Selftest.check("retort queue clearly highlights selected vessel", selected_highlight and highlighted_count == 1)
	var replace_available := g._retort.has_method("_queue_replace")
	g._engine.inventory["earth"] = 1
	if replace_available:
		g._retort.call("_queue_replace", 1, "earth")
	Selftest.check("retort queue replaces selected step", replace_available
		and g._retort._queue == [{"sub": "fire"}, {"sub": "earth"}])
	if is_instance_valid(shared_remove):
		shared_remove.pressed.emit()
	Selftest.check("retort queue shared remove deletes selected step", g._retort._queue == [{"sub": "fire"}]
		and is_instance_valid(edit_actions) and not edit_actions.visible)
	g._retort._cube_levels["queue"] = queue_level_before
	g._retort.queue_set(queue_before_layout)
	g._retort._refresh_queue_editor()
	g._retort._select_retort_tab("cube", false)

	var picker_list0: VBoxContainer = g._retort._retort_list
	var picker_list := VBoxContainer.new()
	g._retort._retort_list = picker_list
	g._engine.inventory["fire"] = 1
	g._engine.inventory["sun"] = 1
	g._retort._cube_levels["complexity"] = 0
	g._retort._rebuild_retort_rows()
	var gated_found := false
	var output_found := false
	for row in picker_list.get_children():
		var texts: Array = []
		for part in row.get_children():
			for label in part.get_children():
				if label is Label:
					texts.append(label.text)
		if row is Button and row.disabled:
			gated_found = texts.has("заперт (сложность) · ×1")
		if texts.has("fire-0 · ×1"):
			output_found = true
	Selftest.check("retort picker shows typed output and complexity gate", gated_found and output_found)
	g._retort._retort_list = picker_list0
	picker_list.free()
	g._engine.inventory["sun"] = 0

	var ui0: Array = g._retort._retort_ui.duplicate(true)
	var head0: Label = g._retort._retort_head
	var cards0: VBoxContainer = g._retort._retort_cards
	var ess0: Label = g._retort._retort_ess
	var temp_cards := VBoxContainer.new()
	g._retort._retort_head = Label.new()
	g._retort._retort_cards = temp_cards
	g._retort._retort_ess = Label.new()
	g._retort._retort_ui.clear()
	for i in Game.RETORT_SLOT_MAX:
		g._retort._retort_ui.append({"title": Label.new(), "state": Label.new(), "primary": Button.new(), "cancel": Button.new()})
	g._retort._retort_slots.clear()
	g._retort._retort_slots.append({"sub": "fire", "name": "Огонь", "essence": "fire-0", "tier": 0, "started": 0.0, "dur": 1.0})
	g._retort._refresh_retort_page()
	var ready_state: Label = g._retort._retort_ui[0]["state"]
	var ready_button: Button = g._retort._retort_ui[0]["primary"]
	Selftest.check("retort ready slot names essence", ready_state.text == "«Огонь» → эссенция fire-0"
		and ready_button.text == "Забрать эссенцию")
	g._retort._cube_levels["slots"] = 0
	g._retort._retort_slots = [
		{"sub": "fire", "name": "Огонь", "essence": "fire-0", "started": 0.0, "dur": 1.0},
		{"sub": "water", "name": "Вода", "essence": "water-0", "started": Time.get_unix_time_from_system(), "dur": 1000000.0},
		{"sub": "earth", "name": "Земля", "essence": "earth-0", "started": Time.get_unix_time_from_system(), "dur": 1000000.0},
		{"sub": "", "name": "", "started": 0.0, "dur": 0.0},
	]
	g._retort._refresh_retort_page()
	Selftest.check("occupied migrated slots stay visible in retort UI",
		g._retort._retort_ui[0]["primary"].visible
		and g._retort._retort_ui[1]["cancel"].visible and g._retort._retort_ui[2]["cancel"].visible
		and not String(g._retort._retort_ui[1]["title"].text).contains("закрыт")
		and not g._retort._retort_ui[3]["primary"].visible
		and String(g._retort._retort_ui[3]["title"].text).contains("закрыт"))
	for entry in g._retort._retort_ui:
		for node in entry.values():
			node.free()
	g._retort._retort_head.free()
	g._retort._retort_ess.free()
	temp_cards.free()
	g._retort._retort_ui = ui0
	g._retort._retort_head = head0
	g._retort._retort_cards = cards0
	g._retort._retort_ess = ess0
	g._retort._retort_slots.clear()
