extends RefCounted
class_name Retention
# Дневной круг + недельный слой (R2): вехи/ранг ярмарки и очага. Доска v2
# (Task 4): состояние и логика дневной половины переехали в Contracts — здесь
# до Task 5 живут только страницы «Круг»/«Неделя» и делегаты к g._contracts.

var g: Game

# страница «Круг» до Task 5: только виджеты; всё состояние очага/вех/ранга
# переехало в Contracts (доска v2, Task 4). Поля делегировать нельзя, поэтому
# страница читает g._contracts.<поле> напрямую.
var _circle_head: Label = null
var _circle_list: VBoxContainer = null
# недельный слой (v30): состояние и логика переехали в Contracts (доска v2,
# Task 3) — здесь остались только виджеты страницы «Неделя» (она удаляется в
# Task 5) и делегаты к g._contracts. Поля делегировать нельзя, поэтому страница
# читает g._contracts.<поле> напрямую.
var _week_head: Label = null
var _week_list: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

# ---------- очаг: делегаты и страница «Круг» (v29 → доска v2 Task 4) ----------
# Три строки дня ушли на доску контрактов: визит-день = закрытый дневной
# контракт, очки вех = тир закрытого контракта, награда «за круг» удалена
# (спека §1/§3). Делегаты ниже нужны только странице до её удаления в Task 5.

func _circle_today() -> String:
	return Time.get_date_string_from_system()


func _circle_yesterday() -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_system() - 86400.0)


func _circle_orders_done() -> bool:
	g._guild._orders_refresh()
	return g._guild._order_targets_cache.size() > 0 and g._guild._order_done.size() >= g._guild._order_targets_cache.size()


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
	var desc := g._label("Доска v2: цель дня и заказы живут на доске контрактов. Закрывай дневные контракты — день засчитается очагу, а тир закрытого контракта принесёт вечные очки вех.", 12)
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(desc)
	_circle_head = g._label("", 13)
	col.add_child(_circle_head)
	_circle_list = VBoxContainer.new()
	_circle_list.add_theme_constant_override("separation", 8)
	col.add_child(_circle_list)
	_refresh_circle_page()


# Доска v2 Task 4: страница «Круг» доживает до Task 5 и читает состояние
# очага/вех/ранга напрямую из Contracts (поля делегировать нельзя). Строки
# «успешные синтезы дня» и «награда круга» удалены вместе с механикой.
func _refresh_circle_page() -> void:
	if g._pages._mode_chips.has("circle"):
		(g._pages._mode_chips["circle"] as Button).text = "Круг ●" if g._contracts.hearth_claimable() else "Круг"
	if _circle_head == null or _circle_list == null:
		return
	_circle_head.text = "Очаг %s · дней с закрытым контрактом: %d · серия: %d · вечных очков: %d" % [
		g._contracts.flame(), g._contracts._visit_days.size(), g._contracts._streak_run, g._contracts._pts_total]
	for child in _circle_list.get_children():
		_circle_list.remove_child(child)
		child.queue_free()
	# §2.2: символ-ранг + титул — первой строкой страницы
	var rank_row := HBoxContainer.new()
	rank_row.name = "CircleRankRow"
	rank_row.add_theme_constant_override("separation", 10)
	var sym := CircleRankSymbol.new()
	sym.setup(g._contracts.rank_level())
	rank_row.add_child(sym)
	var rtxt := g._label(g._contracts.rank_title(g._contracts.rank_level()), 14)
	rtxt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_row.add_child(rtxt)
	_circle_list.add_child(rank_row)
	# очаг: полешко раз в день
	var hearth := HBoxContainer.new()
	hearth.add_theme_constant_override("separation", 8)
	_circle_list.add_child(hearth)
	var hl := g._label("Полешко: +%d ⚡" % g._contracts.hearth_reward(), 14)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hearth.add_child(hl)
	var hb := g._small_button("Забрано ✓" if not g._contracts.hearth_claimable() else "Подбросить", Vector2(150, 40), 2)
	hb.disabled = not g._contracts.hearth_claimable()
	hb.pressed.connect(g._contracts.claim_hearth)
	hearth.add_child(hb)
	# цель дня: подсказка мира либо локальная цель (обе живут в Contracts)
	var ch_txt := ""
	if g._contracts._day_hint != "":
		ch_txt = "Цель дня: %s" % g._contracts._day_hint
	elif not g._contracts._local_goal().is_empty() and String(g._contracts._local_goal().get("out", "")) != "":
		var lg := g._contracts._local_goal()
		ch_txt = "Цель дня (без мира): свари «%s» из %s и %s" % [
			g._online._item_name(String(lg["out"])),
			g._online._item_name(String(lg["a"])),
			g._online._item_name(String(lg["b"]))]
	else:
		ch_txt = "Цель дня: нужна связь с миром"
	var goal_done := false
	for c in g._contracts.daily():
		if String((c as Dictionary)["type"]) == "goal_day":
			goal_done = g._contracts.is_done(String((c as Dictionary)["id"]))
	if goal_done:
		ch_txt += " ✓"
	var ch := g._label(ch_txt, 14)
	if goal_done:
		ch.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
	_circle_list.add_child(ch)
	g._guild._orders_refresh()
	var orow := g._label("Заказы гильдии: %d/3%s" % [g._guild._order_done.size(), " ✓" if _circle_orders_done() else ""], 14)
	if _circle_orders_done():
		orow.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
	_circle_list.add_child(orow)
	# вечные вехи
	var md := g._label("Вехи дней: %s" % g._contracts.mile_strip("дней", Game.CIRCLE_DAY_MILES, g._contracts._mdays), 13)
	md.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	_circle_list.add_child(md)
	var mp := g._label("Вехи очков: %s" % g._contracts.mile_strip("очков", Game.CIRCLE_PTS_MILES, g._contracts._mpts), 13)
	mp.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	_circle_list.add_child(mp)


func _inject_circle_demo() -> void:
	var today := _circle_today()
	g._contracts._visit_days = ["2026-09-10", "2026-09-11", today]
	g._contracts._streak_run = 3
	g._contracts._last_visit_day = today
	g._contracts._hearth_claim = ""
	g._contracts._pts_total = 61
	g._contracts._mdays = 0
	g._contracts._mpts = 1
	g._contracts._day_hint = "Свари что-нибудь из «Мха»"
	g._guild._orders_refresh()
	for t in g._guild._order_targets_cache:
		g._guild._order_done[String(t)] = true

# ---------- недельный слой: туманная жила + ярмарка гильдии (v30) ----------
# Доска v2 (Task 3): всё состояние и вся логика слоя переехали в Contracts
# (game/world/contracts.gd). Здесь остались только делегаты, на которые ещё
# смотрит страница «Неделя» (ниже): файл Retention удаляется в Task 5 вместе
# со страницей и этими обёртками.
# Жила: первооткрытие с тегом недели → +2 очк. дня и 10% прожилка (+1 кап,
# кап 5/нед. — на сервере). Ярмарка: варки пар с выходом-тегом недели идут
# в общий котёл (пара — раз в неделю); закрытый котёл + вклад ≥3 → +0.05/с
# регена навсегда (кап +0.5 суммарно), иначе — утешение эфиром. Теги веществ живут
# на сервере; клиент оперирует только строками недели.

func _fetch_week() -> void:
	g._contracts._fetch_week()


func _fetch_cycle() -> void:
	g._contracts._fetch_cycle()


func _cache_str(key: String) -> String:
	return g._contracts._cache_str(key)


func _week_vein() -> Dictionary:
	return g._contracts._week_vein()


func _week_fair() -> Dictionary:
	return g._contracts._week_fair()


func _week_claimable() -> bool:
	return g._contracts._week_claimable()


func _vein_tag_slug(tag: String) -> String:
	return g._contracts._vein_tag_slug(tag)


func _vein_pour(find_id: String) -> void:
	g._contracts._vein_pour(find_id)


func _fair_offline_available() -> bool:
	return g._contracts._fair_offline_available()


func _fair_offline_claimable() -> bool:
	return g._contracts._fair_offline_claimable()


func _fair_offline_claim() -> void:
	g._contracts._fair_offline_claim()


func _fair_claim() -> void:
	g._contracts._fair_claim()

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
	if g._contracts._week_cache.is_empty():
		var idle := g._label("Жду неделю от мира…", 13)
		if g._contracts._week_offline:
			idle.text = "Мир недоступен — неделя появится, когда будет связь."
		idle.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		_week_list.add_child(idle)
		_week_head.text = ""
		return
	_week_head.text = "Неделя %s" % g._clean_str(g._contracts._week_cache.get("week", "?"))
	var v := _week_vein()
	if not g._contracts._cycle_cache.is_empty():
		v = {"tag1": g._contracts._cycle_cache.get("tag1", ""), "tag2": g._contracts._cycle_cache.get("tag2", ""),
			"spread": String(g._contracts._cycle_cache.get("state", "")) == "spread",
			"my_hits": g._contracts._cycle_cache.get("my_points", 0), "my_streaks": g._contracts._cycle_cache.get("my_streak", 0),
			"streak_cap": Game.VEIN_STREAK_CAP}
	var vtitle := "Жила: «%s»" % g._clean_str(v.get("tag1", "?"))
	if bool(v.get("spread", false)):
		vtitle += " + «%s» (туман расползся)" % g._clean_str(v.get("tag2", "?"))
	var vt := g._label(vtitle + (" · ждёт связи с миром" if _fair_offline_available() else ""), 14)
	vt.add_theme_color_override("font_color", Color(0.55, 0.95, 0.9))
	_week_list.add_child(vt)
	if not g._contracts._cycle_cache.is_empty():
		vt.text += " · туман: %s · миров находок %d/%d" % [String(g._contracts._cycle_cache.get("state", "?")),
			int(g._contracts._cycle_cache.get("world_finds", 0)), int(g._contracts._cycle_cache.get("spread_threshold", 0))]
	_week_list.add_child(g._label("Твоих находок в жиле: %d · прожилки: %d/%d · +кап от жилы: %d" % [
		int(v.get("my_hits", 0)), int(v.get("my_streaks", 0)),
		int(v.get("streak_cap", 5)), g._contracts._vein_cap_total], 13))
	# капли жилы (план 2): по одной на find текущего цикла (R1/R3)
	var cyc_now := String(g._contracts._cycle_cache.get("cycle_id", ""))
	for f in g._contracts._vein_finds:
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
		var who := "Открытие мира" if String(f.get("id", "")).begins_with("wf-") else "Твоё открытие"
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
			g._contracts._fair_local_brews.size(), Game.FAIR_OFFLINE_GOAL], 13))
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
	g._contracts._week_cache = {"week": "2026-W37",
		"vein": {"tag1": "Свет", "tag2": "Тьма", "spread": true, "my_hits": 2, "my_streaks": 1, "streak_cap": 5},
		"fair": {"tag": "Трава", "goal": 22, "progress": 14, "apprentice": 4, "closed": false,
			"my_contrib": 3, "claimed": false,
			"prev": {"week": "2026-W36", "kind": "ether", "amount": 90}}}
	g._contracts._vein_cap_total = 4
	g._contracts._fair_regen_total = 0.05
	g._contracts._week_offline = false
	g._contracts._cycle_cache = {"cycle_id": "vc:demo", "tag1": "Свет", "state": "spread", "world_finds": 9,
		"my_points": 4, "my_streak": 2, "spread_threshold": 12, "started_at": "2026-09-20T00:00:00"}
	g._contracts._vein_finds = [
		{"id": "wf-vc:demo", "tag": "Свет", "points": 2, "found_at": 0, "pair_key": "a|b",
			"cycle_id": "vc:demo", "status": "registered", "server_response": {}},
		{"id": "p-vc:demo", "tag": "Тьма", "points": 1, "found_at": 0, "pair_key": "c|d",
			"cycle_id": "vc:demo", "status": "pending_server", "server_response": {}},
		{"id": "wf-done", "tag": "Свет", "points": 2, "found_at": 0, "pair_key": "e|f",
			"cycle_id": "vc:demo", "status": "poured", "server_response": {}}]
