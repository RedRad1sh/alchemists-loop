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

	# ============ U14 (T18): HouseView — кадры только видимому виду, emit только по факту сдвига ============
	# Хост — обычный Control, не Container: вёрстка перетёрла бы размер вида.
	var u14_host := Control.new()
	u14_host.visible = false
	g.add_child(u14_host)
	var u14_view: HouseView = Game.HouseViewScript.new()
	u14_view.set_editable(true)
	u14_view.animate = true
	u14_view.set_state(true, {"rug": "rug"}, null)
	# за живые тики окна (~0,6 с) main.gd накрутит ether/regen/autosave — снимаем и возвращаем
	var u14_ether := g._engine.ether
	var u14_regen := g._engine.regen_clock
	var u14_autosave := g._engine.autosave_clock
	u14_host.add_child(u14_view)
	# размер задаём в дереве: синтезированным событиям мыши нужны предсказуемые пиксели
	u14_view.size = Vector2(400, 300)
	# гейт process: скрытый предок — ровно то, что делает TabContainer с
	# неактивной страницей вкладки «Дом»
	Selftest.check("u14 process parked under hidden ancestor", not u14_view.is_processing())
	u14_host.visible = true
	Selftest.check("u14 host is visible in tree", u14_host.is_visible_in_tree())
	Selftest.check("u14 process runs when ancestor shows", u14_view.is_processing())
	# Троттл меряем по числу РЕАЛЬНЫХ перерисовок: CanvasItem.draw срабатывает
	# прямо перед каждым _draw(), т.е. это счётчик отрисовок, а не косвенный
	# признак. Верхняя граница — по фактической длительности окна, а не по числу
	# кадров: при 20 redraw/с их не больше одного на 50 мс, а безгейтная версия
	# на типовых 30-60 к/с даёт вдвое-втрое больше. На движке медленнее ~25 к/с
	# различающая сила теряется (граница сливается с кадровой частотой) — это
	# сознательный компромисс: ложнокрасных на слабом железе не будет.
	var u14_draws := [0]
	u14_view.draw.connect(func() -> void: u14_draws[0] += 1)
	var u14_t0 := Time.get_ticks_msec()
	await g.get_tree().create_timer(0.5).timeout
	var u14_elapsed: int = Time.get_ticks_msec() - u14_t0
	# невакуумность всего блока: если draw-сигнал в этом окружении не считается,
	# кейс красный, а не зелёный молча
	Selftest.check("u14 view really redraws while shown", u14_draws[0] >= 3
		and u14_elapsed > 0)
	# +150 мс — три кадра на границы окна (redraw приходит на кадр позже queue_redraw)
	Selftest.check("u14 redraw rate stays at or below 20 fps",
		u14_draws[0] * 50 <= u14_elapsed + 150)
	Selftest.check("u14 shown view really ticks", u14_view._phase > 0.0)
	# и прямое свойство самого троттла: аккумулятор после каждого тика ниже порога
	# (ловит вариант «копить, но не обнулять», который счётчик выше не заметит)
	Selftest.check("u14 redraw accumulator stays below threshold",
		u14_view._redraw_clock >= 0.0 and u14_view._redraw_clock < 0.05)
	u14_host.visible = false
	Selftest.check("u14 process parks when ancestor hides", not u14_view.is_processing())
	# статичный вид (home.gd: prev.animate = false) не берёт кадров, даже когда его показали
	u14_view.animate = false
	u14_host.visible = true
	Selftest.check("u14 non-animated view never processes", not u14_view.is_processing())
	u14_host.visible = false
	# --- контракт эмитов: тап != перетаскивание (home.gd:215 на каждый эмит делает
	# _save_game() + _upload_house()) ---
	var u14_layouts: Array = []
	u14_view.layout_changed.connect(func(_l: Dictionary) -> void: u14_layouts.append(_l))
	var u14_btn := InputEventMouseButton.new()
	u14_btn.button_index = MOUSE_BUTTON_LEFT
	var u14_mv := InputEventMouseMotion.new()
	var u14_tex: Texture2D = u14_view._tex_of("rug")
	# точка захвата — центр видимой (непрозрачной) части ковра, её считает сам вид
	var u14_vis: Rect2 = u14_view._visual_rect("rug", u14_view._item_rect("rug", "rug", u14_view.size.x, u14_view.size.y))
	# невакуумность: промах по мебельке сделал бы зелёными сразу все три кейса
	Selftest.check("u14 rug covers a real area", u14_vis.size.x > 20.0 and u14_vis.size.y > 20.0)
	var u14_down := u14_vis.position + u14_vis.size * 0.5
	# диапазон clamp'а считаем тем же кодом, что и драг: середина заведомо не
	# граница, значит якорь точно уедет и эмит будет за что проверить
	var u14_lo: Vector2 = u14_view._clamp_anchor_to_view("rug", "rug", -10.0, -10.0, u14_tex, u14_view.size.x, u14_view.size.y)
	var u14_hi: Vector2 = u14_view._clamp_anchor_to_view("rug", "rug", 10.0, 10.0, u14_tex, u14_view.size.x, u14_view.size.y)
	var u14_mid := (u14_lo + u14_hi) * 0.5
	Selftest.check("u14 drag range is roomy", absf(u14_hi.x - u14_lo.x) * u14_view.size.x > 40.0
		and absf(u14_hi.y - u14_lo.y) * u14_view.size.y > 40.0)
	var u14_start: Vector2 = u14_view._resolved_anchor("rug", "rug", u14_view.size.x, u14_view.size.y, u14_tex)
	var u14_target := u14_down + (u14_mid - u14_start) * u14_view.size
	# движение заведомо крупнее порога тапа (22 px в element_orb.gd:121)
	Selftest.check("u14 drag is longer than a tap", u14_down.distance_to(u14_target) > 25.0)
	# 1) press + release в одной точке — раскладка не менялась
	u14_btn.pressed = true
	u14_btn.position = u14_down
	u14_view._gui_input(u14_btn)
	Selftest.check("u14 press grabs the rug", u14_view._drag_cat == "rug")
	u14_btn.pressed = false
	u14_view._gui_input(u14_btn)
	Selftest.check("u14 plain tap emits nothing", u14_layouts.is_empty() and u14_view._drag_cat == "")
	# 2) press + движение + release — ровно один эмит с новым якорем
	u14_btn.pressed = true
	u14_view._gui_input(u14_btn)
	u14_mv.position = u14_target
	u14_view._gui_input(u14_mv)
	u14_btn.pressed = false
	u14_btn.position = u14_target
	u14_view._gui_input(u14_btn)
	var u14_now: Vector2 = u14_view._anchor_overrides["rug"]
	Selftest.check("u14 drag really moves the piece", u14_now.distance_to(u14_start) > 0.02
		and u14_now.distance_to(u14_mid) < 0.01)
	Selftest.check("u14 drag emits exactly once", u14_layouts.size() == 1)
	if u14_layouts.size() == 1:
		var u14_payload: Array = u14_layouts[0]["rug"]
		Selftest.check("u14 payload carries the new anchor",
			absf(float(u14_payload[0]) - u14_now.x) < 0.001 and absf(float(u14_payload[1]) - u14_now.y) < 0.001)
	# 3) утащили и вернули на прежнее якорное место — раскладка та же, эмите не быть
	var u14_vis2: Rect2 = u14_view._visual_rect("rug", u14_view._item_rect("rug", "rug", u14_view.size.x, u14_view.size.y))
	var u14_down2 := u14_vis2.position + u14_vis2.size * 0.5
	var u14_q := (u14_lo + u14_mid) * 0.5
	var u14_start2: Vector2 = u14_view._resolved_anchor("rug", "rug", u14_view.size.x, u14_view.size.y, u14_tex)
	var u14_target2 := u14_down2 + (u14_q - u14_start2) * u14_view.size
	u14_btn.pressed = true
	u14_btn.position = u14_down2
	u14_view._gui_input(u14_btn)
	Selftest.check("u14 second press grabs the moved rug", u14_view._drag_cat == "rug")
	u14_mv.position = u14_target2
	u14_view._gui_input(u14_mv)
	var u14_moved2: Vector2 = u14_view._anchor_overrides["rug"]
	Selftest.check("u14 round trip really moved", u14_moved2.distance_to(u14_q) < 0.01)
	u14_mv.position = u14_down2
	u14_view._gui_input(u14_mv)
	u14_btn.pressed = false
	u14_view._gui_input(u14_btn)
	Selftest.check("u14 drag back to start emits nothing", u14_layouts.size() == 1)
	u14_view.queue_free()
	u14_host.queue_free()
	g._engine.ether = u14_ether
	g._engine.regen_clock = u14_regen
	g._engine.autosave_clock = u14_autosave
	# чужие сигналы не тронуты: дом сохранился бы только от реального сдвига
	Selftest.check("u14 house state untouched", g._home.house_layout.is_empty()
		and g._engine.ether == u14_ether)

	# ============ U24 (H1): дефолтные якоря — у каждого предмета остаётся зона тапа ============
	# Проверка идёт теми же функциями, которыми игра проверяет тап, на 8 размерах
	# сцены:Wide Room (1040x300) — ровно тот случай, где старый ковёр проваливался
	# под зону стола и стула и терял 98% своей площади для пальца.
	var u24_sizes: Array = [Vector2(400, 300), Vector2(540, 300), Vector2(1040, 300),
		Vector2(320, 300), Vector2(480, 360), Vector2(300, 300),
		Vector2(320, 240), Vector2(720, 540)]
	var u24_furn := {}
	for c in Game.DECOR:
		u24_furn[String(c["id"])] = String(c["id"])
	var u24_host := Control.new()
	u24_host.visible = false
	g.add_child(u24_host)
	var u24_no_clamp := true
	var u24_floor_ok := true
	var u24_pocket_ok := true
	var u24_on_screen := true
	var u24_checked := 0
	for sz in u24_sizes:
		var u24_view: HouseView = Game.HouseViewScript.new()
		u24_view.set_editable(false)
		u24_view.animate = false
		u24_host.add_child(u24_view)
		u24_view.size = sz
		u24_view.set_state(false, u24_furn, null)
		for raw_cat in HouseView.DRAW_ORDER:
			var cat := String(raw_cat)
			var item_id := String(u24_furn[cat])
			var tex: Texture2D = u24_view._tex_of(item_id)
			if tex == null:
				continue  # missing-ассет: геометрию не измеряем, но и не считаем зелёным молча
			u24_checked += 1
			var p: Array = u24_view._anchor_params(cat, item_id)
			var res: Vector2 = u24_view._resolved_anchor(cat, item_id, sz.x, sz.y, tex)
			if res.distance_to(Vector2(float(p[0]), float(p[1]))) > 0.001:
				u24_no_clamp = false  # дефолт клампится — значит якорь/размер подобраны неверно
			var vr: Rect2 = u24_view._visual_rect(item_id,
				u24_view._item_rect(cat, item_id, sz.x, sz.y))
			if vr.position.x < -0.5 or vr.position.y < -0.5 \
					or vr.end.x > sz.x + 0.5 or vr.end.y > sz.y + 0.5:
				u24_on_screen = false
			# напольный предмет стоит на полу: низ видимой части — за линией пола (0.60·h),
			# а ковёр дополнительно не задирается на стену целиком
			if int(u24_view._mode_of(item_id)) == 0:
				if vr.end.y < sz.y * 0.60:
					u24_floor_ok = false
				if cat == "rug" and vr.position.y < sz.y * 0.60:
					u24_floor_ok = false
			var own := 0
			for ix in 3:
				for iy in 3:
					var pt := Vector2(vr.position.x + vr.size.x * (0.25 + 0.25 * float(ix)),
						vr.position.y + vr.size.y * (0.25 + 0.25 * float(iy)))
					var hit := u24_view._hit_decor(pt)
					if not hit.is_empty() and String(hit["cat"]) == cat:
						own += 1
			if own < 2:
				u24_pocket_ok = false
		u24_view.queue_free()
	u24_host.queue_free()
	# невакуумность: без измеренных предметов блок зелёный по инерции
	Selftest.check("u24 measured a real number of pieces", u24_checked >= 72)
	Selftest.check("u24 h1 default anchors are never clamped", u24_no_clamp)
	Selftest.check("u24 h1 floor pieces stay on the floor", u24_floor_ok)
	Selftest.check("u24 h1 every piece keeps a tappable pocket", u24_pocket_ok)
	Selftest.check("u24 h1 nothing drifts off the scene", u24_on_screen)

	# ============ U25 (H2): чтение якоря не переписывает сохранённую раскладку ============
	var u25_furn := {}
	for c in Game.DECOR:
		u25_furn[String(c["id"])] = String(c["id"])
	var u25_host := Control.new()
	u25_host.visible = false
	g.add_child(u25_host)
	var u25_view: HouseView = Game.HouseViewScript.new()
	u25_view.set_editable(true)
	u25_view.animate = false
	u25_host.add_child(u25_view)
	u25_view.size = Vector2(400, 300)
	# устаревший override заведомо за краем — ровно то, что «самовосстанавливает» запись
	u25_view.set_state(true, u25_furn, null, Color(1.0, 0.72, 0.36),
		Color("#5a4d40"), Color("#5d452f"), {"rug": [9.0, 9.0]})
	var u25_before: Vector2 = u25_view._anchor_overrides["rug"]
	# тап в правый нижний угол: _hit_decor пройдёт по всем категориям и наведёт порядок
	u25_view._hit_decor(Vector2(398.0, 298.0))
	Selftest.check("u25 hit-test left the stored anchor alone",
		u25_view._anchor_overrides["rug"] == u25_before)
	# но картинка обязана остаться в кадре: нормализация — на чтении, а не в поле
	var u25_vr: Rect2 = u25_view._visual_rect("rug", u25_view._item_rect("rug", "rug", 400.0, 300.0))
	Selftest.check("u25 stale anchor still renders inside the scene",
		u25_vr.size.x > 20.0 and u25_vr.end.x <= 400.5 and u25_vr.end.y <= 300.5
		and u25_vr.position.x >= -0.5 and u25_vr.position.y >= -0.5)
	u25_view.queue_free()
	u25_host.queue_free()
