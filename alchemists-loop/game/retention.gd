extends RefCounted
class_name Retention
# Дневной круг + недельный слой (R2): очаг/вехи/награды круга, жила и ярмарка.
# Своё состояние — поля ниже; общее — через g (ноду Game). Имена — как были.

var g: Game

# дневной круг (v29): визиты/серия, открытия дня, кэш цели дня, вехи
var _circle_days: Array = []
var _circle_run := 0
var _circle_last := ""
var _hearth_claim := ""
var _circle_disc_day := ""
var _circle_disc := 0
var _circle_reward_day := ""
var _circle_pts_total := 0
var _circle_mdays := 0
var _circle_mpts := 0
var _circle_hint := ""
var _circle_mine := 0
var _circle_local_done_day := ""
var _circle_local_goal_cache := {}
var _circle_head: Label = null
var _circle_list: VBoxContainer = null
# недельный слой (v30): кэш статуса недели + вечные бонусы
var _week_cache: Dictionary = {}
var _week_offline := false
var _vein_cap_total := 0
var _fair_regen_total := 0.0
var _fair_local_week := ""
var _fair_local_brews: Array = []
var _fair_off_claim_week := ""
var _week_head: Label = null
var _week_list: VBoxContainer = null
# план 2: цикл жилы, pending finds, титулы ранга
var _cycle_cache: Dictionary = {}
var _vein_finds: Array = []
var _unlocked_titles: Array = []
var _active_title := ""
var _cycle_prev_state := ""

func _init(game: Game) -> void:
	g = game

# ---------- дневной круг: контейнер суточного слоя + очаг + вечные вехи (v29) ----------
# Три строки дня (цель, заказы, открытия) + награда за закрытие; очаг копит дни
# визитов мягко (пропуск не штрафует, лишь обнуляет множитель серии); вехи дней
# и вечных очков цели дают постоянный кап/реген и ауру «Очаг».

func _circle_today() -> String:
	return Time.get_date_string_from_system()


func _circle_yesterday() -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_system() - 86400.0)


func _circle_track_visit() -> void:
	var today := _circle_today()
	if _circle_last == today:
		return
	if not _circle_days.has(today):
		_circle_days.append(today)
		while _circle_days.size() > 400:
			_circle_days.pop_front()
	_circle_run = _circle_run + 1 if _circle_last == _circle_yesterday() else 1
	_circle_last = today
	_circle_check_day_miles()
	g._saves._save_game()
	_refresh_circle_page()
	g._engine._refresh()


func _circle_hearth_reward() -> int:
	return int(round(Game.HEARTH_BASE * (1.0 + minf(float(_circle_run), 10.0) * 0.1)))


func _circle_hearth_claimable() -> bool:
	return _hearth_claim != _circle_today()


func _circle_claim_hearth() -> void:
	if not _circle_hearth_claimable():
		return
	_hearth_claim = _circle_today()
	var gain := _circle_hearth_reward()
	g._engine._grant_ether(gain, "hearth")
	g._engine.status_text = "Очаг вспыхнул! +%d ⚡ (серия %d). Заглядывай завтра — угли не гаснут." % [gain, _circle_run]
	Sfx.stage_up()
	g._saves._save_game()
	_refresh_circle_page()
	g._engine._refresh()


func _circle_on_discovery(first_time: bool) -> void:
	if not first_time:
		return
	var today := _circle_today()
	if _circle_disc_day != today:
		_circle_disc_day = today
		_circle_disc = 0
	_circle_disc += 1
	_refresh_circle_page()


func _circle_orders_done() -> bool:
	g._guild._orders_refresh()
	return g._guild._order_targets_cache.size() > 0 and g._guild._order_done.size() >= g._guild._order_targets_cache.size()


func _circle_challenge_done() -> bool:
	return _circle_mine > 0 or _circle_local_done()


func _circle_local_goal_for(day: String) -> Dictionary:
	# Локальная цель дня (A3): детерминирована датой тем же приёмом, что заказы
	# гильдии (_order_targets_for), и заведомо достижима из базовых стихий —
	# только рецепты из двух баз.
	var h: String = ("local_goal_" + day).sha256_text()
	var pool: Array = []
	for r in g.RECIPES:
		if Game.BASE_IDS.has(String(r["a"])) and Game.BASE_IDS.has(String(r["b"])):
			pool.append(r)
	if pool.is_empty():
		return {}
	var idx := h.substr(0, 2).hex_to_int() % pool.size()
	return pool[idx]


func _circle_local_goal() -> Dictionary:
	var day := _circle_today()
	if String(_circle_local_goal_cache.get("day", "")) != day:
		var pick := _circle_local_goal_for(day)
		_circle_local_goal_cache = {"day": day}
		_circle_local_goal_cache.merge(pick)
	return _circle_local_goal_cache


func _circle_local_done() -> bool:
	return _circle_local_done_day == _circle_today() and _circle_local_done_day != ""


func _circle_on_local_brew(output: String) -> void:
	# Офлайн-закрытие «цели дня»: одна награда на день (ключ _circle_today());
	# серверная цель, когда связь есть, перебивает по факту (_circle_mine > 0),
	# двойного начисления нет — очки локали и сервера живут в одном счётчике.
	if output == "" or _circle_local_done():
		return
	if String(_circle_local_goal().get("out", "")) != output:
		return
	_circle_local_done_day = _circle_today()
	_circle_pts_total += Game.CIRCLE_LOCAL_POINTS
	_circle_check_pts_miles()
	if not g._selftest:
		g._hub._log_event("Локальная цель дня выполнена: +%d очк." % Game.CIRCLE_LOCAL_POINTS)
		g._saves._save_game()
		_refresh_circle_page()


func _circle_on_goal_brew(output: String) -> int:
	# §2.4: очки за цель начисляются ПОСЛЕ успешной варки и по ФАКТИЧЕСКОМУ
	# слою результата; пустая заявка (авто/верстак/эксперимент) не платит.
	var goal_key := g._engine.pending_circle_goal
	if goal_key == "" or output == "":
		return 0
	var l := g._engine._layer_of(output)
	for gm in Game.CIRCLE_GOALS:
		var lo := int((gm["layers"] as Array)[0])
		var hi := int((gm["layers"] as Array)[1])
		if String(gm["key"]) == goal_key and l >= lo and l <= hi:
			var pts := int(gm["pts"])
			_circle_pts_total += pts
			_circle_check_pts_miles()
			if not g._selftest:
				g._saves._save_game()
				_refresh_circle_page()
			return pts
	return 0


func _circle_disc_done() -> bool:
	return _circle_disc_day == _circle_today() and _circle_disc >= Game.CIRCLE_DISC_GOAL


func _circle_closed() -> bool:
	return _circle_challenge_done() and _circle_orders_done() and _circle_disc_done()


func _circle_reward_claimable() -> bool:
	return _circle_closed() and _circle_reward_day != _circle_today()


func _circle_claim_reward() -> void:
	if not _circle_closed():
		g._engine.status_text = "Круг ещё не закрыт: нужны цель дня, заказы 3/3 и %d открытий." % Game.CIRCLE_DISC_GOAL
		Sfx.error()
		return
	if _circle_reward_day == _circle_today():
		return
	_circle_reward_day = _circle_today()
	g._engine._grant_ether(Game.CIRCLE_REWARD, "daily_circle")
	g._engine.status_text = "Дневной круг закрыт! +%d ⚡. Светик гордится тобой." % Game.CIRCLE_REWARD
	g._spirit._companion_react("milestone", "круг")
	Sfx.legendary()
	g._saves._save_game()
	_refresh_circle_page()
	g._engine._refresh()


func _circle_day_miles_for(total: int) -> int:
	var n := 0
	for m in Game.CIRCLE_DAY_MILES:
		if total >= int(m):
			n += 1
	return n


func _circle_pts_miles_for(total: int) -> int:
	var n := 0
	for m in Game.CIRCLE_PTS_MILES:
		if total >= int(m):
			n += 1
	return n


func _circle_check_day_miles() -> void:
	var miles := _circle_day_miles_for(_circle_days.size())
	if miles > _circle_mdays:
		_circle_mdays = miles
		_circle_celebrate_mile("дней", int(Game.CIRCLE_DAY_MILES[miles - 1]))


func _circle_check_pts_miles() -> void:
	var miles := _circle_pts_miles_for(_circle_pts_total)
	if miles > _circle_mpts:
		_circle_mpts = miles
		_circle_celebrate_mile("очков", int(Game.CIRCLE_PTS_MILES[miles - 1]))


func _circle_mile_bonus(kind: String, m: int) -> Array:
	# [кап, реген, аура?]
	if kind == "дней":
		return [int(Game.CIRCLE_DAY_CAP.get(m, 0)), float(Game.CIRCLE_DAY_REGEN.get(m, 0.0)), m == 365]
	return [int(Game.CIRCLE_PTS_CAP.get(m, 0)), float(Game.CIRCLE_PTS_REGEN.get(m, 0.0)), false]


func _circle_mile_bonus_text(kind: String, m: int) -> String:
	var b := _circle_mile_bonus(kind, m)
	if bool(b[2]):
		return "Аура «Очаг» для дома Светика разблокирована!"
	var parts: Array = []
	if int(b[0]) > 0:
		parts.append("+%d к капу навсегда" % int(b[0]))
	if float(b[1]) > 0.0:
		parts.append("+%.2f к регену навсегда" % float(b[1]))
	return " и ".join(parts) if not parts.is_empty() else "Светик в восторге!"


func _circle_rank_level() -> int:
	# §2.2: max из двух треков (дни И очки) — активный идёт вперёд по очкам
	var lvl := 0
	for rk in Game.CIRCLE_RANKS:
		var have := _circle_days.size() if String(rk["kind"]) == "дней" else _circle_pts_total
		if have >= int(rk["threshold"]):
			lvl = maxi(lvl, int(rk["level"]))
	return lvl


func _circle_celebrate_mile(kind: String, m: int) -> void:
	var bonus := _circle_mile_bonus_text(kind, m)
	g._engine.status_text = "Веха Дневного круга: %d %s! %s" % [m, kind, bonus]
	g._hub._log_event("Веха круга: %d %s (%s)" % [m, kind, bonus])
	g._spirit._companion_react("milestone", str(m))
	Sfx.stage_up()
	# план 2 §2.2: титул + эксклюзивный декор на том же переходе (идемпотентно)
	var rank := {}
	for rk in Game.CIRCLE_RANKS:
		if String(rk["kind"]) == kind and int(rk["threshold"]) == m:
			rank = rk
	if not rank.is_empty():
		var title := String(rank["title"])
		if not _unlocked_titles.has(title):
			_unlocked_titles.append(title)
		if _circle_rank_level() >= int(rank["level"]):
			_active_title = title
		Analytics.track("circle_rank_up", {"rank_name": title, "days": _circle_days.size(),
			"points": _circle_pts_total})
		if kind == "дней" and Game.CIRCLE_DECOR_REWARDS.has(m):
			g._home._own_item("fireplace", String(Game.CIRCLE_DECOR_REWARDS[m]))
	g._saves._save_game()
	_refresh_circle_page()
	g._engine._refresh()


func _circle_cap_bonus() -> int:
	var total := 0
	for i in mini(_circle_mdays, Game.CIRCLE_DAY_MILES.size()):
		total += int(Game.CIRCLE_DAY_CAP.get(int(Game.CIRCLE_DAY_MILES[i]), 0))
	for i in mini(_circle_mpts, Game.CIRCLE_PTS_MILES.size()):
		total += int(Game.CIRCLE_PTS_CAP.get(int(Game.CIRCLE_PTS_MILES[i]), 0))
	return total


func _circle_regen_bonus() -> float:
	var total := 0.0
	for i in mini(_circle_mdays, Game.CIRCLE_DAY_MILES.size()):
		total += float(Game.CIRCLE_DAY_REGEN.get(int(Game.CIRCLE_DAY_MILES[i]), 0.0))
	for i in mini(_circle_mpts, Game.CIRCLE_PTS_MILES.size()):
		total += float(Game.CIRCLE_PTS_REGEN.get(int(Game.CIRCLE_PTS_MILES[i]), 0.0))
	return total


func _circle_hearth_aura() -> bool:
	return _circle_mdays >= Game.CIRCLE_DAY_MILES.size()


func _circle_flame() -> String:
	# ✦ вместо эмодзи огня: шрифт проекта не содержит 🔥 (тофу на кадре)
	if _circle_run >= 7:
		return "✦✦✦"
	if _circle_run >= 3:
		return "✦✦"
	if _circle_run >= 1:
		return "✦"
	return "·"


func _circle_rank_title(lvl: int) -> String:
	if lvl < 1:
		return "Новичок"
	for rk in Game.CIRCLE_RANKS:
		if int(rk["level"]) == lvl:
			return String(rk["title"])
	return "Новичок"


func _build_circle_page(container: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	col.add_child(g._label("Дневной круг", 17))
	var desc := g._label("Цель дня + заказы гильдии + открытия дня — в одном месте. Закрой круг и забери награду; очаг помнит каждый твой день.", 12)
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(desc)
	_circle_head = g._label("", 13)
	col.add_child(_circle_head)
	_circle_list = VBoxContainer.new()
	_circle_list.add_theme_constant_override("separation", 8)
	col.add_child(_circle_list)
	_refresh_circle_page()


func _circle_mile_strip(kind: String, miles: Array, have: int) -> String:
	var parts: Array = []
	for i in miles.size():
		var m := int(miles[i])
		parts.append("%d ✓" % m if i < have else str(m))
	return " · ".join(parts)


func _refresh_circle_page() -> void:
	if g._pages._mode_chips.has("circle"):
		(g._pages._mode_chips["circle"] as Button).text = "Круг ●" if (_circle_hearth_claimable() or _circle_reward_claimable()) else "Круг"
	if _circle_head == null or _circle_list == null:
		return
	_circle_head.text = "Очаг %s · дней в игре: %d · серия: %d · вечных очков: %d" % [
		_circle_flame(), _circle_days.size(), _circle_run, _circle_pts_total]
	for child in _circle_list.get_children():
		_circle_list.remove_child(child)
		child.queue_free()
	# §2.2: символ-ранг + титул — первой строкой страницы
	var rank_row := HBoxContainer.new()
	rank_row.name = "CircleRankRow"
	rank_row.add_theme_constant_override("separation", 10)
	var sym := CircleRankSymbol.new()
	sym.setup(_circle_rank_level())
	rank_row.add_child(sym)
	var rtxt := g._label(_circle_rank_title(_circle_rank_level()), 14)
	rtxt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_row.add_child(rtxt)
	_circle_list.add_child(rank_row)
	# очаг: полешко раз в день
	var hearth := HBoxContainer.new()
	hearth.add_theme_constant_override("separation", 8)
	_circle_list.add_child(hearth)
	var hl := g._label("Полешко: +%d ⚡" % _circle_hearth_reward(), 14)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hearth.add_child(hl)
	var hb := g._small_button("Забрано ✓" if not _circle_hearth_claimable() else "Подбросить", Vector2(150, 40), 2)
	hb.disabled = not _circle_hearth_claimable()
	hb.pressed.connect(_circle_claim_hearth)
	hearth.add_child(hb)
	# три строки круга
	var ch_txt := ""
	if _circle_hint != "":
		ch_txt = "Цель дня: %s" % _circle_hint
	elif not _circle_local_goal().is_empty() and String(_circle_local_goal().get("out", "")) != "":
		var lg := _circle_local_goal()
		ch_txt = "Цель дня (без мира): свари «%s» из %s и %s" % [
			g._online._item_name(String(lg["out"])),
			g._online._item_name(String(lg["a"])),
			g._online._item_name(String(lg["b"]))]
	else:
		ch_txt = "Цель дня: нужна связь с миром"
	if _circle_challenge_done():
		ch_txt += " ✓ (%d очк.)" % maxi(_circle_mine, Game.CIRCLE_LOCAL_POINTS if _circle_local_done() else 0)
	var ch := g._label(ch_txt, 14)
	if _circle_challenge_done():
		ch.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
	_circle_list.add_child(ch)
	g._guild._orders_refresh()
	var orow := g._label("Заказы гильдии: %d/3%s" % [g._guild._order_done.size(), " ✓" if _circle_orders_done() else ""], 14)
	if _circle_orders_done():
		orow.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
	_circle_list.add_child(orow)
	var dn := _circle_disc if _circle_disc_day == _circle_today() else 0
	var drow := g._label("Открытия дня: %d/%d%s" % [dn, Game.CIRCLE_DISC_GOAL, " ✓" if _circle_disc_done() else ""], 14)
	if _circle_disc_done():
		drow.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
	_circle_list.add_child(drow)
	# награда круга
	var rb := g._small_button("Награда круга: +%d ⚡" % Game.CIRCLE_REWARD, Vector2(0, 46), 2)
	if _circle_reward_day == _circle_today():
		rb.text = "Награда круга забрана ✓"
		rb.disabled = true
	elif not _circle_closed():
		rb.disabled = true
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.pressed.connect(_circle_claim_reward)
	_circle_list.add_child(rb)
	# вечные вехи
	var md := g._label("Вехи дней: %s" % _circle_mile_strip("дней", Game.CIRCLE_DAY_MILES, _circle_mdays), 13)
	md.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	_circle_list.add_child(md)
	var mp := g._label("Вехи очков: %s" % _circle_mile_strip("очков", Game.CIRCLE_PTS_MILES, _circle_mpts), 13)
	mp.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	_circle_list.add_child(mp)


func _inject_circle_demo() -> void:
	var today := _circle_today()
	_circle_days = ["2026-09-10", "2026-09-11", today]
	_circle_run = 3
	_circle_last = today
	_hearth_claim = ""
	_circle_disc_day = today
	_circle_disc = Game.CIRCLE_DISC_GOAL
	_circle_reward_day = ""
	_circle_pts_total = 61
	_circle_mdays = 0
	_circle_mpts = 1
	_circle_hint = "Свари что-нибудь из «Мха»"
	_circle_mine = 2
	g._guild._orders_refresh()
	for t in g._guild._order_targets_cache:
		g._guild._order_done[String(t)] = true

# ---------- недельный слой: туманная жила + ярмарка гильдии (v30) ----------
# Жила: первооткрытие с тегом недели → +2 очк. дня и 10% прожилка (+1 кап,
# кап 5/нед. — на сервере). Ярмарка: варки пар с выходом-тегом недели идут
# в общий котёл (пара — раз в неделю); закрытый котёл + вклад ≥3 → +0.05/с
# регена навсегда (кап +0.5 суммарно), иначе — утешение эфиром. Теги веществ живут
# на сервере; клиент оперирует только строками недели.

func _fetch_week() -> void:
	if not g._online._net_enabled or g._online._device_id == "":
		return
	if not Net.is_available():
		_week_offline = true
		_refresh_week_page()
		return
	Net.week_status(g._online._device_id)
	_fetch_cycle()


func _on_net_week_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		_week_offline = true
		_refresh_week_page()
		return
	_week_offline = false
	_week_cache = result
	g._saves._save_game()
	_refresh_week_page()


func _week_vein() -> Dictionary:
	var v = _week_cache.get("vein", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

# ---------- план 2: цикл жилы ----------

func _fetch_cycle() -> void:
	if not g._online._net_enabled or g._online._device_id == "":
		return
	if not Net.is_available():
		return
	Net.cycle_status(g._online._device_id)


func _on_net_cycle_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		return
	var prev_id := String(_cycle_cache.get("cycle_id", ""))
	_cycle_cache = result
	if String(result.get("state", "")) == "spread" and _cycle_prev_state != "spread":
		# R5: reason — порог достигнут или max_days; duration — от started_at до сегодня
		var wf := int(result.get("world_finds", 0))
		var thr := int(result.get("spread_threshold", 0))
		var dur := 0
		var sa := String(result.get("started_at", ""))
		if sa.length() >= 10:
			dur = maxi(0, int((Time.get_unix_time_from_system() - float(
				Time.get_unix_time_from_datetime_string(sa))) / 86400.0))
		Analytics.track("vein_cycle_spread", {"reason": "threshold" if wf >= thr else "max_days",
			"world_finds": wf, "duration_days": dur})
	_cycle_prev_state = String(result.get("state", ""))
	if prev_id != "" and String(result.get("cycle_id", "")) != prev_id:
		# R1: закрытие старого цикла — невлитые капли его становятся auto_applied
		var autoed := 0
		for f in _vein_finds:
			if typeof(f) == TYPE_DICTIONARY and String(f.get("cycle_id", "")) == prev_id \
					and String(f.get("status", "")) == "registered":
				f["status"] = "auto_applied"
				autoed += 1
				Analytics.track("vein_pour", {"tag": String(f.get("tag", "")), "manual": false})
		Analytics.track("vein_cycle_closed", {"auto_applied_count": autoed,
			"total_points": int(_cycle_cache.get("my_points", 0))})
		_vein_sync_pending()
	g._saves._save_game()
	_refresh_week_page()


func _vein_sync_pending() -> void:
	if not Net.is_available() or g._online._device_id == "":
		return
	var cyc := String(_cycle_cache.get("cycle_id", ""))
	if cyc == "":
		return
	for f in _vein_finds:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if String(f.get("status", "")) == "pending_server" and String(f.get("cycle_id", "")) == cyc:
			Net.vein_find(g._online._device_id, String(f["pair_key"]), String(f["tag"]), cyc)


func _vein_find_exists(cycle_id: String, pair_key: String) -> bool:
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("cycle_id", "")) == cycle_id \
				and String(f.get("pair_key", "")) == pair_key:
			return true
	return false


func _vein_find_entry(pair_key: String) -> Dictionary:
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("pair_key", "")) == pair_key:
			return f
	return {}


func _vein_report_pair(a: String, b: String, out: String) -> void:
	# §3.3.1: personal find рождается только для пары из серверной книги, тег
	# которой активен в текущем цикле; anti-farm — одна пара на цикл (R2: без
	# кэша цикла find не заводится).
	if out == "" or not g._online._is_server_pair(a, b):
		return
	var cyc := String(_cycle_cache.get("cycle_id", ""))
	var tag := String(g._online._server_tag.get(out, ""))
	if cyc == "" or tag == "":
		return
	if tag != String(_cycle_cache.get("tag1", "")) and tag != String(_cycle_cache.get("tag2", "")):
		return
	var pk := g._pair_key(a, b)
	if _vein_find_exists(cyc, pk):
		return
	_vein_finds.append({"id": "%s-%d-%s" % [cyc, int(Time.get_unix_time_from_system()), pk],
		"tag": tag, "points": 1, "found_at": int(Time.get_unix_time_from_system()),
		"pair_key": pk, "cycle_id": cyc, "status": "pending_server", "server_response": {}})
	g._saves._save_game()
	_vein_sync_pending()
	_refresh_week_page()


func _vein_add_from_discover(pair_key: String, out: String, vein: Dictionary) -> void:
	# world-first: сервер уже начислил очки в /discover — капля сразу registered
	if typeof(vein) != TYPE_DICTIONARY or vein.is_empty() or out == "":
		return
	var cyc := String(_cycle_cache.get("cycle_id", ""))
	var tag := String(vein.get("tag", ""))
	if tag == "":
		tag = String(g._online._server_tag.get(out, ""))
	if cyc == "" or tag == "" or _vein_find_exists(cyc, pair_key):
		return
	_vein_finds.append({"id": "wf-%d-%s" % [int(Time.get_unix_time_from_system()), pair_key],
		"tag": tag, "points": int(vein.get("points", Game.VEIN_POINTS_WORLD)),
		"found_at": int(Time.get_unix_time_from_system()), "pair_key": pair_key,
		"cycle_id": cyc, "status": "registered", "server_response": vein})
	g._saves._save_game()
	_refresh_week_page()


func _on_net_vein_find_result(pair_key: String, result: Dictionary) -> void:
	if result.get("offline", false) == true:
		return
	var f := _vein_find_entry(pair_key)
	if f.is_empty():
		return
	if result.get("ok", false) != true:
		var err := String(result.get("error", ""))
		if err == "cycle_mismatch":
			# R2: пересоздаём find в актуальном цикле сервера
			var new_cyc := String(result.get("cycle_id", ""))
			if new_cyc == "":
				new_cyc = String(_cycle_cache.get("cycle_id", ""))
			f["cycle_id"] = new_cyc
			f["id"] = "%s-%d-%s" % [new_cyc, int(Time.get_unix_time_from_system()), pair_key]
			f["status"] = "pending_server"
			f["points"] = 0
			_vein_sync_pending()
		else:
			_vein_finds.erase(f)  # unknown_pair / tag_mismatch — снимаем
		g._saves._save_game()
		_refresh_week_page()
		return
	f["status"] = "registered"
	f["server_response"] = result
	f["points"] = int(result.get("points", 1))
	Analytics.track("vein_personal_find", {"tag": String(f["tag"]),
		"points": int(result.get("points", 1)), "streak_roll": bool(result.get("streak_added", false)),
		"cycle_id": String(f["cycle_id"])})
	if bool(result.get("cap_reached", false)) and int(f.get("cap_paid", 0)) == 0:
		f["cap_paid"] = 1
		g._engine._grant_ether(Game.VEIN_STREAK_REWARD, "vein_streak_cap")
		Analytics.track("vein_streak_cap", {"cycle_id": String(f["cycle_id"]),
			"reward": Game.VEIN_STREAK_REWARD})
		g._engine.status_text = "Прожилка дошла до капа! +%d ⚡" % Game.VEIN_STREAK_REWARD
	g._saves._save_game()
	_refresh_week_page()


func _vein_tag_slug(tag: String) -> String:
	# тег → любое вещество с этим тегом (для цвета капли); "" если нет
	for slug in g._online._server_tag:
		if String(g._online._server_tag[slug]) == tag:
			return String(slug)
	return ""


func _vein_pour(find_id: String) -> void:
	if not Net.is_available() or g._online._device_id == "":
		g._engine.status_text = "Вливание ждёт связи с миром."
		Sfx.error()
		return
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("id", "")) == find_id:
			if String(f.get("status", "")) != "registered":
				return
			Net.vein_pour(g._online._device_id, find_id)
			return


func _on_net_vein_pour_result(find_id: String, result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("id", "")) == find_id:
			if String(f.get("status", "")) == "registered":
				f["status"] = "poured"
				Analytics.track("vein_pour", {"tag": String(f.get("tag", "")), "manual": true})
			break
	g._saves._save_game()
	_refresh_week_page()


func _week_fair() -> Dictionary:
	var f = _week_cache.get("fair", {})
	return f if typeof(f) == TYPE_DICTIONARY else {}


func _week_claimable() -> bool:
	var f := _week_fair()
	if f.is_empty():
		return false
	if bool(f.get("closed", false)) and int(f.get("my_contrib", 0)) >= 3 and not bool(f.get("claimed", false)):
		return true
	return typeof(f.get("prev", null)) == TYPE_DICTIONARY


func _fair_report_brew(a: String, b: String) -> void:
	if g._selftest or a == "" or b == "":
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		return
	Net.fair_brew(g._online._device_id, a, b)


func _on_net_fair_brew_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		return
	if bool(result.get("counted", false)):
		g._engine.status_text = "Вклад в котёл ярмарки засчитан! (твоих: %d)" % int(result.get("contrib", 0))
		var f := _week_fair()
		if not f.is_empty():
			f["progress"] = int(result.get("progress", f.get("progress", 0)))
			f["my_contrib"] = int(result.get("contrib", f.get("my_contrib", 0)))
			f["closed"] = bool(result.get("closed", f.get("closed", false)))
			_week_cache["fair"] = f
			g._saves._save_game()
		_refresh_week_page()
		g._engine._refresh()


func _fair_claim() -> void:
	if g._selftest:
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		g._engine.status_text = "Ярмарка ждёт связи с миром."
		Sfx.error()
		return
	Net.fair_claim(g._online._device_id)


func _fair_on_brew(output: String) -> void:
	# Локальный котёл (A3): считаем варки разных веществ, чтобы ярмарка жила и
	# без сети — вдвое дешевле на выходе. Чистый счётчик: без гейта selftest,
	# как _circle_on_discovery (suite_resonance_net: его мутации восстанавливаются).
	if output == "":
		return
	var w := Home._iso_week_id()
	if _fair_local_week != w:
		_fair_local_week = w
		_fair_local_brews.clear()
	if not _fair_local_brews.has(output):
		_fair_local_brews.append(output)
		if not g._selftest:
			g._saves._save_game()
			_refresh_week_page()


func _fair_offline_available() -> bool:
	return not g._online._net_enabled or not Net.is_available() or g._online._device_id == ""


func _fair_offline_claimable() -> bool:
	if _fair_off_claim_week == Home._iso_week_id():
		return false
	if _fair_local_week != Home._iso_week_id():
		return false
	return _fair_local_brews.size() >= Game.FAIR_OFFLINE_GOAL \
		and _fair_regen_total < Game.FAIR_REGEN_CAP


func _fair_offline_claim() -> void:
	if not _fair_offline_claimable():
		g._engine.status_text = "Локальный котёл: свари %d разных вещества за неделю (%d/%d)." % [
			Game.FAIR_OFFLINE_GOAL, _fair_local_brews.size(), Game.FAIR_OFFLINE_GOAL]
		Sfx.error()
		return
	_fair_off_claim_week = Home._iso_week_id()
	var before := _fair_regen_total
	_fair_regen_total = minf(Game.FAIR_REGEN_CAP, _fair_regen_total + Game.FAIR_REGEN_EACH * Game.FAIR_OFFLINE_FACTOR)
	g._hub._log_event("Ярмарка без мира: +%.2f регена навсегда (вполовину)" % (_fair_regen_total - before))
	g._engine.status_text = "Локальный котёл закрыт: +%.2f к регену навсегда. Без мира — вполовину." % (_fair_regen_total - before)
	g._spirit._companion_react("milestone", "ярмарка")
	Sfx.stage_up()
	g._saves._save_game()
	_refresh_week_page()
	g._engine._refresh()


func _on_net_fair_claim_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		g._engine.status_text = "Мир не ответил — награда котла подождёт."
		Sfx.error()
		return
	var grants_raw = result.get("grants")
	var grants: Array = grants_raw as Array if typeof(grants_raw) == TYPE_ARRAY else []
	if grants.is_empty():
		g._engine.status_text = "Забирать пока нечего: котёл варится или вклад уже забран."
		return
	for gr in grants:
		if typeof(gr) != TYPE_DICTIONARY:
			continue
		var gd := gr as Dictionary
		if String(gd.get("kind", "")) == "regen":
			var before := _fair_regen_total
			_fair_regen_total = minf(Game.FAIR_REGEN_CAP, _fair_regen_total + Game.FAIR_REGEN_EACH)
			g._hub._log_event("Ярмарка %s: +%.2f регена навсегда" % [String(gd.get("week", "?")), _fair_regen_total - before])
			g._engine.status_text = "Котёл ярмарки закрыт! +%.2f к регену навсегда." % (_fair_regen_total - before)
			g._spirit._companion_react("milestone", "ярмарка")
			Sfx.legendary()
		else:
			var amount := int(gd.get("amount", 0))
			g._engine._grant_ether(amount, "fair_compensation")
			g._engine.status_text = "Ярмарка %s: утешение +%d ⚡." % [String(gd.get("week", "?")), amount]
			Sfx.stage_up()
	g._saves._save_game()
	_fetch_week()
	_refresh_week_page()
	g._engine._refresh()


func _discover_vein_bonus(result: Dictionary) -> void:
	var v = result.get("vein", null)
	if typeof(v) != TYPE_DICTIONARY or (v as Dictionary).is_empty():
		return
	var vd := v as Dictionary
	if bool(vd.get("streak", false)):
		_vein_cap_total += 1
		g._engine.status_text = "Прожилка в жиле «%s»! +1 к капу навсегда." % g._clean_str(vd.get("tag", ""))
		g._spirit._companion_react("milestone", "жила")
		Sfx.legendary()
		g._saves._save_game()
		g._engine._refresh()
	else:
		g._engine.status_text = "Находка в жиле «%s»: +%d очк. дня!" % [g._clean_str(vd.get("tag", "")), int(vd.get("points", 0))]
		_fetch_week()


func _build_week_page(container: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	col.add_child(g._label("Недельный слой", 17))
	var desc := g._label("Жила недели награждает первооткрытия с её тегом; ярмарка варит общий котёл из ваших варок. Прогресс недели обнуляется в понедельник, бонусы — вечные.", 12)
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(desc)
	_week_head = g._label("", 13)
	col.add_child(_week_head)
	_week_list = VBoxContainer.new()
	_week_list.add_theme_constant_override("separation", 8)
	col.add_child(_week_list)
	_refresh_week_page()


func _refresh_week_page() -> void:
	if g._pages._mode_chips.has("week"):
		(g._pages._mode_chips["week"] as Button).text = "Неделя ●" if _week_claimable() else "Неделя"
	if _week_head == null or _week_list == null:
		return
	for child in _week_list.get_children():
		_week_list.remove_child(child)
		child.queue_free()
	if _week_cache.is_empty():
		var idle := g._label("Жду неделю от мира…", 13)
		if _week_offline:
			idle.text = "Мир недоступен — неделя появится, когда будет связь."
		idle.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		_week_list.add_child(idle)
		_week_head.text = ""
		return
	_week_head.text = "Неделя %s" % g._clean_str(_week_cache.get("week", "?"))
	var v := _week_vein()
	if not _cycle_cache.is_empty():
		v = {"tag1": _cycle_cache.get("tag1", ""), "tag2": _cycle_cache.get("tag2", ""),
			"spread": String(_cycle_cache.get("state", "")) == "spread",
			"my_hits": _cycle_cache.get("my_points", 0), "my_streaks": _cycle_cache.get("my_streak", 0),
			"streak_cap": Game.VEIN_STREAK_CAP}
	var vtitle := "Жила: «%s»" % g._clean_str(v.get("tag1", "?"))
	if bool(v.get("spread", false)):
		vtitle += " + «%s» (туман расползся)" % g._clean_str(v.get("tag2", "?"))
	var vt := g._label(vtitle + (" · ждёт связи с миром" if _fair_offline_available() else ""), 14)
	vt.add_theme_color_override("font_color", Color(0.55, 0.95, 0.9))
	_week_list.add_child(vt)
	if not _cycle_cache.is_empty():
		vt.text += " · туман: %s · миров находок %d/%d" % [String(_cycle_cache.get("state", "?")),
			int(_cycle_cache.get("world_finds", 0)), int(_cycle_cache.get("spread_threshold", 0))]
	_week_list.add_child(g._label("Твоих находок в жиле: %d · прожилки: %d/%d · +кап от жилы: %d" % [
		int(v.get("my_hits", 0)), int(v.get("my_streaks", 0)),
		int(v.get("streak_cap", 5)), _vein_cap_total], 13))
	# капли жилы (план 2): по одной на find текущего цикла (R1/R3)
	var cyc_now := String(_cycle_cache.get("cycle_id", ""))
	for f in _vein_finds:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if cyc_now != "" and String(f.get("cycle_id", "")) != cyc_now:
			continue
		var st := String(f.get("status", ""))
		var out_slug := _vein_tag_slug(String(f.get("tag", "")))
		var row := HBoxContainer.new()
		row.name = "VeinDropRow"
		row.add_theme_constant_override("separation", 8)
		var drop := VeinDrop.new()
		drop.setup(g._item_colors.get(out_slug, Color(0.6, 0.75, 0.9)), st)
		row.add_child(drop)
		var fl := g._label("", 13)
		var who := "мировая" if String(f.get("id", "")).begins_with("wf-") else "личная"
		match st:
			"pending_server":
				fl.text = "%s · «%s» · %d очк. — Ждёт связи" % [who, String(f.get("tag", "")), int(f.get("points", 1))]
			"registered":
				fl.text = "%s · «%s» · %d очк." % [who, String(f.get("tag", "")), int(f.get("points", 1))]
			_:
				fl.text = "%s · «%s» — влита ✓" % [who, String(f.get("tag", ""))]
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.autowrap_mode = TextServer.AUTOWRAP_OFF
		fl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(fl)
		if st == "registered":
			var pb := g._small_button("Влить", Vector2(96, 40), 2)
			pb.pressed.connect(_vein_pour.bind(String(f["id"])))
			row.add_child(pb)
		_week_list.add_child(row)
	var f := _week_fair()
	var ft := g._label("Ярмарка: котёл «%s»" % g._clean_str(f.get("tag", "?")), 14)
	ft.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	_week_list.add_child(ft)
	var goal := int(f.get("goal", 0))
	var prog := int(f.get("progress", 0)) + int(f.get("apprentice", 0))
	_week_list.add_child(g._label("Котёл: %d/%d (с подмастерьями)%s" % [
		mini(prog, goal) if goal > 0 else prog, goal, " — закрыт!" if bool(f.get("closed", false)) else ""], 13))
	_week_list.add_child(g._label("Твой вклад: %d (награда от 3)" % int(f.get("my_contrib", 0)), 13))
	var reward := g._label("Награда за закрытый котёл: +%.2f ⚡/с навсегда. Это недельный ритуал, а не разовая мелочь." % Game.FAIR_REGEN_EACH, 13)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	_week_list.add_child(reward)
	var cb := g._small_button("Забрать награду котла", Vector2(0, 46), 2)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.disabled = not _week_claimable()
	cb.pressed.connect(_fair_claim)
	_week_list.add_child(cb)
	if _fair_offline_available():
		_week_list.add_child(g._label("Без мира: локальный котёл — %d/%d разных вещества за неделю, награда вполовину." % [
			_fair_local_brews.size(), Game.FAIR_OFFLINE_GOAL], 13))
		var ob := g._small_button("Закрыть локальный котёл (−50 %)", Vector2(0, 46), 2)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.disabled = not _fair_offline_claimable()
		ob.pressed.connect(_fair_offline_claim)
		_week_list.add_child(ob)
	var pv = f.get("prev", null)
	if typeof(pv) == TYPE_DICTIONARY and not (pv as Dictionary).is_empty():
		var pd := pv as Dictionary
		var ptxt := "Прошлый котёл (%s): ждёт награда регена" % g._clean_str(pd.get("week", "?"))
		if String(pd.get("kind", "")) == "ether":
			ptxt = "Прошлый котёл (%s): ждёт утешение +%d ⚡" % [g._clean_str(pd.get("week", "?")), int(pd.get("amount", 0))]
		var pl := g._label(ptxt, 13)
		pl.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		_week_list.add_child(pl)


func _inject_week_demo() -> void:
	_week_cache = {"week": "2026-W37",
		"vein": {"tag1": "Свет", "tag2": "Тьма", "spread": true, "my_hits": 2, "my_streaks": 1, "streak_cap": 5},
		"fair": {"tag": "Трава", "goal": 22, "progress": 14, "apprentice": 4, "closed": false,
			"my_contrib": 3, "claimed": false,
			"prev": {"week": "2026-W36", "kind": "ether", "amount": 90}}}
	_vein_cap_total = 4
	_fair_regen_total = 0.05
	_week_offline = false
	_cycle_cache = {"cycle_id": "vc:demo", "tag1": "Свет", "state": "spread", "world_finds": 9,
		"my_points": 4, "my_streak": 2, "spread_threshold": 12, "started_at": "2026-09-20T00:00:00"}
	_vein_finds = [
		{"id": "wf-vc:demo", "tag": "Свет", "points": 2, "found_at": 0, "pair_key": "a|b",
			"cycle_id": "vc:demo", "status": "registered", "server_response": {}},
		{"id": "p-vc:demo", "tag": "Тьма", "points": 1, "found_at": 0, "pair_key": "c|d",
			"cycle_id": "vc:demo", "status": "pending_server", "server_response": {}},
		{"id": "wf-done", "tag": "Свет", "points": 2, "found_at": 0, "pair_key": "e|f",
			"cycle_id": "vc:demo", "status": "poured", "server_response": {}}]
