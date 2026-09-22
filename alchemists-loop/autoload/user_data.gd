extends Node

# UserData — минимальный приватный контейнер для данных, которые не относятся
# к игровому графу: идентификаторы установки, согласия, идемпотентность покупок
# и лимиты рекламы. Игровой прогресс остаётся в Saves и экспортируется отдельно.
#
# Важно: device_id не является аппаратным идентификатором. Это случайный
# идентификатор установки, который можно удалить кнопкой «Удалить данные».

const DATA_VERSION := 2
const SAVE_PATH := "user://alchemists_loop_user.json"
const TEMP_PATH := "user://alchemists_loop_user.tmp"
const BACKUP_PATH := "user://alchemists_loop_user.bak"

signal changed

var _data: Dictionary = {}

func _ready() -> void:
	_load()

func _defaults() -> Dictionary:
	return {
		"version": DATA_VERSION,
		"device_id": "",
		"install_id": "",
		"consent": {
			"analytics": "unknown",
			"ads_personalized": "unknown",
			"privacy_version": 1,
		},
		"purchases": {
			"processed": {},
			"owned": {},
			"pending": {},
		},
		"ads": {
			"day": "",
			"rewarded_count": 0,
			"last_rewarded_at": 0.0,
			"last_interstitial_at": 0.0,
		},
		"app": {
			"install_at": 0.0,
			"session_count": 0,
			"session_started_at": 0.0,
		},
	}

func _merge_defaults(value: Dictionary, defaults: Dictionary) -> Dictionary:
	for key in defaults:
		if not value.has(key):
			value[key] = defaults[key]
		elif defaults[key] is Dictionary and value[key] is Dictionary:
			value[key] = _merge_defaults(value[key] as Dictionary, defaults[key] as Dictionary)
	return value

func _load() -> void:
	var parsed := _read_json(SAVE_PATH)
	if parsed.is_empty():
		parsed = _read_json(BACKUP_PATH)
	if parsed.is_empty():
		_data = _defaults()
		return
	var version := int(parsed.get("version", 1))
	if version < 1 or version > DATA_VERSION:
		_data = _defaults()
		return
	# v1 не содержала вложенного контейнера покупок и согласий. Миграция
	# намеренно аддитивная: неизвестные поля сохраняются для будущих версий.
	_data = _merge_defaults(parsed, _defaults())
	_data["version"] = DATA_VERSION
	_save()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func _save() -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("UserData: не удалось открыть временный файл.")
		return false
	_data["version"] = DATA_VERSION
	file.store_string(JSON.stringify(_data, "\t"))
	file.flush()
	file.close()
	var save_abs := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_abs := ProjectSettings.globalize_path(TEMP_PATH)
	var backup_abs := ProjectSettings.globalize_path(BACKUP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(backup_abs)
		if DirAccess.rename_absolute(save_abs, backup_abs) != OK:
			push_warning("UserData: не удалось создать backup.")
			return false
	if DirAccess.rename_absolute(temp_abs, save_abs) != OK:
		push_warning("UserData: не удалось заменить файл.")
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(backup_abs, save_abs)
		return false
	changed.emit()
	return true

func save_now() -> bool:
	return _save()

func ensure_install_metadata() -> void:
	var app: Dictionary = _data.get("app", {})
	if float(app.get("install_at", 0.0)) <= 0.0:
		app["install_at"] = Time.get_unix_time_from_system()
		_data["app"] = app
		_save()

func record_session_start() -> void:
	ensure_install_metadata()
	var app: Dictionary = _data.get("app", {})
	app["session_count"] = maxi(0, int(app.get("session_count", 0))) + 1
	app["session_started_at"] = Time.get_unix_time_from_system()
	_data["app"] = app
	_save()

func install_age_seconds() -> float:
	ensure_install_metadata()
	var app: Dictionary = _data.get("app", {})
	return maxf(0.0, Time.get_unix_time_from_system() - float(app.get("install_at", 0.0)))

func session_count() -> int:
	return maxi(0, int((_data.get("app", {}) as Dictionary).get("session_count", 0)))

func session_seconds() -> float:
	var app: Dictionary = _data.get("app", {})
	var started := float(app.get("session_started_at", 0.0))
	if started <= 0.0:
		return 0.0
	return maxf(0.0, Time.get_unix_time_from_system() - started)

func get_or_create_device_id() -> String:
	var current := String(_data.get("device_id", "")).strip_edges()
	if current != "":
		return current
	var seed := "%s:%s:%s:%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi(), OS.get_unique_id()]
	current = "install_" + seed.sha256_text().substr(0, 32)
	_data["device_id"] = current
	_save()
	return current

func get_or_create_install_id() -> String:
	var current := String(_data.get("install_id", "")).strip_edges()
	if current != "":
		return current
	var seed := "%s:%s:%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]
	current = "app_" + seed.sha256_text().substr(0, 32)
	_data["install_id"] = current
	_save()
	return current

func get_consent(key: String) -> String:
	var consent: Dictionary = _data.get("consent", {})
	return String(consent.get(key, "unknown"))

func set_consent(key: String, value: String) -> void:
	if value not in ["unknown", "granted", "denied"]:
		return
	var consent: Dictionary = _data.get("consent", {})
	consent[key] = value
	_data["consent"] = consent
	_save()

func get_ads_state() -> Dictionary:
	var state: Dictionary = _data.get("ads", {})
	return state.duplicate(true)

func set_ads_state(state: Dictionary) -> void:
	_data["ads"] = state.duplicate(true)
	_save()

func rewarded_count_for_today() -> int:
	var state := get_ads_state()
	if String(state.get("day", "")) != Time.get_date_string_from_system():
		return 0
	return maxi(0, int(state.get("rewarded_count", 0)))

func record_rewarded_view() -> void:
	var state := get_ads_state()
	var today := Time.get_date_string_from_system()
	if String(state.get("day", "")) != today:
		state["day"] = today
		state["rewarded_count"] = 0
	state["rewarded_count"] = int(state.get("rewarded_count", 0)) + 1
	state["last_rewarded_at"] = Time.get_unix_time_from_system()
	set_ads_state(state)

func set_last_interstitial_at(at: float) -> void:
	var state := get_ads_state()
	state["last_interstitial_at"] = at
	set_ads_state(state)

func last_interstitial_at() -> float:
	return float(get_ads_state().get("last_interstitial_at", 0.0))

func _token_key(provider: String, token: String, sku: String) -> String:
	# Токены чеков не храним в открытом виде. Для идемпотентности достаточно
	# криптографического отпечатка + провайдера/SKU.
	return "%s:%s:%s" % [provider, sku, token.sha256_text()]

func has_processed_purchase(provider: String, token: String, sku: String) -> bool:
	if token == "":
		return false
	var purchases: Dictionary = _data.get("purchases", {})
	var processed: Dictionary = purchases.get("processed", {})
	return processed.has(_token_key(provider, token, sku))

func mark_processed_purchase(provider: String, token: String, sku: String) -> bool:
	if token == "" or has_processed_purchase(provider, token, sku):
		return false
	var purchases: Dictionary = _data.get("purchases", {})
	var processed: Dictionary = purchases.get("processed", {})
	processed[_token_key(provider, token, sku)] = {
		"provider": provider,
		"sku": sku,
		"processed_at": Time.get_unix_time_from_system(),
	}
	# Не даём служебному журналу расти бесконечно.
	if processed.size() > 200:
		var keys: Array = processed.keys()
		keys.sort_custom(func(a, b): return float(processed[a].get("processed_at", 0.0)) < float(processed[b].get("processed_at", 0.0)))
		for i in range(0, keys.size() - 200):
			processed.erase(keys[i])
		purchases["processed"] = processed
	_data["purchases"] = purchases
	_save()
	return true

func set_owned_product(sku: String, owned: bool = true) -> void:
	var purchases: Dictionary = _data.get("purchases", {})
	var owned_map: Dictionary = purchases.get("owned", {})
	owned_map[sku] = owned
	purchases["owned"] = owned_map
	_data["purchases"] = purchases
	_save()

func is_product_owned(sku: String) -> bool:
	var purchases: Dictionary = _data.get("purchases", {})
	var owned_map: Dictionary = purchases.get("owned", {})
	return bool(owned_map.get(sku, false))

func set_pending_purchase(key: String, value: Dictionary) -> void:
	var purchases: Dictionary = _data.get("purchases", {})
	var pending: Dictionary = purchases.get("pending", {})
	pending[key] = value.duplicate(true)
	purchases["pending"] = pending
	_data["purchases"] = purchases
	_save()

func clear_pending_purchase(key: String) -> void:
	var purchases: Dictionary = _data.get("purchases", {})
	var pending: Dictionary = purchases.get("pending", {})
	pending.erase(key)
	purchases["pending"] = pending
	_data["purchases"] = purchases
	_save()

func export_data() -> Dictionary:
	var out := _data.duplicate(true)
	# Экспорт нужен пользователю, но не должен раскрывать чек-токены. Их в
	# _data и так нет; оставляем явный маркер для потребителя экспорта.
	out["purchase_tokens"] = "not_stored_raw"
	return out

func delete_all_local_data() -> void:
	_data = _defaults()
	_save()
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	changed.emit()
