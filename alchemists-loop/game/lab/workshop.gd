extends RefCounted
class_name Workshop
# Persistent equipment/mastery and validated commands. Core owns execution.

const Rules = preload("res://game/data/workshop_balance.gd")
signal changed

var g: Game
var unlocked := false
var xp := 0
var rank := 0
var autonomy_level := 0
var lines: Array = []
var scheduler_cursor := 0
var last_simulated_at := 0.0
var _future_state: Dictionary = {}
var _next_job_serial := 1
var _equipment_busy := false

func _init(game: Game) -> void:
	g = game
	reset_new_game()

func on_synthesis(item_id: String) -> int:
	if is_read_only() or not g.ITEMS.has(item_id) or item_id in Game.BASE_IDS:
		return 0
	var opened := item_id == "person" and not unlocked
	if opened:
		unlocked = true
	if not unlocked:
		return 0
	var depth := _content_depth(item_id)
	var award := mini(depth, 6) if depth > 0 and depth < Rules.INVALID_DEPTH else 0
	award = mini(award, Rules.MAX_XP - xp)
	xp += award
	if opened or award > 0:
		changed.emit()
	return award

func _content_depth(item_id: String, trail: Array = []) -> int:
	if not g.ITEMS.has(item_id):
		return Rules.INVALID_DEPTH
	if item_id in Game.BASE_IDS:
		return 0
	if g._online._server_layers.has(item_id):
		return _integer(g._online._server_layers[item_id], 1, Rules.INVALID_DEPTH - 1, Rules.INVALID_DEPTH)
	if trail.has(item_id):
		return Rules.INVALID_DEPTH
	var next := trail.duplicate()
	next.append(item_id)
	var best := Rules.INVALID_DEPTH
	for recipe in g.RECIPES:
		if String(recipe.get("out", "")) != item_id:
			continue
		var a := _content_depth(String(recipe.get("a", "")), next)
		var b := _content_depth(String(recipe.get("b", "")), next)
		if a < Rules.INVALID_DEPTH and b < Rules.INVALID_DEPTH:
			best = mini(best, maxi(a, b) + 1)
	return best

func is_read_only() -> bool:
	return not _future_state.is_empty()

func line_count() -> int:
	return int(Rules.RANKS[rank]["lines"])

func queue_capacity() -> int:
	return int(Rules.RANKS[rank]["capacity"])

func offline_stage_limit() -> int:
	return int(Rules.AUTONOMY[autonomy_level]["stages"])

func known_target_recipe(target: String) -> bool:
	if not g.ITEMS.has(target) or target in Game.BASE_IDS:
		return false
	for recipe in g.RECIPES:
		if String(recipe.get("out", "")) == target:
			var a := String(recipe.get("a", ""))
			var b := String(recipe.get("b", ""))
			if g.ITEMS.has(a) and g.ITEMS.has(b) and g._engine.known_recipes.has(g._pair_key(a, b)):
				return true
	return false

func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}

func _command_check() -> Dictionary:
	if is_read_only():
		return _failure("unsupported_version", "Сохранена новая версия Мастерской: обнови игру.")
	if not unlocked:
		return _failure("locked", "Мастерская откроется после Человека.")
	return {"ok": true, "reason": ""}

func rank_availability(next_rank: int) -> Dictionary:
	var check := _command_check()
	if not check["ok"]:
		return check
	if next_rank < 1 or next_rank >= Rules.RANKS.size() or next_rank != rank + 1:
		return _failure("rank", "Сначала построй предыдущий ранг оборудования.")
	var recipe: Dictionary = Rules.RANKS[next_rank]
	if xp < int(recipe["xp"]):
		return _failure("xp", "Нужно %d мастерства Мастерской." % int(recipe["xp"]))
	return _recipe_availability(recipe)

func autonomy_availability() -> Dictionary:
	var check := _command_check()
	if not check["ok"]:
		return check
	var next := autonomy_level + 1
	if next >= Rules.AUTONOMY.size():
		return _failure("maximum", "Автономность уже улучшена до предела.")
	var recipe: Dictionary = Rules.AUTONOMY[next]
	if rank < int(recipe["rank"]):
		return _failure("rank", "Нужен ранг «%s»." % String(Rules.RANKS[int(recipe["rank"])]["name"]))
	return _recipe_availability(recipe)

func _recipe_availability(recipe: Dictionary) -> Dictionary:
	if _equipment_busy or (g._engine.has_method("_resource_mutation_allowed")
		and not bool(g._engine.call("_resource_mutation_allowed"))):
		return _failure("busy", "Котёл занят: дождись завершения текущей операции.")
	for item in recipe["materials"]:
		if not known_target_recipe(item):
			return _failure("recipe", "Сначала открой рецепт: %s." % g._online._item_name(item))
		if int(g._engine.inventory.get(item, 0)) < int(recipe["materials"][item]):
			return _failure("materials", "Не хватает %s: нужно ×%d." % [g._online._item_name(item), int(recipe["materials"][item])])
	if g._engine._available_ether() < int(recipe["ether"]):
		return _failure("ether", "Нужно %d эфира (включая резерв)." % int(recipe["ether"]))
	return {"ok": true, "reason": "", "ether": int(recipe["ether"]), "materials": recipe["materials"].duplicate(true)}

func _spend_recipe(recipe: Dictionary) -> bool:
	_equipment_busy = true
	if not g._engine._spend_ether(int(recipe["ether"])):
		_equipment_busy = false
		return false
	for item in recipe["materials"]:
		g._engine.inventory[item] = int(g._engine.inventory.get(item, 0)) - int(recipe["materials"][item])
	_equipment_busy = false
	return true

func buy_rank(next_rank: int) -> Dictionary:
	var check := rank_availability(next_rank)
	if not check["ok"]:
		return check
	if not _spend_recipe(Rules.RANKS[next_rank]):
		return _failure("ether", "Эфира для оборудования уже недостаточно.")
	rank = next_rank
	while lines.size() < line_count():
		lines.append(_new_line(_unused_id("line", _line_ids())))
	changed.emit()
	return {"ok": true, "reason": "", "rank": rank}

func buy_autonomy() -> Dictionary:
	var check := autonomy_availability()
	if not check["ok"]:
		return check
	if not _spend_recipe(Rules.AUTONOMY[autonomy_level + 1]):
		return _failure("ether", "Эфира для автономности уже недостаточно.")
	autonomy_level += 1
	changed.emit()
	return {"ok": true, "reason": "", "autonomy_level": autonomy_level}

func missing_materials_preview(kind: String) -> Dictionary:
	# Planning is independent of the XP/ether purchase gate: producing the
	# equipment materials is itself a way to practise Workshop mastery.
	var check := _command_check()
	if not check["ok"]:
		return check
	var recipe: Dictionary
	if kind == "rank":
		if rank + 1 >= Rules.RANKS.size():
			return _failure("maximum", "Оборудование уже улучшено до предела.")
		recipe = Rules.RANKS[rank + 1]
	elif kind == "autonomy":
		if autonomy_level + 1 >= Rules.AUTONOMY.size():
			return _failure("maximum", "Автономность уже улучшена до предела.")
		recipe = Rules.AUTONOMY[autonomy_level + 1]
		if rank < int(recipe["rank"]):
			return _failure("rank", "Нужен ранг «%s»." % String(Rules.RANKS[int(recipe["rank"])]["name"]))
	else:
		return _failure("kind", "Выбери материалы оборудования или автономности.")
	var deficits := {}
	for item in recipe["materials"]:
		if not known_target_recipe(item):
			return _failure("recipe", "Сначала открой рецепт «%s» в Эксперименте." % g._online._item_name(item))
		var missing := maxi(0, int(recipe["materials"][item]) - int(g._engine.inventory.get(item, 0)))
		if missing > 0:
			deficits[item] = missing
	var slots: Array[String] = []
	for i in mini(line_count(), lines.size()):
		for _slot in maxi(0, queue_capacity() - lines[i]["queue"].size()):
			slots.append(String(lines[i]["id"]))
	if slots.size() < deficits.size():
		return _failure("capacity", "Для всех недостающих материалов нужно %d свободных мест; доступно %d. Освободи очередь." % [deficits.size(), slots.size()])
	var plan: Array = []
	for item in deficits:
		plan.append({"line_id": slots[plan.size()], "target": item, "mode": "stock",
			"amount": int(recipe["materials"][item])})
	return {"ok": true, "reason": "", "deficits": deficits, "jobs": plan,
		"materials": recipe["materials"].duplicate(true), "ether": int(recipe["ether"])}

func queue_missing_materials(kind: String) -> Dictionary:
	# Recompute at command time, validate the WHOLE plan, then publish once.
	var plan := missing_materials_preview(kind)
	if not plan["ok"]:
		return plan
	if plan["jobs"].is_empty():
		return {"ok": true, "reason": "Все материалы уже есть в общем запасе.", "ids": []}
	var original := lines.duplicate(true)
	var serial := _next_job_serial
	var blocked := is_blocking_signals()
	set_block_signals(true)
	var ids: Array[String] = []
	for job in plan["jobs"]:
		var result := enqueue(String(job["line_id"]), job)
		if not result["ok"]:
			lines = original
			_next_job_serial = serial
			set_block_signals(blocked)
			return result
		ids.append(String(result["id"]))
	set_block_signals(blocked)
	changed.emit()
	return {"ok": true, "reason": "Недостающие материалы запланированы: %d заданий поддержания запаса." % ids.size(), "ids": ids}

func job_preview(target: String, mode: String, amount: int) -> Dictionary:
	if not known_target_recipe(target):
		return _failure("recipe", "Сначала открой рецепт в Эксперименте.")
	if not mode in ["batch", "stock"] or amount < 1 or amount > Game.CRAFT_INVENTORY_STACK_CAP:
		return _failure("amount", "Выбери режим и количество от 1 до %d." % Game.CRAFT_INVENTORY_STACK_CAP)
	var units := amount if mode == "batch" else maxi(0, amount - int(g._engine.inventory.get(target, 0)))
	var stock := g._engine.inventory.duplicate(true)
	stock.erase(target)
	var op_n := {}
	var base_add := {}
	var missing: Array[String] = []
	g._engine._cost_cache.clear()
	g._guild._collect_needs(stock, target, units, op_n, base_add, missing)
	if not missing.is_empty():
		return _failure("recipe", "Маршрут требует ещё не открытого рецепта. Перейди в Эксперимент.")
	var ops: Array = op_n.values()
	ops.sort_custom(_preview_op_order)
	var total := 0
	for op in ops:
		total += int(op["n"])
	if total > Game.CRAFT_PLAN_HARD_LIMIT_OPERATIONS:
		return _failure("plan_limit", "Оценка маршрута слишком длинная; выбери меньшую партию.")
	var discount := Game.BLUEPRINT_DISCOUNT if g._engine._blueprints.has(target) else 1.0
	var simulated := g._engine.inventory.duplicate(true)
	var ether_cost := 0
	var next_cost := 0
	for op in ops:
		var recipe := g._online._find_recipe(String(op["a"]), String(op["b"]))
		var output := String(recipe.get("out", ""))
		var first_cost := g._engine._pair_cost(String(op["a"]), String(op["b"]), discount)
		var repeat_cost := maxi(1, int(round(Game.BREW_COST * discount)))
		if simulated.has(output) and not g._engine.inventory.has(output):
			first_cost = repeat_cost
		if next_cost == 0:
			next_cost = first_cost
		ether_cost += first_cost + maxi(0, int(op["n"]) - 1) * repeat_cost
		simulated[output] = 0
	var shortage := PackedStringArray()
	for item in base_add:
		# _collect_needs has already consumed existing base stock.
		shortage.append("%s ×%d" % [g._online._item_name(item), int(base_add[item])])
	return {"ok": true, "reason": "Добудь из источников: %s." % " · ".join(shortage) if not shortage.is_empty() else "",
		"units": units, "operations": total, "ether": ether_cost, "next_ether": next_cost,
		"discount": discount, "ops": ops, "base_add": base_add}

static func _preview_op_order(a: Dictionary, b: Dictionary) -> bool:
	if int(a["layer"]) != int(b["layer"]):
		return int(a["layer"]) < int(b["layer"])
	return String(a["a"]) + String(a["b"]) < String(b["a"]) + String(b["b"])

func _line(line_id: String) -> Dictionary:
	for line in lines:
		if String(line["id"]) == line_id:
			return line
	return {}

func _line_ids() -> Dictionary:
	var ids := {}
	for line in lines:
		ids[line["id"]] = true
	return ids

func _job_ids() -> Dictionary:
	var ids := {}
	for line in lines:
		for job in line["queue"]:
			ids[job["id"]] = true
	return ids

static func _valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 96:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func _unused_id(prefix: String, used: Dictionary, start: int = 1) -> String:
	var serial := start
	while used.has("%s_%d" % [prefix, serial]):
		serial += 1
	return "%s_%d" % [prefix, serial]

func enqueue(line_id: String, job: Dictionary) -> Dictionary:
	var check := _command_check()
	if not check["ok"]:
		return check
	var line := _line(line_id)
	if line.is_empty():
		return _failure("line", "Эта производственная линия недоступна.")
	if line["queue"].size() >= queue_capacity():
		return _failure("capacity", "Очередь линии заполнена (активное задание тоже занимает место).")
	if not job.get("target") is String or not known_target_recipe(job["target"]):
		return _failure("recipe", "Выбери вещество с открытым рецептом.")
	if not job.get("mode") is String or not job["mode"] in ["batch", "stock"]:
		return _failure("mode", "Выбери партию или поддержание запаса.")
	var amount: Variant = job.get("amount")
	if not amount is int or amount < 1 or amount > Game.CRAFT_INVENTORY_STACK_CAP:
		return _failure("amount", "Количество должно быть целым от 1 до %d." % Game.CRAFT_INVENTORY_STACK_CAP)
	var id: String = _unused_id("job", _job_ids(), _next_job_serial)
	if job.has("id"):
		if not _valid_id(job["id"]) or _job_ids().has(job["id"]):
			return _failure("id", "Идентификатор задания недопустим или уже занят.")
		id = job["id"]
	_next_job_serial += 1
	line["queue"].append({"id": id, "target": job["target"], "mode": job["mode"], "amount": amount,
		"produced": 0, "status": "paused_user" if line["paused"] else "idle", "reason": "", "route_operations": 0})
	changed.emit()
	return {"ok": true, "reason": "", "id": id}

func reorder(line_id: String, from_index: int, to_index: int) -> bool:
	if not _command_check()["ok"]:
		return false
	var line := _line(line_id)
	if line.is_empty() or from_index < 0 or to_index < 0 or from_index >= line["queue"].size() or to_index >= line["queue"].size():
		return false
	if from_index == to_index:
		return true
	var job: Dictionary = line["queue"].pop_at(from_index)
	line["queue"].insert(to_index, job)
	changed.emit()
	return true

func remove_job(line_id: String, job_id: String) -> bool:
	if not _command_check()["ok"]:
		return false
	var line := _line(line_id)
	if line.is_empty():
		return false
	for i in line["queue"].size():
		if line["queue"][i]["id"] == job_id:
			line["queue"].remove_at(i)
			changed.emit()
			return true
	return false

func set_line_paused(line_id: String, paused: bool) -> bool:
	if not _command_check()["ok"]:
		return false
	var line := _line(line_id)
	if line.is_empty():
		return false
	if line["paused"] != paused:
		line["paused"] = paused
		changed.emit()
	return true

func _new_line(id: String) -> Dictionary:
	return {"id": id, "paused": false, "phase_seconds": 0.0, "stage_credit": 0, "queue": []}

func reset_new_game() -> void:
	_clear_state()
	changed.emit()

func _clear_state() -> void:
	_future_state.clear()
	_next_job_serial = 1
	unlocked = false
	xp = 0
	rank = 0
	autonomy_level = 0
	lines = [_new_line("line_1")]
	scheduler_cursor = 0
	last_simulated_at = Time.get_unix_time_from_system()

func reset_prestige() -> void:
	if is_read_only():
		return
	var fresh: Array = []
	for i in line_count():
		fresh.append(_new_line(String(lines[i]["id"]) if i < lines.size() else "line_%d" % (i + 1)))
	lines = fresh
	scheduler_cursor = 0
	last_simulated_at = Time.get_unix_time_from_system()
	changed.emit()

func export_state() -> Dictionary:
	if is_read_only():
		return _future_state.duplicate(true)
	return {"version": Rules.VERSION, "unlocked": unlocked, "xp": xp, "rank": rank,
		"autonomy_level": autonomy_level, "lines": lines.duplicate(true),
		"scheduler_cursor": scheduler_cursor, "last_simulated_at": last_simulated_at}

func import_state(raw: Variant, legacy: Dictionary = {}) -> Dictionary:
	_clear_state()
	if not raw is Dictionary:
		unlocked = g._engine.inventory.has("person")
		last_simulated_at = _number(legacy.get("last_ts"), 0.0, 253402300799.0, last_simulated_at)
		var target: Variant = legacy.get("bench_target", legacy.get("_bench_target"))
		var on: Variant = legacy.get("bench_on", legacy.get("_bench_on", false))
		if unlocked and target is String and known_target_recipe(target):
			lines[0]["paused"] = not (on is bool and on)
			lines[0]["queue"] = [{"id": "job_legacy_bench", "target": target, "mode": "stock",
				"amount": Game.CRAFT_INVENTORY_STACK_CAP, "produced": 0,
				"status": "idle" if on == true else "paused_user", "reason": "", "route_operations": 0}]
		changed.emit()
		return {"ok": true, "reason": "migrated"}
	var source: Dictionary = raw
	var version := _integer(source.get("version"), 1, Rules.MAX_XP, 1)
	if version > Rules.VERSION:
		_future_state = source.duplicate(true)
		changed.emit()
		return {"ok": false, "reason": "unsupported_version"}
	unlocked = source.get("unlocked", false) == true and source.get("unlocked") is bool
	xp = _integer(source.get("xp"), 0, Rules.MAX_XP, 0)
	rank = _integer(source.get("rank"), 0, Rules.RANKS.size() - 1, 0)
	autonomy_level = _integer(source.get("autonomy_level"), 0, mini(rank, Rules.AUTONOMY.size() - 1), 0)
	lines.clear()
	var loaded: Array = source.get("lines", []) if source.get("lines") is Array else []
	var used_lines := {}
	var used_jobs := {}
	for i in line_count():
		var line := _new_line(_unused_id("line", used_lines, i + 1))
		if i < loaded.size() and loaded[i] is Dictionary:
			var entry: Dictionary = loaded[i]
			if _valid_id(entry.get("id")) and not used_lines.has(entry["id"]):
				line["id"] = entry["id"]
			line["paused"] = entry.get("paused") == true and entry.get("paused") is bool
			line["phase_seconds"] = _number(entry.get("phase_seconds"), 0.0, Game.BENCH_INTERVAL, 0.0)
			line["stage_credit"] = _integer(entry.get("stage_credit"), 0, g._engine._stage_ops(), 0)
			if entry.get("queue") is Array:
				for job_entry in entry["queue"]:
					if line["queue"].size() >= queue_capacity():
						break
					var job := _loaded_job(job_entry, used_jobs, bool(line["paused"]))
					if not job.is_empty():
						line["queue"].append(job)
		used_lines[line["id"]] = true
		lines.append(line)
	scheduler_cursor = _integer(source.get("scheduler_cursor"), 0, line_count() - 1, 0)
	last_simulated_at = _number(source.get("last_simulated_at"), 0.0, 253402300799.0, last_simulated_at)
	changed.emit()
	return {"ok": true, "reason": ""}

func _loaded_job(raw: Variant, used_ids: Dictionary, paused: bool) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var entry: Dictionary = raw
	if not entry.get("target") is String or String(entry["target"]).is_empty():
		return {}
	var id := _unused_id("job", used_ids, _next_job_serial)
	if _valid_id(entry.get("id")) and not used_ids.has(entry["id"]):
		id = entry["id"]
	used_ids[id] = true
	_next_job_serial += 1
	var mode: String = entry.get("mode", "batch") if entry.get("mode") is String else "batch"
	if not mode in ["batch", "stock"]:
		mode = "batch"
	var amount := _integer(entry.get("amount"), 1, Game.CRAFT_INVENTORY_STACK_CAP, 1)
	var status: String = entry.get("status", "idle") if entry.get("status") is String else "idle"
	if not status in Rules.STATUSES:
		status = "idle"
	var reason: String = entry.get("reason", "") if entry.get("reason") is String else ""
	if not known_target_recipe(entry["target"]):
		status = "waiting_recipe"
		reason = "Сначала открой рецепт этого вещества."
	elif paused:
		status = "paused_user"
	return {"id": id, "target": entry["target"], "mode": mode, "amount": amount,
		"produced": _integer(entry.get("produced"), 0, amount if mode == "batch" else Game.CRAFT_INVENTORY_STACK_CAP, 0),
		"status": status, "reason": reason,
		"route_operations": _integer(entry.get("route_operations"), 0, Game.CRAFT_PLAN_HARD_LIMIT_OPERATIONS, 0)}

static func _integer(value: Variant, minimum: int, maximum: int, fallback: int) -> int:
	if value is int:
		return value if value >= minimum and value <= maximum else fallback
	if value is float and is_finite(value) and value == floor(value) and value >= minimum and value <= maximum:
		return int(value)
	return fallback

static func _number(value: Variant, minimum: float, maximum: float, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum:
		return float(value)
	return fallback
