extends RefCounted
class_name SuiteSocial
# S1 «Друзья и переписка» (клиент): net-методы, кэш Social, экран SocialUI,
# бейдж, тост, Esc/z-order, сейв-ключи. Герметично: Net в ST drenage-offline,
# поэтому сборку запросов проверяем через _build_request (шаблон
# suite_resonance_net.gd:72-80), состояние — прямыми эмиссиями результата.
# Мутации, красящие этот блок: удалить/переименовать метод, сменить path,
# перепутать поле body, снять signal-эмиссию в _dispatch.

static func run(g: Game) -> void:
	_net_requests(g)
	_dispatch_emits(g)
	_pure_logic(g)
	_cache(g)
	_save_keys(g)
	_wiring(g)
	_screen(g)
	_thread(g)
	_confirm(g)
	_search_helpers(g)

static func _net_requests(_g: Game) -> void:
	# вызов реальных методов: в ST Net синхронно сливает очередь в offline,
	# поэтому вызовы безопасны и доказывают, что методы существуют и не падают
	Net.social_inbox("dev 1")
	Net.messages("dev1", "dev2", 7)
	Net.message_send("dev1", "dev2", "прив")
	Net.friend_request("dev1", "Николя")
	Net.friend_respond("dev1", "dev2", true)
	Net.friend_remove("dev1", "dev2")
	Net.friend_block("dev1", "dev2")
	Net.friend_unblock("dev1", "dev2")
	# сборка запроса проверяется через generic _build_request (Net — синглтон)
	var r: Dictionary = Net._build_request({
		"kind": "social_inbox", "path": "/social/inbox?device_id=dev%201"})
	Selftest.check("social inbox GET path",
		int(r["method"]) == HTTPClient.METHOD_GET
		and String(r["url"]).ends_with("/api/social/inbox?device_id=dev%201"))
	r = Net._build_request({"kind": "messages",
		"path": "/messages?device_id=dev1&peer_device=dev2&since_id=7"})
	Selftest.check("messages GET path",
		int(r["method"]) == HTTPClient.METHOD_GET
		and String(r["url"]).contains("/api/messages?")
		and String(r["url"]).ends_with("since_id=7"))
	r = Net._build_request({"kind": "message_send", "path": "/message/send",
		"body": {"device_id": "dev1", "peer_device": "dev2", "body": "прив"}})
	Selftest.check("send POST body", int(r["method"]) == HTTPClient.METHOD_POST
		and JSON.parse_string(r["body"]) == {"device_id": "dev1", "peer_device": "dev2", "body": "прив"})
	r = Net._build_request({"kind": "friend_request", "path": "/friend/request",
		"body": {"device_id": "dev1", "target_nick": "Николя"}})
	Selftest.check("friend request POST", int(r["method"]) == HTTPClient.METHOD_POST
		and JSON.parse_string(r["body"])["target_nick"] == "Николя")

static func _dispatch_emits(_g: Game) -> void:
	# Каждый из 8 social-сигналов обязан прийти ровно один раз на свой kind:
	# ловит снятие/порчу ветки `signal.emit(parsed)` в Net._dispatch.
	# _dispatch(req, parsed): первый аргумент — запись очереди (важен "kind"),
	# второй — разобранный ответ; герметично вызываем напрямую, без сети.
	var counts := {}
	Net.social_inbox_result.connect(func(_r: Dictionary) -> void: counts["social_inbox"] = int(counts.get("social_inbox", 0)) + 1)
	Net.messages_result.connect(func(_r: Dictionary) -> void: counts["messages"] = int(counts.get("messages", 0)) + 1)
	Net.message_send_result.connect(func(_r: Dictionary) -> void: counts["message_send"] = int(counts.get("message_send", 0)) + 1)
	Net.friend_request_result.connect(func(_r: Dictionary) -> void: counts["friend_request"] = int(counts.get("friend_request", 0)) + 1)
	Net.friend_respond_result.connect(func(_r: Dictionary) -> void: counts["friend_respond"] = int(counts.get("friend_respond", 0)) + 1)
	Net.friend_remove_result.connect(func(_r: Dictionary) -> void: counts["friend_remove"] = int(counts.get("friend_remove", 0)) + 1)
	Net.friend_block_result.connect(func(_r: Dictionary) -> void: counts["friend_block"] = int(counts.get("friend_block", 0)) + 1)
	Net.friend_unblock_result.connect(func(_r: Dictionary) -> void: counts["friend_unblock"] = int(counts.get("friend_unblock", 0)) + 1)
	for kind in ["social_inbox", "messages", "message_send", "friend_request",
			"friend_respond", "friend_remove", "friend_block", "friend_unblock"]:
		Net._dispatch({"kind": String(kind)}, {})
	Selftest.check("dispatch emits social_inbox", int(counts.get("social_inbox", 0)) == 1)
	Selftest.check("dispatch emits messages", int(counts.get("messages", 0)) == 1)
	Selftest.check("dispatch emits message_send", int(counts.get("message_send", 0)) == 1)
	Selftest.check("dispatch emits friend_request", int(counts.get("friend_request", 0)) == 1)
	Selftest.check("dispatch emits friend_respond", int(counts.get("friend_respond", 0)) == 1)
	Selftest.check("dispatch emits friend_remove", int(counts.get("friend_remove", 0)) == 1)
	Selftest.check("dispatch emits friend_block", int(counts.get("friend_block", 0)) == 1)
	Selftest.check("dispatch emits friend_unblock", int(counts.get("friend_unblock", 0)) == 1)

static func _pure_logic(g: Game) -> void:
	# Мутации: сменить порог «99+», сломать «вчера», обрезать пословно не по
	# пробелу, применить not-ok инбокс поверх кэша, не откатить optimistic.
	Selftest.check("badge 0 -> plain", Social.badge_for(0) == "Друзья")
	Selftest.check("badge 2 -> dot", Social.badge_for(2) == "Друзья •2")
	Selftest.check("badge 150 -> cap", Social.badge_for(150) == "Друзья •99+")
	Selftest.check("seen today", Social.last_seen_text("2026-10-10T09:00:00", "2026-10-10") == "был(а) сегодня")
	Selftest.check("seen yesterday", Social.last_seen_text("2026-10-09T23:59:59", "2026-10-10") == "был(а) вчера")
	Selftest.check("seen 3 days", Social.last_seen_text("2026-10-07T09:00:00", "2026-10-10") == "был(а) 3 дня назад")
	Selftest.check("seen empty", Social.last_seen_text("", "2026-10-10") == "")
	Selftest.check("preview short", Social.preview_cut("привет", 60) == "привет")
	Selftest.check("preview cut word", Social.preview_cut("a b c d e f g h i j k l m n o p q r s t u v w x y z a b c d e f g h i j k l m n o p q r s t u v w x y z", 60).length() <= 60)
	Selftest.check("preview no-space fits", Social.preview_cut("х".repeat(80), 60).length() <= 60)

static func _cache(g: Game) -> void:
	# Мутации: ok=false затирает кэш; absent keys падают; 422-список роняет
	# разбор; optimistic не убирается при отказе.
	var s := Social.new(g)
	s.on_inbox({"ok": false, "detail": "not_registered"})
	Selftest.check("not ok keeps cache empty", s.friends().is_empty())
	s.on_inbox({"ok": true, "friends": [
		{"device_id": "npc-spirit", "nick": "Светик", "unread": 1,
		 "last_msg_preview": "Здравствуй", "last_msg_at": "2026-10-10T08:00:00",
		 "last_seen": "", "avatar": {}},
		{"device_id": "dev-b", "nick": "Николя", "unread": 0,
		 "last_msg_preview": "", "last_msg_at": "", "last_seen": "2026-10-09T12:00:00",
		 "avatar": {}}],
		"incoming": [{"device_id": "dev-c", "nick": "Аня", "avatar": {},
			"last_seen": "", "requested_at": "2026-10-10T07:00:00"}],
		"outgoing": [{"nick": "Варя", "requested_at": ""}],
		"unread_total": 1, "requests_total": 1, "friend_limit": 50})
	Selftest.check("inbox applied", s.friends().size() == 2 and s.unread_total() == 1)
	Selftest.check("friend by nick", s.friend_by_nick("Николя").get("device_id", "") == "dev-b")
	Selftest.check("outgoing by nick", s.is_outgoing_to("Варя"))
	s.set_awaiting_peer("dev-b")
	s.on_send({"ok": false, "offline": true})
	s.optimistic_send("dev-b", "горстка")
	Selftest.check("optimistic visible", s.thread("dev-b").size() == 1
		and s.thread("dev-b")[0].get("pending", false))
	s.on_send({"ok": false, "detail": "daily_limit"})
	Selftest.check("optimistic rolled back", s.thread("dev-b").is_empty())

static func _save_keys(g: Game) -> void:
	# Мутации: key переименован; старый сейв без ключей роняет загрузку.
	var s := Social.new(g)
	s.on_inbox({"ok": true, "friends": [{"device_id": "d", "nick": "N", "unread": 2}],
		"incoming": [], "outgoing": [], "unread_total": 2, "requests_total": 0})
	var data := s.to_save()
	Selftest.check("save shape", data.has("social_cache") and data.has("social_last_read"))
	var t := Social.new(g)
	t.from_save({})                       # старый сейв — не падает
	Selftest.check("legacy save ok", t.friends().is_empty())
	t.from_save(data)
	Selftest.check("roundtrip", t.unread_total() == 2)

static func _wiring(g: Game) -> void:
	# Мутации: убрать кнопку «Друзья» из ether_row, сузить её ниже 96,
	# не звать _refresh_header после inbox (бейдж не отрендерится).
	# Проверки экрана (z-группа, скрытость) — в сюите Task 4,SocialUI ещё нет.
	# g.get() вместо g._social_btn: до реализации поля прямой доступ дал бы
	# SCRIPT ERROR и молча сорвал бы прогон — а нам нужны честные FAIL-строки.
	var b: Button = g.get("_social_btn")
	Selftest.check("social button exists", b != null)
	Selftest.check("button width holds badge", b != null and b.custom_minimum_size.x >= 96)
	g._social.on_inbox({"ok": true, "friends": [], "incoming": [],
		"outgoing": [], "unread_total": 2, "requests_total": 0})
	g._engine._refresh_header()
	Selftest.check("badge renders after inbox", b != null and b.text == "Друзья •2")
	# Не оставляем мусор в живом кэше: ниже по прогону идут другие сюиты.
	g._social.on_inbox({"ok": true, "friends": [], "incoming": [],
		"outgoing": [], "unread_total": 0, "requests_total": 0})
	g._engine._refresh_header()


static func _screen(g: Game) -> void:
	var ui = g.get("_social_ui")
	Selftest.check("social screen built", ui != null and ui._screen != null)
	if ui == null or ui._screen == null:
		return
	Selftest.check("social screen hidden", not ui._screen.visible)
	Selftest.check("social screen z20 group", ui._screen.z_index == 20
		and ui._screen.is_in_group("modal_ui"))
	g._social._seed_demo()
	ui.open(0)
	Selftest.check("friends segment", ui._tab == 0 and ui._body != null)
	ui.open(1)
	Selftest.check("requests segment", ui._tab == 1 and ui._body != null)
	ui.close()


static func _thread(g: Game) -> void:
	var ui = g.get("_social_ui")
	if ui == null:
		Selftest.check("social thread available", false)
		return
	g._social._seed_demo()
	ui.open(0)
	ui._open_thread("dev-b")
	Selftest.check("thread opens", ui._peer == "dev-b")
	Selftest.check("thread has bubbles", ui._body.find_child("Bubble_0", true, false) != null
		and ui._body.find_child("Bubble_2", true, false) != null)
	ui._close_thread()
	Selftest.check("thread closes to list", ui._peer == "")
	ui._open_thread(Social.SPIRIT_DEVICE)
	Selftest.check("spirit has no input", ui._body.find_child("SpiritNoInput", true, false) != null
		and ui._body.find_child("ThreadInput", true, false) == null)
	ui.close()


static func _confirm(g: Game) -> void:
	var ui = g.get("_social_ui")
	if ui == null:
		Selftest.check("social confirm available", false)
		return
	g._social._seed_demo()
	ui.open(0)
	ui._open_confirm("dev-b")
	var body: Label = null
	if ui._confirm != null:
		body = ui._confirm.find_child("ConfirmBody", true, false) as Label
	Selftest.check("confirm z21", ui._confirm != null and ui._confirm.z_index == 21)
	Selftest.check("confirm honest copy", body != null
		and String(body.text).contains("Николя")
		and String(body.text).contains("будет удалена у вас обоих"))
	ui._confirm_close()
	ui.close()


static func _search_helpers(g: Game) -> void:
	var s := Social.new(g)
	s._seed_demo()
	Selftest.check("friend state text", SocialUI._friend_state_text("Николя", s) == "в друзьях"
		and SocialUI._friend_state_text("Мирра", s) == "заявка отправлена"
		and SocialUI._friend_state_text("Некто", s) == "в друзья")
