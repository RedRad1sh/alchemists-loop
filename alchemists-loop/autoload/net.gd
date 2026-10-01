# net.gd — Autoload-клиент сервера первооткрытий.
#
# Отвечает за HTTP-общение с сервером (см. discovery-server/server/server.py):
#   check_pair(a, b, nick, device_id) -> сигнал pair_result(pair_key, result)
#   discover(a, b, nick, device_id)   -> сигнал discover_result(pair_key, result)
#   world(page)                       -> сигнал world_result(result)
#   hall()                            -> сигнал hall_result(result)
#   echoes(device_id)                 -> сигнал echoes_result(result)
#   echoes_claim(device_id)           -> сигнал echoes_claim_result(result)
#   letter_today(device_id)           -> сигнал letter_result(result)
#   letter_solve(device_id, a, b)     -> сигнал letter_solve_result(result)
#   atlas_today(device_id)            -> сигнал atlas_result(result)
#   atlas_solve(device_id, a, b)      -> сигнал atlas_solve_result(result)
#   receipt_verify(device_id, provider, sku, receipt_token)
#                                     -> сигнал receipt_verify_result(result)
#
# Запросы ходят строго по одному (очередь), каждый помечен kind/pair_key, так
# что ответы коррелируются с запросами. При недоступном сервере результат
# содержит {"offline": true} — клиент обязан уметь работать офлайн.
#
# Правило сборки: есть "path" — GET на этот путь, есть "body" — POST
# (path+body = POST на явный путь). Для privacy DELETE задаётся явным ключом
# method, чтобы очередь запросов оставалась общей для игры и аккаунта.
#
# Базовый URL: переменная окружения ALCHEMY_SERVER, иначе ProjectSettings
# application/config/alchemy_server (его печатает релизный CI), иначе DEFAULT_BASE.
# В релизе (не debug-сборка) http:// запрещён: итог с http:// = пустая строка,
# то есть «сервера нет» — игра живёт офлайн, а не молча греет 127.0.0.1.

extends Node

const DEFAULT_BASE := "http://127.0.0.1:8080/api"

signal pair_result(pair_key: String, result: Dictionary)
signal discover_result(pair_key: String, result: Dictionary)
signal world_result(result: Dictionary)
signal hall_result(result: Dictionary)
signal events_result(result: Dictionary)
signal challenge_result(result: Dictionary)
signal me_result(result: Dictionary)
signal rejected_result(result: Dictionary)
signal house_result(result: Dictionary)
signal house_visit_result(result: Dictionary)
signal rating_result(result: Dictionary)
signal echoes_result(result: Dictionary)
signal echoes_claim_result(result: Dictionary)
signal letter_result(result: Dictionary)
signal letter_solve_result(result: Dictionary)
signal atlas_result(result: Dictionary)
signal atlas_solve_result(result: Dictionary)
signal week_result(result: Dictionary)
signal fair_brew_result(result: Dictionary)
signal fair_claim_result(result: Dictionary)
signal receipt_verify_result(result: Dictionary)
signal account_export_result(result: Dictionary)
signal account_delete_result(result: Dictionary)
signal vein_find_result(pair_key: String, result: Dictionary)
signal vein_pour_result(find_id: String, result: Dictionary)
signal cycle_result(result: Dictionary)
signal sigil_daily_result(result: Dictionary)
signal sigil_craft_result(result: Dictionary)
signal sigil_catalog_result(result: Dictionary)
signal sigil_collection_result(result: Dictionary)
signal error(message: String)

var base_url := DEFAULT_BASE

var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _inflight: Dictionary = {}
var _available := false

func _ready() -> void:
	base_url = resolve_base_url(
		OS.get_environment("ALCHEMY_SERVER"),
		String(ProjectSettings.get_setting("application/config/alchemy_server", "")),
		OS.is_debug_build())
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	# в selftest сеть не трогаем (герметичный прогон); пустой base_url = «сервера
	# нет» (F1: релиз без https-настройки) — пинг не шлём совсем.
	if base_url != "" and not SelftestMode.enabled():
		_ping()

# Чистый шов разрешения базового URL: env → ProjectSettings → DEFAULT_BASE.
# HTTPS-only часть релиза: итог начинается с http:// и это не debug-сборка → ""
# (тихая подмена схемы увела бы запросы на чужой домен при ALCHEMY_SERVER=http://…).
static func resolve_base_url(env_value: String, setting_value: String, is_debug: bool) -> String:
	var url := env_value.strip_edges()
	if url == "":
		url = setting_value.strip_edges()
	if url == "":
		url = DEFAULT_BASE
	if not is_debug and url.begins_with("http://"):
		return ""
	return url

func is_available() -> bool:
	return _available

func _ping() -> void:
	_enqueue({"kind": "ping", "path": "/health"})

func check_pair(a: String, b: String, nick: String, device_id: String, experiment := false) -> void:
	_enqueue({
		"kind": "brew-check", "pair_key": _pair_key(a, b),
		"body": {"a": a, "b": b, "nick": nick, "device_id": device_id, "experiment": experiment},
	})

func discover(a: String, b: String, nick: String, device_id: String, experiment := false) -> void:
	_enqueue({
		"kind": "discover", "pair_key": _pair_key(a, b),
		"body": {"a": a, "b": b, "nick": nick, "device_id": device_id, "experiment": experiment},
	})

func world(page: int = 1) -> void:
	_enqueue({"kind": "world", "path": "/world?page=%d&per_page=100" % page})

func hall() -> void:
	_enqueue({"kind": "hall", "path": "/hall-of-fame"})

func events() -> void:
	_enqueue({"kind": "events", "path": "/events?limit=12"})

func challenge(device_id: String = "") -> void:
	var path := "/challenge"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "challenge", "path": path})

func me(nick: String, device_id: String) -> void:
	_enqueue({
		"kind": "me",
		"body": {"nick": nick, "device_id": device_id},
	})

func export_account(device_id: String) -> void:
	_enqueue({
		"kind": "account_export",
		"path": "/account/export?device_id=" + device_id.uri_encode(),
	})

func delete_account(device_id: String) -> void:
	_enqueue({
		"kind": "account_delete",
		"path": "/account?device_id=" + device_id.uri_encode(),
		"method": HTTPClient.METHOD_DELETE,
	})

func rejected() -> void:
	_enqueue({"kind": "rejected", "path": "/rejected"})

func house_get(nick: String) -> void:
	_enqueue({"kind": "house", "path": "/house?nick=" + nick.uri_encode()})

func house_save(device_id: String, nick: String, house: Dictionary) -> void:
	# v24: POST на явный путь /house (раньше уходило на несуществующий /house_save
	# и молча падало в 404 — выгрузка домиков не работала).
	_enqueue({
		"kind": "house_save", "path": "/house",
		"body": {"device_id": device_id, "nick": nick, "house": house},
	})

func house_visit(device_id: String, host_nick: String) -> void:
	_enqueue({
		"kind": "house_visit", "path": "/house/visit",
		"body": {"device_id": device_id, "host_nick": host_nick},
	})

func rating(device_id: String = "") -> void:
	var path := "/rating"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "rating", "path": path})

func echoes(device_id: String) -> void:
	var path := "/echoes"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "echoes", "path": path})

func echoes_claim(device_id: String) -> void:
	_enqueue({
		"kind": "echoes_claim", "path": "/echoes/claim",
		"body": {"device_id": device_id},
	})

func letter_today(device_id: String) -> void:
	var path := "/letter/today"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "letter", "path": path})

func letter_solve(device_id: String, a: String, b: String) -> void:
	_enqueue({
		"kind": "letter_solve", "path": "/letter/solve",
		"body": {"device_id": device_id, "a": a, "b": b},
	})

func atlas_today(device_id: String) -> void:
	var path := "/atlas/today"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "atlas", "path": path})

func atlas_solve(device_id: String, a: String, b: String) -> void:
	_enqueue({
		"kind": "atlas_solve", "path": "/atlas/solve",
		"body": {"device_id": device_id, "a": a, "b": b},
	})

func week_status(device_id: String) -> void:
	var path := "/week/status"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "week", "path": path})

func fair_brew(device_id: String, a: String, b: String) -> void:
	_enqueue({
		"kind": "fair_brew", "path": "/fair/brew",
		"body": {"device_id": device_id, "a": a, "b": b},
	})

func fair_claim(device_id: String) -> void:
	_enqueue({
		"kind": "fair_claim", "path": "/fair/claim",
		"body": {"device_id": device_id},
	})

# План 2 (Круг+Жила, клиент): регистрация личного находки, церемония вливания,
# статус цикла жилы. Ответы — см. серверные модели VeinFindResponse /
# VeinPourResponse / CycleStatusResponse (server.py).
func vein_find(device_id: String, pair_key: String, tag: String, cycle_id: String) -> void:
	_enqueue({
		"kind": "vein_find", "path": "/vein/find", "pair_key": pair_key,
		"body": {"device_id": device_id, "pair_key": pair_key, "tag": tag, "cycle_id": cycle_id},
	})

func vein_pour(device_id: String, idempotency_key: String) -> void:
	_enqueue({
		"kind": "vein_pour", "path": "/vein/pour", "find_id": idempotency_key,
		"body": {"device_id": device_id, "idempotency_key": idempotency_key},
	})

func cycle_status(device_id: String) -> void:
	var path := "/vein/cycle/status"
	if device_id != "":
		path += "?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "cycle", "path": path})

# Аркан Сигилов: ежедневные крафты и крафт карточки.
func sigil_daily(device_id: String) -> void:
	var path := "/sigil/daily?device_id=" + device_id.uri_encode()
	_enqueue({"kind": "sigil_daily", "path": path})

func sigil_craft(device_id: String, craft_id: String) -> void:
	_enqueue({
		"kind": "sigil_craft", "path": "/sigil/craft",
		"body": {"device_id": device_id, "craft_id": craft_id},
	})

## Каталог карт: статический артефакт сервера, device_id не нужен.
func sigil_catalog() -> void:
	_enqueue({"kind": "sigil_catalog", "path": "/sigil/catalog"})

## Коллекция игрока: копии карт и внекомплектные крафты.
func sigil_collection(device_id: String) -> void:
	_enqueue({
		"kind": "sigil_collection",
		"path": "/sigil/collection?device_id=" + device_id.uri_encode(),
	})

# T22: серверная проверка платёжного чека (POST /api/receipt/verify). Ответ —
# сигнал receipt_verify_result: {"ok", "verified", "status", "reason",
# "receipt_hash"} либо офлайн-форма {"ok": false, "offline": true}. Сырой токен
# уходит на сервер один раз по запросу; в ответе сервера его нет (только SHA-256).
func receipt_verify(device_id: String, provider: String, sku: String, receipt_token: String) -> void:
	_enqueue({
		"kind": "receipt_verify", "path": "/receipt/verify",
		"body": {
			"device_id": device_id, "provider": provider,
			"sku": sku, "receipt_token": receipt_token,
		},
	})

func _pair_key(a: String, b: String) -> String:
	var p := PackedStringArray([a, b])
	p.sort()
	return "|".join(p)

func _enqueue(req: Dictionary) -> void:
	_queue.append(req)
	if _inflight.is_empty():
		_send_next()

func _build_request(req: Dictionary) -> Dictionary:
	# чистая сборка запроса (URL + метод + тело) — покрыто selftest'ом
	var url := base_url
	if req.has("path"):
		url += String(req["path"])
	else:
		url += "/" + String(req.get("kind", ""))
	var method := int(req.get("method", HTTPClient.METHOD_POST if req.has("body") else HTTPClient.METHOD_GET))
	var body := ""
	if req.has("body"):
		body = JSON.stringify(req.get("body", {}))
	return {"url": url, "method": method, "body": body}

func _drain_offline(message: String) -> void:
	# Снимок длины + проверка пустоты на каждой итерации. Подписчик, синхронно
	# enqueue-нувшийся во время _dispatch, вызывает вложенный _send_next (из
	# _enqueue), а тот разбирает очередь целиком — включая элементы, до которых
	# внешнему циклу ещё «дойти». Без guard'а следующий pop_front() на пустой
	# очереди даёт null → рантайм-ошибка в autoload. Guard оборонительный: два
	# известных в проекте enqueue-из-колбэка (online.gd:486 discover, online.gd:753
	# следующая страница мира) гейтятся `ok == true` (online.gd:481, :737), а
	# offline-ответ его не даёт — то есть сегодня из этого цикла они не достижимы.
	# Оставлен, потому что достижимость зависит от подписчиков вне этого файла.
	# Порядок — как в T13-ветке: сначала гасим inflight (тут гасить нечего),
	# потом _dispatch. ping в _dispatch = pass, поэтому _available остаётся
	# false (сервер не трогали).
	var count := _queue.size()
	for _i in count:
		if _queue.is_empty():
			return
		var req: Dictionary = _queue.pop_front()
		_dispatch(req, {"ok": false, "offline": true, "message": message})

func _send_next() -> void:
	if base_url == "":
		# «Сервера нет» (F1) ≠ «забыли очередь»: закрываем каждый элемент
		# offline-результатом тем же путём, что и рабочий T13-cleanup, иначе
		# подписчики (рейтинг/мир/удаление аккаунта) остаются с предзаполненным
		# статусом навсегда. HTTP не пробуем совсем.
		_drain_offline("сервер не настроен")
		return
	# Re-entrant _send_next (подписчик синхронно enqueue-нулся во время _dispatch)
	# не должен перетирать живой _inflight — продолжение идёт из следующего
	# _on_completed / drain.
	if not _inflight.is_empty():
		return
	if _queue.is_empty():
		return
	var req: Dictionary = _queue.pop_front()
	var built := _build_request(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	_inflight = req
	var err := _try_send(String(built["url"]), headers, int(built["method"]), String(built["body"]))
	if err != OK:
		# Запрос не стартовал — _on_completed по нему не придёт никогда.
		# Общий cleanup для ЛЮБОГО kind (T13): порядок ровно как в известном
		# рабочем пути _on_completed: сначала гасим _inflight, затем _dispatch,
		# затем _send_next. ping дополнительно помечает недоступность сервера —
		# это единственная special-case ветка. Рекурсия хвостовым _send_next()
		# даёт глубину = длина очереди; очередь штатно маленькая (мир/рейтинги/
		# эксперименты), поэтому это приемлемо, а не неограниченный стек.
		if String(req.get("kind", "")) == "ping":
			_available = false
		_inflight = {}
		_dispatch(req, {"ok": false, "offline": true, "message": "не удалось отправить запрос"})
		_send_next()

# Единственная точка выхода в HTTP. В прод-поведении идентична прямому вызову
# _http.request(...); нужна как seam для selftest (см. suite_resonance_net.gd),
# чтобы эмулировать err != OK на старте запроса без живого сервера.
func _try_send(url: String, headers: PackedStringArray, method: int, body: String) -> int:
	if SelftestMode.enabled():
		# Герметичный прогон: сокет не открываем НИКОГДА. Раньше skip касался
		# только _ping(), а production-вызовы (main.gd `_refetch_world` на
		# вкладке «Мир» гейта по selftest не имеет) уходили живым сокетом на
		# 127.0.0.1 — и глобальные ассерты сюит на «очереди нет» краснели от
		# чужого трафика. «Запрос не стартовал» — ровно рабочий путь err != OK:
		# тот же offline-результат, тот же синхронный слив очереди. base_url не
		# трогаем: склейку базы с путём меряют кейсы «net … route».
		return ERR_CANT_CONNECT
	return _http.request(url, headers, method, body)

func _on_completed(result: int, response_code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
	var req: Dictionary = _inflight
	_inflight = {}
	var parsed := {}
	if response_code >= 200 and response_code < 300:
		parsed = _parse(data)
		if parsed.is_empty():
			# 200 с не-JSON телом — это не наш API, а заглушка/антибот хостинга или
			# прокси-страница. Раньше эта ветка ставила _available = true и сливала
			# подписчикам пустой словарь: игра считала сервер здоровым, не уходила в
			# офлайн и оставалась с предзаполненными статусами навсегда.
			parsed = {"ok": false, "offline": true, "message": "сервер вернул не-JSON ответ"}
			_available = false
		else:
			if not parsed.has("ok"):
				parsed["ok"] = true
			_available = true
	elif result != HTTPRequest.RESULT_SUCCESS:
		parsed = {"ok": false, "offline": true, "message": "нет ответа от сервера"}
		_available = false
	else:
		parsed = {"ok": false, "error": "HTTP %d" % response_code, "message": "HTTP %d" % response_code}
		# I-1 (T28): человекочитаемая причина отказа живёт в теле non-2xx по ключу
		# "detail" (сервер: /api/me → «Ник уже занят»). Аддитивно: error/message
		# не трогаем — их читают по точным строкам tests/suite_journal_misc и
		# tests/suite_resonance_net, а monetization.gd — по префиксу «HTTP 5».
		# Кейсы-мутанты: «t28 net extracts string detail» (удаление этого блока)
		# и «t28 net ignores non string detail» (снятие typeof-гейта или записи
		# detail без проверки — словарь/мусорное тело ушло бы вверх вместо отказа).
		var body := _parse(data)
		if typeof(body.get("detail", null)) == TYPE_STRING:
			parsed["detail"] = String(body["detail"])
	_dispatch(req, parsed)
	_send_next()

func _parse(data: PackedByteArray) -> Dictionary:
	var text := data.get_string_from_utf8()
	var j: Variant = JSON.parse_string(text)
	if typeof(j) == TYPE_DICTIONARY:
		return j as Dictionary
	return {}

func _dispatch(req: Dictionary, parsed: Dictionary) -> void:
	match String(req.get("kind", "")):
		"ping":
			pass
		"brew-check":
			pair_result.emit(String(req["pair_key"]), parsed)
		"discover":
			discover_result.emit(String(req["pair_key"]), parsed)
		"world":
			world_result.emit(parsed)
		"hall":
			hall_result.emit(parsed)
		"events":
			events_result.emit(parsed)
		"challenge":
			challenge_result.emit(parsed)
		"me":
			me_result.emit(parsed)
		"account_export":
			account_export_result.emit(parsed)
		"account_delete":
			account_delete_result.emit(parsed)
		"rejected":
			rejected_result.emit(parsed)
		"house":
			house_result.emit(parsed)
		"house_save":
			parsed["_saved"] = true
			house_result.emit(parsed)
		"house_visit":
			house_visit_result.emit(parsed)
		"rating":
			rating_result.emit(parsed)
		"echoes":
			echoes_result.emit(parsed)
		"echoes_claim":
			echoes_claim_result.emit(parsed)
		"letter":
			letter_result.emit(parsed)
		"letter_solve":
			letter_solve_result.emit(parsed)
		"atlas":
			atlas_result.emit(parsed)
		"atlas_solve":
			atlas_solve_result.emit(parsed)
		"week":
			week_result.emit(parsed)
		"fair_brew":
			fair_brew_result.emit(parsed)
		"fair_claim":
			fair_claim_result.emit(parsed)
		"receipt_verify":
			receipt_verify_result.emit(parsed)
		"vein_find":
			vein_find_result.emit(String(req.get("pair_key", "")), parsed)
		"vein_pour":
			vein_pour_result.emit(String(req.get("find_id", "")), parsed)
		"cycle":
			cycle_result.emit(parsed)
		"sigil_daily":
			sigil_daily_result.emit(parsed)
		"sigil_craft":
			sigil_craft_result.emit(parsed)
		"sigil_catalog":
			sigil_catalog_result.emit(parsed)
		"sigil_collection":
			sigil_collection_result.emit(parsed)
