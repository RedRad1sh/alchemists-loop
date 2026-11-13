extends Node

const NetBase = preload("res://autoload/net.gd")

class ProbeNet extends NetBase:
	var sent: Array = []
	func _try_send(url: String, headers: PackedStringArray, method: int, body: String) -> int:
		sent.append({"url": url, "headers": headers, "method": method, "body": body})
		return OK

var fails := 0

func check_case(label: String, ok: bool) -> void:
	print("BETA ", "PASS " if ok else "FAIL ", label)
	if not ok:
		fails += 1

func _ready() -> void:
	var beta := get_node_or_null("/root/BetaAccess")
	check_case("beta access singleton exists", beta != null)
	if beta == null:
		get_tree().quit(1)
		return
	beta.enabled = true
	beta.storage_path = "user://alchemy_st_beta_access.json"
	beta.server_url = "https://beta.invalid/api"
	beta.clear_credentials()
	check_case("gameplay denied before activation", not beta.can_send_gameplay())
	check_case("no bearer before activation", beta.auth_headers("https://beta.invalid/api").is_empty())
	beta.prepare_activation("ABCD-EFGH")
	var secret: String = beta.attempt_secret
	check_case("attempt persisted before send", secret.length() >= 64 and FileAccess.file_exists(beta.storage_path))
	beta.prepare_activation("ABCD-EFGH")
	check_case("retry reuses attempt secret", beta.attempt_secret == secret)
	beta.accept_activation({"ok": true, "beta": true, "device_id": "foreign", "token": "test-token"})
	check_case("foreign activation rejected", not beta.can_send_gameplay())
	beta.accept_activation({"ok": true, "beta": true, "device_id": UserData.get_or_create_device_id(), "token": "test-token"})
	check_case("matching activation unlocks gameplay", beta.can_send_gameplay())
	check_case("bearer attached to matching origin", beta.auth_headers("https://beta.invalid/api") == PackedStringArray(["Authorization: Bearer test-token"]))
	check_case("bearer not sent to different origin", beta.auth_headers("https://other.invalid/api").is_empty())
	check_case("credentials excluded from UserData export", not JSON.stringify(UserData.export_data()).contains("test-token"))
	beta.token = ""
	beta.load_credentials()
	check_case("access survives restart", beta.can_send_gameplay() and beta.identity_secret != "")
	beta.access_revoked()
	check_case("revocation denies gameplay", not beta.can_send_gameplay())
	beta.clear_credentials()
	check_case("wipe removes credentials", not FileAccess.file_exists(beta.storage_path) and beta.identity_secret == "")
	beta.prepare_activation("RATE-LIMIT")
	var rate_probe := ProbeNet.new()
	rate_probe._inflight = {"kind": "beta_activate", "body": {"attempt_secret": beta.attempt_secret}}
	var limited: Array = []
	rate_probe.beta_activate_result.connect(func(result: Dictionary):
		limited.append(result)
		beta.accept_activation(result))
	var rate_start := Time.get_unix_time_from_system()
	rate_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["retry-after: 600"]), "{\"ok\":false,\"error\":\"rate_limited\"}".to_utf8_buffer())
	check_case("activation respects server retry interval", limited.size() == 1 and limited[0].get("retry_after", 0) == 600 and beta.retry_after >= rate_start + 600.0)
	rate_probe.free()
	beta.retry_after = 0.0
	beta.prepare_activation("ABCD-EFGH")
	beta.accept_activation({"ok": true, "beta": true, "device_id": UserData.get_or_create_device_id(), "token": "test-payment-token"})
	Monetization._boot()
	check_case("beta never initializes payment SDK", Monetization.store_id == "beta_test" and Monetization._adapter == null and Monetization._ads == null)
	var base0: String = Net.base_url
	Net.base_url = beta.server_url
	Net._inflight = {"kind": "test_hold"}
	var q0: int = Net._queue.size()
	var started: bool = Monetization.purchase("ether_pack_small")
	check_case("beta purchase goes to dedicated endpoint", started and Net._queue.size() == q0 + 1 and Net._queue.back().get("path") == "/beta/purchase")
	var op: String = beta.pending_purchase("ether_pack_small")
	check_case("payment operation persisted before request", op != "" and FileAccess.get_file_as_string(beta.storage_path).contains(op))
	Monetization.restore()
	check_case("payment retry keeps operation id", beta.pending_purchase("ether_pack_small") == op)
	Net._queue.clear()
	Net._inflight = {}
	Net.base_url = base0
	var probe := ProbeNet.new()
	probe.base_url = beta.server_url
	probe.world(0)
	check_case("outbound gameplay carries bearer", probe.sent.size() == 1 and probe.sent[0]["headers"].has("Authorization: Bearer test-payment-token"))
	probe.hall()
	probe._on_completed(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), "{\"ok\":false}".to_utf8_buffer())
	check_case("401 stops queued gameplay", probe.sent.size() == 1 and probe._queue.is_empty() and not beta.can_send_gameplay())
	probe.free()
	beta.prepare_activation("ABCD-EFGH")
	beta.accept_activation({"ok": true, "beta": true, "device_id": UserData.get_or_create_device_id(), "token": "deletion-token"})
	var own_id: String = UserData.get_or_create_device_id()
	beta.prepare_deletion(own_id)
	beta.clear_credentials()
	check_case("wipe keeps only scoped deletion credentials", beta.token == "" and beta.deletion_token(own_id) == "deletion-token" and beta.pending_code == "")
	var delete_probe := ProbeNet.new()
	delete_probe.base_url = beta.server_url
	delete_probe.delete_account(own_id)
	check_case("deletion retry uses old token", delete_probe.sent.size() == 1 and delete_probe.sent[0]["headers"].has("Authorization: Bearer deletion-token"))
	delete_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), "{\"ok\":false,\"error\":\"unavailable\"}".to_utf8_buffer())
	check_case("database outage preserves deletion credential", beta.deletion_token(own_id) == "deletion-token")
	delete_probe.delete_account(own_id)
	delete_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{\"ok\":true}".to_utf8_buffer())
	check_case("successful deletion removes old credential", beta.deletion_token(own_id) == "")
	delete_probe.free()
	beta.clear_credentials()
	beta.prepare_activation("ABCD-EFGH")
	beta.accept_activation({"ok": true, "beta": true, "device_id": own_id, "token": "payment-flow-token"})
	Net._inflight = {"kind": "test_hold"}
	var game: Game = load("res://main.tscn").instantiate()
	game.SAVE_PATH = "user://alchemy_st_beta_game.json"
	game.TEMP_PATH = "user://alchemy_st_beta_game.tmp"
	game.BACKUP_PATH = "user://alchemy_st_beta_game.bak"
	add_child(game)
	game._saves._save_frozen = true
	var flow_op: String = beta.begin_purchase("ether_pack_small")
	var receipt := "beta_test:flow-token"
	var reply := {"ok": true, "beta": true, "provider": "beta_test", "token": receipt,
		"product_id": "ether_pack_small", "operation_id": flow_op, "already_granted": false}
	var ether_before: int = game._engine.ether + game._engine.ether_overflow
	var queue_before: int = Net._queue.size()
	Monetization._on_beta_purchase(reply)
	check_case("unsaved test payment does not acknowledge", Net._queue.size() == queue_before and game._engine.ether + game._engine.ether_overflow == ether_before + 500)
	game._saves._save_frozen = false
	Monetization._on_beta_purchase(reply)
	check_case("retry saves without granting twice", Net._queue.back().get("path") == "/beta/purchase/granted" and game._engine.ether + game._engine.ether_overflow == ether_before + 500)
	Monetization._on_beta_purchase_granted({"ok": true, "operation_id": flow_op})
	check_case("acknowledged test payment closes journal", beta.pending_purchase("ether_pack_small") == "" and UserData.has_processed_purchase("beta_test", receipt, "ether_pack_small"))
	Monetization._on_beta_purchase(reply)
	check_case("duplicate closed reply grants nothing", game._engine.ether + game._engine.ether_overflow == ether_before + 500)
	var restored_op: String = beta.begin_purchase("ether_pack_small")
	reply["operation_id"] = restored_op
	reply["token"] = "beta_test:restored-token"
	reply["already_granted"] = true
	Monetization._on_beta_purchase(reply)
	check_case("server granted echo adds no ether", game._engine.ether + game._engine.ether_overflow == ether_before + 500)
	Monetization._on_beta_purchase_granted({"ok": true, "operation_id": restored_op})
	game._saves._save_frozen = true
	game.queue_free()
	await get_tree().process_frame
	Monetization._game = null
	Net._queue.clear()
	Net._inflight = {}
	for path in ["user://alchemy_st_beta_game.json", "user://alchemy_st_beta_game.tmp", "user://alchemy_st_beta_game.bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	beta.clear_credentials()
	var screen_script = load("res://game/ui/beta_screen.gd")
	var screen := CanvasLayer.new()
	screen.set_script(screen_script)
	add_child(screen)
	await get_tree().process_frame
	check_case("invite screen visible before access", screen._screen.visible and screen._code.placeholder_text == "Инвайт-код")
	screen._submit.pressed.emit()
	check_case("empty code shown as validation status", not beta.activating and screen._status.text.contains("Введи"))
	screen.queue_free()
	print("BETA RESULT failures=", fails)
	get_tree().quit(0 if fails == 0 else 1)
