extends RefCounted
class_name SuiteSaveSync
# Task 6/7: самодостаточные определения рецептов (known_recipe_defs) + SAVE_VERSION=4
# и миграция v3→v4. membership known_recipes == known_recipe_defs.keys(); сейв хранит
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

# Шаг миграции v3→v4: старый сейв = только массив ключей. Чтение обязано собрать
# определения из каталога (fire+water → steam) и поднять version до 4.
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
	var ok := int(data.get("version", 0)) == 4 and defs.has(key) \
		and String(defs[key].get("out", "")) == "steam"
	Selftest.check("save_sync: v3→v4 migration rebuilds defs from catalog", ok)

static func _union_load_keeps_lost_recipe(g: Game) -> void:
	# Bug B: пара, определения которой нет в текущем каталоге, раньше терялась при
	# загрузке (пересечение с g.RECIPES). Union-загрузка обязана сохранить её как
	# «known but not currently brewable» (var-выход shadow нереален → не варится).
	var key := g._pair_key("ghostrock", "mist")
	var raw := {
		"version": 4,
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
	var foreign := {"version": 4, "inventory": {"fire": 1}, "ether": 50,
		"known_recipes": [], "device_id": "dev-other"}
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(foreign))
	f.close()
	var rejected: Dictionary = g._saves._read_save(g.SAVE_PATH)
	var own := {"version": 4, "inventory": {"fire": 1}, "ether": 50,
		"known_recipes": [], "device_id": "dev-mine"}
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(own))
	f.close()
	var accepted: Dictionary = g._saves._read_save(g.SAVE_PATH)
	g._online._device_id = saved_device
	Selftest.check("save_sync: envelope fail-closed on foreign device_id", \
		rejected.is_empty() and not accepted.is_empty())

# Task 11: per-Part fail-open — битый Part B (known_recipes не массив) обязан
# деградировать знание, но Part C (эфир/инвентарь) применится, а не отменит сейв.
static func _per_part_fail_open_knowledge(g: Game) -> void:
	var raw := {"version": 4, "inventory": {"fire": 1, "water": 1}, "ether": 100,
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

static func run(g: Game) -> void:
	var saved_recipes: Array = g.RECIPES.duplicate()
	var saved_known: Dictionary = g._engine.known_recipes.duplicate()
	var saved_defs: Dictionary = g._engine.known_recipe_defs.duplicate(true)
	var saved_inv: Dictionary = g._engine.inventory.duplicate()
	var saved_book_sig: int = g._engine._book_sig
	var saved_client_rev: int = g._engine.client_rev
	var saved_anchor_ts: float = g._engine.anchor_accrual_ts
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
	_per_part_fail_open_knowledge(g)
	_reconcile_contract(g)
	_wipe(g)
	_read_save_off_catalog_migration(g)
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
