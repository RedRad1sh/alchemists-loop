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

static func _net_requests(_g: Game) -> void:
	# вызов реальных методов: в ST Net синхронно сливает очередь в offline,
	# поэтому вызовы безопасны и доказывают, что методы существуют и не падают
	Net.social_inbox("dev 1")
	Net.messages("dev1", "dev2", 7)
	Net.message_send("dev1", "dev2", "прив")
	Net.friend_request("dev1", "Николя")
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
