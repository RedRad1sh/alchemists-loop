extends RefCounted
class_name SuiteRiddlesRetention
# письма/атлас/панч-лист + бывшие круг/неделя (оп B1). Доска v2 Task 5:
# вкладки «Круг»/«Неделя» удалены — проверки их страниц сняты, поведение
# очага/жилы/ярмарки проверяется на поверхности Contracts.

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
	# --- v29: дневной круг → доска v2 Task 4: очаг/вехи/ранг переехали в Contracts.
	# Старые «шаги диска» и награда 75⚡ за закрытый круг удалены (спека §1/§3);
	# ниже — замены 1:1: очки = тир закрытого контракта, цель дня = контракт
	# goal_day, «круг закрыт» = зеркало заказов гильдии на строке orders.
	var cb4_snap := SuiteContractBoard._cb_snapshot(g._contracts)
	var cb4_ether := g._engine.ether
	g._contracts._visit_days = ["2026-01-01", "2026-01-02"]
	g._contracts._last_visit_day = g._contracts._visit_yesterday()
	g._contracts._streak_run = 4
	g._contracts.track_visit()
	Selftest.check("circle visit run+", g._contracts._streak_run == 5 and g._contracts._last_visit_day == g._contracts._visit_today() and g._contracts._visit_days.has(g._contracts._visit_today()))
	g._contracts.track_visit()
	Selftest.check("circle visit idem", g._contracts._streak_run == 5)
	g._contracts._last_visit_day = "2020-01-01"
	g._contracts.track_visit()
	Selftest.check("circle visit gap", g._contracts._streak_run == 1)
	g._contracts._streak_run = 3
	g._contracts._hearth_claim = ""
	Selftest.check("circle hearth math", g._contracts.hearth_reward() == 13 and g._contracts.hearth_claimable())
	g._engine.ether = 0
	g._contracts.claim_hearth()
	Selftest.check("circle hearth claim", g._engine.ether == 13 and not g._contracts.hearth_claimable())
	g._contracts.claim_hearth()
	Selftest.check("circle hearth once", g._engine.ether == 13)
	# Очки вех = тир закрытого контракта (было: шаги диска по числу синтезов).
	g._contracts._pts_total = 0
	g._contracts._mpts = 0
	g._contracts._mdays = 0
	g._contracts._add_milestone_points("bronze")
	Selftest.check("circle point bronze counts one", g._contracts._pts_total == 1)
	g._contracts._add_milestone_points("silver")
	g._contracts._add_milestone_points("gold")
	Selftest.check("circle points sum by tier values", g._contracts._pts_total == 6 and g._contracts._mpts == 0)
	# Сейв-ключ circle_pts_total переехал на Contracts — прогресс не теряется.
	g._saves._save_game()
	g._contracts._pts_total = 0
	g._saves._load_game()
	Selftest.check("circle points same-day save preserved", g._contracts._pts_total == 6)
	g._contracts._add_milestone_points("bronze")
	Selftest.check("circle points extend after load", g._contracts._pts_total == 7)
	# Дни визита считаются суммарно: семь дней — первая веха дней (было: сброс
	# диска на новый день — теперь сброса нет, в вечные вехи идёт сумма).
	while g._contracts._visit_days.size() < 7:
		g._contracts._visit_days.append("2026-01-%02d" % (g._contracts._visit_days.size() + 3))
	g._contracts._check_day_miles()
	Selftest.check("circle day miles fire on visit days", g._contracts._mdays == 1)
	# Порог очков срабатывает ровно один раз (было: «диск закрыт» за 5 синтезов).
	g._contracts._pts_total = 60
	g._contracts._check_pts_miles()
	Selftest.check("circle points miles fire", g._contracts._mpts == 1)
	g._contracts._check_pts_miles()
	Selftest.check("circle points miles stay at one", g._contracts._mpts == 1)
	Selftest.check("circle day miles", g._contracts._day_miles_for(6) == 0 and g._contracts._day_miles_for(7) == 1 and g._contracts._day_miles_for(365) == 4)
	Selftest.check("circle pts miles", g._contracts._pts_miles_for(49) == 0 and g._contracts._pts_miles_for(50) == 1 and g._contracts._pts_miles_for(500) == 3)
	g._contracts._mdays = 2
	g._contracts._mpts = 1
	Selftest.check("circle cap bonus", g._contracts._mile_cap_bonus() == 8)
	Selftest.check("circle regen bonus", is_equal_approx(g._contracts._mile_regen_bonus(), 0.05))
	g._contracts._mdays = 0
	g._contracts._mpts = 0
	Selftest.check("circle aura gate", not g._contracts.hearth_aura())
	g._contracts._mdays = 4
	Selftest.check("circle aura open", g._contracts.hearth_aura() and g._home._aura_color("hearth") == Color("#ff7a2e"))
	g._contracts._mdays = 0
	# «Круг закрыт» теперь = зеркало заказов на строке orders + открытая цель дня;
	# награду дня отдаёт claim по таблице gold (старые 75⚡ за круг удалены).
	var cb4_gd := SuiteContractBoard._mk(g._contracts, "daily", "goal_day", "gold", 1)
	var cb4_od := SuiteContractBoard._mk(g._contracts, "daily", "orders", "gold", 3)
	var cb4_gd_id := String(cb4_gd["id"])
	var cb4_od_id := String(cb4_od["id"])
	SuiteContractBoard._force_set(g._contracts, [cb4_gd, cb4_od], g._contracts._contracts_weekly)
	SuiteContractBoard._clear_prog(g._contracts)
	g._guild._order_day = g._contracts._visit_today()
	g._guild._order_targets_cache = ["steam", "stone", "clay"]
	g._guild._order_done = {"steam": true, "stone": true, "clay": true}
	g._contracts._sync_orders()
	Selftest.check("circle orders mirror closed guild", g._contracts.progress(cb4_od_id) == 3
		and g._contracts.is_ready(cb4_od_id))
	var cb4_lo := g._contracts._local_goal()
	g._contracts.on_brew(String(cb4_lo.get("out", "")), String(cb4_lo.get("a", "")),
		String(cb4_lo.get("b", "")), false, "manual")
	Selftest.check("circle goal ready on local brew", g._contracts.is_ready(cb4_gd_id))
	g._engine.ether = 0
	var cb4_reward := g._contracts.claim(cb4_gd_id)
	Selftest.check("goal contract pays day reward", bool(cb4_reward["ok"])
		and g._contracts.is_done(cb4_gd_id))
	Selftest.check("goal contract reward once only",
		String(g._contracts.claim(cb4_gd_id)["reason"]) == "claimed")
	# доска v2 Task 5: чип-индикаторы вкладки «Круг» удалены вместе с вкладкой —
	# claimable-очаг виден на доске (hearth_claimable уже проверен выше).
	g._engine.ether = cb4_ether
	SuiteContractBoard._cb_restore(g._contracts, cb4_snap)
	# ============ U35 (A3): цель дня = закреплённый контракт goal_day ============
	# Доска v2 Task 4: локальная цель никуда не делась — она кормит прогресс
	# goal_day (on_brew по совпадению с _local_goal), а серверное испытание
	# закрывает цель mark_day_challenge() без всякой выдачи. Старые флаги
	# _circle_local_done_day/_circle_mine и локальные очки удалены — замены 1:1.
	var u35_snap := SuiteContractBoard._cb_snapshot(g._contracts)
	var u35_g0 := g._contracts._local_goal()
	var u35_gd := SuiteContractBoard._mk(g._contracts, "daily", "goal_day", "gold", 2)
	var u35_gd_id := String(u35_gd["id"])
	var u35_od := SuiteContractBoard._mk(g._contracts, "daily", "orders", "silver", 3)
	var u35_od_id := String(u35_od["id"])
	SuiteContractBoard._force_set(g._contracts, [u35_gd, u35_od], g._contracts._contracts_weekly)
	SuiteContractBoard._clear_prog(g._contracts)
	Selftest.check("u35 goal contract open before", not g._contracts.is_done(u35_gd_id))
	# детерминизм: один и тот же день — одна и та же цель
	var u35_g1 := g._contracts._local_goal_for("2026-09-25")
	var u35_g2 := g._contracts._local_goal_for("2026-09-25")
	Selftest.check("u35 deterministic", String(u35_g1.get("out", "")) == String(u35_g2.get("out", ""))
		and String(u35_g1.get("a", "")) == String(u35_g2.get("a", "")))
	# достижима из баз: оба реагента — базовые стихии; цель никогда не пуста
	Selftest.check("u35 base-only and nonempty", not u35_g0.is_empty()
		and Game.BASE_IDS.has(String(u35_g0["a"])) and Game.BASE_IDS.has(String(u35_g0["b"])))
	# дата действительно участвует: на 12 датах подряд встречается ≥ 2 разных выхода
	var u35_variants := {}
	for u35_i in range(12):
		var u35_gx := g._contracts._local_goal_for("2026-10-%02d" % (u35_i + 1))
		u35_variants[String(u35_gx.get("out", ""))] = true
	Selftest.check("u35 date matters", u35_variants.size() >= 2)
	# чужая варка цель не двигает (было: «u35 wrong output ignored»)
	g._contracts.on_brew("dragon", "", "", false, "manual")
	Selftest.check("u35 foreign brew ignored", g._contracts.progress(u35_gd_id) == 0)
	# варка локальной цели двигает прогресс goal_day (было: «u35 local done»)
	var u35_out := String(u35_g0.get("out", ""))
	g._contracts.on_brew(u35_out, String(u35_g0.get("a", "")), String(u35_g0.get("b", "")), false, "manual")
	Selftest.check("u35 goal brew bumps progress", g._contracts.progress(u35_gd_id) == 1)
	g._contracts.on_brew(u35_out, "", "", false, "manual")
	# награда дня платит ровно один раз (было: «u35 points once» / «no double»):
	# claim платит по таблице gold + 3 очка вех, повторный тап — "claimed".
	var u35_pts0 := g._contracts._pts_total
	var u35_eth0 := g._engine._available_ether()
	var u35_got := g._contracts.claim(u35_gd_id)
	Selftest.check("u35 goal pays table on claim", bool(u35_got["ok"])
		and g._contracts.is_done(u35_gd_id) and g._contracts._pts_total == u35_pts0 + 3)
	var u35_again := g._contracts.claim(u35_gd_id)
	Selftest.check("u35 no double reward", not bool(u35_again["ok"])
		and String(u35_again["reason"]) == "claimed"
		and g._engine._available_ether() == u35_eth0
		and g._contracts._pts_total == u35_pts0 + 3)
	# серверное испытание закрывает цель без варки и без выдачи (было: «u35
	# server overrides» через _circle_mine — теперь через done-флаг goal_day)
	SuiteContractBoard._force_set(g._contracts, [u35_gd], g._contracts._contracts_weekly)
	SuiteContractBoard._clear_prog(g._contracts)
	var u35_ether1 := g._engine.ether
	var u35_pts1 := g._contracts._pts_total
	var u35_days1 := g._contracts._visit_days.size()
	g._contracts._day_hint = "Лодка"
	g._contracts.mark_day_challenge()
	Selftest.check("u35 server closes goal without payout", g._contracts.is_done(u35_gd_id)
		and g._contracts._pts_total == u35_pts1 and g._engine.ether == u35_ether1
		and g._contracts._visit_days.size() == u35_days1)
	# строка orders зеркалит счётчик гильдии (было: «цель требует все заказы»)
	SuiteContractBoard._force_set(g._contracts, [u35_od], g._contracts._contracts_weekly)
	SuiteContractBoard._clear_prog(g._contracts)
	g._guild._order_day = g._contracts._visit_today()
	g._guild._order_targets_cache = ["steam", "stone", "clay"]
	g._guild._order_done = {"steam": true, "stone": true, "clay": true}
	g._contracts._sync_orders()
	Selftest.check("u35 orders mirror guild done count", g._contracts.progress(u35_od_id) == 3
		and g._contracts.is_ready(u35_od_id))
	# серверная подсказка первична локальной цели: страница «Круг» удалена вместе
	# с вкладкой (доска v2 Task 5), канал данных доски — day_hint(); UI-строка
	# цели подключится к нему в Task 7.
	Selftest.check("u35 server hint overrides local goal", g._contracts.day_hint() == "Лодка")
	# restore
	g._guild._order_day = ""
	g._guild._order_targets_cache = []
	g._guild._order_done = {}
	SuiteContractBoard._cb_restore(g._contracts, u35_snap)
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
	# доска v2 Task 5: чип-индикаторы вкладки «Неделя» удалены вместе с вкладкой;
	# _week_claimable уже проверен выше, render-функции страницы больше нет.
	# Чистим фикстурный кэш недели — как это делал прежний «week chip calm».
	g._contracts._week_cache = {}
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
		# Доска v2 (Task 5): Retention удалён — снимок очага/вех/ранга целиком
		# едет в записи Contracts ниже (индекс snapshots[1]).
		[g._contracts, _circle_snapshot(g._contracts, ["_week_cache", "_cycle_cache", "_vein_finds",
			"_vein_cap_total", "_fair_regen_total", "_fair_local_week", "_fair_local_brews",
			"_fair_off_claim_week", "_visit_days", "_streak_run", "_last_visit_day",
			"_hearth_claim", "_pts_total", "_mdays", "_mpts", "_unlocked_titles",
			"_active_title", "_day_hint", "_day_goal_cache", "_contracts_daily",
			"_contracts_daily_prog", "_contracts_daily_done", "_contracts_weekly",
			"_contracts_weekly_prog", "_contracts_weekly_done", "_contracts_last_daily",
			"_contracts_last_weekly", "_contracts_variety", "_contracts_set_week",
			"_active_buffs", "_unlocked_decor", "_last_output"])],
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
	var today := g._contracts._visit_today()
	# Доска v2 Task 4: счётчик «шагов диска» удалён — трекаем прогресс живого
	# brew-контракта. Офлайн-реплей (craft/bench) контрактам не поставляет
	# варок (on_brew, source == "offline_workshop" → early-return, спека §6.4),
	# поэтому эти две проверки инвертированы: шаги есть, счётчик стоит.
	var s4_brew := SuiteContractBoard._mk(g._contracts, "daily", "brew", "silver", 3)
	var s4_goal := SuiteContractBoard._mk(g._contracts, "daily", "goal_day", "gold", 5)
	var s4_orders := SuiteContractBoard._mk(g._contracts, "daily", "orders", "gold", 3)
	var s4_orders2 := SuiteContractBoard._mk(g._contracts, "daily", "orders", "silver", 3)
	var s4_b_id := String(s4_brew["id"])
	var s4_g_id := String(s4_goal["id"])
	var s4_o_id := String(s4_orders["id"])
	var s4_o2_id := String(s4_orders2["id"])
	SuiteContractBoard._force_set(g._contracts, [s4_brew, s4_goal, s4_orders, s4_orders2], g._contracts._contracts_weekly)
	SuiteContractBoard._clear_prog(g._contracts)
	g._contracts._visit_days = []
	g._contracts._streak_run = 0
	g._contracts._last_visit_day = ""
	g._contracts._hearth_claim = ""
	g._contracts._pts_total = 0
	g._contracts._mdays = 0
	g._contracts._mpts = 0
	g._contracts._day_hint = ""
	g._contracts._day_goal_cache = {"day": today, "a": "fire", "b": "water", "out": "steam"}
	g._guild._order_day = today
	g._guild._order_targets_cache = ["steam", "stone", "clay"]
	g._guild._order_done = {"steam": true, "stone": true, "clay": true}
	g._contracts._sync_orders()
	g._contracts._contracts_daily_prog[s4_o_id] = 3
	var s4_orders_got := g._contracts.claim(s4_o_id)
	Selftest.check("circle claim of closed orders records visit day",
		bool(s4_orders_got["ok"]) and g._contracts._visit_days.has(today)
		and g._contracts._streak_run == 1 and g._contracts._pts_total == 3)
	g._engine.selected = ["fire", "water"]
	var manual: Dictionary = await g._engine._brew()
	Selftest.check("circle manual known brew bumps contract once", not bool(manual.get("failed", true))
		and not bool(manual.get("newly_learned", true)) and g._contracts.progress(s4_b_id) == 1)
	var plan := {"ok": true, "total": 1, "ops": [{"a": "fire", "b": "water", "out": "steam", "n": 1}]}
	var bench: bool = await g._engine._run_bench_plan("steam", plan)
	Selftest.check("circle workshop known brew bumps contract once", bench and g._contracts.progress(s4_b_id) == 2)
	var production: bool = await g._engine._run_auto_plan("steam", plan)
	Selftest.check("circle production known brew bumps contract once", production and g._contracts.progress(s4_b_id) == 3)
	g._engine._craft_job = {"item": "steam", "completed": 0, "total_estimate": 1, "plan": plan, "discount": 1.0}
	var offline := g._saves._advance_craft_job_offline(Game.OFFLINE_MIN_SEC + 10.0)
	Selftest.check("circle offline craft commits step but moves no counter", int(offline.get("steps", 0)) == 1
		and g._contracts.progress(s4_b_id) == 3)
	g._engine.inventory["fire"] = 1
	g._engine.inventory["water"] = 1
	g._pages._bench_on = true
	g._pages._bench_target = "steam"
	g._saves._saves_bench_probe = true
	var bench_elapsed := maxf(Game.OFFLINE_MIN_SEC + 1.0,
		g._sigil.bench_interval("steam") / Game.BENCH_OFFLINE_FACTOR + 1.0)
	var offline_bench := g._saves._advance_bench_offline(bench_elapsed)
	Selftest.check("circle offline workshop commits step but moves no counter", int(offline_bench.get("steps", 0)) == 1
		and g._contracts.progress(s4_b_id) == 3)
	var s4_ready := g._contracts.is_ready(s4_b_id)
	var s4_claim := g._contracts.claim(s4_b_id)
	Selftest.check("circle counted repeats close the daily contract", s4_ready
		and bool(s4_claim["ok"]) and g._contracts.is_done(s4_b_id)
		and g._engine.inventory.size() == collection_size and collection_size >= g.ITEMS.size()
		and g._engine.known_recipes.size() == recipes_size)
	# Цель дня — отдельная строка доски: варки она считает сама, а закрытие
	# brew-контракта её не трогает.
	Selftest.check("circle goal contract stays open after brew claim", not g._contracts.is_done(s4_g_id))
	# Заказ гильдии: строка orders зеркалит счётчик гильдии, а не прогресс варок.
	g._guild._order_done.erase("clay")
	g._contracts._sync_orders()
	Selftest.check("circle orders row unready when a guild order reopens",
		not g._contracts.is_ready(s4_o2_id) and g._contracts.progress(s4_o2_id) == 2
		and g._contracts.progress(s4_b_id) == int(s4_brew["goal"]))
	g._guild._order_done["clay"] = true
	var s4_double_ether := g._engine._available_ether()
	var s4_double_pts := g._contracts._pts_total
	var s4_again := g._contracts.claim(s4_b_id)
	Selftest.check("circle closed contract claim pays exactly once", not bool(s4_again["ok"])
		and String(s4_again["reason"]) == "claimed"
		and g._engine._available_ether() == s4_double_ether
		and g._contracts._pts_total == s4_double_pts)
	# доска v2 Task 5: страница «Круг» удалена вместе с вкладкой — её контент
	# (описание доски, счётчик очага, подсказка режима) больше не что проверять;
	# живой эквивалент счётчика — track_visit/claim выше.
	# Отрицательные трассы: сорванный вход / ноль эфира / неизвестный рецепт /
	# родник и подарок — варки нет, значит ни один счётчик доски не двигается.
	# Свежий open-контракт: закрытые claim-ом выше сдвинуть нельзя по определению.
	var s4_b2 := SuiteContractBoard._mk(g._contracts, "daily", "brew", "silver", 6)
	var s4_b2_id := String(s4_b2["id"])
	SuiteContractBoard._force_set(g._contracts, [s4_b2], g._contracts._contracts_weekly)
	SuiteContractBoard._clear_prog(g._contracts)
	var count_before := g._contracts.progress(s4_b2_id)
	var no_inputs := g._engine._commit_brew("fire", "water")
	Selftest.check("circle failed missing ingredients counts zero", bool(no_inputs.get("failed", false))
		and g._contracts.progress(s4_b2_id) == count_before)
	g._engine.inventory["fire"] = 2
	g._engine.inventory["water"] = 2
	g._engine.ether = 0
	g._engine.ether_overflow = 0
	var no_ether := g._engine._commit_brew("fire", "water")
	Selftest.check("circle failed insufficient ether counts zero", bool(no_ether.get("failed", false))
		and g._contracts.progress(s4_b2_id) == count_before)
	g._engine.ether = 1000
	var failed := g._engine._commit_brew("fire", "fire")
	Selftest.check("circle failed unknown recipe counts zero", bool(failed.get("failed", false))
		and g._contracts.progress(s4_b2_id) == count_before)
	g._engine._collect_gain("fire")
	g._engine.spring_on = true
	g._engine.spring_source = "water"
	g._pages._spring_clock = 0.0
	g._engine._spring_tick(Game.SPRING_INTERVAL + 0.01)
	g._engine._gift_clock = 0.0
	g._engine._gift_tick(Game.GIFT_INTERVAL + 0.01)
	Selftest.check("circle sources spring and gifts count zero", g._contracts.progress(s4_b2_id) == count_before)
	g._engine.inventory.erase("steam")
	g._engine.inventory["fire"] = 2
	g._engine.inventory["water"] = 2
	var first_brew := g._engine._commit_brew("fire", "water")
	Selftest.check("circle first local acquisition bumps contract once", not bool(first_brew.get("failed", true))
		and g._contracts.progress(s4_b2_id) == count_before + 1 and g._engine.inventory.has("steam"))

	# Online-ветки больше не питают дневные счётчики: выдача вещества мира — не
	# варка (on_brew зовётся только из _commit_brew), поэтому все ответы дают
	# нулевое движение. Повторы прежних «counts once»-проверок инвертированы.
	g._contracts._contracts_daily_prog[s4_b2_id] = 0
	var pair := g._pair_key("fire", "water")
	var element := {"slug": "steam", "name": g._online._item_name("steam"), "layer": 1,
		"a": "fire", "b": "water", "reused": true}
	var found := {"ok": true, "found": true, "status": "known", "out": element}
	var known := {"status": "known", "discovery": element}
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_pair_result(pair, found)
	Selftest.check("circle online found repeat moves no counter", g._contracts.progress(s4_b2_id) == 0)
	count_before = g._contracts.progress(s4_b2_id)
	g._online._on_net_pair_result(pair, found)
	g._online._on_net_discover_result(pair, known)
	Selftest.check("circle duplicate online answers count zero", g._contracts.progress(s4_b2_id) == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_discover_result(pair, known)
	Selftest.check("circle online known discovery repeat moves no counter", g._contracts.progress(s4_b2_id) == 0)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_discover_result(pair, {"status": "created", "discovery": element})
	Selftest.check("circle online created reused acquisition moves no counter", g._contracts.progress(s4_b2_id) == 0)
	for outcome in [found, {"status": "created", "discovery": element}]:
		g._engine.inventory["fire"] = 2
		g._engine.inventory["water"] = 2
		g._engine.known_recipes.erase(pair)
		g._engine._experiment_last_at = 0.0
		g._engine._experiment_count = 0
		var started := g._engine._begin_experiment("fire", "water")
		var registered := g._online._register_pending_pair("fire", "water", true)
		count_before = g._contracts.progress(s4_b2_id)
		if outcome.has("out"):
			g._online._on_net_pair_result(pair, outcome)
		else:
			g._online._on_net_discover_result(pair, outcome)
		Selftest.check("circle experiment %s repeat moves no counter" % ("found" if outcome.has("out") else "created"),
			started and registered and g._contracts.progress(s4_b2_id) == count_before
			and g._engine._experiment_pending_pair.is_empty())
		count_before = g._contracts.progress(s4_b2_id)
		g._online._on_net_pair_result(pair, found)
		g._online._on_net_discover_result(pair, known)
		Selftest.check("circle duplicate experiment answers count zero", g._contracts.progress(s4_b2_id) == count_before)
	count_before = g._contracts.progress(s4_b2_id)
	g._online._register_pending_pair("fire", "water", false)
	g._online._pending_requests[pair]["at"] = Time.get_ticks_msec() - Online.PENDING_TTL_MSEC - 1
	g._online._on_net_pair_result(pair, found)
	Selftest.check("circle stale online answer counts zero", g._contracts.progress(s4_b2_id) == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_discover_result(pair, {"status": "known", "discovery": {
		"slug": "steam", "name": "Пар", "a": "earth", "b": "air"}})
	Selftest.check("circle mismatched online answer counts zero", g._contracts.progress(s4_b2_id) == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_pair_result(pair, {"ok": true, "found": true, "out": {"slug": "steam", "name": ""}})
	Selftest.check("circle invalid online element counts zero", g._contracts.progress(s4_b2_id) == count_before)
	g._online._register_pending_pair("fire", "water", false)
	g._online._on_net_pair_result(pair, {"status": "not_combinable"})
	Selftest.check("circle rejected online answer counts zero", g._contracts.progress(s4_b2_id) == count_before)
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
	var contracts_before: Dictionary = snapshots[1][1]
	Selftest.check("circle synthesis fixture restores gameplay state", g._engine.inventory == engine_before["inventory"]
		and g._engine.known_recipes == engine_before["known_recipes"]
		and g._engine.ether == engine_before["ether"] and g._engine.ether_overflow == engine_before["ether_overflow"]
		and g._contracts._pts_total == contracts_before["_pts_total"]
		and g._contracts._hearth_claim == contracts_before["_hearth_claim"]
		and g._contracts._contracts_daily == contracts_before["_contracts_daily"]
		and g.is_processing() == processing_before)
	g._engine._refresh()
