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
## 18 px, не 6: деревянная рамка pane_tablet.png — 33 px нативных из 512, то есть
## 16 px при ширине 252. С полем 6 подпись планшета и первый ряд карманов лежали
## на дереве, а третья колонка залезала за правый край (кадр trade_build).
const PANE_PAD := 18.0
## pocket.png 160×200 (0.8) в масштабе 0.4. 64, а не 76: три колонки обязаны
## влезть в 252 − 2×18 = 216 ПОСЛЕ вертикального скроллбара GridScroll (12 px),
## иначе третья колонка режется: 3×64 + 2×6 = 204 = 216 − 12.
const CELL := Vector2(64, 80)
## §D-поле подписи от кромки кармана: ни одна строка не ближе 6 px.
const CELL_FIELD := 6.0
## Кегль полос имени/копий и зазор между полосами кармана.
const INK_FS := 9
const POCKET_GAP := 3.0
## Потолок миниатюры: выше — и она лезет в поля pocket.png. Реальный размер
## берёт остаток высоты (`_pocket_bands`), чтобы подпись физически не могла
## вылезти за нижний край.
const ART_MAX := 44.0
const SEAL := 50.0
const GRID_COLS := 3
const GRID_GAP := 6.0
const SLOT_GAP := 4.0               # 6×64 + 5×4 = 404 ≤ 516
## Бумажная кнопка: nine-slice от paper_note.png с полем кромки PAPER_FIELD,
## поэтому плоский центр = размер минус две кромки. «Предложить» — 78 px при
## кегле 13 (замер Manrope-Regular), значит плоского центра нужно ≥78:
## 136 − 2×27. Ниже — и подпись лезет на рваный край (кадр trade_list).
const SHEET := Vector2(136, 78)
## Записка оффера в списке: бумага paper_note.png (264×176) в соотношении, близком
## к исходному, — растягивать лист до 500 px в ширину нельзя, края рвутся и
## бумага читается как полоса. 3 колонки миниатюр по 40 px на сторону вносят
## M-сторону целиком (6 ячеек = 2 ряда), стрелка и два ряда действий влезают в
## внутреннего поля листа.
const NOTE := Vector2(330, 204)
## Рваный край paper_note.png — 19 px слева/справа и 21/20 px сверху/снизу
## непрозрачной бумаги (замер 2026-10-25: `Image.load_from_file` + порог alpha
## 0.9 по средней строке). Лист лежит на `NinePatchRect`, поэтому край больше не
## масштабируется вместе с листом (при STRETCH_SCALE на 320 px он съедал 23 px,
## и подпись «Серный круг…» начиналась левее видимой бумаги). Патч = 21 px,
## поле §D 6 px ⇒ 27.
const NOTE_PATCH := 21.0
const NOTE_PAD := 27.0
const MINI := 40.0
## Наклон записки заметно меньше наклона планшета: 320 px при 1.2° дали бы +6.7 px
## по высоте строки, и соседние записки в секции перекрывались бы.
const NOTE_TILT := 0.6
## Лист подтверждения — нижняя граница, а не фиксированный размер: MarginContainer
## растёт по содержимому, поэтому при 1+1 карты лист обнимает её (270×160), а не
## остаётся пустой простынёй 420×372, как было в кадре trade_confirm.
const CONFIRM := Vector2(240, 160)
## Тот же рваный край, что у записки списка: лист подтверждения лежит на
## NinePatchRect с патчем NOTE_PATCH, поэтому поле не зависит от ширины листа
## (она растёт по содержимому) — 21 px кромки + 6 px поля §D.
const CONFIRM_PAD := 27.0
const CELL_BIG := 56.0
## 2 колонки на сторону (а не GRID_COLS=3): сторона из 6 позиций даёт лист
## 288×263 вместо 404×195 — ближе к соотношению бумаги 1.5, и подписи сторон
## перестают спорить с шириной колонки.
const CONFIRM_COLS := 2
const CAP := Vector2(40, 40)
const NAIL := Vector2(48, 48)
const FOOT_H := 80.0
const HEAD_H := 52.0
# Поля текста в текстурных блоках (спека 2026-10-25 §D): подписи не должны
# касаться кромки бумаги — иначе текст читается напечатанным поверх картинки.
const PANEL_M := 12.0
const SLOT_M := 8.0
const BTN_M := 27.0
# Рваное поле paper_note.png: 19 px слева/справа и 21/20 px сверху/снизу
# непрозрачной бумаги (замер alpha>0.9). Nine-slice-поле меньше него — и
# оборванный край разъедется при растяжении; поле текста = ему + 6 px §D.
const PAPER_FIELD := 21.0
## Два градуса затемнения, а не один: 0.55 — «копии кончились / нельзя положить»,
## 0.62 — «целика недоступна» (офлайн-планшет друга, locked кнопка, подарок).
const FADE_SPENT := 0.55
const FADE_OUT := 0.62
const PAPER_INK := Color(0.18, 0.11, 0.06)
const BOARD_INK := Color(0.95, 0.88, 0.74)
const AMBER := Color("#c9a061")
## Латунь для надписей ПОВЕРХ бумаги: pane_tablet.png в верхней части — светлый
## мёд, и #c9a061 на нём тонет (контраст ~1.9:1). Жжёная охра остаётся тем же
## акцентом и читается, поэтому пометка «последняя копия» на листе подтверждения
## ей и рисуется, а AMBER живёт на тёмном бархате окна.
const AMBER_INK := Color("#7d4f1c")
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
		# fallback_name приходит как "" (server.py:7052), и get(... , cid) вернёт
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
		# пустую give-сторону (422 side_too_long), а подтверждения игроку неоткуда.
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
		# Код поднимается по обеим сторонам сделки (server.py:4592, вызовы
		# :5823-5824 — и `_trade_registered(conn, me)`, и `(conn, to)`), поэтому
		# копия не должна указывать на отправителя: «заведись» от пропавшего
		# собеседника звучит как обвинение игрока. Формулировка совпадает с
		# social_ui.gd:139 для того же кода.
		"not_registered": return "Профиль ещё не зарегистрирован."
		"not_friends": return "Меняться можно только с друзьями"
		"not_found": return "Такого обмена уже нет"
		"not_pending": return "Этот обмен уже закрыт"
		"not_maker": return "Отменить оффер может только тот, кто его предложил"
		"too_many_open": return "Слишком много висящих предложений — закрой часть"
		"week_limit": return "Недельный лимит исчерпан — сброс в понедельник"
		"expired": return "Предложение просрочилось: ему больше недели"
		# Четыре стадии валидации сторон (NM §2.3, server.py:4640-4641). Порядок
		# копий повторяет порядок стадий: длина → форма → своя коллекция → чужая.
		# Число в копию не вписано: TRADE_SIDE_MAX здесь = 6, но серверный лимит —
		# env ALCHEMY_TRADE_SIDE_MAX (server.py:299), и при пониженном лимите цифра
		# в отказе противоречила бы счётчику "(N/6)" над сеткой. Код отдаётся и за
		# пустую give-сторону (server.py:4717), поэтому «слишком много» не покрывает
		# обе ветки.
		"side_too_long": return "Сторона обмена не заполнена или слишком длинная"
		"bad_item": return "В ячейке не выбрана ровно одна карта"
		"not_enough_copies": return "На своей стороне ты отдаёшь больше копий, чем есть"
		"peer_lacks": return "У собеседника столько копий не найдётся"
		"unknown_card": return "Такую карту мир не знает"
		"self_deal": return "Себе менять нельзя"
		# Голый card_gone отдаёт только перенос подарка (server.py:6089): целевой
		# craft_id уже занят у получателя. Дефицит коллекции при gift сервер
		# называет `not_enough_copies` (server.py:6078 → :4697), а не этим кодом.
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

	# Шапка — ореховая рейка с двумя латунными гвоздиками: заклёпка справа и
	# есть кнопка «Назад»: закрытие окна должно быть частью рамы, а не подписью
	# под ней. Кромки — код-линиями (спека 2026-10-25 §A): тёмная тень под
	# рейкой и светлый верхний срез сверху.
	var head := MarginContainer.new()
	head.name = "Head"
	head.custom_minimum_size = Vector2(0, HEAD_H)
	box.add_child(head)
	var head_plate := TextureRect.new()
	head_plate.name = "Plate"
	head_plate.texture = board_tex("frame_h.png")
	head_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head_plate.stretch_mode = TextureRect.STRETCH_SCALE
	head_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_plate)
	_plate_edges(head, HEAD_H)
	var head_row := HBoxContainer.new()
	head_row.name = "Row"
	head_row.add_theme_constant_override("separation", 8)
	head.add_child(head_row)
	head_row.add_child(_nail_deco("NailL"))
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
	# 10 px: наклон записки ±0.6° раздвигает охватывающий прямоугольник листа
	# 320×200 на 320·sin(0.6°) ≈ 3 px сверху и снизу, и при меньшем зазоре
	# верхние края соседних записок лежали бы друг на друге.
	body.add_theme_constant_override("separation", 10)
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
	_art_seq += 1
	var seq := _art_seq
	var pending: Array = []
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
	var new_btn := _sheet_button("BtnNewOffer", "Предложить обмен",
		Vector2(180, SHEET.y))
	# Без SHRINK_CENTER VBox растягивает бумажную подложку на все 516 px, и лист
	# paper_note.png с соотношением 1.5 превращается в полосу 6.8:1 (кадр списка).
	new_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Спека §9.2: при remain == 0 кнопка «Предложить» неактивна. Держать её живой
	# и глушить только «Дальше» — значит водить игрока в конструктор-тупик.
	new_btn.disabled = at_zero
	if at_zero:
		_fade_tree(new_btn, _fade_mat(FADE_SPENT))
	new_btn.pressed.connect(open_builder)
	_body.add_child(new_btn)
	if _note != "":
		var note := g._label(_note, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", AMBER)
		_body.add_child(note)
	_incoming = _section("Мне предлагают")
	_outgoing = _section("Я предложил")
	_history = _section("История")
	for o in _list.get("incoming", []):
		_offer_note(_incoming, o, 0, pending)
	for o in _list.get("outgoing", []):
		_offer_note(_outgoing, o, 1, pending)
	for o in _list.get("history", []):
		_offer_note(_history, o, 2, pending)
	if _list.is_empty():
		for box in [_incoming, _outgoing, _history]:
			var wait := g._label("—", 12)
			wait.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
			box.add_child(wait)
	_fill_arts(seq, pending)

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
##
## Записка лежит на бумаге, а не в строке текста, потому что сторона теперь
## список: «Уголь → Искра» способна показать только первую карту из шести, и
## игрок принимал бы оффер, не видя его половины. Мини-пара сторон — сетка
## миниатюр, подпись именами остаётся рядом для читаемости.
## Бумажный лист под содержимое: NinePatchRect, а не TextureRect+STRETCH_SCALE.
## Рваный край у paper_note.png — 21 px текстуры; при растяжении он масштабировался
## вместе с листом, и поле текста приходилось пересчитывать под каждый размер
## (записка 320 px съедала 23 px кромки, лист подтверждения — 17 px). Патч держит
## кромку постоянные NOTE_PATCH px при любой ширине, углы остаются нерастянутыми.
func _paper_plate(nm: String, min_size: Vector2, tilt: float) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.name = nm
	p.texture = board_tex("paper_note.png")
	for m in ["patch_margin_left", "patch_margin_top", "patch_margin_right",
			"patch_margin_bottom"]:
		p.set(m, int(NOTE_PATCH))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.pivot_offset = min_size / 2.0
	p.rotation_degrees = tilt
	return p

func _offer_note(box: VBoxContainer, raw, kind: int, pending: Array) -> void:
	if not (raw is Dictionary):
		return
	var o: Dictionary = raw
	var id := int(o.get("id", 0))
	var give: Array = _items_of(o, "give_items")
	var want: Array = _items_of(o, "want_items")
	var mc := MarginContainer.new()
	mc.name = "TradeNote_%d" % id
	mc.custom_minimum_size = NOTE
	mc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(mc)
	var plate := _paper_plate("Plate", NOTE,
		_tilt("note-%d" % id) * (NOTE_TILT / TILT_MAX))
	mc.add_child(plate)
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(s, int(NOTE_PAD))
	mc.add_child(pad)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 3)
	pad.add_child(inner)

	var sides := HBoxContainer.new()
	sides.name = "Sides"
	sides.add_theme_constant_override("separation", 6)
	sides.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(sides)
	sides.add_child(_thumb_grid("Give", give, pending))
	if want.is_empty():
		# Подарок: встречной стороны нет, и пустая сетка читалась бы как «у друга
		# нечего отдать». Сургуч говорит «сюда ничего не просят».
		var seal := TextureRect.new()
		seal.name = "Seal"
		seal.texture = tex("slot_seal.png")
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_SCALE
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.custom_minimum_size = Vector2(MINI, MINI)
		sides.add_child(seal)
	else:
		var arrow := _ink_label("Arrow", "→", 13, Vector2.ZERO, Vector2(14, MINI))
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sides.add_child(arrow)
		sides.add_child(_thumb_grid("Want", want, pending))

	var meta := HBoxContainer.new()
	meta.name = "Meta"
	meta.add_theme_constant_override("separation", 6)
	inner.add_child(meta)
	var sum := Label.new()
	sum.name = "Summary"
	sum.text = _items_line(give, want)
	sum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum.add_theme_font_size_override("font_size", 12)
	sum.add_theme_color_override("font_color", PAPER_INK)
	sum.autowrap_mode = TextServer.AUTOWRAP_OFF
	sum.clip_text = true
	sum.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(sum)
	var who := String(o.get("maker_nick", ""))
	if kind == 1:
		who = String(o.get("taker_nick", ""))
	var tail := who
	if kind == 2:
		tail = _state_word(String(o.get("state", "")))
	if tail != "":
		var dim := Label.new()
		dim.name = "Who"
		dim.text = tail
		dim.add_theme_font_size_override("font_size", 10)
		dim.add_theme_color_override("font_color", PAPER_INK)
		dim.modulate = Color(1, 1, 1, 0.62)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meta.add_child(dim)

	var acts := HBoxContainer.new()
	acts.name = "Acts"
	acts.add_theme_constant_override("separation", 6)
	acts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(acts)
	if kind == 0:
		# Отдельной кнопки «Отклонить» нет: у не-автора cancel отвечает 409
		# not_maker, а отказ по модели встречного оффера — это бездействие или
		# новый оффер (спека §4, §7).
		if _gone.has(id):
			# §7.2 — «спокойное состояние карточки оффера»: строка остаётся на
			# месте (оффер висит pending, пока его не закрыли), мёртвая ручка с
			# неё снимается, копия берётся дословно из спеки.
			var dead := Label.new()
			dead.name = "Gone"
			dead.text = "карты больше нет — предложи другую"
			dead.add_theme_font_size_override("font_size", 11)
			dead.add_theme_color_override("font_color", AMBER)
			dead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			acts.add_child(dead)
		else:
			var yes := _sheet_button("BtnAccept", "Принять")
			yes.pressed.connect(_accept.bind(id))
			acts.add_child(yes)
	elif kind == 1:
		var no := _sheet_button("BtnCancel", "Отменить")
		no.pressed.connect(_cancel.bind(id))
		acts.add_child(no)

## Позиции стороны ответа сервера: N↔M живёт в give_items/want_items, плоские
## give_card_id/give_craft_id/give_name с Task 1 ветки удалены из TradeItemOut.
static func _items_of(o: Dictionary, key: String) -> Array:
	var raw = o.get(key, [])
	return raw if raw is Array else []

## Подпись сторон для записки: имена через запятую, стрелка между сторонами,
## «Подарок: » при пустой встречной стороне (§4.2).
func _items_line(give: Array, want: Array) -> String:
	var parts: Array = []
	for it in give:
		parts.append(_item_name(it))
	var left := ", ".join(PackedStringArray(parts))
	if want.is_empty():
		return "Подарок: " + left
	var rparts: Array = []
	for it in want:
		rparts.append(_item_name(it))
	return left + " → " + ", ".join(PackedStringArray(rparts))

func _item_name(raw) -> String:
	if not (raw is Dictionary):
		return "—"
	var it: Dictionary = raw
	return _title(String(it.get("card_id", "")),
		String(it.get("craft_id", "")), String(it.get("name", "")))

## Состояние закрытой сделки одним словом — история без подписи выглядела бы
## списком висящих офферов.
static func _state_word(state: String) -> String:
	match state:
		"accepted":
			return "принят"
		"cancelled":
			return "отменён"
		"rejected":
			return "отклонён"
		_:
			return ""

## Сетка миниатюр стороны записки: до 6 позиций в 3 колонки. Ячейки — статичные
## TextureRect (не кнопки): в списке оффер игрок ничего не выбирает, а тап по
## бумажной записке должен попадать в её кнопки, а не в картинку.
func _thumb_grid(nm: String, items: Array, pending: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = nm
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for i in items.size():
		var it: Dictionary = items[i] if items[i] is Dictionary else {}
		var t := TextureRect.new()
		t.name = "Thumb_%d" % i
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.custom_minimum_size = Vector2(MINI, MINI)
		t.tooltip_text = _item_name(it)
		grid.add_child(t)
		pending.append([t, _item_preview_arg(it)])
	return grid

## Аргумент превью для позиции ответа сервера: вид — по card_id, экземпляр —
## копией extra (своей или из коллекции друга), иначе ключом кэша станет пустой
## card_id и миниатюра хроматика не найдётся (тот же приём, что `_preview_arg`).
func _item_preview_arg(it: Dictionary) -> Dictionary:
	var cid := String(it.get("card_id", ""))
	if cid != "":
		return {"card_id": cid, "id": cid}
	var craft := String(it.get("craft_id", ""))
	var srcs: Array = [g._sigil.server_extras(), _peer_coll.get("extras", [])]
	for src in srcs:
		for x in src:
			if x is Dictionary \
					and String((x as Dictionary).get("craft_id", "")) == craft:
				var d: Dictionary = (x as Dictionary).duplicate()
				d["id"] = craft
				return d
	return {"id": craft, "card_id": "", "rarity": "chromatic"}

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
	# проверяются обе стороны сделки (server.py:5946-5951: give у maker и want у
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

	var bands := _pocket_bands()
	var art := TextureRect.new()
	art.name = "Art"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2((CELL.x - float(bands[0])) / 2.0, CELL_FIELD)
	art.size = Vector2(bands[0], bands[0])
	b.add_child(art)
	pending.append([art, _preview_arg(side, e)])

	var w := CELL.x - 2.0 * SLOT_M
	var fit := _fit_name(String(e.get("display_name", "")), w)
	var nm := _ink_label("Name", String(fit[1]), int(fit[0]),
		Vector2(SLOT_M, float(bands[1])), Vector2(w, float(bands[3])))
	b.add_child(nm)
	var cp := _ink_label("Copies", _copies_label(side, e), INK_FS,
		Vector2(SLOT_M, float(bands[2])), Vector2(w, float(bands[3])))
	b.add_child(cp)
	if not can_add(side, e):
		b.disabled = true
		_fade_tree(b, _fade_mat(FADE_SPENT))
	b.pressed.connect(_on_cell.bind(side, e))
	return b

## Подпись кармана: 9 px, если не влезает — 8, потом 7; и если даже в 7 px имя
## шире полосы, обрезаем по метрике и ставим «…». Хроматические имена
## («Кобальтовая тропа») без обрезки раздували rect: Godot клампит `size` к
## натуральной ширине текста, и подпись в 48-px полосу ложилась на 104 px — за
## край кожи (кадр trade_build). Возвращает [кегль, строка].
func _fit_name(text: String, w: float) -> Array:
	var f := g.get_theme_default_font()
	for s in [INK_FS, 8, 7]:
		if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x <= w:
			return [s, text]
	var trimmed := text
	while trimmed.length() > 1 \
			and f.get_string_size(trimmed + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x > w:
		trimmed = trimmed.substr(0, trimmed.length() - 2)
	return [7, trimmed + "…"]

## [сторона арте, y имени, y копий, высота строки]. Раскладка выводится из
## метрики шрифта, а не из литеральных y: карман = поле + арте + два зазора +
## две строки + поле, и только так подпись не может залезть за нижний край при
## смене кегля или шрифта темы. При 80 px и строке 13 px арте выходит 40.
func _pocket_bands() -> Array:
	var lh := g.get_theme_default_font().get_height(INK_FS)
	var art := minf(ART_MAX,
		floorf(CELL.y - 2.0 * CELL_FIELD - 2.0 * lh - 2.0 * POCKET_GAP))
	var name_y := CELL_FIELD + art + POCKET_GAP
	return [art, name_y, name_y + lh + POCKET_GAP, lh]

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
		var bands := _pocket_bands()
		var art := TextureRect.new()
		art.name = "Art"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2((CELL.x - float(bands[0])) / 2.0, CELL_FIELD)
		art.size = Vector2(bands[0], bands[0])
		b.add_child(art)
		pending.append([art, _preview_arg(side, e)])
		var w := CELL.x - 2.0 * SLOT_M
		var fit := _fit_name(String(e.get("display_name", "")), w)
		b.add_child(_ink_label("Name", String(fit[1]), int(fit[0]),
			Vector2(SLOT_M, float(bands[1])), Vector2(w, float(bands[3]))))
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

## Бумажная кнопка: та же бумага, что и карманы, но nine-slice (спека §A) —
## TextureButton+STRETCH_SCALE растягивал запечённую тень и кромку вдоль всей
## плашки, и кнопка выглядела наклеенной картинкой. Стиль — `Button` +
## `StyleBoxTexture` с полями 8 лог. px (16 исходных, текстура @2x) под тень и
## кромку; hover +8% яркости, pressed −6% и сдвиг текстуры на 1 px вниз.
func _sheet_button(nm: String, text: String,
		size: Vector2 = SHEET) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxTexture.new()
	sb.texture = board_tex("paper_note.png")
	for m in ["texture_margin_left", "texture_margin_top",
			"texture_margin_right", "texture_margin_bottom"]:
		sb.set(m, PAPER_FIELD)
	for m in ["content_margin_left", "content_margin_top",
			"content_margin_right", "content_margin_bottom"]:
		sb.set(m, BTN_M)
	var sbh: StyleBoxTexture = sb.duplicate()
	sbh.modulate_color = Color(1.08, 1.08, 1.08)
	var sbp: StyleBoxTexture = sb.duplicate()
	sbp.modulate_color = Color(0.94, 0.94, 0.94)
	# «1 px вниз» при нажатии: в Godot 4 у StyleBoxTexture нет texture_offset,
	# сдвиг делаем верхним/нижним полем контента.
	sbp.content_margin_top = BTN_M - 1.0
	sbp.content_margin_bottom = BTN_M + 1.0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 13)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, PAPER_INK)
	b.add_theme_color_override("font_disabled_color",
		Color(PAPER_INK.r, PAPER_INK.g, PAPER_INK.b, 0.55))
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

func _footer() -> void:
	var foot := MarginContainer.new()
	foot.name = "Footer"
	foot.custom_minimum_size = Vector2(0, FOOT_H)
	for s in ["margin_left", "margin_right"]:
		foot.add_theme_constant_override(s, int(PANEL_M))
	_body.add_child(foot)
	var plate := TextureRect.new()
	plate.name = "Rail"
	plate.texture = board_tex("frame_h.png")
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(plate)
	_plate_edges(foot, FOOT_H, false)
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

## Латунный гвоздик-декор на рейке титра (спека §C: два гвоздика, правый из них
## — живая кнопка закрытия).
func _nail_deco(nm: String) -> TextureRect:
	var n := TextureRect.new()
	n.name = nm
	n.texture = board_tex("nail_brass.png")
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.custom_minimum_size = NAIL
	return n

## Код-кромка плашки (спека §A): 1 px светлого среза сверху самой плашки и 2 px
## тёмной контактной тени с нужной стороны. Line2D, а не ColorRect: пин «no flat
## controls in the visible layer» запрещает заливные прямоугольники в видимом
## слое. У футера тень ложится НАД рейкой — под рейкой край окна.
func _plate_edges(parent: Control, h: float, shadow_below: bool = true) -> void:
	var top := Line2D.new()
	top.name = "EdgeTop"
	top.points = PackedVector2Array([Vector2(0, 0.7), Vector2(540, 0.7)])
	top.width = 1.0
	top.default_color = Color("#fdf3dc")
	top.default_color.a = 0.14
	parent.add_child(top)
	var bottom := Line2D.new()
	bottom.name = "EdgeShadow"
	var y := h + 1.0 if shadow_below else -1.0
	bottom.points = PackedVector2Array([Vector2(0, y), Vector2(540, y)])
	bottom.width = 2.0
	bottom.default_color = Color("#120c07")
	bottom.default_color.a = 0.35
	parent.add_child(bottom)

func _ink_label(nm: String, text: String, font_size: int,
		pos: Vector2, size: Vector2) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = text
	# Кегль ДО размера: `Control.size` клампится минимальным размером подписи, а
	# он считается по шрифту. При порядке «size, потом override» rect застревал на
	# строке дефолтного шрифта темы (23 px вместо 13), и подпись уезжала за
	# нижний край кармана — ровно тот §D-брак, который ловит пин.
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", PAPER_INK)
	l.position = pos
	l.size = size
	# Чернила сверху полосы: box подписи клампится к минимуму по дефолтному кеглю
	# темы (23 px) и остаётся выше строки, а §D считает отступ по верхнему краю
	# полосы. При CENTER глифы уезжали бы на 5 px вниз, к нижней кромке кожи.
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
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

## Лист подтверждения: стороны глазами, а не подписью первой карты. Список N↔M
## в строке «Ты отдаёшь: A, B, …» ломается на длинных именах и прячет половину
## сделки под переносом, поэтому каждая ячейка — миниатюра с именем, а янтарём
## помечена именно последняя копия (спека §5.3: сервер такую сделку не блокирует,
## значит название последствия обязан видеть игрок).
func _render_confirm() -> void:
	_clear(_body)
	_art_seq += 1
	var seq := _art_seq
	var pending: Array = []
	_header.text = "%s · %s" % [TITLE, _nick()]
	var give: Array = _offer["give"]
	var want: Array = _offer["want"]
	var sheet := MarginContainer.new()
	sheet.name = "ConfirmSheet"
	sheet.custom_minimum_size = CONFIRM
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(sheet)
	var plate := _paper_plate("Plate", CONFIRM, _tilt(_peer) * 0.5)
	sheet.add_child(plate)
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(s, int(CONFIRM_PAD))
	sheet.add_child(pad)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 6)
	pad.add_child(inner)

	var cols := HBoxContainer.new()
	cols.name = "Cols"
	cols.add_theme_constant_override("separation", 6)
	cols.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(cols)
	cols.add_child(_confirm_col("GiveCol", "Give", "Отдаёшь", give, "give", pending))
	if bool(_offer["gift"]):
		var seal := TextureRect.new()
		seal.name = "GiftSeal"
		seal.texture = tex("slot_seal.png")
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_SCALE
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seal.custom_minimum_size = Vector2(CELL_BIG, CELL_BIG)
		seal.tooltip_text = "Подарок (%s): без встречной карты" % _nick()
		cols.add_child(seal)
	else:
		var arrow := _ink_label("Arrow", "→", 15, Vector2.ZERO,
			Vector2(16, CELL_BIG * 2.0))
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cols.add_child(arrow)
		cols.add_child(_confirm_col("WantCol", "Want", "Прошу взамен", want,
			"want", pending))

	# Предупреждение — только про отдаваемые карты (спека §5.3): want собирается
	# из коллекции друга (§4.1), поэтому «последняя копия» на его стороне описывает
	# карту, которую просят у него, а не ту, что теряю я — игрок читал бы неправду
	# про своё необратимое последствие.
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
		warn.add_theme_color_override("font_color", AMBER)
		_body.add_child(warn)
	if _note != "":
		var note := g._label(_note, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", AMBER)
		_body.add_child(note)
	var acts := HBoxContainer.new()
	acts.name = "Acts"
	acts.add_theme_constant_override("separation", 8)
	acts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(acts)
	var go := _sheet_button("BtnConfirm",
		"Подарить" if bool(_offer["gift"]) else "Предложить")
	go.pressed.connect(_send)
	acts.add_child(go)
	var edit := _sheet_button("BtnBack", "Изменить")
	edit.pressed.connect(open_builder)
	acts.add_child(edit)
	_fill_arts(seq, pending)

## Колонка листа подтверждения: подпись стороны и сетка миниатюр.
func _confirm_col(col_nm: String, grid_nm: String, cap: String, side: Array,
		side_key: String, pending: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = col_nm
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var head := Label.new()
	head.name = "Cap"
	head.text = "%s (%d/%d)" % [cap, side.size(), TRADE_SIDE_MAX]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", PAPER_INK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	col.add_child(_confirm_grid(grid_nm, side, side_key, pending))
	return col

func _confirm_grid(nm: String, side: Array, side_key: String,
		pending: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = nm
	grid.columns = CONFIRM_COLS
	grid.add_theme_constant_override("h_separation", 2)
	# 16 px между рядами — место под подпись имени: она лежит вне прямоугольника
	# миниатюры (у TextureRect нет встроенной подписи), и без зазора имена ряда
	# легли бы на картинки следующего.
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for i in side.size():
		var e: Dictionary = side[i]
		var t := TextureRect.new()
		t.name = "Thumb_%d" % i
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.custom_minimum_size = Vector2(CELL_BIG, CELL_BIG)
		t.tooltip_text = String(e.get("display_name", ""))
		grid.add_child(t)
		pending.append([t, _preview_arg(side_key, e)])
		var nm_lbl := _ink_label("Name", String(e.get("display_name", "")), 9,
			Vector2(0.0, CELL_BIG + 1.0), Vector2(CELL_BIG, 13.0))
		nm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm_lbl.clip_text = true
		# Янтарь — единственный признак «это последняя копия»: плашка поверх
		# миниатюры закрыла бы саму карту (§5).
		if bool(e.get("is_last", false)):
			nm_lbl.add_theme_color_override("font_color", AMBER_INK)
		t.add_child(nm_lbl)
	return grid

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

func _nick() -> String:
	var friend := g._social.friend_by_device(_peer)
	if friend.is_empty():
		return "Алхимик"
	return String(friend.get("nick", "Алхимик"))
