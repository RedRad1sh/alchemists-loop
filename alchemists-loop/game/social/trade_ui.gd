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

## Комплект окна обмена (спека §5): планшет, карман и сургуч — из assets/trades/,
## доски, рейка, уголок, заклёпка и бумага кнопок переиспользуются из
## assets/contracts/. Никаких ColorRect и плоских StyleBoxFlat в видимом слое.
const TRADE_DIR := "res://assets/trades/"
const BOARD_DIR := "res://assets/contracts/"
const FADE_SHADER := "res://assets/contracts/paper_fade.gdshader"

const PANE := Vector2(252, 316)      # два планшета рядом: 2×252 + 8 ≤ 516
const PANE_PAD := 6.0
const CELL := Vector2(76, 96)        # pocket 80×100 логических, минус поле
const ART := 60.0
const SEAL := 60.0
const GRID_COLS := 3
const GRID_GAP := 6.0               # 3×76 + 2×6 = 240 = 252 − 2×6
const SLOT_GAP := 4.0               # 6×76 + 5×4 = 476 ≤ 516
const SHEET := Vector2(112, 76)
const CAP := Vector2(56, 56)
const NAIL := Vector2(48, 48)
const FOOT_H := 80.0
const HEAD_H := 52.0
## Два градуса затемнения, а не один: 0.55 — «копии кончились / нельзя положить»,
## 0.62 — «целика недоступна» (офлайн-планшет друга, locked кнопка, подарок).
const FADE_SPENT := 0.55
const FADE_OUT := 0.62
const PAPER_INK := Color(0.16, 0.11, 0.07)
const BOARD_INK := Color(0.93, 0.86, 0.70)
const AMBER := Color("#e6a84a")
const TILT_MAX := 1.2

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
var _note := ""             # строка серверного отказа (код → текст через _detail_text)
var _gone := {}               # id входящих офферов с ушедшей картой (§7.2)
var _last_id := -1            # id заказа, чей отказ рисовать на строке
var _peer_coll := {}          # кэш peer_collection друга (§2.2): {cards, extras}
## amount -> ShaderMaterial. Один материал на все затемнённые узлы перерисовки:
## на каждом кадре конструктора плодить ShaderMaterial под каждый карман —
## утечка GPU-памяти на слое, который игрок открывает десятки раз за заход.
var _fade_cache := {}
## Поколение перерисовки: недочитанные миниатюры прошлой сборки не имеют права
## лечь на уже освобождённый карман (тот же приём, что `_sigil_tab_seq`).
var _art_seq := 0

func _init(game: Game) -> void:
	g = game

static func tex(fname: String) -> Texture2D:
	return load(TRADE_DIR + fname) as Texture2D

static func board_tex(fname: String) -> Texture2D:
	return load(BOARD_DIR + fname) as Texture2D

## Наклон планшета задан от peer, а не `randf()` (спека §5): два захода в окно
## к одному другу обязаны рисовать одинаковую раскладку. FNV-1a, а не
## `String.hash()` — тот же приём, что у ContractCard.rot_deg: хеш строк у
## движка меняется между сборками, а доски — нет.
static func _tilt(seed_str: String) -> float:
	var h := 2166136261
	for byte in seed_str.to_utf8_buffer():
		h = ((h ^ int(byte)) * 16777619) & 0x7FFFFFFF
	return TILT_MAX * (2.0 * float(h % 1001) / 1000.0 - 1.0)

## Материал затемнения по силе. Кэшируется: узел с тем же amount получает тот же
## ShaderMaterial, поэтому перерисовка конструктора не создаёт новый материал на
## каждый карман.
func _fade_mat(amount: float) -> ShaderMaterial:
	var key := int(amount * 100.0)
	var cached: ShaderMaterial = _fade_cache.get(key) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = load(FADE_SHADER) as Shader
	m.set_shader_parameter("amount", amount)
	_fade_cache[key] = m
	return m

## Fade надевается на каждый рисуемый узел ветки, а не только на подложку: Godot не
## наследует `material` детям, поэтому миниатюра в недоступном кармане осталась бы
## яркой цветной картинкой поверх «серой» ячейки.
func _fade_tree(node: Node, mat: ShaderMaterial) -> void:
	if node is CanvasItem:
		(node as CanvasItem).material = mat
	for c in node.get_children():
		_fade_tree(c, mat)

func is_open() -> bool:
	return _screen != null and _screen.visible

func open(peer: String) -> void:
	if _screen == null:
		build()
	_peer = peer
	_mode = 0
	_offer = {"give": [], "want": [], "gift": false}
	_note = ""
	# Коллекция друга привязана к peer: оставить её между заходами значило бы
	# предлагать «Прошу: <карта Николя>» собеседнику, у которого её нет.
	_peer_coll = {}
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

## Единственный предикат доступности ячейки: по нему кладётся карта, по нему же
## рисуются `disabled` и fade кармана. Если бы гейты жили в двух местах, «серый»
## и «некликабельный» разъехались бы, а игрок кликал бы по карману, который
## прикидывается живым.
func can_add(side: String, entry: Dictionary) -> bool:
	if not _offer.has(side):
		return false
	var arr: Array = _offer[side]
	if arr.size() >= TRADE_SIDE_MAX:
		return false
	# Подарок — односторонняя передача: встречную карту просить не у кого (§4.1).
	if side == "want" and bool(_offer["gift"]):
		return false
	var cid := String(entry.get("card_id", ""))
	var craft := String(entry.get("craft_id", ""))
	# Хроматик — один экземпляр: вторая ячейка того же craft_id запрещена.
	if craft != "":
		for e in arr:
			if String((e as Dictionary).get("craft_id", "")) == craft:
				return false
		return true
	# Вид: сумма занятых ячеек не больше копий в источнике стороны.
	var used := 0
	for e in arr:
		if String((e as Dictionary).get("card_id", "")) == cid:
			used += 1
	var have := _copies_for(side, cid)
	return not (have >= 0 and used >= have)

## Кладёт выбранную карту в следующий свободный слот стороны. Отказ (false) —
## лимит стороны (TRADE_SIDE_MAX), подарок с пустым «Прошу», дефицит копий или
## уже занятый экземпляр: всё это считает can_add.
func add_slot(side: String, entry: Dictionary) -> bool:
	if not can_add(side, entry):
		return false
	var arr: Array = _offer[side]
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

## Ответ коллекции друга по проводам main.gd (не присваивание из тестов):
## panel «Прошу» строится только из него. Пустой/не-ok ответ оставляет прошлый
## кэш как есть — §4.4 рисует по нему «Мир не на связи», а не вымышленную
## пустую коллекцию друга.
func on_peer_collection(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	_peer_coll = {"cards": result.get("cards", {}), "extras": result.get("extras", [])}
	# Перерисовка только на конструкторе: на списке и подтверждении планшета нет,
	# а сброс невысказанного экрана посреди чтения оффера — худшее, что можно
	# сделать с интерфейсом.
	if _mode == 1:
		_render()

func can_confirm() -> bool:
	var give: Array = _offer["give"]
	var want: Array = _offer["want"]
	return give.size() >= 1 and (bool(_offer["gift"]) or want.size() >= 1)

func open_builder() -> void:
	_note = ""
	_mode = 1
	_render()
	# §4.1: панель друга — часть конструктора, поэтому её тянет сам
	# конструктор. Ждать, пока игрок «сам куда-то нажмёт», нечего: без ответа
	# сторона «Прошу» остаётся затемнённой (§4.4).
	Net.trade_peer_collection(g._online._device_id, _peer)

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

	# Затемнение — тёмная ткань тайлом на весь экран: ColorRect-заливка (§5 и
	# AGENTS.md §27) читалась бы как чёрный прямоугольник поверх игры, а не как
	# сукно, на котором лежит окно.
	var dim := TextureRect.new()
	dim.name = "Dim"
	dim.texture = tex("cloth_dark.png")
	dim.stretch_mode = TextureRect.STRETCH_TILE
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

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	# Шапка — рейка досок с гвоздём вместо кнопки «Назад»: закрытие окна должно
	# быть частью рамы, а не подписью под ней.
	var head := MarginContainer.new()
	head.name = "Head"
	head.custom_minimum_size = Vector2(0, HEAD_H)
	box.add_child(head)
	var head_plate := TextureRect.new()
	head_plate.name = "Plate"
	head_plate.texture = board_tex("board_planks.png")
	head_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head_plate.stretch_mode = TextureRect.STRETCH_SCALE
	head_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_plate)
	var head_row := HBoxContainer.new()
	head_row.name = "Row"
	head_row.add_theme_constant_override("separation", 8)
	head.add_child(head_row)
	_header = g._label(TITLE, 17)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	_header.add_theme_color_override("font_color", BOARD_INK)
	head_row.add_child(_header)
	var nail := TextureButton.new()
	nail.name = "BtnClose"
	nail.texture_normal = board_tex("nail_brass.png")
	nail.texture_disabled = nail.texture_normal
	nail.ignore_texture_size = true
	nail.stretch_mode = TextureButton.STRETCH_SCALE
	nail.custom_minimum_size = NAIL
	nail.tooltip_text = "Закрыть"
	nail.pressed.connect(close)
	head_row.add_child(nail)

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

## Конструктор N↔M (спека §4.1): два планшета инвентаря рядом — своя коллекция и
## коллекция друга — и два ряда ячеек под ними. Тап по карману кладёт карту в
## первый свободный слот стороны, тап по занятой ячейке убирает. Недоступное
## затемняется fade-шейдером, а не прячется: игрок обязан видеть, ЧТО он не может
## положить и почему ряд не набирается.
func _render_builder() -> void:
	_clear(_body)
	_header.text = "%s · %s" % [TITLE, _nick()]
	_art_seq += 1
	var seq := _art_seq
	var pending: Array = []

	var panes := HBoxContainer.new()
	panes.name = "Panes"
	# 8 px между планшетами — не косметика: наклон ±1.2° раздвигает охватывающий
	# прямоугольник доски на 316·sin(1.2°) ≈ 7 px, и при меньшем зазоре края двух
	# планшетов перекрывались бы.
	panes.add_theme_constant_override("separation", 8)
	_body.add_child(panes)
	var mine := _pane(panes, "PaneMine", "Мои карты", entries(), "give",
		pending, -_tilt(_peer))
	var peer := _pane(panes, "PanePeer", "Карты: %s" % _nick(), peer_entries(),
		"want", pending, _tilt(_peer))
	# §4.4: ответ коллекции ещё не пришёл (или не придёт — друг офлайн). Панель не
	# пустая и не молчаливая: на ней написано, почему она не заполнена, а не
	# выдуманное «у друга нет карт».
	if _peer_coll.is_empty():
		var inner: VBoxContainer = peer.get_meta("inner")
		var off := Label.new()
		off.name = "Offline"
		off.text = "Мир не на связи\nколлекция друга недоступна"
		off.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off.add_theme_font_size_override("font_size", 12)
		off.add_theme_color_override("font_color", PAPER_INK)
		off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(off)
		_fade_tree(peer, _fade_mat(FADE_OUT))

	var slots := VBoxContainer.new()
	slots.name = "Slots"
	slots.add_theme_constant_override("separation", 4)
	_body.add_child(slots)
	_side_row(slots, "give", _offer["give"], pending)
	_side_row(slots, "want", _offer["want"], pending)

	if _note != "":
		var note := g._label(_note, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", AMBER)
		_body.add_child(note)
	_footer()
	_fill_arts(seq, pending)

## Планшет инвентаря: подложка pane_tablet.png + сетка 3 колонки внутри.
## MarginContainer кладёт ВСЕХ детей в один и тот же прямоугольник — так текстура
## лежит под контентом без PanelContainer и без плоского стиля.
func _pane(parent: Control, nm: String, title: String, items: Array,
		side: String, pending: Array, tilt: float) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.name = nm
	mc.custom_minimum_size = PANE
	parent.add_child(mc)
	var plate := TextureRect.new()
	plate.name = "Plate"
	plate.texture = tex("pane_tablet.png")
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.rotation_degrees = tilt
	plate.pivot_offset = PANE / 2.0
	mc.add_child(plate)
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(s, int(PANE_PAD))
	mc.add_child(pad)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 4)
	pad.add_child(inner)
	mc.set_meta("inner", inner)
	var cap := Label.new()
	cap.name = "Caption"
	cap.text = title
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", PAPER_INK)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cap)
	var scroll := ScrollContainer.new()
	scroll.name = "GridScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = GRID_COLS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", int(GRID_GAP))
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for e in items:
		grid.add_child(_cell(side, e as Dictionary, pending))
	return mc

## Карман ячейки: настоящая кожаная подложка pocket.png, миниатюра поверх, имя и
## счётчик копий. `texture_disabled` — та же текстура: без неё TextureButton в
## disabled не рисует ничего, а серость делает fade-материал, а не отсутствие
## картинки.
func _cell(side: String, e: Dictionary, pending: Array) -> TextureButton:
	var cid := String(e.get("card_id", ""))
	var key := cid if cid != "" else String(e.get("craft_id", ""))
	var b := TextureButton.new()
	b.name = "Cell%s_%s" % ["Mine" if side == "give" else "Peer", key]
	b.texture_normal = tex("pocket.png")
	b.texture_disabled = b.texture_normal
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = CELL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.tooltip_text = "%s\n%s" % [String(e.get("display_name", "")), _copies_hint(side, e)]

	var art := TextureRect.new()
	art.name = "Art"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2((CELL.x - ART) / 2.0, 8.0)
	art.size = Vector2(ART, ART)
	b.add_child(art)
	pending.append([art, _preview_arg(side, e)])

	var nm := _ink_label("Name", String(e.get("display_name", "")), 9,
		Vector2(2.0, 66.0), Vector2(CELL.x - 4.0, 16.0))
	nm.clip_text = true
	b.add_child(nm)
	var cp := _ink_label("Copies", _copies_label(side, e), 9,
		Vector2(2.0, 82.0), Vector2(CELL.x - 4.0, 12.0))
	b.add_child(cp)
	if not can_add(side, e):
		b.disabled = true
		_fade_tree(b, _fade_mat(FADE_SPENT))
	b.pressed.connect(_on_cell.bind(side, e))
	return b

## Подпись + ряд из TRADE_SIDE_MAX ячеек стороны. Ряд рисуется целиком даже при
## пустом оффере: пустые ячейки под сургучом и есть обещание «сюда можно положить
## ещё N», без них игрок не видит потолок стороны.
func _side_row(parent: Control, side: String, arr, pending: Array) -> void:
	var col := VBoxContainer.new()
	col.name = "ColGive" if side == "give" else "ColWant"
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	var list: Array = arr if arr is Array else []
	var cap := Label.new()
	cap.name = "SideCaption"
	cap.text = "%s (%d/%d)" % ["Отдаёшь" if side == "give" else "Прошу взамен",
		list.size(), TRADE_SIDE_MAX]
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)
	var row := HBoxContainer.new()
	row.name = "RowGive" if side == "give" else "RowWant"
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", int(SLOT_GAP))
	col.add_child(row)
	for i in TRADE_SIDE_MAX:
		row.add_child(_slot(side, i, list, pending))

func _slot(side: String, pos: int, arr: Array, pending: Array) -> TextureButton:
	var b := TextureButton.new()
	b.name = "Slot%s_%d" % ["Give" if side == "give" else "Want", pos]
	b.texture_normal = tex("pocket.png")
	b.texture_disabled = b.texture_normal
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = CELL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	if pos < arr.size():
		var e: Dictionary = arr[pos]
		var art := TextureRect.new()
		art.name = "Art"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2((CELL.x - ART) / 2.0, 8.0)
		art.size = Vector2(ART, ART)
		b.add_child(art)
		pending.append([art, _preview_arg(side, e)])
		b.add_child(_ink_label("Name", String(e.get("display_name", "")), 9,
			Vector2(2.0, 66.0), Vector2(CELL.x - 4.0, 16.0)))
		b.tooltip_text = String(e.get("display_name", ""))
		b.pressed.connect(_on_slot_pressed.bind(side, pos))
	else:
		# Пустая ячейка — сургуч: «сюда ещё ничего не положили». В занятой сургуча
		# быть не должно, иначе проверка «slot seal fills empty cells» превращается
		# в «на ряду есть хоть один сургуч».
		var seal := TextureRect.new()
		seal.name = "Seal"
		seal.texture = tex("slot_seal.png")
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_SCALE
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.position = Vector2((CELL.x - SEAL) / 2.0, (CELL.y - SEAL) / 2.0)
		seal.size = Vector2(SEAL, SEAL)
		b.add_child(seal)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if side == "want" and bool(_offer["gift"]):
		b.disabled = true
		_fade_tree(b, _fade_mat(FADE_OUT))
	return b

## Бумажная кнопка нижнего ряда: подложка paper_note.png с текстом-лейблом.
## Обычная Button с StyleBoxFlat сюда не годится — §5 требует, чтобы кнопки окна
## были вырезаны из той же бумаги, что и карманы.
func _sheet_button(nm: String, text: String) -> TextureButton:
	var b := TextureButton.new()
	b.name = nm
	b.texture_normal = board_tex("paper_note.png")
	b.texture_disabled = b.texture_normal
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = SHEET
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var cap := _ink_label("Text", text, 13, Vector2(4.0, 8.0),
		Vector2(SHEET.x - 8.0, SHEET.y - 16.0))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(cap)
	return b

func _footer() -> void:
	var foot := MarginContainer.new()
	foot.name = "Footer"
	foot.custom_minimum_size = Vector2(0, FOOT_H)
	_body.add_child(foot)
	var plate := TextureRect.new()
	plate.name = "Rail"
	plate.texture = board_tex("frame_h.png")
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(plate)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 6)
	foot.add_child(row)
	row.add_child(_corner("CapL"))
	var offer := _sheet_button("BtnOffer", "Предложить")
	# Гейт §9.2 живёт и здесь: остаток недели считает сервер, поэтому «Предложить»
	# глушится по remain, а не по локальному подсчёту.
	offer.disabled = (not can_confirm()) or int(_list.get("remain", 1)) <= 0
	offer.pressed.connect(open_confirm)
	row.add_child(offer)
	var gift := _sheet_button("BtnGift",
		"Подарок: да" if bool(_offer["gift"]) else "Подарить")
	gift.pressed.connect(_toggle_gift)
	row.add_child(gift)
	var back := _sheet_button("BtnBack", "К списку")
	back.pressed.connect(_back_to_list)
	row.add_child(back)
	row.add_child(_corner("CapR"))

## Уголок рейки — декор, а не кнопка: пин «builder buttons declare tappable
## sizes» читает все BaseButton ряда, и превращать украшение в недоступную кнопку
## незачем.
func _corner(nm: String) -> TextureRect:
	var c := TextureRect.new()
	c.name = nm
	c.texture = board_tex("corner_iron.png")
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_SCALE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = CAP
	return c

func _ink_label(nm: String, text: String, font_size: int,
		pos: Vector2, size: Vector2) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = text
	l.position = pos
	l.size = size
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", PAPER_INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _copies_label(side: String, e: Dictionary) -> String:
	if String(e.get("card_id", "")) == "":
		return "×1"
	var have := _copies_for(side, String(e.get("card_id", "")))
	if have < 0:
		return ""
	return "×%d" % have

## Причина, по которой карман недоступна, — в тултипе, а не на самой ячейке: 76 px
## не выносят второй строки, а «почему не кладётся» игрок спрашивает глазами, а не
## тапом (спека §4.1).
func _copies_hint(side: String, e: Dictionary) -> String:
	var cid := String(e.get("card_id", ""))
	if cid == "":
		return "Единственный экземпляр"
	var have := _copies_for(side, cid)
	if have < 0:
		return "Коллекция недоступна"
	if side == "give":
		return "Копий в коллекции: %d" % have
	return "У друга копий: %d" % have

## Аргумент preview_texture: вид — по card_id (ключ кэша — карточка каталога),
## экземпляр — копией серверной extra с `id = craft_id`: без этого ключом станет
## пустой card_id и превью хроматика не найдётся (§4.1, sigil_manager:487).
func _preview_arg(side: String, e: Dictionary) -> Dictionary:
	var cid := String(e.get("card_id", ""))
	if cid != "":
		return {"card_id": cid, "id": cid}
	var craft := String(e.get("craft_id", ""))
	var src: Array = g._sigil.server_extras() if side == "give" \
		else (_peer_coll.get("extras", []) as Array)
	for x in src:
		if x is Dictionary and String((x as Dictionary).get("craft_id", "")) == craft:
			var d: Dictionary = (x as Dictionary).duplicate()
			d["id"] = craft
			return d
	return {"id": craft, "card_id": "", "rarity": "chromatic"}

## Миниатюры дорисовываются после сборки дерева (тот же приём, что sigil_ui:335):
## карманы, имена и счётники видны сразу, картинки приходят позже. Попадание в
## кэш превью возвращает синхронно, поэтому в selftest и в прогретой сессии арт
## стоит на месте в том же кадре.
func _fill_arts(seq: int, pending: Array) -> void:
	for p in pending:
		var art: TextureRect = p[0] as TextureRect
		if seq != _art_seq or art == null or not is_instance_valid(art):
			return
		var preview: ImageTexture = await g._sigil.preview_texture(p[1] as Dictionary)
		if seq != _art_seq or art == null or not is_instance_valid(art) or preview == null:
			continue
		art.texture = preview

func _on_cell(side: String, e: Dictionary) -> void:
	if add_slot(side, e):
		_render()

func _on_slot_pressed(side: String, pos: int) -> void:
	remove_slot(side, pos)
	_render()

func _toggle_gift() -> void:
	_offer["gift"] = not bool(_offer["gift"])
	if bool(_offer["gift"]):
		_offer["want"] = []
	_render()

func _back_to_list() -> void:
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
