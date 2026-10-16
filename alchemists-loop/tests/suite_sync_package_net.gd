extends RefCounted
class_name SuiteSyncPackageNet
# Task 9: Net.sync_package() enqueue-шов + Sync.apply_reconcile (Part A server-wins /
# Part B union / Part C clamp). Синк — единая точка: ответ сервера пополняет знание,
# ничего локального не удаляет.

const NetBase := preload("res://autoload/net.gd")

# Шов: перехватываем _enqueue, не трогая HTTP/очередь живого autoload.
class CaptureNet extends NetBase:
	var captured: Array = []
	func _enqueue(req: Dictionary) -> void:
		captured.append(req)

static func run(g: Game) -> void:
	var saved_known: Dictionary = g._engine.known_recipes.duplicate()
	var saved_defs: Dictionary = g._engine.known_recipe_defs.duplicate(true)
	var saved_overflow: int = g._engine.ether_overflow
	var saved_rev: int = g._engine.client_rev

	# Net-шов: sync_package(pkg) → enqueue kind=sync_package, POST /sync/package, body=pkg.
	var cn := CaptureNet.new()
	var pkg := {"device_id": "dev-1", "part_b": {"recipes": []}}
	cn.sync_package(pkg)
	var routed := false
	if not cn.captured.is_empty():
		var req: Dictionary = cn.captured[0]
		routed = String(req.get("kind", "")) == "sync_package" \
			and String(req.get("path", "")) == "/sync/package" \
			and req.has("body")
	Selftest.check("sync_net: sync_package enqueues POST /sync/package with body", routed)

	# Part B union: recovery-грант добавляется, локальное знание остаётся целым.
	g._engine.known_recipes.clear()
	g._engine.known_recipe_defs.clear()
	var local := g._pair_key("fire", "water")
	g._engine.known_recipe_defs[local] = {"a": "fire", "b": "water", "out": "steam"}
	g._engine.known_recipes[local] = true
	var ghost := g._pair_key("sand", "fire")
	g._sync.apply_reconcile(g, {"ok": true, "grants": [],
		"recovered": [{"pair_key": ghost, "a": "sand", "b": "fire", "out": "glass"}]})
	Selftest.check("sync_reconcile: recovery grant added, local kept", \
		g._engine.known_recipes.has(local) and g._engine.known_recipes.has(ghost) \
		and g._engine.known_recipe_defs.has(ghost))

	g._engine.known_recipes = saved_known
	g._engine.known_recipe_defs = saved_defs
	g._engine.ether_overflow = saved_overflow
	g._engine.client_rev = saved_rev

	# Review #3: boot/resume-синк обязан ставить пакет в очередь, даже когда
	# Net ещё НЕ помечен available (is_available()==false на холодном старте).
	# Иначе union-рековери грантов (главная цель boot-пакета) молча не происходит.
	# fail-open при «сервера нет» обеспечивает сам Net (_send_next base_url=="" →
	# тихий offline-дренаж), а не этот гейт. Мутация-красная: вернуть
	# `and not Net.is_available()` в request_sync → enqueued=false, тест красный.
	var saved_net_enabled: bool = g._online._net_enabled
	var saved_device_id: String = g._online._device_id
	var cn2 := CaptureNet.new()
	g._online._net_enabled = true
	g._online._device_id = "dev-boot"
	g._engine.known_recipes.clear()
	g._engine.known_recipe_defs.clear()
	var bkey := g._pair_key("fire", "water")
	g._engine.known_recipe_defs[bkey] = {"a": "fire", "b": "water", "out": "steam"}
	g._engine.known_recipes[bkey] = true
	g._sync.request_sync(g, cn2)
	var enqueued := false
	if not cn2.captured.is_empty():
		var req: Dictionary = cn2.captured[0]
		enqueued = String(req.get("kind", "")) == "sync_package" and req.has("body")
	Selftest.check("sync_net: boot request_sync enqueues even when Net not yet available", enqueued)
	g._online._net_enabled = saved_net_enabled
	g._online._device_id = saved_device_id
	g._engine.known_recipes.clear()
	g._engine.known_recipe_defs.clear()
