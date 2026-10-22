extends RefCounted
class_name Social
# Состояние S1-социалки: снапшот /api/social/inbox, ленты по парам,
# оптимистичная отправка, сейв-ключи. Сеть — только через Net-сигналы,
# которые маршрутизирует main.gd (Task 3). Чистые функции — static, чтобы
# selftest звал их без сборки Game.

const SPIRIT_DEVICE := "npc-spirit"
const SPIRIT_NICK := "Светик"

var g: Game
var cache := {}                       # снапшот inbox
var threads := {}                     # peer_device -> Array[Dictionary]
var last_read_id := {}                # peer_device -> int (для since_id)
var optimistic := {}                  # peer_device -> Array pending-письмо
var prev_total := -1                  # до последнего inbox: СУММА unread+requests
                                      # (спека 542/575: бейдж и тост считают сумму)
var _awaiting_peer := ""              # R3: контекст для messages_result
var _session_toast_shown := false     # R4

func _init(game: Game) -> void:
	g = game

static func badge_for(unread: int) -> String:
	if unread <= 0:
		return "Друзья"
	if unread > 99:
		return "Друзья •99+"
	return "Друзья •" + str(unread)

static func last_seen_text(iso: String, today: String) -> String:
	if iso.length() < 10 or today.length() < 10:
		return ""
	var d := iso.substr(0, 10)
	var t := today.substr(0, 10)
	if d == t:
		return "был(а) сегодня"
	# Time.get_datetime_dict_from_string в 4.7 нет — разбираем через
	# get_unix_time_from_datetime_string (тот же приём, что retention.gd:578);
	# «T00:00:00» доклеиваем, чтобы строка точно прошла datetime-парсер.
	# Нерразобранная дата даёт 0 — фолбэк пустой строкой без ложного «0 дней».
	var du := int(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	var tu := int(Time.get_unix_time_from_datetime_string(t + "T00:00:00"))
	if du == 0 or tu == 0:
		return ""
	var days := tu / 86400 - du / 86400
	if days <= 0:
		return "был(а) сегодня"
	if days == 1:
		return "был(а) вчера"
	return "был(а) " + str(days) + " " + _days_word(days) + " назад"

static func _days_word(n: int) -> String:
	# Русская плюрализация счётчика дней: 1 день, 2-4 дня, 5+ дней.
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return "день"
	if m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14):
		return "дня"
	return "дней"

static func preview_cut(body: String, max_len: int) -> String:
	body = body.replace("\n", " ")
	if body.length() <= max_len:
		return body
	# Многоточие учитывается внутри max_len: итог всегда ≤ max_len даже при
	# жёсткой резке без пробела; sp >= 0 (а не > 0) — ведущий пробел тоже
	# схлопывается в «…», а не даёт результат длины max_len+1.
	var cut := body.substr(0, max_len - 1)
	var sp := cut.rfind(" ")
	if sp >= 0:
		cut = cut.substr(0, sp)
	return cut + "…"

func refresh() -> void:
	Net.social_inbox(g._online._device_id)

func on_inbox(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	prev_total = total()
	cache = result

func friends() -> Array: return cache.get("friends", [])
func incoming() -> Array: return cache.get("incoming", [])
func outgoing() -> Array: return cache.get("outgoing", [])
func unread_total() -> int: return int(cache.get("unread_total", 0))
func requests_total() -> int: return int(cache.get("requests_total", 0))
## Входящие офферы (S2): «партнёр ждёт моего действия». Специально НЕ включает
## мои исходящие — напоминание о собственном ожидании это шум (спека §8.5).
func trades_pending() -> int: return int(cache.get("trades_pending", 0))
func total() -> int: return unread_total() + requests_total() + trades_pending()

func friend_by_device(dev: String) -> Dictionary:
	for f in friends():
		if f.get("device_id", "") == dev:
			return f
	return {}

func friend_by_nick(nick: String) -> Dictionary:
	for f in friends():
		if f.get("nick", "") == nick:
			return f
	return {}

func is_outgoing_to(nick: String) -> bool:
	for o in outgoing():
		if o.get("nick", "") == nick:
			return true
	return false

func set_awaiting_peer(peer: String) -> void:
	_awaiting_peer = peer

func load_thread(peer: String) -> void:
	set_awaiting_peer(peer)
	Net.messages(g._online._device_id, peer, int(last_read_id.get(peer, 0)))

func on_messages(result: Dictionary) -> void:
	var peer := _awaiting_peer
	if peer == "" or result.get("ok", false) != true:
		return
	var rows: Array = []
	for m in result.get("messages", []):
		if m is Dictionary:
			rows.append(m)
	rows.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	threads[peer] = rows
	# FIX-A: асинхронный прилёт от живого сервера обязан перерисовать открытую
	# ленту этого пира — иначе экран остаётся наpre-response кэше (а после
	# успешной отправки optimistic-хвост стёрт, и refresh_thread из on_send
	# рисует СТАРЫЙ снапшот: своё письмо невидимкой). Только что записанный
	# threads[peer] — свежий источник; перерисовка ровно для видимого пира.
	if g._social_ui != null and g._social_ui.visible_thread() == peer:
		g._social_ui.refresh_thread()

func thread(peer: String) -> Array:
	var out: Array = threads.get(peer, []).duplicate()
	for p in optimistic.get(peer, []):
		out.append(p)
	return out

func optimistic_send(peer: String, body: String) -> void:
	if not optimistic.has(peer):
		optimistic[peer] = []
	optimistic[peer].append({"id": -1, "from_me": true, "body": body,
		"sent_at": "", "pending": true})

func on_send(result: Dictionary) -> void:
	# Отказ любого вида — снимаем ВСЕ pending текущего ожидаемого пира: текст
	# не доставлен, клиент обязан это показать честной лентой (урок Fix #3).
	var peer := _awaiting_peer
	if result.get("ok", false) == true:
		# Блуждающий ok без ожидающего пира: не дёргаем Net.messages(dev,"",0)
		# и не троим ленты — тот же guard, что в ветке отказа ниже.
		if peer == "":
			return
		optimistic.erase(peer)
		load_thread(peer)          # добрать серверный id/sent_at
		if g._social_ui != null and g._social_ui.visible_thread() == peer:
			g._social_ui.refresh_thread()
		return
	if peer != "":
		optimistic.erase(peer)
		if g._social_ui != null:
			# F4: detail нетипизирован — при 422 сервер шлёт СПИСОК, в String-
			# параметр show_send_error его не гоним (паттерн main.gd
			# `_on_friend_respond`); при отсутствии detail (offline-отказ)
			# молча исчезать pending-пузырьку не даём — показываем офлайн-текст.
			var detail = result.get("detail", "")
			if detail is String and detail != "":
				g._social_ui.show_send_error(detail)
			elif detail is String and result.get("offline", false) == true:
				g._social_ui.show_send_error("offline")
			else:
				g._social_ui.show_send_error("unmapped")

func send_message(peer: String, body: String) -> void:
	set_awaiting_peer(peer)
	optimistic_send(peer, body)
	Net.message_send(g._online._device_id, peer, body)
	if g._social_ui != null:
		g._social_ui.refresh_thread()

func should_show_toast() -> bool:
	# FIX-C (спека 542): тост при росте СУММЫ unread+requests, не одного unread.
	if _session_toast_shown or total() <= 0:
		return false
	return prev_total != total()

func mark_toast_shown() -> void:
	_session_toast_shown = true

func to_save() -> Dictionary:
	return {"social_cache": cache, "social_last_read": last_read_id}

func from_save(data: Dictionary) -> void:
	cache = data.get("social_cache", {}) if data.get("social_cache", {}) is Dictionary else {}
	last_read_id = data.get("social_last_read", {}) if data.get("social_last_read", {}) is Dictionary else {}

func _seed_demo() -> void:
	# Только для --demo --action=social (R5). Синтетический мир приёмки.
	cache = {"friends": [
		{"device_id": "npc-spirit", "nick": SPIRIT_NICK, "unread": 1,
			"avatar": {}, "last_seen": "",
			"last_msg_at": "2026-10-10T08:00:00",
			"last_msg_preview": "Ты вернулся. Печь помнит твои руки."},
		{"device_id": "dev-b", "nick": "Николя", "unread": 2,
			"avatar": {}, "last_seen": "2026-10-10T07:10:00",
			"last_msg_at": "2026-10-10T07:10:00",
			"last_msg_preview": "Скинул тебе серную печать, забери у дома."},
		{"device_id": "dev-c", "nick": "Аня", "unread": 0,
			"avatar": {}, "last_seen": "2026-10-07T18:00:00",
			"last_msg_at": "2026-10-07T18:00:00",
			"last_msg_preview": "Круг на вчера — красавец."}],
		"incoming": [{"device_id": "dev-d", "nick": "Варя", "avatar": {},
			"last_seen": "2026-10-10T06:00:00", "requested_at": ""}],
		"outgoing": [{"nick": "Мирра", "requested_at": ""}],
		"unread_total": 3, "requests_total": 1, "friend_limit": 50}
	threads["dev-b"] = [
		{"id": 10, "from_me": false, "body": "Как тебе второй круг?", "sent_at": "2026-10-09T19:00:00"},
		{"id": 11, "from_me": true, "body": "Стабильнее первого. Но эфир жрёт.", "sent_at": "2026-10-09T19:05:00"},
		{"id": 12, "from_me": false, "body": "Скинул тебе серную печать, забери у дома.", "sent_at": "2026-10-10T07:10:00"}]
	threads["npc-spirit"] = [
		{"id": 20, "from_me": false, "body": "Ты вернулся. Печь помнит твои руки.", "sent_at": "2026-10-10T08:00:00"}]
