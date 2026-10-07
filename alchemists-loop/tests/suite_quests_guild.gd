extends RefCounted
class_name SuiteQuestsGuild
# задания/достижения/комплекты/заказы/престиж (оп B1).

static func run(g: Game) -> void:
	# Герметичность: ST-сейв на диске может нести quests_done из прошлого прогона
	# (boot грузит его до u20-wipe), а _init_new_game квесты намеренно не трогает.
	g._guild._quests_done.clear()
	# задания Светика
	Selftest.check("quest chain data", Game.SPIRIT_QUESTS.size() >= 10)
	var st_steam := int(g._guild._quest_brew.get("steam", 0))
	Selftest.check("quest progress brew", g._guild._quest_progress({"goal": "brew", "target": "steam"}) == st_steam)
	g._guild._quest_brew["steam"] = st_steam + 1
	Selftest.check("quest brew counted", g._guild._quest_progress({"goal": "brew", "target": "steam"}) == st_steam + 1)
	Selftest.check("quest items goal", g._guild._quest_progress({"goal": "items"}) == g._engine.inventory.size())
	Selftest.check("quest target", g._guild._quest_target({"count": 30}) == 30)
	Selftest.check("active quest first", String(g._guild._active_quest().get("id", "")) == "q1")
	Selftest.check("quest tier counted", g._guild._quest_progress({"goal": "tier", "tier": 2}) == int(g._guild._quest_tier.get(2, 0)))
	Selftest.check("quest goal done funcs", g._guild._quest_progress({"goal": "affinity"}) == g._spirit._companion_level_for(g._spirit._companion_affinity))

	# Ряды заданий — карточки с полосой прогресса, а не пара Label.
	g._progress_ui._rebuild_quest_rows()
	var qrows := g._guild._quest_rows.get_children()
	var qcards := 0
	for qnode in qrows:
		if qnode is PanelContainer and (qnode as Control).find_child("ProgressBar", true, false) != null:
			qcards += 1
	Selftest.check("quest rows render as cards",
		qrows.size() == Game.SPIRIT_QUESTS.size() and qcards == qrows.size())
	var q0: Dictionary = Game.SPIRIT_QUESTS[0]
	var q0bar: ProgressBar = null
	if not qrows.is_empty() and qrows[0] is PanelContainer:
		q0bar = (qrows[0] as PanelContainer).find_child("ProgressBar", true, false) as ProgressBar
	Selftest.check("quest card bar carries quest progress",
		q0bar != null and int(q0bar.max_value) == g._guild._quest_target(q0)
		and int(q0bar.value) == mini(g._guild._quest_progress(q0), g._guild._quest_target(q0)))

	# достижения
	Selftest.check("achievements data", Game.ACHIEVEMENTS.size() >= 20)
	var map_script: GDScript = null
	var map_instance: Control = null
	if ResourceLoader.exists("res://game/meta/achievement_map_view.gd"):
		map_script = load("res://game/meta/achievement_map_view.gd") as GDScript
	if map_script != null:
		map_instance = map_script.new() as Control
	var map_states: Dictionary = {}
	if map_instance != null:
		map_states = map_instance.call("compute_track_states", [
			{"id": "items10", "param": 10},
			{"id": "items20", "param": 20},
			{"id": "items30", "param": 30},
		], {"items10": true})
	Selftest.check(
		"achievement map preserves completed milestones",
		map_states.get("items10", -1) == 2
	)
	Selftest.check(
		"achievement map unlocks only the next threshold",
		map_states.get("items20", -1) == 1 and map_states.get("items30", -1) == 0
	)
	var independent_states: Dictionary = {}
	if map_instance != null:
		independent_states = map_instance.call("compute_track_states", [
			{"id": "recipe5", "param": 5},
			{"id": "recipe10", "param": 10},
		], {})
	Selftest.check("achievement map opens each independent track at its first step",
		independent_states.get("recipe5", -1) == 1 and independent_states.get("recipe10", -1) == 0)
	var tied_states: Dictionary = {}
	if map_instance != null:
		tied_states = map_instance.call("compute_track_states", [
			{"id": "tier1a", "param": 10},
			{"id": "tier1b", "param": 10},
			{"id": "tier2", "param": 20},
		], {})
	Selftest.check("achievement map keeps equal thresholds in the same tier",
		tied_states.get("tier1a", -1) == 1 and tied_states.get("tier1b", -1) == 1
			and tied_states.get("tier2", -1) == 0)
	if map_instance != null:
		map_instance.free()
	Selftest.check("ach items progress", g._progress_ui._ach_progress({"kind": "items"}) == g._engine.inventory.size())
	Selftest.check("ach recipes progress", g._progress_ui._ach_progress({"kind": "recipes"}) == g._engine.known_recipes.size())
	Selftest.check("ach successes", g._progress_ui._ach_progress({"kind": "successes"}) == g._engine.successes)
	Selftest.check("ach fails", g._progress_ui._ach_progress({"kind": "fails"}) == maxi(0, g._engine.attempts - g._engine.successes))
	Selftest.check("ach legend uses tier4", g._progress_ui._ach_progress({"kind": "legend"}) == int(g._guild._quest_tier.get(4, 0)))
	Selftest.check("ach upgrades total", g._progress_ui._ach_progress({"kind": "upgrades"}) == g._progress_ui._upgrades_total())

	# комплекты стихий
	Selftest.check("category sets data", Game.CATEGORY_SETS.size() == 4)
	Selftest.check("category totals", g._progress_ui._cat_total("огонь") == 7 and g._progress_ui._cat_total("вода") == 9
		and g._progress_ui._cat_total("воздух") == 12 and g._progress_ui._cat_total("земля") == 29)
	Selftest.check("category found base", g._progress_ui._cat_found("огонь") >= int(g._engine.inventory.has("fire"))
		and g._progress_ui._cat_found("вода") >= int(g._engine.inventory.has("water"))
		and g._progress_ui._cat_found("огонь") <= 7 and g._progress_ui._cat_found("вода") <= 9)
	Selftest.check("ach sets progress", g._progress_ui._ach_progress({"kind": "sets"}) == g._progress_ui._set_done.size())
	var all := 0
	for k in Game.CATEGORY_OF:
		all += 1
	Selftest.check("category covers 57", all == 57)

	# заказы гильдии
	var ord1 := g._guild._order_targets_for("2026-09-11")
	var ord2 := g._guild._order_targets_for("2026-09-11")
	var ord3 := g._guild._order_targets_for("2026-09-12")
	Selftest.check("orders 3 distinct non-base", ord1.size() == 3
		and ord1[0] != ord1[1] and ord1[1] != ord1[2] and ord1[0] != ord1[2]
		and not Game.BASE_IDS.has(String(ord1[0])))
	Selftest.check("orders deterministic per day", ord1 == ord2)
	Selftest.check("orders differ by day", ord1 != ord3)
	Selftest.check("order bounty maps rarity", g._guild._order_bounty("steam") == 6 and g._guild._order_bounty("house") == 45)

	# офлайн-накопление
	Selftest.check("offline below min", g._saves._offline_gain(30, 1.0, 0, 500) == 0)
	Selftest.check("offline normal", g._saves._offline_gain(120, 2.0, 0, 1000) == 240)
	Selftest.check("offline caps at ether cap", g._saves._offline_gain(100000, 1.0, 0, 500) == 500)
	Selftest.check("offline caps at 8h", g._saves._offline_gain(100000, 1.0, 0, 100000) == 28800)

	# престиж «Перегонка»
	var inv_sz := g._engine.inventory.size()
	var exp_g := 0
	if inv_sz >= Game.PRESTIGE_MIN:
		exp_g = int(floor(float(inv_sz - Game.PRESTIGE_MIN) / 5.0)) + 1
	Selftest.check("prestige gain formula", g._hub._prestige_gain() == exp_g)
	var sg_backup: int = int(g._engine.sage_gold)
	g._engine.sage_gold = 0
	var cap0 := g._engine._max_ether()
	g._engine.sage_gold = 3
	Selftest.check("sage multiplier bounded", absf(g._engine._sage_multiplier() - 1.12) < 0.001)
	Selftest.check("sage cap bonus", g._engine._max_ether() == cap0 + 120)
	g._engine.sage_gold = 100
	Selftest.check("sage multiplier has ceiling", absf(g._engine._sage_multiplier() - 1.6) < 0.001)
	g._engine.sage_gold = sg_backup
