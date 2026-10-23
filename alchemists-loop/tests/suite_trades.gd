extends RefCounted
class_name SuiteTrades
# S2 «Обмен картами» (клиент): net-слой, подслой TradeUI внутри SocialUI,
# пикер последней копии, недельный лимит и бейдж. Герметично: в selftest Net
# сливает очередь в offline (SelftestMode), поэтому сборку запроса смотрим на
# подставном NetBase с погашенным _send_next (шаблон suite_resonance_net.gd:5
# `const NetBase := preload(...)`), а маршрутизацию — прямым Net._dispatch.
# Мутации, красящие этот блок: удалить метод/сигнал в net.gd, сменить path или
# поле body, снять `trade_*.emit(parsed)` в _dispatch, подменить emit(parsed) на
# emit({}), перепутать местами give/want или card/craft в body.

const NetBase := preload("res://autoload/net.gd")

## Текстурный комплект окна обмена (спека §5): PNG @2x из SVG-генератора ВНЕ репо.
const TA_DIR := "res://assets/trades/"

# HoldingNet: _send_next погашен, значит _enqueue накапливает запросы в _queue,
# и мы видим РОВНО ТО, что поставил в очередь вызываемый метод (а не словарь,
# переписанный руками в тесте).
class HoldingNet extends NetBase:
	func _send_next() -> void:
		pass

	# Вызов метода по имени через call: компилируется до GREEN. Если метода нет,
	# возвращаем {} — проверка краснеет честно, без рантайм-ошибки.
	static func one(held: NetBase, m: String, args: Array) -> Dictionary:
		held._queue.clear()
		if not held.has_method(m):
			return {}
		held.callv(m, args)
		if held._queue.is_empty():
			return {}
		return held._queue[0]


static func run(g: Game) -> void:
	_methods(g)
	_shapes(g)
	_dispatch_routes(g)
	_entry(g)
	_constructor(g)
	_list_actions(g)
	_textures(g)
	_builder(g)
	_offer_model(g)


static func _methods(_g: Game) -> void:
	var held := HoldingNet.new()
	for m in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift",
			"trade_list", "trade_peer_collection"]:
		Selftest.check("net has " + m, held.has_method(m))
	held.free()


static func _shapes(_g: Game) -> void:
	var held := HoldingNet.new()
	# N↔M: give/want — массивы позиций Item = {card_id, craft_id} (XOR: заполнен
	# ровно один ключ). Слоты заполнены РАЗНЫМИ значениями намеренно: здесь
	# пинится маппинг «аргумент метода → ключ body», а не валидность запроса
	# (инвариант XOR держит сервер, сторону выбирает пикер Tasks 8–9). Пустой
	# массив не ловит ни перестановку give/want, ни фиксированную пустую строку
	# в net.gd.
	var q := HoldingNet.one(held, "trade_offer", ["me", "peer",
		[{"card_id": "spark", "craft_id": ""}, {"card_id": "", "craft_id": "gc1"}],
		[{"card_id": "ice", "craft_id": ""}]])
	Selftest.check("trade offer POST body", q != {}
		and String(q.get("path", "")) == "/trade/offer"
		and q.get("body", {}) == {"device_id": "me", "to": "peer",
			"give": [{"card_id": "spark", "craft_id": ""},
				{"card_id": "", "craft_id": "gc1"}],
			"want": [{"card_id": "ice", "craft_id": ""}]})
	# Пин брифа: body несёт СПИСКИ позиций ровно заданной длины, а одиночных
	# ключей прошлой сигнатуры в нём больше нет.
	q = HoldingNet.one(held, "trade_offer",
		["dev-a", "dev-b", [{"card_id": "clay"}, {"craft_id": "c-31"}],
			[{"card_id": "metal"}]])
	var lists_body: Dictionary = q.get("body", {})
	Selftest.check("net offer body carries item lists", q != {}
		and String(q.get("path", "")) == "/trade/offer"
		and (lists_body.get("give", []) as Array).size() == 2
		and (lists_body.get("want", []) as Array).size() == 1
		and not lists_body.has("give_card_id"))
	q = HoldingNet.one(held, "trade_accept", ["me", 12])
	Selftest.check("trade accept POST body", q != {}
		and String(q.get("path", "")) == "/trade/accept"
		and q.get("body", {}) == {"device_id": "me", "id": 12})
	q = HoldingNet.one(held, "trade_cancel", ["me", 12])
	Selftest.check("trade cancel POST body", q != {}
		and String(q.get("path", "")) == "/trade/cancel"
		and q.get("body", {}) == {"device_id": "me", "id": 12})
	q = HoldingNet.one(held, "trade_gift", ["me", "peer",
		[{"card_id": "spark", "craft_id": ""}, {"card_id": "", "craft_id": "gc1"}]])
	Selftest.check("trade gift POST body", q != {}
		and String(q.get("path", "")) == "/trade/gift"
		and q.get("body", {}) == {"device_id": "me", "to": "peer",
			"give": [{"card_id": "spark", "craft_id": ""},
				{"card_id": "", "craft_id": "gc1"}]})
	q = HoldingNet.one(held, "trade_list", ["dev 1"])
	Selftest.check("trade list GET path", q != {}
		and String(q.get("path", "")) == "/trade/list?device_id=dev%201"
		and not q.has("body"))
	# GET по образцу trade_list: оба параметра в query, тела нет.
	q = HoldingNet.one(held, "trade_peer_collection", ["dev 1", "peer 2"])
	Selftest.check("trade peer collection GET path", q != {}
		and String(q.get("path", "")) == "/trade/peer_collection?device_id=dev%201&peer=peer%202"
		and not q.has("body"))
	held.free()


static func _dispatch_routes(_g: Game) -> void:
	# Каждый kind обязан прийти РОВНО В СВОЙ сигнал и со своим parsed-словарём:
	# маркер {"for": kind} ловит и снятую ветку `trade_*.emit(parsed)` (тогда
	# got остаётся пустым), и подмену на `emit({})`, и перепутанные между собой
	# ветки. Connect по StringName — чтобы несуществующий сигнал не ронял билд
	# на RED. Отключение в конце — как в шаблоне (suite_resonance_net.gd:461),
	# иначе подписчики висят на autoload до конца прогона и текут в ObjectDB.
	var want := {}
	var got := {}
	var cbs := []
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift",
			"trade_list", "trade_peer_collection"]:
		var sig := String(kind) + "_result"
		want[sig] = {"for": String(kind)}
		if Net.has_signal(sig):
			var cb: Callable = func(r: Dictionary) -> void: got[sig] = r
			cbs.append([sig, cb])
			Net.connect(StringName(sig), cb)
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift",
			"trade_list", "trade_peer_collection"]:
		Net._dispatch({"kind": kind}, want[String(kind) + "_result"])
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift",
			"trade_list", "trade_peer_collection"]:
		var sig := String(kind) + "_result"
		Selftest.check("dispatch emits " + String(kind), got.get(sig, {}) == want[sig])
	for entry in cbs:
		Net.disconnect(StringName(entry[0]), entry[1])


static func _button_named(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
		var deep := _button_named(c, text)
		if deep != null:
			return deep
	return null


static func _label_has(node: Node, needle: String) -> bool:
	for c in node.get_children():
		if c is Label and (c as Label).text.contains(needle):
			return true
		if _label_has(c, needle):
			return true
	return false


static func _pending(kind: String) -> bool:
	# Синхронного offline-слива может не быть: чужой запрос ещё в _inflight, и
	# _send_next выходит рано — тогда запрос остаётся в Net._queue, что тоже
	# доказательство «метод вызвали».
	for req in Net._queue:
		if String(req.get("kind", "")) == kind:
			return true
	return false


static func _entry(g: Game) -> void:
	# Мутации: убрать кнопку из _friend_row (первые два кейса); убрать add_child
	# слоя в экран SocialUI (третий — слой не прикрепляется); снять Net.trade_list
	# в open() (четвёртый — список не запрашивается); убрать z_index 21 или
	# add_to_group (пятый); снять elif-ветку в _close_top_modal (шестой — Esc
	# гасит SocialUI); убрать _trade_close() в open/close (седьмой — слой
	# переживает закрытие экрана с чужим _peer); снять connect/forwarder в main
	# (восьмой — _list не приходит).
	var names := ["swap row for friend", "swap hidden for spirit",
		"swap press opens trade", "trade open pulls list",
		"trade layer z and group",
		"esc closes trade not social", "social reopen drops trade",
		"trade list routed to trade ui"]
	var ui = g.get("_social_ui")
	if ui == null:
		for n in names:
			Selftest.check(n, false)
		return
	g._social._seed_demo()
	var row: Control = ui._friend_row(g._social.friend_by_device("dev-b"))
	var swap := _button_named(row, "Обменять")
	Selftest.check("swap row for friend", swap != null)
	var spirit_row: Control = ui._friend_row(
		{"device_id": Social.SPIRIT_DEVICE, "nick": Social.SPIRIT_NICK})
	Selftest.check("swap hidden for spirit", _button_named(spirit_row, "Обменять") == null)
	ui.open(0)
	# Запрос списка — вторая половина провода: open() обязан сам дёрнуть
	# Net.trade_list. base_url гасим на время нажатия (шаблон
	# suite_companion_atlas.gd:24-40): при пустом base_url очередь сливается в
	# offline синхронно, значит trade_list_result гарантированно доходит до того,
	# как мы снимем подписчика, и никакого настоящего HTTP не будет.
	# `ui`/`tr` пришли через get() и потому Variant: `:=` на них тип не выводит.
	var base0 := String(Net.base_url)
	var pulls := {"n": 0}
	var spy := func(_res: Dictionary) -> void:
		pulls["n"] = int(pulls["n"]) + 1
	var pending_before := _pending("trade_list")
	Net.base_url = ""
	Net.trade_list_result.connect(spy)
	if swap != null:
		swap.pressed.emit()
	Net.trade_list_result.disconnect(spy)
	Net.base_url = base0
	var tr = ui.get("_trade")
	Selftest.check("swap press opens trade", tr != null and tr.is_open()
		and (tr.get("_screen") as Control) != null
		and (tr.get("_screen") as Control).get_parent() == ui._screen)
	Selftest.check("trade open pulls list",
		not pending_before and (int(pulls["n"]) >= 1 or _pending("trade_list")))
	if tr != null:
		var s: Control = tr.get("_screen")
		Selftest.check("trade layer z and group", s != null and s.z_index == 21
			and s.is_in_group("modal_ui"))
	else:
		Selftest.check("trade layer z and group", false)
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_ESCAPE
	var esc_ok := g._handle_esc(k)
	if tr != null:
		Selftest.check("esc closes trade not social", esc_ok and not tr.is_open()
			and ui._screen.visible)
	else:
		Selftest.check("esc closes trade not social", false)
	ui.open(0)
	var tr2 = ui.get("_trade")
	if tr2 != null:
		tr2.open("dev-b")
		ui.close()
		ui.open(0)
		Selftest.check("social reopen drops trade", not tr2.is_open()
			and String(tr2.get("_peer")) == "")
		tr2.open("dev-b")
		Net.trade_list_result.emit({"ok": true, "incoming": [], "outgoing": [],
			"history": [], "week_limit": 10, "remain": 7})
		Selftest.check("trade list routed to trade ui",
			int((tr2.get("_list") as Dictionary).get("remain", -1)) == 7)
	else:
		Selftest.check("social reopen drops trade", false)
		Selftest.check("trade list routed to trade ui", false)
	# Оба ряда собранны detached (`_friend_row` ничего не добавляет в дерево),
	# поэтому их обязан освободить создавший — иначе каждый прогон selftest
	# оставляет узлы в ObjectDB (правило minors Task 7).
	row.free()
	spirit_row.free()
	ui.close()


static func _constructor(g: Game) -> void:
	# Мутации: добавить/убрать ключ в pick() (первый кейс), переписать is_last на
	# copies <= 1 без оговорки про craft_id (второй/третий/четвёртый), забыть ветку
	# extras или фолбэк имени (пятый), not disabled у want в gift-режиме (шестой),
	# вызвать Net.trade_offer из open_confirm() вместо кнопки (седьмой и восьмой: в
	# первом падает потому, что сигнал уже прилетел до нажатия, во втором — fired
	# становится 2, а запрос уже лежит в очереди до нажатия), снять маппинг detail
	# (девятый), снять offline-ветку в `_on_write_result` (десятый), вернуть в
	# предупреждение второй дизъюнкт про want (одиннадцатый), забыть сброс _note в
	# open_confirm() (двенадцатый), оставить подарок на экране подтверждения с уже
	# очищенным оффером (тринадцатый), убрать сброс черновика в open()
	# (четырнадцатый).
	# Страж has_script_method — он же и RED: удалить любой из семи новых методов
	# значит получить все четырнадцать падений сразу, а не обрезанную сюиту.
	var names := ["pick contract is four fields", "pick single copy is last",
		"pick third copy is not last", "pick chromatic is always last",
		"entries list owned cards and extras", "gift mode kills want slot",
		"confirm warns before offer", "offer sends only on proceed",
		"offer failure shows server copy", "offline refusal says no connection",
		"confirm warns about what you give", "confirm drops the stale refusal",
		"gift success leaves confirm", "open clears the draft"]
	var T = load("res://game/social/trade_ui.gd")
	var api := ["pick", "entries", "open_builder", "open_confirm",
		"can_confirm", "on_offer", "on_gift"]
	var ready := true
	for m in api:
		if not T.has_script_method(StringName(m)):
			ready = false
	if not ready:
		for n in names:
			Selftest.check(n, false)
		return
	# Экземпляр, а не статика: selftest не ссылается на class_name TradeUI
	# напрямую, а методы вызывает через Variant — ровно как SocialUI достают из
	# g.get("_social_ui"). TradeUI наследует RefCounted, поэтому tu.free() не нужен.
	var tu = T.new(g)
	var p: Dictionary = tu.pick("spark", "", 1, "Искра")
	Selftest.check("pick contract is four fields", p.keys().size() == 4
		and p.has("card_id") and p.has("craft_id")
		and p.has("is_last") and p.has("display_name"))
	Selftest.check("pick single copy is last",
		bool(tu.pick("spark", "", 1, "").get("is_last", false)))
	Selftest.check("pick third copy is not last",
		not bool(tu.pick("ice", "", 3, "").get("is_last", true)))
	# copies=4 — единственный способ заставить этот кейс краснеть: при copies <= 1
	# условие «копий мало» уже истинно, и ветка craft_id != "" не проверялась бы
	# ничем. Хроматик всегда единственный экземпляр, поэтому именно он обязан
	# считаться последним даже при формально большем числе копий.
	var ch: Dictionary = tu.pick("", "x1", 4, "Радуга")
	Selftest.check("pick chromatic is always last", bool(ch.get("is_last", false))
		and String(ch.get("card_id", "")) == "" and String(ch.get("craft_id", "")) == "x1")

	# Достаём слой ДО правок общего g._sigil: если проверка на null стоит после
	# присваиваний, её ранний return оставляет каталог unit-trade и экземпляр x1 в
	# менеджере, а дальше идут SuiteJuice, SuiteSaveSync, SuiteSyncPackageNet и
	# SuiteContractBoard (tests/selftest.gd:163-166) — падали бы они уже на себя.
	var ui = g.get("_social_ui")
	if ui == null:
		for n in names.slice(4):
			Selftest.check(n, false)
		return
	ui.open(0)
	var tr = ui.get("_trade")
	if tr == null:
		for n in names.slice(4):
			Selftest.check(n, false)
		return
	var sm = g._sigil
	sm.set_catalog([
		{"id": "spark", "set": "fire", "rarity": "common", "ether_cost": 100,
			"recipe": [], "process": "sublimatio", "stage": "albedo",
			"fallback_name": "Искра", "object_type": "object", "seed": 1},
		{"id": "ice", "set": "water", "rarity": "rare", "ether_cost": 150,
			"recipe": [], "process": "sublimatio", "stage": "albedo",
			"fallback_name": "Лёд", "object_type": "object", "seed": 2},
		# fallback_name пустой — ровно так поле приходит для вида без имени
		# (SigilCatalogCard.fallback_name = "", server.py:1097). Пикер обязан
		# показать id, иначе кнопка «— последняя» без названия недостижима глазами.
		{"id": "dust", "set": "earth", "rarity": "common", "ether_cost": 50,
			"recipe": [], "process": "calcinatio", "stage": "nigredo",
			"fallback_name": "", "object_type": "object", "seed": 3},
	], [], "unit-trade")
	sm._server_collection = {"spark": {"copies": 1, "first_at": ""},
		"ice": {"copies": 3, "first_at": ""},
		"dust": {"copies": 2, "first_at": ""}}
	sm._server_extras = [{"craft_id": "x1", "rarity": "chromatic",
		"llm_name": "Радуга", "crafted_at": "", "seed": 7, "lore": "",
		"ingredients": []}]
	# Снимок ДО прогрева: _preview_cache — тот же объект Dictionary, поэтому
	# prev0 обязан быть копией, иначе «восстановление» вернула бы прогретое.
	var prev0: Dictionary = (sm._preview_cache as Dictionary).duplicate()
	_warm_previews(sm, ["spark", "ice", "dust", "x1"])
	var list: Array = tr.entries()
	var by_card := {}
	for e in list:
		var key := String(e.get("card_id", "")) + "|" + String(e.get("craft_id", ""))
		by_card[key] = e
	Selftest.check("entries list owned cards and extras", list.size() == 4
		and bool(by_card.get("spark|", {}).get("is_last", false))
		and String(by_card.get("spark|", {}).get("display_name", "")) == "Искра"
		and not bool(by_card.get("ice|", {}).get("is_last", true))
		and String(by_card.get("dust|", {}).get("display_name", "")) == "dust"
		and String(by_card.get("|x1", {}).get("display_name", "")) == "Радуга")

	tr.open("dev-b")
	tr.open_builder()
	tr._offer = {"give": [tu.pick("spark", "", 1, "Искра")],
		"want": [tu.pick("ice", "", 3, "Лёд")], "gift": false}
	tr._mode = 1
	tr.call("_render")
	var slot_want := _node(tr._body, "SlotWant_0")
	var wn := _node(slot_want, "Name")
	# Подарок включает _toggle_gift(), он же и обнуляет want. Присваивать
	# _offer["gift"] = true напрямую нельзя: проверка описывала бы состояние,
	# которого игрок не может получить, а настоящий путь (живая ячейка с именем
	# карты, после — пустая ячейка под сургучом и disabled) оставался бы без
	# покрытия.
	var want_live := slot_want is TextureButton \
		and not (slot_want as TextureButton).disabled \
		and wn is Label and String((wn as Label).text) == "Лёд"
	tr.call("_toggle_gift")
	var slot_gift := _node(tr._body, "SlotWant_0")
	var gift_seal := _node(slot_gift, "Seal")
	Selftest.check("gift mode kills want slot", want_live
		and slot_gift is TextureButton and (slot_gift as TextureButton).disabled
		and gift_seal is TextureRect and _tex_name(gift_seal) == "slot_seal.png"
		and _node(slot_gift, "Name") == null
		and (tr._offer["want"] as Array).is_empty()
		and bool(tr._offer["gift"]))

	var fired := {"n": 0}
	var cb := func(_r: Dictionary) -> void: fired["n"] = int(fired["n"]) + 1
	Net.trade_offer_result.connect(cb)
	# _toggle_gift() стёр want — собираем встречный оффер заново, иначе
	# open_confirm() уйдёт в «Выбери карту» и проверка 7 покраснеет не за то.
	tr._offer = {"give": [tu.pick("spark", "", 1, "Искра")],
		"want": [tu.pick("ice", "", 3, "Лёд")], "gift": false}
	tr.open_confirm()
	Selftest.check("confirm warns before offer", tr._mode == 2
		and _label_has(tr._body, "последн") and _label_has(tr._body, "вехи")
		and int(fired["n"]) == 0)
	var proceed := _button_named(tr._body, "Предложить")
	# Offer обязан уходить по нажатию кнопки, а не из open_confirm(). Сигнал
	# ждём детерминированно: гасим base_url на время нажатия (шаблон
	# suite_companion_atlas.gd:24-40) — при пустом base_url очередь сливается в
	# offline синхронно. Если чужой запрос ещё в _inflight, слива нет и
	# trade_offer остаётся в очереди — это тоже доказательство вызова.
	var pending0 := _pending("trade_offer")
	var base0 := String(Net.base_url)
	Net.base_url = ""
	if proceed != null:
		proceed.pressed.emit()
	Net.base_url = base0
	Selftest.check("offer sends only on proceed", proceed != null and not pending0
		and (int(fired["n"]) == 1 or _pending("trade_offer")))
	if Net.trade_offer_result.is_connected(cb):
		Net.trade_offer_result.disconnect(cb)
	tr.open_confirm()
	tr.call("on_offer", {"ok": false, "detail": "too_many_open"})
	Selftest.check("offer failure shows server copy", _label_has(tr._body, "висящих"))

	# Offline-ответ Net приходит без ключа detail (net.gd:454 — {ok:false,
	# offline:true, message:...}), поэтому без отдельной ветки он попадёт в `_:`
	# «Мир не понял запрос»: игрок читает это про запрос, который никуда не ушёл.
	# Вызов прямой, а не через нажатие выше: синхронный слив очереди при нажатии
	# может не состояться в этом кадре (чужой запрос в _inflight), а копия обязана
	# быть запинена детерминированно.
	tr.call("on_offer", {"ok": false, "offline": true, "message": "сервер не настроен"})
	Selftest.check("offline refusal says no connection",
		_label_has(tr._body, "не на связи"))

	# Предупреждение — только про отдаваемую карту. Пикер want берёт тот же
	# список, что и give (из МОЕЙ коллекции — §8.4: источник данных один),
	# поэтому «последняя копия» на стороне want описывает карту, которую просят
	# у меня. Теряю я другую, и копия «Это твоя последняя копия» поверх want
	# говорит игроку неправду про необратимое последствие.
	tr._offer = {"give": [tu.pick("ice", "", 3, "Лёд")],
		"want": [tu.pick("spark", "", 1, "Искра")], "gift": false}
	tr.open_confirm()
	Selftest.check("confirm warns about what you give", tr._mode == 2
		and not _label_has(tr._body, "последн"))

	# Прошлый отказ не должен переживать следующее подтверждение: игрок обязан
	# видеть причину отказа, который он получил сейчас, а не того, что он уже
	# исправил.
	tr._offer = {"give": [tu.pick("spark", "", 1, "Искра")],
		"want": [tu.pick("ice", "", 3, "Лёд")], "gift": false}
	tr.open_confirm()
	tr.call("on_offer", {"ok": false, "detail": "week_limit"})
	var note_shown := _label_has(tr._body, "Недельный")
	tr.open_confirm()
	Selftest.check("confirm drops the stale refusal", note_shown
		and not _label_has(tr._body, "Недельный"))

	# Успешный подарок обязан уйти с экрана подтверждения: _offer уже пуст,
	# поэтому единственная живая кнопка «Подарить» через _send() отправила бы
	# Net.trade_gift(dev, peer, "", "") — серверный 422 bad_selector вместо
	# подтверждения, и игроку неоткуда узнать, что подарок дошёл.
	tr._offer = {"give": [tu.pick("", "x1", 1, "Радуга")],
		"want": [], "gift": true}
	tr.open_confirm()
	tr.call("on_gift", {"ok": true, "craft_id": "x1", "moved_name": "Радуга",
		"remain": 7})
	Selftest.check("gift success leaves confirm", tr._mode != 2
		and (tr._offer["give"] as Array).is_empty())

	# Смена собеседника чистит черновик: иначе полусобранный оффер, начатый с
	# другом A, уходит другу B одним нажатием «Предложить» в конструкторе.
	tr.open("dev-b")
	tr.open_builder()
	tr._offer["give"] = [tu.pick("spark", "", 1, "Искра")]
	tr.open("dev-c")
	Selftest.check("open clears the draft",
		(tr._offer["give"] as Array).is_empty() and not bool(tr.can_confirm()))
	tr.call("close")
	# Фикстура живёт в общем g._sigil, а после SuiteTrades идут SuiteJuice,
	# SuiteSaveSync, SuiteSyncPackageNet и SuiteContractBoard
	# (tests/selftest.gd:163-166): возвращаем состояние покоя той же идиомой,
	# которой чистит себя SuiteSigilCards.
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	sm._preview_cache = prev0


static func _rows_of(box) -> int:
	if box == null:
		return -1
	return (box as Control).get_child_count()


## Строка опознаётся по имени узла, которое даёт `_offer_row`: `_rows_of == 1`
## выполняется и на прежних placeholder'ах «—» (по одному Label в каждом боксе).
static func _row_named(box, want: String) -> bool:
	return _row_of(box, want) != null


## «Спокойное состояние, а не красный баннер» измеримо только цветом строки:
## слой рисует отказ янтарным (Color("#e6a84a") — он же у `_note` в конструкторе
## и у `social_ui.gd:89`), красный этот пин краснит.
static func _label_is_calm(node: Node, needle: String) -> bool:
	for c in node.get_children():
		if c is Label and (c as Label).text.contains(needle):
			return (c as Label).get_theme_color("font_color") == Color("#e6a84a")
		if _label_is_calm(c, needle):
			return true
	return false


## Строка по имени узла (`TradeRow_%d`) — или null. `_rows_of` считает и
## placeholder'ы «—», поэтому «строки нет» измеримо только именем.
static func _row_of(box, want: String) -> Node:
	if box == null:
		return null
	for c in (box as Control).get_children():
		if String((c as Node).name) == want:
			return c
	return null


## id, привязанный к кнопке строки: `_accept.bind(id)` / `_cancel.bind(id)`.
## Счётчик нажатия доказывает лишь «запрос ушёл», а не «запрос про ЭТУ сделку»:
## после `.bind(id)` → `.bind(0)` провод гудел бы зелёным.
## Список подключений смотрим у самого сигнала (образец — contracts.gd:644):
## `pressed` объявлен в BaseButton, поэтому нода приводится к нему, а не к Node.
static func _bound_id(node: Node, method: String) -> int:
	for c in (node as BaseButton).pressed.get_connections():
		var cb: Callable = c["callable"]
		if String(cb.get_method()) == method:
			var args: Array = cb.get_bound_arguments()
			if args.size() == 1:
				return int(args[0])
	return -1


static func _list_actions(g: Game) -> void:
	# Мутации: не взять incoming/outgoing/history из ответа (первый кейс);
	# нарисовать «Отклонить» у входящего (второй — ручкой отклонения сервер
	# отвечает 409 not_maker); снять connect/forwarder cancel (третий); не позвать
	# Net.trade_accept с id из строки (четвёртый); посчитать remain локально или
	# не показать его (пятый); сдвинуть сброс на воскресенье (шестой); разблокировать
	# «Дальше» при remain 0 (седьмой); забыть перебор коллекции/inbox после ok
	# (восьмой); показать card_gone красной ошибкой вместо состояния карточки или
	# устроить re-pull при отказе (девятый); не сложить trades_pending в total
	# (десятый).
	# Диффы к брифу (обоснование — task-10-report.md): строки пинятся ещё и именем
	# узла; «Дальше» проверяется на заполненном черновике, иначе её глузит пустой
	# выбор, а не остаток; cancel пинится всем проводом, как требует третий кейс;
	# вызовы ещё не существующих методов гейтятся has_script_method/has_method —
	# без гейда отсутствующий вызов обрывает сюжет, и проверки 6–10 не состоятся.
	var names := ["list rows follow server slices",
		"incoming row has accept only", "outgoing row has cancel",
		"accept press sends that order", "header shows server remain",
		"offer entry live while remain remains",
		"reset day is next monday", "proceed locked at zero remain",
		"accept ok re-pulls collection and inbox",
		"card gone is calm and does not re-pull",
		"trades pending counts into badge",
		"header names reset day at zero", "offer entry locked at zero remain",
		"gift row is labelled as gift", "accept row sends its own id",
		"cancel row sends its own id", "accept offline says no connection",
		"cancel offline says no connection", "gone offer loses its accept",
		"cancel ok clears the list", "gift ok re-pulls collection and inbox",
		"toast waits for messages not trades"]
	var ui = g.get("_social_ui")
	if ui == null:
		for n in names:
			Selftest.check(n, false)
		return
	var sm = g._sigil
	sm._server_collection = {"spark": {"copies": 1, "first_at": ""}}
	var prev0: Dictionary = (sm._preview_cache as Dictionary).duplicate()
	_warm_previews(sm, ["spark", "ice", "dust", "x1", "c-17", "ember"])
	# `_seed_demo()` пишет ЖИВОЙ g._social (cache + threads), а не только кэш
	# сигилов. Возврат снимка — единственный честный способ не оставить мусор в
	# общем объекте: четыре следующие сюиты читают его сегодня по случайности.
	var social_cache0: Dictionary = g._social.cache
	var social_threads0: Dictionary = g._social.threads.duplicate()
	g._social._seed_demo()
	ui.open(0)
	var tr = ui.get("_trade")
	if tr == null:
		for n in names:
			Selftest.check(n, false)
		sm._server_collection = {}
		sm._preview_cache = prev0
		return
	tr.open("dev-b")
	tr.call("on_list", {"ok": true,
		"incoming": [{"id": 11, "maker_device": "dev-b", "taker_device": "me",
			"maker_nick": "Николя", "taker_nick": "Я", "state": "pending",
			"created_at": "2026-10-20T09:00:00", "give_card_id": "ice",
			"give_craft_id": "", "give_name": "", "want_card_id": "spark",
			"want_craft_id": "", "want_name": ""}],
		"outgoing": [{"id": 12, "maker_device": "me", "taker_device": "dev-b",
			"maker_nick": "Я", "taker_nick": "Николя", "state": "pending",
			"created_at": "2026-10-20T09:30:00", "give_card_id": "",
			"give_craft_id": "x1", "give_name": "Радуга", "want_card_id": "ice",
			"want_craft_id": "", "want_name": ""}],
		"history": [{"id": 13, "maker_device": "dev-b", "taker_device": "me",
			"maker_nick": "Николя", "taker_nick": "Я", "state": "accepted",
			"created_at": "2026-10-18T09:00:00", "give_card_id": "ember",
			"give_craft_id": "", "give_name": "", "want_card_id": "spark",
			"want_craft_id": "", "want_name": ""}],
		"week_limit": 10, "remain": 7})
	Selftest.check("list rows follow server slices", _rows_of(tr._incoming) == 1
		and _rows_of(tr._outgoing) == 1 and _rows_of(tr._history) == 1
		and _row_named(tr._incoming, "TradeRow_11")
		and _row_named(tr._outgoing, "TradeRow_12")
		and _row_named(tr._history, "TradeRow_13")
		and _label_has(tr._outgoing, "Радуга →"))
	var in_box: Control = tr._incoming
	Selftest.check("incoming row has accept only", _button_named(in_box, "Принять") != null
		and _button_named(in_box, "Отклонить") == null
		and _button_named(in_box, "Отменить") == null)
	var out_box: Control = tr._outgoing
	var cancel_btn := _button_named(out_box, "Отменить")
	var acc_fired := {"n": 0}
	var acc_cb := func(_r: Dictionary) -> void: acc_fired["n"] = int(acc_fired["n"]) + 1
	Net.trade_accept_result.connect(acc_cb)
	var accept_btn := _button_named(in_box, "Принять")
	if accept_btn != null:
		accept_btn.pressed.emit()
	Selftest.check("accept press sends that order", int(acc_fired["n"]) == 1)
	if Net.trade_accept_result.is_connected(acc_cb):
		Net.trade_accept_result.disconnect(acc_cb)
	var cancel_fired := {"n": 0}
	var cancel_cb := func(_r: Dictionary) -> void: cancel_fired["n"] = int(cancel_fired["n"]) + 1
	Net.trade_cancel_result.connect(cancel_cb)
	if cancel_btn != null:
		cancel_btn.pressed.emit()
	if Net.trade_cancel_result.is_connected(cancel_cb):
		Net.trade_cancel_result.disconnect(cancel_cb)
	# Третий кейс по комментарию брифа краснеет от снятия connect/forwarder,
	# поэтому пин — весь провод: нажатие шлёт Net.trade_cancel (счётчик), а отказ
	# доезжает до слоя через main (emit, а не прямой вызов on_cancel).
	if cancel_btn != null:
		Net.trade_cancel_result.emit({"ok": false, "detail": "not_pending"})
	Selftest.check("outgoing row has cancel", cancel_btn != null
		and int(cancel_fired["n"]) == 1 and _label_has(tr._body, "уже закрыт"))
	# Шапка печатает сделанное (`limit - remain` из ответа), а не остаток: строка
	# «Обменов на этой неделе: 10 из 10» при remain 0 зафиксирована в приёмке
	# Task 11, поэтому при remain 7 из 10 здесь обязано быть «3 из 10».
	Selftest.check("header shows server remain", _label_has(tr._body, "3 из 10"))
	# Комплементарный пин к гейту §9.2: при ненулевом остатке вход обязан быть
	# жив, иначе `new_btn.disabled = true` (обмен недоступен всегда) зелёный.
	var entry_live := _button_named(tr._body, "Предложить обмен")
	Selftest.check("offer entry live while remain remains",
		entry_live != null and not entry_live.disabled)
	# Чистые даты: 2026-10-21 — среда, следующий понедельник 26-е; с понедельника
	# на понедельник (delta 0 → 7), иначе «сброс сегодня» ввёл бы в заблуждение.
	var T = load("res://game/social/trade_ui.gd")
	var tu = T.new(g)
	var has_day: bool = T.has_script_method("reset_day") \
		and T.has_script_method("reset_day_label")
	Selftest.check("reset day is next monday", has_day
		and String(tu.reset_day("2026-10-21")) == "2026-10-26"
		and String(tu.reset_day("2026-10-26")) == "2026-11-02"
		and String(tu.reset_day_label("2026-10-21")) == "26.10")
	tr.call("on_list", {"ok": true, "incoming": [], "outgoing": [], "history": [],
		"week_limit": 10, "remain": 0})
	tr._offer = {"give": [tu.pick("spark", "", 1, "Искра")],
		"want": [tu.pick("ice", "", 3, "Лёд")], "gift": false}
	tr.open_builder()
	var next := _btn(tr._body, "Footer/BtnOffer")
	Selftest.check("proceed locked at zero remain", next != null
		and bool(tr.can_confirm()) and next.disabled)
	var pulls := {"coll": 0, "inbox": 0}
	var coll_cb := func(_r: Dictionary) -> void: pulls["coll"] = int(pulls["coll"]) + 1
	var inbox_cb := func(_r: Dictionary) -> void: pulls["inbox"] = int(pulls["inbox"]) + 1
	Net.sigil_collection_result.connect(coll_cb)
	Net.social_inbox_result.connect(inbox_cb)
	var has_accept := g.has_method("_on_trade_accept_result")
	if has_accept:
		g.call("_on_trade_accept_result", {"ok": true, "id": 11, "remain": 6,
			"peer_remain": 8, "moved_in": {"craft_id": "c1", "llm_name": ""},
			"moved_out": {"craft_id": "c2", "llm_name": ""}})
	Selftest.check("accept ok re-pulls collection and inbox", has_accept
		and int(pulls["coll"]) == 1 and int(pulls["inbox"]) == 1)
	if has_accept:
		g.call("_on_trade_accept_result", {"ok": false, "detail": "card_gone:maker"})
	Net.trade_accept_result.emit({"ok": false, "detail": "card_gone:maker"})
	var repull := int(pulls["coll"]) == 1 and int(pulls["inbox"]) == 1
	var has_on_accept: bool = T.has_script_method("on_accept")
	if has_on_accept:
		tr.call("on_accept", {"ok": false, "detail": "card_gone:maker"})
	Selftest.check("card gone is calm and does not re-pull", has_on_accept and repull
		and _label_has(tr._body, "карты больше нет")
		and _label_is_calm(tr._body, "карты больше нет"))
	if Net.sigil_collection_result.is_connected(coll_cb):
		Net.sigil_collection_result.disconnect(coll_cb)
	if Net.social_inbox_result.is_connected(inbox_cb):
		Net.social_inbox_result.disconnect(inbox_cb)
	var s := Social.new(g)
	s.on_inbox({"ok": true, "friends": [], "incoming": [], "outgoing": [],
		"unread_total": 1, "requests_total": 0, "trades_pending": 2})
	Selftest.check("trades pending counts into badge", s.total() == 3
		and Social.badge_for(s.total()) == "Друзья •3")
	# --- Раунд исправлений ревью ---
	# Живой список с нулевым остатком и односторонней строкой. Состояние
	# восстанавливается через open(), а не присваиванием `_gone`: снятие отметки
	# на входе — часть поведения (у нового собеседника строка живая). Присваивать
	# `_gone` в тесте нельзя: до правки поля нет, а запись в несуществующее поле
	# экземпляра обрывает сюжет жёсткой ошибкой вместо RED.
	tr.open("dev-b")
	var zero := {"ok": true,
		"incoming": [{"id": 11, "maker_device": "dev-b", "taker_device": "me",
			"maker_nick": "Николя", "taker_nick": "Я", "state": "pending",
			"created_at": "2026-10-20T09:00:00", "give_card_id": "ice",
			"give_craft_id": "", "give_name": "", "want_card_id": "spark",
			"want_craft_id": "", "want_name": ""}],
		"outgoing": [{"id": 12, "maker_device": "me", "taker_device": "dev-b",
			"maker_nick": "Я", "taker_nick": "Николя", "state": "pending",
			"created_at": "2026-10-20T09:30:00", "give_card_id": "",
			"give_craft_id": "x1", "give_name": "Радуга", "want_card_id": "ice",
			"want_craft_id": "", "want_name": ""},
			{"id": 14, "maker_device": "me", "taker_device": "dev-c",
			"maker_nick": "Я", "taker_nick": "Аня", "state": "pending",
			"created_at": "2026-10-20T10:00:00", "give_card_id": "spark",
			"give_craft_id": "", "give_name": "", "want_card_id": "",
			"want_craft_id": "", "want_name": ""}],
		"history": [], "week_limit": 10, "remain": 0}
	tr._list = zero
	tr.call("_render")
	# Ветка `if remain <= 0:` в шапке до этого не краснела ничем: проверка 6
	# меряла reset_day_label как чистую функцию, а проверка 7 читала next.disabled.
	Selftest.check("header names reset day at zero",
		_label_has(tr._body, " · сброс ") and _label_has(tr._body, "10 из 10"))
	# Спека §9.2 дословно: «при remain == 0 кнопка „Предложить“ неактивна». Гейт
	# только на «Дальше» оставляет живым вход: игрок с исчерпанным лимитом
	# заводил бы экран, с которого нельзя уйти.
	var entry := _button_named(tr._body, "Предложить обмен")
	Selftest.check("offer entry locked at zero remain", entry != null and entry.disabled)
	# Односторонняя строка (`want_*` пустые) раньше не рендерилась вовсе: все три
	# ряда первой фикстуры двусторонние, и ветка «Подарок: » была недостижима.
	Selftest.check("gift row is labelled as gift",
		_row_of(tr._outgoing, "TradeRow_14") != null
		and _label_has(tr._outgoing, "Подарок: "))
	# Кнопка строки обязана нести id СВОЕЙ сделки.
	var acc_b := _button_named(tr._incoming, "Принять")
	var can_b := _button_named(tr._outgoing, "Отменить")
	Selftest.check("accept row sends its own id", acc_b != null
		and _bound_id(acc_b, "_accept") == 11)
	Selftest.check("cancel row sends its own id", can_b != null
		and _bound_id(can_b, "_cancel") == 12)
	# Офлайн-слив Net не имеет ключа detail (net.gd:454). Без отдельной ветки
	# отказ долетает до `_:` «Мир не понял запрос» — про запрос, который никуда не
	# уходил. Emit, а не прямой вызов: пинуется и маршрутизация main.gd.
	Net.trade_accept_result.emit({"ok": false, "offline": true,
		"message": "сервер не настроен"})
	Selftest.check("accept offline says no connection",
		_label_has(tr._body, "Мир не на связи")
		and not _label_has(tr._body, "не понял запрос"))
	Net.trade_cancel_result.emit({"ok": false, "offline": true,
		"message": "сервер не настроен"})
	Selftest.check("cancel offline says no connection",
		_label_has(tr._body, "Мир не на связи")
		and not _label_has(tr._body, "не понял запрос"))
	# §7.2: «карты больше нет — предложи другую» — спокойное состояние КАРТОЧКИ, а
	# не баннер над списком. Нажатие задаёт `_last_id`, поэтому отказ атрибутируется
	# именно этой строке.
	var live_acc := _button_named(tr._incoming, "Принять")
	if live_acc != null:
		live_acc.pressed.emit()
	Net.trade_accept_result.emit({"ok": false, "detail": "card_gone:taker"})
	var dead := _row_of(tr._incoming, "TradeRow_11")
	Selftest.check("gone offer loses its accept", dead != null
		and _button_named(dead, "Принять") == null
		and _label_is_calm(dead, "карты больше нет"))
	# Успешная отмена обязана убрать строку сразу: при ok `on_accept` чистит _list
	# и перерисовывает, а прежний `on_cancel` только звал Net.trade_list — против
	# живого сервера отменённая сделка висела бы на экране до ответа.
	Net.trade_cancel_result.emit({"ok": true, "id": 12})
	Selftest.check("cancel ok clears the list", _row_of(tr._outgoing, "TradeRow_12") == null)
	# Подарок переносит карту так же, как принятый обмен, и обязан звать тот же
	# перебор (§8.4). Без этой проверки строка `_trades_repull()` в
	# `_on_trade_gift_result` удаляется молча — сюжет остаётся зелёным.
	var gp := {"coll": 0, "inbox": 0}
	var gcoll := func(_r: Dictionary) -> void: gp["coll"] = int(gp["coll"]) + 1
	var ginbox := func(_r: Dictionary) -> void: gp["inbox"] = int(gp["inbox"]) + 1
	Net.sigil_collection_result.connect(gcoll)
	Net.social_inbox_result.connect(ginbox)
	Net.trade_gift_result.emit({"ok": true, "craft_id": "x1",
		"moved_name": "Радуга", "remain": 7})
	var gpull := int(gp["coll"]) == 1 and int(gp["inbox"]) == 1
	if Net.sigil_collection_result.is_connected(gcoll):
		Net.sigil_collection_result.disconnect(gcoll)
	if Net.social_inbox_result.is_connected(ginbox):
		Net.social_inbox_result.disconnect(ginbox)
	Selftest.check("gift ok re-pulls collection and inbox", gpull)
	# Тост говорит «Тебе написали», значит реагировать обязан только на сообщения и
	# заявки. Первая за сессию весточка — прилетевший оффер (trades_pending 0→2), и
	# под ней игрок ждёт письма, которого нет; §8.5 отводит trades_pending бейджу.
	var st := Social.new(g)
	st.on_inbox({"ok": true, "friends": [], "incoming": [], "outgoing": [],
		"unread_total": 0, "requests_total": 0, "trades_pending": 0})
	st.on_inbox({"ok": true, "friends": [], "incoming": [], "outgoing": [],
		"unread_total": 0, "requests_total": 0, "trades_pending": 2})
	var trade_only := not st.should_show_toast()
	st.on_inbox({"ok": true, "friends": [], "incoming": [], "outgoing": [],
		"unread_total": 1, "requests_total": 0, "trades_pending": 2})
	Selftest.check("toast waits for messages not trades",
		trade_only and st.should_show_toast() and st.total() == 3)
	tr.call("close")
	sm._server_collection = {}
	sm._preview_cache = prev0
	g._social.cache = social_cache0
	g._social.threads = social_threads0


## Текстурный комплект (Task 7, спека §5 + AGENTS.md §27): планшет панели, карман
## ячейки, сургуч пустого слота и ткань затемнения. Пины читают ПИКСЕЛИ, а не только
## факт загрузки: «не плоская заливка» и «рваный край = альфа» — условия приёмки §5,
## existence-проверка их не доказывает (PNG, залитый одним цветом, прошёл бы её).
## Хелперы дельты/шва переиспользованы из SuiteContractBoard (:3123+) — тот же
## QC-язык, что уже приняли для доски, а не новый вариант того же кода.
## Мутации, красящие блок: залить PNG одним цветом; сделать угол бумаги непрозрачным;
## разорвать шов тканевого тайла; удалить `.import`; отдать PNG другого размера.
static func _textures(_g: Game) -> void:
	# Декларируемые размеры @2x — контракт, который читает раскладка Task 8
	# (спека §4.1: панель 256×320, карман 80×100, печать 60×60, тайл ткани 128×128).
	var sizes := {
		"pane_tablet.png": Vector2i(512, 640),
		"pocket.png": Vector2i(160, 200),
		"slot_seal.png": Vector2i(120, 120),
		"cloth_dark.png": Vector2i(256, 256),
	}
	var loaded := true
	for f in sizes:
		var t := load(TA_DIR + String(f)) as Texture2D
		loaded = loaded and t != null and t.get_width() > 0
	Selftest.check("trade textures load from assets", loaded)
	# Без `.import` свежий worktree физически не видит текстуру: `--import` обязан
	# быть прогнан, а его результат — закоммичен (тот же контракт, что у доски).
	var sidecars := []
	for f in sizes:
		if not FileAccess.file_exists(TA_DIR + String(f) + ".import"):
			sidecars.append(String(f))
	Selftest.check("trade textures ship .import sidecars", sidecars.is_empty())
	var imgs := {}
	var sizes_ok := true
	for f in sizes:
		var img := SuiteContractBoard._ca_img(TA_DIR + String(f))
		sizes_ok = sizes_ok and img != null and img.get_size() == (sizes[f] as Vector2i)
		if img != null:
			imgs[String(f)] = img
	Selftest.check("trade textures exported at declared sizes", sizes_ok)
	# Разнообразие цвета + высокочастотная деталь (волокна/потёртости), иначе
	# гладкий градиент считался бы «текстурой» при одном тоне на всём листе.
	var varied := true
	for f in ["pane_tablet.png", "pocket.png", "slot_seal.png", "cloth_dark.png"]:
		var img: Image = imgs.get(String(f), null)
		if img == null:
			varied = false
			continue
		varied = varied and _distinct(img) >= 24
		varied = varied and SuiteContractBoard._ca_inner(img, "x") > 0.02
	Selftest.check("trade textures are not flat fills", varied)
	# Рваный край бумаги — это альфа-канал, а не нарисованная рамка: 2 px у углов
	# прозрачны, вертикальная полоса тела непрозрачна (§5.3 язык доски).
	var torn := true
	for f in ["pane_tablet.png", "pocket.png"]:
		var img: Image = imgs.get(String(f), null)
		if img == null:
			torn = false
			continue
		var w := img.get_width()
		var h := img.get_height()
		var clean := img.get_pixel(1, 1).a < 0.05 and img.get_pixel(w - 2, 1).a < 0.05
		clean = clean and img.get_pixel(1, h - 2).a < 0.05
		clean = clean and img.get_pixel(w - 2, h - 2).a < 0.05
		var body := true
		for k in 5:
			body = body and img.get_pixel(int(w * 0.5), int(h * (0.3 + 0.1 * k))).a > 0.9
		torn = torn and clean and body
	Selftest.check("trade paper textures are torn cut-outs", torn)
	# Ткань затемнения тайлится на весь экран (§5: «не заливка цветом») — шов обязан
	# не превышать внутренний перепад, иначе на 540×960 видна сетка 256.
	var cloth: Image = imgs.get("cloth_dark.png", null)
	var seam_ok := cloth != null
	if seam_ok:
		for ax in ["x", "y"]:
			seam_ok = seam_ok and (SuiteContractBoard._ca_seam(cloth, String(ax))
				<= SuiteContractBoard._ca_inner(cloth, String(ax)) * 1.6 + 0.02)
	Selftest.check("trade cloth tile is seamless on both axes", seam_ok)


## Число различных цветов на сетке 24×24 с квантом 5 бит на канал: без кванта
## дизеринг PNG посчитался бы разнообразием и пин краснел бы на плоской залике
## неверно, а с квантом плоская заливка даёт ровно 1 цвет. Квант — 32 уровня, а
## не 16: тёмная ткань виньетки (#0d0906…#b3a37c) целиком не влезает в 16
## коробок по каналу, и проверка требовала бы от затемнения bright-палитры.
static func _distinct(img: Image) -> int:
	var seen := {}
	var w := img.get_width()
	var h := img.get_height()
	for i in range(24):
		for j in range(24):
			var c := img.get_pixel(int(w * (0.05 + 0.9 * i / 23.0)),
				int(h * (0.05 + 0.9 * j / 23.0)))
			seen["%d_%d_%d_%d" % [int(c.r * 31), int(c.g * 31), int(c.b * 31),
				int(c.a * 31)]] = true
	return seen.size()


## Узел по пути, где каждый сегмент — ИМЯ в поддереве предыдущего сегмента.
## Буквальный `get_node("Slots/SlotGive_5/Seal")` не годится: раскладка обязана
## содержать ScrollContainer в планшете и ряд-обёртку в доске оффера (план
## Task 8, Interfaces), поэтому между «Slots» и «SlotGive_5» есть уровень.
static func _node(root: Node, path: String) -> Node:
	var cur: Node = root
	for seg in path.split("/"):
		if cur == null:
			return null
		cur = _desc(cur, String(seg))
	return cur


## Поиск по имени: сначала прямые дети, потом глубина — чтобы «Plate» планшета
## не спутать с «Plate» шапки окна.
static func _desc(root: Node, nm: String) -> Node:
	for c in root.get_children():
		if String(c.name) == nm:
			return c
	for c in root.get_children():
		var deep := _desc(c, nm)
		if deep != null:
			return deep
	return null


static func _btn(node: Node, path: String) -> TextureButton:
	return _node(node, path) as TextureButton


## Имя PNG под контролом. Пины сверяют КОНКРЕТНУЮ текстуру: «TextureRect вообще
## чем-то залит» прошла бы и с заглушкой, а §5 требует конкретный комплект.
static func _tex_name(node: Node) -> String:
	var t: Texture2D = null
	if node is TextureRect:
		t = (node as TextureRect).texture
	elif node is TextureButton:
		t = (node as TextureButton).texture_normal
	if t == null:
		return ""
	return String(t.resource_path).get_file()


## Сколько fade-шейдер глушит карман: 0 = живой, 1 = недоступен. -1 означает
## «материала нет вообще» — это тоже отказ проверки, потому что недоступная
## ячейка обязана выглядеть недоступной, а не просто не отвечать на тап.
static func _fade_amount(node: Node) -> float:
	if node == null:
		return -1.0
	var m: Material = (node as CanvasItem).material
	if not (m is ShaderMaterial):
		return -1.0
	return float((m as ShaderMaterial).get_shader_parameter("amount"))


## Плоские заливки в поддереве: ColorRect и Panel с StyleBoxFlat (§5: «никаких
## ColorRect/плоских StyleBoxFlat в видимом слое окна обмена»).
static func _flat_in(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is ColorRect:
			out.append(String(c.name) + " ColorRect")
		elif c is Panel:
			if (c as Control).get_theme_stylebox("panel") is StyleBoxFlat:
				out.append(String(c.name) + " StyleBoxFlat")
		out.append_array(_flat_in(c))
	return out


static func _buttons_in(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is BaseButton:
			out.append(c)
		out.append_array(_buttons_in(c))
	return out


## Тёплый кэш миниатюр: preview_texture отдаёт ImageTexture по попаду в кэш, не
## заводя настоящий SubViewport-рендер. Без этого каждая перерисовка
## конструктора в headless стояла бы по кадру на клетку (тот же приём, что
## suite_sigil_cards.gd:360, только сидировается память, а не PNG на диске).
static func _warm_previews(sm, ids: Array) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for i in ids:
		sm._preview_cache[String(i)] = ImageTexture.create_from_image(img)


## Конструктор N↔M (Task 8, спека §4.1): два планшета инвентаря на текстуре,
## сетки 3 колонки, тап по клетке = ячейка стороны, недоступное — fade, а не
## скрытие. Секция идёт ПОСЛЕ _textures (пинит конкретные PNG комплекта) и
## ПЕРЕД _offer_model (тот обязан оставаться последним: он чистит g._sigil).
static func _builder(g: Game) -> void:
	# Мутации, красящие блок: построить панель друга из entries() вместо
	# peer_entries() (пин 4); снять бейдж копий (5); перепутать стороны тапа —
	# клетка друга кладёт в give (6/7); забыть remove_slot по тапу по полной
	# ячейке (8); рисовать сургуч и в занятой ячейке (9); глушить карман только
	# флагом disabled без fade-материала (10/11/12) или наоборот; не позвать
	# Net.trade_peer_collection из open_builder() (13); снять маршрутизацию
	# trade_peer_collection_result в main (14); звать Net.trade_offer из
	# кнопки конструктора вместо перехода к подтверждению (15); задать ячейке
	# размер 24 px (16, AGENTS.md §12); вернуть ColorRect затемнения или
	# PanelContainer с плоским StyleBoxFlat (17, 18).
	var names := ["builder shows two inventory panes",
		"builder panes are textured tablets", "own grid lists own cards",
		"peer grid lists peer cards not own",
		"grid cell is a pocket with name and copies",
		"tap on own cell adds give slot", "tap on peer cell adds want slot",
		"tap on filled slot removes it", "slot seal fills empty cells",
		"pocket greys out when copies are spent",
		"side cap greys out remaining cells",
		"peer pane fades without collection",
		"builder asks for peer collection",
		"peer collection result fills peer pane",
		"proceed opens confirm from a full draft",
		"builder buttons declare tappable sizes",
		"builder visible layer has no flat controls",
		"window chrome is planks cloth and nail",
		"window chrome closes on the nail"]
	var T = load("res://game/social/trade_ui.gd")
	var ui = g.get("_social_ui")
	if ui == null:
		for n in names:
			Selftest.check(n, false)
		return
	ui.open(0)
	var tr = ui.get("_trade")
	if tr == null:
		for n in names:
			Selftest.check(n, false)
		return
	var sm = g._sigil
	var coll0: Dictionary = sm._server_collection
	var extras0: Array = sm._server_extras
	var prev0: Dictionary = (sm._preview_cache as Dictionary).duplicate()
	var cache0 = g._social.cache
	var threads0 = g._social.threads.duplicate()
	sm.set_catalog([
		{"id": "spark", "set": "fire", "rarity": "common", "ether_cost": 100,
			"recipe": [], "process": "sublimatio", "stage": "albedo",
			"fallback_name": "Искра", "object_type": "object", "seed": 1},
		{"id": "ice", "set": "water", "rarity": "rare", "ether_cost": 150,
			"recipe": [], "process": "sublimatio", "stage": "albedo",
			"fallback_name": "Лёд", "object_type": "object", "seed": 2},
		{"id": "dust", "set": "earth", "rarity": "common", "ether_cost": 50,
			"recipe": [], "process": "calcinatio", "stage": "nigredo",
			"fallback_name": "Пыль", "object_type": "object", "seed": 3},
	], [], "unit-builder")
	# Копий ровно 1 + 3 + 2 = 6: тогда полную сторону можно набрать ЛЕГАЛЬНЫМИ
	# тапами и проверить кап без прямой записи в _offer (пин 11).
	sm._server_collection = {"spark": {"copies": 1, "first_at": ""},
		"ice": {"copies": 3, "first_at": ""},
		"dust": {"copies": 2, "first_at": ""}}
	sm._server_extras = [{"craft_id": "x1", "rarity": "chromatic",
		"llm_name": "Радуга", "crafted_at": "", "seed": 7, "lore": "",
		"ingredients": []}]
	g._social._seed_demo()
	_warm_previews(sm, ["spark", "ice", "dust", "x1", "c-17"])
	tr.call("set_peer_coll", {})
	# Остаток лимита фикстурируем явно: `_list` живёт на слое и после
	# _list_actions содержит remain 0, а гейт §9.2 глушил бы «Предложить» на
	# legitimately собранном черновике (пин 15 краснел бы не за то).
	# base_url гасим ДО open(): enqueue trade_list сливает очередь синхронно
	# (net.gd:460) и уносит из неё запросы коллекции, нашедшие её в _queue из
	# _constructor/_list_actions. Иначе spy посчитал бы чужой слив и пин 13
	# прошёл бы без вызова Net.trade_peer_collection.
	var base0 := String(Net.base_url)
	Net.base_url = ""
	tr.open("dev-b")
	tr._list = {"ok": true, "week_limit": 10, "remain": 7,
		"incoming": [], "outgoing": [], "history": []}

	# Запрос коллекции друга — первая половина провода §4.1: конструктор тянет
	# её сам, игрок не ждёт «пока сам не нажмёт» (шаблон :200).
	var pulls := {"n": 0}
	var spy := func(_r: Dictionary) -> void: pulls["n"] = int(pulls["n"]) + 1
	var pending_before := _pending("trade_peer_collection")
	Net.trade_peer_collection_result.connect(spy)
	tr.open_builder()
	Net.trade_peer_collection_result.disconnect(spy)
	Net.base_url = base0
	var b: Node = tr._body
	var mine := _node(b, "PaneMine")
	var peer := _node(b, "PanePeer")
	Selftest.check("builder shows two inventory panes", mine != null and peer != null
		and _label_has(mine, "Мои карты") and _label_has(peer, "Карты: Николя"))
	Selftest.check("builder panes are textured tablets",
		_node(mine, "Plate") is TextureRect
		and _tex_name(_node(mine, "Plate")) == "pane_tablet.png"
		and _tex_name(_node(peer, "Plate")) == "pane_tablet.png")
	Selftest.check("builder asks for peer collection", not pending_before
		and (int(pulls["n"]) >= 1 or _pending("trade_peer_collection")))
	# §4.4: коллекция друга ещё не пришла — планшет не пустой и не молчаливый,
	# он затемнён и говорит про связь. Живая панель при этом обязана остаться
	# яркой, иначе «затемнить всё» тоже прошла бы проверку.
	Selftest.check("peer pane fades without collection",
		_fade_amount(_node(peer, "Plate")) > 0.5
		and _label_has(peer, "не на связи")
		and _fade_amount(_node(mine, "Plate")) < 0.5)

	# Коллекция друга приходит по проводам main.gd, а не присваиванием
	# _peer_coll: проверка 14 пинит и сигнал, и forwarder, и слой.
	var routed: bool = bool(T.has_script_method("on_peer_collection")) \
		and g.has_method("_on_trade_peer_collection_result")
	if routed:
		Net.trade_peer_collection_result.emit({"ok": true,
			"cards": {"ice": {"copies": 2, "first_at": ""}},
			"extras": [{"craft_id": "c-17", "rarity": "chromatic",
				"llm_name": "Радуга друга"}]})
	Selftest.check("peer collection result fills peer pane", routed
		and not (tr._peer_coll as Dictionary).is_empty())
	Selftest.check("own grid lists own cards",
		_node(b, "CellMine_spark") != null and _node(b, "CellMine_ice") != null
		and _node(b, "CellMine_dust") != null and _node(b, "CellMine_x1") != null)
	# Панель друга — из его коллекции: ice там есть, а spark/dust/x1 (мои) быть
	# не должно. Именно этот пин краснеет, если want-сторону собрать из entries().
	Selftest.check("peer grid lists peer cards not own",
		_node(b, "CellPeer_ice") != null and _node(b, "CellPeer_c-17") != null
		and _node(b, "CellPeer_spark") == null
		and _node(b, "CellPeer_dust") == null)
	var ice := _node(b, "CellMine_ice")
	var ice_nm := _node(ice, "Name")
	var ice_cp := _node(ice, "Copies")
	Selftest.check("grid cell is a pocket with name and copies",
		_tex_name(ice) == "pocket.png" and _node(ice, "Art") is TextureRect
		and ice_nm is Label and (ice_nm as Label).text == "Лёд"
		and ice_cp is Label and (ice_cp as Label).text == "×3")

	var give_n: Callable = func() -> int: return (tr._offer["give"] as Array).size()
	var want_n: Callable = func() -> int: return (tr._offer["want"] as Array).size()
	var was_give: int = give_n.call()
	if ice != null:
		(ice as TextureButton).pressed.emit()
	var g0: Dictionary = ((tr._offer["give"] as Array) as Array)[0] \
		if give_n.call() > 0 else {}
	Selftest.check("tap on own cell adds give slot", was_give == 0
		and give_n.call() == 1 and String(g0.get("card_id", "")) == "ice")
	var was_want: int = want_n.call()
	var peer_c := _node(b, "CellPeer_c-17")
	if peer_c != null:
		(peer_c as TextureButton).pressed.emit()
	var w0: Dictionary = ((tr._offer["want"] as Array) as Array)[0] \
		if want_n.call() > 0 else {}
	Selftest.check("tap on peer cell adds want slot", was_want == 0
		and want_n.call() == 1 and String(w0.get("craft_id", "")) == "c-17"
		and String(w0.get("card_id", "")) == "")
	# Тап по занятой ячейке убирает карту обратно (§4.1) — иначе игрок,
	# положивший не ту карту, не сможет её снять без закрытия окна.
	var slot0 := _node(b, "SlotGive_0")
	if slot0 != null:
		(slot0 as TextureButton).pressed.emit()
	Selftest.check("tap on filled slot removes it", slot0 != null
		and give_n.call() == 0)

	# Пустая ячейка — сургуч, занятая — миниатюра без сургуча.
	var s5 := _node(b, "Slots/SlotGive_5")
	var s5_seal := _node(s5, "Seal")
	var dust := _node(b, "CellMine_dust")
	if dust != null:
		(dust as TextureButton).pressed.emit()
	var s0 := _node(b, "SlotGive_0")
	Selftest.check("slot seal fills empty cells", s5 != null
		and s5_seal is TextureRect and _tex_name(s5_seal) == "slot_seal.png"
		and s0 != null and _node(s0, "Seal") == null
		and _node(s0, "Art") is TextureRect)

	# Вторая копия Пыли легальна (copies 2) и исчерпывает вид: карман глушится
	# fade-ом, а живой карман Льда обязан остаться ярным.
	dust = _node(b, "CellMine_dust")
	if dust != null:
		(dust as TextureButton).pressed.emit()
	var spent := _node(b, "CellMine_dust")
	Selftest.check("pocket greys out when copies are spent",
		give_n.call() == 2 and _fade_amount(spent) > 0.5
		and _fade_amount(_node(spent, "Art")) > 0.5
		and _fade_amount(_node(b, "CellMine_ice")) < 0.5)

	# Полная сторона (лимит 6) — глушится ВЕСЯ своя панель, включая хроматик:
	# у него копии не кончались, отказывает именно лимит ряда.
	for cid in ["spark", "ice", "ice", "ice"]:
		var c := _node(b, "CellMine_" + String(cid))
		if c != null:
			(c as TextureButton).pressed.emit()
	var faded_all: bool = give_n.call() == 6
	for cid in ["spark", "ice", "dust", "x1"]:
		var cc := _node(b, "CellMine_" + String(cid))
		faded_all = faded_all and cc != null and _fade_amount(cc) > 0.5
	Selftest.check("side cap greys out remaining cells", faded_all)

	tr._offer = {"give": [tr.pick("spark", "", 1, "Искра")],
		"want": [tr.pick("ice", "", 2, "Лёд")], "gift": false}
	tr.call("_render")
	# «Предложить» в конструкторе переводит на подтверждение, а НЕ отправляет:
	# отправка — одна кнопка экрана подтверждения (пин «offer sends only on
	# proceed» в _constructor). Остаток в фикстуре ненулевой (remain 7), значит
	# пин краснеет только от «кнопка шлёт Net.trade_offer».
	var offer := _btn(b, "Footer/BtnOffer")
	var offer_live := offer != null and not offer.disabled and int(tr._mode) == 1
	if offer_live:
		offer.pressed.emit()
	Selftest.check("proceed opens confirm from a full draft", offer_live
		and int(tr._mode) == 2)
	tr.call("open_builder")
	b = tr._body
	# §12 AGENTS.md: ни одной кнопки шириной ~24 px. Меряем custom_minimum_size,
	# а не size: в selftest кадр ещё не разложен, and size был бы нулевым всегда.
	var too_small := []
	for n in _buttons_in(b):
		var ms: Vector2 = (n as Control).custom_minimum_size
		if ms.x < 48.0 or ms.y < 40.0:
			too_small.append(String(n.name))
	Selftest.check("builder buttons declare tappable sizes", too_small.is_empty())
	Selftest.check("builder visible layer has no flat controls",
		_flat_in(b).is_empty())
	# Шапка и затемнение окна: ткань вместо ColorRect, доски вместо плоской
	# панели, заклёпка-кнопка вместо «Назад». Пишется по всему экрану: снимает
	# и ColorRect затемнения, и PanelContainer с темой-стилем. `dim` вынесен в
	# переменную и проверен на null: прямой каст при ещё плоском окне уронил бы
	# всю сюиту ошибкой вместо чистой RED-падения проверки.
	var screen: Control = tr.get("_screen")
	var pre_open: bool = tr.is_open()
	var close_btn := _btn(screen, "Head/BtnClose")
	var dim := _node(screen, "Dim") as TextureRect
	Selftest.check("window chrome is planks cloth and nail",
		_tex_name(_node(screen, "Head/Plate")) == "board_planks.png"
		and _tex_name(close_btn) == "nail_brass.png"
		and _tex_name(dim) == "cloth_dark.png"
		and dim != null and dim.stretch_mode == TextureRect.STRETCH_TILE
		and _flat_in(screen).is_empty())
	if close_btn != null:
		close_btn.pressed.emit()
	Selftest.check("window chrome closes on the nail", pre_open and not tr.is_open())
	tr.call("close")
	sm.set_catalog([], [], "")
	sm._server_collection = coll0
	sm._server_extras = extras0
	sm._preview_cache = prev0
	g._social.cache = cache0
	g._social.threads = threads0

## уникальность хроматика и панель «Прошу» из коллекции друга. Секция чисто-API:
## слой-модель живёт на detached-экземпляре T.new(g), экран SocialUI здесь не
## нужен — own-panel-гейты читают g._sigil напрямую. Вызывается ПОСЛЕДНЕЙ, а
## фикстура _server_collection обязательно возвращается в покой, иначе красными
## упадут SuiteJuice/SuiteSaveSync/SuiteSyncPackageNet/SuiteContractBoard.
static func _offer_model(g: Game) -> void:
	# Мутации, красящие блок: снять гейт лимита стороны в add_slot (первый кейс
	# краснеет на 6+1 — седьмая ячейка clay легальна по копиям, но запрещена
	# капом); обнулить remove_slot (второй); снять гейт копий вида (третий);
	# читать копии не из живых коллекций, а из словаря ячейки, или не строить
	# peer_entries из _peer_coll (четвёртый).
	var T = load("res://game/social/trade_ui.gd")
	var tu = T.new(g)
	var sm = g._sigil
	# Копий вида — 8 (R16): тогда шесть ячеек легальны, а седьмая отказана ИМЕННО
	# лимитом стороны (6), а не дефицитом копий (8) — иначе кап не отличался бы от
	# нехватки. metal: одна копия — вторая ячейка того же вида отказана по копиям.
	sm._server_collection = {"clay": {"copies": 8, "first_at": ""},
		"metal": {"copies": 1, "first_at": ""}}
	for i in range(6):
		tu.add_slot("give", tu.pick("clay", "", 2, "Глина"))
	Selftest.check("slot cap enforced at six",
		int(tu._offer["give"].size()) == 6
		and not tu.add_slot("give", tu.pick("clay", "", 2, "Глина")))
	tu.remove_slot("give", 0)
	Selftest.check("slot add and remove roundtrip",
		int(tu._offer["give"].size()) == 5
		and tu.add_slot("give", tu.pick("clay", "", 2, "Глина")))
	# metal в коллекции одна копия: первая ячейка проходит, вторая — отказ по
	# копиям. first_ok обязан быть истинен, иначе пин краснел бы и на заглушке.
	tu._offer["give"].clear()
	var first_ok: bool = tu.add_slot("give", tu.pick("metal", "", 1, "Металл"))
	Selftest.check("pocket refused when copies spent",
		first_ok and not tu.add_slot("give", tu.pick("metal", "", 1, "Металл")))
	# Панель «Прошу» читает коллекцию ДРУГА, а не свою (спека §4.1): без
	# peer_coll пусто, с ней — позиции друга (хроматик по llm_name, вид по copies).
	var empty_before: bool = tu.peer_entries().is_empty()
	tu.set_peer_coll({"cards": {"ice": {"copies": 3, "first_at": ""}},
		"extras": [{"craft_id": "c-17", "rarity": "chromatic",
			"llm_name": "Радуга друга"}]})
	var pe: Array = tu.peer_entries()
	var chroma := {}
	var view := {}
	for e in pe:
		if String(e.get("craft_id", "")) == "c-17":
			chroma = e
		if String(e.get("card_id", "")) == "ice":
			view = e
	# Хроматик всегда последний экземпляр; вид с 3 копиями — не последний.
	Selftest.check("peer pane reads peer collection", empty_before and pe.size() == 2
		and String(chroma.get("display_name", "")) == "Радуга друга"
		and bool(chroma.get("is_last", false))
		and not bool(view.get("is_last", true)))
	# want-гейт читает копии ИЗ КОЛЛЕКЦИИ ДРУГА (не из своей и не из словаря
	# ячейки): у друга одна копия ice — вторая ячейка запрещена.
	tu._offer["give"].clear()
	tu.set_peer_coll({"cards": {"ice": {"copies": 1, "first_at": ""}}, "extras": []})
	var w_first: bool = tu.add_slot("want", tu.pick("ice", "", 1, "Лёд"))
	Selftest.check("want gate uses peer copies",
		w_first and not tu.add_slot("want", tu.pick("ice", "", 1, "Лёд")))
	# При пустом кэше гейт best-effort: источник истины сервер (§3, он ответит 409
	# peer_lacks), а блокировка запрещала бы собирать оффер офлайн. Мутация
	# «возвращать 0 вместо -1» краснит ровно эту проверку.
	tu._offer["want"].clear()
	tu.set_peer_coll({})
	Selftest.check("want gate best-effort without peer collection",
		tu.add_slot("want", tu.pick("ice", "", 1, "Лёд")))
	# На сетку уезжают РОВНО селекторы: is_last/display_name — клиентский UX-слой,
	# сервер их не ждёт (§2.2). keys().size() == 2 ловит и просковзание записи
	# pick() целиком, и лишнюю пару ключей.
	var wire: Array = T._wire_items([tu.pick("clay", "", 8, "Глина")])
	Selftest.check("wire items carry only selectors", wire.size() == 1
		and (wire[0] as Dictionary).keys().size() == 2
		and String(wire[0].get("card_id", "")) == "clay"
		and String(wire[0].get("craft_id", "")) == ""
		and not wire[0].has("is_last") and not wire[0].has("display_name"))
	# Возврат общего состояния в покой — до follow-up-сюит (selftest.gd:163-166).
	sm._server_collection = {}

