extends Node
class_name Sync
# Единый sync-пакет сейва: чистый builder envelope + Part A/B/C (spec 2026-10-16).
# Part A (ранг/resonance) не строим — сервер authoritative сам перетирает своим
# ответом. Part B = знание устройства (рецепты-гранты + известные элементы).
# Part C = непрозрачное локальное зеркало (инвентарь + заявленная аккумуляция).

const NetBase := preload("res://autoload/net.gd")

var g: Game  # хост-игра для обработчика сигнала Net (ставит main.gd в _ready)
var last_sync_ok: bool = true  # false после оффлайн/сбоя — fail-open маркер
var _sync_dirty: bool = false  # локальное знание изменилось → отложить flush
var _flush_clock: float = 0.0

# Источник device_id / _net_enabled.
static func build_package(g: Game) -> Dictionary:
	var base := {}
	for b in Modes.BASE_IDS:
		base[String(b)] = true

	var recipes: Array = []
	var defs: Dictionary = g._engine.known_recipe_defs
	for key in defs:
		var d: Variant = defs[key]
		if not (d is Dictionary):
			continue
		recipes.append({
			"pair_key": String(key),
			"a": String((d as Dictionary).get("a", "")),
			"b": String((d as Dictionary).get("b", "")),
			"out": String((d as Dictionary).get("out", "")),
		})

	var elements: Array = []
	var inventory_slugs: Array = []
	for slug in g._engine.inventory:
		if int(g._engine.inventory[slug]) > 0 and not base.has(String(slug)):
			elements.append(String(slug))
			inventory_slugs.append(String(slug))

	return {
		"device_id": g._online._device_id,
		"schema_version": Balance.SYNC_SCHEMA_VERSION,
		"client_rev": g._engine.client_rev,
		"anchor_accrual_ts": g._engine.anchor_accrual_ts,
		"part_b": {"recipes": recipes, "elements": elements},
		"part_c": {
			"inventory_slugs": inventory_slugs,
			"accrual_declared": float(g._engine.ether_overflow),
			"accrual_rate_declared": 0.0,
		},
	}

# Reconcile ответа /sync/package: Part A server-wins, Part B union, Part C clamp.
func apply_reconcile(g: Game, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return  # offline/ошибка → ничего не применяем (fail-open живёт в триггере, Task 10)
	# Part A — server-wins ровно для того, что реально в ответе синка: серверные часы
	# как якорь offline-аккумуляции (wall-clock банк, clamp Part C / Task 10).
	# Ранг/resonance остаются за /me и /rating — sync-ответ их не несёт, не перетираем.
	if result.has("anchor_server_ts"):
		g._engine.anchor_accrual_ts = float(result["anchor_server_ts"])
	# Part B — union знания устройства: пополняем, локальное никогда не удаляем.
	var grants_v: Variant = result.get("grants", [])
	if grants_v is Array:
		for gr in (grants_v as Array):
			if not (gr is Dictionary):
				continue
			var gd: Dictionary = gr
			# element-грант (ref=slug, без a/b) — выход-знание для гейта, не рецепт.
			if String(gd.get("kind", "")) != "recipe":
				continue
			_add_grant_def(g, String(gd.get("ref", "")),
				String(gd.get("a", "")), String(gd.get("b", "")), String(gd.get("out", "")))
	var recovered_v: Variant = result.get("recovered", [])
	if recovered_v is Array:
		for rc in (recovered_v as Array):
			if not (rc is Dictionary):
				continue
			var rd: Dictionary = rc
			_add_grant_def(g, String(rd.get("pair_key", "")),
				String(rd.get("a", "")), String(rd.get("b", "")), String(rd.get("out", "")))
	# Part C — advisory clamp offline-эфира ТОЛЬКО на миграционном первом заходе
	# (client_rev ещё не бампался) и только при положительном потолке. При
	# accrual_rate_declared=0 (Task 8 дефолт) потолок=0, и безусловный clamp стёр бы
	# легитимный банк; в штатном оффлайне не трогаем.
	if result.has("accrual_ceiling") and g._engine.client_rev == 0:
		var ceiling := float(result["accrual_ceiling"])
		if ceiling > 0.0 and g._engine.ether_overflow > int(ceiling):
			g._engine.ether_overflow = int(ceiling)

# Union-добавление определения пары: пропускаем пустой ключ и уже известное локально.
func _add_grant_def(g: Game, key: String, a: String, b: String, out: String) -> void:
	if key == "" or g._engine.known_recipe_defs.has(key):
		return
	g._engine.known_recipe_defs[key] = {"a": a, "b": b, "out": out}
	g._engine.known_recipes[key] = true

# Триггер синка: собрать пакет, отправить, результат разберёт _on_sync_result.
# Гейт — только `_net_enabled` (selftest/оффлайн-установка): сам Net fail-open
# при «сервера нет» (`_send_next` при base_url=="" тихо сливает очередь offline).
# НЕ гейтим по is_available(): на холодном boot/resume он ещё false, а union-
# рековери грантов — как раз цель boot-пакета (review #3). `net` — тестируемый
# шов (по образцу Net._try_send), в проде = автозагрузка Net.
func request_sync(game: Game, net: NetBase = Net) -> void:
	g = game
	if not game._online._net_enabled:
		last_sync_ok = false
		return
	_sync_dirty = false
	net.sync_package(Sync.build_package(game))

# Ответ /sync/package: серверный clock-якорь authoritative (Part A), гранты/
# восстановление union'ятся в локальное знание (Part B), всё остальное локально.
func _on_sync_result(result: Dictionary) -> void:
	last_sync_ok = bool(result.get("ok", false))
	if last_sync_ok and g != null:
		apply_reconcile(g, result)

# Локальное знание изменилось (варка/первооткрытие) — отложить flush на троттл.
func mark_dirty() -> void:
	_sync_dirty = true

func _process(delta: float) -> void:
	# Boot/resume синкают явно; таймер лишь occasionally льёт накопленное офлайн
	# знание, когда сеть появилась. В selftest _net_enabled=false → ранний выход.
	if g == null or not g._online._net_enabled:
		return
	_flush_clock += delta
	if _sync_dirty and _flush_clock >= Balance.SYNC_THROTTLE_SEC:
		_flush_clock = 0.0
		request_sync(g)


