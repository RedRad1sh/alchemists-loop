extends RefCounted
class_name TradeUI
# S2 «Обмен картами»: подслой обмена внутри экрана «Друзья». Три состояния —
# список (этот таск), конструктор и подтверждение (Task 9), действия по офферам
# и их последствия (Task 10). Сеть — только через Net-сигналы, которые
# маршрутизирует main.gd; представление не считает недельный лимит само и не
# заводит свою коллекцию карт (спека §8.4).

const TITLE := "Обмен"

## Зеркало серверного env ALCHEMY_TRADE_SIDE_MAX (спека §3): лимит ячеек на
## сторону. Источник истины — сервер; клиентский гейт только UX, чтобы игрок не
## собирал заведомо отклоняемый оффер.
const TRADE_SIDE_MAX := 6

var g: Game
var _screen: Control = null
var _body: VBoxContainer = null
var _header: Label = null
var _incoming: VBoxContainer = null
var _outgoing: VBoxContainer = null
var _history: VBoxContainer = null
var _peer := ""
var _mode := 0
var _list := {}
var _offer := {"give": [], "want": [], "gift": false}   # N↔M: стороны — списки ячеек
var _picking := ""          # "give" | "want" | "" — идёт ли выбор карты
var _note := ""             # строка серверного отказа (код → текст через _detail_text)
var _gone := {}               # id входящих офферов с ушедшей картой (§7.2)
var _last_id := -1            # id заказа, чей отказ рисовать на строке
var _peer_coll := {}          # кэш peer_collection друга (§2.2): {cards, extras}

func _init(game: Game) -> void:
	g = game

func is_open() -> bool:
	return _screen != null and _screen.visible

func open(peer: String) -> void:
	if _screen == null:
		build()
	_peer = peer
	_mode = 0
	_offer = {"give": [], "want": [], "gift": false}
	_picking = ""
	_note = ""
	# Отметка «карты больше нет» привязана к офферу конкретного собеседника:
	# у нового peer'а чужая мёртвая строка не имеет права пережить смену окна.
	_gone = {}
	_screen.visible = true
	Net.trade_list(g._online._device_id)
	_render()

func close() -> void:
	var was := is_open()
	_peer = ""
	if _screen != null:
		_screen.visible = false
	# Звук — только на закрытие видимого слоя: SocialUI дёргает _trade_close() и
	# при open(), и при close(), поэтому без гейда каждый вход в «Друзья» после
	# первого обмена давал бы фантомный клик при уже погашенном слое.
	if was:
		Sfx.click()

func on_list(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	_list = result
	_render()

## Контракт выбранной карты — спека §8.3: четыре поля, ни одним больше.
## card_id пуст => это экземпляр (хроматик) по craft_id, и он всегда последний.
func pick(card_id: String, craft_id: String, copies: int,
		display_name: String) -> Dictionary:
	return {"card_id": card_id, "craft_id": craft_id,
		"is_last": craft_id != "" or copies <= 1,
		"display_name": display_name}

## Всё, что можно отдать прямо сейчас: виды карт из серверной коллекции и
## внекомплектные экземпляры. Локальная коллекция (sigil_crafts на клиенте)
## для этого не заводится (§8.4) — источник один: кэш /api/sigil/collection.
func entries() -> Array:
	var out: Array = []
	var coll: Dictionary = g._sigil.server_collection()
	for cid in coll:
		var copies := int((coll[cid] as Dictionary).get("copies", 0))
		if copies <= 0:
			continue
		var nm := str(g._sigil.card(str(cid)).get("fallback_name", cid))
		# Пустое значение отличается от отсутствующего ключа: у вида без имени
		# fallback_name приходит как "" (server.py:1097), и get(... , cid) вернёт
		# именно "". Без фолбэка кнопка пикера рисуется безымянной — «— последняя»
		# вместо названия, и опознать карту нельзя.
		if nm == "":
			nm = str(cid)
		out.append(pick(str(cid), "", copies, nm))
	for x in g._sigil.server_extras():
		if not (x is Dictionary):
			continue
		var craft := str((x as Dictionary).get("craft_id", ""))
		if craft == "":
			continue
		var nm := str((x as Dictionary).get("llm_name", ""))
		if nm == "":
			nm = "Внекомплектная"
		out.append(pick("", craft, 1, nm))
	return out

## Число копий вида, доступное стороне. give — своя серверная коллекция; want —
## коллекция друга из _peer_coll. Отрицательный ответ означает «источник
## недоступен» (want без peer_coll: офлайн/ещё не запрошен) — тогда гейт
## best-effort не блокирует ячейку: источник истины сервер (§3, он ответит 409
## peer_lacks), а блокировка сделала бы сборку оффера невозможной офлайн.
func _copies_for(side: String, cid: String) -> int:
	if side == "want":
		if _peer_coll.is_empty():
			return -1
		var cards: Dictionary = _peer_coll.get("cards", {})
		if not cards.has(cid):
			return 0
		return int((cards[cid] as Dictionary).get("copies", 0))
	var coll: Dictionary = g._sigil.server_collection()
	if not coll.has(cid):
		return 0
	return int((coll[cid] as Dictionary).get("copies", 0))

## Кладёт выбранную карту в следующий свободный слот стороны. Отказ (false) —
## лимит стороны (TRADE_SIDE_MAX) либо дефицит копий: экземпляр хроматика
## уникален (одна ячейка на craft_id), вид занят ячейками не больше копий (§3).
func add_slot(side: String, entry: Dictionary) -> bool:
	if not _offer.has(side):
		return false
	var arr: Array = _offer[side]
	if arr.size() >= TRADE_SIDE_MAX:
		return false
	var cid := String(entry.get("card_id", ""))
	var craft := String(entry.get("craft_id", ""))
	# Хроматик — один экземпляр: вторая ячейка того же craft_id запрещена.
	if craft != "":
		for e in arr:
			if String((e as Dictionary).get("craft_id", "")) == craft:
				return false
		arr.append(entry)
		return true
	# Вид: сумма занятых ячеек не больше копий в источнике стороны.
	var used := 0
	for e in arr:
		if String((e as Dictionary).get("card_id", "")) == cid:
			used += 1
	var have := _copies_for(side, cid)
	if have >= 0 and used >= have:
		return false
	arr.append(entry)
	return true

## Снимает ячейку с позиции pos. pos вне диапазона — бездействие (кнопка
## «убрать» на пустой стороне недостижима, но защита от случайного индекса нужна).
func remove_slot(side: String, pos: int) -> void:
	if not _offer.has(side):
		return
	var arr: Array = _offer[side]
	if pos < 0 or pos >= arr.size():
		return
	arr.remove_at(pos)

## Всё, что можно попросить у друга прямо сейчас: позиции из кэша peer_collection
## (спека §4.1 — want берётся из чужой коллекции, а не из своей). При пустом
## кэше — пусто; панель «Прошу» недоступна, пока ответ не пришёл.
func peer_entries() -> Array:
	var out: Array = []
	if _peer_coll.is_empty():
		return out
	var cards: Dictionary = _peer_coll.get("cards", {})
	for cid in cards:
		var copies := int((cards[cid] as Dictionary).get("copies", 0))
		if copies <= 0:
			continue
		var nm := str(g._sigil.card(str(cid)).get("fallback_name", cid))
		if nm == "":
			nm = str(cid)
		out.append(pick(str(cid), "", copies, nm))
	for x in _peer_coll.get("extras", []):
		if not (x is Dictionary):
			continue
		var craft := str((x as Dictionary).get("craft_id", ""))
		if craft == "":
			continue
		var nm := str((x as Dictionary).get("llm_name", ""))
		if nm == "":
			nm = "Внекомплектная"
		out.append(pick("", craft, 1, nm))
	return out

## Кэш ответа GET /api/trade/peer_collection: {cards, extras} (§2.2).
func set_peer_coll(coll: Dictionary) -> void:
	_peer_coll = coll

func can_confirm() -> bool:
	var give: Array = _offer["give"]
	var want: Array = _offer["want"]
	return give.size() >= 1 and (bool(_offer["gift"]) or want.size() >= 1)

func open_builder() -> void:
	_picking = ""
	_note = ""
	_mode = 1
	_render()

func open_confirm() -> void:
	if not can_confirm():
		_note = "Выбери карту"
		_mode = 1
		_render()
		return
	_note = ""        # прошлый отказ нельзя приносить на новое подтверждение
	_mode = 2
	_render()

func on_offer(result: Dictionary) -> void:
	_on_write_result(result, true)

func on_gift(result: Dictionary) -> void:
	_on_write_result(result, false)

func _on_write_result(result: Dictionary, is_offer: bool) -> void:
	if result.get("ok", false) == true:
		_offer = {"give": [], "want": [], "gift": false}
		_picking = ""
		_note = ""
		# Оба успеха уходят на список. Оставленный экран подтверждения рисует
		# «Ты отдаёшь: » с пустым именем и живой кнопкой, нажатие которой шлёт
		# пустые селекторы (422 bad_selector), а подтверждения игроку неоткуда.
		_mode = 0
		if is_offer:
			Net.trade_list(g._online._device_id)   # re-pull списка офферов
		_render()
		return
	_note = _refusal_text(result)
	_render()

## Коды сервера (§7) → текст. Единая таблица на весь слой: отказ offer и отказ
## accept/cancel/gift обязаны звучать одинаково, иначе игрок решит, что это
## разные механизмы.
static func _detail_text(code: String) -> String:
	match code:
		# Код поднимается по обеим сторонам сделки (server.py:5578-5579 — и
		# `_trade_registered(conn, me)`, и `(conn, to)`), поэтому копия не должна
		# указывать на отправителя: «заведись» от пропавшего собеседника звучит как
		# обвинение игрока. Формулировка совпадает с social_ui.gd:139 для того же
		# кода.
		"not_registered": return "Профиль ещё не зарегистрирован."
		"not_friends": return "Меняться можно только с друзьями"
		"not_found": return "Такого обмена уже нет"
		"not_pending": return "Этот обмен уже закрыт"
		"not_maker": return "Отменить оффер может только тот, кто его предложил"
		"too_many_open": return "Слишком много висящих предложений — закрой часть"
		"week_limit": return "Недельный лимит исчерпан — сброс в понедельник"
		"expired": return "Предложение просрочилось: ему больше недели"
		"card_not_owned": return "Этой карты у тебя уже нет"
		"unknown_card": return "Такую карту мир не знает"
		"bad_selector": return "Нужно выбрать ровно одну карту"
		"self_deal": return "Себе менять нельзя"
		# Голый card_gone отдаёт только gift (server.py:5805 и :5810): целевой
		# craft_id уже занят у получателя, либо строка ушла из-под нас.
		"card_gone": return "Подарок не дошёл: карта ушла или такая же уже у него"
		"card_gone:maker": return "У предложившего карты больше нет"
		"card_gone:taker": return "У тебя больше нет карты для обмена"
		_: return "Мир не понял запрос"

## Копия отказа для всех четырёх действий слоя. Офлайн обязан быть отдельной
## веткой: у Net-слива нет ключа detail (net.gd:454), поэтому без неё запрос,
## который никуда не ушёл, читается как сбой мира. Текст совпадает с
## social_ui.gd:141 для того же состояния.
static func _refusal_text(result: Dictionary) -> String:
	if result.get("offline", false) == true:
		return "Мир не на связи"
	return _detail_text(String(result.get("detail", "")))

## День недели Грегориана, 0=воскресенье … 1=понедельник … 6=суббота
## (алгоритм Sakamoto). У Time.get_datetime_dict_* поля weekday нет, поэтому
## считать самому — и ровно здесь, а не в каждом лейбле.
static func _weekday(y: int, m: int, d: int) -> int:
	var t := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	if m < 3:
		y -= 1
	return int((y + int(y / 4.0) - int(y / 100.0) + int(y / 400.0) + t[m - 1] + d) % 7)

## Ближайший понедельник 00:00 после today — день сброса недельного лимита
## (спека §7.2: «следующий понедельник, локальное время клиента»; серверную
## ISO-неделю на клиента не переносим). Полдень как опора, чтобы переход
## летнего времени не сдвинул дату. Метод экземпляра, а не `static`: сьют
## зовёт его через `tu = T.new(g)` и не ссылается на `class_name TradeUI`.
## Sakamoto даёт 0=воскресенье, 1=понедельник, поэтому до понедельника
## остаётся `(8 - wd) % 7` дней, а не `(7 - wd) % 7` — второй вариант на
## среде (wd=3) даёт воскресенье 25.10 вместо 26.10, а в понедельник и
## вовсе ноль, то есть «сегодня».
func reset_day(today: String) -> String:
	if today.length() < 10:
		return ""
	var y := int(today.substr(0, 4))
	var m := int(today.substr(5, 2))
	var d := int(today.substr(8, 2))
	if y < 2000 or m < 1 or m > 12 or d < 1 or d > 31:
		return ""
	var delta := (8 - _weekday(y, m, d)) % 7
	if delta == 0:
		delta = 7
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0})
	var out := Time.get_datetime_dict_from_unix_time(int(unix) + delta * 86400)
	return "%04d-%02d-%02d" % [int(out["year"]), int(out["month"]), int(out["day"])]

## Та же дата для человека: 2026-10-26 -> «26.10».
func reset_day_label(today: String) -> String:
	var iso := reset_day(today)
	if iso == "":
		return ""
	return iso.substr(8, 2) + "." + iso.substr(5, 2)

func build() -> void:
	if _screen != null:
		return
	var root := Control.new()
	root.name = "TradeScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	# z = 21 и группа modal_ui — ровно как у `_confirm` в `_open_confirm`
	# (спека §8.2): слой перекрывает SocialUI (z = 20) и попадает в общий
	# предикат модалок.
	root.z_index = 21
	root.add_to_group("modal_ui")
	g._social_ui._screen.add_child(root)
	_screen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_header = g._label(TITLE, 17)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_header)
	var back := g._small_button("Назад", Vector2(84, 34), 0)
	back.pressed.connect(close)
	head.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

func _section(title: String) -> VBoxContainer:
	var t := g._label(title, 13)
	t.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_body.add_child(t)
	var body := VBoxContainer.new()
	body.name = title
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(body)
	return body

func _clear(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _render() -> void:
	if _screen == null or _body == null:
		return
	match _mode:
		1:
			_render_builder()
		2:
			_render_confirm()
		3:
			_render_builder()
		_:
			_render_list()

func _render_list() -> void:
	_clear(_body)
	_header.text = "%s · %s" % [TITLE, _nick()]
	var at_zero := false
	if _list.has("remain"):
		var remain := int(_list.get("remain", 0))
		var limit := int(_list.get("week_limit", 0))
		var line := "Обменов на этой неделе: %d из %d" % [limit - remain, limit]
		if remain <= 0:
			line += " · сброс " + reset_day_label(Time.get_date_string_from_system())
			at_zero = true
		var sub := g._label(line, 12)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		_body.add_child(sub)
	var new_btn := g._small_button("Предложить обмен", Vector2(180, 40), 0)
	# Спека §9.2: при remain == 0 кнопка «Предложить» неактивна. Держать её живой
	# и глушить только «Дальше» — значит водить игрока в конструктор-тупик.
	new_btn.disabled = at_zero
	new_btn.pressed.connect(open_builder)
	_body.add_child(new_btn)
	if _note != "":
		var note := g._label(_note, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(note)
	_incoming = _section("Мне предлагают")
	_outgoing = _section("Я предложил")
	_history = _section("История")
	for o in _list.get("incoming", []):
		_offer_row(_incoming, o, 0)
	for o in _list.get("outgoing", []):
		_offer_row(_outgoing, o, 1)
	for o in _list.get("history", []):
		_offer_row(_history, o, 2)
	if _list.is_empty():
		for box in [_incoming, _outgoing, _history]:
			var wait := g._label("—", 12)
			wait.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
			box.add_child(wait)

## Имя карты для строки и слота: сервер подписывает только экземплярные сделки
## (`*_craft_id` непустой), для карт вида имя берётся из каталога — конкретный
## экземпляр при этом не обещан и не записан (раллинг 8 плана).
func _title(card_id: String, craft_id: String, server_name: String) -> String:
	if server_name != "":
		return server_name
	if craft_id != "":
		return "Внекомплектная"
	if card_id == "":
		return "—"
	var nm := str(g._sigil.card(card_id).get("fallback_name", card_id))
	return nm

## kind: 0 = входящий (могу принять), 1 = исходящий (могу отменить),
## 2 = история (без действий).
func _offer_row(box: VBoxContainer, raw, kind: int) -> void:
	if not (raw is Dictionary):
		return
	var o: Dictionary = raw
	var id := int(o.get("id", 0))
	var give := _title(String(o.get("give_card_id", "")),
		String(o.get("give_craft_id", "")), String(o.get("give_name", "")))
	var want := _title(String(o.get("want_card_id", "")),
		String(o.get("want_craft_id", "")), String(o.get("want_name", "")))
	var text := give
	if want == "—":
		text = "Подарок: " + give            # односторонняя передача: want_* пустые
	else:
		text = give + " → " + want
	var row := HBoxContainer.new()
	row.name = "TradeRow_%d" % id
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 44)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(g._label(text, 13))
	var who := String(o.get("maker_nick", ""))
	if kind == 1:
		who = String(o.get("taker_nick", ""))
	if who != "":
		var dim := g._label(who, 11)
		dim.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		info.add_child(dim)
	row.add_child(info)
	box.add_child(row)
	if kind == 0:
		# Отдельной кнопки «Отклонить» нет: у не-автора cancel отвечает 409
		# not_maker, а отказ по модели встречного оффера — это бездействие или
		# новый оффер (спека §4, §7).
		if _gone.has(id):
			# §7.2 — «спокойное состояние карточки оффера»: строка остаётся на
			# месте (оффер висит pending, пока его не закрыли), мёртвая ручка с
			# неё снимается, копия берётся дословно из спеки.
			var dead := g._label("карты больше нет — предложи другую", 11)
			dead.add_theme_color_override("font_color", Color("#e6a84a"))
			info.add_child(dead)
		else:
			var yes := g._small_button("Принять", Vector2(96, 34), 0)
			yes.pressed.connect(_accept.bind(id))
			row.add_child(yes)
	elif kind == 1:
		var no := g._small_button("Отменить", Vector2(110, 34), 0)
		no.pressed.connect(_cancel.bind(id))
		row.add_child(no)

func _accept(id: int) -> void:
	_last_id = id           # отказ приходит без id, строку надо опознать
	Net.trade_accept(g._online._device_id, id)

func _cancel(id: int) -> void:
	Net.trade_cancel(g._online._device_id, id)

func on_accept(result: Dictionary) -> void:
	if result.get("ok", false) == true:
		_note = ""
		_list = {}
		_mode = 0
		_gone = {}
		Net.trade_list(g._online._device_id)
		_render()
		return
	var code := String(result.get("detail", ""))
	# card_gone — штатный ответ модели «без блокировки карт» (спека §7.2). Так
	# проверяются обе стороны сделки (server.py:5663-5670: give у maker и want у
	# taker), и оба кода значат одно: принять эту сделку уже нельзя. Значит
	# состояние надевается на строку, а не только на строку отказа сверху.
	if code == "card_gone:maker" or code == "card_gone:taker":
		_gone[_last_id] = true
	_note = _refusal_text(result)
	_render()

func on_cancel(result: Dictionary) -> void:
	if result.get("ok", false) == true:
		_note = ""
		_list = {}        # симметрия с on_accept: без re-render'а отменённая
		_mode = 0         # строка висела бы до ответа trade_list
		Net.trade_list(g._online._device_id)
		_render()
		return
	_note = _refusal_text(result)
	_render()

func _slot_text(e) -> String:
	if not (e is Dictionary) or (e as Dictionary).is_empty():
		return "не выбрана"
	return String((e as Dictionary).get("display_name", ""))

## Подпись slot-кнопки стороны-списка (R14): имя ПЕРВОЙ ячейки, «не выбрана» для
## пустой стороны, «<имя> +N» если ячеек больше одной. Визуал конструктора —
## Task 8; здесь прежняя одна кнопка на сторону с прежним name и press.
func _side_label(side) -> String:
	if not (side is Array) or (side as Array).is_empty():
		return "не выбрана"
	var arr: Array = side
	var first := String((arr[0] as Dictionary).get("display_name", ""))
	if arr.size() == 1:
		return first
	return "%s +%d" % [first, arr.size() - 1]

func _render_builder() -> void:
	_clear(_body)
	_header.text = "%s · %s" % [TITLE, _nick()]
	_body.add_child(g._label("Что отдаю", 13))
	var give := g._small_button(_side_label(_offer["give"]), Vector2(260, 40), 0)
	give.name = "GiveSlot"
	give.pressed.connect(_pick_for.bind("give"))
	_body.add_child(give)
	_body.add_child(g._label("Что прошу взамен", 13))
	var want := g._small_button(_side_label(_offer["want"]), Vector2(260, 40), 0)
	want.name = "WantSlot"
	want.disabled = bool(_offer["gift"])     # подарок = односторонняя передача
	want.pressed.connect(_pick_for.bind("want"))
	_body.add_child(want)
	var gift_btn := g._small_button(
		"Подарить" if not bool(_offer["gift"]) else "Подарок: да", Vector2(140, 34), 0)
	gift_btn.pressed.connect(_toggle_gift)
	_body.add_child(gift_btn)
	if _note != "":
		var note := g._label(_note, 12)
		note.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(note)
	if _picking != "":
		_body.add_child(g._label("Выбери карту", 13))
		for e in entries():
			var nm := String(e["display_name"])
			if bool(e["is_last"]):
				nm += " — последняя"
			var b := g._small_button(nm, Vector2(260, 40), 0)
			b.pressed.connect(_choose.bind(e))
			_body.add_child(b)
		var cancel := g._small_button("Отменить выбор", Vector2(150, 34), 0)
		cancel.pressed.connect(_stop_picking)
		_body.add_child(cancel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	var next := g._small_button("Дальше", Vector2(120, 40), 0)
	next.disabled = (not can_confirm()) or int(_list.get("remain", 1)) <= 0
	next.pressed.connect(open_confirm)
	row.add_child(next)
	var back := g._small_button("Назад", Vector2(96, 34), 0)
	back.pressed.connect(_back_to_list)
	row.add_child(back)

func _toggle_gift() -> void:
	_offer["gift"] = not bool(_offer["gift"])
	if bool(_offer["gift"]):
		_offer["want"] = []
	_render()

func _pick_for(slot: String) -> void:
	_picking = slot
	_mode = 3
	_render()

func _stop_picking() -> void:
	_picking = ""
	_mode = 1
	_render()

func _choose(e: Dictionary) -> void:
	# Пикер (остаётся до Task 8, раллинг R13) кладёт карту через add_slot — тот же
	# путь, что и будущий клик по сетке: гейты лимита стороны и копий применяются
	# к реальному выбору игрока, а не обходятся прямой записью в ячейку.
	if _picking == "give" or _picking == "want":
		add_slot(_picking, e)
	_picking = ""
	_mode = 1
	_note = ""
	_render()

func _back_to_list() -> void:
	_picking = ""
	_mode = 0
	_render()

func _render_confirm() -> void:
	_clear(_body)
	_header.text = "%s · %s" % [TITLE, _nick()]
	var give: Array = _offer["give"]
	var want: Array = _offer["want"]
	_body.add_child(g._label("Ты отдаёшь: %s" % _side_names(give), 14))
	if bool(_offer["gift"]):
		_body.add_child(g._label("Подарок (%s): без встречной карты" % _nick(), 13))
	else:
		_body.add_child(g._label("Ты получаешь: %s" % _side_names(want), 14))
	# Предупреждение — только про отдаваемые карты (спека §5.3): сервер такую
	# сделку не блокирует, поэтому название последствия обязано быть на экране.
	# И только по give: want собирается из коллекции друга (§4.1), поэтому
	# «последняя копия» на его стороне описывает карту, которую просят у него, а
	# не ту, что теряю я — игрок читал бы неправду про своё необратимое последствие.
	var any_last := false
	for e in give:
		if bool((e as Dictionary).get("is_last", false)):
			any_last = true
	if any_last:
		var warn := g._label(
			"Это твоя последняя копия вида. Отдав её, теряешь карту из "
			+ "коллекции: прогресс достижений по сигилам и невыбранные вехи "
			+ "комплекта пересчитываются по тому, что осталось.", 13)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(warn)
	if _note != "":
		var note := g._label(_note, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	var go := g._small_button("Подарить" if bool(_offer["gift"]) else "Предложить",
		Vector2(150, 40), 0)
	go.pressed.connect(_send)
	row.add_child(go)
	var edit := g._small_button("Изменить", Vector2(110, 34), 0)
	edit.pressed.connect(open_builder)
	row.add_child(edit)

func _send() -> void:
	var dev := g._online._device_id
	# Контракт N↔M: на сетку уезжают РОВНО {card_id, craft_id} (спека §2.2).
	# is_last/display_name — клиентский UX-слой, сервер их не ждёт. Новый массив
	# строится заново, поэтому долговременный _offer не попадает в очередь Net по
	# ссылке (закрытие hazard Task 5 «Net кладёт массив в очередь по ссылке»).
	var give := _wire_items(_offer["give"])
	if bool(_offer["gift"]):
		Net.trade_gift(dev, _peer, give)
		return
	Net.trade_offer(dev, _peer, give, _wire_items(_offer["want"]))

## Позиции стороны в формат отправки: список словарей {card_id, craft_id}.
static func _wire_items(side) -> Array:
	var out: Array = []
	if not (side is Array):
		return out
	for e in side:
		out.append({"card_id": String((e as Dictionary).get("card_id", "")),
			"craft_id": String((e as Dictionary).get("craft_id", ""))})
	return out

## Человекочитаемая подпись стороны для экрана подтверждения: имена ячеек через
## запятую. Только для отрисовки текста — на сетку не уезжает (_wire_items).
func _side_names(side) -> String:
	if not (side is Array):
		return ""
	var parts: Array = []
	for e in side:
		parts.append(String((e as Dictionary).get("display_name", "")))
	return ", ".join(PackedStringArray(parts))

func _nick() -> String:
	var friend := g._social.friend_by_device(_peer)
	if friend.is_empty():
		return "Алхимик"
	return String(friend.get("nick", "Алхимик"))
