extends RefCounted
class_name SuiteSaveSync
# Task 6/7: самодостаточные определения рецептов (known_recipe_defs) + актуальная
# SAVE_VERSION (Task 5 дома поднял формат до 6) и миграция v3→текущей. membership known_recipes == known_recipe_defs.keys(); сейв хранит
# defs целиком, загрузка больше не режет знание пересечением с каталогом (фикс Bug B).

const ST_PATH := "user://alchemy_st_save_sync.json"
const ST_TEMP := "user://alchemy_st_save_sync.tmp"
const ST_BAK := "user://alchemy_st_save_sync.bak"

static func _wipe(g: Game) -> void:
	for path in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# Step 1 (Task 6): сейв обязан писать определения, а не только массив ключей.
static func _save_writes_self_contained_defs(g: Game) -> void:
	var key := g._pair_key("fire", "water")
	g._engine.known_recipes.clear()
	g._engine.known_recipe_defs.clear()
	g._engine.known_recipes[key] = true
	g._engine.known_recipe_defs[key] = {"a": "fire", "b": "water", "out": "steam"}
	g._saves._save_game()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(g.SAVE_PATH))
	var raw: Dictionary = parsed if parsed is Dictionary else {}
	var saved_defs: Variant = raw.get("known_recipe_defs", null)
	var ok := saved_defs is Dictionary \
		and (saved_defs as Dictionary).has(key) \
		and String((saved_defs as Dictionary)[key].get("out", "")) == "steam"
	Selftest.check("save_sync: save writes self-contained defs", ok)

# Шаг миграции старого сейва: до 4 — только массив ключей. Чтение обязано собрать
# определения из каталога (fire+water → steam) и поднять version до SAVE_VERSION.
static func _migration_v3_builds_defs(g: Game) -> void:
	var key := g._pair_key("fire", "water")
	var raw := {
		"version": 3,
		"inventory": {"fire": 1, "water": 1, "steam": 1},
		"known_recipes": [key],
	}
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	var data := g._saves._read_save(g.SAVE_PATH)
	var defs: Dictionary = data.get("known_recipe_defs", {})
	var ok := int(data.get("version", 0)) == Game.SAVE_VERSION and defs.has(key) \
		and String(defs[key].get("out", "")) == "steam"
	Selftest.check("save_sync: v3 migration rebuilds defs from catalog", ok)

static func _union_load_keeps_lost_recipe(g: Game) -> void:
	# Bug B: пара, определения которой нет в текущем каталоге, раньше терялась при
	# загрузке (пересечение с g.RECIPES). Union-загрузка обязана сохранить её как
	# «known but not currently brewable» (var-выход shadow нереален → не варится).
	var key := g._pair_key("ghostrock", "mist")
	var raw := {
		"version": 5,
		"inventory": {"ghostrock": 1, "mist": 1},
		"known_recipes": [key],
		"known_recipe_defs": {key: {"a": "ghostrock", "b": "mist", "out": "shadow"}},
	}
	g._saves._apply_recipe_knowledge(raw)
	Selftest.check("save_sync: lost recipe survives load as not-brewable", \
		g._engine.known_recipes.has(key) and g._engine.known_recipe_defs.has(key) \
		and not g._workshop.known_target_recipe("shadow"))

# Task 8: Sync.build_package(g) собирает единый конверт. part_b.recipes обязан нести
# pair_key из ключа known_recipe_defs (значения {a,b,out} его не содержат); part_c
# перечисляет не-базовые открытые элементы из инвентаря.
static func _build_package_envelope(g: Game) -> void:
	var key := g._pair_key("fire", "water")
	g._engine.known_recipes.clear()
	g._engine.known_recipe_defs.clear()
	g._engine.inventory.clear()
	g._engine.known_recipes[key] = true
	g._engine.known_recipe_defs[key] = {"a": "fire", "b": "water", "out": "steam"}
	g._engine.inventory["fire"] = 5
	g._engine.inventory["steam"] = 3
	var pkg := Sync.build_package(g)
	var ver_ok := int(pkg.get("schema_version", -1)) == Balance.SYNC_SCHEMA_VERSION
	var part_b: Dictionary = pkg.get("part_b", {})
	var recipes: Array = part_b.get("recipes", [])
	var has_pair_key := false
	for r in recipes:
		if r is Dictionary and String((r as Dictionary).get("pair_key", "")) == key:
			has_pair_key = true
	var part_c: Dictionary = pkg.get("part_c", {})
	var slugs: Array = part_c.get("inventory_slugs", [])
	var has_steam := slugs.has("steam")
	Selftest.check("save_sync: build_package envelope + part_b pair_key + part_c slugs", \
		ver_ok and has_pair_key and has_steam)

# Task 10: оффлайн (selftest: _net_enabled=false) request_sync обязан no-op'ить —
# fail-open: знание не меняется, sync-флаг падает в false, исключений нет.
static func _request_sync_offline_fail_open(g: Game) -> void:
	var before := g._engine.known_recipes.size()
	g._sync.last_sync_ok = true
	g._sync.request_sync(g)
	Selftest.check("save_sync: offline request_sync fail-open, knowledge intact", \
		not g._sync.last_sync_ok and g._engine.known_recipes.size() == before)

# Task 11: envelope fail-closed — сейв с чужим device_id не читаем вовсе ({}),
# сейв текущего устройства читаем. Пустой device_id (старый сейв/оффлайн-установка)
# совместим: чужого устройства не заявлено → не отвергаем.
static func _envelope_fail_closed_device(g: Game) -> void:
	var saved_device := g._online._device_id
	g._online._device_id = "dev-mine"
	var foreign := {"version": 5, "inventory": {"fire": 1}, "ether": 50,
		"known_recipes": [], "device_id": "dev-other"}
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(foreign))
	f.close()
	var rejected: Dictionary = g._saves._read_save(g.SAVE_PATH)
	var own := {"version": 5, "inventory": {"fire": 1}, "ether": 50,
		"known_recipes": [], "device_id": "dev-mine"}
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(own))
	f.close()
	var accepted: Dictionary = g._saves._read_save(g.SAVE_PATH)
	g._online._device_id = saved_device
	Selftest.check("save_sync: envelope fail-closed on foreign device_id", \
		rejected.is_empty() and not accepted.is_empty())

# Порча/потеря UserData не должна делать собственный сейв «чужим»: пустой
# device_id в UserData восстанавливается из сейва. Свой id при этом не
# подменяется — перенесённый чужой сейв по-прежнему отвергается.
static func _device_id_recovered_from_save(g: Game) -> void:
	var saved_device := g._online._device_id
	var saved_ud: Dictionary = UserData._data.duplicate(true)
	var own := {"version": 5, "inventory": {"fire": 1}, "ether": 50,
		"known_recipes": [], "device_id": "dev-from-save"}
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(own))
	f.close()
	UserData._data.erase("device_id")
	g._online._device_id = g._online._load_device_id()
	var recovered: bool = g._online._device_id == "dev-from-save" \
		and UserData.get_or_create_device_id() == "dev-from-save" \
		and not g._saves._read_save(g.SAVE_PATH).is_empty()
	UserData._data["device_id"] = "dev-mine"
	g._online._device_id = g._online._load_device_id()
	var kept: bool = g._online._device_id == "dev-mine" \
		and g._saves._read_save(g.SAVE_PATH).is_empty()
	UserData._data = saved_ud
	UserData._save()
	g._online._device_id = saved_device
	Selftest.check("save_sync: lost UserData device_id is recovered from own save", recovered)
	Selftest.check("save_sync: own UserData device_id is not replaced by a save's", kept)

static func _rejected_copies(g: Game) -> Array:
	var prefix := g.SAVE_PATH.get_file().get_basename() + ".rejected."
	var out: Array = []
	for name in DirAccess.get_files_at("user://"):
		if String(name).begins_with(prefix):
			out.append("user://" + String(name))
	return out

# Отвергнутый сейв (чужой device_id, битый JSON) нельзя молча затирать автосейвом
# новой игры: до перезаписи он откладывается копией рядом.
static func _rejected_save_is_quarantined(g: Game) -> void:
	for path in _rejected_copies(g):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var saved_device := g._online._device_id
	g._online._device_id = "dev-mine"
	var foreign_text := JSON.stringify({"version": 5, "inventory": {"fire": 1}, "ether": 50,
		"known_recipes": [], "device_id": "dev-other"})
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(foreign_text)
	f.close()
	g._saves._load_game()
	var copies := _rejected_copies(g)
	var kept: bool = copies.size() == 1 \
		and FileAccess.get_file_as_string(String(copies[0])) == foreign_text
	for path in copies:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_wipe(g)
	g._saves._load_game()
	var none_for_missing: bool = _rejected_copies(g).is_empty()
	g._online._device_id = saved_device
	Selftest.check("save_sync: rejected save is quarantined before it can be overwritten", kept)
	Selftest.check("save_sync: missing save leaves no quarantine copy", none_for_missing)

# Task 11: per-Part fail-open — битый Part B (known_recipes не массив) обязан
# деградировать знание, но Part C (эфир/инвентарь) применится, а не отменит сейв.
static func _per_part_fail_open_knowledge(g: Game) -> void:
	var raw := {"version": 5, "inventory": {"fire": 1, "water": 1}, "ether": 100,
		"known_recipes": 5}
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	var data := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("save_sync: corrupt Part B degrades, Part C (ether/inventory) survives", \
		not data.is_empty() and int(data.get("ether", -1)) == 100 \
		and (data.get("inventory") is Dictionary) \
		and (data.get("known_recipes") is Array))

# Task 12: контракт — штатный sync-ответ (client_rev>0) НЕ трогает локальный
# (накрученный) эфир, даже если сервер вернул потолок меньше банка; знание только
# пополняется грантами/восстановлением, локальное не удаляется и пустой ключ не
# просачивается. Part C = client-wins, Part B = union.
static func _reconcile_contract(g: Game) -> void:
	var saved_rev := g._engine.client_rev
	var saved_overflow := g._engine.ether_overflow
	g._engine.known_recipes.clear()
	g._engine.known_recipe_defs.clear()
	var local_key := g._pair_key("copper", "tin")
	g._engine.known_recipes[local_key] = true
	g._engine.known_recipe_defs[local_key] = {"a": "copper", "b": "tin", "out": "bronze"}
	g._engine.client_rev = 5  # штатный клиент (не миграционный первый заход)
	g._engine.ether_overflow = 999999  # накрученный оффлайн-банк
	var grant_key := g._pair_key("leaf", "stone")
	var rec_key := g._pair_key("sand", "fire")
	var result := {
		"ok": true,
		"accrual_ceiling": 100,  # серверный потолок меньше накрученного банка
		"anchor_server_ts": 5000.0,
		"grants": [{"kind": "recipe", "ref": grant_key, "a": "leaf", "b": "stone", "out": "paste"}],
		"recovered": [{"pair_key": rec_key, "a": "sand", "b": "fire", "out": "glass"},
			{"pair_key": "", "a": "", "b": "", "out": ""}],  # пустой ключ не просочится
	}
	g._sync.apply_reconcile(g, result)
	var ether_untouched := g._engine.ether_overflow == 999999
	var local_kept := g._engine.known_recipes.has(local_key) \
		and g._engine.known_recipe_defs.has(local_key)
	var grew := g._engine.known_recipes.has(grant_key) and g._engine.known_recipes.has(rec_key)
	var defs_grew := g._engine.known_recipe_defs.has(grant_key) \
		and g._engine.known_recipe_defs.has(rec_key)
	var no_empty := not g._engine.known_recipes.has("")
	g._engine.client_rev = saved_rev
	g._engine.ether_overflow = saved_overflow
	Selftest.check("save_sync: contract reconcile keeps inflated ether, knowledge only grows", \
		ether_untouched and local_kept and grew and defs_grew and no_empty)

static func _read_save_off_catalog_migration(g: Game) -> void:
	# Review Focus #3 / review #6: РЕАЛЬный v3-сейв (только массив ключей) с парой,
	# определения которой НЕТ в каталоге, обязан пройти через _read_save и стать
	# known-but-not-brewable (def есть, out="", в знании остаётся, не варится), а не
	# исчезнуть (Bug B) и не стать варимым. Мутация-красные: «continue» для off-catalog
	# ключей в _read_save → ghost пропадёт из defs → красным; смена out="" на выдуман
	#     -> not-brewable-ассерт красный.
	var ghost := g._pair_key("ghostrock", "mist")
	var raw := {
		"version": 3,
		"inventory": {"ghostrock": 1, "mist": 1},
		"known_recipes": [ghost],
	}
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	var data := g._saves._read_save(g.SAVE_PATH)
	g._saves._apply_recipe_knowledge(data)
	var kept := g._engine.known_recipes.has(ghost) and g._engine.known_recipe_defs.has(ghost)
	var out_empty := String((g._engine.known_recipe_defs.get(ghost, {}) as Dictionary).get("out", "")) == ""
	var not_brewable := not g._workshop.known_target_recipe("shadow")
	Selftest.check("save_sync: _read_save keeps off-catalog v3 key as known-but-not-brewable", \
		kept and out_empty and not_brewable)

static func _personal_target_save_load(g: Game) -> void:
	var raw_target := {
		"id": "pt-save-target", "kind": "llm", "slug": "pt-save-hidden", "name": "Сохранённая цель",
		"hint": "Найди новую связь.", "status": "active", "cycle_week": "2026-W48",
		"attempts": 2, "successful_steps": 1, "spent_ether": 12, "next_eligible_week": "",
		"source_pair": ["fire", "water"], "seed": 77, "prompt": "SECRET_PROMPT",
		"evaluator_explanation": "SECRET_EXPLANATION"}
	g._online._on_experiment_target_sync_result({"ok": true, "target": raw_target})
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._saves._save_game()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(g.SAVE_PATH))
	var raw: Dictionary = parsed if parsed is Dictionary else {}
	var saved_value: Variant = raw.get("personal_experiment_target", null)
	var saved_target: Dictionary = saved_value if saved_value is Dictionary else {}
	var allowed_keys := ["id", "kind", "slug", "name", "hint", "status", "cycle_week", "attempts",
		"successful_steps", "spent_ether", "next_eligible_week", "completed", "generation"]
	var only_allowed := saved_value is Dictionary
	for key in saved_target.keys():
		only_allowed = only_allowed and allowed_keys.has(String(key))
	var saved_generation := int(raw.get("personal_experiment_generation", -1))
	Selftest.check("save_sync: personal target save shape is allowlisted",
		only_allowed and String(saved_target.get("id", "")) == "pt-save-target"
		and not saved_target.has("source_pair") and not saved_target.has("seed")
		and not saved_target.has("prompt") and not saved_target.has("evaluator_explanation")
		and saved_generation == int(saved_target.get("generation", -2)))
	g._online._target_state = {}
	g._online._pending_requests["stale"] = {"a": "fire", "b": "water", "at": Time.get_ticks_msec()}
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._saves._load_game()
	Selftest.check("save_sync: target state survives save shape", g._online._target_state.get("status", "") == "active")
	Selftest.check("save_sync: target load increments generation and clears pending",
		int(g._online._target_state.get("generation", -1)) == saved_generation + 1
		and g._online._pending_requests.is_empty() and g._engine._experiment_pending_pair.is_empty())

	var malformed: Dictionary = raw.duplicate(true)
	malformed["personal_experiment_target"] = "broken"
	malformed["personal_experiment_generation"] = saved_generation
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(malformed))
	f.close()
	g._online._target_state = {"id": "stale-target", "status": "active", "generation": 99}
	g._online._pending_requests["stale"] = {"a": "fire", "b": "water", "at": Time.get_ticks_msec()}
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._saves._load_game()
	Selftest.check("save_sync: malformed personal target is ignored and pending is cleared",
		g._online._target_state.is_empty() and g._online._pending_requests.is_empty()
		and g._engine._experiment_pending_pair.is_empty())
	_wipe(g)

static func _personal_target_attempt_replay(g: Game) -> void:
	var saved_target: Dictionary = g._online._target_state.duplicate(true)
	var saved_receipt: Dictionary = g._online._target_attempt_receipt.duplicate(true)
	var saved_pending: Dictionary = g._online._pending_requests.duplicate(true)
	var saved_pair: Array = g._engine._experiment_pending_pair.duplicate()
	var saved_reserve: int = g._engine._experiment_reserved_ether
	var saved_ether: int = g._engine.ether
	var saved_overflow: int = g._engine.ether_overflow
	var saved_attempts: int = g._engine.attempts
	var saved_successes: int = g._engine.successes
	var saved_day: String = g._engine._experiment_day
	var saved_count: int = g._engine._experiment_count
	var saved_last_at: float = g._engine._experiment_last_at
	var saved_net_enabled: bool = g._online._net_enabled
	var saved_net_available: bool = Net._available
	var saved_net_queue: Array[Dictionary] = Net._queue.duplicate()
	var saved_net_inflight: Dictionary = Net._inflight.duplicate(true)
	var saved_layers: Dictionary = g._online._server_layers.duplicate(true)
	var saved_authors: Dictionary = g._online._server_authors.duplicate(true)
	var cost := int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST))
	var raw_target := {
		"id": "pt-replay-target", "kind": "world", "slug": "steam", "name": "Пар",
		"hint": "Соедини огонь и воду.", "status": "active", "cycle_week": "2026-W48",
		"attempts": 0, "successful_steps": 0, "spent_ether": 0, "next_eligible_week": ""}
	g._online._target_state = {}
	g._online._target_attempt_receipt.clear()
	g._online._pending_requests.clear()
	g._engine._experiment_pending_pair.clear()
	g._engine._experiment_reserved_ether = 0
	g._engine.ether = 100
	g._engine.ether_overflow = 0
	g._engine._experiment_day = g._engine._experiment_day_key()
	g._engine._experiment_count = 0
	g._engine._experiment_last_at = 0.0
	g._engine.inventory["steam"] = 1
	g._online._on_experiment_target_sync_result({"ok": true, "target": raw_target})
	g._online._net_enabled = true
	Net._available = true
	Net._inflight = {"kind": "selftest-hold"}
	Net._queue.clear()
	var started: bool = g._online._start_experiment("fire", "water")
	var request_id := ""
	if not Net._queue.is_empty():
		var queued_body: Dictionary = (Net._queue.back() as Dictionary).get("body", {})
		request_id = String(queued_body.get("request_id", ""))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(g.SAVE_PATH))
	var raw_save: Dictionary = parsed if parsed is Dictionary else {}
	var receipt: Dictionary = raw_save.get("personal_experiment_attempt", {})
	var receipt_keys := ["a", "b", "target_id", "request_id", "generation", "cycle_week", "at", "reserved_cost"]
	var receipt_shape := receipt is Dictionary and (receipt as Dictionary).size() == receipt_keys.size()
	for key in receipt_keys:
		receipt_shape = receipt_shape and receipt.has(key)
	Selftest.check("save_sync: target attempt receipt is durable before response",
		started and request_id != "" and receipt_shape
		and String(receipt.get("request_id", "")) == request_id
		and String(receipt.get("target_id", "")) == "pt-replay-target"
		and String(receipt.get("cycle_week", "")) == "2026-W48"
		and int(receipt.get("reserved_cost", -1)) == cost)
	var saved_generation := int(raw_save.get("personal_experiment_generation", -1))
	g._online._pending_requests.clear()
	g._engine._experiment_pending_pair.clear()
	g._engine._experiment_reserved_ether = 0
	g._saves._load_game()
	var restored_generation := int(g._online._target_state.get("generation", -1))
	var restored_pending: Dictionary = g._online._pending_requests.get(g._pair_key("fire", "water"), {})
	Selftest.check("save_sync: target attempt load restores correlation and reserve",
		restored_generation == saved_generation + 1
		and g._engine._experiment_pending_pair == ["fire", "water"]
		and g._engine._experiment_reserved_ether == cost
		and String(restored_pending.get("request_id", "")) == request_id
		and int(restored_pending.get("generation", -1)) == restored_generation)
	var replayed := false
	if g._online.has_method("_resume_pending_target_attempt"):
		replayed = bool(g._online.call("_resume_pending_target_attempt"))
	var replay_request_id := ""
	if not Net._queue.is_empty():
		var replay_body: Dictionary = (Net._queue.back() as Dictionary).get("body", {})
		replay_request_id = String(replay_body.get("request_id", ""))
	Selftest.check("save_sync: target attempt replay keeps request identity",
		replayed and replay_request_id == request_id)
	var completed_target: Dictionary = raw_target.duplicate(true)
	completed_target["status"] = "completed"
	completed_target["completed"] = true
	completed_target["attempts"] = 1
	completed_target["successful_steps"] = 1
	completed_target["spent_ether"] = cost
	var response := {
		"ok": true, "status": "created", "request_id": request_id,
		"target_id": "pt-replay-target", "pair_key": g._pair_key("fire", "water"),
		"target": completed_target, "ether_charged": cost, "acquired": true,
		"discovery": {"slug": "steam", "name": "Пар", "a": "fire", "b": "water"}}
	var inventory_before := int(g._engine.inventory.get("steam", 0))
	var ether_before := g._engine.ether + g._engine.ether_overflow
	g._online._on_experiment_target_result(request_id, g._pair_key("fire", "water"), response)
	Selftest.check("save_sync: replayed accepted target result grants and charges once",
		int(g._engine.inventory.get("steam", 0)) == inventory_before + 1
		and g._engine.ether + g._engine.ether_overflow == ether_before - cost
		and g._online._pending_requests.is_empty()
		and g._engine._experiment_pending_pair.is_empty()
		and g._engine._experiment_reserved_ether == 0
		and String(g._online._target_state.get("status", "")) == "completed")
	g._online._on_experiment_target_result(request_id, g._pair_key("fire", "water"), response)
	Selftest.check("save_sync: duplicate target replay cannot grant or charge twice",
		int(g._engine.inventory.get("steam", 0)) == inventory_before + 1
		and g._engine.ether + g._engine.ether_overflow == ether_before - cost)
	g._saves._save_game()
	parsed = JSON.parse_string(FileAccess.get_file_as_string(g.SAVE_PATH))
	raw_save = parsed if parsed is Dictionary else {}
	Selftest.check("save_sync: settled target attempt receipt is not persisted",
		not raw_save.has("personal_experiment_attempt") or (raw_save["personal_experiment_attempt"] as Dictionary).is_empty())
	g._online._target_state = saved_target
	g._online._target_attempt_receipt = saved_receipt
	g._online._pending_requests = saved_pending
	g._engine._experiment_pending_pair = saved_pair
	g._engine._experiment_reserved_ether = saved_reserve
	g._engine.ether = saved_ether
	g._engine.ether_overflow = saved_overflow
	g._engine.attempts = saved_attempts
	g._engine.successes = saved_successes
	g._engine._experiment_day = saved_day
	g._engine._experiment_count = saved_count
	g._engine._experiment_last_at = saved_last_at
	g._online._net_enabled = saved_net_enabled
	Net._available = saved_net_available
	Net._queue = saved_net_queue
	Net._inflight = saved_net_inflight
	g._online._server_layers = saved_layers
	g._online._server_authors = saved_authors
	_wipe(g)

static func run(g: Game) -> void:
	var saved_recipes: Array = g.RECIPES.duplicate()
	var saved_known: Dictionary = g._engine.known_recipes.duplicate()
	var saved_defs: Dictionary = g._engine.known_recipe_defs.duplicate(true)
	var saved_inv: Dictionary = g._engine.inventory.duplicate()
	var saved_book_sig: int = g._engine._book_sig
	var saved_client_rev: int = g._engine.client_rev
	var saved_anchor_ts: float = g._engine.anchor_accrual_ts
	var saved_target: Dictionary = g._online._target_state.duplicate(true)
	var saved_receipt: Dictionary = g._online._target_attempt_receipt.duplicate(true)
	var saved_pending: Dictionary = g._online._pending_requests.duplicate(true)
	var saved_exp_pair: Array = g._engine._experiment_pending_pair.duplicate()
	g.SAVE_PATH = ST_PATH
	g.TEMP_PATH = ST_TEMP
	g.BACKUP_PATH = ST_BAK
	_wipe(g)
	_save_writes_self_contained_defs(g)
	_wipe(g)
	_migration_v3_builds_defs(g)
	_wipe(g)
	_union_load_keeps_lost_recipe(g)
	_wipe(g)
	_build_package_envelope(g)
	_request_sync_offline_fail_open(g)
	_envelope_fail_closed_device(g)
	_device_id_recovered_from_save(g)
	_wipe(g)
	_rejected_save_is_quarantined(g)
	_per_part_fail_open_knowledge(g)
	_reconcile_contract(g)
	_wipe(g)
	_read_save_off_catalog_migration(g)
	_wipe(g)
	_personal_target_save_load(g)
	_personal_target_attempt_replay(g)
	g.SAVE_PATH = "user://alchemy_save.json"
	g.TEMP_PATH = "user://alchemy_save.tmp"
	g.BACKUP_PATH = "user://alchemy_save.bak"
	g.RECIPES = saved_recipes
	g._engine.known_recipes = saved_known
	g._engine.known_recipe_defs = saved_defs
	g._engine.inventory = saved_inv
	g._engine._book_sig = saved_book_sig
	g._engine.client_rev = saved_client_rev
	g._engine.anchor_accrual_ts = saved_anchor_ts
	g._online._target_state = saved_target
	g._online._target_attempt_receipt = saved_receipt
	g._online._pending_requests = saved_pending
	g._engine._experiment_pending_pair.clear()
	for item in saved_exp_pair:
		g._engine._experiment_pending_pair.append(String(item))
