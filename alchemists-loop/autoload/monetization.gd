extends Node

const GooglePlayBillingAdapterScript = preload("res://platform/google_play_billing.gd")
const RuStorePayAdapterScript = preload("res://platform/rustore_pay.gd")
const AdsAdapterScript = preload("res://platform/ads_adapter.gd")

# Причины «валидатор не смог ответить» — зеркало серверного
# RECEIPT_UNAVAILABLE_REASONS (discovery-server/server/server.py). Это НЕ отказ
# по конкретному чеку, и решение «начислять или нет» здесь другое.
const RECEIPT_UNAVAILABLE_REASONS := ["vendor_validation_disabled", "vendor_validation_not_implemented"]
# Потолок очереди проверок чеков: restore теоретически может принести сколько
# угодно непотреблённых чеков, а каждый — это HTTP-запрос. Сверх потолка чек
# просто не уходит на проверку и будет повторен на следующем restore.
const MAX_QUEUED_RECEIPT_CHECKS := 16

# Monetization — фасад магазина и рекламы. Игровой код знает только SKU из
# data/monetization.json и сигналы этого файла. Начисление идемпотентно:
# повторный onResume/restore по тому же purchase token ничего не выдаёт.
#
# Порядок обработки покупки (T22):
#   0) сервер проверяет чек (Net.receipt_verify → receipt_verify_result);
#   1) _grant_product; 2) consume/acknowledge с ЧТЕНИЕМ результата;
#   3) только после подтверждённого магазина — журнал UserData.mark_processed +
#   снятие pending. Если магазин не подтвердил — журнал не пишем, а отметка
#   «уже начислено» (I-1) живёт в секции granted того же неуязвимого журнала,
#   поэтому переживает и снятие pending, и wipe: restore повторит только шаг 2.

signal initialized(store_id: String, billing_available: bool, ads_available: bool)
signal purchase_started(product_id: String)
signal purchase_succeeded(product_id: String, provider: String)
signal purchase_failed(product_id: String, code: String, message: String)
signal rewarded_available(placement_id: String, available: bool)
signal rewarded_started(placement_id: String)
signal rewarded_finished(placement_id: String, reward: Dictionary)

var store_id := "standalone"
var provider_label := "локальный режим"
var catalog: Dictionary = {}
var ads_config: Dictionary = {}
var billing_available := false
var ads_available := false
var _adapter: RefCounted = null
var _ads: RefCounted = null
var _game: Node = null
var _booted := false
var _pending_product := ""
var _pending_placement := ""
# T22: очереди покупок, для которых ждём ответ /api/receipt/verify. Порядок
# совпадает с порядком запросов (очередь Net сериальная), поэтому ответ без
# receipt_hash корректно снимает голову очереди, а ответ с hash — свой чек.
var _verify_requests: Array = []

func _ready() -> void:
	_load_catalog()
	call_deferred("_boot")

func _boot() -> void:
	store_id = App.store_id
	provider_label = App.provider_label()
	# Net — autoload, идущий после Monetization в project.godot: в _ready() его
	# ещё нет, а call_deferred("_boot") уже есть. Подключаемся именно здесь.
	if Net != null and not Net.receipt_verify_result.is_connected(_on_receipt_verify_result):
		Net.receipt_verify_result.connect(_on_receipt_verify_result)
	_ads = AdsAdapterScript.new()
	_ads.rewarded_completed.connect(_on_rewarded_completed)
	_ads.ad_failed.connect(_on_ad_failed)
	# interstitial_closed слушателя больше не имеет: раньше здесь стояла подписка
	# на пустую лямбду, которая лишь маскировала отсутствие interstitial-вызова.
	# Частота показа учитывается в show_interstitial() через
	# UserData.set_last_interstitial_at — на закрытие ролика реагировать нечего.
	if store_id == App.STORE_GOOGLE_PLAY:
		_adapter = GooglePlayBillingAdapterScript.new()
	elif store_id == App.STORE_RUSTORE:
		_adapter = RuStorePayAdapterScript.new()
	if _adapter != null:
		_adapter.initialized.connect(_on_billing_initialized)
		_adapter.purchase_received.connect(_on_purchase_received)
		_adapter.purchase_failed.connect(_on_billing_failed)
		_adapter.purchases_restored.connect(_on_purchases_restored)
		if store_id == App.STORE_RUSTORE:
			_adapter.initialize(OS.get_environment("RUSTORE_APPLICATION_ID"), OS.get_environment("RUSTORE_DEEPLINK_SCHEME"))
		else:
			_adapter.initialize()
	else:
		billing_available = false
	configure_consent()
	_booted = true
	initialized.emit(store_id, billing_available, ads_available)

func _load_catalog() -> void:
	catalog.clear()
	ads_config = {}
	var file := FileAccess.open("res://data/monetization.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var raw: Dictionary = parsed
	for item in raw.get("products", []):
		if item is Dictionary and String(item.get("id", "")) != "":
			catalog[String(item["id"])] = item
	ads_config = raw.get("ads", {}) if raw.get("ads", {}) is Dictionary else {}

func configure_consent() -> void:
	if _ads == null:
		return
	var consent := UserData.get_consent("ads_personalized")
	# Передача согласия адаптеру: он сам решает, быть ли рекламе вообще
	# (AdsAdapterScript.consent_allows_ads — единственно «granted»), и гасит при
	# отказе и клиента, и debug-стаб. До бута идём через initialize(): только он
	# приносит текущий store_id. Позже (смена режима в Лавке) — через
	# set_consent(): тот же перевызов, но без переподключения SDK, когда значение
	# не менялось.
	if _booted:
		_ads.set_consent(consent)
	else:
		_ads.initialize(store_id, consent)
	ads_available = _ads.is_available()
	if not AdsAdapterScript.consent_allows_ads(consent):
		# F4 (раунд правки U18): при отзыве согласия сторона адаптера гасит свой
		# _placement_pending (initialize, ветка отказа), а фасад раньше оставлял
		# _pending_placement висеть — и первый же поздний ad_failed разметил бы
		# уже отменённый показ через rewarded_available(..., false) в _on_ad_failed.
		# Снимаем здесь же, где гасится реклама.
		_pending_placement = ""
	if _booted:
		initialized.emit(store_id, billing_available, ads_available)

func bind_game(game: Node) -> void:
	_game = game

func get_products() -> Array:
	return catalog.values()

func get_product(product_id: String) -> Dictionary:
	return catalog.get(product_id, {})

func status_text() -> String:
	if store_id == App.STORE_STANDALONE:
		return "Локальный режим: подключи Android-плагин для покупок"
	if not billing_available:
		return "%s: платёжный плагин не подключён" % provider_label
	return "%s: магазин готов" % provider_label

func is_product_owned(product_id: String) -> bool:
	return UserData.is_product_owned(product_id)

func purchase(product_id: String) -> bool:
	var product := get_product(product_id)
	if product.is_empty():
		purchase_failed.emit(product_id, "unknown_sku", "Товар не найден в каталоге")
		return false
	if String(product.get("type", "")) == "non_consumable" and is_product_owned(product_id):
		purchase_failed.emit(product_id, "already_owned", "Товар уже восстановлен")
		return false
	if _adapter == null or not billing_available:
		purchase_failed.emit(product_id, "provider_unavailable", status_text())
		return false
	var sku_map: Dictionary = product.get("store_sku", {})
	var sku := String(sku_map.get(store_id, ""))
	if sku == "":
		purchase_failed.emit(product_id, "sku_not_configured", "SKU не настроен для %s" % provider_label)
		return false
	_pending_product = product_id
	UserData.set_pending_purchase(product_id, {"provider": store_id, "sku": sku, "started_at": Time.get_unix_time_from_system()})
	purchase_started.emit(product_id)
	Analytics.track("purchase_start", {"sku": product_id, "store": store_id, "type": String(product.get("type", ""))})
	return bool(_adapter.purchase(sku))

# Отказной путь покупки: снять запись из purchases.pending. Pending пишется на
# старте (purchase) и на успехе снимается в _finish_purchase; без этого хелпера
# каждая из веток отказа оставляла запись навсегда (мусор, который больше никто
# не читает). Снятие безопасно: отметка «уже начислено» с U17/I-1 живёт в
# отдельной секции granted журнала покупок, а не в pending, поэтому вторая
# выдача им не открывается. Пустой product_id — это ветки _on_purchase_received
# (purchase_pending / purchase_rejected / unknown_sku), где товар ещё не
# опознан: чистить там нечего, а выдумывать ключ нельзя.
func _drop_pending_if_any(product_id: String) -> void:
	if product_id == "":
		return
	UserData.clear_pending_purchase(product_id)

func restore() -> void:
	# Путь повтора незакрытых покупок — только restore (удалённый до бута
	# _apply_pending_entitlements ничего не начислял и был ложной точкой входа):
	# незавершённые покупки не начисляются без подтверждённого callback от стора,
	# restore приносит чек заново, и он проходит весь цикл с серверной проверкой.
	if _adapter != null and billing_available:
		_adapter.restore()

func show_rewarded(placement_id: String) -> bool:
	var placement := _find_placement(placement_id)
	if placement.is_empty():
		rewarded_available.emit(placement_id, false)
		return false
	# Реклама разрешена только при «granted»: раньше гейт проверял лишь «unknown»
	# и отказ («denied») считался согласием — ровно то, за что прилетает бан в EEA.
	if not AdsAdapterScript.consent_allows_ads(UserData.get_consent("ads_personalized")):
		rewarded_available.emit(placement_id, false)
		return false
	var cap := int(ads_config.get("rewarded_daily_cap", 5))
	if UserData.rewarded_count_for_today() >= cap:
		rewarded_available.emit(placement_id, false)
		return false
	var cooldown := float(ads_config.get("rewarded_cooldown_sec", 150))
	var last := float(UserData.get_ads_state().get("last_rewarded_at", 0.0))
	if Time.get_unix_time_from_system() - last < cooldown:
		rewarded_available.emit(placement_id, false)
		return false
	if _ads == null or not _ads.is_available():
		rewarded_available.emit(placement_id, false)
		return false
	_pending_placement = placement_id
	rewarded_started.emit(placement_id)
	Analytics.track("rewarded_start", {"placement": placement_id, "store": store_id})
	var shown := bool(_ads.show_rewarded(placement_id))
	if not shown:
		_pending_placement = ""
	return shown

func can_show_interstitial() -> bool:
	# Про согласие interstitial раньше не спрашивал вовсе. Межэкранная реклама
	# показывается без прямого действия игрока, поэтому consent-гейт здесь обязателен
	# тем более, что guardrails частоты его не касаются.
	if not AdsAdapterScript.consent_allows_ads(UserData.get_consent("ads_personalized")):
		return false
	if UserData.is_product_owned("remove_ads"):
		return false
	# Не показываем рекламу в первых сессиях/днях: это guardrail, а не
	# единственный cooldown. Значения приходят из каталога, чтобы их можно было
	# изменить без правок игрового цикла.
	var minimum_sessions := int(ads_config.get("minimum_session_number", 3))
	if UserData.session_count() < minimum_sessions:
		return false
	var minimum_age_days := float(ads_config.get("minimum_account_age_days", 2))
	if UserData.install_age_seconds() < minimum_age_days * 86400.0:
		return false
	if UserData.session_count() <= 1 and UserData.session_seconds() < 600.0:
		return false
	var cooldown := float(ads_config.get("interstitial_cooldown_sec", 1500))
	return Time.get_unix_time_from_system() - UserData.last_interstitial_at() >= cooldown

func show_interstitial(context: String = "navigation") -> bool:
	if not can_show_interstitial() or _ads == null or not _ads.is_available():
		return false
	var shown := bool(_ads.show_interstitial())
	if shown:
		# F4 (раунд правки U18): track — внутрь успешной ветки. На реальном клиенте
		# show_interstitial() может вернуть false по method_missing
		# (ads_adapter.gd:147-148), и прежний порядок считал бы показ, которого не
		# было, при неразрешённом кулдауне — спам на каждую смену вкладки.
		Analytics.track("interstitial_start", {"context": context, "store": store_id})
		UserData.set_last_interstitial_at(Time.get_unix_time_from_system())
	return shown

func _find_placement(placement_id: String) -> Dictionary:
	for item in ads_config.get("placements", []):
		if item is Dictionary and String(item.get("id", "")) == placement_id:
			return item
	return {}

func _on_billing_initialized(available: bool, _message: String) -> void:
	billing_available = available
	if _booted:
		initialized.emit(store_id, billing_available, ads_available)
	if available:
		restore()

func _on_billing_failed(code: String, message: String) -> void:
	purchase_failed.emit(_pending_product, code, message)
	_drop_pending_if_any(_pending_product)
	Analytics.track("purchase_fail", {"sku": _pending_product, "store": store_id, "code": code})
	_pending_product = ""

func _on_purchases_restored(items: Array) -> void:
	# Сигнал уже обработал каждый элемент; отдельная аналитика нужна только для
	# отладки восстановления и не содержит токенов.
	Analytics.track("purchases_restore", {"count": items.size(), "store": store_id})

func _on_purchase_received(purchase: Dictionary) -> void:
	var provider := String(purchase.get("provider", store_id))
	var sku := String(purchase.get("sku", ""))
	# Токен нормализуем на входе: ключ локального журнала и отпечаток, который
	# сверяет сервер, должны считаться от одного ряда байтов (сервер тоже
	# strip'ует токен перед SHA-256).
	var token := String(purchase.get("token", "")).strip_edges()
	# Единый контракт адаптеров: state — нормализованная строка
	# "purchased" / "pending" / "rejected". Начисляем только "purchased";
	# отсутствующее или незнакомое значение всегда трактуем как отказ,
	# никогда как подтверждение (Google Play: purchaseState 0 = purchased,
	# 1 = pending, 2 = declined — числовые состояния адаптер не пропускает).
	var state := String(purchase.get("state", ""))
	if state == "pending":
		purchase_failed.emit("", "purchase_pending", "Покупка ещё не подтверждена магазином")
		return
	if state != "purchased":
		purchase_failed.emit("", "purchase_rejected", "Магазин не подтвердил покупку")
		return
	var product_id := _product_id_for_sku(sku)
	if product_id == "":
		purchase_failed.emit("", "unknown_sku", "Покупка пришла с неизвестным SKU")
		return
	if UserData.has_processed_purchase(provider, token, sku):
		return
	if token == "":
		purchase_failed.emit(product_id, "missing_token", "У покупки нет идентификатора")
		_drop_pending_if_any(product_id)
		return
	# T22 шаг 0: до начисления чек проверяет сервер (Google Play / RuStore
	# вердикт), а не только клиент. Ответ приходит асинхронно — очередь Net
	# сериальная, продолжение в _on_receipt_verify_result.
	if _verify_requests.size() >= MAX_QUEUED_RECEIPT_CHECKS:
		# Не начинаем проверку, которую не сможем завершить: чек никуда не
		# денется — restore принесёт его повторно при следующем onResume.
		purchase_failed.emit(product_id, "receipt_queue_full", "Очередь проверки чеков заполнена — повторим при следующем запуске")
		_drop_pending_if_any(product_id)
		return
	if _verify_request_index(provider, sku, token) >= 0:
		return  # адаптер прислал тот же чек дважды, пока ждём ответ
	_verify_requests.append({
		"provider": provider, "sku": sku, "token": token, "product_id": product_id,
	})
	Net.receipt_verify(UserData.get_or_create_device_id(), provider, sku, token)

func _verify_request_index(provider: String, sku: String, token: String) -> int:
	for i in range(_verify_requests.size()):
		var item: Dictionary = _verify_requests[i]
		if (String(item.get("provider", "")) == provider
				and String(item.get("sku", "")) == sku
				and String(item.get("token", "")) == token):
			return i
	return -1

func _take_verify_request(echo_hash: String) -> Dictionary:
	# Ответ с receipt_hash коррелируется по отпечатку (его считает и сервер); без
	# него (offline/4xx/5xx net.gd тело не отдаёт) — снимается голова очереди:
	# запросы уходят и возвращаются строго по одному, порядок сохранён.
	if echo_hash != "":
		for i in range(_verify_requests.size()):
			var item: Dictionary = _verify_requests[i]
			if String(item.get("token", "")).sha256_text() == echo_hash:
				_verify_requests.remove_at(i)
				return item
		return {}
	if _verify_requests.is_empty():
		return {}
	return _verify_requests.pop_front()

func _on_receipt_verify_result(result: Dictionary) -> void:
	var request := _take_verify_request(String(result.get("receipt_hash", "")))
	if request.is_empty():
		# Ответ без запроса (дубликат, ответ после отмены) или отпечаток не из
		# нашей очереди: начислять по нему не за что.
		return
	var product_id := String(request["product_id"])
	var is_debug := OS.is_debug_build()
	if not receipt_grant_allowed(result, is_debug):
		var reason := String(result.get("reason", ""))
		if reason == "":
			reason = String(result.get("message", "сервер не ответил"))
		purchase_failed.emit(product_id, "receipt_not_verified", "Сервер не подтвердил покупку: %s" % reason)
		_drop_pending_if_any(product_id)
		_pending_product = ""
		return
	_finish_purchase(request, not (result.get("verified", false) == true))

func _finish_purchase(request: Dictionary, unverified: bool) -> void:
	var provider := String(request["provider"])
	var sku := String(request["sku"])
	var token := String(request["token"])
	var product_id := String(request["product_id"])
	var product := get_product(product_id)
	var product_type := String(product.get("type", ""))
	# Шаг 1 — начисление.
	if not _purchase_already_granted(provider, sku, token, product_id):
		if not _grant_product(product_id):
			purchase_failed.emit(product_id, "grant_failed", "Не удалось начислить покупку")
			# Начисления не было — pending-запись это просто мусор, снимаем.
			_drop_pending_if_any(product_id)
			return
		_mark_purchase_granted(provider, sku, token, product_id)
	# Шаг 2 — подтверждение магазина с ЧТЕНИЕМ результата.
	var confirmed := _confirm_purchase_with_store(token, sku, product_type == "consumable")
	_report_purchase(product_id, unverified, confirmed)
	# Шаг 3 — журнал «полностью завершено» и снятие pending только после
	# подтверждённого потребления. Иначе consumable зависал: локально чек
	# «закрыт», restore его больше не отдаст, а в магазине он не потреблён.
	# M-1: результат записи журнала читается. Если строка processed НЕ записана,
	# покупку не считаем закрытой: pending остаётся (restore повторит consume), а
	# granted-отметка не снимается (mark_processed_purchase стирает её только при
	# успешной записи). Порядок один: сначала успешная запись журнала, только затем
	# снятие pending.
	var closed := false
	if confirmed:
		closed = UserData.mark_processed_purchase(provider, token, sku)
		if closed:
			UserData.clear_pending_purchase(product_id)
		else:
			push_warning("Monetization: журнал покупок не записан — покупку не считаем закрытой, повторим при следующем запуске.")
	# Товар игрок уже получил (или получит при ретрае), поэтому успех
	# показываем в обеих ветках; различает их только журнал.
	purchase_succeeded.emit(product_id, provider)
	# «purchase_success» — только действительно закрытая покупка (журнал записан);
	# и неподтверждённый магазин, и упавшая запись журнала — это unconfirmed.
	Analytics.track("purchase_unconfirmed" if not closed else "purchase_success", {
		"sku": product_id, "store": provider, "type": product_type,
	})
	_pending_product = ""

func _receipt_validator_unavailable(result: Dictionary) -> bool:
	if result.get("offline", false) == true:
		return true
	if String(result.get("reason", "")) in RECEIPT_UNAVAILABLE_REASONS:
		return true
	# net.gd тело 4xx/5xx не разбирает — остаётся только «HTTP <код>». 5xx:
	# валидатор не смог ответить; 4xx: отказ по существу запроса (неизвестный
	# SKU, чек с другого устройства) — это не «недоступность».
	return String(result.get("error", "")).begins_with("HTTP 5")

func receipt_grant_allowed(result: Dictionary, is_debug: bool) -> bool:
	# Решение «можно ли начислять» по ответу валидатора — без побочных эффектов
	# и без обращения к состоянию, чтобы покрыть её selftest'ом в чистом виде.
	#
	# Сервер недоступен / гейт выключен ≠ «разрешить выдачу»: иначе вся проверка
	# обходится молчанием бэкенда. Но и отбирать у игрока покупку без работающего
	# бэкенда нельзя, поэтому: в отладочной сборке (OS.is_debug_build) чек
	# начисляем с честным предупреждением в статусе, в релизной — только
	# verified: true. Настоящий отказ магазина (ok:false без недоступности)
	# запрещает выдачу в любой сборке.
	if result.get("ok", false) == true and result.get("verified", false) == true:
		return true
	return is_debug and _receipt_validator_unavailable(result)

func _purchase_already_granted(provider: String, sku: String, token: String, _product_id: String) -> bool:
	# I-1: отметка о начислении живёт в неуязвимом журнале (секция granted), а не
	# в затираемом pending и не в processed: журнал означает «полностью завершено»,
	# а здесь как раз хвост consume не закрыт. Ключ — тот же provider/token/sku,
	# поэтому product_id в расчёте не участвует.
	return UserData.is_purchase_granted(provider, token, sku)

func _mark_purchase_granted(provider: String, sku: String, token: String, _product_id: String) -> void:
	# Пишем отметку в журнал; pending остаётся только с provider/sku/started_at
	# (как было до U17) — granted/token_hash из него убраны вместе с переносом.
	# R-1: результат записи читаем ради наблюдаемости (тот же принцип, что в M-1).
	# Порядок не меняем: перенос метки ДО начисления перевёл бы риск из «двойная
	# выдача» в «потерянная оплата». Отказ записи не откатывает начисление, но
	# сбой обязан быть различим по месту, а не только общим warning'ом UserData.
	if not UserData.mark_purchase_granted(provider, token, sku):
		push_warning("Monetization: отметка о начислении не записана на диск; при гибели процесса покупка может начислиться повторно.")

func _confirm_purchase_with_store(token: String, sku: String, consumable: bool) -> bool:
	# Честно о сигнале: bool у адаптеров означает «метод плагина нашёлся и был
	# вызван» (_call_first в google_play_billing.gd / rustore_pay.gd), а не
	# «магазин подтвердил списание» — код ответа плагина теряется в адаптере.
	# Порядок это чинит ровно в тех границах, что даёт текущий контракт;
	# проброс кода магазина — следующий шаг (меняет контракт адаптеров).
	if _adapter == null:
		return false
	if consumable:
		return _adapter.consume(token, sku) == true
	if _adapter.has_method("acknowledge"):
		# non-consumable Google Play без acknowledge рефаундится через 3 дня.
		return _adapter.acknowledge(token) == true
	# У RuStore-адаптера acknowledge нет: там consume = confirm_two_step_purchase.
	return _adapter.consume(token, sku) == true

func _report_purchase(product_id: String, unverified: bool, confirmed: bool) -> void:
	if _game == null:
		return
	var product := get_product(product_id)
	var text := "Покупка применена: %s." % String(product.get("title", product_id))
	if unverified:
		text += " Сервер проверки чеков не ответил: выдача только в отладочной сборке."
	if not confirmed:
		text += " Магазин не подтвердил списание — повторим при следующем запуске."
	_game._engine.status_text = text
	_game._engine._refresh()


func _product_id_for_sku(sku: String) -> String:
	for product_id in catalog:
		var product: Dictionary = catalog[product_id]
		var sku_map: Dictionary = product.get("store_sku", {})
		if String(sku_map.get(store_id, "")) == sku or sku == product_id:
			return product_id
	return ""

func _grant_product(product_id: String) -> bool:
	var product := get_product(product_id)
	if product.is_empty():
		return false
	if _game == null:
		# На старте приложения restore может прийти раньше Main._ready. Храним
		# чек как pending и выдадим товар после bind_game.
		return false
	var reward: Dictionary = product.get("reward", {})
	if reward.has("ether"):
		_game._engine._grant_ether(int(reward["ether"]), "purchase")
	if reward.has("sage_gold"):
		_game._engine.sage_gold += int(reward["sage_gold"])
	if reward.has("theme"):
		_game._home._cosmetic_theme = String(reward["theme"])
		_game._home._theme_custom_on = false
		_game._home._apply_cosmetic()
	if bool(reward.get("remove_ads", false)):
		UserData.set_owned_product(product_id, true)
	_game._engine.status_text = "Покупка применена: %s." % String(product.get("title", product_id))
	_game._engine._refresh()
	_game._saves._save_game()
	return true

func _on_rewarded_completed(placement_id: String) -> void:
	var placement := _find_placement(placement_id)
	if placement.is_empty():
		return
	UserData.record_rewarded_view()
	var reward: Dictionary = placement.get("reward", {})
	if _game != null:
		if reward.has("ether"):
			_game._engine._grant_ether(int(reward["ether"]), "rewarded")
		if reward.has("source_boost_seconds"):
			_game._engine._source_boost_until = maxf(_game._engine._source_boost_until, Time.get_unix_time_from_system()) + float(reward["source_boost_seconds"])
		_game._engine.status_text = "Награда рекламы получена: %s." % String(placement.get("title", placement_id))
		_game._engine._refresh()
		_game._saves._save_game()
	rewarded_finished.emit(placement_id, reward)
	Analytics.track("rewarded_finish", {"placement": placement_id, "store": store_id})
	_pending_placement = ""

func _on_ad_failed(code: String, message: String) -> void:
	Analytics.track("ads_error", {"format": "rewarded", "code": code})
	rewarded_available.emit(_pending_placement, false)
	_pending_placement = ""
