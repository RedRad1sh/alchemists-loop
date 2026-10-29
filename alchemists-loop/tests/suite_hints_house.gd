extends RefCounted
class_name SuiteHintsHouse
# бонусы/намёки/дом/светляк (оп B1).

static func run(g: Game) -> void:
	# постоянные бонусы прогрессии
	var _cap_before := g._engine._max_ether()
	var _rate_before := g._engine._ether_rate()
	g._guild._quests_done["test_q"] = true
	Selftest.check("quest cap bonus", g._engine._max_ether() == _cap_before + Game.QUEST_CAP)
	Selftest.check("quest regen bonus", absf(g._engine._ether_rate() - (_rate_before + Game.QUEST_REGEN * g._engine._sage_multiplier())) < 0.001)
	g._guild._quests_done.erase("test_q")
	var _cap_b2 := g._engine._max_ether()
	g._progress_ui._ach_done["test_a"] = true
	Selftest.check("ach cap bonus", g._engine._max_ether() == _cap_b2 + Game.ACH_CAP)
	Selftest.check("ach regen bonus", absf(g._engine._ether_rate() - (_rate_before + Game.ACH_REGEN * g._engine._sage_multiplier())) < 0.001)
	g._progress_ui._ach_done.erase("test_a")
	Selftest.check("achievement requirement text", g._progress_ui._ach_requirement({"kind": "items", "param": 6}) != "")

	# намёк не должен «умирать»: даже если все рецепты из запаса открыты
	g._engine.known_recipes.clear()
	for r in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(r["a"]), String(r["b"]))] = true
	g._engine.inventory.clear()
	g._engine.inventory["fire"] = 3
	g._engine.inventory["water"] = 3
	var _hc := g._pages._hint_candidates()
	Selftest.check("hint never empty with stock", not _hc.is_empty())
	g._engine.inventory.clear()
	var _hc0 := g._pages._hint_candidates()
	Selftest.check("hint empty without any stock", _hc0.is_empty())

	# v22: намёки не предлагают пары, уже отвергнутые сервером
	g._engine.known_recipes.clear()
	g._engine.inventory.clear()
	g._engine.inventory["fire"] = 3
	g._engine.inventory["water"] = 3
	g._engine.inventory["earth"] = 3
	g._engine._rejected_pairs.clear()
	var _h_a := g._pages._hint_candidates()
	Selftest.check("hint has unknown pairs", _h_a.size() >= 2)
	var _pk_a := g._pair_key(String(_h_a[0]["a"]), String(_h_a[0]["b"]))
	g._engine._rejected_pairs[_pk_a] = true
	var _h_b := g._pages._hint_candidates()
	var _gone := true
	for c in _h_b:
		if g._pair_key(String(c["a"]), String(c["b"])) == _pk_a:
			_gone = false
	Selftest.check("hint excludes rejected pair", _gone)
	g._engine._rejected_pairs.clear()

	g._engine.known_recipes.clear()

	# дом Светика: траты и обстановка; не загрязняем следующую сюиту наградами.
	var house_before := {}
	for key in ["_cosmetic_house", "_cosmetic_theme", "_cosmetic_aura", "_theme_custom_on",
			"_aura_custom_on", "house_unlocked", "house_placements", "house_tasks_done"]:
		var value: Variant = g._home.get(key)
		house_before[key] = value.duplicate(true) if value is Array else value
	var ether_before := g._engine.ether
	var overflow_before := g._engine.ether_overflow
	var status_before := g._engine.status_text
	var companion_before := {}
	for key in ["_companion_unlocked", "_companion_affinity", "_companion_level", "_companion_idle_clock"]:
		companion_before[key] = g._spirit.get(key)
	var house_save_frozen := g._saves._save_frozen
	g._saves._save_frozen = true
	g._spirit._companion_unlocked = false
	g._engine.ether_overflow = 0
	g._engine.ether = 2000
	var _eth0 := g._engine.ether
	g._home._cosmetic_theme = "cobalt"
	g._home._cosmetic_aura = "amber"
	g._home._theme_custom_on = false
	g._home._aura_custom_on = false
	g._home._cosmetic_house = false
	g._home.house_unlocked.clear()
	g._home.house_placements.clear()
	g._home.house_tasks_done.clear()
	Selftest.check("theme color cobalt", g._home._theme_color("cobalt") == Color("#0d1219"))
	Selftest.check("theme color ember", g._home._theme_color("ember") == Color("#1a0e0e"))
	Selftest.check("aura color amber", g._home._aura_color("amber") == Color("#ffb85c"))
	Selftest.check("aura color rose", g._home._aura_color("rose") == Color("#ff8fb3"))
	g._home._buy_theme("ember", 120)
	Selftest.check("buy theme applies", g._home._cosmetic_theme == "ember" and g._engine.ether == _eth0 - 120)
	g._home._buy_theme("ember", 120)
	Selftest.check("buy theme idempotent", g._home._cosmetic_theme == "ember" and g._engine.ether == _eth0 - 120)
	g._home._buy_aura("aqua", 150)
	Selftest.check("buy aura applies", g._home._cosmetic_aura == "aqua" and g._engine.ether == _eth0 - 270)
	var _rug_cost := HouseItems.price("rug_alt")
	Selftest.check("furniture gated before house", not g._home._buy_house_item("rug_alt") and g._engine.ether == _eth0 - 270)
	g._home._buy_house()
	Selftest.check("buy house applies", g._home._cosmetic_house and g._engine.ether == _eth0 - 270 - Game.HOUSE_COST)
	g._home._buy_house_item("rug_alt")
	Selftest.check("buy furniture applies", g._home.house_unlocked.has("rug_alt") and g._engine.ether == _eth0 - 270 - Game.HOUSE_COST - _rug_cost)
	Selftest.check("buy furniture idempotent", not g._home._buy_house_item("rug_alt") and g._engine.ether == _eth0 - 270 - Game.HOUSE_COST - _rug_cost)
	Selftest.check("decor category", HouseItems.items_in_cat("rug").size() == 2)
	Selftest.check("decor lookup", HouseItems.get_item("rug")["label"] == "Тканый ковёр" and HouseItems.price("bed") == 250)
	Selftest.check("house json shape", g._home._house_json().get("v", 0) == 2
		and g._home._house_json().has("items")
		and g._home._house_json().get("built", false) == g._home._cosmetic_house)
	Selftest.check("challenge requirement text", g._progress_ui._ach_requirement({"kind": "challenge", "param": 3}) == "Выполни цель дня 3 раз(а)")
	# Светик пробуждается от первой Искры; до этого подсказок нет
	var _unl0 := g._spirit._companion_unlocked
	g._spirit._companion_unlocked = false
	Selftest.check("hint gated before unlock", g._pages._hint() == false)
	g._spirit._companion_unlock()
	Selftest.check("companion unlock", g._spirit._companion_unlocked)
	g._spirit._companion_unlock()
	Selftest.check("companion unlock idempotent", g._spirit._companion_unlocked)
	g._spirit._companion_unlocked = _unl0
	for key in house_before:
		g._home.set(key, house_before[key])
	for key in companion_before:
		g._spirit.set(key, companion_before[key])
	g._engine.ether = ether_before
	g._engine.ether_overflow = overflow_before
	g._engine.status_text = status_before
	g._home._apply_cosmetic()
	g._home._refresh_house_screen()
	g._spirit._refresh_companion_visible()
	g._saves._save_frozen = house_save_frozen
	g._engine.known_recipes.clear()

	# серверные элементы/рецепты переживают перезагрузку
	g._online._restore_server_elements({"__st_srv": {"name": "ТестСервер", "color": "#123456", "g": "fire", "d": "Лор"}})
	Selftest.check("server element restore", g.ITEMS.has("__st_srv") and String(g.ITEMS["__st_srv"]["name"]) == "ТестСервер")
	g._online._restore_server_recipes([{"a": "__st_a", "b": "__st_b", "out": "__st_srv"}])
	Selftest.check("server recipe restore", not g._online._find_recipe("__st_a", "__st_b").is_empty())
	g._online._restore_server_elements({})
	g._online._restore_server_recipes([])

	# ============ U13 (T17): анти-спам кнопок траты ============
	# Гейты чистые (часы параметром) — окно проверяется без реального кадра; затем
	# живой двойной тап по _hint: одно списание на два нажатия.
	var u13_ether := g._engine.ether
	var u13_overflow := g._engine.ether_overflow
	var u13_inv := g._engine.inventory.duplicate(true)
	var u13_known := g._engine.known_recipes.duplicate(true)
	var u13_brewing := g._engine.brewing
	var u13_auto := g._engine._auto
	var u13_status := g._engine.status_text
	var u13_exp_pair := g._engine._experiment_pending_pair.duplicate()
	var u13_unlocked := g._spirit._companion_unlocked
	var u13_idle := g._spirit._companion_idle_clock
	var u13_filter := g._pages._experiment_filter
	var u13_hint_ids := g._pages._experiment_hint_ids.duplicate()
	var u13_exp_a := g._pages._experiment_a
	var u13_exp_b := g._pages._experiment_b
	var u13_guard := g._pages._spend_guard_ms.duplicate(true)
	var u13_claim_at := g._resonance._res_claim_at
	# _hint уводит табу в эксперимент — снимаем и возвращаем табу/попап, иначе блок
	# оставил бы чужую активную вкладку на все последующие сюиты.
	var u13_tab := g._tabs_ref.current_tab
	var u13_popup := g._popup.visible
	var u13_n_inv := g._engine.inventory.size()
	var u13_n_known := g._engine.known_recipes.size()
	var u13_n_hint_ids := g._pages._experiment_hint_ids.size()
	g._pages._spend_guard_ms.clear()
	g._resonance._res_claim_at = 0
	# свободное окно разрешает трату и взводится, повтор внутри окна отбит, после окна — снова можно
	Selftest.check("u13 spend gate arms", g._pages._spend_gate("hint", 1000))
	Selftest.check("u13 spend gate refuses repeat", not g._pages._spend_gate("hint", 1100))
	Selftest.check("u13 spend gate opens after window", g._pages._spend_gate("hint", 1300))
	# граница окна ровно SPEND_GUARD_MSEC: 249 мс — занято, 250 мс — свободно.
	# Ловит подмену `<` на `<=`, которую шаги 1000/1100/1300 не замечают.
	g._pages._spend_guard_ms.clear()
	Selftest.check("u13 spend gate boundary", g._pages._spend_gate("hint", 1000)
		and not g._pages._spend_gate("hint", 1249) and g._pages._spend_gate("hint", 1250)
		and not g._pages._spend_gate("hint", 1499))
	# свежий ключ не «съедает» тап в первые 250 мс жизни игры (отметка стартует с
	# -SPEND_GUARD_MSEC, а не с 0, как _collect_all_ms)
	Selftest.check("u13 spend gate allows first tap at boot", g._pages._spend_gate("boot", 100))
	# ключи независимы: probe не наследует занятую подсказкой отметку
	Selftest.check("u13 spend gate keys independent", g._pages._spend_gate("probe", 1100)
		and not g._pages._spend_gate("probe", 1200))
	g._pages._spend_guard_ms.clear()
	g._spirit._companion_unlocked = true
	g._engine.brewing = false
	g._engine._auto = false
	g._engine._experiment_pending_pair.clear()
	g._engine.known_recipes.clear()
	g._engine.ether = 200
	# невакуумность: кандидатов хватает и на второй тап, значит false даёт только гейт
	Selftest.check("u13 hint candidates leave room", g._pages._hint_candidates().size() >= 2)
	var u13_avail0 := g._engine.ether + g._engine.ether_overflow
	Selftest.check("u13 first hint pays", g._pages._hint()
		and g._engine.ether + g._engine.ether_overflow == u13_avail0 - Game.HINT_COST)
	var u13_ids1 := g._pages._experiment_hint_ids.duplicate()
	var u13_status1 := g._engine.status_text
	# второй тап в этом же кадре: молча, без списания и без перезаписи подсветки
	Selftest.check("u13 second hint in same frame spends nothing", not g._pages._hint()
		and g._engine.ether + g._engine.ether_overflow == u13_avail0 - Game.HINT_COST
		and g._engine.status_text == u13_status1 and g._pages._experiment_hint_ids == u13_ids1)
	# restore: мир после блока — ровно как до него; снятые окна не должны отбить
	# тап позднего сюжета (Time.get_ticks_msec() монотонна)
	g._engine.ether = u13_ether
	g._engine.ether_overflow = u13_overflow
	g._engine.inventory = u13_inv
	g._engine.known_recipes = u13_known
	g._engine.brewing = u13_brewing
	g._engine._auto = u13_auto
	g._engine.status_text = u13_status
	g._spirit._companion_unlocked = u13_unlocked
	g._spirit._companion_idle_clock = u13_idle
	g._pages._experiment_filter = u13_filter
	g._pages._experiment_a = u13_exp_a
	g._pages._experiment_b = u13_exp_b
	g._pages._spend_guard_ms = u13_guard
	g._pages._spend_guard_ms.erase("hint")
	g._resonance._res_claim_at = u13_claim_at
	g._tabs_ref.current_tab = u13_tab
	if not u13_popup:
		g._hide_popup()
	g._engine._experiment_pending_pair.clear()
	for u13_raw_p in u13_exp_pair:
		g._engine._experiment_pending_pair.append(String(u13_raw_p))
	g._pages._experiment_hint_ids.clear()
	for u13_raw_h in u13_hint_ids:
		g._pages._experiment_hint_ids.append(String(u13_raw_h))
	Selftest.check("u13 state restored", g._engine.ether == u13_ether
		and g._engine.ether_overflow == u13_overflow and g._engine.brewing == u13_brewing
		and g._engine._auto == u13_auto and g._spirit._companion_unlocked == u13_unlocked
		and g._engine.inventory.size() == u13_n_inv and g._engine.known_recipes.size() == u13_n_known
		and g._pages._experiment_hint_ids.size() == u13_n_hint_ids
		and g._resonance._res_claim_at == u13_claim_at
		and g._tabs_ref.current_tab == u13_tab and g._popup.visible == u13_popup)
	Selftest.check("u13 guards released for later suites", not g._pages._spend_guard_ms.has("hint"))

	# ============ U28 (β): выдача награды идемпотентна и не в эфире ============
	var u28_ether := g._engine.ether
	var u28_house := g._home._cosmetic_house
	var u28_flag_prev := g._spirit._companion_unlocked
	g._spirit._companion_unlocked = true
	var u28_unlocked: Array = g._home.house_unlocked.duplicate()
	var u28_done: Array = g._home.house_tasks_done.duplicate()
	var u28_affinity := g._spirit._companion_affinity
	var u28_level := g._spirit._companion_level
	g._home._cosmetic_house = true
	g._home.house_tasks_done.clear()
	g._home.house_unlocked.clear()
	g._home._complete_house_task(_u28_task("chair_at_table"))
	Selftest.check("b reward grants ownership", g._home.house_unlocked.has("window_guild"))
	Selftest.check("b reward spends no ether", g._engine.ether == u28_ether)
	Selftest.check("b reward marks the task done once", g._home.house_tasks_done == ["chair_at_table"])
	Selftest.check("b gift text names the item, not the category id",
		g._engine.status_text.contains("Витраж гильдии") and not g._engine.status_text.contains("window"))
	g._home._complete_house_task(_u28_task("chair_at_table"))
	Selftest.check("b reward idempotent", g._home.house_tasks_done.size() == 1
		and (g._home.house_unlocked as Array).count("window_guild") == 1)
	g._home.house_tasks_done.clear()
	g._home.house_unlocked = ["window_seal"]
	Selftest.check("b already-owned reward reports no gift",
		g._home._grant_task_reward(_u28_task("plant_by_window")) == "")
	var u28_aff0 := g._spirit._companion_affinity
	g._home._complete_house_task(_u28_task("plant_by_window"))
	Selftest.check("b already-owned reward still completes",
		g._home.house_tasks_done == ["plant_by_window"])
	Selftest.check("b already-owned reward keeps the owned list unchanged",
		g._home.house_unlocked == ["window_seal"])
	Selftest.check("b completion gives affinity, not ether",
		g._spirit._companion_affinity > u28_aff0 and g._engine.ether == u28_ether)
	g._home._cosmetic_house = u28_house
	g._spirit._companion_unlocked = u28_flag_prev
	Selftest.check("b U28 restores the companion flag it found",
		g._spirit._companion_unlocked == u28_flag_prev)
	g._spirit._companion_affinity = u28_affinity
	g._spirit._companion_level = u28_level
	g._home.house_unlocked = u28_unlocked
	g._home.house_tasks_done = u28_done

	# ============ U29 (δ): витрина считает данные, а не выдумывает их ============
	var u29_first := g._progress_ui._ach_world_first
	var u29_inv := g._engine.inventory.duplicate(true)
	g._progress_ui._ach_world_first = 12
	g._engine.inventory.clear()
	# цвет пламени — самое редкое вещество из запаса; без запаса — базовое
	var u29_empty_flame := g._home._showcase_flame_color()
	g._engine.inventory["fire"] = 1
	var u29_flame := g._home._showcase_flame_color()
	Selftest.check("d flame follows the rarest held substance", u29_flame != u29_empty_flame)
	Selftest.check("d bottle count caps at 9", g._home._showcase_bottles() == 9)
	g._progress_ui._ach_world_first = 3
	Selftest.check("d bottle count follows world-firsts", g._home._showcase_bottles() == 3)
	g._progress_ui._ach_world_first = 0
	Selftest.check("d no world-firsts means no bottles", g._home._showcase_bottles() == 0)
	# окно честно: без связи — заглушка, а не вчерашняя цель
	var u29_nick := g._online._net_nick
	var u29_hint := g._contracts._day_hint
	g._online._net_nick = ""
	g._contracts._day_hint = "Лодка"
	Selftest.check("d window says so offline", g._home._showcase_window_caption().contains("после связи"))
	g._online._net_nick = "Варда"
	Selftest.check("d window shows the world goal", g._home._showcase_window_caption() == "мир: Лодка")
	g._online._net_nick = u29_nick
	g._contracts._day_hint = u29_hint
	g._progress_ui._ach_world_first = u29_first
	g._engine.inventory = u29_inv
	# Витрина гостя теперь плашка реального RoomView, без legacy-вида.
	g._home._apply_player_house("Варда", {"v": 2, "built": true, "items": [], "world_first": 4})
	Selftest.check("d guest showcase data applied", g._home._host_showcase_lbl.text.begins_with("Колбы: 4"))

	# ============ U30 (γ): недельный подарок хосту — из серверного числа, не из тапа ============
	var u30_week := g._home.house_gift_week
	var u30_count := g._home.house_gift_count
	var u30_unlocked: Array = g._home.house_unlocked.duplicate()
	var u30_ether := g._engine.ether
	g._home.house_gift_week = ""
	g._home.house_gift_count = 0
	g._home.house_unlocked.clear()
	# 0..2 визита — не за что
	for v in [0, 1, 2]:
		g._home._check_house_gift(v)
	Selftest.check("c no gift below 3 guests", g._home.house_gift_count == 0)
	# 3 визита -> 1, 6 -> 2, 20 -> всё равно 2 (потолок недели)
	g._home._check_house_gift(3)
	Selftest.check("c one gift at 3 guests", g._home.house_gift_count == 1)
	var u30_gift_id := ""
	if g._home.house_unlocked.size() > 0:
		u30_gift_id = String(g._home.house_unlocked[0])
	var u30_gift_label := String(HouseItems.get_item(u30_gift_id).get("label", ""))
	Selftest.check("c gift text names the item, not a catalog id",
		u30_gift_label != "" and g._engine.status_text == "Гости принесли тебе " + u30_gift_label)
	g._home._check_house_gift(20)
	Selftest.check("c gift cap is 2 per week", g._home.house_gift_count == 2)
	g._home._check_house_gift(20)
	Selftest.check("c repeat check in the same week grants nothing", g._home.house_gift_count == 2)
	Selftest.check("c host gift grants ownership, never ether",
		g._engine.ether == u30_ether and g._home.house_unlocked.size() > 0)
	# смена недели обнуляет счётчик
	g._home.house_gift_week = "2000-W01"
	g._home._check_house_gift(9)
	Selftest.check("c new week restarts the counter", g._home.house_gift_count == 2)
	# Календарная математика (решение R7) проверяется на датах, где она реально
	# ломается: 2026-01-01 — четверг, «своя» первая неделя; 2027-01-01 — пятница,
	# т.е. принадлежит ISO-году 2026 и его 53-й неделе; 2024-12-30 — понедельник
	# первой недели ISO-года 2025. Формат «YYYY-Www» из этих трёх следует сам.
	Selftest.check("c iso week 2026-01-01 is W01 of 2026",
		g._home._iso_week_of(2026, 1, 1) == "2026-W01")
	Selftest.check("c iso week 2027-01-01 belongs to 2026-W53",
		g._home._iso_week_of(2027, 1, 1) == "2026-W53")
	Selftest.check("c iso week 2024-12-30 belongs to 2025-W01",
		g._home._iso_week_of(2024, 12, 30) == "2025-W01")
	var u30_id := g._home._iso_week_id()
	Selftest.check("c week id looks like YYYY-Www",
		u30_id.length() == 8 and u30_id.contains("-W"))
	g._home.house_gift_week = u30_week
	g._home.house_gift_count = u30_count
	g._home.house_unlocked = u30_unlocked

	# ============ Дом: вкладка -> полноэкранный экран ============
	# Мутации, которые красят блок: вернуть «Дом» в TabContainer (краснеют
	# «five tabs» и «house is not a tab»), снять z_index/add_to_group с
	# HouseScreen (краснеют «house screen sits above persistent ui» и
	# «house screen blocks world events»), убрать показ из _open_workshop
	# (краснеет «open workshop shows the house screen»), убрать ветку
	# _house_screen из _close_top_modal (краснеет «esc closes house screen»).
	var u31_titles := []
	for u31_i in g._tabs_ref.get_tab_count():
		u31_titles.append(g._tabs_ref.get_tab_title(u31_i))
	Selftest.check("five tabs", g._tabs_ref.get_tab_count() == 5)
	Selftest.check("house is not a tab", not u31_titles.has("Дом"))
	Selftest.check("tab captions are readable (font_size >= 13)",
		g._tabs_ref.get_theme_font_size("font_size") >= 13)
	var u31_screen := g._home._house_screen
	Selftest.check("house screen built and hidden on start",
		u31_screen != null and not u31_screen.visible)
	Selftest.check("house screen sits above persistent ui",
		u31_screen != null and u31_screen.z_index == 20)
	Selftest.check("house screen is a modal surface",
		u31_screen != null and u31_screen.is_in_group("modal_ui"))
	g._home._open_workshop()
	Selftest.check("open workshop shows the house screen",
		u31_screen.visible and g._home._house_room != null)
	Selftest.check("house screen blocks world events", not g._online._can_spawn_event())
	Selftest.check("esc closes house screen", g._close_top_modal() and not u31_screen.visible)


static func _u28_task(id: String) -> Dictionary:
	# настоящая запись Game.HOUSE_TASKS: _complete_house_task читает не только
	# id/give, но и "text" (статус в home.gd) — синтетика без него падала бы
	for t in Game.HOUSE_TASKS:
		if String(t["id"]) == id:
			return t
	return {}
