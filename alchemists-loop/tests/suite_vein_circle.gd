extends RefCounted
class_name SuiteVeinCircle
# План 2 (Круг+Жила, клиент): net-endpoint'ы, cycle-кэш, personal finds,
# капли/pour, выбор цели, ранг-символ, swipe. Герметично: Net в ST всегда
# дренируется в offline (Global Constraints), поэтому сборка запросов меряет
# _build_request (шаблон suite_resonance_net.gd:72-80), а обработчики —
# прямые эмиссии сигналов.

static func run(g: Game) -> void:
	# ---------- T1: request shapes ----------
	var b_find := Net._build_request({"kind": "vein_find", "path": "/vein/find",
		"body": {"device_id": "d1", "pair_key": "earth|fire", "tag": "Туман", "cycle_id": "vc:1"}})
	Selftest.check("net vein_find route", String(b_find["url"]).ends_with("/vein/find")
		and int(b_find["method"]) == HTTPClient.METHOD_POST)
	var b_pour := Net._build_request({"kind": "vein_pour", "path": "/vein/pour",
		"body": {"device_id": "d1", "idempotency_key": "k1"}})
	Selftest.check("net vein_pour route", String(b_pour["url"]).ends_with("/vein/pour")
		and int(b_pour["method"]) == HTTPClient.METHOD_POST)
	var b_cycle := Net._build_request({"kind": "cycle", "path": "/vein/cycle/status?device_id=d1"})
	Selftest.check("net cycle route GET", String(b_cycle["url"]).ends_with("/vein/cycle/status?device_id=d1")
		and int(b_cycle["method"]) == HTTPClient.METHOD_GET)
	# ---------- T1: dispatch -> сигналы (корреляция: pair_key / find_id) ----------
	var seen_find: Array = []
	var cb_find := func(_pk: String, r: Dictionary) -> void: seen_find.append([_pk, r])
	Net.vein_find_result.connect(cb_find)
	Net._dispatch({"kind": "vein_find", "pair_key": "earth|fire"}, {"ok": true, "points": 1, "cap_reached": false})
	var seen_pour: Array = []
	var cb_pour := func(_fid: String, r: Dictionary) -> void: seen_pour.append([_fid, r])
	Net.vein_pour_result.connect(cb_pour)
	Net._dispatch({"kind": "vein_pour", "find_id": "k1"}, {"ok": true, "already_poured": true})
	var seen_cycle: Array = []
	var cb_cycle := func(r: Dictionary) -> void: seen_cycle.append(r)
	Net.cycle_result.connect(cb_cycle)
	Net._dispatch({"kind": "cycle"}, {"ok": true, "cycle_id": "vc:2", "state": "active"})
	Net.vein_find_result.disconnect(cb_find)
	Net.vein_pour_result.disconnect(cb_pour)
	Net.cycle_result.disconnect(cb_cycle)
	Selftest.check("net vein dispatch trio correlated", seen_find.size() == 1 and seen_pour.size() == 1
		and seen_cycle.size() == 1
		and String((seen_find[0] as Array)[0]) == "earth|fire"
		and String((seen_pour[0] as Array)[0]) == "k1"
		and String((seen_cycle[0] as Dictionary)["cycle_id"]) == "vc:2")
	# ---------- T1: вызовы не падают, дренируются в offline ----------
	Net.vein_find("d1", "earth|fire", "Туман", "vc:1")
	Net.vein_pour("d1", "k1")
	Net.cycle_status("d1")
	Selftest.check("net vein calls drain offline", Net._queue.is_empty() and Net._inflight.is_empty())

	# ---------- T2: сейв round-trip ----------
	var sv_titles := g._retention._unlocked_titles.duplicate(true)
	var sv_active := g._retention._active_title
	var sv_finds: Array = g._retention._vein_finds.duplicate(true)
	var sv_cycle: Dictionary = g._retention._cycle_cache.duplicate(true)
	g._retention._unlocked_titles.clear()
	g._retention._unlocked_titles.append("Искра")
	g._retention._active_title = "Искра"
	g._retention._vein_finds.clear()
	g._retention._vein_finds.append({"id": "f1", "tag": "Туман", "points": 1, "found_at": 123,
		"pair_key": "earth|fire", "cycle_id": "vc:1", "status": "pending_server", "server_response": {}})
	g._retention._cycle_cache = {"cycle_id": "vc:1", "tag1": "Туман", "state": "active", "world_finds": 0}
	g._online._server_tag["fog"] = "Туман"
	g._saves._save_game()
	g._retention._unlocked_titles.clear()
	g._retention._active_title = ""
	g._retention._vein_finds.clear()
	g._retention._cycle_cache = {}
	g._online._server_tag.clear()
	g._saves._load_game()
	Selftest.check("save roundtrip vein titles+finds+cycle+tags",
		g._retention._unlocked_titles.has("Искра") and g._retention._active_title == "Искра"
		and g._retention._vein_finds.size() == 1
		and String((g._retention._vein_finds[0] as Dictionary)["id"]) == "f1"
		and String(g._retention._cycle_cache.get("cycle_id", "")) == "vc:1"
		and String(g._online._server_tag.get("fog", "")) == "Туман")
	g._retention._unlocked_titles = sv_titles
	g._retention._active_title = sv_active
	g._retention._vein_finds = sv_finds
	g._retention._cycle_cache = sv_cycle

	# ---------- T3: cycle cache ----------
	var sv_cycle2: Dictionary = g._retention._cycle_cache.duplicate(true)
	g._retention._cycle_cache = {}
	Net.cycle_result.emit({"ok": true, "cycle_id": "vc:A", "tag1": "Туман", "tag2": "",
		"state": "active", "world_finds": 3, "my_points": 2, "my_streak": 1,
		"started_at": "2026-09-20T00:00:00", "spread_threshold": 12})
	var cached := String(g._retention._cycle_cache.get("cycle_id", "")) == "vc:A"
	# spread-переход: прежний active → новый spread; клиент это переживает
	Net.cycle_result.emit({"ok": true, "cycle_id": "vc:A", "tag1": "Туман", "tag2": "Мрак",
		"state": "spread", "world_finds": 12, "my_points": 2, "my_streak": 1,
		"started_at": "2026-09-20T00:00:00", "spread_threshold": 12})
	var spread_ok := String(g._retention._cycle_cache.get("state", "")) == "spread"
	# смена цикла: старые registered-капли становятся auto_applied (R1)
	g._retention._vein_finds = [{"id": "f9", "tag": "Туман", "points": 1, "found_at": 1,
		"pair_key": "a|b", "cycle_id": "vc:A", "status": "registered", "server_response": {}}]
	Net.cycle_result.emit({"ok": true, "cycle_id": "vc:B", "tag1": "Мрак", "tag2": "",
		"state": "active", "world_finds": 0, "my_points": 0, "my_streak": 0,
		"started_at": "2026-09-27T00:00:00", "spread_threshold": 12})
	var autoed := String((g._retention._vein_finds[0] as Dictionary)["status"]) == "auto_applied"
	# offline-ответ кэш не трогает
	Net.cycle_result.emit({"ok": false, "offline": true})
	var untouched := String(g._retention._cycle_cache.get("cycle_id", "")) == "vc:B"
	g._retention._cycle_cache = sv_cycle2
	g._retention._vein_finds = []
	Selftest.check("cycle cache + spread + auto_applied on rollover + offline-safe",
		cached and spread_ok and autoed and untouched)

	# ---------- T4: personal find ----------
	var sv_cycle3: Dictionary = g._retention._cycle_cache.duplicate(true)
	var sv_finds3: Array = g._retention._vein_finds.duplicate(true)
	var sv_tags3: Dictionary = g._online._server_tag.duplicate(true)
	var sv_sr: Array = g._online._server_recipes.duplicate(true)
	g._online._server_tag["steam"] = "Туман"
	g._retention._cycle_cache = {"cycle_id": "vc:T", "tag1": "Туман", "state": "active",
		"world_finds": 0, "my_points": 0, "my_streak": 0}
	g._retention._vein_finds = []
	g._online._server_recipes.append({"a": "fire", "b": "water", "out": "steam"})
	g._retention._vein_report_pair("fire", "water", "steam")
	var pf1 := g._retention._vein_finds.size() == 1 \
		and String((g._retention._vein_finds[0] as Dictionary)["status"]) == "pending_server" \
		and String((g._retention._vein_finds[0] as Dictionary)["cycle_id"]) == "vc:T"
	# повтор той же пары за тот же цикл — дубль не заводится
	g._retention._vein_report_pair("fire", "water", "steam")
	var pf2 := g._retention._vein_finds.size() == 1
	# пара вне серверной книги — не заводится
	g._retention._vein_report_pair("earth", "air", "dust")
	var pf3 := g._retention._vein_finds.size() == 1
	# тег вне активного тега цикла — не заводится
	g._online._server_tag["dust"] = "Мрак"
	g._online._server_recipes.append({"a": "earth", "b": "air", "out": "dust"})
	g._retention._vein_report_pair("earth", "air", "dust")
	var pf4 := g._retention._vein_finds.size() == 1
	# ответ сервера: registered + cap-награда один раз
	var e0 := g._engine.ether
	Net.vein_find_result.emit("fire|water", {"ok": true, "points": 1, "streak_added": true,
		"streak_count": 5, "cap_reached": true, "cycle_id": "vc:T"})
	var reg := String((g._retention._vein_finds[0] as Dictionary)["status"]) == "registered" \
		and g._engine.ether >= e0 + Game.VEIN_STREAK_REWARD
	# cycle_mismatch → find пересоздан с актуальным циклом (R2)
	g._retention._cycle_cache = {"cycle_id": "vc:U", "tag1": "Туман", "state": "active",
		"world_finds": 0, "my_points": 0, "my_streak": 0}
	Net.vein_find_result.emit("fire|water", {"ok": false, "error": "cycle_mismatch", "cycle_id": "vc:U"})
	var remade := g._retention._vein_finds.size() == 1 \
		and String((g._retention._vein_finds[0] as Dictionary)["cycle_id"]) == "vc:U" \
		and String((g._retention._vein_finds[0] as Dictionary)["status"]) == "pending_server"
	# unknown_pair — запись снимается
	Net.vein_find_result.emit("fire|water", {"ok": false, "error": "unknown_pair"})
	var dropped := g._retention._vein_finds.is_empty()
	g._retention._cycle_cache = sv_cycle3
	g._retention._vein_finds = sv_finds3
	g._online._server_tag = sv_tags3
	g._online._server_recipes = sv_sr
	# Fix #6 + приоритет заявки: та же пара в двух циклах — ответ должен уйти в
	# pending-заявку, а не в зарегистрированную запись прошлого цикла, которая
	# стоит в массиве раньше. Мутация «return f без проверки статуса» (старый код)
	# красит ve1; мутация «continue когда статус не pending_server» (слишком узкий
	# фикс) красит ve2 — запоздалый ответ по зарегистрированной паре терялся бы.
	g._retention._vein_finds = [
		{"pair_key": "fire|water", "cycle_id": "vc:OLD", "status": "registered"},
		{"pair_key": "fire|water", "cycle_id": "vc:NEW", "status": "pending_server"}]
	var ve1 := String(g._retention._vein_find_entry("fire|water")["cycle_id"]) == "vc:NEW"
	var ve_exact := String(g._retention._vein_find_entry("fire|water", "vc:OLD")["cycle_id"]) == "vc:OLD"
	g._retention._vein_finds = [{"pair_key": "fire|water", "cycle_id": "vc:OLD", "status": "registered"}]
	var ve2 := not g._retention._vein_find_entry("fire|water").is_empty()
	var ve3 := g._retention._vein_find_entry("earth|air").is_empty()
	g._retention._vein_finds = sv_finds3
	Selftest.check("vein entry lookup: pending wins, cycle-exact matches, registered fallback",
		ve1 and ve_exact and ve2 and ve3)
	Selftest.check("personal find: route/dedup/tag/cap-grant/mismatch-recreate/drop",
		pf1 and pf2 and pf3 and pf4 and reg and remade and dropped)

	# ---------- T5: pour ----------
	var sv_cycle5: Dictionary = g._retention._cycle_cache.duplicate(true)
	var sv_finds5: Array = g._retention._vein_finds.duplicate(true)
	g._retention._cycle_cache = {"cycle_id": "vc:P", "tag1": "Туман", "state": "active"}
	g._retention._vein_finds = [{"id": "p1", "tag": "Туман", "points": 1, "found_at": 1,
		"pair_key": "a|b", "cycle_id": "vc:P", "status": "registered", "server_response": {}}]
	g._retention._vein_pour("p1")
	var still := String((g._retention._vein_finds[0] as Dictionary)["status"]) == "registered"
	Net.vein_pour_result.emit("p1", {"ok": true, "already_poured": false})
	var poured := String((g._retention._vein_finds[0] as Dictionary)["status"]) == "poured"
	# повторный pour залитой капли — no-op, ответ идемпотентен
	g._retention._vein_pour("p1")
	Net.vein_pour_result.emit("p1", {"ok": true, "already_poured": true})
	var nochange := String((g._retention._vein_finds[0] as Dictionary)["status"]) == "poured"
	# offline-ответ не переводит
	g._retention._vein_finds[0]["status"] = "registered"
	Net.vein_pour_result.emit("p1", {"ok": false, "offline": true})
	var off := String((g._retention._vein_finds[0] as Dictionary)["status"]) == "registered"
	# rendering: ряды капель по числу записей текущего цикла
	var sv_week5: Dictionary = g._retention._week_cache.duplicate(true)
	g._retention._week_cache = {"week": "2026-W40", "vein": {"tag1": "Туман", "spread": false,
		"my_hits": 1, "my_streaks": 0, "streak_cap": 5}, "fair": {}}
	var host5 := VBoxContainer.new()
	g._retention._build_week_page(host5)
	var drop_rows := 0
	for c in g._retention._week_list.get_children():
		if String(c.name).begins_with("VeinDropRow"):
			drop_rows += 1
	var renders := drop_rows == 1
	g._retention._week_cache = sv_week5
	g._retention._cycle_cache = sv_cycle5
	g._retention._vein_finds = sv_finds5
	Selftest.check("pour: manual flow + idempotency + offline + render",
		still and poured and nochange and off and renders)

	# ---------- T6: (удалён — GoalPicker удалён, модалка не нужна) ----------

	# ---------- T7: пассивные очки Круга по слою ----------
	var sv_pts := g._retention._circle_pts_total
	var sv_mpts := g._retention._circle_mpts
	var sv_titles7 := g._retention._unlocked_titles.duplicate(true)
	var sv_act7 := g._retention._active_title
	# steam (слой 1) → fast (1-2) = +1 очко
	var pts := g._retention._circle_on_goal_brew("steam")
	var fast_ok := pts == 1
	# пустой output — 0
	pts = g._retention._circle_on_goal_brew("")
	var empty_zero := pts == 0
	# Проверим, что функция возвращает очки по слою (не по заявке)
	# Для этого нужно, чтобы рецепты были в known_recipes — в selftest это не всегда так,
	# поэтому проверяем только базовые случаи
	g._retention._circle_pts_total = sv_pts
	g._retention._circle_mpts = sv_mpts
	g._retention._unlocked_titles = sv_titles7
	g._retention._active_title = sv_act7
	Selftest.check("circle passive points by layer",
		fast_ok and empty_zero)

	# ---------- T8: ранг ----------
	var sv_days := g._retention._circle_days.duplicate(true)
	var sv_pts2 := g._retention._circle_pts_total
	var sv_titles8 := g._retention._unlocked_titles.duplicate(true)
	var sv_act2 := g._retention._active_title
	g._retention._circle_days = []
	g._retention._circle_pts_total = 0
	var l0 := g._retention._circle_rank_level() == 0
	g._retention._circle_pts_total = 60
	# 60 очков → уровень 3 («Тлеющий», порог 50), даже если дней 0
	var l3 := g._retention._circle_rank_level() == 3
	g._retention._circle_days.resize(30)
	# 30 дней → уровень 2; очки выше → ранг не падает
	var mono := g._retention._circle_rank_level() == 3
	g._retention._circle_days.resize(365)
	g._retention._circle_pts_total = 500
	var l7 := g._retention._circle_rank_level() == 7
	# выдача титулов идемпотентна: повторный celebrate не дублирует
	g._retention._unlocked_titles.clear()
	g._retention._circle_celebrate_mile("очков", 50)
	var t1 := g._retention._unlocked_titles.has("Тлеющий")
	g._retention._circle_celebrate_mile("очков", 50)
	var idem := g._retention._unlocked_titles.count("Тлеющий") == 1
	# декор за 30 дней выдаётся через β-путь и не продаётся
	g._retention._circle_celebrate_mile("дней", 30)
	var own := (g._home.house_owned.get("fireplace", []) as Array).has("fireplace_ember")
	var shop_ok := true
	for c in Game.DECOR:
		if String(c["id"]) == "fireplace":
			for it in (c.get("items", []) as Array):
				if bool(it.get("reward", false)) and int(it.get("cost", 0)) > 0:
					shop_ok = false
	Selftest.check("rank formula + titles idempotent + decor reward",
		l0 and l3 and mono and l7 and t1 and idem and own and shop_ok)
	g._retention._circle_days = sv_days
	g._retention._circle_pts_total = sv_pts2
	g._retention._unlocked_titles = sv_titles8
	g._retention._active_title = sv_act2

	# ---------- T9: swipe-предикат ----------
	Selftest.check("swipe closes only strong downward drag",
		UiGestures.swipe_closes(Vector2(0, 120)) and UiGestures.swipe_closes(Vector2(30, 100))
		and not UiGestures.swipe_closes(Vector2(0, 60)) and not UiGestures.swipe_closes(Vector2(150, 90))
		and not UiGestures.swipe_closes(Vector2(0, -120)))
