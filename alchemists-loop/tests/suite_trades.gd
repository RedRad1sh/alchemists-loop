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


static func _entry(g: Game) -> void:
	# Мутации: убрать кнопку из _friend_row (первые два кейса); убрать z_index 21
	# или add_to_group (четвёртый); снять elif-ветку в _close_top_modal (пятый —
	# Esc гасит SocialUI); убрать _trade_close() в open/close (шестой — слой
	# переживает закрытие экрана с чужим _peer); снять connect/forwarder в main
	# (седьмой — _list не приходит).
	var names := ["swap row for friend", "swap hidden for spirit",
		"swap press opens trade", "trade layer z and group",
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
	# `ui` пришёл через get() и потому Variant: `:=` не смог бы вывести тип из
	# ui._screen (нет заданного типа), а без этого блок не компилируется вообще.
	var before: int = ui._screen.get_child_count()
	if swap != null:
		swap.pressed.emit()
	var tr = ui.get("_trade")
	Selftest.check("swap press opens trade", tr != null and tr.is_open()
		and ui._screen.get_child_count() > before)
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
