extends RefCounted
class_name RuStorePayAdapter

# Адаптер официального RuStore Godot Pay. Поддерживает текущий
# RuStoreGodotPayClient и legacy-совместимый singleton RustoreBilling. В
# проекте нет жёсткой зависимости от классов SDK, поэтому редактор и GP-билд
# собираются без RuStore-плагина.

signal initialized(available: bool, message: String)
signal purchase_received(purchase: Dictionary)
signal purchase_failed(code: String, message: String)
signal purchases_restored(purchases: Array)

var _client = null
var _app_id := ""
var _deeplink_scheme := ""
var _sku_pending := ""

func provider_id() -> String:
	return "rustore"

func is_available() -> bool:
	return _client != null

func initialize(app_id: String = "", deeplink_scheme: String = "") -> void:
	_app_id = app_id if app_id != "" else OS.get_environment("RUSTORE_APPLICATION_ID")
	_deeplink_scheme = deeplink_scheme if deeplink_scheme != "" else OS.get_environment("RUSTORE_DEEPLINK_SCHEME")
	_client = _find_client()
	if _client == null:
		initialized.emit(false, "RuStore Pay plugin не подключён")
		return
	_connect_signals()
	var call := _call_first(["init", "initialize"], [_app_id, _deeplink_scheme])
	if not bool(call.get("called", false)):
		# Новая версия создаёт уже настроенный client через get_instance.
		call = {"called": true}
	initialized.emit(true, "RuStore Pay готов")

func purchase(store_sku: String) -> bool:
	if _client == null:
		purchase_failed.emit("provider_unavailable", "RuStore Pay недоступен")
		return false
	_sku_pending = store_sku
	var payload := {"product_id": store_sku, "productId": store_sku, "developer_payload": "alchemists-loop"}
	for args in [[store_sku], [payload], [store_sku, payload]]:
		var call := _call_first(["purchase_product", "purchaseProduct", "purchase", "purchase_two_step", "purchaseTwoStep"], args)
		if bool(call.get("called", false)):
			var result = call.get("result")
			if result is Dictionary and _looks_like_purchase(result as Dictionary):
				_on_purchase(result as Dictionary)
			return true
	purchase_failed.emit("purchase_method_missing", "В плагине RuStore не найден метод покупки")
	return false

func restore() -> bool:
	if _client == null:
		return false
	var call := _call_first(["get_purchases", "getPurchases", "purchases"], [])
	if not bool(call.get("called", false)):
		return false
	var result = call.get("result")
	var items: Array = []
	if result is Array:
		items = result as Array
	elif result is Dictionary:
		for key in ["items", "purchases", "data"]:
			if result.get(key) is Array:
				items = result[key] as Array
				break
	_on_purchases(items)
	return true

func consume(purchase_id: String, developer_payload: String = "") -> bool:
	if _client == null:
		return false
	var payload := {"payload": developer_payload}
	var result := _call_first(["confirm_two_step_purchase", "confirmTwoStepPurchase", "confirm_purchase", "confirmPurchase", "consume_purchase", "consumePurchase"], [purchase_id, payload])
	if not bool(result.get("called", false)):
		result = _call_first(["confirm_two_step_purchase", "confirmTwoStepPurchase", "confirm_purchase", "confirmPurchase", "consume_purchase", "consumePurchase"], [purchase_id])
	return bool(result.get("called", false))

func _find_client():
	for singleton_name in ["RustoreBilling", "RuStoreGodotPay", "RuStoreGodotPayClient", "RuStoreBilling"]:
		if Engine.has_singleton(singleton_name):
			return Engine.get_singleton(singleton_name)
	for node_path in ["/root/RustoreBilling", "/root/RuStoreGodotPay", "/root/RuStoreGodotPayClient"]:
		if Engine.get_main_loop() is SceneTree:
			var node := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(node_path.trim_prefix("/root/"))
			if node != null:
				return node
	return null

func _connect_signals() -> void:
	for signal_name in ["rustore_purchase_product", "purchase_success", "on_purchase_success", "on_purchase_two_step_success"]:
		_connect_signal(signal_name, Callable(self, "_on_purchase_signal"))
	for signal_name in ["rustore_get_purchases", "get_purchases_success", "on_get_purchases_success"]:
		_connect_signal(signal_name, Callable(self, "_on_restore_signal"))
	for signal_name in ["rustore_purchase_error", "purchase_failure", "on_purchase_failure"]:
		_connect_signal(signal_name, Callable(self, "_on_error_signal"))

func _connect_signal(signal_name: String, callback: Callable) -> void:
	if _client == null or not _client.has_signal(signal_name):
		return
	if not _client.is_connected(signal_name, callback):
		_client.connect(signal_name, callback)

func _on_purchase_signal(value = null, _extra = null) -> void:
	if value is Dictionary:
		_on_purchase(value as Dictionary)
	else:
		purchase_failed.emit("invalid_purchase", "RuStore вернул неизвестный формат покупки")

func _on_restore_signal(value = null, _extra = null) -> void:
	if value is Array:
		_on_purchases(value as Array)
	elif value is Dictionary:
		var items: Array = value.get("items", value.get("purchases", []))
		_on_purchases(items)

func _on_error_signal(code = "", message = "") -> void:
	purchase_failed.emit(str(code), str(message))

func _on_purchase(raw: Dictionary) -> void:
	var purchase := _normalize_purchase(raw)
	if purchase.is_empty():
		purchase_failed.emit("invalid_purchase", "Не удалось разобрать покупку RuStore")
		return
	purchase_received.emit(purchase)

func _on_purchases(items: Array) -> void:
	var normalized: Array = []
	for item in items:
		if item is Dictionary:
			var purchase := _normalize_purchase(item as Dictionary)
			if not purchase.is_empty():
				normalized.append(purchase)
				purchase_received.emit(purchase)
	purchases_restored.emit(normalized)

func _normalize_purchase(raw: Dictionary) -> Dictionary:
	var sku := String(raw.get("product_id", raw.get("productId", raw.get("sku", raw.get("product", _sku_pending)))))
	var token := String(raw.get("purchase_id", raw.get("purchaseId", raw.get("invoice_id", raw.get("invoiceId", raw.get("subscription_token", raw.get("subscriptionToken", "")))))))
	if sku == "" or token == "":
		return {}
	return {
		"provider": provider_id(),
		"sku": sku,
		"token": token,
		"purchase_id": token,
		"state": _normalize_state(raw),
		"raw": raw,
	}

# Контракт RuStore Pay: PAID = оплачено, PENDING = ожидает завершения
# внешней оплаты, CANCELED/CANCELLED = отменена; в RuStore Store API
# встречается BOUGHT/PURCHASED как синоним оплаченной. Неизвестный или
# отсутствующий статус → "rejected": прежний дефолт "PAID" выдавал товар
# при пустом поле, теперь неясные состояния никогда не подтверждают.
func _normalize_state(raw: Dictionary) -> String:
	var value := ""
	for key in ["purchase_state", "purchaseState", "state"]:
		if raw.has(key):
			value = String(raw[key]).to_upper()
			break
	match value:
		"PAID", "BOUGHT", "PURCHASED":
			return "purchased"
		"PENDING":
			return "pending"
		_:
			return "rejected"

func _looks_like_purchase(raw: Dictionary) -> bool:
	return String(raw.get("purchase_id", raw.get("purchaseId", raw.get("invoice_id", raw.get("invoiceId", ""))))) != ""

func _call_first(methods: Array, args: Array) -> Dictionary:
	if _client == null:
		return {"called": false}
	for method_name in methods:
		if _client.has_method(method_name):
			return {"called": true, "result": _client.callv(method_name, args)}
	return {"called": false}
