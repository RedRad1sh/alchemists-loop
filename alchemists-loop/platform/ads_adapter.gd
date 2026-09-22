extends RefCounted
class_name AdsAdapter

# Единый тонкий слой над AdMob (Google Play) и Яндекс Mobile Ads (RuStore).
# Имена singleton/method допускают варианты community-плагинов; отсутствие
# плагина — нормальный режим для desktop и selftest, а не ошибка игры.

signal initialized(available: bool, message: String)
signal rewarded_completed(placement_id: String)
signal ad_failed(code: String, message: String)
signal interstitial_closed

var _client = null
var _store_id := "standalone"
var _placement_pending := ""
var _stub := false

func initialize(store_id: String, personalized_consent: String) -> void:
	_store_id = store_id
	_stub = OS.get_environment("ALCHEMY_ADS_STUB") == "1" or OS.get_cmdline_user_args().has("--ads-stub")
	if personalized_consent == "unknown":
		initialized.emit(false, "Ожидается согласие на рекламу")
		return
	_client = _find_client(store_id)
	if _client == null and not _stub:
		initialized.emit(false, "Рекламный плагин не подключён")
		return
	if _client != null:
		_connect_signals()
		_call_first(["initialize", "init", "load_rewarded", "loadRewarded"], [])
	initialized.emit(true, "Реклама готова" if _client != null else "Реклама в debug-режиме")

func is_available() -> bool:
	return _stub or _client != null

func show_rewarded(placement_id: String) -> bool:
	if _stub:
		_placement_pending = placement_id
		call_deferred("_complete_stub_reward")
		return true
	if _client == null:
		ad_failed.emit("provider_unavailable", "Rewarded-реклама недоступна")
		return false
	_placement_pending = placement_id
	var call := _call_first(["show_rewarded", "show_rewarded_ad", "showRewarded", "showRewardedAd"], [])
	if not bool(call.get("called", false)):
		ad_failed.emit("method_missing", "В рекламном плагине не найден rewarded-метод")
		return false
	return true

func show_interstitial() -> bool:
	if _client == null or _stub:
		return false
	var call := _call_first(["show_interstitial", "showInterstitial"], [])
	return bool(call.get("called", false))

func _complete_stub_reward() -> void:
	rewarded_completed.emit(_placement_pending)
	_placement_pending = ""

func _find_client(store_id: String):
	var names := ["YandexMobileAds", "YandexAds", "AdMob", "GodotAdMob", "MobileAds"]
	if store_id == "google_play":
		names = ["AdMob", "GodotAdMob", "MobileAds", "YandexMobileAds"]
	elif store_id == "rustore":
		names = ["YandexMobileAds", "YandexAds", "MobileAds", "AdMob"]
	for singleton_name in names:
		if Engine.has_singleton(singleton_name):
			return Engine.get_singleton(singleton_name)
	return null

func _connect_signals() -> void:
	for signal_name in ["rewarded", "rewarded_ad_rewarded", "on_rewarded", "rewarded_closed"]:
		_connect_signal(signal_name, Callable(self, "_on_rewarded_signal"))
	for signal_name in ["ad_failed_to_show", "ad_failed", "on_ad_failed"]:
		_connect_signal(signal_name, Callable(self, "_on_failed_signal"))
	for signal_name in ["interstitial_closed", "on_interstitial_closed"]:
		_connect_signal(signal_name, Callable(self, "_on_interstitial_closed"))

func _connect_signal(signal_name: String, callback: Callable) -> void:
	if _client == null or not _client.has_signal(signal_name):
		return
	if not _client.is_connected(signal_name, callback):
		_client.connect(signal_name, callback)

func _on_rewarded_signal(_value = null, _extra = null) -> void:
	rewarded_completed.emit(_placement_pending)
	_placement_pending = ""

func _on_failed_signal(code = "", message = "") -> void:
	ad_failed.emit(str(code), str(message))
	_placement_pending = ""

func _on_interstitial_closed(_value = null) -> void:
	interstitial_closed.emit()

func _call_first(methods: Array, args: Array) -> Dictionary:
	if _client == null:
		return {"called": false}
	for method_name in methods:
		if _client.has_method(method_name):
			return {"called": true, "result": _client.callv(method_name, args)}
	return {"called": false}
