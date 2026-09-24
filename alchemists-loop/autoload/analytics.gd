extends Node

# Analytics — consent-aware фасад. В релизном проекте подключается GameAnalytics
# и, при необходимости для RuStore, AppMetrica. Без плагинов игра не падает:
# события остаются в локальной очереди только после согласия и могут быть
# просмотрены в debug-логе.

# var, а не const: автотест переводит очередь на свой файл, иначе selftest пишет
# события в реальный файл аналитики установки (см. tests/selftest.gd).
var QUEUE_PATH := "user://alchemists_loop_analytics.json"
const MAX_QUEUE := 300

var _consent := "unknown"
var _configured := false
var _session_started_at := 0.0
var _events: Array = []
var _provider := "none"

func _ready() -> void:
	configure_consent()

func configure_consent() -> void:
	_consent = UserData.get_consent("analytics")
	if _consent == "granted":
		_configured = true
		_detect_provider()
	else:
		_configured = false
		_provider = "none"

func _detect_provider() -> void:
	_provider = "local"
	for singleton_name in ["GameAnalytics", "game_analytics"]:
		if Engine.has_singleton(singleton_name):
			_provider = "gameanalytics"
			return
	for singleton_name in ["AppMetrica", "appmetrica"]:
		if Engine.has_singleton(singleton_name):
			_provider = "appmetrica"
			return

func has_consent() -> bool:
	return _consent == "granted"

func consent_status() -> String:
	return _consent

func provider_status() -> String:
	return _provider

func set_consent(allowed: bool) -> void:
	UserData.set_consent("analytics", "granted" if allowed else "denied")
	configure_consent()

func session_start(source: String = "icon") -> void:
	_session_started_at = Time.get_unix_time_from_system()
	UserData.record_session_start()
	track("session_start", {"source": source})

func session_end(reason: String = "close") -> void:
	if _session_started_at <= 0.0:
		return
	var length := maxi(0, int(Time.get_unix_time_from_system() - _session_started_at))
	track("session_end", {"reason": reason, "lengthSec": length})
	_session_started_at = 0.0

func track(event_name: String, properties: Dictionary = {}) -> void:
	if not has_consent():
		return
	var clean_name := event_name.strip_edges().to_lower()
	if clean_name == "" or not _valid_event_name(clean_name):
		return
	var payload := {
		"event": clean_name,
		"properties": _sanitize(properties),
		"ts": int(Time.get_unix_time_from_system()),
	}
	_events.append(payload)
	if _events.size() > MAX_QUEUE:
		_events.pop_front()
	_dispatch(payload)
	_write_queue()

func _valid_event_name(name: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]{1,63}$")
	return re.search(name) != null

func _sanitize(properties: Dictionary) -> Dictionary:
	var out := {}
	for raw_key in properties:
		var key := String(raw_key)
		if key == "device_id" or key == "install_id" or key == "nick" or key == "email":
			continue
		var value = properties[raw_key]
		match typeof(value):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
				out[key] = value
			TYPE_STRING:
				out[key] = String(value).substr(0, 64)
	return out

func _dispatch(payload: Dictionary) -> void:
	var event_name := String(payload["event"])
	var props: Dictionary = payload["properties"]
	if Engine.has_singleton("GameAnalytics"):
		var ga = Engine.get_singleton("GameAnalytics")
		if ga != null:
			if ga.has_method("add_design_event"):
				ga.call("add_design_event", event_name, props)
			elif ga.has_method("track_event"):
				ga.call("track_event", event_name, props)
	elif Engine.has_singleton("AppMetrica"):
		var am = Engine.get_singleton("AppMetrica")
		if am != null and am.has_method("report_event"):
			am.call("report_event", event_name, props)
	if OS.get_environment("ALCHEMY_ANALYTICS_DEBUG") == "1":
		print("ANALYTICS ", JSON.stringify(payload))

func _write_queue() -> void:
	# События не записываются до согласия. После согласия очередь полезна для
	# диагностики и для SDK, которое ещё не успело инициализироваться.
	var file := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_events))
	file.close()

func clear_local_queue() -> void:
	_events.clear()
	if FileAccess.file_exists(QUEUE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(QUEUE_PATH))

func export_data() -> Array:
	return _events.duplicate(true)
