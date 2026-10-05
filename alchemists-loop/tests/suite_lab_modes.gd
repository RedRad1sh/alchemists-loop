extends RefCounted
class_name SuiteLabModes
# лаборатория/режимы/прокачка/поиск (оп B1).

static func run(g: Game) -> void:
	# закреплённая панель «ВАРИТЬ»
	Selftest.check("brew bar overlaid", g._brew_bar != null and g._brew_bar.get_parent() == g)
	Selftest.check("brew bar bottom anchor", g._brew_bar.anchor_bottom == 1.0 and g._brew_bar.offset_bottom < 0.0)
	Selftest.check("brew btn inside bar", g._engine._brew_btn.get_parent() != g._tabs_ref and g._brew_bar.is_ancestor_of(g._engine._brew_btn))
	Selftest.check("primary experiment tab", g._tabs_ref.get_tab_title(0) == "Эксперимент")
	Selftest.check("experiment location built", g._pages._experiment_field != null and g._pages._experiment_cauldron != null and g._pages._experiment_drawer != null)
	g._pages._toggle_experiment_drawer()
	Selftest.check("experiment drawer reopens", not g._pages._experiment_drawer.visible and g._pages._experiment_reopen_button.visible)
	g._pages._toggle_experiment_drawer()
	g._engine.inventory["fire"] = maxi(int(g._engine.inventory.get("fire", 0)), 1)
	var exp_tokens_before := g._pages._experiment_tokens.size()
	g._pages._experiment_spawn_token("fire")
	Selftest.check("experiment tap creates field reagent", g._pages._experiment_tokens.size() == exp_tokens_before + 1)
	var exp_token: ElementOrb = g._pages._experiment_tokens.back()
	g._pages._experiment_add_token_to_cauldron(exp_token)
	Selftest.check("field reagent enters cauldron", g._pages._experiment_cauldron_items.size() == 1 and g._pages._experiment_cauldron_items[0] == "fire")
	g._pages._experiment_clear_cauldron()
	Selftest.check("experiment cauldron can be cleared", g._pages._experiment_cauldron_items.is_empty())
	g._tabs_ref.current_tab = 2
	g._update_brew_bar_visibility()
	Selftest.check("bar hides on other tab", not g._brew_bar.visible)
	g._tabs_ref.current_tab = 1
	g._update_brew_bar_visibility()
	Selftest.check("bar visible on lab", g._brew_bar.visible)
	var pad_ok := false
	var lab_scroll := g._tabs_ref.get_child(1) as ScrollContainer
	if lab_scroll != null:
		for ch in lab_scroll.get_children():
			var v: VBoxContainer = null
			if ch is VBoxContainer:
				v = ch
			elif ch is MarginContainer:
				for gc in ch.get_children():
					if gc is VBoxContainer:
						v = gc
			if v == null:
				continue
			for sub in v.get_children():
				if sub is Control and (sub as Control).custom_minimum_size.y >= 100.0 \
						and sub.get_child_count() == 0:
					pad_ok = true
	Selftest.check("lab pad for bar", pad_ok)

	# прокачка: улучшения появляются вместе с веществами
	var steam_keep := int(g._engine.inventory.get("steam", 0))
	g._engine.inventory.erase("steam")
	g._engine.inventory.erase("clay")
	g._engine.inventory.erase("glass")
	g._engine.inventory.erase("mushroom")
	Selftest.check("upgrades locked while items closed", not g._engine._up_unlocked("ether_regen")
		and not g._engine._up_unlocked("ether_cap") and not g._engine._up_unlocked("brew_speed")
		and not g._engine._up_unlocked("source_yield") and not g._engine._up_unlocked("auto_gift"))
	g._engine.ether = 10
	Selftest.check("locked upgrade rejected", not g._engine._buy_upgrade("ether_regen") and g._engine._up_lvl("ether_regen") == 0)
	g._engine.inventory["steam"] = maxi(steam_keep, 1)
	Selftest.check("upgrade unlocked by steam", g._engine._up_unlocked("ether_regen") and not g._engine._up_unlocked("brew_speed"))
	g._engine.ether = 1000
	Selftest.check("upgrade buy", g._engine._buy_upgrade("ether_regen") and g._engine._up_lvl("ether_regen") == 1 and g._engine.ether == 850)
	Selftest.check("regen faster", g._engine._ether_rate() >= Game.BASE_ETHER_REGEN + 0.35)
	g._engine.inventory["clay"] = maxi(int(g._engine.inventory.get("clay", 0)), 1)
	g._engine.inventory["glass"] = maxi(int(g._engine.inventory.get("glass", 0)), 1)
	g._engine.inventory["mushroom"] = maxi(int(g._engine.inventory.get("mushroom", 0)), 1)
	g._engine.inventory["fish"] = maxi(int(g._engine.inventory.get("fish", 0)), 1)
	Selftest.check("upgrades unlocked later", g._engine._up_unlocked("ether_cap") and g._engine._up_unlocked("brew_speed")
		and g._engine._up_unlocked("source_yield") and g._engine._up_unlocked("auto_gift"))
	var _cap_pre := g._engine._max_ether()
	Selftest.check("upgrade cap buy", g._engine._buy_upgrade("ether_cap") and g._engine._max_ether() == _cap_pre + 50)
	# дефект: цена не должна расти быстрее, чем кап эфира (иначе ступень недостижима)
	var _cap_max := Game.MAX_ETHER + 50 * 8 + 50
	var _affordable := true
	for u in Game.UPGRADES:
		for l in int(u["max"]):
			if int(float(u["base"]) * pow(float(u["growth"]), l)) > _cap_max:
				_affordable = false
	Selftest.check("upgrades affordable within cap", _affordable)
	var bs_saved := g.BREW_SECONDS
	g.BREW_SECONDS = 2.0
	Selftest.check("brew speed buy", g._engine._buy_upgrade("brew_speed") and g._engine._brew_time() < g.BREW_SECONDS)
	g.BREW_SECONDS = bs_saved
	g._engine.ether = 5000
	Selftest.check("upgrade mid level", g._engine._buy_upgrade("ether_cap") and g._engine._up_lvl("ether_cap") == 2)
	for i in 3:
		g._engine._buy_upgrade("source_yield")
	Selftest.check("source yield maxed", g._engine._up_lvl("source_yield") == 3)
	var water_have := int(g._engine.inventory.get("water", 0))
	g._engine._source_taps = 0
	for i in 3:
		g._engine._collect("water")
	Selftest.check("source yield calm taps", int(g._engine.inventory.get("water", 0)) == water_have + 3)
	g._engine._collect("water")
	Selftest.check("source yield waits until fifth tap", int(g._engine.inventory.get("water", 0)) == water_have + 4)
	g._engine._collect("water")
	Selftest.check("source yield bonus", int(g._engine.inventory.get("water", 0)) == water_have + 6)

	# Подсказка Светика — единственный платный канал: направление без reveal результата.
	g._spirit._companion_unlocked = true
	g._engine.inventory["fire"] = maxi(int(g._engine.inventory.get("fire", 0)), 1)
	g._engine.inventory["water"] = maxi(int(g._engine.inventory.get("water", 0)), 1)
	g._engine.known_recipes.erase(g._pair_key("fire", "water"))
	var known_before := g._engine.known_recipes.size()
	g._engine.ether = 200
	var hint_paid := g._pages._hint()
	Selftest.check("paid hint points without reveal", hint_paid and g._engine.ether == 200 - Game.HINT_COST and g._engine.known_recipes.size() == known_before
		and g._engine.status_text.find("Светик") >= 0)

	# поиск по названию (лаборатория)
	Selftest.check("search matches all", g._online._matches_search("fire") and g._online._matches_search("house"))
	g._engine._search_box.text = "дом"
	Selftest.check("search finds house", g._online._matches_search("house") and not g._online._matches_search("fire"))
	Selftest.check("search finds house recipe", g._online._find_recipe("wall", "wood").get("out", "") == "house")
	g._engine._search_box.text = ""

	# судьбоносные режимы
	g._engine.inventory["plant"] = maxi(int(g._engine.inventory.get("plant", 0)), 1)
	Selftest.check("modes unlocked by items", g._engine._mode_unlocked("spring"))
	g._engine.inventory["person"] = maxi(int(g._engine.inventory.get("person", 0)), 1)
	g._engine._refresh()
	Selftest.check("mode bench unlocked", g._engine._mode_unlocked("bench"))
	# resonance = _ach_world_first >= 1; счётчик персистится в сейве, поэтому
	# изолируем его: сейв прошлого прогона мог принести >0 (иначе кейс краснел
	# бы от чужого прогресса, а не от мутации кода).
	var awf_snapshot: int = g._progress_ui._ach_world_first
	g._progress_ui._ach_world_first = 0
	Selftest.check("mode resonance locked w/o discovery", not g._engine._mode_unlocked("resonance"))
	g._progress_ui._ach_world_first = maxi(awf_snapshot, 1)
	g._progress_ui._ach_world_first = 1
	# Late systems are deliberately staged by collection depth; make the fixture
	# represent a late-mid-game laboratory before checking lazy page creation.
	var mode_ids: Array = g.ITEMS.keys()
	for mode_id in mode_ids:
		if g._engine.inventory.size() >= 30:
			break
		g._engine.inventory[String(mode_id)] = maxi(int(g._engine.inventory.get(String(mode_id), 0)), 1)
	g._engine._refresh()
	Selftest.check("mode resonance unlocked by discovery", g._engine._mode_unlocked("resonance"))
	Selftest.check("mode pages built", g._pages._mode_pages.size() == 9 and g._pages._mode_chips.size() == 9)
	Selftest.check("mode tabs compat", g._pages._mode_tabs.size() == 9)
	Selftest.check("compact tools omit experiment", not (g._pages._mode_chips["experiment"] as Button).visible
		and (g._pages._mode_chips["letters"] as Button).visible
		and not (g._pages._mode_chips["spring"] as Button).visible
		and not (g._pages._mode_chips["resonance"] as Button).visible
		and not (g._pages._mode_chips["atlas"] as Button).visible)
	Selftest.check("experiment primary remains available", g._engine._mode_unlocked("experiment") and g._pages._experiment_field != null)
	g._engine._experiment_day = Time.get_date_string_from_system()
	g._engine._experiment_count = 0
	g._engine._experiment_last_at = 0.0
	g._engine.inventory["fire"] = maxi(int(g._engine.inventory.get("fire", 0)), 2)
	g._engine.ether = maxi(g._engine.ether, 200)
	g._engine._rejected_pairs.erase(g._pair_key("fire", "fire"))
	var experiment_status := g._engine._experiment_status("fire", "fire")
	Selftest.check("experiment frontier status", bool(experiment_status.get("ok", false)))
	var recipes_saved: Dictionary = g._engine.known_recipes.duplicate()
	g._engine.known_recipes.clear()
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	g._engine.known_recipes[g._pair_key("earth", "fire")] = true
	var frontier_plan := g._guild._plan_known_frontier("brick")
	Selftest.check("known frontier points to experiment", not frontier_plan.get("frontier", []).is_empty())
	g._engine.known_recipes = recipes_saved
	Selftest.check("mode retort staged", g._engine._mode_unlocked("retort"))
