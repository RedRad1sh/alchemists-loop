extends Node

const GameScript = preload("res://main.gd")
var g: Game
var result: Dictionary = {}

func _ready() -> void:
	g = load("res://main.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g._online._net_enabled = false
	g._online._device_id = "avatar-acceptance"
	Net.base_url = "http://127.0.0.1:8891/api"
	g._hub._open_profile()
	g._hub._profile_nick.text = "Varda"
	g._hub._choose_profile_gender("female")
	g._hub._save_profile()
	var http := HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.timeout = 10.0
	var request: Dictionary = Net._build_request({"kind": "me", "body": {"nick": g._online._net_nick, "device_id": g._online._device_id, "avatar_gender": g._online._avatar_gender}})
	print("AVATAR_REQUEST ", request)
	var err := http.request(request.url, PackedStringArray(["Content-Type: application/json"]), request.method, request.body)
	if err == OK:
		var response: Array = await http.request_completed
		var text := (response[3] as PackedByteArray).get_string_from_utf8()
		print("AVATAR_RESPONSE ", response[0], " ", response[1], " ", text.substr(0, 300))
		if response[1] == 200:
			result = JSON.parse_string(text)
	var valid: bool = result.get("ok", false) and result.get("avatar_gender") == "female" and result.get("avatar", {}).get("gender") == "female"
	print("AVATAR_LIVE_SERVER ", valid, " ", result.get("avatar"))
	g._hub._on_net_me_result(result)
	g._hub._open_profile()
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := "C:/Users/nkucherenko/agent-coding/captures/preview/avatar-profile-female-540x960.png"
	print("AVATAR_CAPTURE ", image.save_png(output), " profile=", g._hub._profile_nick.get_parent().get_parent().get_global_rect())
	get_tree().quit(0 if valid else 1)

func _received(data: Dictionary) -> void:
	result = data
