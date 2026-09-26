# net.gd — Autoload-сервис сетевого взаимодействия с сервером первооткрытий.
# 
# Поместить в проект как Autoload (Project Settings → Autoload → net.gd).
# 
# Использование из main.gd:
#   net.check_pair(a, b)   → проверка, является ли пара кандидатом
#   net.discover(a, b)     → регистрация нового первооткрытия (идемпотентно)
#   net.world()            → получение списка всех элементов
#
# Все методы асинхронны (возвращают Promise-результат через 시그널 или callback).
# При недоступности сети ведёт себя как «Туман рассеялся…», возврат 1 эфира.

extends Node

# ---------------------------------------------------------------------------
# Константы
# ---------------------------------------------------------------------------

const SERVER_URL := "http://localhost:8080/api"  # Заменить на реальный URL при деплое
const REQUEST_TIMEOUT := 4.0                       # Секунд на ожидание ответа
const CANDIDATE_CHANCE := 0.05                     # 5% шанс тумана → не отправлять запрос
const CANDIDATE_COOLDOWN := 60.0                   # Секунд между повторными проверками одной пары

# ---------------------------------------------------------------------------
# Сигналы (для реакции на ответы)
# ---------------------------------------------------------------------------

signal brew_check_result(result: Dictionary)
signal discover_result(result: Dictionary)
signal world_result(result: Dictionary)
signal error(message: String)

# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

var _http_request: HTTPRequest
var _pending_requests: Dictionary = {}   # request_id → {callback, data}
var _last_candidate_time: Dictionary = {}  # pair_key → timestamp
var _is_server_available: bool = true

# ---------------------------------------------------------------------------
# Инициализация
# ---------------------------------------------------------------------------

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Проверка доступности сервера
	_ping_server()

# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------

func _ping_server() -> void:
	"""
	Асинхронная проверка доступности сервера по /api/health.
	Обновляет _is_server_available.
	"""
	var url := SERVER_URL + "/health"
	_http_request.request(url, ["Content-Type: application/json"])


func _pair_key(a: String, b: String) -> String:
	"""
	Канонический ключ пары (независим от порядка ингредиентов).
	"""
	if a == b:
		return a + "|" + a
	var sorted := [a, b].sort()
	return sorted[0] + "|" + sorted[1]


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _should_send_candidate(a: String, b: String) -> bool:
	"""
	Определяет, нужно ли отправлять запрос на сервер для данной пары.
	Возвращает false, если:
	- выпал 5% шанс тумана (рандом)
	- не прошло 60 сек с последней проверки этой пары
	"""
	var key := _pair_key(a, b)
	var now := _now()
	
	# Шанс тумана
	if randf() < CANDIDATE_CHANCE:
		return false
	
	# Кулдаун
	if _last_candidate_time.has(key):
		if now - _last_candidate_time[key] < CANDIDATE_COOLDOWN:
			return false
	
	_last_candidate_time[key] = now
	return true


# ---------------------------------------------------------------------------
# Основные методы
# ---------------------------------------------------------------------------

func check_pair(a: String, b: String, nick: String, device_id: String) -> void:
	"""
	Асинхронная проверка, является ли пара кандидатом на первооткрытие.
	
	Сигнал brew_check_result вернёт:
	{
		"ok": bool,
		"pair_key": str,
		"found": bool,
		"out": dict | null,
		"discoverer": dict | null,
		"pending": bool,
		"message": str
	}
	
	При недоступности сервера — будет отправлен сигнал error() и
	результат можно рассматривать как оффлайн-фоллбэк.
	"""
	if not _should_send_candidate(a, b):
		# Шанс тумана — вести себя как сейчас (туман + возврат 1 эфира)
		brew_check_result({
			"ok": false,
			"offline": true,
			"message": "Туман рассеялся…"
		})
		return
	
	if not _is_server_available:
		brew_check_result({
			"ok": false,
			"offline": true,
			"message": "Сервер недоступен"
		})
		return
	
	var url := SERVER_URL + "/brew-check"
	var body := {
		"a": a,
		"b": b,
		"nick": nick,
		"device_id": device_id
	}
	
	var error := _http_request.request(url, ["Content-Type: application/json"], Registry.STRING, JSON.stringify(body))
	if error != OK:
		brew_check_result({
			"ok": false,
			"error": "request_failed",
			"message": "Не удалось отправить запрос"
		})


func discover(a: String, b: String, nick: String, device_id: String) -> void:
	"""
	Асинхронная регистрация нового первооткрытия (идемпотентно по pair_key).
	
	Сигнал discover_result вернёт:
	{
		"ok": bool,
		"discovery": DiscoveryData | null,
		"already_known": bool,
		"message": str
	}
	
	При недоступности сервера — будет отправлен сигнал error() и
	результат можно рассматривать как оффлайн-фоллбэк.
	"""
	if not _is_server_available:
		discover_result({
			"ok": false,
			"offline": true,
			"message": "Сервер недоступен"
		})
		return
	
	var url := SERVER_URL + "/discover"
	var body := {
		"a": a,
		"b": b,
		"nick": nick,
		"device_id": device_id
	}
	
	var error := _http_request.request(url, ["Content-Type: application/json"], Registry.STRING, JSON.stringify(body))
	if error != OK:
		discover_result({
			"ok": false,
			"error": "request_failed",
			"message": "Не удалось отправить запрос"
		})


func world(page: int = 1, per_page: int = 50) -> void:
	"""
	Асинхронная загрузка списка всех известных элементов.
	
	Сигнал world_result вернёт:
	{
		"ok": bool,
		"elements": [ElementData, ...],
		"page": int,
		"per_page": int,
		"total": int
	}
	"""
	if not _is_server_available:
		world_result({
			"ok": false,
			"elements": [],
			"offline": true,
			"message": "Сервер недоступен"
		})
		return
	
	var url := SERVER_URL + "/world?page=" + str(page) + "&per_page=" + str(per_page)
	
	var error := _http_request.request(url, ["Content-Type: application/json"])
	if error != OK:
		world_result({
			"ok": false,
			"elements": [],
			"error": "request_failed"
		})


func hall_of_fame() -> void:
	"""
	Асинхронная загрузка тим-10 первооткрытий.
	
	Сигнал hall_result вернёт:
	{
		"ok": bool,
		"hall": [HallEntry, ...]
	}
	"""
	hall_result.connect(_on_hall_result)
	if not _is_server_available:
		hall_result.emit({
			"ok": false,
			"hall": [],
			"offline": true
		})
		return
	
	var url := SERVER_URL + "/hall-of-fame"
	
	var error := _http_request.request(url, ["Content-Type: application/json"])
	if error != OK:
		hall_result.emit({
			"ok": false,
			"hall": [],
			"error": "request_failed"
		})


signal hall_result(result: Dictionary)


# ---------------------------------------------------------------------------
# Обработчики ответов
# ---------------------------------------------------------------------------

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""
	Обработка завершения HTTP-запроса.
	"""
	if response_code != 200:
		error.emit("HTTP " + str(response_code))
		return
	
	var text := body.get_string_from_utf8()
	
	# Пытаемся определить, какой запрос завершился
	# (в простом варианте — по порядку вызовов)
	# В полноценной реализации нужен request_id
	
	# Для простоты анализируем тело ответа:
	if text.begins_with("{"):
		var json := JSON.parse_string(text)
		if json == null:
			error.emit("JSON parse error")
			return
		
		# Определяем тип ответа по содержимому
		if json.has("discovery"):
			discover_result.emit(json)
		elif json.has("elements"):
			world_result.emit(json)
		elif json.has("found"):
			brew_check_result.emit(json)
		elif json.has("hall"):
			hall_result.emit(json)
		else:
			error.emit("Unknown response format")
	else:
		error.emit("Invalid response")


func _on_hall_result(result: Dictionary) -> void:
	"""
	Callback для hall_of_fame — перенаправляет в сигнал.
	"""
	hall_result.emit(result)


# ---------------------------------------------------------------------------
# Проверка доступности сервера
# ---------------------------------------------------------------------------

func _check_server_health(response_code: int) -> void:
	if response_code == 200:
		_is_server_available = true
	else:
		_is_server_available = false


# ---------------------------------------------------------------------------
# Дополнительные утилиты
# ---------------------------------------------------------------------------

func is_server_available() -> bool:
	return _is_server_available


func get_pair_key(a: String, b: String) -> String:
	return _pair_key(a, b)


# ---------------------------------------------------------------------------
# Конец net.gd
# ---------------------------------------------------------------------------
