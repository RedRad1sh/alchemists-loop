extends RefCounted
class_name Guild
# Гильдия (R3): задания Светика, заказы гильдии, планировщик автоварки.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _quests_done: Dictionary = {}
var _quest_brew: Dictionary = {}
var _quest_tier: Dictionary = {}
var _quest_challenge := 0
var _quest_updating := false
var _quest_label: Button = null
var _quest_rows: VBoxContainer = null
var _order_day := ""
var _order_targets_cache: Array = []
var _order_done: Dictionary = {}
var _order_rows: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

# ---------- задания Светика (квесты духа) ----------

func _quest_on_brew(output: String) -> void:
	_quest_brew[output] = int(_quest_brew.get(output, 0)) + 1
	_orders_check(output)
	_quest_on_state()

func _quest_on_challenge() -> void:
	_quest_challenge += 1
	_quest_on_state()

func _quest_on_state() -> void:
	if g._selftest:
		return
	_quests_update()

func _quest_progress(q: Dictionary) -> int:
	match String(q.get("goal", "")):
		"brew":
			return int(_quest_brew.get(String(q.get("target", "")), 0))
		"items":
			return g._engine.inventory.size()
		"recipes":
			return g._engine.known_recipes.size()
		"tier":
			return int(_quest_tier.get(int(q.get("tier", 0)), 0))
		"affinity":
			return g._spirit._companion_level_for(g._spirit._companion_affinity)
		"challenge":
			return _quest_challenge
	return 0

func _quest_target(q: Dictionary) -> int:
	return int(q.get("count", 1))

func _active_quest() -> Dictionary:
	for q in Game.SPIRIT_QUESTS:
		if not _quests_done.has(String(q["id"])):
			return q
	return {}

# ---------- заказы гильдии (ежедневные) ----------

func _order_targets_for(day: String) -> Array:
	# 3 разных вещества (не базовые), детерминированно от даты
	var h: String = ("orders_" + day).sha256_text()
	var ids: Array = g.ITEMS.keys()
	var picked: Array = []
	var cursor := 0
	while picked.size() < 3 and cursor < 96:
		var hex2 := h.substr((cursor * 2) % h.length(), 2)
		var idx := hex2.hex_to_int() % ids.size()
		var slug := String(ids[idx])
		if not Game.BASE_IDS.has(slug) and not picked.has(slug):
			picked.append(slug)
		cursor += 1
	return picked

func _orders_refresh() -> void:
	var day := Time.get_date_string_from_system()
	if _order_day != day:
		_order_day = day
		_order_targets_cache = _order_targets_for(day)
		_order_done.clear()
		if not g._selftest:
			g._saves._save_game()

func _order_bounty(slug: String) -> int:
	return int(g._engine._rarity_of(slug)["bounty"])

func _orders_check(output: String) -> void:
	if g._selftest:
		return
	_orders_refresh()
	if _order_targets_cache.has(output) and not _order_done.has(output):
		_order_done[output] = true
		var b := _order_bounty(output)
		g._engine._grant_ether(b, "guild_order")
		g._online._set_status("ЗАКАЗ ГИЛЬДИИ: «%s» выполнен (+%d ⚡)" % [g._online._item_name(output), b])
		g._spirit._companion_react("order_done", g._online._item_name(output))
		g._hub._log_event("Заказ гильдии: «%s» выполнен (+%d ⚡)" % [g._online._item_name(output), b])
		Sfx.divide()
		if _order_done.size() == _order_targets_cache.size():
			g._engine._grant_ether(100, "guild_orders_complete")
			g._spirit._companion_gain(5)
			g._online._set_status("ВСЕ ЗАКАЗЫ ГИЛЬДИИ ВЫПОЛНЕНЫ: +100 ⚡")
			g._hub._log_event("Все заказы гильдии выполнены: +100 ⚡")
			Sfx.legendary()
		g._saves._save_game()
		_refresh_quest_label()

func _quests_update() -> void:
	# начисляем награды за выполненные задания; без сайд-эффектов в selftest
	if _quest_updating:
		return
	_quest_updating = true
	var changed := false
	var last_title := ""
	for q in Game.SPIRIT_QUESTS:
		var id := String(q["id"])
		if _quests_done.has(id):
			continue
		if _quest_progress(q) >= _quest_target(q):
			_quests_done[id] = true
			g._engine._grant_ether(int(q.get("ether", 0)), "spirit_quest")
			g._spirit._companion_gain(int(q.get("aff", 0)))
			g._spirit._companion_react("quest_done", String(q["title"]))
			last_title = String(q["title"])
			if not g._selftest:
				g._hub._log_event("Задание Светика: %s" % String(q["title"]))
			changed = true
	_quest_updating = false
	if changed:
		g._saves._save_game()
		_refresh_quest_label()
		g._online._set_status("ЗАДАНИЕ: %s — +%d кап и +%.1f/с навсегда!" % [last_title, Game.QUEST_CAP, Game.QUEST_REGEN])
	g._progress_ui._ach_update()

func _refresh_quest_label() -> void:
	if _quest_label == null:
		return
	_orders_refresh()
	var q := _active_quest()
	if q.is_empty():
		if _order_targets_cache.size() > 0 and _order_done.size() < _order_targets_cache.size():
			_quest_label.text = "✦ Гильдия: заказов %d/%d" % [_order_done.size(), _order_targets_cache.size()]
			_quest_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
		else:
			_quest_label.text = "✦ Светик: все задания выполнены!"
			_quest_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.9))
		return
	var p := mini(_quest_progress(q), _quest_target(q))
	_quest_label.text = "✦ Светик: %s — %d/%d" % [String(q["title"]), p, _quest_target(q)]
	_quest_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))

func _collect_needs(stock: Dictionary, item: String, units: int,
		op_n: Dictionary, base_add: Dictionary, missing: Array[String]) -> void:
	if units <= 0:
		return
	var avail := int(stock.get(item, 0))
	var take := mini(avail, units)
	stock[item] = avail - take
	units -= take
	if units <= 0:
		return
	if item in Game.BASE_IDS:
		base_add[item] = int(base_add.get(item, 0)) + units
		return
	# выбираем самый дешёвый известный рецепт для item
	var best_cost := 1 << 29
	var best_a := ""
	var best_b := ""
	for r in g.RECIPES:
		if String(r["out"]) != item:
			continue
		if not g._engine.known_recipes.has(g._pair_key(String(r["a"]), String(r["b"]))):
			continue
		var c := g._engine._cost_of(String(r["a"])) + g._engine._cost_of(String(r["b"]))
		if c < best_cost:
			best_cost = c
			best_a = String(r["a"])
			best_b = String(r["b"])
	if best_a == "":
		if not missing.has(item):
			missing.append(item)
		return
	var key := g._pair_key(best_a, best_b)
	if not op_n.has(key):
		op_n[key] = {"a": best_a, "b": best_b, "n": 0, "layer": g._engine._layer_of(item)}
	op_n[key]["n"] = int(op_n[key]["n"]) + units
	_collect_needs(stock, best_a, units, op_n, base_add, missing)
	_collect_needs(stock, best_b, units, op_n, base_add, missing)

func _collect_frontier_needs(stock: Dictionary, item: String, units: int,
		op_n: Dictionary, base_add: Dictionary, frontier: Array, missing: Array[String],
		trail: Array[String]) -> void:
	if units <= 0:
		return
	var avail := int(stock.get(item, 0))
	var take := mini(avail, units)
	stock[item] = avail - take
	units -= take
	if units <= 0:
		return
	if item in Game.BASE_IDS:
		base_add[item] = int(base_add.get(item, 0)) + units
		return
	if trail.has(item):
		if not missing.has(item):
			missing.append(item)
		return
	var recipe: Dictionary = {}
	for raw in g.RECIPES:
		var candidate: Dictionary = raw
		if String(candidate.get("out", "")) == item:
			recipe = candidate
			break
	if recipe.is_empty():
		if not missing.has(item):
			missing.append(item)
		return
	var a := String(recipe["a"])
	var b := String(recipe["b"])
	var key := g._pair_key(a, b)
	var next_trail := trail.duplicate()
	next_trail.append(item)
	var front_before := frontier.size()
	var missing_before := missing.size()
	# Для неизвестного узла сначала готовим его входы известными рецептами.
	# Только если оба входа доступны, сам узел становится frontier-задачей.
	_collect_frontier_needs(stock, a, units, op_n, base_add, frontier, missing, next_trail)
	_collect_frontier_needs(stock, b, units, op_n, base_add, frontier, missing, next_trail)
	if not g._engine.known_recipes.has(key):
		if frontier.size() == front_before and missing.size() == missing_before:
			frontier.append({"a": a, "b": b, "out": item, "n": units,
				"key": key, "layer": g._engine._content_layer(item)})
		return
	if frontier.size() > front_before or missing.size() > missing_before:
		return
	if not op_n.has(key):
		op_n[key] = {"a": a, "b": b, "n": 0, "layer": g._engine._layer_of(item)}
	op_n[key]["n"] = int(op_n[key]["n"]) + units

func _plan_known_frontier(item_id: String) -> Dictionary:
	# Частичный план: известные операции до ближайшего неизвестного рецепта.
	# {ok, ops, frontier, base_add, missing, total}; неизвестность — задача
	# Эксперимент, а не generic-блокировка автокрафта.
	g._engine._cost_cache.clear()
	var stock := g._engine.inventory.duplicate()
	stock.erase(item_id)
	var op_n: Dictionary = {}
	var base_add: Dictionary = {}
	var frontier: Array = []
	var missing: Array[String] = []
	_collect_frontier_needs(stock, item_id, 1, op_n, base_add, frontier, missing, [])
	var ops: Array = []
	for key in op_n:
		ops.append(op_n[key])
	ops.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x["layer"]) < int(y["layer"]))
	var total := 0
	for op in ops:
		total += int(op.get("n", 0))
	return {
		"ok": frontier.is_empty() and missing.is_empty(),
		"item": item_id,
		"ops": ops,
		"total": total,
		"base_add": base_add,
		"frontier": frontier,
		"missing": missing,
	}

func _plan_craft(item_id: String) -> Dictionary:
	# план автоварки: {ok, reason, ops: [{a,b,n,layer}], total, base_add}
	g._engine._cost_cache.clear()
	var fail := func(why: String) -> Dictionary:
		return {"ok": false, "reason": why}
	if not g.ITEMS.has(item_id):
		return fail.call("такого вещества нет.")
	var op_n: Dictionary = {}
	var base_add: Dictionary = {}
	var missing: Array[String] = []
	# целевой предмет не берём из запаса: автоварка всегда варит +1 сверх имеющегося
	var stock := g._engine.inventory.duplicate()
	stock.erase(item_id)
	_collect_needs(stock, item_id, 1, op_n, base_add, missing)
	if not missing.is_empty():
		return fail.call("нужен открытый рецепт для «%s»." % g._online._item_name(missing[0]))
	var ops: Array = []
	for key in op_n:
		ops.append(op_n[key])
	ops.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x["layer"]) < int(y["layer"]))
	var total := 0
	for op in ops:
		total += int(op["n"])
	# хватает ли базовых стихий в запасе
	var shortage := PackedStringArray()
	for raw in base_add:
		var id2 := String(raw)
		var need := int(base_add[raw])
		if need > int(g._engine.inventory.get(id2, 0)):
			shortage.append("%s ×%d" % [g._online._item_name(id2), need - int(g._engine.inventory.get(id2, 0))])
	if not shortage.is_empty():
		return fail.call("добудь из источников: %s." % " · ".join(shortage))
	return {"ok": true, "item": item_id, "ops": ops, "total": total, "base_add": base_add}
