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


static func _methods(_g: Game) -> void:
	var held := HoldingNet.new()
	for m in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift", "trade_list"]:
		Selftest.check("net has " + m, held.has_method(m))
	held.free()


static func _shapes(_g: Game) -> void:
	var held := HoldingNet.new()
	# Все четыре слота селектора заполнены РАЗНЫМИ значениями намеренно: здесь
	# пинится маппинг «аргумент метода → ключ body», а не валидность запроса
	# (инвариант XOR держит сервер §4, а сторону выбирает пикер Task 9). Пустой
	# слот не ловит ни перестановку give/want, ни фиксированную пустую строку
	# в net.gd.
	var q := HoldingNet.one(held, "trade_offer",
		["me", "peer", "spark", "gc1", "ice", "wc1"])
	Selftest.check("trade offer POST body", q != {}
		and String(q.get("path", "")) == "/trade/offer"
		and q.get("body", {}) == {"device_id": "me", "to": "peer",
			"give_card_id": "spark", "give_craft_id": "gc1",
			"want_card_id": "ice", "want_craft_id": "wc1"})
	q = HoldingNet.one(held, "trade_accept", ["me", 12])
	Selftest.check("trade accept POST body", q != {}
		and String(q.get("path", "")) == "/trade/accept"
		and q.get("body", {}) == {"device_id": "me", "id": 12})
	q = HoldingNet.one(held, "trade_cancel", ["me", 12])
	Selftest.check("trade cancel POST body", q != {}
		and String(q.get("path", "")) == "/trade/cancel"
		and q.get("body", {}) == {"device_id": "me", "id": 12})
	q = HoldingNet.one(held, "trade_gift", ["me", "peer", "spark", "gc1"])
	Selftest.check("trade gift POST body", q != {}
		and String(q.get("path", "")) == "/trade/gift"
		and q.get("body", {}) == {"device_id": "me", "to": "peer",
			"card_id": "spark", "craft_id": "gc1"})
	q = HoldingNet.one(held, "trade_list", ["dev 1"])
	Selftest.check("trade list GET path", q != {}
		and String(q.get("path", "")) == "/trade/list?device_id=dev%201"
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
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift", "trade_list"]:
		var sig := String(kind) + "_result"
		want[sig] = {"for": String(kind)}
		if Net.has_signal(sig):
			var cb: Callable = func(r: Dictionary) -> void: got[sig] = r
			cbs.append([sig, cb])
			Net.connect(StringName(sig), cb)
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift", "trade_list"]:
		Net._dispatch({"kind": kind}, want[String(kind) + "_result"])
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift", "trade_list"]:
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
	# copies < 1 (второй/третий), забыть ветку extras (четвёртый/пятый), not
	# disabled у want в gift-режиме (шестой), вызвать Net.trade_offer из
	# open_confirm() вместо кнопки (седьмой и восьмой: в первом падает потому,
	# что сигнал уже прилетел до нажатия, во втором — fired становится 2, а
	# запрос уже лежит в очереди до нажатия), снять маппинг detail (девятый).
	# Страж has_script_method — он же и RED: удалить любой из семи новых методов
	# значит получить все девять падений сразу, а не обрезанную сюиту.
	var names := ["pick contract is four fields", "pick single copy is last",
		"pick third copy is not last", "pick chromatic is always last",
		"entries list owned cards and extras", "gift mode kills want slot",
		"confirm warns before offer", "offer sends only on proceed",
		"offer failure shows server copy"]
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
	var ch: Dictionary = tu.pick("", "x1", 0, "Радуга")
	Selftest.check("pick chromatic is always last", bool(ch.get("is_last", false))
		and String(ch.get("card_id", "")) == "" and String(ch.get("craft_id", "")) == "x1")

	var sm = g._sigil
	sm.set_catalog([
		{"id": "spark", "set": "fire", "rarity": "common", "ether_cost": 100,
			"recipe": [], "process": "sublimatio", "stage": "albedo",
			"fallback_name": "Искра", "object_type": "object", "seed": 1},
		{"id": "ice", "set": "water", "rarity": "rare", "ether_cost": 150,
			"recipe": [], "process": "sublimatio", "stage": "albedo",
			"fallback_name": "Лёд", "object_type": "object", "seed": 2},
	], [], "unit-trade")
	sm._server_collection = {"spark": {"copies": 1, "first_at": ""},
		"ice": {"copies": 3, "first_at": ""}}
	sm._server_extras = [{"craft_id": "x1", "rarity": "chromatic",
		"llm_name": "Радуга", "crafted_at": "", "seed": 7, "lore": "",
		"ingredients": []}]
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
	var list: Array = tr.entries()
	var by_card := {}
	for e in list:
		var key := String(e.get("card_id", "")) + "|" + String(e.get("craft_id", ""))
		by_card[key] = e
	Selftest.check("entries list owned cards and extras", list.size() == 3
		and bool(by_card.get("spark|", {}).get("is_last", false))
		and String(by_card.get("spark|", {}).get("display_name", "")) == "Искра"
		and not bool(by_card.get("ice|", {}).get("is_last", true))
		and String(by_card.get("|x1", {}).get("display_name", "")) == "Радуга")

	tr.open("dev-b")
	tr.open_builder()
	tr._offer = {"give": tu.pick("spark", "", 1, "Искра"),
		"want": tu.pick("ice", "", 3, "Лёд"), "gift": false}
	tr._mode = 1
	tr.call("_render")
	var want_btn := _button_named(tr._body, "Лёд")
	tr._offer["gift"] = true
	tr.call("_render")
	var want_btn2 := _button_named(tr._body, "Лёд")
	Selftest.check("gift mode kills want slot", want_btn != null and want_btn2 != null
		and not want_btn.disabled and want_btn2.disabled)

	var fired := {"n": 0}
	var cb := func(_r: Dictionary) -> void: fired["n"] = int(fired["n"]) + 1
	Net.trade_offer_result.connect(cb)
	tr._offer["gift"] = false
	tr.open_confirm()
	Selftest.check("confirm warns before offer", tr._mode == 2
		and _label_has(tr._body, "последн") and int(fired["n"]) == 0)
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
	tr.call("close")
	# Фикстура живёт в общем g._sigil, а после SuiteTrades идут SuiteJuice,
	# SuiteSaveSync, SuiteSyncPackageNet и SuiteContractBoard
	# (tests/selftest.gd:163-166): возвращаем состояние покоя той же идиомой,
	# которой чистит себя SuiteSigilCards.
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
