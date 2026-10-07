extends RefCounted
class_name Core
# Игровой движок (R13): drag&drop, варка, сбор, прокачка, refresh, автоварка, редкость.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var inventory: Dictionary = {}
var known_recipes: Dictionary = {}
var selected: Array[String] = []
var ether: int = Game.START_ETHER
var attempts: int = 0
var successes: int = 0
var brewing: bool = false
# U9 (T12): поколенческий счётчик сбросов мира (престиж / новая игра / загрузка
# сейва). Каждая потребляющая корутина захватывает его перед await и сверяет после:
# изменение означает, что мир под корутиной заменили, — выход без коммита.
var brew_epoch := 0
var brew_elapsed: float = 0.0
var regen_clock: float = 0.0
var autosave_clock: float = 0.0
var status_text := "Собери ингредиенты и свари первое вещество."
var _cauldron: CauldronView
var _slot_a: SlotWell
var _slot_b: SlotWell
var _brew_btn: Button
var _progress: ProgressBar
var _status_label: Label
var _ether_label: Label
var _collection_label: Label
var _book_list: VBoxContainer
var _book_sig := -1
var _book_q := "@@init@@"
var _search_box: LineEdit
var _book_stats: Label
var _source_orbs: Dictionary = {}
var _item_orbs: Dictionary = {}
# Обёртки ячеек лаборатории: внутри остаётся ElementOrb для tap/drag,
# а сама компактная ячейка даёт удобную touch-зону и подпись.
var _item_cells: Dictionary = {}
var _ghost: ElementOrb
var _drag_id := ""
var _drag_ok := false
var _auto_cancel := false
var _auto := false
var _auto_new: Array[String] = []
var _cost_cache: Dictionary = {}
var _layer_cache: Dictionary = {}
var _pending_item := ""
var _pending_plan: Dictionary = {}
var upgrades: Dictionary = {}
# Ether above the active cap is not silently destroyed. It is a visible reserve
# that can fund later brewing/purchases and the optional mastery rites; passive
# regeneration never fills this reserve.
var ether_overflow: int = 0
var mastery_rank: int = 0
var spring_source := "water"
var spring_on := false
var _source_taps := 0
var _collect_all_ms := 0  # антиспам кнопки «Все»
var _collect_last_gain := 1
var _gift_clock := 0.0
var _milestones_done: Dictionary = {}
# U11 (T15): selftest-наблюдаемость `_grant_first_open` — в selftest сам грант
# no-op (нижний гейт функции сохраняет детерминизм сюит), но счётчик вызовов
# позволяет контрактным тестам found/discover-веток проверить «гран ровно один
# раз на первое локальное получение». Не сериализуется, на геймплей не влияет.
var _first_open_calls := 0
var sage_gold := 0
var _last_pair: Array = []
var _repeat_btn: Button = null
var _reset_btn: Button = null
var _auto_stop_btn: Button = null
var _rejected_pairs: Dictionary = {}
var _last_candidate_time: Dictionary = {}
var _source_boost_until := 0.0  # rewarded: временное удвоение добычи

# Crafting rework: explicit experiments, resumable production jobs and route
# blueprints. The server remains authoritative for new world elements.
var _experiment_day := ""
var _experiment_count := 0
var _experiment_last_at := 0.0
var _experiment_pending_pair: Array[String] = []
var _craft_job: Dictionary = {}
var _blueprints: Dictionary = {}
var _production_discount := 1.0

func _init(game: Game) -> void:
	g = game

# ================= drag & drop =================

func _orb_can_take(item_id: String) -> bool:
	var stock := int(inventory.get(item_id, 0))
	var reserved := selected.count(item_id)
	return stock > reserved

func _on_source_tapped(orb: ElementOrb, item_id: String) -> void:
	if brewing or _auto:
		_deny_orb(orb, "Котёл занят варкой — подожди немного, потом добывай.")
		return
	_collect(item_id)

func _on_item_tapped(orb: ElementOrb, item_id: String) -> void:
	if brewing or _auto:
		_deny_orb(orb, "Котёл занят варкой — ингредиенты пока не поменять.")
		return
	if not orb.discovered:
		status_text = "Туман скрывает это вещество. Попробуй другие пары в котле…"
		Sfx.click()
		_refresh()
		return
	if _place_to_free_slot(item_id):
		Sfx.click()
		Input.vibrate_handheld(8)
		status_text = "В лунку: %s. Можно варить или добавить второй ингредиент." % g._online._item_name(item_id)
	else:
		_deny_orb(orb, "Лунки заняты. Тапни по лунке, чтобы убрать, или перетащи новое вещество поверх.")

func _on_orb_drag_started(orb: ElementOrb, at: Vector2, item_id: String) -> void:
	if brewing or _auto:
		_deny_orb(orb, "Котёл занят варкой — подожди немного.")
		return
	_drag_ok = false
	if not _orb_can_take(item_id) and _source_orbs.has(item_id):
		_drag_ok = true
	elif _item_orbs.has(item_id) and _orb_can_take(item_id):
		_drag_ok = true
	else:
		return
	if _item_orbs.has(item_id) and not (_item_orbs[item_id] as ElementOrb).discovered:
		_deny_orb(orb, "Туман скрывает это вещество — его нельзя использовать.")
		return
	_drag_id = item_id
	if _ghost == null:
		_ghost = g._make_orb(item_id, 62)
		_ghost.interactive = false
		_ghost.z_index = 100
		_ghost.position = at - Vector2(31, 31)
		g.add_child(_ghost)

func _on_orb_drag_ended(_orb: ElementOrb, at: Vector2, item_id: String) -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if not _drag_ok or _drag_id != item_id:
		_drag_id = ""
		return
	_drag_id = ""
	var target := _drop_target(at)
	if target == "":
		if _item_orbs.has(item_id):
			_deny_drop(item_id)
		return
	# источник: сначала добыть, затем положить
	if _source_orbs.has(item_id):
		_collect(item_id)
	if not _orb_can_take(item_id):
		status_text = "Не хватает %s в запасе." % g._online._item_name(item_id)
		_refresh()
		return
	_place_into_slot(item_id, target)
	status_text = "В лунку %s: %s." % [target, g._online._item_name(item_id)]
	Sfx.click()
	Input.vibrate_handheld(8)
	_refresh()

func _deny_drop(item_id: String) -> void:
	var orb: ElementOrb = _item_orbs.get(item_id)
	status_text = "Отпусти %s над лункой A или B, или просто тапни по нему." % g._online._item_name(item_id)
	if orb != null:
		orb.refuse()
	Sfx.error()
	_refresh()

func _drop_target(at: Vector2) -> String:
	var ra := _slot_a.get_global_rect().grow(16)
	var rb := _slot_b.get_global_rect().grow(16)
	var rc := _cauldron.get_global_rect().grow(8)
	if ra.has_point(at):
		return "A"
	if rb.has_point(at):
		return "B"
	if rc.has_point(at):
		return "A" if _slot_a.element_id == "" else ("B" if _slot_b.element_id == "" else "")
	return ""

func _trigger_cauldron_ingredient(item_id: String) -> void:
	if _cauldron != null:
		_cauldron.trigger_ingredient(g._item_colors.get(item_id, Color.WHITE))


func _place_into_slot(item_id: String, slot_letter: String) -> bool:
	if slot_letter == "A":
		if selected.size() > 0 and selected[0] == item_id:
			return false
		if selected.size() == 2:
			selected[0] = item_id
		elif selected.size() == 1:
			selected[0] = item_id
		else:
			selected.append(item_id)
		_slot_a.set_slot(item_id, g._item_colors.get(item_id, Color.WHITE))
		_trigger_cauldron_ingredient(item_id)
		return true
	else:
		if selected.size() == 2 and selected[1] == item_id:
			return false
		if selected.size() == 2:
			selected[1] = item_id
		else:
			selected.append(item_id)
		_sync_slot_b()
		_trigger_cauldron_ingredient(item_id)
		return true

func _place_to_free_slot(item_id: String) -> bool:
	if _slot_a.element_id == "":
		selected.append(item_id)
		_slot_a.set_slot(item_id, g._item_colors.get(item_id, Color.WHITE))
		_trigger_cauldron_ingredient(item_id)
		return true
	if _slot_b.element_id == "":
		selected.append(item_id)
		_sync_slot_b()
		_trigger_cauldron_ingredient(item_id)
		return true
	return false

func _sync_slot_b() -> void:
	if selected.size() >= 2:
		_slot_b.set_slot(selected[1], g._item_colors.get(selected[1], Color.WHITE))
	else:
		_slot_b.set_slot("", Color.WHITE)

func _on_slot_cleared(well: SlotWell) -> void:
	if brewing or _auto:
		_deny_well(well, "Котёл занят варкой — лунки пока не трогать.")
		return
	var had := false
	if well == _slot_a and selected.size() > 0:
		selected.remove_at(0)
		_slot_a.set_slot("", Color.WHITE)
		had = true
	elif well == _slot_b and selected.size() > 1:
		selected.remove_at(1)
		_slot_b.set_slot("", Color.WHITE)
		had = true
	if had:
		well.flash()
		Sfx.click()
		Input.vibrate_handheld(8)
		status_text = "Лунка освобождена."
	else:
		well.refuse()
		Sfx.click()
		Input.vibrate_handheld(6)
		status_text = "Лунка пуста: тапни по веществу в запасе или перетащи его сюда."
	_refresh()
# ================= прокачка и режимы =================

func _up_def(id: String) -> Dictionary:
	for u in Game.UPGRADES:
		if String(u["id"]) == id:
			return u
	return {}

func _up_unlocked(id: String) -> bool:
	var u := _up_def(id)
	if u.is_empty():
		return false
	var need := String(u.get("unlock", ""))
	return need == "" or inventory.has(need)

func _up_lvl(id: String) -> int:
	return int(upgrades.get(id, 0))

func _up_cost(id: String) -> int:
	var u := _up_def(id)
	if u.is_empty():
		return 1 << 29
	return int(float(u["base"]) * pow(float(u["growth"]), _up_lvl(id)))

func _sage_multiplier() -> float:
	# Prestige remains useful, but cannot make regeneration grow without bound.
	# The cap bonus is deliberately stronger than the bounded regen multiplier.
	return 1.0 + 0.04 * minf(float(sage_gold), 15.0)

func _max_ether() -> int:
	return Game.MAX_ETHER + 50 * _up_lvl("ether_cap") + _collection_cap_bonus() \
		+ 40 * sage_gold + g._progress_ui._quest_cap_bonus() + g._progress_ui._ach_cap_bonus() + g._resonance._res_cap_bonus() \
		+ g._retort._essence_cap_bonus() + g._riddles._letter_cap_bonus() + g._riddles._atlas_cap_bonus() + g._retention._circle_cap_bonus() \
		+ g._retention._vein_cap_total + g._sigil.milestone_cap_bonus()

func _ether_rate() -> float:
	return (Game.BASE_ETHER_REGEN + 0.35 * float(_up_lvl("ether_regen")) + _collection_regen_bonus() \
		+ g._progress_ui._quest_regen_bonus() + g._progress_ui._ach_regen_bonus() + g._resonance._res_regen_bonus() \
		+ g._retention._circle_regen_bonus() + g._retention._fair_regen_total) * _sage_multiplier()

func _brew_time() -> float:
	return maxf(0.35, g.BREW_SECONDS * pow(0.90, _up_lvl("brew_speed")))

func _content_layer(item_id: String, trail: Array = []) -> int:
	# Unlike _layer_of, this is independent of the player's known recipe book;
	# it lets the first discovery quote its real depth surcharge.
	if item_id in Game.BASE_IDS:
		return 0
	if g._online._server_layers.has(item_id):
		return int(g._online._server_layers[item_id])
	if trail.has(item_id):
		return 1 << 29
	var next_trail := trail.duplicate()
	next_trail.append(item_id)
	var best := 1 << 29
	for raw_recipe in g.RECIPES:
		var recipe: Dictionary = raw_recipe
		if String(recipe.get("out", "")) != item_id:
			continue
		var la := _content_layer(String(recipe.get("a", "")), next_trail)
		var lb := _content_layer(String(recipe.get("b", "")), next_trail)
		if la < (1 << 29) and lb < (1 << 29):
			best = mini(best, maxi(la, lb) + 1)
	return best

func _discovery_fee_for_layer(layer: int) -> int:
	if layer <= 0:
		return 0
	var key := mini(layer, 6)
	return int(Game.DISCOVERY_FEES.get(key, Game.DISCOVERY_FEES[6]))

func _production_pair_block(a: String, b: String) -> String:
	var recipe := g._online._find_recipe(a, b)
	if recipe.is_empty():
		return "recipe"
	var output := String(recipe.get("out", ""))
	if output != "" and int(inventory.get(output, 0)) >= Game.CRAFT_INVENTORY_STACK_CAP:
		return "inventory"
	return ""

func _pair_cost(a: String, b: String, discount: float = 1.0) -> int:
	var recipe := g._online._find_recipe(a, b)
	var raw_cost := Game.BREW_COST
	if not recipe.is_empty():
		var output := String(recipe.get("out", ""))
		if output != "" and not inventory.has(output):
			raw_cost += _discovery_fee_for_layer(_content_layer(output))
	return maxi(1, int(round(float(raw_cost) * discount)))

func _plan_ether_cost(plan: Dictionary, limit_ops: int = -1, discount: float = 1.0) -> int:
	# Simulate discovery flags in operation order so an auto-chain quotes its
	# real price instead of multiplying the old flat brew cost. A limit quotes
	# the next resumable stage without changing the full-plan estimate.
	var simulated := inventory.duplicate()
	var total := 0
	var taken := 0
	for raw_op in plan.get("ops", []):
		var op: Dictionary = raw_op
		var a := String(op.get("a", ""))
		var b := String(op.get("b", ""))
		for _i in int(op.get("n", 0)):
			if limit_ops >= 0 and taken >= limit_ops:
				return maxi(1, int(round(float(total) * discount))) if total > 0 else 0
			var recipe := g._online._find_recipe(a, b)
			var cost := Game.BREW_COST
			if not recipe.is_empty():
				var out := String(recipe.get("out", ""))
				if out != "" and not simulated.has(out):
					cost += _discovery_fee_for_layer(_content_layer(out))
					simulated[out] = 0
			total += cost
			taken += 1
	if total <= 0:
		return 0
	return maxi(1, int(round(float(total) * discount)))

func _grant_ether(amount: int, _reason: String = "") -> int:
	# Instant rewards use this funnel. Direct energy respects the active cap;
	# the rest becomes a visible, non-energy reserve for mastery rites.
	if amount <= 0:
		return 0
	var direct := mini(amount, maxi(0, _max_ether() - ether))
	ether += direct
	ether_overflow += amount - direct
	return direct

func _experiment_day_key() -> String:
	return Time.get_date_string_from_system()

func _experiment_sync_day() -> void:
	var today := _experiment_day_key()
	if _experiment_day != today:
		_experiment_day = today
		_experiment_count = 0

func _experiment_remaining() -> int:
	_experiment_sync_day()
	return maxi(0, Game.EXPERIMENT_DAILY_LIMIT - _experiment_count)

func _experiment_cooldown_remaining() -> float:
	var elapsed := Time.get_unix_time_from_system() - _experiment_last_at
	return maxf(0.0, Game.EXPERIMENT_COOLDOWN_SEC - elapsed)

func _experiment_status(a: String, b: String) -> Dictionary:
	_experiment_sync_day()
	# U9 (T11): единый мьютекс потребляющих трасс — эксперимент нельзя начать
	# посреди ручной варки, автоплана или шага верстака.
	if brewing or _auto or g._pages._bench_busy:
		return {"ok": false, "reason": "Котёл занят варкой или производством — дождись завершения."}
	if a == "" or b == "" or not g.ITEMS.has(a) or not g.ITEMS.has(b):
		return {"ok": false, "reason": "Выбери два известных вещества."}
	var need_a := 2 if a == b else 1
	if int(inventory.get(a, 0)) < need_a or int(inventory.get(b, 0)) < (2 if a == b else 1):
		return {"ok": false, "reason": "Для эксперимента нужны оба реагента в запасе."}
	if _experiment_pending_pair.size() == 2:
		return {"ok": false, "reason": "Предыдущий эксперимент ещё обрабатывается — дождись ответа мира."}
	var key := g._pair_key(a, b)
	if known_recipes.has(key):
		return {"ok": false, "reason": "Эта комбинация уже записана в книге рецептов."}
	if _rejected_pairs.has(key):
		return {"ok": false, "reason": "Эта комбинация уже признана несочетаемой."}
	var cooldown := _experiment_cooldown_remaining()
	if cooldown > 0.0:
		return {"ok": false, "reason": "Следующий эксперимент будет доступен через %d с." % ceili(cooldown)}
	if _experiment_remaining() <= 0:
		return {"ok": false, "reason": "Дневной лимит экспериментов исчерпан."}
	if _available_ether() < Game.EXPERIMENT_COST:
		return {"ok": false, "reason": "Для эксперимента нужно %d ⚡." % Game.EXPERIMENT_COST}
	return {"ok": true, "key": key}

func _begin_experiment(a: String, b: String) -> bool:
	var check := _experiment_status(a, b)
	if not bool(check.get("ok", false)):
		status_text = String(check.get("reason", "Эксперимент недоступен."))
		Sfx.error()
		_refresh()
		return false
	if not _spend_ether(Game.EXPERIMENT_COST):
		return false
	inventory[a] = int(inventory.get(a, 0)) - 1
	inventory[b] = int(inventory.get(b, 0)) - 1
	attempts += 1
	_experiment_sync_day()
	_experiment_count += 1
	_experiment_last_at = Time.get_unix_time_from_system()
	_experiment_pending_pair = [a, b]
	status_text = "Эксперимент отправлен в лабораторный журнал: %s + %s…" % [g._online._item_name(a), g._online._item_name(b)]
	Analytics.track("experiment_start", {"left": a, "right": b, "cost": Game.EXPERIMENT_COST})
	_refresh()
	return true

func _finish_experiment_inputs(a: String, b: String, full_refund: bool) -> void:
	# U9 (T12): поздний ответ после сброса мира — pending очищен престижем/новой
	# игрой, возвращать/списывать поверх свежего подарочного запаса нельзя.
	# (Корреляция конкретной пары — в Online, задел U11/T14 закрыт; здесь — факт наличия pending.)
	if _experiment_pending_pair.size() != 2:
		return
	inventory[a] = int(inventory.get(a, 0)) + 1
	inventory[b] = int(inventory.get(b, 0)) + 1
	_grant_ether(Game.EXPERIMENT_COST if full_refund else Game.EXPERIMENT_FAILURE_REFUND, "experiment_refund")
	_experiment_pending_pair.clear()
	_refresh()

func _experiment_succeeded(slug: String, a: String, b: String) -> void:
	# U9 (T12): зеркальный guard — успех без висящего эксперимента начислять нельзя.
	if _experiment_pending_pair.size() != 2:
		return
	known_recipes[g._pair_key(a, b)] = true
	inventory[slug] = int(inventory.get(slug, 0)) + 1
	successes += 1
	_experiment_pending_pair.clear()
	status_text = "Эксперимент удался: открыто новое вещество «%s»." % g._online._item_name(slug)
	Analytics.track("experiment_result", {"left": a, "right": b, "result": "created", "output": slug})
	_refresh()
	g._saves._save_game()

func _experiment_failed(a: String, b: String, reason: String = "") -> void:
	# U9 (T12): поздний «not_combinable» после сброса мира — не помечаем пару
	# отклонённой и не трогаем новый инвентарь (зеркальный guard в _finish_experiment_inputs).
	if _experiment_pending_pair.size() != 2:
		return
	_rejected_pairs[g._pair_key(a, b)] = true
	_finish_experiment_inputs(a, b, false)
	status_text = "Эксперимент не дал результата: %s" % (reason if reason != "" else "эти вещества не сочетаются")
	Analytics.track("experiment_result", {"left": a, "right": b, "result": "rejected"})
	Sfx.error()
	g._saves._save_game()

func _available_ether() -> int:
	return ether + ether_overflow

func _spend_ether(amount: int) -> bool:
	if amount < 0 or _available_ether() < amount:
		return false
	var from_current := mini(ether, amount)
	ether -= from_current
	var rest := amount - from_current
	if rest > 0:
		ether_overflow -= rest
	return true

func _spend_mastery_ether(amount: int) -> bool:
	return _spend_ether(amount)

func _stage_ops() -> int:
	# A2: этап автоварки растёт от ранга печати (3 → 4 → 5). Константа — база;
	# читают этап только отсюда.
	var n := Game.CRAFT_STAGE_OPERATIONS
	for r in Game.MASTERY_STAGE_RANKS:
		if mastery_rank >= int(r):
			n += 1
	return n

func _mastery_cost() -> int:
	return int(round(float(Game.ETHER_MASTERY_BASE) * pow(Game.ETHER_MASTERY_GROWTH, mastery_rank)))

func _buy_mastery() -> bool:
	var cost := _mastery_cost()
	if not _spend_mastery_ether(cost):
		status_text = "Для печати мастерства нужно %d ⚡ (эфир + резерв)." % cost
		Sfx.error()
		_refresh()
		return false
	mastery_rank += 1
	status_text = "Печать мастерства укреплена: ранг %d." % mastery_rank
	if mastery_rank in [1, 5, 10, 25, 50]:
		status_text += " Новый титул записан в архиве."
	Sfx.legendary()
	g._saves._save_game()
	g._hub._rebuild_up_rows()
	_refresh()
	return true

func _buy_upgrade(id: String) -> bool:
	var u := _up_def(id)
	if u.is_empty():
		return false
	if not _up_unlocked(id):
		status_text = "«%s» откроется вместе с веществом «%s»." % [String(u["name"]), g._online._item_name(String(u["unlock"]))]
		Sfx.error()
		_refresh()
		return false
	var lvl := _up_lvl(id)
	if lvl >= int(u["max"]):
		status_text = "«%s» прокачана до максимума." % String(u["name"])
		Sfx.error()
		_refresh()
		return false
	var cost := _up_cost(id)
	if not _spend_ether(cost):
		status_text = "Не хватает эфира на «%s»: нужно %d, есть %d." % [u["name"], cost, ether]
		Sfx.error()
		_refresh()
		return false
	upgrades[id] = lvl + 1
	status_text = "Улучшено: %s (ур. %d)." % [u["name"], lvl + 1]
	g._progress_ui._ach_update()
	Sfx.divide()
	Input.vibrate_handheld(15)
	g._hub._rebuild_up_rows()
	_refresh()
	g._saves._save_game()
	return true

func _mode_unlocked(key: String) -> bool:
	if key == "spring":
		return inventory.has("plant")
	if key == "resonance":
		return g._progress_ui._ach_world_first >= 1
	for m in Game.MODES:
		if String(m["key"]) != key:
			continue
		var requirement := String(m.get("unlock", ""))
		if requirement != "" and not inventory.has(requirement):
			return false
		return inventory.size() >= int(m.get("min_items", 0))
	return false

func _spring_tick(delta: float) -> void:
	if not _mode_unlocked("spring") or not spring_on:
		return
	g._pages._spring_clock += delta
	if g._pages._spring_clock >= Game.SPRING_INTERVAL:
		g._pages._spring_clock -= Game.SPRING_INTERVAL
		inventory[spring_source] = int(inventory.get(spring_source, 0)) + 1
		_refresh()

func _gift_tick(delta: float) -> void:
	# улучшение «Дары»: +1 случайное открытое вещество каждые 2 минуты
	if _up_lvl("auto_gift") < 1:
		return
	_gift_clock += delta
	if _gift_clock < Game.GIFT_INTERVAL:
		return
	_gift_clock -= Game.GIFT_INTERVAL
	var pick := g._online._random_opened_item()
	if pick == "":
		return
	inventory[pick] = int(inventory.get(pick, 0)) + 1
	status_text = "Дары: %s +1." % g._online._item_name(pick)
	var orb: ElementOrb = _item_orbs.get(pick)
	if orb != null:
		g._online._floater_at(orb.get_global_rect().get_center(), "+%s" % g._online._item_name(pick),
			g._item_colors.get(pick, Color.WHITE))
	Sfx.click()
	_refresh()
# ================= геймплей =================

func _deny_orb(orb: ElementOrb, msg: String) -> void:
	if orb != null:
		orb.refuse()
	status_text = msg
	Sfx.error()
	_refresh()

func _deny_well(well: SlotWell, msg: String) -> void:
	if well != null:
		well.refuse()
	status_text = msg
	Sfx.error()
	Input.vibrate_handheld(12)
	_refresh()

func _collect_all() -> void:
	if brewing or _auto:
		status_text = "Котёл занят варкой — подожди немного."
		Sfx.error()
		return
	# антиспам: на слабых устройствах очередь нажатий вешала интерфейс (п.6)
	var now_ms := Time.get_ticks_msec()
	if now_ms - _collect_all_ms < 250:
		return
	_collect_all_ms = now_ms
	# пакетный сбор: один звук, один refresh, один сейв на всю партию
	for b in Game.BASE_IDS:
		_collect_gain(String(b))
		var orb: ElementOrb = _source_orbs.get(String(b))
		if orb != null:
			g._online._floater_at(orb.get_global_rect().get_center(), "+%d" % _collect_last_gain,
				g._item_colors.get(String(b), Color.WHITE))
	Sfx.bubble()
	Input.vibrate_handheld(12)
	status_text = "Добыто со всех источников сразу."
	_refresh()
	g._saves._save_game()

func _collect_gain(item_id: String) -> int:
	# чистая математика добычи без refresh/сейва (для пакетного сбора)
	var gained := 1
	if _source_boost_until > Time.get_unix_time_from_system():
		gained += 1
	_source_taps += 1
	if _source_taps % maxi(2, 8 - _up_lvl("source_yield")) == 0:
		gained += 1
	inventory[item_id] = int(inventory.get(item_id, 0)) + gained
	_collect_last_gain = gained
	return gained


func _collect(item_id: String, silent := false) -> void:
	var gained := _collect_gain(item_id)
	if not silent:
		status_text = "Добыто: %s +%d." % [g._online._item_name(item_id), gained]
		Sfx.bubble()
		Input.vibrate_handheld(10)
	var orb: ElementOrb = _source_orbs.get(item_id)
	if orb != null:
		g._online._floater_at(orb.get_global_rect().get_center(), "+%d" % gained,
			g._item_colors.get(item_id, Color.WHITE))
	_refresh()
	Analytics.track("tap_source", {"element": item_id, "amount": gained})
	g._saves._save_game()

var _brew_epoch := 0  # инкрементируется при старте варки; отменяет зависшие async-пути

func _can_brew() -> bool:
	# U9 (T11): верстак — тоже потребляющая трасса, ручная варка с ним не совмещается.
	if brewing or g._pages._bench_busy or selected.size() != 2:
		return false
	return _available_ether() >= _pair_cost(selected[0], selected[1], _production_discount)

## Текст неудачной варки, когда мир так и не спросили. Раньше все случаи
## выглядели одинаково («Туман рассеялся… Возвращено N эфира»), и отложенный
## запрос было не отличить от настоящей неудачи — это и читалось как баг.
func _candidate_skip_text(reason: String, retry_in: float) -> String:
	var tail := " Возвращено %d эфира." % Game.FAILURE_REFUND
	match reason:
		"offline":
			return "Туман рассеялся… Мира нет на связи, спросить пару не у кого." + tail
		"busy":
			return "Туман рассеялся… Мир занят другой парой, эта подождёт." + tail
		"cooldown":
			return ("Туман рассеялся… Мир посмотрит эту пару через %d с."
				% ceili(maxf(retry_in, 1.0))) + tail
		_:
			# "fog" — тот самый 5-процентный туман у авто-производства.
			return "Туман рассеялся…" + tail


func _brew(from_auto: bool = false) -> Dictionary:
	var pair_cost := Game.BREW_COST
	if selected.size() == 2:
		pair_cost = _pair_cost(selected[0], selected[1], _production_discount)
	# U9 (T11): единый мьютекс — ручная варка не стартует, пока идёт автоплан.
	if _auto and not from_auto:
		status_text = "Котёл занят производством — дождись завершения этапа."
		Sfx.error()
		return {"failed": true, "reason": "gate"}
	if not _can_brew():
		if selected.size() != 2:
			status_text = "Положи в лунки два ингредиента."
		elif _available_ether() < pair_cost:
			status_text = "Не хватает эфира: открытие этой глубины стоит %d ⚡." % pair_cost
		else:
			status_text = "Котёл занят: дождись завершения текущей варки или производства."
		return {"failed": true, "reason": "gate"}
	var a := selected[0]
	var b := selected[1]
	Analytics.track("combine_start", {"left": a, "right": b, "source": "manual"})
	if not g._online._has_ingredients(a, b):
		status_text = "Не хватает ингредиентов для этой пары."
		_refresh()
		return {"failed": true, "reason": "ingredients"}
	_last_pair = [a, b]
	brewing = true
	brew_elapsed = 0.0
	if g._spirit._companion != null and g._spirit._companion.visible:
		g._spirit._companion.set_sprite("tremble", -1.0)
		g._spirit._companion.set_shake(true)
	if _progress != null:
		_progress.value = 0.0
	status_text = "Котёл светится. Туман собирается над водой…"
	Sfx.draft_open()
	_refresh()
	var epoch_before := brew_epoch
	await g.get_tree().create_timer(_brew_time()).timeout
	if brew_epoch != epoch_before:
		# U9 (T12): мир был сброшен во время сна корутины (престиж/новая игра/
		# загрузка). Молча выходим: без коммита, списания и наград — реагенты
		# уже принадлежат новому миру.
		brewing = false
		if g._spirit._companion != null:
			g._spirit._companion.set_shake(false)
		_refresh()
		return {"failed": true, "reason": "epoch"}

	var res := _commit_brew(a, b)
	if bool(res.get("failed", true)):
		if String(res.get("reason", "")) == "ingredients":
			# U9 (T11): fail-closed списание — ингредиенты перехвачены другой
			# трассой пока котёл «спал»; ничего не тратим, в сеть не идём.
			status_text = "Ингредиенты не дожили до котла: варка отменена без списания."
		else:
			# manual = не автоплан: осознанная варка обязана дойти до мира.
			# Троттлинг (60 с на пару и 5% «тумана») остаётся только для
			# авто-производства — иначе повторная варка молча не спрашивала бы
			# сервер, а игрок видел бы обычную неудачу и считал это багом.
			var net: Dictionary = g._online._try_net_candidate(a, b, not _auto)
			if bool(net.get("ok", false)):
				status_text = "Туман рассеялся… Мир проверяет пару…"
			else:
				status_text = _candidate_skip_text(String(net.get("reason", "")),
					float(net.get("retry_in", 0.0)))
				g._spirit._companion_react("fail", "")
		Sfx.error()
		Input.vibrate_handheld(20)
		if _cauldron != null:
			_cauldron.trigger_flash(Color(0.55, 0.6, 0.68))
	else:
		var output := String(res["output"])
		var newly_learned := bool(res["newly_learned"])
		if newly_learned:
			if _auto:
				_auto_new.append(output)
				status_text = "…открыт рецепт: %s" % g._online._item_name(output)
			else:
				status_text = "НОВЫЙ РЕЦЕПТ: %s!" % g._online._item_name(output)
				Input.vibrate_handheld(45)
				if _cauldron != null:
					_cauldron.trigger_flash(g._item_colors.get(output, Color.WHITE))
				var ml: Array = res.get("milestones", [])
				g._show_discovery_popup(output, a, b, ml)
				g._spirit._companion_react_discovery(output)
				g._spirit._companion_gain(2)
		else:
			status_text = "Успех: %s +1." % g._online._item_name(output)
			g._spirit._companion_react("success_known", g._online._item_name(output))
			g._spirit._companion_gain(1)
			if _cauldron != null:
				_cauldron.trigger_flash(g._item_colors.get(output, Color.WHITE))
			if not _auto:
				Sfx.divide()
				Input.vibrate_handheld(20)
				g._online._floater_at(_cauldron.get_global_rect().get_center(), "+%s" % g._online._item_name(output),
					g._item_colors.get(output, Color.WHITE))
	if g._spirit._companion != null:
		g._spirit._companion.set_shake(false)
		g._spirit._companion_apply_level()
	selected.clear()
	_slot_a.set_slot("", Color.WHITE)
	_slot_b.set_slot("", Color.WHITE)
	brewing = false
	if _progress != null:
		_progress.value = 100.0
	_refresh()
	g._saves._save_game()
	return res

func _repeat_last() -> void:
	if brewing or _last_pair.size() != 2:
		return
	var a := String(_last_pair[0])
	var b := String(_last_pair[1])
	if not g._online._has_ingredients(a, b):
		status_text = "Для повтора не хватает ингредиентов: %s + %s." % [g._online._item_name(a), g._online._item_name(b)]
		Sfx.error()
		_refresh()
		return
	selected = [a, b]
	_refresh()
	status_text = "Повтор: %s + %s. Жми «ВАРИТЬ»." % [g._online._item_name(a), g._online._item_name(b)]
	Sfx.click()

func _reset_slots() -> void:
	if brewing or _auto:
		return
	selected.clear()
	_slot_a.set_slot("", Color.WHITE)
	_slot_b.set_slot("", Color.WHITE)
	status_text = "Лунки очищены."
	Sfx.click()
	_refresh()


func _stop_auto() -> void:
	if not _auto:
		return
	_auto_cancel = true
	status_text = "Автоварка: остановлю после текущего шага…"
	Sfx.click()
# ================= refresh =================

func _refresh() -> void:
	if g._item_colors.is_empty():
		g._online._init_colors()
	_refresh_header()
	# статус
	if _status_label != null:
		_status_label.text = status_text
	# орбы
	for raw_id in _item_orbs:
		var item_id := String(raw_id)
		var orb: ElementOrb = _item_orbs[item_id]
		var stock := int(inventory.get(item_id, 0))
		var has := inventory.has(item_id)
		var changed := orb.count != stock or orb.discovered != has
		orb.count = stock
		orb.discovered = has
		var reserved := selected.count(item_id)
		var available := has and stock > reserved
		var mod := Color(1, 1, 1, 0.45 if not available else 1.0)
		if orb.modulate != mod:
			orb.modulate = mod
			changed = true
		var vis := g._online._matches_search(item_id)
		if orb.visible != vis:
			orb.visible = vis
			changed = true
		var cell := _item_cells.get(item_id) as Control
		if cell != null and cell.visible != vis:
			cell.visible = vis
		if changed:
			if has:
				var rar := _rarity_of(item_id)
				orb.tooltip_text = "%s ×%d — %s · %s" % [g._online._item_name(item_id), stock, g._online._item_desc(item_id), rar["name"]]
			else:
				orb.tooltip_text = "Скрыто туманом — свари что-нибудь новое"
			orb.queue_redraw()
	for raw_id in _source_orbs:
		var orb: ElementOrb = _source_orbs[String(raw_id)]
		var n := int(inventory.get(String(raw_id), 0))
		if orb.count != n:
			orb.count = n
			orb.queue_redraw()
	# лунки в синхроне с selected + цвет зелья в котле
	if selected.is_empty():
		_slot_a.set_slot("", Color.WHITE)
		_slot_b.set_slot("", Color.WHITE)
		_cauldron.clear_mixture()
	elif selected.size() == 1:
		_slot_a.set_slot(selected[0], g._item_colors.get(selected[0], Color.WHITE))
		_slot_b.set_slot("", Color.WHITE)
		_cauldron.clear_mixture()
	else:
		_slot_a.set_slot(selected[0], g._item_colors.get(selected[0], Color.WHITE))
		_slot_b.set_slot(selected[1], g._item_colors.get(selected[1], Color.WHITE))
		_cauldron.set_mixture(g._item_colors.get(selected[0], Color.WHITE),
			g._item_colors.get(selected[1], Color.WHITE))
	# книга и цепочки пересобираются только когда изменился набор веществ/рецептов
	# или запрос поиска — иначе это пустая трата времени на каждый клик
	var sig := known_recipes.size() * 100000 + inventory.size()
	var q := g._online._search_query()
	if sig != _book_sig or q != _book_q:
		_book_sig = sig
		_book_q = q
		_refresh_book()
		g._online._refresh_chains()
	g._pages._ensure_modes()
	g._pages._refresh_mode_pages()
	g._update_brew_bar_visibility()

func _refresh_header() -> void:
	if not is_instance_valid(_ether_label):
		return
	_ether_label.text = "⚡%d/%d · рез:%d · +%.1f/с" % [ether, _max_ether(), ether_overflow, _ether_rate()]
	var nxt := _next_milestone(inventory.size())
	var atlas := ""
	if nxt > 0:
		atlas = "   ·   Атлас: награда на %d" % nxt
	_collection_label.text = "Веществ открыто: %d / %d   ·   Рецептов: %d / %d%s" % [
		inventory.size(), g.ITEMS.size(), known_recipes.size(), g.RECIPES.size(), atlas]
	g._guild._orders_refresh()
	g._guild._refresh_quest_label()
	if g._hub._up_btn != null:
		var affordable := 0
		for u in Game.UPGRADES:
			var uid := String(u["id"])
			if _up_unlocked(uid) and _up_lvl(uid) < int(u["max"]) and _available_ether() >= _up_cost(uid):
				affordable += 1
		# Смысл «улучшений» несёт иконка trend_up (main._build_ui), в тексте —
		# только счётчик. Без импортированной иконки — прежний глиф «▲».
		if g._hub._up_btn.icon != null:
			g._hub._up_btn.text = "" if affordable == 0 else str(affordable)
		else:
			g._hub._up_btn.text = "▲" if affordable == 0 else "▲%d" % affordable
		g._hub._up_btn.add_theme_color_override("font_color",
			Color(1.0, 0.88, 0.45) if affordable > 0 else Color(0.8, 0.85, 0.9))

func _refresh_book() -> void:
	if _book_list == null:
		return
	for child in _book_list.get_children():
		_book_list.remove_child(child)
		child.queue_free()
	if _book_stats != null:
		_book_stats.text = "Варок: %d   ·   Успешных: %d" % [attempts, successes]
	for recipe in g.RECIPES:
		var a := String(recipe["a"])
		var b := String(recipe["b"])
		var out := String(recipe["out"])
		if not known_recipes.has(g._pair_key(a, b)):
			continue
		if not (g._online._matches_search(out) or g._online._matches_search(a) or g._online._matches_search(b)):
			continue
		var row := _auto_row(a, b, out)
		_book_list.add_child(row)

func _auto_row(a: String, b: String, out: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 15)
	var r := _rarity_of(out)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.9)
	sb.set_corner_radius_all(14)
	var rc: Color = r["color"]
	sb.border_color = Color(rc.r, rc.g, rc.b, 0.55)
	sb.set_border_width_all(1)
	var sb_h: StyleBoxFlat = sb.duplicate()
	sb_h.bg_color = Color(0.13, 0.18, 0.25, 1)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_auto_craft.bind(out))

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)

	hb.add_child(_mini_orb(a, 40))
	var plus := g._label("+", 15)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(plus)
	hb.add_child(_mini_orb(b, 40))
	var arrow := g._label("→", 19)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.add_theme_color_override("font_color", Color(0.5, 0.9, 0.85))
	hb.add_child(arrow)
	hb.add_child(_mini_orb(out, 40))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(150, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := g._label(g._online._item_name(out), 14)
	nm.add_theme_color_override("font_color", g._item_colors.get(out, Color.WHITE).lightened(0.25))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var sub_txt := "%s + %s · %s" % [g._online._item_name(a), g._online._item_name(b), String(r["name"])]
	var cat := String(Game.CATEGORY_OF.get(out, ""))
	if cat != "":
		sub_txt += " · %s" % g._progress_ui._cat_title(cat)
	var sub := g._label(sub_txt, 10)
	if int(r["tier"]) >= 1:
		sub.add_theme_color_override("font_color", Color(r["color"]).lightened(0.15))
	else:
		sub.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	hb.add_child(col)
	return btn

func _mini_orb(item_id: String, px: int) -> ElementOrb:
	var orb := ElementOrb.new()
	orb.interactive = false
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.custom_minimum_size = Vector2(px, px)
	orb.setup(item_id, g._item_colors.get(item_id, Color(0.5, 0.6, 0.7)), true, g._online._item_glyph(item_id))
	return orb
# ================= автоварка: планировщик =================

func _cost_of(item_id: String) -> int:
	# минимальное число базовых стихий для производства (по известным рецептам)
	if _cost_cache.has(item_id):
		return int(_cost_cache[item_id])
	if item_id in Game.BASE_IDS:
		_cost_cache[item_id] = 1
		return 1
	_cost_cache[item_id] = 1 << 29  # защита от циклов
	var best := 1 << 29
	for r in g.RECIPES:
		if String(r["out"]) != item_id:
			continue
		if not known_recipes.has(g._pair_key(String(r["a"]), String(r["b"]))):
			continue
		var c := _cost_of(String(r["a"])) + _cost_of(String(r["b"]))
		if c < best:
			best = c
	_cost_cache[item_id] = best
	return best

func _layer_of(item_id: String) -> int:
	# слой сложности для порядка варки (дети раньше родителей)
	if _layer_cache.has(item_id):
		return int(_layer_cache[item_id])
	if item_id in Game.BASE_IDS:
		_layer_cache[item_id] = 0
		return 0
	# защита от циклов (серверные рецепты могут замкнуть граф): сеем sentinel,
	# как в _cost_of; если слой не вычислялся — снимем ниже (политику «недостижимость
	# не кэшируем» сохраняем).
	_layer_cache[item_id] = 1 << 29
	var l := 1 << 29
	for r in g.RECIPES:
		if String(r["out"]) != item_id:
			continue
		if not known_recipes.has(g._pair_key(String(r["a"]), String(r["b"]))):
			continue
		l = mini(l, maxi(_layer_of(String(r["a"])), _layer_of(String(r["b"]))) + 1)
	# «недостижимость» НЕ кэшируем: иначе после открытия рецепта слой останется
	# устаревшим sentinel'ом и сломает порядок автоварки (дефект: пролаги/сбой плана)
	if l < (1 << 29):
		_layer_cache[item_id] = l
	else:
		_layer_cache.erase(item_id)
	return l

func _rarity_of(item_id: String) -> Dictionary:
	# редкость вещества из слоя; награда за первое открытие растёт с глубиной
	var layer := _layer_of(item_id)
	if g._online._server_layers.has(item_id):
		layer = int(g._online._server_layers[item_id])
	if layer <= 0:
		return {"tier": 0, "name": "первостихия", "color": Color(0.60, 0.65, 0.70), "bounty": 0}
	if layer <= 2:
		return {"tier": 1, "name": "обычное", "color": Color(0.72, 0.78, 0.83), "bounty": 6}
	if layer <= 4:
		return {"tier": 2, "name": "редкое", "color": Color(0.36, 0.62, 0.95), "bounty": 12}
	if layer == 5:
		return {"tier": 3, "name": "эпическое", "color": Color(0.74, 0.45, 0.95), "bounty": 25}
	return {"tier": 4, "name": "легендарное", "color": Color(0.98, 0.80, 0.20), "bounty": 45}

func _milestone_reward(count: int) -> int:
	return int(Game.MILESTONE_REWARDS.get(count, 0))

func _milestone_boost(count: int) -> String:
	match count:
		20: return "regen1"
		40: return "cap50"
		57: return "regen2"
		_: return ""

func _milestone_text(count: int) -> String:
	var txt := "ВЕХА АТЛАСА: %d веществ · +%d ⚡" % [count, _milestone_reward(count)]
	match _milestone_boost(count):
		"regen1": txt += " · +0.50 ⚡/с навсегда"
		"cap50": txt += " · +50 к капу эфира"
		"regen2": txt += " · +0.75 ⚡/с, титул Архимаг"
	return txt

func _next_milestone(count: int) -> int:
	for m in Game.MILESTONES:
		if count < int(m):
			return int(m)
	return 0

func _collection_regen_bonus() -> float:
	var b := 0.0
	if _milestones_done.has(20):
		b += 0.5
	if _milestones_done.has(57):
		b += 0.75
	return b

func _collection_cap_bonus() -> int:
	return 50 if _milestones_done.has(40) else 0

func _check_milestones() -> Array:
	# начисляет награды за пройденные вехи; вернёт список новых вех
	var crossed: Array = []
	if g._selftest:
		return crossed
	var count := inventory.size()
	for m in Game.MILESTONES:
		var mi := int(m)
		if count >= mi and not _milestones_done.has(mi):
			crossed.append(mi)
	for m in crossed:
		var mi := int(m)
		_milestones_done[mi] = true
		_grant_ether(_milestone_reward(mi), "atlas_milestone")
		g._spirit._companion_react("milestone", str(mi))
		if _milestone_boost(mi) == "regen2":
			Sfx.legendary()
		else:
			Sfx.divide()
	if not crossed.is_empty():
		g._saves._save_game()
	return crossed

func _grant_first_open(slug: String) -> Array:
	# награда за первое появление вещества в инвентаре; вернёт новые вехи
	_first_open_calls += 1  # U11 (T15): см. комментарий у поля
	if g._selftest or not g.ITEMS.has(slug):
		return []
	_layer_cache.erase(slug)
	var r := _rarity_of(slug)
	var b := int(r["bounty"])
	if b > 0:
		_grant_ether(b, "first_discovery")
	var t := int(r["tier"])
	if t >= 2:
		g._guild._quest_tier[t] = int(g._guild._quest_tier.get(t, 0)) + 1
	var crossed := _check_milestones()
	g._guild._quest_on_state()
	return crossed
# ---------- запуск автоварки ----------

func _auto_craft(item_id: String) -> void:
	# тап по рецепту: посчитать, показать расход, по подтверждению — варить
	if brewing or _auto or (g._confirm != null and g._confirm.visible):
		return
	if not _craft_job.is_empty() and String(_craft_job.get("item", "")) != item_id:
		status_text = "Сначала продолжи или останови Производство для «%s»." % g._online._item_name(String(_craft_job.get("item", "")))
		Sfx.error()
		_refresh()
		return
	var plan := g._guild._plan_craft(item_id)
	if not bool(plan.get("ok", false)):
		var frontier := g._guild._plan_known_frontier(item_id)
		var frontier_rows: Array = frontier.get("frontier", [])
		if not frontier_rows.is_empty():
			var f: Dictionary = frontier_rows[0]
			status_text = "Нужно открыть: %s + %s (через Эксперимент)" % [
				g._online._item_name(String(f.get("a", ""))), g._online._item_name(String(f.get("b", "")))]
		else:
			status_text = "Автоварка: %s" % String(plan.get("reason", "невозможно"))
		Sfx.error()
		_refresh()
		return
	var route_discount := Game.BLUEPRINT_DISCOUNT if _blueprints.has(item_id) else 1.0
	var ether_need := _plan_ether_cost(plan, -1, route_discount)
	var stage_preview := mini(_stage_ops(), int(plan.get("total", 0)))
	var stage_cost_preview := _plan_ether_cost(plan, stage_preview, route_discount)
	Analytics.track("craft_plan_preview", {
		"target": item_id, "operations": int(plan.get("total", 0)),
		"stage_operations": stage_preview, "total_ether": ether_need,
		"stage_ether": stage_cost_preview, "available_ether": _available_ether(),
		"cap": _max_ether(), "blueprint": _blueprints.has(item_id),
	})
	if int(plan.get("total", 0)) > Game.CRAFT_PLAN_HARD_LIMIT_OPERATIONS:
		status_text = "Цепочка слишком длинная для локального плана (%d операций). Открой ближайший узел через Эксперимент." % int(plan["total"])
		Sfx.error()
		_refresh()
		return
	var stage_limit := mini(_stage_ops(), int(plan.get("total", 0)))
	var stage_cost := _plan_ether_cost(plan, stage_limit, route_discount)
	_pending_item = item_id
	_pending_plan = plan
	g._confirm_orb.setup(item_id, g._item_colors.get(item_id, Color.WHITE), true, g._online._item_glyph(item_id))
	g._confirm_l1.text = g._online._item_name(item_id)
	g._confirm_l2.text = _base_spend_text(plan)
	var warning_note := "⚠ длинная цепочка · " if int(plan["total"]) >= Game.CRAFT_PLAN_WARNING_OPERATIONS else ""
	var blueprint_note := ""
	if _blueprints.has(item_id):
		blueprint_note = "Чертёж: −%d%% · " % [int(round((1.0 - Game.BLUEPRINT_DISCOUNT) * 100.0))]
	g._confirm_l3.text = "%s%sВарок: %d · всего эфир: %d · сейчас этап: %d ⚡ · можно продолжить позже" % [
		warning_note, blueprint_note, int(plan["total"]), ether_need, stage_cost]
	g._confirm_dim.visible = true
	g._confirm.visible = true
	Sfx.click()

func _record_blueprint(item_id: String, plan: Dictionary) -> void:
	if item_id == "" or plan.is_empty():
		return
	_blueprints[item_id] = {
		"version": 1,
		"item": item_id,
		"operations": int(plan.get("total", 0)),
		"plan": plan.duplicate(true),
		"discount": Game.BLUEPRINT_DISCOUNT,
		"created_at": Time.get_unix_time_from_system(),
	}

func _base_spend_text(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	for raw in Game.BASE_IDS:
		var id2 := String(raw)
		if plan["base_add"].has(id2):
			parts.append("%s ×%d" % [g._online._item_name(id2), int(plan["base_add"][id2])])
	if parts.is_empty():
		return "Все ингредиенты возьмутся из запаса."
	return "Нужно добыть из источников: %s" % " · ".join(parts)

func _on_confirm_brew() -> void:
	var item := _pending_item
	var plan: Dictionary = _pending_plan
	g._hide_confirm()
	if not plan.is_empty():
		_run_auto_plan(item, plan)

func _run_auto_plan(item_id: String, plan: Dictionary) -> bool:
	# U9 (T11): автоплан — часть единого мьютекса потребляющих трасс.
	if brewing or _auto or g._pages._bench_busy:
		status_text = "Котёл занят: дождись завершения текущей варки или производства."
		Sfx.error()
		_refresh()
		return false
	var total := int(plan.get("total", 0))
	if total <= 0:
		return false
	var route_discount := Game.BLUEPRINT_DISCOUNT if _blueprints.has(item_id) else 1.0
	var resuming_job := not _craft_job.is_empty() and String(_craft_job.get("item", "")) == item_id
	if not resuming_job:
		_craft_job = {
			"item": item_id,
			"started_at": Time.get_unix_time_from_system(),
			"completed": 0,
			"total_estimate": total,
			"plan": plan.duplicate(true),
			"total_cost": _plan_ether_cost(plan, -1, route_discount),
			"discount": route_discount,
			"status": "running",
		}
	if resuming_job:
		Analytics.track("craft_job_resume", {
			"target": item_id, "completed": int(_craft_job.get("completed", 0)),
			"total": int(_craft_job.get("total_estimate", total)),
			"status": String(_craft_job.get("status", "paused")),
		})
	else:
		Analytics.track("craft_job_start", {
			"target": item_id, "operations": total,
			"total_ether": int(_craft_job.get("total_cost", 0)),
			"blueprint": _blueprints.has(item_id),
		})
		if _blueprints.has(item_id):
			Analytics.track("craft_job_repeat", {"target": item_id, "discount": route_discount})
	var job_plan: Dictionary = _craft_job.get("plan", plan)
	var total_estimate := maxi(total, int(_craft_job.get("total_estimate", total)))
	var stage_budget := maxi(1, _stage_ops())
	var stage_cost := _plan_ether_cost(plan, stage_budget, route_discount)
	_production_discount = route_discount
	if stage_cost > 0 and _available_ether() <= 0:
		_craft_job["status"] = "paused_ether"
		Analytics.track("craft_job_pause", {
			"target": item_id, "reason": "ether",
			"completed": int(_craft_job.get("completed", 0)), "required": stage_cost,
		})
		_production_discount = 1.0
		status_text = "Цепочка сохранена: следующий этап требует около %d ⚡." % stage_cost
		g._saves._save_game()
		_refresh()
		return true
	_auto = true
	_auto_cancel = false
	_auto_new.clear()
	if _auto_stop_btn != null:
		_auto_stop_btn.visible = true
	var steps := 0
	var cancelled := false
	var paused_reason := ""
	for op in plan.get("ops", []):
		if _auto_cancel or steps >= stage_budget:
			cancelled = _auto_cancel
			break
		var a := String(op["a"])
		var b := String(op["b"])
		for _i in int(op["n"]):
			if _auto_cancel or steps >= stage_budget:
				cancelled = _auto_cancel
				break
			var pair_block := _production_pair_block(a, b)
			if pair_block != "":
				paused_reason = pair_block
				break
			var pair_cost := _pair_cost(a, b, route_discount)
			if not g._online._has_ingredients(a, b):
				paused_reason = "ingredients"
				break
			if _available_ether() < pair_cost:
				paused_reason = "ether"
				break
			steps += 1
			selected = [a, b]
			_slot_a.set_slot(a, g._item_colors.get(a, Color.WHITE))
			_slot_b.set_slot(b, g._item_colors.get(b, Color.WHITE))
			var done := int(_craft_job.get("completed", 0))
			var left := maxi(0, total_estimate - done)
			var eta := int(ceilf(left * _brew_time()))
			status_text = "Производство «%s»: этап %d · шаг %d/%d — %s + %s (~%dс)" % [
				g._online._item_name(item_id), ceili(float(done + 1) / float(stage_budget)), done + 1,
				total_estimate, g._online._item_name(a), g._online._item_name(b), eta]
			_refresh()
			var epoch_before := brew_epoch
			var brew_res: Dictionary = await _brew(true)
			if brew_epoch != epoch_before:
				# U9 (T12): мир сброшен под производством — молча выходим,
				# освобождая мьютекс, и не трогаем новый инвентарь.
				_auto = false
				_production_discount = 1.0
				if _auto_stop_btn != null:
					_auto_stop_btn.visible = false
				return false
			if bool(brew_res.get("failed", true)):
				# U9 (T11): упавший шаг не двигает completed; производство
				# встаёт на паузу с причиной отказа, маршрут сохраняется.
				var fail_reason := String(brew_res.get("reason", "recipe"))
				paused_reason = fail_reason if fail_reason in ["ingredients", "ether"] else "recipe"
				break
			_craft_job["completed"] = done + 1
			_craft_job["status"] = "running"
			# Сохраняем после каждой операции, а не только после всего этапа:
			# закрытие приложения не откатывает уже полученные промежуточные items.
			g._saves._save_game()
		if not paused_reason.is_empty() or cancelled:
			break
	_auto = false
	_production_discount = 1.0
	if _auto_stop_btn != null:
		_auto_stop_btn.visible = false
	if cancelled:
		_craft_job["status"] = "paused_user"
		Analytics.track("craft_job_cancel", {
			"target": item_id, "completed": int(_craft_job.get("completed", 0)),
			"total": total_estimate, "kept_intermediates": true,
		})
		status_text = "Цепочка сохранена после остановки: %d/%d операций." % [int(_craft_job.get("completed", 0)), total_estimate]
		Sfx.error()
	elif not paused_reason.is_empty():
		_craft_job["status"] = "paused_" + paused_reason
		Analytics.track("craft_job_pause", {
			"target": item_id, "reason": paused_reason,
			"completed": int(_craft_job.get("completed", 0)), "total": total_estimate,
		})
		var pause_label := "эфир" if paused_reason == "ether" else ("ингредиенты" if paused_reason == "ingredients" else ("рецепт" if paused_reason == "recipe" else "инвентарь"))
		status_text = "Цепочка сохранена: %d/%d операций. Причина паузы: %s." % [
			int(_craft_job.get("completed", 0)), total_estimate, pause_label]
	elif int(_craft_job.get("completed", 0)) < total_estimate:
		_craft_job["status"] = "paused_stage"
		Analytics.track("craft_job_pause", {
			"target": item_id, "reason": "operation_cap",
			"completed": int(_craft_job.get("completed", 0)), "total": total_estimate,
		})
		status_text = "Этап завершён: %d/%d операций. Нажми цель ещё раз, чтобы продолжить." % [
			int(_craft_job.get("completed", 0)), total_estimate]
	else:
		var saved_plan: Dictionary = job_plan if not job_plan.is_empty() else plan
		_record_blueprint(item_id, saved_plan)
		Analytics.track("craft_job_complete", {
			"target": item_id, "operations": total_estimate,
			"blueprint": true, "repeat": resuming_job,
		})
		_craft_job.clear()
		status_text = "Производство завершён: %s +1. Маршрут сохранён как чертёж." % g._online._item_name(item_id)
		if not _auto_new.is_empty():
			var names := PackedStringArray()
			for nid in _auto_new:
				names.append(g._online._item_name(String(nid)))
			g._present_popup(String(_auto_new.back()), "Новые рецепты по пути: " + " · ".join(names))
	_refresh()
	g._saves._save_game()
	return true

func _run_bench_plan(item_id: String, plan: Dictionary) -> bool:
	# фоновая варка верстака: не трогает котёл и не блокирует игрока
	if brewing or _auto or g._pages._bench_busy:
		return false
	var total := int(plan["total"])
	var route_discount := Game.BLUEPRINT_DISCOUNT if _blueprints.has(item_id) else 1.0
	g._pages._bench_busy = true
	_production_discount = route_discount
	_auto_new.clear()
	var st := 0
	var stage_limit := mini(total, _stage_ops())
	for op in plan["ops"]:
		var a := String(op["a"])
		var b := String(op["b"])
		for i in int(op["n"]):
			if st >= stage_limit:
				g._pages._bench_busy = false
				_production_discount = 1.0
				status_text = "Производство: этап %d/%d завершён — продолжу через %d с." % [st, total, int(g._sigil.bench_interval(item_id))]
				_refresh()
				g._saves._save_game()
				return true
			var pair_block := _production_pair_block(a, b)
			if pair_block != "" or not g._online._has_ingredients(a, b) or _available_ether() < _pair_cost(a, b, route_discount):
				g._pages._bench_busy = false
				_production_discount = 1.0
				var bench_reason := "рецепт" if pair_block == "recipe" else ("инвентарь" if pair_block == "inventory" else ("ингредиенты" if not g._online._has_ingredients(a, b) else "эфир"))
				status_text = "Верстак остановился: %s; продолжит с этого места." % bench_reason
				_refresh()
				return false
			st += 1
			status_text = "Верстак варит «%s»: шаг %d/%d — %s + %s…" % [
				g._online._item_name(item_id), st, total, g._online._item_name(a), g._online._item_name(b)]
			_refresh()
			var epoch_before := brew_epoch
			await g.get_tree().create_timer(0.3).timeout
			if brew_epoch != epoch_before:
				# U9 (T12): мир сброшен посреди шага верстака — молча выходим
				# без коммита/списания, освобождая мьютекс.
				g._pages._bench_busy = false
				_production_discount = 1.0
				return false
			var res := _commit_brew(a, b)
			if bool(res.get("failed", true)):
				# U9 (T11): fail-closed списание — верстак останавливается,
				# маршрут продолжит с этого места позже.
				g._pages._bench_busy = false
				_production_discount = 1.0
				var commit_reason := String(res.get("reason", ""))
				var stop_label := "ингредиенты" if commit_reason == "ingredients" \
					else ("эфир" if commit_reason == "ether" else "рецепт")
				status_text = "Верстак остановился: %s; продолжит с этого места." % stop_label
				_refresh()
				g._saves._save_game()
				return false
			g._saves._save_game()
			if bool(res.get("newly_learned", false)):
				_auto_new.append(String(res["output"]))
	g._pages._bench_busy = false
	_production_discount = 1.0
	_record_blueprint(item_id, plan)
	status_text = "Верстак завершил: %s +1 (шагов: %d)." % [g._online._item_name(item_id), total]
	if not _auto_new.is_empty():
		var names := PackedStringArray()
		for nid in _auto_new:
			names.append(g._online._item_name(String(nid)))
		g._present_popup(String(_auto_new.back()), "Новые рецепты по пути: " + " · ".join(names))
	_refresh()
	g._saves._save_game()
	return true

func _commit_brew(a: String, b: String) -> Dictionary:
	var recipe := g._online._find_recipe(a, b)
	var output := String(recipe.get("out", "")) if not recipe.is_empty() else ""
	var first_time := output != "" and not inventory.has(output)
	var brew_cost := Game.BREW_COST
	if first_time:
		brew_cost += _discovery_fee_for_layer(_content_layer(output))
	brew_cost = maxi(1, int(round(float(brew_cost) * _production_discount)))
	# U9 (T11): повторная проверка прямо перед списанием (fail-closed): между
	# гейтом трассы и этим моментом лежат await, за которые ингредиенты мог
	# съесть другой потребитель. Не хватает — выходим без списания реагентов
	# И без траты эфира (коммит атомарен с этой проверки).
	if not g._online._has_ingredients(a, b):
		return {"failed": true, "output": "", "newly_learned": false, "reason": "ingredients"}
	if not _spend_ether(brew_cost):
		return {"failed": true, "output": "", "newly_learned": false, "reason": "ether"}
	inventory[a] = int(inventory[a]) - 1
	inventory[b] = int(inventory[b]) - 1
	attempts += 1
	g._riddles._letter_attempt(a, b)
	g._riddles._atlas_attempt(a, b)
	if recipe.is_empty():
		_grant_ether(Game.FAILURE_REFUND, "failed_brew")
		Analytics.track("combine_try", {"left": a, "right": b, "result": "fail", "source": "recipe"})
		return {"failed": true, "output": "", "newly_learned": false}
	var key := g._pair_key(a, b)
	var newly_learned := not known_recipes.has(key)
	known_recipes[key] = true
	inventory[output] = int(inventory.get(output, 0)) + 1
	_layer_cache.erase(output)
	successes += 1
	g._retention._circle_on_discovery(first_time)
	g._retention._circle_on_local_brew(output)
	var milestones: Array = []
	if first_time:
		milestones = _grant_first_open(output)
		if not g._selftest:
			g._hub._log_event("Открыто вещество «%s»" % g._online._item_name(output))
	if output == "spark":
		g._spirit._companion_unlock()
	g._guild._quest_on_brew(output)
	g._retention._fair_report_brew(a, b)
	g._retention._fair_on_brew(output)
	# план 2 §3.3.1: варка серверно-известной пары = личное открытие (офлайн —
	# уйдёт в pending_server, онлайн — зарегистрируется сразу).
	g._retention._vein_report_pair(a, b, output)
	# §2.4: очки цели — по факту успеха и фактического слоя; заявка снимается
	# только здесь (отмена/провал не платят и не сгорают молча — она сбросится
	# следующим успешным путём или новой модалкой).
	g._retention._circle_on_goal_brew(output)
	Analytics.track("combine_try", {"left": a, "right": b, "result": "new" if newly_learned else "known", "output": output, "source": "recipe"})
	return {"failed": false, "output": output, "newly_learned": newly_learned, "milestones": milestones}
