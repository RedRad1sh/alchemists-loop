extends RefCounted
class_name Riddles
# Письма Светика + Атлас: ежедневные загадки-пары (оп B2). Своё состояние —
# поля ниже; общее состояние игры — через g (ноду Game). Имена методов — как
# были в main (с подчёркиванием): вызовы меняются только префиксом _riddles.

var g: Game

# письма Светика: сегодняшнее + бэклог (без слагов ответа — их знает только сервер)
var _letter_today: Dictionary = {}
var _letter_backlog: Array = []
var _letter_solved_total := 0
var _letter_milestones := 0
var _letter_pending: Array = []   # офлайн-попытки: ключи пар «a|b»
var _letter_inflight: Array = []  # отосланные solve без ответа (FIFO для корреляции)
var _letter_offline := false
var _letter_head: Label = null
var _letter_list: VBoxContainer = null
# атлас: сегодняшняя общемировая страница + альбом прошлого + мои счётчики
var _atlas_today: Dictionary = {}
var _atlas_history: Array = []
var _atlas_solved_total := 0
var _atlas_milestones := 0
var _atlas_pending: Array = []
var _atlas_inflight: Array = []
var _atlas_offline := false
var _atlas_head: Label = null
var _atlas_list: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

# ---------- письма Светика: ежедневная загадка-пары ----------
# Клиент получает только намёк + длины слов (+известные буквы из старых писем).
# Сами слаги ответа знает только сервер: каждая сваренная пара уходит на
# POST /letter/solve, сервер сверяет с неразгаданными письмами (сегодня+бэклог).
# Офлайн-попытки копятся в _letter_pending и досылаются при первой связи.

func _letter_cap_bonus() -> int:
	return Game.LETTER_CAP_EACH * _letter_milestones

func _letter_milestones_for(total: int) -> int:
	return maxi(0, total) / Game.LETTER_MILE_EVERY

func _letter_has_unsolved() -> bool:
	return _letter_unsolved_count() > 0

func _letter_unsolved_count() -> int:
	var n := 0
	if not _letter_today.is_empty() and not bool(_letter_today.get("solved", false)):
		n += 1
	for e in _letter_backlog:
		if not bool((e as Dictionary).get("solved", false)):
			n += 1
	return n

func _fetch_letters() -> void:
	if not g._online._net_enabled or g._online._device_id == "":
		return
	if not Net.is_available():
		_letter_offline = true
		_refresh_letters_page()
		return
	Net.letter_today(g._online._device_id)

func _on_net_letter_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		_letter_offline = true
		_refresh_letters_page()
		if g._saves._return_open:
			g._saves._refresh_return_popup()
		return
	_letter_offline = false
	var letter_today_raw = result.get("today")
	_letter_today = letter_today_raw as Dictionary if typeof(letter_today_raw) == TYPE_DICTIONARY else {}
	var letter_backlog_raw = result.get("backlog")
	_letter_backlog = letter_backlog_raw as Array if typeof(letter_backlog_raw) == TYPE_ARRAY else []
	_letter_solved_total = maxi(0, int(result.get("solved_total", 0)))
	_letter_milestones = _letter_milestones_for(_letter_solved_total)
	_flush_letter_pending()
	_flush_atlas_pending()  # связь есть — досылаем и атлас
	g._saves._save_game()
	_refresh_letters_page()
	g._engine._refresh()
	if g._saves._return_open:
		g._saves._refresh_return_popup()

func _letter_queue_pending(a: String, b: String) -> void:
	var key := g._pair_key(a, b)
	if _letter_pending.has(key):
		return
	_letter_pending.append(key)
	while _letter_pending.size() > Game.LETTER_PENDING_MAX:
		_letter_pending.pop_front()
	g._saves._save_game()

func _flush_letter_pending() -> void:
	if _letter_pending.is_empty():
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		return
	for key in _letter_pending:
		var parts := String(key).split("|")
		if parts.size() == 2:
			_letter_inflight.append(String(key))
			Net.letter_solve(g._online._device_id, parts[0], parts[1])
	_letter_pending.clear()
	g._saves._save_game()

func _letter_attempt(a: String, b: String) -> void:
	if not _letter_has_unsolved():
		return
	if g._selftest:
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		_letter_queue_pending(a, b)
		return
	_letter_inflight.append(g._pair_key(a, b))
	Net.letter_solve(g._online._device_id, a, b)

func _on_net_letter_solve_result(result: Dictionary) -> void:
	var key := ""
	if not _letter_inflight.is_empty():
		key = String(_letter_inflight.pop_front())
	if result.get("offline", false) == true or result.get("ok", false) != true:
		if key != "" and not _letter_pending.has(key):
			_letter_pending.append(key)
			g._saves._save_game()
		return
	_letter_offline = false
	if bool(result.get("matched", false)):
		var day := String(result.get("day", ""))
		_letter_mark_solved(day)
		_letter_solved_total = maxi(0, int(result.get("solved_total", _letter_solved_total)))
		var miles := _letter_milestones_for(_letter_solved_total)
		if miles > _letter_milestones:
			_letter_milestones = miles
			_letter_celebrate_milestone()
		else:
			_letter_celebrate_solve(day)
		g._saves._save_game()
		_refresh_letters_page()
		g._engine._refresh()
	_flush_letter_pending()

func _letter_mark_solved(day: String) -> void:
	if day == "":
		return
	if String(_letter_today.get("day", "")) == day:
		_letter_today["solved"] = true
	for e in _letter_backlog:
		if String((e as Dictionary).get("day", "")) == day:
			(e as Dictionary)["solved"] = true

func _letter_celebrate_solve(day: String) -> void:
	if g._selftest:
		return
	g._online._set_status("✦ Письмо Светика (%s) разгадано! Веха — каждые %d." % [_letter_day_title(day), Game.LETTER_MILE_EVERY])
	Sfx.discovery()
	g._spirit._companion_react("happy", "")

func _letter_celebrate_milestone() -> void:
	if g._selftest:
		return
	g._online._set_status("✦ Веха писем! +%d к капу эфира навсегда (всего +%d)." % [Game.LETTER_CAP_EACH, _letter_cap_bonus()])
	Sfx.stage_up()
	g._spirit._companion_react("happy", "")
	g._spirit._companion_open_dialog("Ты разгадал ещё пять моих писем! Котёл стал вместительнее — держи.", false)

func _letter_day_title(day: String) -> String:
	if day == Time.get_date_string_from_system():
		return "сегодня"
	var yest := Time.get_date_string_from_unix_time(Time.get_unix_time_from_system() - 86400.0)
	if day == yest:
		return "вчера"
	return day

func _letter_word_shape(entry: Dictionary, tag: String) -> String:
	var n := maxi(1, int(entry.get("len_" + tag, 1)))
	var chars: PackedStringArray = []
	for i in n:
		chars.append("·")
	var known: Array = entry.get("known_" + tag, [])
	for raw in known:
		if typeof(raw) != TYPE_ARRAY:
			continue
		var pair: Array = raw
		if pair.size() >= 2:
			var idx := int(pair[0])
			if idx >= 0 and idx < n:
				chars[idx] = String(pair[1])
	return "".join(chars)

func _letter_pattern(entry: Dictionary) -> String:
	return "%s  +  %s" % [_letter_side(entry, "a"), _letter_side(entry, "b")]

func _letter_side(entry: Dictionary, tag: String) -> String:
	# сервер приоткрывает имена дозированно: известное — кавычками, нет — силуэтом
	var nm := g._clean_str(entry.get(tag + "_name", ""))
	if nm != "":
		return "«%s»" % nm
	return _letter_word_shape(entry, tag)

func _build_letters_page(container: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	col.add_child(g._label("Письма Светика", 17))
	var desc := g._label("Каждый день Светик прячет пару веществ в намёк. Свари эту пару — письмо разгадано. Ответ знает только мир, подсмотреть нельзя.", 12)
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	_letter_head = g._label("", 13)
	col.add_child(_letter_head)
	_letter_list = VBoxContainer.new()
	_letter_list.add_theme_constant_override("separation", 10)
	col.add_child(_letter_list)
	_refresh_letters_page()

func _refresh_letters_page() -> void:
	if g._pages._mode_chips.has("letters"):
		(g._pages._mode_chips["letters"] as Button).text = "Письма ●" if _letter_has_unsolved() else "Письма"
	if _letter_head == null or _letter_list == null:
		return
	_letter_head.text = "Разгадано: %d · вехи: %d (+%d к капу навсегда)" % [_letter_solved_total, _letter_milestones, _letter_cap_bonus()]
	for child in _letter_list.get_children():
		_letter_list.remove_child(child)
		child.queue_free()
	if _letter_today.is_empty() and _letter_backlog.is_empty():
		var idle := g._label("Жду письма от Светика…", 13)
		if _letter_offline:
			idle.text = "Мир недоступен — письма появятся, когда будет связь."
		idle.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		_letter_list.add_child(idle)
		return
	var entries: Array = []
	if not _letter_today.is_empty():
		entries.append(_letter_today)
	for e in _letter_backlog:
		entries.append(e)
	for raw in entries:
		_letter_list.add_child(_letter_card(raw))


func _letter_card_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.12, 0.095, 0.97)
	sb.set_corner_radius_all(12)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _letter_card(entry: Dictionary) -> PanelContainer:
	# п.12: письмо — пергаментная карточка: конверт + день + статус, строка-намёк, силуэт пары
	var solved := bool(entry.get("solved", false))
	var is_today := String(entry.get("day", "")) == Time.get_date_string_from_system()
	var accent := Color(0.45, 0.75, 0.5) if solved else (Color(1.0, 0.78, 0.35) if is_today else Color(0.45, 0.5, 0.55))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _letter_card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var env := g._label("✉", 20)
	env.size_flags_horizontal = 0
	head.add_child(env)
	var title := g._label("Письмо · %s" % _letter_day_title(String(entry.get("day", "?"))), 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var badge := g._label("✓ разгадано" if solved else ("ждёт сегодня" if is_today else "прошлое"), 12)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", accent)
	head.add_child(badge)
	col.add_child(HSeparator.new())
	var hint := g._label("«%s»" % String(entry.get("hint", "")), 13)
	hint.add_theme_color_override("font_color", Color(0.85, 0.78, 0.66))
	col.add_child(hint)
	var pat := g._label(_letter_pattern(entry), 16)
	pat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pat.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6) if solved else Color(1.0, 0.85, 0.42))
	col.add_child(pat)
	return card

func _inject_letter_demo() -> void:
	var today := Time.get_date_string_from_system()
	var yest := Time.get_date_string_from_unix_time(Time.get_unix_time_from_system() - 86400.0)
	_letter_today = {"day": today, "hint": "Шёпот: жаркое обнимает текучее — и над котлом встаёт туман.",
		"len_a": 5, "len_b": 4, "known_a": [], "known_b": [], "revealed": false, "solved": false}
	_letter_backlog = [
		{"day": yest, "hint": "Вчерашний шёпот: твёрдое встретило живое.",
			"len_a": 5, "len_b": 7, "known_a": [[0, "з"]], "known_b": [], "revealed": false, "solved": false},
		{"day": "2026-08-01", "hint": "Давний шёпот.", "len_a": 4, "len_b": 4,
			"known_a": [], "known_b": [], "revealed": true, "a_name": "Огонь", "b_name": "Вода", "solved": true},
	]
	_letter_solved_total = 6
	_letter_milestones = 1
	_letter_offline = false

# ---------- страница Атласа: общемировая загадка дня ----------
# Та же схема, что письма (матчинг на сервере, слаги не утекают), но страница
# одна на всех и разгадывается только сегодня; прошлое — альбом с ответами.
# Силуэты слов и заголовки дней переиспользуют _letter_word_shape/_letter_pattern.

func _atlas_cap_bonus() -> int:
	return Game.ATLAS_CAP_EACH * _atlas_milestones

func _atlas_milestones_for(total: int) -> int:
	return maxi(0, total) / Game.ATLAS_MILE_EVERY

func _atlas_has_unsolved() -> bool:
	return not _atlas_today.is_empty() and not bool(_atlas_today.get("solved_by_me", false))

func _fetch_atlas() -> void:
	if not g._online._net_enabled or g._online._device_id == "":
		return
	if not Net.is_available():
		_atlas_offline = true
		_refresh_atlas_page()
		return
	Net.atlas_today(g._online._device_id)

func _on_net_atlas_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		_atlas_offline = true
		_refresh_atlas_page()
		if g._saves._return_open:
			g._saves._refresh_return_popup()
		return
	_atlas_offline = false
	var atlas_today_raw = result.get("today")
	_atlas_today = atlas_today_raw as Dictionary if typeof(atlas_today_raw) == TYPE_DICTIONARY else {}
	var atlas_history_raw = result.get("history")
	_atlas_history = atlas_history_raw as Array if typeof(atlas_history_raw) == TYPE_ARRAY else []
	_atlas_solved_total = maxi(0, int(result.get("solved_total", 0)))
	_atlas_milestones = _atlas_milestones_for(_atlas_solved_total)
	_flush_atlas_pending()
	_flush_letter_pending()  # связь есть — досылаем и письма
	g._saves._save_game()
	_refresh_atlas_page()
	g._engine._refresh()
	if g._saves._return_open:
		g._saves._refresh_return_popup()

func _atlas_queue_pending(a: String, b: String) -> void:
	var key := g._pair_key(a, b)
	if _atlas_pending.has(key):
		return
	_atlas_pending.append(key)
	while _atlas_pending.size() > Game.ATLAS_PENDING_MAX:
		_atlas_pending.pop_front()
	g._saves._save_game()

func _flush_atlas_pending() -> void:
	if _atlas_pending.is_empty():
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		return
	for key in _atlas_pending:
		var parts := String(key).split("|")
		if parts.size() == 2:
			_atlas_inflight.append(String(key))
			Net.atlas_solve(g._online._device_id, parts[0], parts[1])
	_atlas_pending.clear()
	g._saves._save_game()

func _atlas_attempt(a: String, b: String) -> void:
	if not _atlas_has_unsolved():
		return
	if g._selftest:
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		_atlas_queue_pending(a, b)
		return
	_atlas_inflight.append(g._pair_key(a, b))
	Net.atlas_solve(g._online._device_id, a, b)

func _on_net_atlas_solve_result(result: Dictionary) -> void:
	var key := ""
	if not _atlas_inflight.is_empty():
		key = String(_atlas_inflight.pop_front())
	if result.get("offline", false) == true or result.get("ok", false) != true:
		if key != "" and not _atlas_pending.has(key):
			_atlas_pending.append(key)
			g._saves._save_game()
		return
	_atlas_offline = false
	if bool(result.get("matched", false)):
		_atlas_today["solved_by_me"] = true
		_atlas_today["solvers"] = int(_atlas_today.get("solvers", 0)) + 1
		_atlas_solved_total = maxi(0, int(result.get("solved_total", _atlas_solved_total)))
		var miles := _atlas_milestones_for(_atlas_solved_total)
		if miles > _atlas_milestones:
			_atlas_milestones = miles
			_atlas_celebrate_milestone()
		else:
			_atlas_celebrate_solve()
		g._saves._save_game()
		_refresh_atlas_page()
		g._engine._refresh()
	_flush_atlas_pending()

func _atlas_celebrate_solve() -> void:
	if g._selftest:
		return
	g._online._set_status("Страница Атласа разгадана! Твоих страниц: %d (веха — каждые %d)." % [_atlas_solved_total, Game.ATLAS_MILE_EVERY])
	Sfx.discovery()
	g._spirit._companion_react("happy", "")

func _atlas_celebrate_milestone() -> void:
	if g._selftest:
		return
	g._online._set_status("Веха Атласа! +%d к капу эфира навсегда (всего +%d)." % [Game.ATLAS_CAP_EACH, _atlas_cap_bonus()])
	Sfx.stage_up()
	g._spirit._companion_react("happy", "")
	g._spirit._companion_open_dialog("Десять страниц Атласа! Мир записывает твоё имя — а котёл становится вместительнее.", false)

func _build_atlas_page(container: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	col.add_child(g._label("Страница Атласа", 17))
	var desc := g._label("Одна загадка на весь мир. Свари пару сегодня — завтра страница уйдёт в альбом с ответом.", 12)
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	_atlas_head = g._label("", 13)
	col.add_child(_atlas_head)
	_atlas_list = VBoxContainer.new()
	_atlas_list.add_theme_constant_override("separation", 10)
	col.add_child(_atlas_list)
	_refresh_atlas_page()

func _atlas_days_strip() -> String:
	# п.11: компактные бейджи по дням (старые → новые): ✓ разгадан, · пропущен, ○ сегодня ждёт
	var marks: Array = []
	for raw in _atlas_history:
		marks.push_front("✓" if bool((raw as Dictionary).get("solved_by_me", false)) else "·")
	if not _atlas_today.is_empty():
		marks.append("✓" if bool(_atlas_today.get("solved_by_me", false)) else "○")
	return " ".join(marks)


func _refresh_atlas_page() -> void:
	if g._pages._mode_chips.has("atlas"):
		(g._pages._mode_chips["atlas"] as Button).text = "Атлас ●" if _atlas_has_unsolved() else "Атлас"
	if _atlas_head == null or _atlas_list == null:
		return
	_atlas_head.text = "Моих страниц: %d · вехи: %d (+%d к капу навсегда)" % [_atlas_solved_total, _atlas_milestones, _atlas_cap_bonus()]
	for child in _atlas_list.get_children():
		_atlas_list.remove_child(child)
		child.queue_free()
	if _atlas_today.is_empty() and _atlas_history.is_empty():
		var idle := g._label("Жду страницу от мира…", 13)
		if _atlas_offline:
			idle.text = "Мир недоступен — страница появится, когда будет связь."
		idle.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		_atlas_list.add_child(idle)
		return
	if not _atlas_today.is_empty():
		var mine := bool(_atlas_today.get("solved_by_me", false))
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		_atlas_list.add_child(card)
		var title := g._label("Сегодня%s · разгадали: %d" % [" ✓" if mine else "", int(_atlas_today.get("solvers", 0))], 14)
		if mine:
			title.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
		card.add_child(title)
		var riddle := g._label(String(_atlas_today.get("riddle", "")), 13)
		riddle.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		riddle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(riddle)
		var pat := g._label(_letter_pattern(_atlas_today), 15)
		if not mine:
			pat.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
		card.add_child(pat)
	if not _atlas_history.is_empty() or not _atlas_today.is_empty():
		_atlas_list.add_child(g._label("Дни: %s" % _atlas_days_strip(), 13))
	for raw in _atlas_history:
		var entry: Dictionary = raw
		var hsolved := bool(entry.get("solved_by_me", false))
		var hcard := VBoxContainer.new()
		hcard.add_theme_constant_override("separation", 2)
		_atlas_list.add_child(hcard)
		var htitle := g._label("Альбом (%s)%s" % [_letter_day_title(String(entry.get("day", "?"))), " ✓" if hsolved else ""], 13)
		htitle.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6) if hsolved else Color(0.55, 0.66, 0.72))
		hcard.add_child(htitle)
		var hpat := g._label(_letter_pattern(entry), 14)
		hpat.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		hcard.add_child(hpat)

func _inject_atlas_demo() -> void:
	_atlas_today = {"day": Time.get_date_string_from_system(),
		"riddle": "Загадка мира: звонкое встретило тягучее — и потекла песня.",
		"len_a": 6, "len_b": 5, "known_a": [], "known_b": [],
		"solvers": 3, "solved_by_me": false}
	_atlas_history = [
		{"day": "2026-09-10", "riddle": "Прошлая загадка.",
			"a_name": "Кристалл", "b_name": "Мох", "len_a": 8, "len_b": 3,
			"known_a": [], "known_b": []},
	]
	_atlas_solved_total = 12
	_atlas_milestones = 1
	_atlas_offline = false
