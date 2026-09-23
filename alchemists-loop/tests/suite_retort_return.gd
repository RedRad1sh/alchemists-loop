extends RefCounted
class_name SuiteRetortReturn
# реторта/сводка возврата (оп B1).

static func run(g: Game) -> void:
	# реторта: сроки, слоты, настой, эссенции
	Selftest.check("retort hours", g._retort._retort_hours_for_tier(0) == 8.0 and g._retort._retort_hours_for_tier(4) == 24.0
		and g._retort._retort_hours_text(1) == "12 ч")
	Selftest.check("retort left text", g._retort._retort_left_text(7 * 3600 + 20 * 60) == "7 ч 20 мин"
		and g._retort._retort_left_text(45 * 60) == "45 мин" and g._retort._retort_left_text(50) == "50 с")
	g._retort._essences.clear()
	g._retort._retort_slots.clear()
	var sg_keep := g._engine.sage_gold
	g._engine.sage_gold = 0
	Selftest.check("retort one slot base", g._retort._retort_slots_open() == 1)
	g._retort._essences = {"a": "А", "b": "Б", "c": "В"}
	Selftest.check("retort second slot by essences", g._retort._retort_slots_open() == 2)
	g._engine.sage_gold = 1
	Selftest.check("retort third slot by prestige", g._retort._retort_slots_open() == 3)
	g._retort._essences.clear()
	g._engine.sage_gold = sg_keep
	var t0 := 1000000.0
	g._engine.inventory["fire"] = 5
	var fire_have := int(g._engine.inventory["fire"])
	Selftest.check("retort start", g._retort._retort_start(0, "fire", t0) and int(g._engine.inventory["fire"]) == fire_have - 1
		and g._retort._retort_busy(0))
	Selftest.check("retort not ready early", not g._retort._retort_ready(0, t0 + 8.0 * 3600.0 - 1.0)
		and g._retort._retort_collect(0, t0 + 8.0 * 3600.0 - 1.0).get("ok", true) == false)
	Selftest.check("retort ready on time", g._retort._retort_ready(0, t0 + 8.0 * 3600.0 + 1.0))
	var ret_cap0 := g._engine._max_ether()
	var got := g._retort._retort_collect(0, t0 + 8.0 * 3600.0 + 1.0)
	Selftest.check("retort first essence grants cap", bool(got.get("ok", false)) and bool(got.get("perm", false))
		and g._engine._max_ether() == ret_cap0 + Game.RETORT_CAP_EACH and not g._retort._retort_busy(0))
	g._engine.inventory["water"] = 3
	Selftest.check("retort start water", g._retort._retort_start(0, "water", t0))
	Selftest.check("retort cancel refunds", g._retort._retort_cancel(0) and int(g._engine.inventory["water"]) == 3 and not g._retort._retort_busy(0))
	g._retort._essences.clear()
	for i in 10:
		g._retort._essences["e%d" % i] = "Э%d" % i
	Selftest.check("essence bonus caps at 10", g._retort._essence_cap_bonus() == Game.RETORT_CAP_EACH * Game.RETORT_CAP_FIRST)
	g._retort._essences["extra"] = "Лишняя"
	Selftest.check("essence bonus stays capped", g._retort._essence_cap_bonus() == Game.RETORT_CAP_EACH * Game.RETORT_CAP_FIRST)
	g._engine.inventory["earth"] = 2
	g._retort._retort_start(0, "earth", t0)
	g._engine.ether = 100
	var late := g._retort._retort_collect(0, t0 + 9.0 * 3600.0)
	Selftest.check("retort late unique pays ether", bool(late.get("ok", false)) and not bool(late.get("perm", false))
		and int(late.get("gain", 0)) == Game.RETORT_REPEAT_ETHER and g._engine.ether == 100 + Game.RETORT_REPEAT_ETHER)
	g._pages._select_mode("retort")
	Selftest.check("retort page visible", (g._pages._mode_pages["retort"] as Control).visible)
	g._engine.inventory["fire"] = 2
	g._retort._retort_start(1, "fire", t0)
	g._retort._refresh_retort_page()
	Selftest.check("retort chip dot when ready", String((g._pages._mode_chips["retort"] as Button).text).contains("●"))
	Selftest.check("retort hello ready", g._retort._retort_hello_line() == "Реторта готова — неси кружку!")
	g._retort._retort_collect(1, t0 + 9.0 * 3600.0)
	g._retort._retort_start(0, "fire", Time.get_unix_time_from_system())
	Selftest.check("retort hello simmer", g._retort._retort_hello_line().begins_with("Реторта побулькивает"))
	g._retort._retort_cancel(0)
	Selftest.check("retort hello silent", g._retort._retort_hello_line() == "")
	g._retort._essences = {"fire": "Огонь"}
	g._retort._retort_start(0, "water", 2000000.0)
	g._saves._save_game()
	g._retort._essences.clear()
	g._retort._retort_slots.clear()
	g._saves._load_game()
	Selftest.check("retort persist", g._retort._essences.get("fire", "") == "Огонь"
		and String(g._retort._retort_slot(0).get("sub", "")) == "water"
		and float(g._retort._retort_slot(0).get("started", 0.0)) == 2000000.0)
	g._retort._retort_cancel(0)
	g._retort._essences.clear()
	# сводка возврата
	Selftest.check("spring offline gain", g._saves._spring_offline_gain(3600.0) == 50 and g._saves._spring_offline_gain(60.0) == 10
		and g._saves._spring_offline_gain(30.0) == 0)
	g._saves._return_elapsed = 100.0
	Selftest.check("return not due early", not g._saves._return_due())
	g._saves._return_elapsed = 2000.0
	Selftest.check("return due after gap", g._saves._return_due())
	g._saves._inject_return_demo()
	g._saves._open_return_popup()
	Selftest.check("return opens", g._saves._return_open and g._saves._return_shown and g._saves._return_list.get_child_count() >= 8)
	var rtxt := ""
	for ch in g._saves._return_list.get_children():
		rtxt += (ch as Label).text + "\n"
	Selftest.check("return lines", rtxt.contains("150") and rtxt.contains("Реторта готова") and rtxt.contains("#14"))
	g._saves._close_return_popup()
	Selftest.check("return closes", not g._saves._return_open and not g._saves._return_popup.visible)
	g._last_rank = 14
	g._online._world_total_seen = 60
	g._saves._save_game()
	g._last_rank = 0
	g._online._world_total_seen = 0
	g._saves._load_game()
	Selftest.check("return persist", g._last_rank == 14 and g._online._world_total_seen == 60)
	g._saves._return_elapsed = 0.0
	# ============ U16 (T20): обещание про кап реторты — из констант, а не с потолка ============
	# Текст строится в _build_retort_page; контейнер в дерево не ставим — билдер чистый
	# (только add_child + _refresh_retort_page по своим нодам). Но билдер ПЕРЕЗАПИСЫВАЕТ
	# поля вида (_retort_ui/_retort_head/_retort_cards/_retort_ess/_retort_desc) ссылками на
	# эти ноды, а _refresh_retort_page проверяет только == null, значит после free() любой
	# поздний refresh (pages.gd:1770, main.gd:532) читал бы freed-объекты. Снимаем все пять
	# полей и возвращаем обратно.
	var u16_ui0 := g._retort._retort_ui.duplicate(true)
	var u16_head0: Label = g._retort._retort_head
	var u16_cards0: VBoxContainer = g._retort._retort_cards
	var u16_ess0: Label = g._retort._retort_ess
	var u16_desc0: Label = g._retort._retort_desc
	var u16_box := VBoxContainer.new()
	g._retort._build_retort_page(u16_box)
	Selftest.check("u16 retort desc is built and non-empty", g._retort._retort_desc != null
		and g._retort._retort_desc.text.length() > 0)
	var u16_text := "" if g._retort._retort_desc == null else g._retort._retort_desc.text
	# невакуумность: старые числа отличались от фактических констант (было «10» и «+2»),
	# иначе проверка «устаревших цифр нет» ничего не доказывает
	Selftest.check("u16 constants differ from the stale claim", Game.RETORT_CAP_FIRST != 10
		and Game.RETORT_CAP_EACH != 2)
	Selftest.check("u16 retort text carries the live constant values",
		u16_text.contains("Первые %d" % Game.RETORT_CAP_FIRST)
		and u16_text.contains("дают +%d к капу" % Game.RETORT_CAP_EACH))
	Selftest.check("u16 stale numbers gone from the promise", not u16_text.contains("10 уникальных")
		and not u16_text.contains("+2 к капу"))
	u16_box.free()
	g._retort._retort_ui = u16_ui0
	g._retort._retort_head = u16_head0
	g._retort._retort_cards = u16_cards0
	g._retort._retort_ess = u16_ess0
	g._retort._retort_desc = u16_desc0
	Selftest.check("u16 retort view fields restored", g._retort._retort_ui == u16_ui0
		and g._retort._retort_head == u16_head0 and g._retort._retort_desc == u16_desc0)
