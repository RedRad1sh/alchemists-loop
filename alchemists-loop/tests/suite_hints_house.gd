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

	# v22: у линзы свой перк — рецепт для выбранной цели
	var _lt := g._pages._lens_targets()
	Selftest.check("lens targets are undiscovered", not _lt.is_empty() and not _lt.has("fire"))
	g._pages._lens_target = String(_lt[0])
	Selftest.check("lens target set", g._pages._lens_target != "")
	Selftest.check("lens target candidates is array", typeof(g._pages._lens_target_candidates(g._pages._lens_target)) == TYPE_ARRAY)
	g._pages._lens_target = ""
	g._engine.known_recipes.clear()

	# дом Светика: траты и обстановка
	g._engine.ether = 2000
	var _eth0 := g._engine.ether
	g._home._cosmetic_theme = "cobalt"
	g._home._cosmetic_aura = "amber"
	g._home._cosmetic_house = false
	g._home.house_furniture.clear()
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
	var _rug_cost := g._home._decor_cost("rug", "rug_1")
	g._home._buy_furniture("rug", "rug_1")
	Selftest.check("furniture gated before house", g._home.house_furniture.is_empty() and g._engine.ether == _eth0 - 270)
	g._home._buy_house()
	Selftest.check("buy house applies", g._home._cosmetic_house and g._engine.ether == _eth0 - 270 - Game.HOUSE_COST)
	g._home._buy_furniture("rug", "rug_1")
	Selftest.check("buy furniture applies", g._home.house_furniture.get("rug", "") == "rug_1" and g._engine.ether == _eth0 - 270 - Game.HOUSE_COST - _rug_cost)
	g._home._buy_furniture("rug", "rug_1")
	Selftest.check("buy furniture idempotent", g._home.house_furniture.size() == 1 and g._engine.ether == _eth0 - 270 - Game.HOUSE_COST - _rug_cost)
	Selftest.check("decor category", g._home._decor_cat("rug").get("label", "") == "Ковёр" and g._home._decor_cat("rug").get("items", []).size() == 10)
	Selftest.check("decor lookup", g._home._decor_label("rug", "rug") == "Классический" and g._home._decor_cost("bed", "bed") == 250)
	Selftest.check("house json shape", g._home._house_json().has("furniture") and g._home._house_json().get("built", false) == g._home._cosmetic_house)
	g._home.house_layout = {"bed": [0.22, 0.86], "lamp": [0.68, 0.84]}
	var _house_with_layout := g._home._house_json()
	Selftest.check("house json keeps layout", _house_with_layout.get("layout", {}).get("bed", []).size() == 2 and absf(float(_house_with_layout["layout"]["lamp"][0]) - 0.68) < 0.001)
	g._home.house_layout.clear()
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
	g._home._cosmetic_theme = "cobalt"
	g._home._cosmetic_aura = "amber"
	g._home._cosmetic_house = false
	g._home.house_furniture.clear()
	g._engine.ether = _eth0
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
	# живой двойной тап по _hint/_lens_reveal: одно списание на два нажатия.
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
	# _lens_reveal открывает попап и уводит табу в лабораторию — иначе блок оставил бы
	# открытый попап на все последующие сюиты.
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
	# ключи независимы: линза не наследует занятую подсказкой отметку
	Selftest.check("u13 spend gate keys independent", g._pages._spend_gate("lens", 1100)
		and not g._pages._spend_gate("lens", 1200))
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
	# то же для линзы (30⚡): состояние подбирается честно, до обоих вызовов
	Selftest.check("u13 lens candidates leave room", g._pages._lens_candidates().size() >= 2)
	var u13_avail1 := g._engine.ether + g._engine.ether_overflow
	var u13_known1 := g._engine.known_recipes.size()
	Selftest.check("u13 first lens pays", g._pages._lens_reveal()
		and g._engine.ether + g._engine.ether_overflow == u13_avail1 - Game.LENS_COST
		and g._engine.known_recipes.size() == u13_known1 + 1)
	var u13_status2 := g._engine.status_text
	Selftest.check("u13 second lens in same frame spends nothing", not g._pages._lens_reveal()
		and g._engine.ether + g._engine.ether_overflow == u13_avail1 - Game.LENS_COST
		and g._engine.known_recipes.size() == u13_known1 + 1
		and g._engine.status_text == u13_status2)
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
	g._pages._spend_guard_ms.erase("lens")
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
	Selftest.check("u13 guards released for later suites", not g._pages._spend_guard_ms.has("hint")
		and not g._pages._spend_guard_ms.has("lens"))
