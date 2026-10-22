extends RefCounted
class_name SuiteTrades
# S2 «Обмен картами» (клиент): net-слой, подслой TradeUI внутри SocialUI,
# пикер последней копии, недельный лимит и бейдж. Герметично: в selftest Net
# сливает очередь в offline (SelftestMode), поэтому сборку запроса смотрим на
# подставном NetBase с погашенным _send_next (шаблон suite_resonance_net.gd:5
# `const NetBase := preload(...)`), а маршрутизацию — прямым Net._dispatch.
# Мутации, красящие этот блок: удалить метод/сигнал в net.gd, сменить path или
# поле body, снять `trade_*.emit(parsed)` в _dispatch.

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


static func _shapes(_g: Game) -> void:
	var held := HoldingNet.new()
	var q := HoldingNet.one(held, "trade_offer",
		["me", "peer", "spark", "", "ice", ""])
	Selftest.check("trade offer POST body", q != {}
		and String(q.get("path", "")) == "/trade/offer"
		and q.get("body", {}) == {"device_id": "me", "to": "peer",
			"give_card_id": "spark", "give_craft_id": "",
			"want_card_id": "ice", "want_craft_id": ""})
	q = HoldingNet.one(held, "trade_accept", ["me", 12])
	Selftest.check("trade accept POST body", q != {}
		and String(q.get("path", "")) == "/trade/accept"
		and q.get("body", {}) == {"device_id": "me", "id": 12})
	q = HoldingNet.one(held, "trade_cancel", ["me", 12])
	Selftest.check("trade cancel POST body", q != {}
		and String(q.get("path", "")) == "/trade/cancel"
		and q.get("body", {}) == {"device_id": "me", "id": 12})
	q = HoldingNet.one(held, "trade_gift", ["me", "peer", "spark", ""])
	Selftest.check("trade gift POST body", q != {}
		and String(q.get("path", "")) == "/trade/gift"
		and q.get("body", {}) == {"device_id": "me", "to": "peer",
			"card_id": "spark", "craft_id": ""})
	q = HoldingNet.one(held, "trade_list", ["dev 1"])
	Selftest.check("trade list GET path", q != {}
		and String(q.get("path", "")) == "/trade/list?device_id=dev%201"
		and not q.has("body"))


static func _dispatch_routes(_g: Game) -> void:
	# Каждый kind обязан прийти ровно в свой сигнал: ловит снятие ветки
	# `trade_*.emit(parsed)` в Net._dispatch. Connect по StringName — чтобы
	# несуществующий сигнал не ронял билд на RED.
	var fired := {}
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift", "trade_list"]:
		var sig := String(kind) + "_result"
		if Net.has_signal(sig):
			Net.connect(StringName(sig),
				func(_r: Dictionary) -> void: fired[sig] = int(fired.get(sig, 0)) + 1)
	Net._dispatch({"kind": "trade_offer"}, {})
	Net._dispatch({"kind": "trade_accept"}, {})
	Net._dispatch({"kind": "trade_cancel"}, {})
	Net._dispatch({"kind": "trade_gift"}, {})
	Net._dispatch({"kind": "trade_list"}, {})
	for kind in ["trade_offer", "trade_accept", "trade_cancel", "trade_gift", "trade_list"]:
		Selftest.check("dispatch emits " + String(kind),
			int(fired.get(String(kind) + "_result", 0)) == 1)
