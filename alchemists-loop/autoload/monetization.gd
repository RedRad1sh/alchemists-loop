extends Node

const GooglePlayBillingAdapterScript = preload("res://platform/google_play_billing.gd")
const RuStorePayAdapterScript = preload("res://platform/rustore_pay.gd")
const AdsAdapterScript = preload("res://platform/ads_adapter.gd")

# Monetization — фасад магазина и рекламы. Игровой код знает только SKU из
# data/monetization.json и сигналы этого файла. Начисление идемпотентно:
# повторный onResume/restore по тому же purchase token ничего не выдаёт.

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

func _ready() -> void:
	_load_catalog()
	call_deferred("_boot")

func _boot() -> void:
	store_id = App.store_id
	provider_label = App.provider_label()
	_ads = AdsAdapterScript.new()
	_ads.rewarded_completed.connect(_on_rewarded_completed)
	_ads.ad_failed.connect(_on_ad_failed)
	_ads.interstitial_closed.connect(func() -> void: pass)
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
	_ads.initialize(store_id, consent)
	ads_available = _ads.is_available()
	if _booted:
		initialized.emit(store_id, billing_available, ads_available)

func bind_game(game: Node) -> void:
	_game = game
	_apply_pending_entitlements()

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

func restore() -> void:
	if _adapter != null and billing_available:
		_adapter.restore()

func show_rewarded(placement_id: String) -> bool:
	var placement := _find_placement(placement_id)
	if placement.is_empty():
		rewarded_available.emit(placement_id, false)
		return false
	if UserData.get_consent("ads_personalized") == "unknown":
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
	Analytics.track("interstitial_start", {"context": context, "store": store_id})
	var shown := bool(_ads.show_interstitial())
	if shown:
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
	Analytics.track("purchase_fail", {"sku": _pending_product, "store": store_id, "code": code})
	_pending_product = ""

func _on_purchases_restored(items: Array) -> void:
	# Сигнал уже обработал каждый элемент; отдельная аналитика нужна только для
	# отладки восстановления и не содержит токенов.
	Analytics.track("purchases_restore", {"count": items.size(), "store": store_id})

func _on_purchase_received(purchase: Dictionary) -> void:
	var provider := String(purchase.get("provider", store_id))
	var sku := String(purchase.get("sku", ""))
	var token := String(purchase.get("token", ""))
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
		return
	# В production receipt должен быть проверен сервером Google/RuStore до этой
	# точки. Фасад принимает нормализованный callback SDK; серверную валидацию
	# подключаем через backend-плагин/ALCHEMY_RECEIPT_VALIDATION_URL на этапе
	# релиза, не храним секреты стор в клиенте.
	if not _grant_product(product_id):
		purchase_failed.emit(product_id, "grant_failed", "Не удалось начислить покупку")
		return
	UserData.mark_processed_purchase(provider, token, sku)
	UserData.clear_pending_purchase(product_id)
	var product := get_product(product_id)
	if String(product.get("type", "")) == "consumable":
		_adapter.consume(token, sku)
	else:
		_adapter.acknowledge(token) if _adapter.has_method("acknowledge") else _adapter.consume(token, sku)
	purchase_succeeded.emit(product_id, provider)
	Analytics.track("purchase_success", {"sku": product_id, "store": provider, "type": String(product.get("type", ""))})
	_pending_product = ""

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

func _apply_pending_entitlements() -> void:
	# Неполные покупки остаются видимыми в UserData, но не начисляются без
	# нового подтверждённого callback от стора. Это исключает повторную выдачу.
	pass

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
