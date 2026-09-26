extends Node

# UserData — минимальный приватный контейнер для данных, которые не относятся
# к игровому графу: идентификаторы установки, согласия, pending/owned покупок
# и лимиты рекламы (файл alchemists_loop_user.json, затирается «Удалить
# данные»). Идемпотентность завершённых чеков — не здесь, а в журнале покупок
# alchemists_loop_purchases.json (ниже), который вайп переживает. Игровой
# прогресс остаётся в Saves и экспортируется отдельно.
#
# Важно: device_id не является аппаратным идентификатором. Это случайный
# идентификатор установки, который можно удалить кнопкой «Удалить данные».

const DATA_VERSION := 2
# Пути — переменные (как SAVE_PATH у сейвов в main.gd): самотест переводит их на
# ST-префикс, чтобы не трогать реальные данные установки. Настоящие имена и
# ST-двойники — константы. U23 (T27): перевод случается в _ready этой же
# автозагрузки ВЫШЕ _load(): автозагрузки готовятся до главной сцены, и без
# раннего перевода _load/_save и ensure_install_metadata перезаписали бы настоящие
# файлы до всякой изоляции (см. _isolate_selftest_paths).
const REAL_SAVE_PATH := "user://alchemists_loop_user.json"
const REAL_TEMP_PATH := "user://alchemists_loop_user.tmp"
const REAL_BACKUP_PATH := "user://alchemists_loop_user.bak"
const ST_SAVE_PATH := "user://alchemy_st_user.json"
const ST_TEMP_PATH := "user://alchemy_st_user.tmp"
const ST_BACKUP_PATH := "user://alchemy_st_user.bak"
# T22: журнал завершённых покупок живёт в ОТДЕЛЬНОМ файле и переживает
# «Удалить локальные данные»: его стирание означало бы, что локальный клиент
# снова готов выдать уже выданный consumable (restore после удаления). Ключи
# журнала — provider:sku:sha256(token), то есть к device_id они не привязаны и
# смысл не теряются, когда идентификатор установки удаляют вместе с остальными
# данными. Это платёжная защита, а не поведенческие данные.
const REAL_PURCHASES_PATH := "user://alchemists_loop_purchases.json"
const REAL_PURCHASES_TEMP_PATH := "user://alchemists_loop_purchases.tmp"
const ST_PURCHASES_PATH := "user://alchemy_st_purchases.json"
const ST_PURCHASES_TEMP_PATH := "user://alchemy_st_purchases.tmp"
const PURCHASES_VERSION := 1
const PROCESSED_CAP := 200

var SAVE_PATH := REAL_SAVE_PATH
var TEMP_PATH := REAL_TEMP_PATH
var BACKUP_PATH := REAL_BACKUP_PATH
var PURCHASES_PATH := REAL_PURCHASES_PATH
var PURCHASES_TEMP_PATH := REAL_PURCHASES_TEMP_PATH

signal changed

var _data: Dictionary = {}
var _processed: Dictionary = {}
# T22/I-1: отметка «начислено, но магазин ещё не подтвердил consume» живёт в
# том же неуязвимом файле журнала отдельной секцией, а НЕ в затираемом
# purchases.pending — иначе вайп стирал бы её и restore лил бы награду повторно.
var _granted: Dictionary = {}
# U23 (T27): факт, что загрузочный _load() отработал уже при переведённых на
# ST-двойники путях. Ставится первой строкой _load() и сверяется в начале
# Selftest.run: снятие ST-ветки из _ready или перенос _load() выше перевода
# красят кейс u23 (первый доступ к файлам должен быть изолирован).
var _boot_load_used_st_path := false

func _ready() -> void:
	_isolate_selftest_paths()
	_load()
	_load_purchase_journal()

func _isolate_selftest_paths() -> void:
	# U23 (T27): перевод обязан стоять перед первым обращением к файлам. Флаг
	# читается из общего источника (SelftestMode), потому что разбор в Main._ready
	# происходит позже: App._ready зовёт ensure_install_metadata() сразу после
	# этого _ready, и к тому моменту пути уже должны быть ST.
	# ST-двойники стираются здесь же, до первого чтения: остаток прошлого
	# прерванного прогона (pending-метки, session_count) не должен попадать в
	# _load() вместо пустого контейнера — проверки сюиты зависят от её записей,
	# а не от мусора на диске.
	if not SelftestMode.enabled():
		return
	SAVE_PATH = ST_SAVE_PATH
	TEMP_PATH = ST_TEMP_PATH
	BACKUP_PATH = ST_BACKUP_PATH
	PURCHASES_PATH = ST_PURCHASES_PATH
	PURCHASES_TEMP_PATH = ST_PURCHASES_TEMP_PATH
	for p in [SAVE_PATH, TEMP_PATH, BACKUP_PATH, PURCHASES_PATH, PURCHASES_TEMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

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
			# Ключ оставлен пустым намеренно: журнал завершённых покупок с T22
			# живёт в PURCHASES_PATH и в стираемый файл не пишется. Пустой ключ
			# держим, чтобы _merge_defaults не плодил расхождений у старых файлов
			# и чтобы форма export_data не менялась.
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
	# U23: фиксируется путь в момент первого чтения (см. _boot_load_used_st_path).
	_boot_load_used_st_path = SAVE_PATH == ST_SAVE_PATH
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

# --- Журнал завершённых покупок (T22): отдельный файл, переживает wipe --------

func _load_purchase_journal() -> void:
	# Читается независимо от основного файла: «Удалить локальные данные» трогает
	# основной файл, а журнал уже выданных чеков остаётся. Секция granted (I-1) —
	# отметка «начислено, но хвост не закрыт»; она живёт здесь же, чтобы пережить
	# и снятие pending, и вайп.
	var stored := _read_json(PURCHASES_PATH)
	_processed = {}
	_granted = {}
	var entries: Variant = stored.get("processed", null)
	if entries is Dictionary:
		_processed = (entries as Dictionary).duplicate(true)
	var granted_entries: Variant = stored.get("granted", null)
	if granted_entries is Dictionary:
		_granted = (granted_entries as Dictionary).duplicate(true)
	# Миграция (аддитивная, без bump'а DATA_VERSION): до T22 журнал лежал в
	# стираемом purchases.processed основного файла. Переносим сюда все legacy-
	# записи, которых ещё нет в новом журнале: мержим при ЛЮБОМ непустом legacy,
	# а не только «когда своего файла ещё нет» — к этому моменту свой файл уже мог
	# существовать, поэтому уже перенесённые ключи не перетираем. Иначе обновление
	# тихо «подарило» бы существующим установкам повторную выдачу после удаления
	# данных, то есть ровно тот дефект, который T22 чинит.
	var purchases: Dictionary = _data.get("purchases", {})
	var legacy: Variant = purchases.get("processed", {})
	if not (legacy is Dictionary) or (legacy as Dictionary).is_empty():
		return
	for key in (legacy as Dictionary):
		var entry: Variant = (legacy as Dictionary)[key]
		if entry is Dictionary and not _processed.has(String(key)):
			_processed[String(key)] = (entry as Dictionary).duplicate(true)
	_trim_processed()
	# M-2: legacy-копию в стираемом файле затираем и основной файл перезаписываем
	# ТОЛЬКО после успешной записи нового файла журнала. Иначе при неудачной записи
	# перенесённые записи потерялись бы и там (нового файла нет), и тут (его
	# затёрли бы) — окно безвозвратной потери журнала.
	if not _save_purchases():
		return
	purchases["processed"] = {}
	_data["purchases"] = purchases
	_save()

func _save_purchases() -> bool:
	# Замена одним rename: файл журнала либо старый, либо новый — промежуточного
	# состояния нет. Backup как у основного файла не ведём: журнал дополняемый, а
	# потеря одной строки означает лишь повторную проверку чека, но не порчу
	# пользовательских данных.
	var file := FileAccess.open(PURCHASES_TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("UserData: не удалось открыть временный файл журнала покупок.")
		return false
	file.store_string(JSON.stringify({"version": PURCHASES_VERSION, "processed": _processed, "granted": _granted}, "\t"))
	file.flush()
	file.close()
	var journal_abs := ProjectSettings.globalize_path(PURCHASES_PATH)
	var temp_abs := ProjectSettings.globalize_path(PURCHASES_TEMP_PATH)
	if DirAccess.rename_absolute(temp_abs, journal_abs) != OK:
		push_warning("UserData: не удалось заменить файл журнала покупок.")
		DirAccess.remove_absolute(temp_abs)
		return false
	changed.emit()
	return true

func _trim_processed() -> void:
	# Не даём служебному журналу расти бесконечно: режем самые старые по
	# processed_at (тот же порядок, что был до переноса в отдельный файл).
	if _processed.size() <= PROCESSED_CAP:
		return
	var keys: Array = _processed.keys()
	keys.sort_custom(func(a, b): return float(_processed[a].get("processed_at", 0.0)) < float(_processed[b].get("processed_at", 0.0)))
	for i in range(0, keys.size() - PROCESSED_CAP):
		_processed.erase(keys[i])

func _trim_granted() -> void:
	# Тот же потолок и тот же порядок, что у processed: режем самые старые granted-
	# отметки по granted_at. Протухание не нужно — granted означает «хвост consume
	# не закрыт», такая отметка обязана дожить до ретрая, а расти в бесконечность
	# ей не даёт этот рез.
	if _granted.size() <= PROCESSED_CAP:
		return
	var keys: Array = _granted.keys()
	keys.sort_custom(func(a, b): return float(_granted[a].get("granted_at", 0.0)) < float(_granted[b].get("granted_at", 0.0)))
	for i in range(0, keys.size() - PROCESSED_CAP):
		_granted.erase(keys[i])

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
	return _processed.has(_token_key(provider, token, sku))

func mark_processed_purchase(provider: String, token: String, sku: String) -> bool:
	if token == "" or has_processed_purchase(provider, token, sku):
		return false
	var key := _token_key(provider, token, sku)
	_processed[key] = {
		"provider": provider,
		"sku": sku,
		"processed_at": Time.get_unix_time_from_system(),
	}
	_trim_processed()
	if not _save_purchases():
		return false
	# I-1: чек закрыт в журнале — отдельная granted-отметка больше не нужна, иначе
	# словарь рос бы без границы. Снимаем её ТОЛЬКО после успешной записи processed
	# (иначе при неудачной записи отметка исчезнет, а строки processed нет — остаток
	# снова получит двойное начисление на ретрае).
	if _granted.has(key):
		_granted.erase(key)
		_save_purchases()
	return true

# --- Отметка «уже начислено» (I-1): своя секция того же неуязвимого журнала ----
# Ключ — тот же _token_key, что у processed, чтобы granted и processed строка
# чека соотносились один-к-одному. Живёт вне pending, поэтому переживает и снятие
# pending, и «Удалить локальные данные» — restore не нальёт награду повторно.

func is_purchase_granted(provider: String, token: String, sku: String) -> bool:
	if token == "":
		return false
	return _granted.has(_token_key(provider, token, sku))

func mark_purchase_granted(provider: String, token: String, sku: String) -> bool:
	if token == "":
		return false
	_granted[_token_key(provider, token, sku)] = {
		"provider": provider,
		"sku": sku,
		"granted_at": Time.get_unix_time_from_system(),
	}
	_trim_granted()
	return _save_purchases()

func clear_purchase_granted(provider: String, token: String, sku: String) -> void:
	var key := _token_key(provider, token, sku)
	if not _granted.has(key):
		return
	_granted.erase(key)
	_save_purchases()

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

# T22: чтение pending-записи о начатой, но не закрытой покупке (provider/sku/
# started_at). Отметка «уже начислено» с фикса I-1 живёт НЕ здесь, а в секции
# granted журнала покупок (is_purchase_granted) — pending затирается вайпом.
func get_pending_purchase(key: String) -> Dictionary:
	var purchases: Dictionary = _data.get("purchases", {})
	var pending: Dictionary = purchases.get("pending", {})
	var value: Variant = pending.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func clear_pending_purchase(key: String) -> void:
	var purchases: Dictionary = _data.get("purchases", {})
	var pending: Dictionary = purchases.get("pending", {})
	pending.erase(key)
	purchases["pending"] = pending
	_data["purchases"] = purchases
	_save()

func export_data() -> Dictionary:
	var out := _data.duplicate(true)
	# Журнал завершённых покупок живёт вне _data (см. PURCHASES_PATH), но в экспорт
	# обязан попадать: это данные пользователя, а не внутренняя примета файла.
	var purchases: Dictionary = out.get("purchases", {})
	purchases["processed"] = _processed.duplicate(true)
	out["purchases"] = purchases
	# Экспорт нужен пользователю, но не должен раскрывать чек-токены. Их в
	# _data и так нет; оставляем явный маркер для потребителя экспорта.
	out["purchase_tokens"] = "not_stored_raw"
	return out

func delete_all_local_data() -> void:
	# Журнал покупок (_processed и granted-отметки / PURCHASES_PATH) здесь
	# СОХРАНЯЕТСЯ целиком: он защищает от повторной выдачи уже потреблённых и уже
	# начисленных, но не закрытых чеков и не является поведенческими данными.
	# Временный файл журнала — мусор, его удаляем.
	_data = _defaults()
	_save()
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH, PURCHASES_TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	changed.emit()
