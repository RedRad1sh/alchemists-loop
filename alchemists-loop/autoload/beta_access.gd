extends Node

signal access_changed
signal status_changed

var enabled := OS.has_feature("beta")
var storage_path := "user://beta_access.json"
var server_url := ""
var token := ""
var device_id := ""
var attempt_secret := ""
var identity_secret := ""
var pending_code := ""
var activating := false
var status := "Введи инвайт-код для доступа к серверу."
var retry_after := 0.0
var server_confirmed := false
var deletions: Array = []
var purchases: Dictionary = {}

func _ready() -> void:
	server_url = App.resolve_config("ALCHEMY_SERVER", "application/config/alchemy_server").trim_suffix("/")
	if SelftestMode.isolated():
		storage_path = "user://alchemy_st_beta_access.json"
		return
	if enabled:
		load_credentials()

func can_send_gameplay() -> bool:
	return not enabled or (token != "" and device_id == UserData.get_or_create_device_id() and _transport_allowed(server_url))

func _transport_allowed(url: String) -> bool:
	return url.begins_with("https://") or (OS.has_feature("editor") and (url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")))

func _origin(url: String) -> String:
	var parts := url.split("://", false, 1)
	if parts.size() != 2:
		return ""
	return parts[0].to_lower() + "://" + parts[1].get_slice("/", 0).to_lower()

func auth_headers(url: String) -> PackedStringArray:
	if not enabled or not can_send_gameplay() or _origin(url) != _origin(server_url):
		return PackedStringArray()
	return PackedStringArray(["Authorization: Bearer " + token])

func prepare_activation(code: String) -> bool:
	if identity_secret == "":
		identity_secret = Crypto.new().generate_random_bytes(32).hex_encode()
	var normalized := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if pending_code != normalized or attempt_secret == "":
		attempt_secret = Crypto.new().generate_random_bytes(32).hex_encode()
		pending_code = normalized
	return _save_credentials()

func activate(code: String) -> void:
	if activating or Time.get_unix_time_from_system() < retry_after:
		return
	if not _transport_allowed(server_url):
		_set_status("Нужен настроенный HTTPS-адрес beta-сервера.")
		return
	if code.strip_edges() == "" or code.length() > 128:
		_set_status("Введи инвайт-код.")
		return
	if not prepare_activation(code):
		_set_status("Не удалось сохранить попытку входа. Проверь свободное место.")
		return
	activating = true
	_set_status("Проверяю приглашение…")
	Net.beta_activate(pending_code, UserData.get_or_create_device_id(), attempt_secret)

func accept_activation(result: Dictionary) -> void:
	if pending_code == "" or attempt_secret == "":
		return
	if result.has("_attempt_hash") and String(result["_attempt_hash"]) != attempt_secret.sha256_text():
		return
	activating = false
	if result.get("ok", false) != true or result.get("beta", false) != true:
		if result.get("http_status", 0) == 429:
			var seconds := clampi(int(result.get("retry_after", 600)), 1, 86400)
			retry_after = Time.get_unix_time_from_system() + seconds
			_set_status("Слишком много попыток. Повтори через %d с." % seconds)
		elif result.get("offline", false):
			_set_status("Сервер не ответил. Повтори вход — приглашение не потеряется.")
		else:
			_set_status("Код не принят. Проверь его или попроси новое приглашение.")
		return
	if String(result.get("device_id", "")) != UserData.get_or_create_device_id() or String(result.get("token", "")) == "":
		_set_status("Сервер вернул некорректное подтверждение входа.")
		return
	token = String(result["token"])
	device_id = String(result["device_id"])
	if not _save_credentials():
		token = ""
		_set_status("Не удалось сохранить доступ. Повтори вход.")
		return
	server_confirmed = true
	pending_code = ""
	attempt_secret = ""
	_save_credentials()
	_set_status("Бета: доступ открыт. Покупки тестовые, без оплаты.")
	access_changed.emit()

func access_revoked() -> void:
	token = ""
	device_id = ""
	server_confirmed = false
	_save_credentials()
	_set_status("Доступ к серверу закрыт. Для входа нужен новый инвайт-код.")
	access_changed.emit()

func _set_status(text: String) -> void:
	status = text
	status_changed.emit()

func load_credentials() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(storage_path)) if FileAccess.file_exists(storage_path) else null
	if not parsed is Dictionary or String(parsed.get("server_url", "")) != server_url:
		return
	token = String(parsed.get("token", ""))
	device_id = String(parsed.get("device_id", ""))
	attempt_secret = String(parsed.get("attempt_secret", ""))
	identity_secret = String(parsed.get("identity_secret", ""))
	pending_code = String(parsed.get("pending_code", ""))
	deletions = parsed.get("deletions", []) if parsed.get("deletions") is Array else []
	purchases = parsed.get("purchases", {}) if parsed.get("purchases") is Dictionary else {}
	if token != "":
		status = "Доступ сохранён. Покупки в бете тестовые, без оплаты."

func _save_credentials() -> bool:
	var file := FileAccess.open(storage_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"server_url": server_url, "token": token, "device_id": device_id,
		"attempt_secret": attempt_secret, "identity_secret": identity_secret, "pending_code": pending_code, "deletions": deletions, "purchases": purchases}))
	file.flush()
	var err := file.get_error()
	file.close()
	return err == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(storage_path + ".tmp"), ProjectSettings.globalize_path(storage_path)) == OK

func clear_credentials() -> void:
	activating = false
	token = ""
	device_id = ""
	attempt_secret = ""
	identity_secret = ""
	pending_code = ""
	server_confirmed = false
	purchases.clear()
	for path in [storage_path, storage_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not deletions.is_empty():
		_save_credentials()

func prepare_deletion(id: String) -> void:
	if not enabled or token == "" or device_id != id:
		return
	for entry in deletions:
		if String(entry.get("device_id", "")) == id and String(entry.get("server_url", "")) == server_url:
			return
	deletions.append({"device_id": id, "server_url": server_url, "token": token})
	_save_credentials()

func deletion_token(id: String) -> String:
	for entry in deletions:
		if String(entry.get("device_id", "")) == id and String(entry.get("server_url", "")) == server_url:
			return String(entry.get("token", ""))
	return ""

func finish_deletion(id: String) -> void:
	for i in range(deletions.size() - 1, -1, -1):
		if String(deletions[i].get("device_id", "")) == id and String(deletions[i].get("server_url", "")) == server_url:
			deletions.remove_at(i)
	_save_credentials()

func pending_purchase(product_id: String) -> String:
	return String(purchases.get(product_id, ""))

func begin_purchase(product_id: String) -> String:
	if not purchases.has(product_id):
		purchases[product_id] = Crypto.new().generate_random_bytes(24).hex_encode()
	if not _save_credentials():
		return ""
	return String(purchases[product_id])

func finish_purchase(product_id: String) -> void:
	purchases.erase(product_id)
	_save_credentials()
