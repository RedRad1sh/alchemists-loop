extends Node

# App — единая информация о варианте Android-сборки и жизненном цикле.
# Платёжные и рекламные SDK не подключаются напрямую к игровым экранам:
# Game общается с фасадом Monetization, а фасад выбирает провайдера по build
# feature (google_play/rustore) или по ALCHEMY_STORE для staging.

signal application_paused
signal application_resumed
signal consent_changed

const STORE_STANDALONE := "standalone"
const STORE_GOOGLE_PLAY := "google_play"
const STORE_RUSTORE := "rustore"

var store_id := STORE_STANDALONE
var _was_paused := false

func _ready() -> void:
	UserData.ensure_install_metadata()
	store_id = _detect_store()

func _detect_store() -> String:
	var override := OS.get_environment("ALCHEMY_STORE").strip_edges().to_lower()
	if override in [STORE_GOOGLE_PLAY, STORE_RUSTORE, STORE_STANDALONE]:
		return override
	if OS.has_feature("rustore"):
		return STORE_RUSTORE
	if OS.has_feature("google_play") or OS.has_feature("googleplay"):
		return STORE_GOOGLE_PLAY
	return STORE_STANDALONE

func is_android() -> bool:
	return OS.get_name() == "Android"

func is_ru_build() -> bool:
	return store_id == STORE_RUSTORE

func is_google_build() -> bool:
	return store_id == STORE_GOOGLE_PLAY

func provider_label() -> String:
	match store_id:
		STORE_GOOGLE_PLAY:
			return "Google Play"
		STORE_RUSTORE:
			return "RuStore"
	return "локальный режим"

func analytics_consent() -> String:
	return UserData.get_consent("analytics")

func ads_consent() -> String:
	return UserData.get_consent("ads_personalized")

func set_consent(analytics_allowed: bool, personalized_ads_allowed: bool) -> void:
	UserData.set_consent("analytics", "granted" if analytics_allowed else "denied")
	UserData.set_consent("ads_personalized", "granted" if personalized_ads_allowed else "denied")
	consent_changed.emit()
	if is_instance_valid(Analytics):
		Analytics.configure_consent()
	if is_instance_valid(Monetization):
		Monetization.configure_consent()

func consent_is_decided() -> bool:
	return analytics_consent() != "unknown" and ads_consent() != "unknown"

func privacy_policy_url() -> String:
	var env := OS.get_environment("ALCHEMY_PRIVACY_URL").strip_edges()
	if env != "":
		return env
	return String(ProjectSettings.get_setting("application/config/privacy_policy_url", ""))

func open_privacy_policy() -> bool:
	var url := privacy_policy_url()
	if url == "":
		return false
	return OS.shell_open(url) == OK

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_was_paused = true
		application_paused.emit()
		if is_instance_valid(Analytics):
			Analytics.session_end("background")
		if is_instance_valid(UserData):
			UserData.save_now()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _was_paused:
			_was_paused = false
			application_resumed.emit()
			if is_instance_valid(Analytics):
				Analytics.session_start("resume")
			if is_instance_valid(Monetization):
				Monetization.restore()
