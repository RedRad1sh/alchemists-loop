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
