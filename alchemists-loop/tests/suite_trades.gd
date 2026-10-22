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
