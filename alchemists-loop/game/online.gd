extends RefCounted
class_name Online
# Онлайн (R8): рейтинг, сервер первооткрытий, мир (зал славы, цепочки, события).
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _hall_list: VBoxContainer
var _chains_list: VBoxContainer
# Глобальный QTE события: он не принадлежит вкладке «Мир» и может появиться
# поверх любой текущей страницы в безопасной случайной точке экрана.
var _event_qte: Control = null
var _event_card: PanelContainer = null
var _event_btn: Button = null
var _event_label: Label = null
var _event_progress: ProgressBar = null
var _event_active := false
var _event_type := ""
var _event_left := 0.0
var _event_clock := 0.0
var _event_t := 0.0
var _world_total := 0
var _world_total_seen := 0
var _netbrew_pair := ""
# Headless E2E hook: starts the same Experiment path as the UI after ping.
var _netexperiment_pair := ""
var _netexperiment_started := false
var _net_enabled := false
var _device_id := ""
var _net_nick := Game.NET_NICK
var _challenge_avatar: Avatar = null
var _server_layers: Dictionary = {}
var _server_elements: Dictionary = {}
var _server_recipes: Array = []
var _server_tag: Dictionary = {}   # slug → тег природы (для /api/vein/find)
var _rating_list: VBoxContainer = null
var _rating_status: Label = null
var _rating_me: Label = null
var _pending_requests: Dictionary = {}
# U11 (T14): корреляция запрос↔ответ. Pending хранится словарём
# pair_key → {"a": String, "b": String, "experiment": bool, "at": int}
# («at» — Time.get_ticks_msec на момент вставки). Инварианты:
# * слот занимает ровно одна пара: пока словарь непуст, новая регистрация
#   запрещена (_register_pending_pair → false — запрос НЕ отправляется),
#   поэтому «enqueue-перехват» (ответ X применяется к pending Y) невозможен;
# * обработчики Net извлекают запись по pair_key из сигнала и молча дропают
#   ответы без записи (дубликаты, запоздалые, ответы после сброса мира);
# * записи не живут вечно: PENDING_TTL_MSEC по времени вставки — тот же
#   минимальный подход к устареванию, что CANDIDATE_COOLDOWN и 8-секундный
#   дедлайн resume в этом файле (Net-таймаута здесь нет: сериализованная
#   очередь даёт ровно один ответ на запрос; ответ может застрять только
#   за поллингом событий/house-upload — TTL покрывает и это). Плюс полный
#   clear при сбросах мира (main.gd `_init_new_game`, hub.gd `_do_prestige`,
#   saves.gd `_load_game`).
# * prune — не только удаление: просроченная запись ЭКСПЕРИМЕНТА при прунинге
#   возвращает реагенты и эфир (_prune_pending_requests), иначе осиротевший
#   _experiment_pending_pair намертво блокировал бы варку/престиж/новую игру.
const PENDING_TTL_MSEC := 120000
var _resume_experiment_wait := false
var _resume_experiment_deadline := 0.0
var _server_authors: Dictionary = {}
var _world_last_fetch_ms := 0
var _world_loaded := false
var _world_poll := 0.0
var _rating_poll := 0.0
var _challenge_label: Label = null
var _world_grid: GridContainer = null
var _world_status: Label = null
var _world_search: LineEdit = null
var _world_page := 0
var _world_page_label: Label = null
var _world_prev: Button = null
var _world_next: Button = null

func _init(game: Game) -> void:
	g = game

# ---------- рейтинг ----------

func _build_rating_page(page: VBoxContainer) -> void:
	var t := g._label("РЕЙТИНГ ИГРОКОВ", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	page.add_child(t)
	var sub := g._label("Кто сколько открыл — и чей домик можно посмотреть.", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	page.add_child(sub)
	_rating_me = g._label("", 12)
	_rating_me.add_theme_color_override("font_color", Color(0.66, 0.91, 0.80))
	# Блок 5: своя строка — закреплённой чип-карточкой с бирюзовой обводкой.
	var me_sb := StyleBoxFlat.new()
	me_sb.bg_color = Color(0.09, 0.13, 0.12, 0.9)
	me_sb.set_corner_radius_all(12)
	me_sb.border_color = Color(0.35, 0.88, 0.84, 0.8)
	me_sb.set_border_width_all(1)
	me_sb.content_margin_left = 12
	me_sb.content_margin_right = 12
	me_sb.content_margin_top = 8
	me_sb.content_margin_bottom = 8
	_rating_me.add_theme_stylebox_override("normal", me_sb)
	page.add_child(_rating_me)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	page.add_child(status_row)
	_rating_status = g._label("Связываемся с миром…", 13)
	_rating_status.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	_rating_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_rating_status)
	# «Обновить» — иконкой 44×40 вместо кнопки во всю ширину.
	var refresh := g._small_button("", Vector2(44, 40), 1)
	UiIcon.into_button(refresh, "repeat", 18, Color(0.9, 0.95, 1.0))
	# UX-31: loading-состояние сетевой кнопки — disabled на время запроса.
	refresh.pressed.connect(func() -> void:
		refresh.disabled = true
		refresh.tooltip_text = "Обновляю…"
		Net.rating(_device_id))
	refresh.name = "RatingRefresh"
	status_row.add_child(refresh)
	_rating_list = VBoxContainer.new()
	_rating_list.add_theme_constant_override("separation", 6)
	page.add_child(_rating_list)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 150)
	page.add_child(bottom_pad)


func _refresh_rating() -> void:
	if _net_enabled:
		Net.rating(_device_id)


func _on_net_rating_result(result: Dictionary) -> void:
	var refresh: Button = null
	for b in g.find_children("RatingRefresh", "Button", true, false):
		refresh = b as Button
		break
	if refresh != null:
		refresh.disabled = false
		refresh.tooltip_text = "Обновить рейтинг"
	if _rating_list == null:
		return
	for child in _rating_list.get_children():
		_rating_list.remove_child(child)
		child.queue_free()
	if result.get("ok", false) != true:
		_rating_status.text = "Сервер недоступен — рейтинг появится позже."
		return
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		_rating_status.text = "Пока никто ничего не открыл. Стань первым!"
	else:
		_rating_status.text = "Первооткрытия · вещества · очки целей"
	var me_raw = result.get("me")
	if typeof(me_raw) == TYPE_DICTIONARY:
		var me := me_raw as Dictionary
		_rating_me.text = "Ты: #%d %s — открытий %d" % [
			int(me.get("rank", 0)), g._clean_str(me.get("nick", "ты")), int(me.get("discoveries", 0))]
		var nr := int(me.get("rank", 0))
		if nr > 0:
			if (g._saves._return_open or g._saves._return_due()) and g._saves._return_rank_old < 0:
				g._saves._return_rank_old = g._last_rank
			g._last_rank = nr
			g._saves._save_game()
	else:
		_rating_me.text = ""
	if g._saves._return_open:
		g._saves._refresh_return_popup()
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d := r as Dictionary
		var nick := g._clean_str(d.get("nick", "кто-то"))
		var rank := int(d.get("rank", 0))
		var disc := int(d.get("discoveries", 0))
		var elems := int(d.get("elements", 0))
		var pts := int(d.get("points", 0))
		var has_house := bool(d.get("house_built", false))
		# Блок 5: строка рейтинга — карточка; топ-3 с «медальным» цветом места.
		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.07, 0.10, 0.14, 0.9)
		csb.set_corner_radius_all(12)
		csb.content_margin_left = 10
		csb.content_margin_right = 10
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		if nick == _net_nick:
			csb.border_color = Color(0.35, 0.88, 0.84, 0.9)
			csb.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", csb)
		_rating_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var rl := g._label("#%d" % rank, 15)
		rl.custom_minimum_size = Vector2(40, 0)
		var medal := [Color(1.0, 0.85, 0.44), Color(0.78, 0.82, 0.86), Color(0.80, 0.59, 0.39)]
		rl.add_theme_color_override("font_color", medal[rank - 1] if rank in [1, 2, 3] else Color(0.49, 0.55, 0.61))
		row.add_child(rl)
		row.add_child(g._make_avatar(nick, 20))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var nm := g._label(nick, 14)
		v.add_child(nm)
		# γ: сколько человек побывало в гостях у этого игрока за ISO-неделю (T7)
		var guests := int(d.get("house_guests", 0))
		var extra := "" if guests == 0 else " · гостей %d" % guests
		var st := g._label("открытий %d · веществ %d · очки %d%s" % [disc, elems, pts, extra], 11)
		st.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
		v.add_child(st)
		var chip := g._label("%d ⚡" % pts, 12)
		chip.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		var chsb := StyleBoxFlat.new()
		chsb.bg_color = Color(0.15, 0.20, 0.26, 0.9)
		chsb.set_corner_radius_all(13)
		chsb.content_margin_left = 10
		chsb.content_margin_right = 10
		chsb.content_margin_top = 4
		chsb.content_margin_bottom = 4
		chip.add_theme_stylebox_override("normal", chsb)
		row.add_child(chip)
		if has_house:
			var btn := g._small_button("Домик", Vector2(80, 36), 1)
			btn.pressed.connect(g._home._open_player_house.bind(nick))
			row.add_child(btn)


func _on_net_house_result(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	if bool(result.get("_saved", false)):
		return  # эхо собственной выгрузки — гостевой попап не трогаем
	var nick := g._clean_str(result.get("nick", ""))
	var house_raw = result.get("house")
	if not result.get("found", true):
		# кнопка визита видима уже с момента открытия попапа (_open_player_house):
		# у несуществующего домика ей нажиматься нельзя — спалит локальный
		# дневной кэш _mark_visited
		if g._home._house_visit_btn != null:
			g._home._house_visit_btn.visible = false
		if g._home._house_popup != null and g._home._house_popup.visible:
			g._home._house_popup_title.text = "%s: домика нет" % nick
		return
	if typeof(house_raw) == TYPE_DICTIONARY:
		g._home._apply_player_house(nick, house_raw as Dictionary)
		# γ: у визита должны быть последствия — сообщаем хосту, что заходили.
		# Один раз на хоста в день: локальный кэш, чтобы не долбить сеть при каждом
		# открытии попапа (и офлайн сюда не доходит: Net.house_get зовётся только с сетью).
		if g._online._device_id != "" and nick != "" and g._home._visit_allowed(nick):
			g._home._mark_visited(nick)
			Net.house_visit(g._online._device_id, nick)
	else:
		if g._home._house_visit_btn != null:
			g._home._house_visit_btn.visible = false
		if g._home._house_popup != null and g._home._house_popup.visible:
			g._home._house_popup_title.text = "%s: домик ещё не построен" % nick


func _on_net_house_visit_result(result: Dictionary) -> void:
	# Ответ нужен только для статуса: награда хосту идёт через /api/me (T7),
	# а не здесь — иначе счётчик зависел бы от того, кто первым успел зайти.
	if result.get("ok", false) == true:
		g._engine.status_text = "Визит засвидетельствован."


func _on_net_rejected_result(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	var arr: Array = result.get("rejected", [])
	for pk in arr:
		g._engine._rejected_pairs[String(pk)] = true


func _has_ingredients(a: String, b: String) -> bool:
	if a == b:
		return int(g._engine.inventory.get(a, 0)) >= 2
	return int(g._engine.inventory.get(a, 0)) >= 1 and int(g._engine.inventory.get(b, 0)) >= 1

func _find_recipe(a: String, b: String) -> Dictionary:
	var key := g._pair_key(a, b)
	for recipe in g.RECIPES:
		if g._pair_key(String(recipe["a"]), String(recipe["b"])) == key:
			return recipe
	return {}
func _is_server_pair(a: String, b: String) -> bool:
	# план 2: personal find возможен только для пары, которую сервер уже знает
	var key := g._pair_key(a, b)
	for sr in _server_recipes:
		if g._pair_key(String(sr.get("a", "")), String(sr.get("b", ""))) == key:
			return true
	return false

func _run_netbrew(a: String, b: String) -> void:
	"""Отладка интеграции: прогнать пару через сеть как неизвестную."""
	# U11: dev-хук (--netbrew=) — запись pending ставится напрямую, в том
	# числе перезаписью занятого слота: это ручной одиночный прогон запроса.
	_pending_requests[g._pair_key(a, b)] = {
		"a": a, "b": b, "experiment": false, "at": Time.get_ticks_msec()}
	print("NETBREW start ", a, " + ", b)
	Net.check_pair(a, b, _net_nick, _device_id)

func _tick_netexperiment() -> void:
	if _netexperiment_started or _netexperiment_pair == "" or not _net_enabled or not Net.is_available():
		return
	var parts := _netexperiment_pair.split(",", false)
	if parts.size() != 2:
		print("NETEXPERIMENT invalid pair=", _netexperiment_pair)
		_netexperiment_started = true
		return
	var a := String(parts[0]).strip_edges()
	var b := String(parts[1]).strip_edges()
	if a == "" or b == "":
		print("NETEXPERIMENT invalid pair=", _netexperiment_pair)
		_netexperiment_started = true
		return
	_netexperiment_started = true
	print("NETEXPERIMENT start ", a, " + ", b)
	_start_experiment(a, b)

func _set_status(text: String) -> void:
	g._engine.status_text = text
	if g._engine._status_label != null:
		g._engine._status_label.text = text
	# Экспериментальная локация имеет собственную обратную связь, чтобы
	# серверный результат был виден рядом с котлом, а не только в шапке.
	if g._pages != null and g._pages._experiment_status != null:
		g._pages._experiment_status.text = text

func _prune_pending_requests() -> void:
	# U11 (T14): устаревание записей pending — по времени вставки (см. блок
	# комментария у _pending_requests). Вызывается на каждой регистрации/изъятии.
	# Не только удаляет: просроченный живой эксперимент разрешаем так же, как
	# offline-refund в _tick_pending_experiment (возврат реагентов и полного
	# эфира), иначе осиротевший _experiment_pending_pair заблокирует три системы.
	var now := Time.get_ticks_msec()
	for key in _pending_requests.keys():
		var entry: Dictionary = _pending_requests[key]
		if now - int(entry.get("at", now)) <= PENDING_TTL_MSEC:
			continue
		_pending_requests.erase(String(key))
		var ea := String(entry.get("a", ""))
		var eb := String(entry.get("b", ""))
		# не трогаем чужой/свежий эксперимент и уже сброшенный мир (U9-контракт):
		# возврат только когда висящий pending совпадает с этой записью.
		if bool(entry.get("experiment", false)) and _experiment_pending_matches(ea, eb):
			g._engine._finish_experiment_inputs(ea, eb, true)
			_set_status("Мир не ответил вовремя: реагенты и эфир возвращены.")
			g._saves._save_game()

func _register_pending_pair(a: String, b: String, is_experiment: bool) -> bool:
	# True — слот свободен и занят этой парой; False — pending уже ждёт ответа
	# (этой или другой пары) либо a/b пусты: запрос отправлять нельзя.
	if a == "" or b == "":
		return false
	_prune_pending_requests()
	if not _pending_requests.is_empty():
		return false
	_pending_requests[g._pair_key(a, b)] = {
		"a": a, "b": b, "experiment": is_experiment, "at": Time.get_ticks_msec()}
	return true

func _take_pending_pair(pair_key: String) -> Dictionary:
	# Изъекает pending-запись по pair_key из сигнала Net; {} — записи нет
	# (дубликат/запоздалый ответ, ответ после сброса или prune).
	_prune_pending_requests()
	if not _pending_requests.has(pair_key):
		return {}
	var entry: Dictionary = _pending_requests[pair_key]
	_pending_requests.erase(pair_key)
	return entry

func _experiment_pending_matches(a: String, b: String) -> bool:
	# U11 (T14): закрывает задел U9 — сверка пары ответа с висящим экспериментом
	# (порядок-insensitive, через ту же нормализацию _pair_key).
	var pending: Array = g._engine._experiment_pending_pair
	return pending.size() == 2 \
		and g._pair_key(String(pending[0]), String(pending[1])) == g._pair_key(a, b)

func _grant_local_acquisition(slug: String) -> Array:
	# единая точка «первое локальное получение вещества из мира»: +1 в инвентарь,
	# circular-эффект Круга и грант первооткрытия; возвращает новые вехи
	var first_open := not g._engine.inventory.has(slug)
	g._engine.inventory[slug] = int(g._engine.inventory.get(slug, 0)) + 1
	g._retention._circle_on_discovery(first_open)
	if first_open:
		return g._engine._grant_first_open(slug)
	return []

func _try_net_candidate(a: String, b: String) -> bool:
	"""Попробовать проверить неизвестную пару на сервере. True — запрос ушёл."""
	if not _net_enabled or not Net.is_available():
		return false
	var key := g._pair_key(a, b)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(g._engine._last_candidate_time.get(key, 0.0)) < Game.CANDIDATE_COOLDOWN:
		return false
	if randf() < Game.CANDIDATE_CHANCE:
		return false
	# U11 (T14): не перезахватываем занятый слот. Пока другая пара ждёт ответа
	# мира, запрос не отправляем и cooldown не тратим: игрок видит штатную
	# реплику неудачной варки («Туман рассеялся… Возвращено N эфира»,
	# core.gd `_brew`), пара остаётся неизвестной и запросится позже.
	if not _register_pending_pair(a, b, false):
		return false
	g._engine._last_candidate_time[key] = now
	# The legacy cauldron path also uses the server's Experiment budget now, but
	# keeps its existing refund/inventory semantics.
	Net.check_pair(a, b, _net_nick, _device_id, true)
	return true

func _start_experiment(a: String, b: String) -> bool:
	"""Явный Эксперимент: только 2 реагента в v1, сервер авторитетен."""
	if not _net_enabled or not Net.is_available():
		_set_status("Эксперимент требует связи с миром: новый элемент нельзя создать офлайн.")
		Sfx.error()
		return false
	# U11 (T14): начинаем эксперимент только на свободный pending-слот — иначе
	# реагенты были бы съедены, а ответ чужой пары применён к эксперименту.
	_prune_pending_requests()
	if not _pending_requests.is_empty():
		_set_status("Мир ещё обрабатывает предыдущий запрос — эксперимент будет доступен через несколько секунд.")
		Sfx.error()
		return false
	if not g._engine._begin_experiment(a, b):
		return false
	# Слот пуст и иных потребителей в этом кадре нет — регистрация успешна by construction.
	if not _register_pending_pair(a, b, true):
		g._engine._finish_experiment_inputs(a, b, true)
		return false
	Net.check_pair(a, b, _net_nick, _device_id, true)
	g._saves._save_game()
	return true

func _resume_pending_experiment() -> void:
	if g._engine._experiment_pending_pair.size() != 2 or not _net_enabled:
		return
	var a := String(g._engine._experiment_pending_pair[0])
	var b := String(g._engine._experiment_pending_pair[1])
	# U11 (T14): resume — авторитетный путь (запись эксперимента восстановлена
	# из сейва): осиротевшие записи прошлой сессии сбрасываем, их ответы
	# будут проигнорированы без pending-записи.
	_pending_requests.clear()
	if not Net.is_available() or not _register_pending_pair(a, b, true):
		# нет связи ИЛИ регистрация не удалась (пустой slug из сейва): запрос
		# не отправляем — без записи pending он некоррелируем (дефект T14).
		# Сохранённая пара ждёт; 8-секундный дедлайн вернёт реагенты штатно.
		_resume_experiment_wait = true
		_resume_experiment_deadline = Time.get_ticks_msec() / 1000.0 + 8.0
		_set_status("Эксперимент сохранён; ждём связь с миром для продолжения.")
		return
	_resume_experiment_wait = false
	_set_status("Продолжаем незавершённый эксперимент: %s + %s…" % [_item_name(a), _item_name(b)])
	Net.check_pair(a, b, _net_nick, _device_id, true)

func _tick_pending_experiment() -> void:
	if not _resume_experiment_wait or g._engine._experiment_pending_pair.size() != 2:
		return
	if Net.is_available():
		_resume_pending_experiment()
		return
	if Time.get_ticks_msec() / 1000.0 < _resume_experiment_deadline:
		return
	var a := String(g._engine._experiment_pending_pair[0])
	var b := String(g._engine._experiment_pending_pair[1])
	_resume_experiment_wait = false
	g._engine._finish_experiment_inputs(a, b, true)
	_set_status("Эксперимент не был отправлен: реагенты и эфир возвращены.")
	g._saves._save_game()

func _experiment_outcome(out: Dictionary, a: String, b: String, created: bool = false) -> void:
	# U9 (T12): поздний ответ эксперимента после сброса мира (престиж/новая игра
	# чистят _experiment_pending_pair) не должен регистрировать рецепты, дарить
	# вещества и списывать свежий подарочный запас — дропаем без эффектов.
	if g._engine._experiment_pending_pair.size() != 2:
		print("NETEXPERIMENT stale pair=", a, " + ", b)
		_set_status("Поздний ответ эксперимента проигнорирован: лаборатория уже была сброшена.")
		return
	# U11 (T14): задел U9 закрыт — поздний ответ СТАРОЙ пары, пока висит новый
	# эксперимент, тоже дропается (сверка pair_key, defense-in-depth:
	# обработчики Net проверяют то же до вызова).
	if not _experiment_pending_matches(a, b):
		print("NETEXPERIMENT mismatch pair=", a, " + ", b)
		_set_status("Поздний ответ эксперимента проигнорирован: он не про текущую пару.")
		return
	var slug := _apply_server_element(out)
	if slug == "":
		g._engine._finish_experiment_inputs(a, b, true)
		Analytics.track("experiment_result", {"left": a, "right": b, "result": "invalid"})
		_set_status("Мир вернул неполный результат — реагенты восстановлены.")
		return
	_register_server_recipe(a, b, slug)
	var key := g._pair_key(a, b)
	g._engine.known_recipes[key] = true
	# first_open — до инкремента; грант и круг — ПОСЛЕ _experiment_succeeded (она
	# делает inventory[slug]+=1): иначе _check_milestones не учтёт это вещество и
	# веха на N веществ сработает на одно открытие позже.
	var first_open := not g._engine.inventory.has(slug)
	g._engine._experiment_succeeded(slug, a, b)
	g._retention._circle_on_discovery(first_open)
	var first_milestones: Array = []
	if first_open:
		first_milestones = g._engine._grant_first_open(slug)
	g._retention._fair_report_brew(a, b)
	if created:
		_set_status("ПЕРВОЭКСПЕРИМЕНТ: %s — мир записал тебя первым!" % _item_name(slug))
		g._spirit._companion_react("world_first", _item_name(slug))
		g._hub._log_event("Первооткрытие через Эксперимент: «%s»" % _item_name(slug))
		g._spirit._companion_gain(5)
		g._progress_ui._ach_world_first += 1
		g._progress_ui._ach_update()
	else:
		g._spirit._companion_react_discovery(slug)
	_server_authors[slug] = g._clean_str(out.get("author", _net_nick))
	_rebuild_world_grid()
	g._show_discovery_popup(slug, a, b, first_milestones)
	g._saves._save_game()

func _on_net_pair_result(pair_key: String, result: Dictionary) -> void:
	print("NETPAIR status=", g._clean_str(result.get("status", "")), " found=", result.get("found", false))
	# U11 (T14): ответ привязан к pair_key запроса (net.gd `_dispatch`).
	# Записи pending нет — дубликат/запоздалый ответ молча дропаем.
	var entry := _take_pending_pair(pair_key)
	if entry.is_empty():
		print("NETPAIR dropped: no pending entry for pair=", pair_key)
		return
	var a := String(entry["a"])
	var b := String(entry["b"])
	var is_experiment := bool(entry["experiment"])
	if is_experiment and not _experiment_pending_matches(a, b):
		print("NETEXPERIMENT stale pair=", a, " + ", b)
		_set_status("Поздний ответ эксперимента проигнорирован: он не про текущую пару.")
		return
	if result.get("ok", false) == true and result.get("found", false) == true:
		if is_experiment:
			_experiment_outcome(result.get("out", {}) as Dictionary, a, b)
			return
		var slug := _apply_server_element(result.get("out", {}))
		if slug != "":
			_register_server_recipe(a, b, slug)
			g._engine.known_recipes[g._pair_key(a, b)] = true
			g._retention._fair_report_brew(a, b)
			# U11 (T15): первое ЛОКАЛЬНОЕ получение мир-открытого вещества — через
			# _grant_local_acquisition (+1 в инвентарь, circular-эффект Круга,
			# _grant_first_open: rarity-пошлина, tier-учёт гильдии, вехи атласа,
			# сброс _layer_cache) — как _commit_brew и discover-ветка. Серверные
			# награды первооткрытия (_ach_world_first, «ПЕРВООТКРЫТИЕ») здесь
			# НЕ начисляются — их даёт только created/не-reused путь, так что
			# двойного счёта достижений нет.
			var first_milestones: Array = _grant_local_acquisition(slug)
			var world_author := g._clean_str((result.get("out", {}) as Dictionary).get("author", ""))
			if world_author != "":
				_server_authors[slug] = world_author
			_set_status("Эта пара уже открыта в мире: %s!" % _item_name(slug))
			_rebuild_world_grid()
			g._engine._refresh()
			g._show_discovery_popup(slug, a, b, first_milestones)
		else:
			_set_status("Туман рассеялся… (мир не ответил внятно)")
	elif String(result.get("status", "")) == "not_combinable":
		if is_experiment:
			g._engine._experiment_failed(a, b)
			return
		g._engine._rejected_pairs[pair_key] = true
		_set_status("Туман рассеялся… эти вещества не сочетаются.")
		g._spirit._companion_react("fail", "")
	elif String(result.get("status", "")) == "candidate" or (result.get("ok", false) == true and result.get("found", false) == false):
		# Слот свободен (запись извлечена выше) — занимаем его заново под
		# discover-фазу той же пары; не занял (гонка/prune) — молча не
		# отправляем: пара останется кандидатом и повторится по cooldown.
		if _register_pending_pair(a, b, is_experiment):
			Net.discover(a, b, _net_nick, _device_id, is_experiment)
	else:
		var msg := g._clean_str(result.get("message", ""))
		if is_experiment:
			g._engine._finish_experiment_inputs(a, b, true)
			Analytics.track("experiment_result", {"left": a, "right": b, "result": "unavailable"})
			_set_status("Эксперимент отложен: %s" % (msg if msg != "" else "мир недоступен"))
			return
		_set_status("Мир не ответил: %s" % msg if msg != "" else "Туман рассеялся… (мир недоступен)")

func _on_net_discover_result(pair_key: String, result: Dictionary) -> void:
	print("NETDISCOVER status=", g._clean_str(result.get("status", "")))
	var status := String(result.get("status", ""))
	var disc: Dictionary = {}
	var disc_raw = result.get("discovery", {})
	if typeof(disc_raw) == TYPE_DICTIONARY:
		disc = disc_raw
	# U11 (T14): корреляция по pair_key из сигнала; записи pending нет —
	# дропаем. Для created/known сервер эхом кладёт пару в discovery
	# (server.py: DiscoveryData.a/b/pair_key) — требуем непустых a/b, равных
	# pending-записи (порядок-insensitive через _pair_key). Раньше пустые a/b
	# дарили вещество «ни за что».
	var entry := _take_pending_pair(pair_key)
	if entry.is_empty():
		print("NETDISCOVER dropped: no pending entry for pair=", pair_key)
		return
	var a := String(entry["a"])
	var b := String(entry["b"])
	var is_experiment := bool(entry["experiment"])
	if status == "created" or status == "known":
		var da := g._clean_str(disc.get("a", ""))
		var db := g._clean_str(disc.get("b", ""))
		if da == "" or db == "" or g._pair_key(da, db) != pair_key:
			print("NETDISCOVER dropped: discovery pair mismatch for pair=", pair_key)
			return
	if is_experiment and not _experiment_pending_matches(a, b):
		print("NETEXPERIMENT stale pair=", a, " + ", b)
		_set_status("Поздний ответ эксперимента проигнорирован: он не про текущую пару.")
		return
	# U6-fix (I-1): сервер возвращает status="created" и для reused (дедуп
	# имени: пара привязана к уже существующему веществу) — это НЕ
	# первооткрытие, серверных наград в таком ответе нет. Клиентские награды
	# (ПЕРВООТКРЫТИЕ, спутник, ачивка, vein-бонус) обязан включать только
	# reused-флаг из discovery, иначе дубль-имя фармит «первооткрытия».
	var reused := bool(disc.get("reused", false))
	if status == "created" or status == "known":
		if is_experiment:
			_experiment_outcome(disc, a, b, status == "created" and not reused)
			return
		var slug := _apply_server_element(disc)
		if slug != "":
			_register_server_recipe(a, b, slug)
			g._engine.known_recipes[g._pair_key(a, b)] = true
			g._retention._fair_report_brew(a, b)
			# first_open нужен ниже (статус/реакция спутника); хелпер считает его сам
			# перед тем же инкрементом — значения совпадают.
			var first_open := not g._engine.inventory.has(slug)
			var first_milestones: Array = _grant_local_acquisition(slug)
			if status == "known":
				# §3.3.1: пара известна серверу, но клиент её ещё не регистрировал
				# как личную — маршрутизируем в /api/vein/find.
				g._retention._vein_report_pair(a, b, slug)
			var author := g._clean_str(disc.get("author", _net_nick))
			_server_authors[slug] = author
			if status == "created" and not reused:
				_set_status("ПЕРВООТКРЫТИЕ: %s (автор: %s)!" % [_item_name(slug), author])
				g._spirit._companion_react("world_first", _item_name(slug))
				g._hub._log_event("Первооткрытие: «%s» — ты первый!" % _item_name(slug))
				g._spirit._companion_gain(5)
				g._progress_ui._ach_world_first += 1
				g._progress_ui._ach_update()
			else:
				_set_status("Эта пара уже открыта: %s (автор: %s)." % [_item_name(slug), author])
				if first_open:
					g._spirit._companion_react_discovery(slug)
			# ежедневная цель (личная, день не заканчивается первым)
			var ch_won := false
			var ch_first := false
			var ch_target_name := ""
			var ch_raw = result.get("challenge")
			if typeof(ch_raw) == TYPE_DICTIONARY:
				var ch := ch_raw as Dictionary
				ch_target_name = g._clean_str(ch.get("target_name", ""))
				ch_won = bool(ch.get("won", false))
				ch_first = bool(ch.get("first", false))
			_rebuild_world_grid()
			g._engine._refresh()
			if ch_won:
				g._engine._grant_ether(Game.CHALLENGE_REWARD, "daily_challenge")
				g._spirit._companion_gain(5)
				g._guild._quest_on_challenge()
				g._spirit._companion_react("challenge_win", ch_target_name)
				_set_status("ЕЖЕДНЕВНАЯ ЦЕЛЬ ВЫПОЛНЕНА: +%d эфира!" % Game.CHALLENGE_REWARD)
				g._hub._log_event("Ежедневная цель «%s» выполнена: +%d эфира" % [ch_target_name, Game.CHALLENGE_REWARD])
				g._show_challenge_win_popup(slug, ch_target_name, a, b, ch_first)
			else:
				var rr := g._engine._rarity_of(slug)
				var sub2 := "%s + %s → %s\nавтор: %s" % [_item_name(a), _item_name(b), _item_name(slug), author]
				var dsc2 := _item_desc(slug)
				if dsc2 != "":
					sub2 += "\n«%s»" % dsc2
				sub2 += "\n%s · награда +%d ⚡" % [rr["name"], rr["bounty"]]
				for m in first_milestones:
					sub2 += "\n%s" % g._engine._milestone_text(int(m))
				g._present_popup(slug, sub2, "НОВЫЙ РЕЦЕПТ!", rr["color"])
			if status == "created" and not reused:
				g._retention._discover_vein_bonus(result)
				var vein_data = result.get("vein")
				if typeof(vein_data) == TYPE_DICTIONARY:
					g._retention._vein_add_from_discover(pair_key, slug, vein_data)
	elif status == "not_combinable":
		if is_experiment:
			g._engine._experiment_failed(a, b)
			return
		g._engine._rejected_pairs[pair_key] = true
		_set_status("Туман рассеялся… эти вещества не сочетаются.")
		g._spirit._companion_react("fail", "")
	else:
		var msg := g._clean_str(result.get("message", ""))
		if is_experiment:
			g._engine._finish_experiment_inputs(a, b, true)
			Analytics.track("experiment_result", {"left": a, "right": b, "result": "unavailable"})
			_set_status("Эксперимент отложен: %s" % (msg if msg != "" else "мир недоступен"))
			return
		_set_status("Мир не ответил: %s" % msg if msg != "" else "Туман рассеялся… (мир недоступен)")

func _apply_server_element(d) -> String:
	"""Зарегистрировать элемент с сервера в локальных данных; вернуть slug ("" если не вышло)."""
	if typeof(d) != TYPE_DICTIONARY:
		return ""
	var dd: Dictionary = d
	var slug := String(dd.get("slug", ""))
	var name := String(dd.get("name", ""))
	var color := String(dd.get("color", "#8899aa"))
	if slug == "" or name == "":
		return ""
	var tag := g._clean_str(dd.get("tag", ""))
	if slug != "" and tag != "":
		_server_tag[slug] = tag
	if not color.begins_with("#"):
		color = "#8899aa"
	var glyph := String(dd.get("glyph", ""))
	if glyph == "" or not ElementGlyphs.has(glyph):
		glyph = _category_glyph(String(dd.get("category", "")))
	var cat := g._clean_str(dd.get("category", ""))
	var dsc := g._clean_str(dd.get("d", "")).strip_edges()
	if dsc == "" and cat != "":
		dsc = "Стихия «%s»." % cat
	if not g.ITEMS.has(slug):
		var entry: Dictionary = {"name": name, "color": color}
		if glyph != "":
			entry["g"] = glyph
		if dsc != "":
			entry["d"] = dsc
		g.ITEMS[slug] = entry
		g._item_colors[slug] = Color(color)
		_server_elements[slug] = entry
		g._engine._layer_cache.erase(slug)
		_add_inventory_orb(slug)
	else:
		if glyph != "" and not g.ITEMS[slug].has("g"):
			g.ITEMS[slug]["g"] = glyph
		if dsc != "" and not g.ITEMS[slug].has("d"):
			g.ITEMS[slug]["d"] = dsc
		if _server_elements.has(slug):
			_server_elements[slug] = g.ITEMS[slug]
	_server_layers[slug] = int(dd.get("layer", 0))
	return slug

func _register_server_recipe(a: String, b: String, out: String) -> void:
	g._engine._layer_cache.erase(out)
	var key := g._pair_key(a, b)
	for r in g.RECIPES:
		if g._pair_key(String(r["a"]), String(r["b"])) == key:
			return
	g.RECIPES.append({"a": a, "b": b, "out": out})
	for sr in _server_recipes:
		if g._pair_key(String(sr.get("a", "")), String(sr.get("b", ""))) == key:
			return
	_server_recipes.append({"a": a, "b": b, "out": out})

func _restore_server_elements(raw) -> void:
	# снять ранее зарегистрированные серверные элементы, чтобы повторная
	# загрузка не дублировала и не подмешивала чужие
	for slug in _server_elements:
		g.ITEMS.erase(String(slug))
		g._item_colors.erase(String(slug))
	_server_elements.clear()
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for key in raw:
		var slug := String(key)
		var e = raw[key]
		if typeof(e) != TYPE_DICTIONARY or slug == "":
			continue
		var name := g._clean_str(e.get("name", "")).strip_edges()
		var color := g._clean_str(e.get("color", "#8899aa"))
		if name == "":
			continue
		if not color.begins_with("#"):
			color = "#8899aa"
		var entry: Dictionary = {"name": name, "color": color}
		var gl := g._clean_str(e.get("g", ""))
		if gl != "" and ElementGlyphs.has(gl):
			entry["g"] = gl
		var d := g._clean_str(e.get("d", ""))
		if d != "":
			entry["d"] = d
		g.ITEMS[slug] = entry
		g._item_colors[slug] = Color(color)
		g._engine._layer_cache.erase(slug)
		_server_elements[slug] = entry


func _restore_server_recipes(raw) -> void:
	for sr in _server_recipes:
		var sk := g._pair_key(String(sr.get("a", "")), String(sr.get("b", "")))
		for i in range(g.RECIPES.size() - 1, -1, -1):
			if g._pair_key(String(g.RECIPES[i]["a"]), String(g.RECIPES[i]["b"])) == sk:
				g.RECIPES.remove_at(i)
				break
	_server_recipes.clear()
	if typeof(raw) != TYPE_ARRAY:
		return
	for r in raw:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var a := String(r.get("a", ""))
		var b := String(r.get("b", ""))
		var out := String(r.get("out", ""))
		if a == "" or b == "" or out == "":
			continue
		if _find_recipe(a, b).is_empty():
			g.RECIPES.append({"a": a, "b": b, "out": out})
		_server_recipes.append({"a": a, "b": b, "out": out})


func _add_inventory_orb(item_id: String) -> void:
	# Новые вещества используют тот же компактный вид ячейки, что и
	# первоначальный список лаборатории.
	if g._pages != null:
		g._pages._add_lab_reagent_cell(item_id)

func _load_device_id() -> String:
	# Единое хранилище установки вместо отдельного открытого файла. Старый
	# user://device_id читается один раз для миграции, затем переносится в
	# UserData.
	if UserData != null:
		var id := UserData.get_or_create_device_id()
		if id != "":
			return id
	var legacy_path := "user://device_id"
	if FileAccess.file_exists(legacy_path):
		var legacy := FileAccess.open(legacy_path, FileAccess.READ)
		if legacy != null:
			var old_id := legacy.get_as_text().strip_edges()
			if old_id != "":
				return old_id
	return "install_" + ("%s:%s" % [Time.get_unix_time_from_system(), randi()]).sha256_text().substr(0, 32)

# ---------------------------------------------------------------------------
# #8: «Удалить локальные данные» внутри живой сессии.
# ---------------------------------------------------------------------------
func _forget_net_identity() -> void:
	# старый device_id больше не должен уходить на сервер: почти все Net-вызовы
	# гейтятся _net_enabled и непустым _device_id (resonance/retention/riddles/
	# home). Само удаление сервера — исключение: оно идёт ДО вызова этого метода.
	_net_enabled = false
	_device_id = ""
	_net_nick = ""

func _retry_pending_account_delete(net: Object = null) -> void:
	if net == null:
		net = Net
	var pending := UserData.get_account_delete_pending()
	if pending == "":
		return
	net.delete_account(pending)

func _on_account_delete_result(result: Dictionary) -> void:
	if result.get("ok", false) == true:
		var pending := UserData.get_account_delete_pending()
		var deleted_id := String(result.get("device_id", ""))
		if deleted_id == "" or deleted_id == pending:
			UserData.clear_account_delete_pending()

func _on_net_world_result(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		_world_loaded = true
		if _world_status != null:
			_world_status.text = "Сервер недоступен — показаны локальные вещества."
		return
	var elements: Array = result.get("elements", [])
	var total := int(result.get("total", 0))
	var page := int(result.get("page", 1))
	var per_page := int(result.get("per_page", 100))
	for e in elements:
		var slug := _apply_server_element(e)
		if slug != "" and typeof(e) == TYPE_DICTIONARY:
			_server_authors[slug] = g._clean_str((e as Dictionary).get("author", ""))
	print("NETWORLD page=", page, " total=", total, " got=", elements.size(), " local=", g.ITEMS.size())
	# дотягиваем остальные страницы (сервер отдаёт до 100 за запрос)
	if page * per_page < total:
		Net.world(page + 1)
		return
	if _world_status != null:
		_world_status.text = "В мире известно %d веществ (локально %d)." % [total, g.ITEMS.size()]
	_world_loaded = true
	_world_total = total
	if (g._saves._return_open or g._saves._return_due()) and g._saves._return_world_new < 0:
		g._saves._return_world_new = maxi(0, total - _world_total_seen)
	_world_total_seen = total
	if g._saves._return_open:
		g._saves._refresh_return_popup()
	g._saves._save_game()
	_rebuild_world_grid()

func _world_query() -> String:
	if _world_search == null:
		return ""
	return _world_search.text.strip_edges().to_lower()


func _world_filtered_ids() -> Array:
	var q := _world_query()
	var ids: Array = g.ITEMS.keys()
	ids.sort()
	if q == "":
		return ids
	var out: Array = []
	for item_id in ids:
		var sid := String(item_id)
		var author := String(_server_authors.get(sid, ""))
		if _item_name(sid).to_lower().contains(q) or sid.to_lower().contains(q) or (author != "" and author.to_lower().contains(q)):
			out.append(sid)
	return out


func _world_set_page(p: int) -> void:
	var total := _world_filtered_ids().size()
	var pages := maxi(1, int(ceil(float(total) / float(Game.WORLD_PAGE_SIZE))))
	_world_page = clampi(p, 0, pages - 1)
	Sfx.click()
	_rebuild_world_grid()


func _on_world_search(_t: String) -> void:
	_world_page = 0
	_rebuild_world_grid()


func _rebuild_world_grid() -> void:
	if _world_grid == null:
		return
	for child in _world_grid.get_children():
		_world_grid.remove_child(child)
		child.queue_free()
	var ids := _world_filtered_ids()
	var total := ids.size()
	var pages := maxi(1, int(ceil(float(total) / float(Game.WORLD_PAGE_SIZE))))
	_world_page = clampi(_world_page, 0, pages - 1)
	var from := _world_page * Game.WORLD_PAGE_SIZE
	var to := mini(total, from + Game.WORLD_PAGE_SIZE)
	if total == 0 and _world_grid != null:
		_world_grid.add_child(g._label("Ничего не найдено. Попробуй другой запрос.", 13))
	for i in range(from, to):
		var item_id: String = ids[i]
		var sid := String(item_id)
		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.05, 0.08, 0.11, 0.9)
		csb.set_corner_radius_all(12)
		csb.content_margin_left = 10
		csb.content_margin_right = 10
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", csb)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_world_grid.add_child(card)
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var orb := g._make_orb(sid, 34)
		orb.interactive = false
		row.add_child(orb)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var author := String(_server_authors.get(sid, ""))
		var nm := g._label(_item_name(sid), 14)
		if author != "" and author == _net_nick and g._resonance._res_gilded():
			nm.text = "✦ " + nm.text
			nm.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(nm)
		var subrow := HBoxContainer.new()
		subrow.add_theme_constant_override("separation", 6)
		if author != "":
			subrow.add_child(g._make_avatar(author, 16))
			var sub := g._label("автор: %s" % author, 11)
			sub.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
			subrow.add_child(sub)
		else:
			var sub := g._label("локально", 11)
			sub.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
			subrow.add_child(sub)
		v.add_child(subrow)
		var dsc := _item_desc(sid)
		if dsc != "":
			var dl := g._label(dsc, 11)
			dl.add_theme_color_override("font_color", Color(0.45, 0.52, 0.60))
			v.add_child(dl)
		row.add_child(v)
	if _world_page_label != null:
		if total == 0:
			_world_page_label.text = "0 веществ"
		else:
			_world_page_label.text = "%d–%d из %d · стр. %d/%d" % [from + 1, to, total, _world_page + 1, pages]
	if _world_prev != null:
		_world_prev.disabled = _world_page <= 0
	if _world_next != null:
		_world_next.disabled = _world_page >= pages - 1

func _item_name(item_id: String) -> String:
	return String(g.ITEMS[item_id]["name"])

func _item_desc(item_id: String) -> String:
	return String(g.ITEMS[item_id].get("d", ""))

func _item_glyph(item_id: String) -> String:
	if not g.ITEMS.has(item_id):
		return item_id
	var gl := String(g.ITEMS[item_id].get("g", ""))
	return gl if gl != "" else item_id

func _category_glyph(cat: String) -> String:
	match cat:
		"огонь":
			return "fire"
		"вода":
			return "water"
		"земля":
			return "earth"
		"воздух":
			return "air"
	return ""

func _on_search_changed(_t: String) -> void:
	g._engine._refresh()

func _search_query() -> String:
	if g._engine._search_box == null:
		return ""
	return g._engine._search_box.text.strip_edges().to_lower()

func _matches_search(item_id: String) -> bool:
	var q := _search_query()
	if q == "":
		return true
	return _item_name(item_id).to_lower().contains(q) or item_id.to_lower().contains(q)

func _init_colors() -> void:
	for raw_id in g.ITEMS:
		g._item_colors[String(raw_id)] = Color(String(g.ITEMS[raw_id]["color"]))

func _floater_at(pos: Vector2, text: String, color: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 20)
	lb.add_theme_color_override("font_color", color.lightened(0.15))
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lb.add_theme_constant_override("outline_size", 8)
	lb.position = pos + Vector2(-40, -20)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(lb)
	g.floaters.append({"l": lb, "t": 0.0, "life": 0.9})

# ---------- мир: зал славы, цепочки, события ----------

func _on_net_events_result(result: Dictionary) -> void:
	if g._feed_list == null:
		return
	for child in g._feed_list.get_children():
		g._feed_list.remove_child(child)
		child.queue_free()
	if result.get("ok", false) != true:
		return
	var events: Array = result.get("events", [])
	print("NETEVENTS got=", events.size())
	if events.is_empty():
		var none := g._label("Пока тихо — стань первым первооткрывателем сегодня!", 12)
		none.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		g._feed_list.add_child(none)
		return
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var out_name := g._clean_str(d.get("out_name", "?"))
		var nick := g._clean_str(d.get("discoverer", "кто-то"))
		var a_name := g._clean_str(d.get("a_name", ""))
		var b_name := g._clean_str(d.get("b_name", ""))
		var ago := int(d.get("ago_sec", 0))
		var who := nick if nick != "" else "кто-то"
		var parts := "«%s» + «%s»" % [a_name, b_name]
		var txt := "%s открыл «%s» (%s) · %s" % [who, out_name, parts, _ago_text(ago)]
		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.05, 0.08, 0.11, 0.9)
		csb.set_corner_radius_all(10)
		csb.content_margin_left = 10
		csb.content_margin_right = 10
		csb.content_margin_top = 6
		csb.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", csb)
		g._feed_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		card.add_child(row)
		row.add_child(g._make_avatar(nick, 18))
		var lbl := g._label(txt, 12)
		lbl.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

func _on_net_challenge_result(result: Dictionary) -> void:
	if _challenge_label == null:
		return
	if result.get("ok", false) != true:
		_challenge_label.text = "Цель дня появится после связи с миром…"
		return
	var hint := g._clean_str(result.get("hint", ""))
	var first_nick := g._clean_str(result.get("first_nick", ""))
	var completions := int(result.get("completions", 0))
	var my_points := int(result.get("my_points", 0))
	if first_nick != "":
		_challenge_avatar.visible = true
		_challenge_avatar.setup(first_nick, 20)
		_challenge_label.text = "Цель дня: %s · выполнено: %d · первый: %s" % [hint, completions, first_nick]
	else:
		_challenge_avatar.visible = false
		_challenge_label.text = "Цель дня: %s · выполнено: %d · твои очки: %d" % [hint, completions, my_points]
	g._retention._circle_hint = hint
	g._retention._circle_mine = my_points
	g._retention._circle_pts_total = maxi(g._retention._circle_pts_total, int(result.get("my_points_total", g._retention._circle_pts_total)))
	g._retention._circle_check_pts_miles()
	g._saves._save_game()
	g._retention._refresh_circle_page()

func _ago_text(sec: int) -> String:
	if sec < 60:
		return "только что"
	if sec < 3600:
		return "%d мин назад" % (sec / 60)
	if sec < 86400:
		return "%d ч назад" % (sec / 3600)
	return "%d дн назад" % (sec / 86400)

func _on_net_hall_result(result: Dictionary) -> void:
	if _hall_list == null:
		return
	for child in _hall_list.get_children():
		_hall_list.remove_child(child)
		child.queue_free()
	if result.get("ok", false) != true:
		var off := g._label("Рейтинг доступен с сервером.", 13)
		off.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		_hall_list.add_child(off)
		return
	var hall: Array = result.get("hall", [])
	if hall.is_empty():
		var none := g._label("Пока нет первооткрывателей.", 13)
		none.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		_hall_list.add_child(none)
		return
	for e in hall:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var rank := int(d.get("rank", 0))
		var nick := g._clean_str(d.get("nick", "…"))
		var cnt := int(d.get("count", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var rk := g._label("%d." % rank, 14)
		rk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rk.custom_minimum_size = Vector2(26, 0)
		row.add_child(rk)
		row.add_child(g._make_avatar(nick, 20))
		var lb := g._label("%s — %d" % [nick, cnt], 14)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if rank == 1:
			lb.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		row.add_child(lb)
		_hall_list.add_child(row)

func _refresh_chains() -> void:
	if _chains_list == null:
		return
	for child in _chains_list.get_children():
		_chains_list.remove_child(child)
		child.queue_free()
	var depth := {"fire": 1, "water": 1, "earth": 1, "air": 1}
	var changed := true
	var guard := 0
	while changed and guard < 200:
		changed = false
		guard += 1
		for r in g.RECIPES:
			var a := String(r["a"])
			var b := String(r["b"])
			var o := String(r["out"])
			if not g._engine.known_recipes.has(g._pair_key(a, b)):
				continue
			var l := maxi(int(depth.get(a, 1)), int(depth.get(b, 1))) + 1
			if l > int(depth.get(o, 1)):
				depth[o] = l
				changed = true
	var opened: Array = []
	for item_id in g._engine.inventory:
		opened.append({"id": String(item_id), "d": int(depth.get(String(item_id), 1))})
	opened.sort_custom(func(x, y): return int(x["d"]) > int(y["d"]))
	var shown := 0
	for e in opened:
		if shown >= 5:
			break
		_chains_list.add_child(g._label("· %s — цепочка из %d звеньев" % [
			_item_name(String(e["id"])), int(e["d"])], 14))
		shown += 1
	if shown == 0:
		var none := g._label("Открой вещества — появятся твои цепочки.", 13)
		none.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		_chains_list.add_child(none)

func _random_opened_item() -> String:
	var pool: Array = []
	for item_id in g._engine.inventory:
		if not Game.BASE_IDS.has(String(item_id)):
			pool.append(String(item_id))
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])


func _build_event_qte() -> void:
	if _event_qte != null:
		return
	# Глобальный прозрачный слой: интерактивен только маленький пузырёк.
	# Он выше страниц/нижней панели, но ниже обычного discovery popup и магазина.
	_event_qte = Control.new()
	_event_qte.name = "WorldEventQTE"
	_event_qte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_event_qte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_qte.visible = false
	_event_qte.z_as_relative = false
	_event_qte.z_index = 12
	g.add_child(_event_qte)

	_event_card = PanelContainer.new()
	_event_card.name = "QTEBubble"
	_event_card.custom_minimum_size = Vector2(104, 112)
	_event_card.size = Vector2(104, 112)
	_event_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var bubble_panel := StyleBoxFlat.new()
	bubble_panel.bg_color = Color(0.06, 0.10, 0.17, 0.96)
	bubble_panel.border_color = Color(1.0, 0.78, 0.28, 0.95)
	bubble_panel.set_border_width_all(2)
	bubble_panel.set_corner_radius_all(52)
	bubble_panel.shadow_color = Color(0.95, 0.62, 0.18, 0.28)
	bubble_panel.shadow_size = 9
	_event_card.add_theme_stylebox_override("panel", bubble_panel)
	_event_qte.add_child(_event_card)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_card.add_child(col)

	_event_btn = Button.new()
	_event_btn.text = "☄"
	_event_btn.custom_minimum_size = Vector2(78, 70)
	_event_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_event_btn.add_theme_font_size_override("font_size", 30)
	_event_btn.focus_mode = Control.FOCUS_NONE
	_event_btn.tooltip_text = "Быстрая реакция: нажми на пузырёк"
	_event_btn.pressed.connect(_on_event_tap)
	var bubble_normal := StyleBoxFlat.new()
	bubble_normal.bg_color = Color(1.0, 0.62, 0.16, 0.98)
	bubble_normal.border_color = Color(1.0, 0.91, 0.47, 1.0)
	bubble_normal.set_border_width_all(2)
	bubble_normal.set_corner_radius_all(39)
	bubble_normal.shadow_color = Color(1.0, 0.68, 0.2, 0.38)
	bubble_normal.shadow_size = 7
	_event_btn.add_theme_stylebox_override("normal", bubble_normal)
	var bubble_hover := bubble_normal.duplicate() as StyleBoxFlat
	bubble_hover.bg_color = Color(1.0, 0.75, 0.28, 1.0)
	_event_btn.add_theme_stylebox_override("hover", bubble_hover)
	var bubble_pressed := bubble_normal.duplicate() as StyleBoxFlat
	bubble_pressed.bg_color = Color(0.88, 0.42, 0.10, 1.0)
	_event_btn.add_theme_stylebox_override("pressed", bubble_pressed)
	_event_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	col.add_child(_event_btn)

	_event_label = g._label("", 11)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.custom_minimum_size = Vector2(0, 15)
	_event_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	_event_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_event_label)

	_event_progress = ProgressBar.new()
	_event_progress.custom_minimum_size = Vector2(68, 4)
	_event_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_event_progress.max_value = Game.EVENT_WINDOW
	_event_progress.value = 0.0
	_event_progress.show_percentage = false
	_event_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var progress_bg := StyleBoxFlat.new()
	progress_bg.bg_color = Color(0.14, 0.19, 0.27, 0.95)
	progress_bg.set_corner_radius_all(2)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color(1.0, 0.72, 0.25, 0.98)
	progress_fill.set_corner_radius_all(2)
	_event_progress.add_theme_stylebox_override("background", progress_bg)
	_event_progress.add_theme_stylebox_override("fill", progress_fill)
	col.add_child(_event_progress)

func _place_event_qte() -> void:
	if _event_qte == null or _event_card == null:
		return
	var viewport_size := g.get_viewport().get_visible_rect().size
	var card_size := _event_card.size
	# Не прячем QTE под шапкой или BrewBar: случайность остаётся заметной
	# и доступной на portrait-экране, в том числе на Android.
	var left := 14.0
	var top := 174.0
	var max_x := maxf(left, viewport_size.x - card_size.x - 14.0)
	var max_y := maxf(top, viewport_size.y - card_size.y - 164.0)
	_event_card.position = Vector2(randf_range(left, max_x), randf_range(top, max_y))

func _event_tick(delta: float) -> void:
	if _event_active:
		_event_left -= delta
		if _event_left <= 0.0:
			_event_left = 0.0
			_event_active = false
			g._engine.status_text = "Событие упущено."
			g._engine._refresh()
			_update_event_ui()
		else:
			_event_t -= delta
			if _event_t <= 0.0:
				_event_t = 0.12
				_update_event_ui()
		return
	_event_clock += delta
	if _event_clock >= Game.EVENT_INTERVAL:
		_event_clock = 0.0
		_spawn_event()

func _spawn_event() -> void:
	_event_type = Game.EVENT_TYPES[randi() % Game.EVENT_TYPES.size()]
	_event_active = true
	_event_left = Game.EVENT_WINDOW
	_event_t = 0.0
	_place_event_qte()
	if _event_qte != null:
		_event_qte.visible = true
	g._engine.status_text = "☄ Событие: %s! Успей нажать всплывающее окно." % _event_name()
	Sfx.mystic()
	g._engine._refresh()
	_update_event_ui()

func _event_name() -> String:
	match _event_type:
		"comet":
			return "Кометный дождь · +25 эфира"
		"gift":
			return "Дар тумана · +1 вещество"
		"insight":
			return "Озарение · новый рецепт"
	return "Событие"

func _event_symbol() -> String:
	match _event_type:
		"comet":
			return "☄"
		"gift":
			return "✦"
		"insight":
			return "✧"
	return "!"

func _update_event_ui() -> void:
	if _event_qte == null or _event_btn == null:
		return
	if _event_active:
		_event_qte.visible = true
		_event_btn.disabled = false
		_event_btn.text = _event_symbol()
		_event_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		if _event_label != null:
			_event_label.text = "%d с" % maxi(1, ceili(_event_left))
		if _event_progress != null:
			_event_progress.value = _event_left
	else:
		_event_qte.visible = false
		_event_btn.disabled = true
		if _event_progress != null:
			_event_progress.value = 0.0

func _on_event_tap() -> void:
	if not _event_active:
		return
	var reward_pos := _event_btn.get_global_rect().get_center()
	_event_active = false
	_event_clock = 0.0
	_update_event_ui()
	match _event_type:
		"comet":
			# Полный грант 25: сверх кэпа уходит в ether_overflow (резерв),
			# а не теряется.
			g._engine._grant_ether(25, "comet")
			g._engine.status_text = "☄ Комета! +25 эфира."
			_floater_at(reward_pos, "+25 ⚡", Color(1.0, 0.9, 0.4))
		"gift":
			var pick := _random_opened_item()
			if pick != "":
				g._engine.inventory[pick] = int(g._engine.inventory.get(pick, 0)) + 1
				g._engine.status_text = "☄ Дар тумана: %s +1." % _item_name(pick)
				_floater_at(reward_pos, "+%s" % _item_name(pick),
					g._item_colors.get(pick, Color.WHITE))
			else:
				g._engine.status_text = "☄ Дар тумана: пока нечего дарить."
		"insight":
			var cand := g._pages._unrevealed_recipe_candidates()
			if not cand.is_empty():
				var r: Dictionary = cand[randi() % cand.size()]
				var ra := String(r["a"])
				var rb := String(r["b"])
				var rout := String(r["out"])
				g._engine.known_recipes[g._pair_key(ra, rb)] = true
				g._engine.status_text = "☄ Озарение: %s + %s → %s!" % [_item_name(ra), _item_name(rb), _item_name(rout)]
				g._present_popup(rout, "Озарение открыло рецепт:\n%s + %s → %s" % [
					_item_name(ra), _item_name(rb), _item_name(rout)])
			else:
				g._engine.status_text = "☄ Озарение: все пары из известных веществ открыты."
	Sfx.divide()
	g._engine._refresh()
	_update_event_ui()
	g._saves._save_game()

