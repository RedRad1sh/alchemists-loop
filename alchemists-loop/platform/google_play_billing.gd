extends RefCounted
class_name GooglePlayBillingAdapter

# Адаптер намеренно не ссылается на addon напрямую: проект запускается в
# редакторе и в RuStore-сборке без Google-классов. После установки
# GodotGooglePlayBilling v3 его BillingClient/GodotGooglePlayBilling можно
# зарегистрировать как Android singleton или autoload — фасад подхватит оба
# варианта и поддерживает старые имена методов.

signal initialized(available: bool, message: String)
signal purchase_received(purchase: Dictionary)
signal purchase_failed(code: String, message: String)
signal purchases_restored(purchases: Array)

var _client = null
var _connected := false
var _sku_pending := ""

func provider_id() -> String:
	return "google_play"

func is_available() -> bool:
	return _client != null

func initialize() -> void:
	_client = _find_client()
	if _client == null:
		initialized.emit(false, "Google Play Billing plugin не подключён")
		return
	_connect_signals()
	var call := _call_first(["start_connection", "startConnection", "connect", "initialize"], [])
	if bool(call.get("called", false)):
		# Некоторые версии плагина присылают connected позже, другие уже готовы.
		_connected = true
		initialized.emit(true, "Google Play Billing готов")
	else:
		initialized.emit(false, "У плагина нет метода запуска соединения")

func purchase(store_sku: String) -> bool:
	if _client == null:
		purchase_failed.emit("provider_unavailable", "Google Play Billing недоступен")
		return false
	_sku_pending = store_sku
	for args in [[store_sku], [store_sku, "inapp"]]:
		var call := _call_first(["purchase", "purchase_product", "buy"], args)
		if bool(call.get("called", false)):
			var result = call.get("result")
			if result is Dictionary and _looks_like_purchase(result as Dictionary):
				_on_purchase(result as Dictionary)
			return true
	purchase_failed.emit("purchase_method_missing", "В плагине Google Play не найден метод покупки")
	return false

func restore() -> bool:
	if _client == null:
		return false
	for args in [[], ["inapp"], ["inapp", true]]:
		var call := _call_first(["query_purchases", "queryPurchases", "get_purchases", "getPurchases"], args)
		if bool(call.get("called", false)):
			var result = call.get("result")
			if result is Array:
				_on_purchases(result as Array)
			elif result is Dictionary:
				_on_purchases(_extract_purchase_array(result as Dictionary))
			return true
	return false

func consume(token: String, sku: String = "") -> bool:
	if _client == null:
		return false
	var result := _call_first(["consume_purchase", "consumePurchase", "consume"], [token])
	if not bool(result.get("called", false)) and sku != "":
		result = _call_first(["consume_purchase", "consumePurchase", "consume"], [sku])
	return bool(result.get("called", false))

func acknowledge(token: String) -> bool:
	if _client == null:
		return false
	return bool(_call_first(["acknowledge_purchase", "acknowledgePurchase", "acknowledge"], [token]).get("called", false))

func _find_client():
	for singleton_name in ["GodotGooglePlayBilling", "BillingClient", "GooglePlayBilling"]:
		if Engine.has_singleton(singleton_name):
			return Engine.get_singleton(singleton_name)
		for node_path in ["/root/BillingClient", "/root/GodotGooglePlayBilling", "/root/GooglePlayBilling"]:
			var tree := Engine.get_main_loop() as SceneTree
			if tree == null:
				continue
			var node: Node = tree.root.get_node_or_null(node_path.trim_prefix("/root/"))
			if node != null:
				return node
	return null

func _connect_signals() -> void:
	for signal_name in ["purchases_updated", "purchase_updated", "on_purchase", "purchase_success"]:
		_connect_signal(signal_name, Callable(self, "_on_purchase_signal"))
	for signal_name in ["purchase_error", "billing_error", "on_error"]:
		_connect_signal(signal_name, Callable(self, "_on_error_signal"))
	for signal_name in ["connected", "billing_connected"]:
		_connect_signal(signal_name, Callable(self, "_on_connected"))

func _connect_signal(signal_name: String, callback: Callable) -> void:
	if _client == null or not _client.has_signal(signal_name):
		return
	if not _client.is_connected(signal_name, callback):
		_client.connect(signal_name, callback)

func _on_connected(_value = null) -> void:
	_connected = true
	initialized.emit(true, "Google Play Billing готов")

func _on_error_signal(code = "", message = "") -> void:
	purchase_failed.emit(str(code), str(message))

func _on_purchase_signal(value = null, _extra = null) -> void:
	if value is Array:
		_on_purchases(value as Array)
	elif value is Dictionary:
		_on_purchase(value as Dictionary)
	else:
		purchase_failed.emit("invalid_purchase", "Плагин вернул неизвестный формат покупки")

func _on_purchases(items: Array) -> void:
	var normalized: Array = []
	for item in items:
		if item is Dictionary:
			var purchase := _normalize_purchase(item as Dictionary)
			if not purchase.is_empty():
				normalized.append(purchase)
				purchase_received.emit(purchase)
	purchases_restored.emit(normalized)

func _on_purchase(raw: Dictionary) -> void:
	var purchase := _normalize_purchase(raw)
	if purchase.is_empty():
		purchase_failed.emit("invalid_purchase", "Не удалось разобрать покупку Google Play")
		return
	purchase_received.emit(purchase)

func _normalize_purchase(raw: Dictionary) -> Dictionary:
	var sku := String(raw.get("sku", raw.get("product_id", raw.get("productId", ""))))
	if sku == "":
		sku = _first_product_id(raw)
	if sku == "":
		sku = _sku_pending
	var token := String(raw.get("purchase_token", raw.get("purchaseToken", raw.get("token", ""))))
	if sku == "" or token == "":
		return {}
	return {
		"provider": provider_id(),
		"sku": sku,
		"token": token,
		"state": _normalize_state(raw),
		"acknowledged": bool(raw.get("is_acknowledged", raw.get("acknowledged", false))),
		"raw": raw,
	}

# Матрица Google Play Billing: purchaseState 0 = purchased, 1 = pending,
# 2 = declined. Отсутствующее или незнакомое значение приводим к "rejected":
# отсутствие поля не должно выглядеть как подтверждённая покупка, поэтому
# здесь нет дефолта-«1». Фасад начисляет только строку "purchased".
func _normalize_state(raw: Dictionary) -> String:
	var value = null
	if raw.has("purchase_state"):
		value = raw["purchase_state"]
	elif raw.has("purchaseState"):
		value = raw["purchaseState"]
	else:
		return "rejected"
	# Литеральные паттерны match в Godot 4 сверяют typeof(value) с типом литерала
	# до сравнения значений, а равенства BOOL↔INT у движка нет: false/true/null/
	# строка сюда не попадают и уходят в `_` -> "rejected".
	match value:
		0:
			return "purchased"
		1:
			return "pending"
		2:
			return "rejected"
		_:
			# Не-целочисленное или неизвестное состояние: подтверждающей
			# покупки нет, отклоняем вместо угадывания.
			return "rejected"

func _extract_purchase_array(raw: Dictionary) -> Array:
	for key in ["purchases", "items", "data"]:
		if raw.get(key) is Array:
			return raw[key] as Array
	return []

# Плагин v2 несёт sku восстановленной покупки в массиве product_ids, одиночного
# поля нет. При restore _sku_pending пуст, поэтому без чтения массива покупка
# превращалась бы в «нераспознанную».
func _first_product_id(raw: Dictionary) -> String:
	for key in ["product_ids", "productIds"]:
		var ids = raw.get(key, null)
		if (ids is Array or ids is PackedStringArray) and not ids.is_empty():
			var first := String(ids[0])
			if first != "":
				return first
	return ""

func _looks_like_purchase(raw: Dictionary) -> bool:
	return String(raw.get("purchase_token", raw.get("purchaseToken", raw.get("token", "")))) != ""

func _call_first(methods: Array, args: Array) -> Dictionary:
	if _client == null:
		return {"called": false}
	for method_name in methods:
		if _client.has_method(method_name):
			return {"called": true, "result": _client.callv(method_name, args)}
	return {"called": false}
