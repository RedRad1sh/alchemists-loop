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
	Selftest.check("circle synthesis repeat counts", g._retention._circle_disc == 1)
	g._retention._circle_on_discovery(true)
	g._retention._circle_on_discovery(true)
	Selftest.check("circle synthesis new and repeated count", g._retention._circle_disc == 3 and g._retention._circle_disc_day == g._retention._circle_today() and not g._retention._circle_disc_done())
	# Старые circle_disc-поля остаются: уже заработанный прогресс дня не теряется.
	g._saves._save_game()
	g._retention._circle_disc_day = ""
	g._retention._circle_disc = 0
	g._saves._load_game()
	Selftest.check("circle synthesis same-day save preserved", g._retention._circle_disc == 3
		and g._retention._circle_disc_day == g._retention._circle_today())
	g._retention._circle_on_discovery(false)
	Selftest.check("circle synthesis repeat extends saved progress", g._retention._circle_disc == 4)
	g._retention._circle_disc_day = g._retention._circle_yesterday()
	g._retention._circle_disc = Game.CIRCLE_DISC_GOAL
	Selftest.check("circle synthesis previous day is not done", not g._retention._circle_disc_done())
	g._retention._circle_on_discovery(false)
	Selftest.check("circle synthesis new day resets on repeat", g._retention._circle_disc == 1
		and g._retention._circle_disc_day == g._retention._circle_today())
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
	var circle_reward_ether := g._engine._available_ether()
	g._retention._circle_claim_reward()
	Selftest.check("circle reward exactly once", g._engine._available_ether() == circle_reward_ether)
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
	g._contracts._week_cache = {"week": "2026-W37",
		"vein": {"tag1": "Свет", "tag2": "Тьма", "spread": false, "my_hits": 0, "my_streaks": 0, "streak_cap": 5},
		"fair": {"tag": "Трава", "goal": 22, "progress": 10, "apprentice": 2, "closed": false,
			"my_contrib": 1, "claimed": false}}
	Selftest.check("week claimable no", not g._contracts._week_claimable())
	(g._contracts._week_cache["fair"] as Dictionary)["closed"] = true
	(g._contracts._week_cache["fair"] as Dictionary)["my_contrib"] = 3
	Selftest.check("week claimable yes", g._contracts._week_claimable())
	(g._contracts._week_cache["fair"] as Dictionary)["closed"] = false
	(g._contracts._week_cache["fair"] as Dictionary)["my_contrib"] = 1
	(g._contracts._week_cache["fair"] as Dictionary)["prev"] = {"week": "2026-W36", "kind": "ether", "amount": 60}
	Selftest.check("week claimable prev", g._contracts._week_claimable())
	g._contracts._vein_cap_total = 0
	g._contracts._discover_vein_bonus({"vein": {"tag": "Свет", "points": 2, "streak": false}})
	Selftest.check("week vein points", g._contracts._vein_cap_total == 0)
	g._contracts._discover_vein_bonus({"vein": {"tag": "Свет", "points": 2, "streak": true}})
	Selftest.check("week vein streak", g._contracts._vein_cap_total == 1)
	g._contracts._fair_regen_total = 0.0
	g._engine.ether = 0
	g._contracts._on_net_fair_claim_result({"ok": true, "grants": [{"week": "2026-W37", "kind": "regen", "amount": 0}]})
	Selftest.check("week claim regen", is_equal_approx(g._contracts._fair_regen_total, Game.FAIR_REGEN_EACH))
	g._contracts._on_net_fair_claim_result({"ok": true, "grants": [{"week": "2026-W36", "kind": "ether", "amount": 90}]})
	Selftest.check("week claim ether", g._engine.ether == 90)
	g._contracts._fair_regen_total = 0.49
	g._contracts._on_net_fair_claim_result({"ok": true, "grants": [{"week": "2026-W37", "kind": "regen", "amount": 0}]})
	Selftest.check("week claim regen cap", is_equal_approx(g._contracts._fair_regen_total, 0.5))
	g._contracts._fair_regen_total = 0.0
	g._contracts._on_net_fair_brew_result({"ok": true, "counted": true, "progress": 11, "contrib": 2, "closed": false})
	Selftest.check("week brew cache", int(g._contracts._week_fair().get("progress", 0)) == 11 and int(g._contracts._week_fair().get("my_contrib", 0)) == 2)
	g._retention._refresh_week_page()
	Selftest.check("week chip dot", String((g._pages._mode_chips["week"] as Button).text) == "Неделя ●")
	g._contracts._week_cache = {}
	g._retention._refresh_week_page()
	Selftest.check("week chip calm", String((g._pages._mode_chips["week"] as Button).text) == "Неделя")
	var b_week := Net._build_request({"kind": "week", "path": "/week/status?device_id=d"})
	Selftest.check("net week route", String(b_week["url"]).ends_with("/week/status?device_id=d") and int(b_week["method"]) == HTTPClient.METHOD_GET)
	var b_fair := Net._build_request({"kind": "fair_brew", "path": "/fair/brew", "body": {"device_id": "d", "a": "x", "b": "y"}})
	Selftest.check("net fair route", String(b_fair["url"]).ends_with("/api/fair/brew") and int(b_fair["method"]) == HTTPClient.METHOD_POST)
	# ============ U36 (A3): офлайн-котёл ярмарки ============
	var u36_total := g._contracts._fair_regen_total
	var u36_lw := g._contracts._fair_local_week
	var u36_lb := (g._contracts._fair_local_brews as Array).duplicate()
	var u36_ow := g._contracts._fair_off_claim_week
	g._contracts._fair_local_week = ""
	g._contracts._fair_local_brews.clear()
	g._contracts._fair_off_claim_week = ""
	g._contracts._fair_regen_total = 0.0
	Selftest.check("u36 not claimable empty", not g._contracts._fair_offline_claimable())
	for u36_out in ["steam", "stone", "steam", "clay"]:
		g._contracts._fair_on_brew(u36_out)
	Selftest.check("u36 distinct counted", (g._contracts._fair_local_brews as Array).size() == 3)
	Selftest.check("u36 claimable at 3", g._contracts._fair_offline_claimable())
	g._contracts._fair_offline_claim()
	Selftest.check("u36 half regen", absf(g._contracts._fair_regen_total - Game.FAIR_REGEN_EACH * Game.FAIR_OFFLINE_FACTOR) < 0.0001)
	Selftest.check("u36 once per week", not g._contracts._fair_offline_claimable()
		and g._contracts._fair_off_claim_week == Home._iso_week_id())
	# потолок общий с серверной ярмаркой
	g._contracts._fair_regen_total = Game.FAIR_REGEN_CAP
	g._contracts._fair_off_claim_week = ""
	Selftest.check("u36 cap respected", not g._contracts._fair_offline_claimable())
	# неделя сменилась — счётчик обнулился, ключ недели поменялся
	g._contracts._fair_regen_total = 0.0
	g._contracts._fair_local_week = "2000-W01"
	g._contracts._fair_off_claim_week = "2000-W01"
	g._contracts._fair_on_brew("steam")
	Selftest.check("u36 week rollover resets", (g._contracts._fair_local_brews as Array).size() == 1
		and g._contracts._fair_local_week == Home._iso_week_id()
		and g._contracts._fair_off_claim_week == "2000-W01")
	# restore
	g._contracts._fair_regen_total = u36_total
	g._contracts._fair_local_week = u36_lw
	g._contracts._fair_local_brews = u36_lb
	g._contracts._fair_off_claim_week = u36_ow
	await _test_circle_synthesis_paths(g)


static func _circle_snapshot(target: Object, fields: Array) -> Dictionary:
	var state := {}
	for field in fields:
		var value: Variant = target.get(String(field))
		state[field] = value.duplicate(true) if value is Array or value is Dictionary else value
	return state


static func _test_circle_synthesis_paths(g: Game) -> void:
	# Реальные ручная/производственные трассы и online-хендлеры, без сервера и моков.
	# Каждый затрагиваемый модуль восстанавливается, запись fixture заморожена.
	var processing_before := g.is_processing()
	g.set_process(false)
	var floaters_before := g.floaters.duplicate(true)
	var floater_labels_before: Array = []
	for floater in floaters_before:
		floater_labels_before.append(floater["l"])
	var snapshots := [
		[g._engine, _circle_snapshot(g._engine, ["inventory", "known_recipes", "selected", "ether",
			"ether_overflow", "attempts", "successes", "upgrades", "brewing", "brew_elapsed",
			"status_text", "_last_pair", "_auto", "_auto_cancel", "_auto_new", "_craft_job",
			"_blueprints", "_production_discount", "_layer_cache", "_cost_cache", "_book_sig", "_book_q",
			"_source_taps", "_collect_last_gain", "_gift_clock", "spring_on", "spring_source",
			"_experiment_pending_pair", "_experiment_day", "_experiment_count", "_experiment_last_at",
			"_rejected_pairs", "_first_open_calls"])],
		[g._retention, _circle_snapshot(g._retention, ["_circle_disc_day", "_circle_disc",
			"_circle_local_done_day", "_circle_local_goal_cache", "_circle_mine", "_circle_reward_day",
			"_circle_pts_total", "_circle_mpts", "_circle_head", "_circle_list"])],
		# Доска v2 (Task 3): недельный слой переехал в Contracts — снимок его полей
		# едет отдельной записью (индексы snapshots[0]/[1] выше по коду не
		# сдвигаются), иначе варка в этом тесте оставила бы чужой локальный котёл.
		[g._contracts, _circle_snapshot(g._contracts, ["_week_cache", "_cycle_cache", "_vein_finds",
			"_vein_cap_total", "_fair_regen_total", "_fair_local_week", "_fair_local_brews",
			"_fair_off_claim_week"])],
		[g._guild, _circle_snapshot(g._guild, ["_quest_brew", "_order_day", "_order_targets_cache", "_order_done"])],
		[g._pages, _circle_snapshot(g._pages, ["_bench_on", "_bench_target", "_bench_busy", "_spring_clock"])],
		[g._saves, _circle_snapshot(g._saves, ["_save_frozen", "_saves_bench_probe", "_return_craft_steps",
			"_return_craft_status", "_return_bench_steps", "_return_bench_items", "_return_bench_status"])],
		[g._online, _circle_snapshot(g._online, ["_pending_requests", "_server_layers", "_server_authors", "_net_enabled"])],
		[g._spirit, _circle_snapshot(g._spirit, ["_companion_affinity", "_companion_idle_clock"])],
	]
	var popup_visible := g._popup.visible
	var popup_dim_visible := g._popup_dim.visible
	g._saves._save_frozen = true
	g._online._net_enabled = false
	g._online._pending_requests.clear()
	g._contracts._cycle_cache = {}
	g._engine.brewing = false
	g._engine._auto = false
	g._pages._bench_busy = false
	g._engine.upgrades = {"brew_speed": 100, "auto_gift": 1}
	g._engine.ether = 1000
	g._engine.ether_overflow = 0
	g._engine._production_discount = 1.0
	g._engine._blueprints = {}
	g._engine._craft_job = {}
	g._engine._experiment_pending_pair.clear()
	for item in g.ITEMS:
		g._engine.inventory[String(item)] = 1
	for recipe in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(recipe["a"]), String(recipe["b"]))] = true
	g._engine.inventory["fire"] = 20
	g._engine.inventory["water"] = 20
	g._engine.inventory["steam"] = 0
	var collection_size := g._engine.inventory.size()
	var recipes_size := g._engine.known_recipes.size()
	var today := g._retention._circle_today()
	g._retention._circle_disc_day = today
	g._retention._circle_disc = 0
	g._retention._circle_pts_total = 0
	g._retention._circle_mpts = 0
	g._retention._circle_local_goal_cache = {"day": today, "a": "fire", "b": "water", "out": "steam"}
	g._retention._circle_local_done_day = ""
	g._retention._circle_mine = 0
	g._retention._circle_reward_day = ""
	g._guild._order_day = today
	g._guild._order_targets_cache = ["steam", "stone", "clay"]
	g._guild._order_done = {"steam": true, "stone": true, "clay": true}
	g._retention._circle_claim_reward()
	Selftest.check("circle status describes successful syntheses", g._engine.status_text.contains("успешных синтезов"))
	g._engine.selected = ["fire", "water"]
	var manual: Dictionary = await g._engine._brew()
	Selftest.check("circle manual known brew counts once", not bool(manual.get("failed", true))
		and not bool(manual.get("newly_learned", true)) and g._retention._circle_disc == 1)
	var plan := {"ok": true, "total": 1, "ops": [{"a": "fire", "b": "water", "out": "steam", "n": 1}]}
	var bench: bool = await g._engine._run_bench_plan("steam", plan)
	Selftest.check("circle workshop known brew counts once", bench and g._retention._circle_disc == 2)
	var production: bool = await g._engine._run_auto_plan("steam", plan)
	Selftest.check("circle production known brew counts once", production and g._retention._circle_disc == 3)
	g._engine._craft_job = {"item": "steam", "completed": 0, "total_estimate": 1, "plan": plan, "discount": 1.0}
	var offline := g._saves._advance_craft_job_offline(Game.OFFLINE_MIN_SEC + 10.0)
	Selftest.check("circle offline production counts committed steps", int(offline.get("steps", 0)) == 1
		and g._retention._circle_disc == 4)
	g._engine.inventory["fire"] = 1
	g._engine.inventory["water"] = 1
	g._pages._bench_on = true
	g._pages._bench_target = "steam"
	g._saves._saves_bench_probe = true
	var bench_elapsed := maxf(Game.OFFLINE_MIN_SEC + 1.0,
		g._sigil.bench_interval("steam") / Game.BENCH_OFFLINE_FACTOR + 1.0)
	var offline_bench := g._saves._advance_bench_offline(bench_elapsed)
	Selftest.check("circle offline workshop counts committed steps", int(offline_bench.get("steps", 0)) == 1
		and g._retention._circle_disc == Game.CIRCLE_DISC_GOAL)
	Selftest.check("circle full collection closes on five known repeats", g._retention._circle_closed()
		and g._engine.inventory.size() == collection_size and collection_size >= g.ITEMS.size()
		and g._engine.known_recipes.size() == recipes_size)
	# Остальные два условия остаются обязательными даже после пяти синтезов.
	g._retention._circle_local_done_day = ""
	Selftest.check("circle syntheses still require daily goal", not g._retention._circle_closed())
	g._retention._circle_local_done_day = today
	g._guild._order_done.erase("clay")
	Selftest.check("circle syntheses still require all orders", not g._retention._circle_closed())
	g._guild._order_done["clay"] = true
	var ether_before := g._engine._available_ether()
	g._retention._circle_claim_reward()
	g._retention._circle_claim_reward()
	Selftest.check("circle five repeats reward exactly once", g._engine._available_ether() == ether_before + 75
		and g._retention._circle_reward_day == today)
	var host := VBoxContainer.new()
	g._retention._build_circle_page(host)
	var description_ok := false
	var progress_ok := false
	for label in host.find_children("*", "Label", true, false):
		var text := (label as Label).text
		description_ok = description_ok or (text.contains("успешные синтезы дня") and text.contains("повторные"))
		progress_ok = progress_ok or text == "Успешные синтезы дня: %d/%d ✓" % [Game.CIRCLE_DISC_GOAL, Game.CIRCLE_DISC_GOAL]
	Selftest.check("circle page describes new and repeated syntheses", description_ok)
	Selftest.check("circle page displays successful synthesis progress", progress_ok)
	var circle_mode_hint := g._pages._mode_hint("circle")
	Selftest.check("circle mode hint describes repeated successful syntheses",
		circle_mode_hint.contains("успешные синтезы дня") and circle_mode_hint.contains("повторные"))
	host.free()
	# Отцепляем уничтоженную тестовую страницу до следующего refresh.
	g._retention._circle_head = null
	g._retention._circle_list = null
	var count_before := g._retention._circle_disc
	var no_inputs := g._engine._commit_brew("fire", "water")
	Selftest.check("circle failed missing ingredients counts zero", bool(no_inputs.get("failed", false))
		and g._retention._circle_disc == count_before)
	g._engine.inventory["fire"] = 2
	g._engine.inventory["water"] = 2
	g._engine.ether = 0
	g._engine.ether_overflow = 0
	var no_ether := g._engine._commit_brew("fire", "water")
	Selftest.check("circle failed insufficient ether counts zero", bool(no_ether.get("failed", false))
		and g._retention._circle_disc == count_before)
	g._engine.ether = 1000
	var failed := g._engine._commit_brew("fire", "fire")
	Selftest.check("circle failed unknown recipe counts zero", bool(failed.get("failed", false))
		and g._retention._circle_disc == count_before)
	g._engine._collect_gain("fire")
	g._engine.spring_on = true
	g._engine.spring_source = "water"
	g._pages._spring_clock = 0.0
	g._engine._spring_tick(Game.SPRING_INTERVAL + 0.01)
	g._engine._gift_clock = 0.0
	g._engine._gift_tick(Game.GIFT_INTERVAL + 0.01)
	Selftest.check("circle sources spring and gifts count zero", g._retention._circle_disc == count_before)
	g._engine.inventory.erase("steam")
	g._engine.inventory["fire"] = 2
	g._engine.inventory["water"] = 2
	var first_brew := g._engine._commit_brew("fire", "water")
	Selftest.check("circle first local acquisition counts once", not bool(first_brew.get("failed", true))
		and g._retention._circle_disc == count_before + 1 and g._engine.inventory.has("steam"))

	# Все success-ответы возвращают уже имеющийся steam: это именно повторные получения.
	g._retention._circle_disc = 0
	var pair := g._pair_key("fire", "water")
	var element := {"slug": "steam", "name": g._online._item_name("steam"), "layer": 1,
		"a": "fire", "b": "water", "reused": true}
	var found := {"ok": true, "found": true, "status": "known", "out": element}
	var known := {"status": "known", "discovery": element}
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_pair_result(pair, found)
	Selftest.check("circle online found repeat counts once", g._retention._circle_disc == 1)
	count_before = g._retention._circle_disc
	g._online._on_net_pair_result(pair, found)
	g._online._on_net_discover_result(pair, known)
	Selftest.check("circle duplicate online answers count zero", g._retention._circle_disc == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_discover_result(pair, known)
	Selftest.check("circle online known discovery repeat counts once", g._retention._circle_disc == 2)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_discover_result(pair, {"status": "created", "discovery": element})
	Selftest.check("circle online created reused acquisition counts once", g._retention._circle_disc == 3)
	for outcome in [found, {"status": "created", "discovery": element}]:
		g._engine.inventory["fire"] = 2
		g._engine.inventory["water"] = 2
		g._engine.known_recipes.erase(pair)
		g._engine._experiment_last_at = 0.0
		g._engine._experiment_count = 0
		var started := g._engine._begin_experiment("fire", "water")
		var registered := g._online._register_pending_pair("fire", "water", true)
		count_before = g._retention._circle_disc
		if outcome.has("out"):
			g._online._on_net_pair_result(pair, outcome)
		else:
			g._online._on_net_discover_result(pair, outcome)
		Selftest.check("circle experiment %s repeat counts once" % ("found" if outcome.has("out") else "created"),
			started and registered and g._retention._circle_disc == count_before + 1
			and g._engine._experiment_pending_pair.is_empty())
		count_before = g._retention._circle_disc
		g._online._on_net_pair_result(pair, found)
		g._online._on_net_discover_result(pair, known)
		Selftest.check("circle duplicate experiment answers count zero", g._retention._circle_disc == count_before)
	count_before = g._retention._circle_disc
	g._online._register_pending_pair("fire", "water", false)
	g._online._pending_requests[pair]["at"] = Time.get_ticks_msec() - Online.PENDING_TTL_MSEC - 1
	g._online._on_net_pair_result(pair, found)
	Selftest.check("circle stale online answer counts zero", g._retention._circle_disc == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_discover_result(pair, {"status": "known", "discovery": {
		"slug": "steam", "name": "Пар", "a": "earth", "b": "air"}})
	Selftest.check("circle mismatched online answer counts zero", g._retention._circle_disc == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_pair_result(pair, {"ok": true, "found": true, "out": {"slug": "steam", "name": ""}})
	Selftest.check("circle invalid online element counts zero", g._retention._circle_disc == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_pair_result(pair, {"status": "not_combinable"})
	Selftest.check("circle rejected online answer counts zero", g._retention._circle_disc == count_before)
	for floater in g.floaters:
		if not floater_labels_before.has(floater["l"]):
			(floater["l"] as Label).queue_free()
	g.floaters = floaters_before
	for snapshot in snapshots:
		var target: Object = snapshot[0]
		var state: Dictionary = snapshot[1]
		for field in state:
			target.set(String(field), state[field])
	g._popup.visible = popup_visible
	g._popup_dim.visible = popup_dim_visible
	g.set_process(processing_before)
	var engine_before: Dictionary = snapshots[0][1]
	var circle_before: Dictionary = snapshots[1][1]
	Selftest.check("circle synthesis fixture restores gameplay state", g._engine.inventory == engine_before["inventory"]
		and g._engine.known_recipes == engine_before["known_recipes"]
		and g._engine.ether == engine_before["ether"] and g._engine.ether_overflow == engine_before["ether_overflow"]
		and g._retention._circle_disc == circle_before["_circle_disc"]
		and g._retention._circle_disc_day == circle_before["_circle_disc_day"]
		and g.is_processing() == processing_before)
	g._engine._refresh()
	g._retention._refresh_circle_page()
