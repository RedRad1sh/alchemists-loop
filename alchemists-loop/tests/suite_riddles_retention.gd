extends RefCounted
class_name SuiteRiddlesRetention
# письма/атлас/панч-лист/круг/неделя (оп B1).

static func run(g: Game) -> void:
	# письма Светика: паттерн, вехи, очередь, solve-хендлер, страница
	g._riddles._letter_today = {"day": "2026-09-12", "hint": "ш", "len_a": 5, "len_b": 4,
		"known_a": [[1, "ы"]], "known_b": [], "revealed": false, "solved": false}
	g._riddles._letter_backlog = []
	Selftest.check("letter pattern shapes", g._riddles._letter_pattern(g._riddles._letter_today) == "·ы···  +  ····")
	Selftest.check("letter has unsolved", g._riddles._letter_has_unsolved() and g._riddles._letter_unsolved_count() == 1)
	Selftest.check("letter miles math", g._riddles._letter_milestones_for(12) == 2 and g._riddles._letter_milestones_for(4) == 0)
	Selftest.check("letter day title", g._riddles._letter_day_title(Time.get_date_string_from_system()) == "сегодня")
	g._riddles._letter_milestones = 2
	var let_cap0 := g._engine._max_ether()
	g._riddles._letter_milestones = 0
	Selftest.check("letter cap wires into max ether", let_cap0 - g._engine._max_ether() == 2 * Game.LETTER_CAP_EACH)
	g._riddles._letter_pending.clear()
	g._riddles._letter_queue_pending("fire", "water")
	g._riddles._letter_queue_pending("water", "fire")
	Selftest.check("letter pending dedupes", g._riddles._letter_pending == ["fire|water"])
	g._riddles._letter_pending.clear()
	for li in 25:
		g._riddles._letter_queue_pending("la%d" % li, "lb")
	Selftest.check("letter pending capped", g._riddles._letter_pending.size() == Game.LETTER_PENDING_MAX)
	g._riddles._letter_pending = ["fire|water"]
	g._riddles._letter_inflight.append("fire|water")
	g._riddles._on_net_letter_solve_result({"ok": true, "matched": true, "day": "2026-09-12",
		"solved_total": 5, "milestone": true})
	Selftest.check("letter solve marks + milestone", bool(g._riddles._letter_today.get("solved", false))
		and g._riddles._letter_milestones == 1 and g._riddles._letter_solved_total == 5)
	g._riddles._letter_inflight.append("a|b")
	g._riddles._on_net_letter_solve_result({"ok": false, "offline": true})
	Selftest.check("letter solve offline requeues", g._riddles._letter_pending.has("a|b"))
	g._saves._save_game()
	g._riddles._letter_milestones = 0
	g._riddles._letter_pending.clear()
	g._riddles._letter_solved_total = 0
	g._riddles._letter_today = {}
	g._saves._load_game()
	Selftest.check("letter persist", g._riddles._letter_milestones == 1 and g._riddles._letter_solved_total == 5
		and g._riddles._letter_pending.has("a|b") and bool(g._riddles._letter_today.get("solved", false)))
	# Issue #7: в чужом сейве letter_cache/atlas_cache могут лежать строкой или
	# числом. Без typeof-проверки ДО typed-присваивания _load_game падает с
	# runtime error — мутация: вернуть в saves.gd `var lcache: Dictionary =
	# data.get(...)` (проверку после объявления), и этот кейс покраснеет.
	var _s7_today = g._riddles._letter_today.duplicate(true)
	var _s7_s0 := FileAccess.get_file_as_string(g.SAVE_PATH)
	var _s7_json = JSON.parse_string(_s7_s0)
	_s7_json["letter_cache"] = "испорченный"
	_s7_json["atlas_cache"] = 42
	var _s7_f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	_s7_f.store_string(JSON.stringify(_s7_json))
	_s7_f.close()
	g._saves._load_game()
	Selftest.check("broken cache types load into clean defaults",
		typeof(g._riddles._letter_today) == TYPE_DICTIONARY and g._riddles._letter_today.is_empty()
		and typeof(g._riddles._atlas_today) == TYPE_DICTIONARY)
	g._riddles._letter_today = _s7_today
	# The fixture may have loaded an earlier save with fewer collection keys;
	# stage the late-game laboratory explicitly before selecting gated pages.
	var late_ids: Array = g.ITEMS.keys()
	for late_id in late_ids:
		if g._engine.inventory.size() >= 30:
			break
		g._engine.inventory[String(late_id)] = maxi(int(g._engine.inventory.get(String(late_id), 0)), 1)
	g._engine._refresh()
	g._pages._ensure_modes()
	g._pages._select_mode("letters")
	Selftest.check("letter page visible", (g._pages._mode_pages["letters"] as Control).visible)
	Selftest.check("letter chip no dot when solved", String((g._pages._mode_chips["letters"] as Button).text) == "Письма")
	var b_letter := Net._build_request({"kind": "letter", "path": "/letter/today?device_id=d"})
	Selftest.check("net letter get route", String(b_letter["url"]).ends_with("/letter/today?device_id=d")
		and int(b_letter["method"]) == HTTPClient.METHOD_GET)
	var b_solve := Net._build_request({"kind": "letter_solve", "path": "/letter/solve",
		"body": {"device_id": "d", "a": "x", "b": "y"}})
	Selftest.check("net letter solve route", String(b_solve["url"]).ends_with("/api/letter/solve")
		and int(b_solve["method"]) == HTTPClient.METHOD_POST)

	# атлас: вехи, очередь, solve-хендлер, страница, альбом
	g._riddles._atlas_today = {"day": "2026-09-12", "riddle": "з", "len_a": 6, "len_b": 5,
		"known_a": [], "known_b": [], "solvers": 3, "solved_by_me": false}
	g._riddles._atlas_history = []
	Selftest.check("atlas miles math", g._riddles._atlas_milestones_for(23) == 2 and g._riddles._atlas_milestones_for(9) == 0)
	Selftest.check("atlas has unsolved", g._riddles._atlas_has_unsolved())
	Selftest.check("atlas pattern reuses shapes", g._riddles._letter_pattern(g._riddles._atlas_today) == "······  +  ·····")
	g._riddles._atlas_milestones = 2
	var at_cap0 := g._engine._max_ether()
	g._riddles._atlas_milestones = 0
	Selftest.check("atlas cap wires into max ether", at_cap0 - g._engine._max_ether() == 2 * Game.ATLAS_CAP_EACH)
	g._riddles._atlas_pending.clear()
	g._riddles._atlas_queue_pending("crystal", "moss")
	g._riddles._atlas_queue_pending("moss", "crystal")
	Selftest.check("atlas pending dedupes", g._riddles._atlas_pending == ["crystal|moss"])
	g._pages._select_mode("atlas")
	Selftest.check("atlas page visible", (g._pages._mode_pages["atlas"] as Control).visible)
	Selftest.check("atlas chip dot when unsolved", String((g._pages._mode_chips["atlas"] as Button).text) == "Атлас ●")
	g._riddles._atlas_inflight.append("crystal|moss")
	g._riddles._on_net_atlas_solve_result({"ok": true, "matched": true, "solved_total": 10, "milestone": true})
	Selftest.check("atlas solve marks + milestone", bool(g._riddles._atlas_today.get("solved_by_me", false))
		and int(g._riddles._atlas_today.get("solvers", 0)) == 4
		and g._riddles._atlas_milestones == 1 and g._riddles._atlas_solved_total == 10)
	g._riddles._atlas_inflight.append("c|d")
	g._riddles._on_net_atlas_solve_result({"ok": false, "offline": true})
	Selftest.check("atlas solve offline requeues", g._riddles._atlas_pending.has("c|d"))
	g._saves._save_game()
	g._riddles._atlas_milestones = 0
	g._riddles._atlas_pending.clear()
	g._riddles._atlas_solved_total = 0
	g._riddles._atlas_today = {}
	g._saves._load_game()
	Selftest.check("atlas persist", g._riddles._atlas_milestones == 1 and g._riddles._atlas_solved_total == 10
		and g._riddles._atlas_pending.has("c|d") and bool(g._riddles._atlas_today.get("solved_by_me", false)))
	var b_atlas := Net._build_request({"kind": "atlas", "path": "/atlas/today?device_id=d"})
	Selftest.check("net atlas get route", String(b_atlas["url"]).ends_with("/atlas/today?device_id=d")
		and int(b_atlas["method"]) == HTTPClient.METHOD_GET)
	var b_asolve := Net._build_request({"kind": "atlas_solve", "path": "/atlas/solve",
		"body": {"device_id": "d", "a": "x", "b": "y"}})
	Selftest.check("net atlas solve route", String(b_asolve["url"]).ends_with("/api/atlas/solve")
		and int(b_asolve["method"]) == HTTPClient.METHOD_POST)

	# --- панч-лист: пакетный сбор, платная палитра, пейджер мира, бейджи атласа, письма ---
	g._engine._source_taps = 0
	Selftest.check("collect gain base", g._engine._collect_gain("fire") == 1 and int(g._engine.inventory.get("fire", 0)) >= 1)
	var boost_inventory := int(g._engine.inventory.get("fire", 0))
	var boost_taps := g._engine._source_taps
	g._engine._source_boost_until = Time.get_unix_time_from_system() + 60.0
	var boosted_gain := g._engine._collect_gain("fire")
	Selftest.check("rewarded source boost", boosted_gain >= 2)
	g._engine.inventory["fire"] = boost_inventory
	g._engine._source_taps = boost_taps
	g._engine._source_boost_until = 0.0
	g._engine._collect_all_ms = 0
	var inv_before: Dictionary = g._engine.inventory.duplicate()
	g._engine._collect_all()
	var grew := true
	for b in Game.BASE_IDS:
		if int(g._engine.inventory.get(String(b), 0)) <= int(inv_before.get(String(b), 0)):
			grew = false
	Selftest.check("collect all grows", grew)
	g._engine._collect_all_ms = Time.get_ticks_msec()
	var inv_mid: Dictionary = g._engine.inventory.duplicate()
	g._engine._collect_all()
	var same := true
	for b in Game.BASE_IDS:
		if int(g._engine.inventory.get(String(b), 0)) != int(inv_mid.get(String(b), 0)):
			same = false
	Selftest.check("collect all antispam", same)
	g._home._custom_unlocked.clear()
	var wall_before := g._home._cosmetic_wall
	g._home._open_color_picker("wall")
	g._engine.ether = 0
	g._engine.ether_overflow = 0
	g._home._confirm_color_picker()
	Selftest.check("custom poor rollback", not g._home._custom_unlocked.has("wall") and g._home._cosmetic_wall == wall_before)
	g._engine.ether = 10000
	g._home._custom_unlocked.clear()
	g._home._open_color_picker("wall")
	g._home._confirm_color_picker()
	Selftest.check("custom unlock wall", bool(g._home._custom_unlocked.get("wall", false)) and g._engine.ether == 10000 - int(Game.CUSTOM_COSTS["wall"]))
	g._online._world_search.text = ""
	Selftest.check("world all", g._online._world_filtered_ids().size() == g.ITEMS.size())
	g._online._world_search.text = "zzz_no_such_zzz"
	Selftest.check("world empty", g._online._world_filtered_ids().is_empty())
	g._online._world_search.text = "огонь"
	var wf := g._online._world_filtered_ids()
	var wf_ok := not wf.is_empty()
	for sid in wf:
		var s := String(sid)
		if not (g._online._item_name(s).to_lower().contains("огонь") or s.contains("огонь")):
			wf_ok = false
	Selftest.check("world query", wf_ok)
	g._online._world_search.text = ""
	g._online._world_page = 999
	g._online._rebuild_world_grid()
	Selftest.check("world page clamp", g._online._world_page == maxi(0, int(ceil(float(g.ITEMS.size()) / float(Game.WORLD_PAGE_SIZE))) - 1))
	g._riddles._atlas_history = [{"day": "2026-09-10", "solved_by_me": true}, {"day": "2026-09-09", "solved_by_me": false}]
	g._riddles._atlas_today = {"day": "2026-09-12", "solved_by_me": false}
	Selftest.check("atlas days strip", g._riddles._atlas_days_strip() == "· ✓ ○")
	g._riddles._atlas_today = {"day": "2026-09-12", "solved_by_me": true}
	Selftest.check("atlas days solved", g._riddles._atlas_days_strip() == "· ✓ ✓")
	g._riddles._atlas_history = []
	g._riddles._atlas_today = {}
	var lc := g._riddles._letter_card({"day": Time.get_date_string_from_system(), "hint": "тест",
		"len_a": 4, "len_b": 4, "solved": false})
	Selftest.check("letter card", lc is PanelContainer)
	lc.queue_free()
	# --- v29: дневной круг ---
	g._retention._circle_days = ["2026-01-01", "2026-01-02"]
	g._retention._circle_last = g._retention._circle_yesterday()
	g._retention._circle_run = 4
	g._retention._circle_track_visit()
	Selftest.check("circle visit run+", g._retention._circle_run == 5 and g._retention._circle_last == g._retention._circle_today() and g._retention._circle_days.has(g._retention._circle_today()))
	g._retention._circle_track_visit()
	Selftest.check("circle visit idem", g._retention._circle_run == 5)
	g._retention._circle_last = "2020-01-01"
	g._retention._circle_track_visit()
	Selftest.check("circle visit gap", g._retention._circle_run == 1)
	g._retention._circle_run = 3
	g._retention._hearth_claim = ""
	Selftest.check("circle hearth math", g._retention._circle_hearth_reward() == 13 and g._retention._circle_hearth_claimable())
	g._engine.ether = 0
	g._retention._circle_claim_hearth()
	Selftest.check("circle hearth claim", g._engine.ether == 13 and not g._retention._circle_hearth_claimable())
	g._retention._circle_claim_hearth()
	Selftest.check("circle hearth once", g._engine.ether == 13)
	g._retention._circle_disc_day = ""
	g._retention._circle_disc = 0
	g._retention._circle_on_discovery(false)
	Selftest.check("circle disc repeat", g._retention._circle_disc == 0)
	g._retention._circle_on_discovery(true)
	g._retention._circle_on_discovery(true)
	Selftest.check("circle disc count", g._retention._circle_disc == 2 and g._retention._circle_disc_day == g._retention._circle_today() and not g._retention._circle_disc_done())
	for i in Game.CIRCLE_DISC_GOAL:
		g._retention._circle_on_discovery(true)
	Selftest.check("circle disc goal", g._retention._circle_disc_done())
	Selftest.check("circle day miles", g._retention._circle_day_miles_for(6) == 0 and g._retention._circle_day_miles_for(7) == 1 and g._retention._circle_day_miles_for(365) == 4)
	Selftest.check("circle pts miles", g._retention._circle_pts_miles_for(49) == 0 and g._retention._circle_pts_miles_for(50) == 1 and g._retention._circle_pts_miles_for(500) == 3)
	g._retention._circle_mdays = 2
	g._retention._circle_mpts = 1
	Selftest.check("circle cap bonus", g._retention._circle_cap_bonus() == 8)
	Selftest.check("circle regen bonus", is_equal_approx(g._retention._circle_regen_bonus(), 0.05))
	g._retention._circle_mdays = 0
	g._retention._circle_mpts = 0
	Selftest.check("circle aura gate", not g._retention._circle_hearth_aura())
	g._retention._circle_mdays = 4
	Selftest.check("circle aura open", g._retention._circle_hearth_aura() and g._home._aura_color("hearth") == Color("#ff7a2e"))
	g._retention._circle_mdays = 0
	g._retention._circle_mine = 2
	g._guild._orders_refresh()
	for t in g._guild._order_targets_cache:
		g._guild._order_done[String(t)] = true
	Selftest.check("circle closed", g._retention._circle_closed() and g._retention._circle_reward_claimable())
	g._engine.ether = 0
	g._retention._circle_claim_reward()
	Selftest.check("circle reward", g._engine.ether == Game.CIRCLE_REWARD and not g._retention._circle_reward_claimable())
	g._retention._refresh_circle_page()
	Selftest.check("circle chip calm", String((g._pages._mode_chips["circle"] as Button).text) == "Круг")
	g._retention._hearth_claim = ""
	g._retention._refresh_circle_page()
	Selftest.check("circle chip dot", String((g._pages._mode_chips["circle"] as Button).text) == "Круг ●")
	# ============ U35 (A3): локальная цель дня ============
	var u35_pts := g._retention._circle_pts_total
	var u35_done_day := g._retention._circle_local_done_day
	var u35_mine := g._retention._circle_mine
	var u35_hint := g._retention._circle_hint
	var u35_reward_day := g._retention._circle_reward_day
	var u35_mpts := g._retention._circle_mpts
	g._retention._circle_mine = 0
	g._retention._circle_hint = ""
	g._retention._circle_local_done_day = ""
	g._retention._circle_reward_day = ""
	Selftest.check("u35 offline challenge dead before", not g._retention._circle_challenge_done())
	# детерминизм: один и тот же день — одна и та же цель
	var u35_g1 := g._retention._circle_local_goal_for("2026-09-25")
	var u35_g2 := g._retention._circle_local_goal_for("2026-09-25")
	Selftest.check("u35 deterministic", String(u35_g1.get("out", "")) == String(u35_g2.get("out", ""))
		and String(u35_g1.get("a", "")) == String(u35_g2.get("a", "")))
	# достижима из баз: оба реагента — базовые стихии; цель никогда не пуста
	Selftest.check("u35 base-only and nonempty", not u35_g1.is_empty()
		and Game.BASE_IDS.has(String(u35_g1["a"])) and Game.BASE_IDS.has(String(u35_g1["b"])))
	# дата действительно участвует: на 12 датах подряд встречается ≥ 2 разных выхода
	var u35_variants := {}
	for u35_i in range(12):
		var u35_gd := g._retention._circle_local_goal_for("2026-10-%02d" % (u35_i + 1))
		u35_variants[String(u35_gd.get("out", ""))] = true
	Selftest.check("u35 date matters", u35_variants.size() >= 2)
	# варка цели закрывает «цель дня» офлайн и даёт очки ровно один раз
	g._retention._circle_on_local_brew(String(g._retention._circle_local_goal()["out"]))
	Selftest.check("u35 local done", g._retention._circle_challenge_done())
	Selftest.check("u35 points once", g._retention._circle_pts_total == u35_pts + Game.CIRCLE_LOCAL_POINTS)
	g._retention._circle_on_local_brew(String(g._retention._circle_local_goal()["out"]))
	Selftest.check("u35 no double points", g._retention._circle_pts_total == u35_pts + Game.CIRCLE_LOCAL_POINTS)
	# чужая варка не засчитывается
	g._retention._circle_local_done_day = ""
	g._retention._circle_on_local_brew("dragon")
	Selftest.check("u35 wrong output ignored", not g._retention._circle_challenge_done())
	# серверная цель перебивает локальную по факту: my_points > 0 → done и без локали
	g._retention._circle_mine = 3
	Selftest.check("u35 server overrides", g._retention._circle_challenge_done())
	# закрытый круг офлайн отдаёт награду один раз в день
	g._retention._circle_local_done_day = g._retention._circle_today()
	g._guild._order_day = g._retention._circle_today()
	g._guild._order_targets_cache = ["steam", "stone", "clay"]
	g._guild._order_done = {"steam": true, "stone": true, "clay": true}
	g._retention._circle_disc_day = g._retention._circle_today()
	g._retention._circle_disc = Game.CIRCLE_DISC_GOAL
	Selftest.check("u35 circle closed offline", g._retention._circle_reward_claimable())
	g._retention._circle_claim_reward()
	Selftest.check("u35 reward once", g._retention._circle_reward_day == g._retention._circle_today()
		and not g._retention._circle_reward_claimable())
	# restore
	g._retention._circle_mine = u35_mine
	g._retention._circle_hint = u35_hint
	g._retention._circle_local_done_day = u35_done_day
	g._retention._circle_pts_total = u35_pts
	g._retention._circle_mpts = u35_mpts
	g._retention._circle_reward_day = u35_reward_day
	g._guild._order_day = ""
	g._guild._order_targets_cache = []
	g._guild._order_done = {}
	g._retention._circle_disc_day = ""
	g._retention._circle_disc = 0
	# --- v30: недельный слой ---
	g._retention._week_cache = {"week": "2026-W37",
		"vein": {"tag1": "Свет", "tag2": "Тьма", "spread": false, "my_hits": 0, "my_streaks": 0, "streak_cap": 5},
		"fair": {"tag": "Трава", "goal": 22, "progress": 10, "apprentice": 2, "closed": false,
			"my_contrib": 1, "claimed": false}}
	Selftest.check("week claimable no", not g._retention._week_claimable())
	(g._retention._week_cache["fair"] as Dictionary)["closed"] = true
	(g._retention._week_cache["fair"] as Dictionary)["my_contrib"] = 3
	Selftest.check("week claimable yes", g._retention._week_claimable())
	(g._retention._week_cache["fair"] as Dictionary)["closed"] = false
	(g._retention._week_cache["fair"] as Dictionary)["my_contrib"] = 1
	(g._retention._week_cache["fair"] as Dictionary)["prev"] = {"week": "2026-W36", "kind": "ether", "amount": 60}
	Selftest.check("week claimable prev", g._retention._week_claimable())
	g._retention._vein_cap_total = 0
	g._retention._discover_vein_bonus({"vein": {"tag": "Свет", "points": 2, "streak": false}})
	Selftest.check("week vein points", g._retention._vein_cap_total == 0)
	g._retention._discover_vein_bonus({"vein": {"tag": "Свет", "points": 2, "streak": true}})
	Selftest.check("week vein streak", g._retention._vein_cap_total == 1)
	g._retention._fair_regen_total = 0.0
	g._engine.ether = 0
	g._retention._on_net_fair_claim_result({"ok": true, "grants": [{"week": "2026-W37", "kind": "regen", "amount": 0}]})
	Selftest.check("week claim regen", is_equal_approx(g._retention._fair_regen_total, Game.FAIR_REGEN_EACH))
	g._retention._on_net_fair_claim_result({"ok": true, "grants": [{"week": "2026-W36", "kind": "ether", "amount": 90}]})
	Selftest.check("week claim ether", g._engine.ether == 90)
	g._retention._fair_regen_total = 0.49
	g._retention._on_net_fair_claim_result({"ok": true, "grants": [{"week": "2026-W37", "kind": "regen", "amount": 0}]})
	Selftest.check("week claim regen cap", is_equal_approx(g._retention._fair_regen_total, 0.5))
	g._retention._fair_regen_total = 0.0
	g._retention._on_net_fair_brew_result({"ok": true, "counted": true, "progress": 11, "contrib": 2, "closed": false})
	Selftest.check("week brew cache", int(g._retention._week_fair().get("progress", 0)) == 11 and int(g._retention._week_fair().get("my_contrib", 0)) == 2)
	g._retention._refresh_week_page()
	Selftest.check("week chip dot", String((g._pages._mode_chips["week"] as Button).text) == "Неделя ●")
	g._retention._week_cache = {}
	g._retention._refresh_week_page()
	Selftest.check("week chip calm", String((g._pages._mode_chips["week"] as Button).text) == "Неделя")
	var b_week := Net._build_request({"kind": "week", "path": "/week/status?device_id=d"})
	Selftest.check("net week route", String(b_week["url"]).ends_with("/week/status?device_id=d") and int(b_week["method"]) == HTTPClient.METHOD_GET)
	var b_fair := Net._build_request({"kind": "fair_brew", "path": "/fair/brew", "body": {"device_id": "d", "a": "x", "b": "y"}})
	Selftest.check("net fair route", String(b_fair["url"]).ends_with("/api/fair/brew") and int(b_fair["method"]) == HTTPClient.METHOD_POST)
	# ============ U36 (A3): офлайн-котёл ярмарки ============
	var u36_total := g._retention._fair_regen_total
	var u36_lw := g._retention._fair_local_week
	var u36_lb := (g._retention._fair_local_brews as Array).duplicate()
	var u36_ow := g._retention._fair_off_claim_week
	g._retention._fair_local_week = ""
	g._retention._fair_local_brews.clear()
	g._retention._fair_off_claim_week = ""
	g._retention._fair_regen_total = 0.0
	Selftest.check("u36 not claimable empty", not g._retention._fair_offline_claimable())
	for u36_out in ["steam", "stone", "steam", "clay"]:
		g._retention._fair_on_brew(u36_out)
	Selftest.check("u36 distinct counted", (g._retention._fair_local_brews as Array).size() == 3)
	Selftest.check("u36 claimable at 3", g._retention._fair_offline_claimable())
	g._retention._fair_offline_claim()
	Selftest.check("u36 half regen", absf(g._retention._fair_regen_total - Game.FAIR_REGEN_EACH * Game.FAIR_OFFLINE_FACTOR) < 0.0001)
	Selftest.check("u36 once per week", not g._retention._fair_offline_claimable()
		and g._retention._fair_off_claim_week == Home._iso_week_id())
	# потолок общий с серверной ярмаркой
	g._retention._fair_regen_total = Game.FAIR_REGEN_CAP
	g._retention._fair_off_claim_week = ""
	Selftest.check("u36 cap respected", not g._retention._fair_offline_claimable())
	# неделя сменилась — счётчик обнулился, ключ недели поменялся
	g._retention._fair_regen_total = 0.0
	g._retention._fair_local_week = "2000-W01"
	g._retention._fair_off_claim_week = "2000-W01"
	g._retention._fair_on_brew("steam")
	Selftest.check("u36 week rollover resets", (g._retention._fair_local_brews as Array).size() == 1
		and g._retention._fair_local_week == Home._iso_week_id()
		and g._retention._fair_off_claim_week == "2000-W01")
	# restore
	g._retention._fair_regen_total = u36_total
	g._retention._fair_local_week = u36_lw
	g._retention._fair_local_brews = u36_lb
	g._retention._fair_off_claim_week = u36_ow
