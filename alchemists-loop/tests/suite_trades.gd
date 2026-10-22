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
	var want_btn := _button_named(tr._body, "Лёд")
	# Подарок включает _toggle_gift(), он же и обнуляет want. Присваивать
	# _offer["gift"] = true напрямую нельзя: проверка описывала бы состояние,
	# которого игрок не может получить, а настоящий путь (слот «не выбрана» и
	# disabled) оставался бы без покрытия.
	tr.call("_toggle_gift")
	var none_btn := _button_named(tr._body, "не выбрана")
	Selftest.check("gift mode kills want slot", want_btn != null and none_btn != null
		and not want_btn.disabled and none_btn.disabled
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
	# другом A, уходит другу B одним нажатием «Дальше».
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
	var next := _button_named(tr._body, "Дальше")
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
	g._social.cache = social_cache0
	g._social.threads = social_threads0


## Модель оффера списками (Task 6): гейт лимита стороны, гейт копий вида,
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
	# Возврат общего состояния в покой — до follow-up-сюит (selftest.gd:163-166).
	sm._server_collection = {}

