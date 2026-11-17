extends RefCounted
class_name SuiteRetortReturn
# реторта/сводка возврата (оп B1).

static func run(g: Game) -> void:
	# реторта: сроки, настой, отмена и сохранение слота
	# u32: пиним ранг и нулевой уровень speed, чтобы базовые часы не зависели
	# от состояния предыдущих сюитов.
	var u32_rank0 := g._engine.mastery_rank
	g._engine.mastery_rank = 0
	g._retort._cube_levels["speed"] = 0
	g._retort._cube_levels["complexity"] = 4
	Selftest.check("retort hours", g._retort._retort_hours_for_tier(0) == 8.0 and g._retort._retort_hours_for_tier(4) == 24.0
		and g._retort._retort_hours_text(1) == "12 ч")
	g._engine.mastery_rank = u32_rank0
	Selftest.check("retort left text", g._retort._retort_left_text(7 * 3600 + 20 * 60) == "7 ч 20 мин"
		and g._retort._retort_left_text(45 * 60) == "45 мин" and g._retort._retort_left_text(50) == "50 с")
	g._retort._retort_slots.clear()
	g._retort._cube_levels["slots"] = 0
	g._engine.mastery_rank = 0
	var t0 := 1000000.0
	g._engine.inventory["fire"] = 5
	var fire_have := int(g._engine.inventory["fire"])
	Selftest.check("retort start", g._retort._retort_start(0, "fire", t0) and int(g._engine.inventory["fire"]) == fire_have - 1
		and g._retort._retort_busy(0))
	Selftest.check("retort not ready early", not g._retort._retort_ready(0, t0 + 8.0 * 3600.0 - 1.0)
		and g._retort._retort_collect(0, t0 + 8.0 * 3600.0 - 1.0).get("ok", true) == false)
	Selftest.check("retort ready on time", g._retort._retort_ready(0, t0 + 8.0 * 3600.0 + 1.0))
	g._retort._retort_collect(0, t0 + 8.0 * 3600.0 + 1.0)
	g._engine.inventory["water"] = 3
	Selftest.check("retort start water", g._retort._retort_start(0, "water", t0))
	Selftest.check("retort cancel refunds", g._retort._retort_cancel(0) and int(g._engine.inventory["water"]) == 3 and not g._retort._retort_busy(0))
	g._pages._select_mode("retort")
	Selftest.check("retort page visible", (g._pages._mode_pages["retort"] as Control).visible)
	g._retort._cube_levels["slots"] = 1
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
	g._engine.inventory["water"] = maxi(1, int(g._engine.inventory.get("water", 0)))
	g._retort._retort_start(0, "water", 2000000.0)
	g._saves._save_game()
	g._retort._essence_codex.clear()
	g._retort._retort_slots.clear()
	g._saves._load_game()
	Selftest.check("retort persist", g._retort.essence_known(g._retort.essence_of("fire"))
		and String(g._retort._retort_slot(0).get("sub", "")) == "water"
		and String(g._retort._retort_slot(0).get("essence", "")) == g._retort.essence_of("water")
		and int(g._retort._retort_slot(0).get("tier", -1)) == int(g._engine._rarity_of("water").get("tier", 0))
		and float(g._retort._retort_slot(0).get("started", 0.0)) == 2000000.0)
	g._retort._retort_cancel(0)
	g._retort._retort_slots.clear()
	g._retort._cube_levels["slots"] = 0
	g._retort._cube_levels["speed"] = 0
	g._retort._cube_levels["complexity"] = 0
	# сводка возврата: оценка Родника — только для включённого и открытого
	var sp_on: bool = g._engine.spring_on
	var sp_had_plant: bool = g._engine.inventory.has("plant")
	var sp_plant: int = int(g._engine.inventory.get("plant", 0))
	g._engine.spring_on = true
	g._engine.inventory["plant"] = maxi(sp_plant, 1)
	Selftest.check("spring offline gain (new formula: window 300s at lvl 0)", g._saves._spring_offline_gain(3600.0) == 50 and g._saves._spring_offline_gain(60.0) == 10
		and g._saves._spring_offline_gain(30.0) == 0)
	g._engine.spring_on = sp_on
	if sp_had_plant: g._engine.inventory["plant"] = sp_plant
	else: g._engine.inventory.erase("plant")
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
	# ============ sb9 (T9/B): строка «слишком короткое отсутствие» — только при честном статусе "" ============
	# Офлайн-маршрут верстака сорвался на паузе: шагов нет, статус "ingredients".
	# elif (_return_bench_status == "") не срабатывает — строка не появляется вовсе.
	g._saves._return_bench_steps = 0
	g._saves._return_bench_status = "ingredients"
	g._pages._bench_on = true
	g._pages._bench_target = "water"
	g._saves._open_return_popup()
	var sb9_rtxt := ""
	for ch in g._saves._return_list.get_children():
		sb9_rtxt += (ch as Label).text + "\n"
	Selftest.check("sb9 return poster skips bench line when offline route failed",
		not sb9_rtxt.contains("слишком короткое отсутствие"))
	g._pages._bench_on = false
	g._pages._bench_target = ""
	g._saves._close_return_popup()
	# Честное короткое отсутствие: верстак включён и цель выбрана, статус "" → строка есть.
	g._saves._return_bench_status = ""
	g._pages._bench_on = true
	g._pages._bench_target = "water"
	g._saves._open_return_popup()
	sb9_rtxt = ""
	for ch in g._saves._return_list.get_children():
		sb9_rtxt += (ch as Label).text + "\n"
	Selftest.check("sb9 return poster keeps bench line for genuine short absence",
		sb9_rtxt.contains("слишком короткое отсутствие"))
	g._pages._bench_on = false
	g._pages._bench_target = ""
	g._saves._close_return_popup()
	g._last_rank = 14
	g._online._world_total_seen = 60
	g._saves._save_game()
	g._last_rank = 0
	g._online._world_total_seen = 0
	g._saves._load_game()
	Selftest.check("return persist", g._last_rank == 14 and g._online._world_total_seen == 60)
	g._saves._return_elapsed = 0.0
	# ============ U32 (A2): срок реторты от ранга печати ============
	g._engine.mastery_rank = 1
	Selftest.check("u32 rank 1 no bonus", g._retort._retort_mastery_factor() == 1.0)
	g._engine.mastery_rank = 2
	Selftest.check("u32 rank 2 minus 6", absf(g._retort._retort_mastery_factor() - 0.94) < 0.0001)
	g._engine.mastery_rank = 5
	Selftest.check("u32 tier0 at rank 5", absf(g._retort._retort_hours_for_tier(0) - 6.08) < 0.001)
	g._engine.mastery_rank = 6
	Selftest.check("u32 floor at rank 6", g._retort._retort_hours_for_tier(0) == 6.0)
	g._engine.mastery_rank = 20
	Selftest.check("u32 floor holds", g._retort._retort_hours_for_tier(0) == 6.0
		and g._retort._retort_hours_for_tier(4) == 6.0)
	var u32_r0 := g._engine.mastery_rank
	g._engine.mastery_rank = 1
	Selftest.check("u32 tier1 at rank 1", g._retort._retort_hours_for_tier(1) == 12.0)
	g._engine.mastery_rank = u32_r0
	# срок фиксируется при закладке: работающий сосуд не укорачивается задним числом.
	# Отступление от брифа (задача 2): огонь, а не камень. Камень — слой 1 (рецепт
	# земля+огонь известен с бутстрапа, saves.gd) → тир 1 → база 12 ч, и на ранге 7
	# пол ещё не достигнут (12 × 0.64 = 7.68 ч) — кейс с камнем был бы красным всегда.
	# Огонь — первостихия, тир 0: 8 × 0.64 = 5.12 → пол 6 ч, как в ruling Q2.
	g._retort._retort_slots.clear()
	g._engine.mastery_rank = 7
	g._engine.inventory["fire"] = 1
	Selftest.check("u32 start at rank 7", g._retort._retort_start(0, "fire")
		and absf(float(g._retort._retort_slot(0)["dur"]) - 6.0 * 3600.0) < 1.0)
	g._engine.mastery_rank = 0
	Selftest.check("u32 running job keeps dur", absf(float(g._retort._retort_slot(0)["dur"]) - 6.0 * 3600.0) < 1.0)
	g._retort._retort_cancel(0)
	g._engine.inventory["fire"] = maxi(1, int(g._engine.inventory.get("fire", 0)))
