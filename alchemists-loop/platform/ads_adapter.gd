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
# T23: носитель согласия у адаптера свой. Плагину другой носитель не передать
# (NPA-флаг появится вместе с реальным плагином — см. consent_allows_ads), а без
# своего поля адаптер не пережил бы смену согласия без перезапуска.
var _consent := "unknown"
# Награда текущего показа: выдана ли она сигналом «rewarded». Нужна, чтобы
# связка «rewarded -> rewarded_closed» не дала двойного начисления, а закрытие
# без награды (скип видео) не считалось досмотренным роликом.
var _reward_earned := false

# Единственный режим, в котором реклама крутится вообще: "granted". unknown и
# denied запрещены и на инициализации, и на показе — этого требует собственный
# ТЗ (docs/android/PLUGIN_SETUP.md §4 «Реклама и согласия» и smoke-чек §5
# «Consent unknown/denied: реклама не стартует»).
# ОСОЗНАННОЕ ОТСТУПЛЕНИЕ: вместо «персонализированная реклама выключена, но
# NPA-формат идёт» здесь полный запрет. Имена API реального плагина
# (setNPA / RequestConfiguration.isNonPersonalizedAd и т. п.) сверить не с чем, а
# выдуманная передача флага была бы той же дыркой с комментарием «мы передали».
# NPA-режим реализуем, когда плагин появится и его контракт можно проверить.
static func consent_allows_ads(consent: String) -> bool:
	return consent == "granted"

# Стаб живёт только в отладочной сборке. Иначе release-APK получает бесплатные
# rewarded до дневного капа через `adb shell am start --esa args,--ads-stub`,
# чего docs/android/PLUGIN_SETUP.md §4 прямо запрещает («Стаб доступен только
# отладочной сборке»).
# cmdline_args — Variant намеренно: аргументы приходят PackedStringArray'ем
# (OS.get_cmdline_user_args), а конвертера в Array у него нет (to_array() в Godot 4
# не существует), поэтому контракт читается итерацией, которая годится обоим
# контейнерам. selftest зовёт тот же предикт с обычным Array-литералом.
static func stub_requested(cmdline_args: Variant, env_value: String, is_debug: bool) -> bool:
	if not is_debug:
		return false
	if env_value == "1":
		return true
	for arg in cmdline_args:
		if String(arg) == "--ads-stub":
			return true
	return false

static func payload_awards_reward(value: Variant) -> bool:
	# T23: Dictionary-payload у AdMob-подобных несёт reward (amount/type) и может
	# сказать «не заработано» явно — тогда награду не начисляем. При null или
	# не-Dictionary единственный верифицируемый признак — ИМЯ сигнала: решаем по
	# нему. Поля amount/type не читаем намеренно: размер награды берётся из
	# каталога (Monetization._find_placement), а не из того, что прислал SDK.
	if value is Dictionary:
		return ((value as Dictionary).get("earned", true) != false)
	return true

func initialize(store_id: String, personalized_consent: String) -> void:
	_store_id = store_id
	# Согласие сохраняем до любого возврата — оно нужно set_consent(), чтобы
	# доинициализироваться позже без перезапуска.
	_consent = personalized_consent
	# Гейт согласия стоит ВЫШЕ решения о стабе и сбрасывает и клиента, и стаб:
	# is_available() возвращает true по одному лишь _stub, поэтому «отказал — и
	# реклама недоступна» краснело бы ровно в headless-сюите, где стаб включён.
	if not consent_allows_ads(personalized_consent):
		_client = null
		_stub = false
		# Незакрытый показ, начатый на «granted», права на награду не имеет: плагин
		# остаётся подписанным на наши обработчики и может прислать rewarded уже
		# после отзыва согласия. Право на выдачу — непустой _placement_pending,
		# поэтому он снимается здесь же, где и клиент.
		_placement_pending = ""
		_reward_earned = false
		if personalized_consent == "unknown":
			initialized.emit(false, "Ожидается согласие на рекламу")
		else:
			initialized.emit(false, "Согласие на рекламу отклонено")
		return
	# Аргументы передаются как есть: PackedStringArray от OS.get_cmdline_user_args()
	# итерится тем же циклом, что и Array из selftest-литерала (см. stub_requested).
	_stub = stub_requested(OS.get_cmdline_user_args(), OS.get_environment("ALCHEMY_ADS_STUB"), OS.is_debug_build())
	_client = _find_client(store_id)
	if _client == null and not _stub:
		initialized.emit(false, "Рекламный плагин не подключён")
		return
	if _client != null:
		_connect_signals()
		_call_first(["initialize", "init", "load_rewarded", "loadRewarded"], [])
	initialized.emit(true, "Реклама готова" if _client != null else "Реклама в debug-режиме")

func set_consent(consent: String) -> void:
	# Точка перевызова при изменении согласия (Лавка меняет режим без перезапуска
	# игры). Полное состояние пересобирает initialize(): он и гасит адаптер при
	# отказе, и поднимает клиента/стаб при последующем «granted».
	# Текущее значение храним в _store_id, поэтому store_id передавать не нужно.
	if consent == _consent:
		return
	initialize(_store_id, consent)

func is_available() -> bool:
	return _stub or _client != null

func show_rewarded(placement_id: String) -> bool:
	if not consent_allows_ads(_consent):
		# Второй эшелон защиты (первый — гейт согласия в initialize): вызов
		# возможен из кода, который держит адаптер, поднятый на «granted», а
		# согласие уже отозвали.
		ad_failed.emit("consent_required", "Rewarded-реклама недоступна без согласия")
		return false
	# Новый показ — новая награда: флаг сбрасывается здесь же, где и
	# _placement_pending, иначе closed от прошлого ролика съел бы показ этого.
	_reward_earned = false
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
	if not consent_allows_ads(_consent):
		ad_failed.emit("consent_required", "Interstitial-реклама недоступна без согласия")
		return false
	# Под стабом interstitial обязан работать: без этого путь «показали — записали
	# время кулдауна — второй отказ» непроверяем ни в selftest, ни на desktop.
	if _stub:
		call_deferred("_close_stub_interstitial")
		return true
	if _client == null:
		return false
	var call := _call_first(["show_interstitial", "showInterstitial"], [])
	return bool(call.get("called", false))

func _complete_stub_reward() -> void:
	# Стаб имитирует плагин, поэтому проходит ТОТ ЖЕ путь награды, что и
	# настоящий SDK: прямой emit rewarded_completed в обход _on_rewarded_signal
	# оставил бы гейты payload и «награда один раз» непроверяемыми под стабом.
	_on_rewarded_signal(null)

func _close_stub_interstitial() -> void:
	interstitial_closed.emit()

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
	for signal_name in ["rewarded", "rewarded_ad_rewarded", "on_rewarded"]:
		_connect_signal(signal_name, Callable(self, "_on_rewarded_signal"))
	# T23: «закрыто» — НЕ синоним «заработано». Раньше rewarded_closed висел на
	# том же обработчике, и плагин, который шлёт закрытие раньше/вместо награды
	# (скип видео), приносил игроку награду и записи в дневной кап.
	for signal_name in ["rewarded_closed", "on_rewarded_closed"]:
		_connect_signal(signal_name, Callable(self, "_on_rewarded_closed"))
	for signal_name in ["ad_failed_to_show", "ad_failed", "on_ad_failed"]:
		_connect_signal(signal_name, Callable(self, "_on_failed_signal"))
	for signal_name in ["interstitial_closed", "on_interstitial_closed"]:
		_connect_signal(signal_name, Callable(self, "_on_interstitial_closed"))

func _connect_signal(signal_name: String, callback: Callable) -> void:
	if _client == null or not _client.has_signal(signal_name):
		return
	if not _client.is_connected(signal_name, callback):
		_client.connect(signal_name, callback)

func _on_rewarded_signal(value = null, _extra = null) -> void:
	if _placement_pending == "":
		# Нет активного показа — нет и права на награду: поздний колбэк плагина
		# или сигнал, прилетевший после отзыва согласия (initialize снимает
		# _placement_pending вместе с клиентом, см. гейт выше).
		return
	if _reward_earned:
		# Дубликат (плагин шлёт награду дважды) — второе начисление не проходим.
		return
	if not payload_awards_reward(value):
		# Payload сказал «earned: false» — награды нет. Молчать нельзя: показ
		# закончился, и игрок вправе узнать, что награда не выдана.
		_report_reward_not_earned()
		return
	_reward_earned = true
	rewarded_completed.emit(_placement_pending)
	_placement_pending = ""

func _on_rewarded_closed(_value = null, _extra = null) -> void:
	# Связка «rewarded -> closed» — нормальный порядок AdMob-подобных: награду
	# уже выдал _on_rewarded_signal, и второй эмит был бы двойной выдачей.
	if _reward_earned:
		_reward_earned = false
		return
	if _placement_pending == "":
		# Late closed вне активного показа: сообщать нечего, показ не начинали.
		return
	_report_reward_not_earned()

func _report_reward_not_earned() -> void:
	ad_failed.emit("not_earned", "Реклама закрыта до награды")
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
