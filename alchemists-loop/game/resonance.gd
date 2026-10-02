extends RefCounted
class_name Resonance
# Резонанс 2.0 (R5): отголоски чужих повторов, родословная, вехи резонанса.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _res_balance := 0
var _res_total := 0
var _res_echo_ether := 5
var _res_cap := 20
var _res_desc: Array = []
var _res_desc_total := 0
var _res_top: Array = []
var _res_apprentice: Dictionary = {}
var _res_done: Dictionary = {}
# msec отправки «Забрать» в полёте; 0 — окно свободно (_claim_gate)
var _res_claim_at := 0
var _res_info: Label = null
var _res_claim_btn: Button = null
var _res_miles: Label = null
var _res_lines: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

# ---------- резонанс 2.0: отголоски чужих повторов + родословная ----------

func _build_resonance_page(container: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	col.add_child(g._label("Отголоски мира", 17))
	var desc := g._label("Когда другие игроки повторяют твои вещества, здесь копится эхо. Забирай его эфиром — эхо не сгорает.", 12)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(desc)
	_res_info = g._label("", 13)
	_res_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_res_info)
	_res_claim_btn = g._small_button("Забрать", Vector2(0, 44))
	_res_claim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_claim_btn.pressed.connect(_claim_echoes)
	col.add_child(_res_claim_btn)
	_res_miles = g._label("", 12)
	_res_miles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_res_miles.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
	col.add_child(_res_miles)
	col.add_child(g._label("Родословная", 14))
	_res_lines = VBoxContainer.new()
	_res_lines.add_theme_constant_override("separation", 4)
	col.add_child(_res_lines)
	var hint := g._label("Вехи вечные: 10 повторов → +0.03/с, 50 → +5 к капу, 100 → золотая рамка твоих веществ в сетке мира.", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.55, 0.66, 0.72))
	col.add_child(hint)
	_refresh_resonance_page()

func _refresh_resonance_page() -> void:
	if _res_info == null or _res_claim_btn == null or _res_miles == null or _res_lines == null:
		return
	var info := PackedStringArray()
	info.append("Эхо к получению: %d (кап %d) · всего повторов: %d" % [_res_balance, _res_cap, _res_total])
	if not _res_top.is_empty() and typeof(_res_top[0]) == TYPE_DICTIONARY:
		var t := _res_top[0] as Dictionary
		info.append("Самое звонкое: «%s» — %d" % [g._clean_str(t.get("name", "?")), int(t.get("count", 0))])
	if not _res_apprentice.is_empty():
		info.append("Подмастерья сегодня варили «%s»" % g._clean_str(_res_apprentice.get("name", "?")))
	_res_info.text = "\n".join(info)
	_res_claim_btn.text = "Забрать: +%d ⚡" % _res_claim_ether()
	_res_claim_btn.disabled = _res_balance <= 0 or not g._online._net_enabled or not Net.is_available()
	var parts := PackedStringArray()
	for m in Game.RES_MILES:
		var mi := int(m)
		if _res_done.has(mi):
			parts.append("✓ %d" % mi)
		else:
			parts.append("%d/%d" % [mini(_res_total, mi), mi])
	_res_miles.text = "Вехи: %s" % " · ".join(parts)
	for child in _res_lines.get_children():
		_res_lines.remove_child(child)
		child.queue_free()
	var dtxt := PackedStringArray()
	if _res_desc.is_empty():
		dtxt.append("Пока тихо. Открой вещество первым — и мир начнёт его повторять.")
	else:
		dtxt.append("Из твоих открытий родилось: %d" % _res_desc_total)
		var shown := 0
		for d in _res_desc:
			if shown >= 8:
				break
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var dd := d as Dictionary
			dtxt.append("· «%s» — %s" % [g._clean_str(dd.get("name", "?")), g._clean_str(dd.get("by", "кто-то"))])
			shown += 1
		if _res_desc_total > shown:
			dtxt.append("…и ещё %d" % (_res_desc_total - shown))
	var dlbl := g._label("\n".join(dtxt), 12)
	dlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlbl.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	_res_lines.add_child(dlbl)

func _res_claim_ether() -> int:
	return maxi(0, _res_balance) * maxi(0, _res_echo_ether)

func _res_cap_bonus() -> int:
	return Game.RES_CAP50 if _res_done.has(50) else 0

func _res_regen_bonus() -> float:
	return Game.RES_REGEN10 if _res_done.has(10) else 0.0

func _res_gilded() -> bool:
	return _res_done.has(100)

func _res_mile_reward_text(mi: int) -> String:
	match mi:
		10:
			return "+0.03/с к регену"
		50:
			return "+5 к капу эфира"
		100:
			return "золотая рамка твоих веществ"
	return ""

func _res_check_milestones() -> Array:
	# вехи по вечному счётчику; в selftest только флаги, без сайд-эффектов
	var newly: Array = []
	for m in Game.RES_MILES:
		var mi := int(m)
		if _res_total >= mi and not _res_done.has(mi):
			_res_done[mi] = true
			newly.append(mi)
	if newly.is_empty() or g._selftest:
		return newly
	for mi in newly:
		g._hub._log_event("Веха отголосков: %d повторов (%s)" % [int(mi), _res_mile_reward_text(int(mi))])
	g._online._set_status("ВЕХА ОТГОЛОСКОВ: %d повторов — %s навсегда!" % [int(newly.back()), _res_mile_reward_text(int(newly.back()))])
	g._spirit._companion_react("achievement", "Отголоски")
	Sfx.divide()
	Input.vibrate_handheld(20)
	if _res_done.has(100):
		g._online._rebuild_world_grid()
	g._saves._save_game()
	return newly

func _fetch_echoes() -> void:
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		return
	Net.echoes(g._online._device_id)

func _claim_gate(now_ms: int) -> bool:
	# True — запрос разрешён и окно занято до ответа мира; False — прошлый claim ещё в пути.
	# now_ms параметром, чтобы это было чисто тестируемо.
	if _res_claim_at != 0 and now_ms - _res_claim_at < Game.RESONANCE_CLAIM_GATE_MSEC:
		return false
	_res_claim_at = now_ms
	return true

func _claim_echoes() -> void:
	if _res_balance <= 0:
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		g._online._set_status("Мир недоступен — эхо подождёт.")
		Sfx.error()
		return
	# окно взводится только когда запрос реально уходит: офлайн-тап не съедает 15 с
	if not _claim_gate(Time.get_ticks_msec()):
		return
	Net.echoes_claim(g._online._device_id)

func _on_net_echoes_result(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	_res_balance = maxi(0, int(result.get("balance", 0)))
	_res_total = maxi(0, int(result.get("total", 0)))
	_res_echo_ether = maxi(1, int(result.get("echo_ether", 5)))
	_res_cap = maxi(1, int(result.get("cap", 20)))
	var resonance_top_raw = result.get("top")
	_res_top = resonance_top_raw as Array if typeof(resonance_top_raw) == TYPE_ARRAY else []
	var resonance_desc_raw = result.get("descendants")
	_res_desc = resonance_desc_raw as Array if typeof(resonance_desc_raw) == TYPE_ARRAY else []
	_res_desc_total = maxi(0, int(result.get("descendants_total", 0)))
	var ap = result.get("apprentice")
	_res_apprentice = ap if typeof(ap) == TYPE_DICTIONARY else {}
	if not _res_apprentice.is_empty():
		g._online._set_status("Подмастерья гильдии сегодня варили «%s»: +1 отголосок." % g._clean_str(_res_apprentice.get("name", "?")))
		g._hub._log_event("Подмастерья: +1 отголосок за «%s»" % g._clean_str(_res_apprentice.get("name", "?")))
	_res_check_milestones()
	_refresh_resonance_page()
	g._progress_ui._refresh_achievement_map()
	if g._saves._return_open:
		g._saves._refresh_return_popup()
	g._engine._refresh()
	g._saves._save_game()

func _on_net_echoes_claim_result(result: Dictionary) -> void:
	# ответ (любой) снимает окно: залипший флаг блокировал бы claim на всё оставшееся время
	_res_claim_at = 0
	if result.get("ok", false) != true:
		g._online._set_status("Мир не отдал эхо — попробуй позже.")
		return
	var claimed := maxi(0, int(result.get("claimed", 0)))
	var gain := maxi(0, int(result.get("ether", 0)))
	_res_balance = maxi(0, _res_balance - claimed)
	_res_total = maxi(_res_total, int(result.get("total", _res_total)))
	if gain > 0:
		g._engine._grant_ether(gain, "resonance_echo")
		g._online._set_status("Забрано отголосков: %d (+%d ⚡)." % [claimed, gain])
		Sfx.bubble()
		Input.vibrate_handheld(12)
	else:
		g._online._set_status("Эхо пусто — загляни позже.")
	_refresh_resonance_page()
	g._progress_ui._refresh_achievement_map()
	g._engine._refresh_header()
	g._saves._save_game()
