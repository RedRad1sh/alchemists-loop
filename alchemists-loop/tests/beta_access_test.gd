extends Node

const NetBase = preload("res://autoload/net.gd")

class ProbeNet extends NetBase:
	var sent: Array = []
	func _try_send(url: String, headers: PackedStringArray, method: int, body: String) -> int:
		sent.append({"url": url, "headers": headers, "method": method, "body": body})
		return OK

class RejectingNet extends NetBase:
	func _try_send(_url: String, _headers: PackedStringArray, _method: int, _body: String) -> int:
		return ERR_CANT_CONNECT

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
	check_case("never activated beta needs no deletion credential", beta.prepare_deletion(UserData.get_or_create_device_id()))
	beta.prepare_activation("ABCD-EFGH")
	var secret: String = beta.attempt_secret
	var attempt_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(beta.storage_path))
	var identity: String = beta.identity_secret
	check_case("attempt persisted before send", secret.length() >= 64 and attempt_file.get("attempt_secret") == secret)
	beta.token = ""
	beta.device_id = ""
	beta.attempt_secret = ""
	beta.identity_secret = ""
	beta.pending_code = ""
	beta.load_credentials()
	check_case("activation retry survives restart", beta.attempt_secret == secret and beta.identity_secret == identity and beta.pending_code == "ABCDEFGH")
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
	beta.device_id = ""
	beta.attempt_secret = ""
	beta.identity_secret = ""
	beta.pending_code = ""
	beta.server_confirmed = false
	beta.load_credentials()
	check_case("credentials survive restart", beta.token == "test-token" and beta.device_id == UserData.get_or_create_device_id() and beta.identity_secret == identity)
	check_case("saved access waits for beta confirmation", not beta.can_send_gameplay() and beta.auth_headers(beta.server_url).is_empty())
	var health_probe := ProbeNet.new()
	health_probe.base_url = beta.server_url
	health_probe._inflight = {"kind": "ping"}
	health_probe._queue.append({"kind": "world", "path": "/world"})
	health_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{\"ok\":true,\"beta\":false}".to_utf8_buffer())
	check_case("non beta health blocks queued gameplay", health_probe.sent.is_empty() and not beta.can_send_gameplay())
	var confirmations: Array = []
	var on_confirmation := func(): confirmations.append(beta.can_send_gameplay())
	beta.access_changed.connect(on_confirmation)
	health_probe._inflight = {"kind": "ping"}
	health_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{\"ok\":true,\"beta\":true}".to_utf8_buffer())
	check_case("confirmed saved access resumes bootstrap", confirmations == [true])
	health_probe._inflight = {"kind": "ping"}
	health_probe._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check_case("failed health clears server confirmation", not beta.can_send_gameplay())
	beta.server_confirmed = true
	var rejecting_probe := RejectingNet.new()
	rejecting_probe.base_url = beta.server_url
	rejecting_probe._enqueue({"kind": "ping", "path": "/health"})
	check_case("unsent health clears server confirmation", not beta.can_send_gameplay())
	rejecting_probe.free()
	beta.access_changed.disconnect(on_confirmation)
	health_probe.free()
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
	delete_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), "{\"ok\":false}".to_utf8_buffer())
	check_case("rejected deletion preserves retry credential", beta.deletion_token(own_id) == "deletion-token")
	delete_probe.delete_account(own_id)
	delete_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"ok": true, "device_id": own_id}).to_utf8_buffer())
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
	game._shop._rebuild()
	check_case("beta shop hides unavailable ads", game._shop._list.get_child_count() == Monetization.get_products().size())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beta-capture="):
			game._shop._dim.show()
			game._shop._popup.show()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--beta-capture="))
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
	var duplicate_op: String = beta.begin_purchase("ether_pack_small")
	reply["operation_id"] = duplicate_op
	reply["token"] = receipt
	Monetization._beta_receipts.clear()
	Monetization._on_beta_purchase(reply)
	Monetization._on_beta_purchase_granted({"ok": true, "operation_id": duplicate_op})
	beta.purchases.clear()
	beta.load_credentials()
	check_case("restored processed receipt closes persisted operation", beta.pending_purchase("ether_pack_small") == "" and game._engine.ether + game._engine.ether_overflow == ether_before + 500)
	game._saves._save_game()
	var storage0: String = beta.storage_path
	beta.storage_path = storage0 + "/missing/credentials.json"
	var deletion_ready: Variant = beta.call("prepare_deletion", own_id)
	check_case("failed deletion preparation reports failure", deletion_ready == false)
	game._online._device_id = own_id
	game._shop._delete_armed = true
	game._shop._delete_data()
	check_case("failed deletion persistence prevents local wipe", FileAccess.file_exists(game.SAVE_PATH) and beta.token == "payment-flow-token" and game._online._device_id == own_id)
	beta.storage_path = storage0
	var identity0: String = beta.identity_secret
	var user0: Dictionary = UserData._data.duplicate(true)
	beta.access_revoked()
	beta.device_id = ""
	beta.identity_secret = ""
	beta.load_credentials()
	game._shop._delete_armed = true
	game._shop._delete_data()
	check_case("revoked access preserves ownership until authenticated deletion", beta.device_id == own_id and beta.identity_secret == identity0 and FileAccess.file_exists(game.SAVE_PATH) and game._online._device_id == own_id)
	UserData._data = user0
	UserData._save()
	beta.identity_secret = identity0
	beta.prepare_activation("RECOVER-ACCESS")
	beta.accept_activation({"ok": true, "beta": true, "device_id": own_id, "token": "recovered-deletion-token"})
	game._online._device_id = own_id
	game._online._net_enabled = true
	game._saves._save_frozen = false
	game._saves._save_game()
	var marker0: String = UserData.DELETE_PENDING_PATH
	UserData.DELETE_PENDING_PATH = storage0 + "/missing/delete-marker.json"
	Net.base_url = beta.server_url
	Net._queue.clear()
	Net._inflight = {"kind": "test_hold"}
	game._shop._delete_armed = true
	game._shop._delete_data()
	check_case("beta wipe persists deletion without a secondary marker", not FileAccess.file_exists(game.SAVE_PATH) and beta.deletion_token(own_id) == "recovered-deletion-token")
	if not Net._queue.is_empty():
		Net._inflight = Net._queue.pop_front()
		Net._on_completed(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), "{\"ok\":false}".to_utf8_buffer())
	Net._queue.clear()
	Net._inflight = {"kind": "test_hold"}
	UserData.DELETE_PENDING_PATH = marker0
	beta.deletions.clear()
	beta.load_credentials()
	var retry_probe := ProbeNet.new()
	retry_probe.base_url = beta.server_url
	game._online._retry_pending_account_delete(retry_probe)
	check_case("restart retries beta deletion after marker failure and unavailable server", retry_probe.sent.size() == 1 and retry_probe.sent[0]["method"] == HTTPClient.METHOD_DELETE and retry_probe.sent[0]["headers"].has("Authorization: Bearer recovered-deletion-token"))
	game._shop._delete_data()
	check_case("manual beta deletion retry uses the durable credential", Net._queue.size() == 1 and Net._queue[0].get("delete_token") == "recovered-deletion-token")
	retry_probe._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"ok": true, "device_id": own_id}).to_utf8_buffer())
	check_case("successful retry closes beta deletion state", beta.deletion_token(own_id) == "")
	retry_probe.free()
	Net._queue.clear()
	Net._inflight = {"kind": "test_hold"}
	Net.base_url = base0
	beta.clear_credentials()
	game._online._device_id = UserData.get_or_create_device_id()
	game._saves._save_frozen = false
	game._saves._save_game()
	game._shop._delete_armed = true
	game._shop._delete_data()
	check_case("unactivated beta wipes locally without server deletion", not FileAccess.file_exists(game.SAVE_PATH) and game._online._device_id == "" and UserData.get_account_delete_pending_ids().is_empty())
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beta-capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--beta-capture=").get_basename() + "-invite.png")
	screen.queue_free()
	print("BETA RESULT failures=", fails)
	get_tree().quit(0 if fails == 0 else 1)
