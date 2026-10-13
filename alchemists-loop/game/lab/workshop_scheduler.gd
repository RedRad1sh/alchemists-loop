extends RefCounted
class_name WorkshopScheduler
# One chronological executor. Phases are effective ONLINE seconds; offline
# scales elapsed time, never the saved phase. A ready stage freezes its phase.
const EPS := 0.0000001
const MAX_EVENTS := 100000

var g: Game
var workshop: Workshop
var _blocked: Dictionary = {}
var _signature := 0
var _mutation := 0
var _readonly_watermark := 0.0
var _running := false
var _line_changed := false
var _stats: Dictionary = {}
var _stages: Dictionary = {}
var _offline := false
var _manual_phase := 0.0
var _manual_ready := false
var _manual_left := 0
var _manual_block: Array = []

func _init(game: Game, model: Workshop) -> void:
	g = game
	workshop = model

func _blank() -> Dictionary:
	var lines := {}
	for line in workshop.lines:
		lines[String(line["id"])] = {"steps": 0, "items": 0, "mastery": 0, "ether_spent": 0,
			"stages": 0, "status": "idle", "reason": "", "queue_count": line["queue"].size()}
	return {"steps": 0, "items": 0, "mastery": 0, "ether_spent": 0,
		"ether_gained": 0, "spring_items": 0, "craft_steps": 0, "craft_items": 0,
		"craft_status": "", "lines": lines, "events": 0, "simulated_seconds": 0.0,
		"skipped_seconds": 0.0, "simulated_until": 0.0, "consumed_until": 0.0, "status": "idle"}

func _writable() -> bool:
	return workshop.unlocked and not workshop.is_read_only()

func _interval(line: Dictionary) -> float:
	var target := ""
	if not line["queue"].is_empty(): target = String(line["queue"][0]["target"])
	var interval: float = g._sigil.bench_interval(target)
	return interval if is_finite(interval) and interval > EPS else Game.BENCH_INTERVAL

func _token() -> Array:
	return [_signature, _mutation]

func _resource_signature() -> int:
	var commands: Array = []
	for line in workshop.lines:
		var jobs: Array = []
		for job in line["queue"]:
			jobs.append([job["id"], job["target"], job["mode"], job["amount"], job["produced"]])
		commands.append([line["id"], line["paused"], jobs, _interval(line)])
	return hash([g._engine.inventory, g._engine.known_recipes, g.RECIPES,
		g._engine.ether, g._engine.ether_overflow, g._engine._blueprints,
		g._engine.brewing, g._engine._auto, g._pages._bench_busy,
		g._engine._resource_mutation_allowed(), g._engine._stage_ops(), commands])

func advance(delta_seconds: float, offline := false) -> Dictionary:
	if _running or not is_finite(delta_seconds) or delta_seconds < 0.0:
		return _blank()
	if offline and delta_seconds < Game.OFFLINE_MIN_SEC:
		var ignored := _blank()
		ignored["skipped_seconds"] = delta_seconds
		return ignored
	_running = true
	_offline = offline
	_stats = _blank()
	_stats["status"] = "complete"
	_stages.clear()
	_line_changed = false
	_signature = _resource_signature()
	_mutation = 0
	_manual_phase = 0.0
	_manual_ready = false
	_manual_left = g._engine._stage_ops() if offline and not workshop.is_read_only() else 0
	_manual_block.clear()
	var duration := minf(delta_seconds, Game.OFFLINE_CAP_SEC)
	_stats["skipped_seconds"] = delta_seconds - duration
	var frozen: bool = g._saves._save_frozen
	if offline: g._saves._save_frozen = true
	_normalise()
	var elapsed := 0.0
	while true:
		_mature()
		_dispatch_manual()
		_dispatch_lines()
		if elapsed >= duration - EPS: break
		if int(_stats["events"]) >= MAX_EVENTS:
			_stats["status"] = "event_limit"
			_stats["skipped_seconds"] += duration - elapsed
			break
		var dt := _next_event(duration - elapsed)
		if not is_finite(dt) or dt <= 0.0:
			_stats["status"] = "invalid_event"
			_stats["skipped_seconds"] += duration - elapsed
			break
		_elapse(dt)
		elapsed += dt
		_stats["events"] += 1
	_stats["simulated_seconds"] = elapsed
	_summarise()
	if offline: g._saves._save_frozen = frozen
	_running = false
	if _line_changed: workshop.changed.emit()
	return _stats

func _normalise() -> void:
	if not is_finite(g._engine.regen_clock): g._engine.regen_clock = 0.0
	g._engine.regen_clock = fposmod(maxf(0.0, g._engine.regen_clock), 1.0)
	if not is_finite(g._pages._spring_clock): g._pages._spring_clock = 0.0
	g._pages._spring_clock = fposmod(maxf(0.0, g._pages._spring_clock), Game.SPRING_INTERVAL)
	if not _writable(): return
	for line in workshop.lines:
		var old_phase: float = line["phase_seconds"]
		var phase := clampf(old_phase, 0.0, _interval(line)) if is_finite(old_phase) else 0.0
		var credit := clampi(int(line["stage_credit"]), 0, g._engine._stage_ops())
		if phase != old_phase or credit != int(line["stage_credit"]): _line_changed = true
		line["phase_seconds"] = 0.0 if credit > 0 else phase
		line["stage_credit"] = credit
		_stages[line["id"]] = 1 if _offline and credit > 0 else 0
		_stats["lines"][line["id"]]["stages"] = _stages[line["id"]]
		if line["queue"].is_empty():
			_clear_ready(line)

func _clear_ready(line: Dictionary) -> void:
	if line["stage_credit"] != 0 or line["phase_seconds"] != 0.0: _line_changed = true
	line["stage_credit"] = 0
	line["phase_seconds"] = 0.0
	_blocked.erase(line["id"])

func _timer_active(line: Dictionary) -> bool:
	return _writable() and not line["paused"] and not line["queue"].is_empty() \
		and int(line["stage_credit"]) == 0 \
		and (not _offline or int(_stages.get(line["id"], 0)) < workshop.offline_stage_limit())

func _mature() -> void:
	if not _writable(): return
	for line in workshop.lines:
		if _timer_active(line) and float(line["phase_seconds"]) >= _interval(line) - EPS:
			line["phase_seconds"] = 0.0
			line["stage_credit"] = g._engine._stage_ops()
			_stages[line["id"]] = int(_stages.get(line["id"], 0)) + 1
			_stats["lines"][line["id"]]["stages"] = _stages[line["id"]]
			_blocked.erase(line["id"])
			_line_changed = true

func _manual_active() -> bool:
	return _offline and _manual_left > 0 and not g._engine._craft_job.is_empty() and not workshop.is_read_only()

func _spring_active() -> bool:
	if not g._engine.spring_on or not g._engine._mode_unlocked("spring"):
		return false
	return true

func _next_event(remaining: float) -> float:
	var dt := remaining
	var rate: float = g._engine._ether_rate()
	if is_finite(rate) and rate > 0.0 and g._engine.ether < g._engine._max_ether():
		dt = minf(dt, maxf(EPS, (1.0 - g._engine.regen_clock) / rate))
	if _spring_active():
		dt = minf(dt, maxf(EPS, g._engine.spring_interval() - g._pages._spring_clock))
	var speed := Game.BENCH_OFFLINE_FACTOR if _offline else 1.0
	for line in workshop.lines:
		if _timer_active(line):
			dt = minf(dt, maxf(EPS, (_interval(line) - float(line["phase_seconds"])) / speed))
	if _manual_active() and not _manual_ready:
		dt = minf(dt, maxf(EPS, g._engine._brew_time() - _manual_phase))
	return dt

func _elapse(dt: float) -> void:
	var rate: float = g._engine._ether_rate()
	if is_finite(rate) and rate > 0.0:
		var produced := g._engine.regen_clock + dt * rate
		var ticks := int(floor(produced + EPS))
		g._engine.regen_clock = maxf(0.0, produced - float(ticks))
		var gain := mini(ticks, maxi(0, g._engine._max_ether() - g._engine.ether))
		g._engine.ether += gain
		_stats["ether_gained"] += gain
		if gain > 0: _mutation += 1
	if _spring_active():
		g._pages._spring_clock += dt
		var interval: float = g._engine.spring_interval()
		if g._pages._spring_clock >= interval - EPS:
			g._pages._spring_clock = maxf(0.0, g._pages._spring_clock - interval)
			if _offline:
				# Офлайн: не проверяем буфер, просто производим в инвентарь
				for source in g._engine.spring_sources:
					g._engine.inventory[source] = int(g._engine.inventory.get(source, 0)) + 1
					_stats["spring_items"] += 1
					_mutation += 1
			else:
				# Онлайн: проверяем буфер
				var volume_cap: int = SpringBalance.VOLUME_CAP[g._engine.spring_levels.get("volume", 0)]
				for source in g._engine.spring_sources:
					var current_buffer: int = g._engine.spring_buffer.get(source, 0)
					if current_buffer < volume_cap:
						g._engine.spring_buffer[source] = current_buffer + 1
						g._engine.inventory[source] = int(g._engine.inventory.get(source, 0)) + 1
						_stats["spring_items"] += 1
						_mutation += 1
	elif _offline and g._engine.spring_on and g._engine._mode_unlocked("spring"):
		var interval: float = g._engine.spring_interval()
		g._pages._spring_clock = fposmod(g._pages._spring_clock + dt, interval)
	var speed := Game.BENCH_OFFLINE_FACTOR if _offline else 1.0
	for line in workshop.lines:
		if _timer_active(line):
			line["phase_seconds"] = float(line["phase_seconds"]) + dt * speed
			_line_changed = true
	if _manual_active() and not _manual_ready:
		_manual_phase += dt
		if _manual_phase >= g._engine._brew_time() - EPS:
			_manual_phase = 0.0
			_manual_ready = true

func _busy() -> bool:
	return g._engine.brewing or g._engine._auto or g._pages._bench_busy \
		or not g._engine._resource_mutation_allowed()

func _set_status(job: Dictionary, status: String, reason: String) -> void:
	if job.get("status", "") != status or job.get("reason", "") != reason:
		job["status"] = status
		job["reason"] = reason
		_line_changed = true

func _reason(code: String) -> String:
	match code:
		"ether": return "Не хватает эфира (включая резерв)."
		"ingredients": return "Не хватает ингредиентов: добудь из источников или дождись другой линии."
		"inventory": return "Достигнут предел запаса вещества."
		"stock": return "Нужный общий запас уже произведён."
		"busy": return "Котёл занят ручной варкой или производством."
		_: return "Сначала открой рецепт вещества и его зависимостей."

func _plan(target: String) -> Dictionary:
	if not workshop.known_target_recipe(target): return {"ok": false, "code": "recipe"}
	var plan: Dictionary = g._guild._plan_craft(target)
	if not bool(plan.get("ok", false)):
		var frontier: Dictionary = g._guild._plan_known_frontier(target)
		plan["code"] = "recipe" if not frontier.get("frontier", []).is_empty() or not frontier.get("missing", []).is_empty() else "ingredients"
	elif int(plan.get("total", 0)) <= 0 or int(plan.get("total", 0)) > Game.CRAFT_PLAN_HARD_LIMIT_OPERATIONS:
		return {"ok": false, "code": "recipe"}
	return plan

func _operation(target: String, discount: float) -> Dictionary:
	if _busy(): return {"failed": true, "reason": "busy"}
	var plan := _plan(target)
	if not bool(plan.get("ok", false)): return {"failed": true, "reason": plan.get("code", "recipe")}
	var ops: Array = plan.get("ops", [])
	if ops.is_empty(): return {"failed": true, "reason": "recipe"}
	var op: Dictionary = ops[0]
	var result: Dictionary = g._engine._commit_brew(String(op["a"]), String(op["b"]),
		{"source": "offline_workshop" if _offline else "workshop", "production": true, "discount": discount})
	result["plan"] = plan
	return result

func _count(result: Dictionary, line_id := "") -> void:
	_stats["steps"] += 1
	_stats["mastery"] += int(result.get("mastery_awarded", 0))
	_stats["ether_spent"] += int(result.get("ether_spent", 0))
	if line_id != "":
		var line: Dictionary = _stats["lines"][line_id]
		line["steps"] += 1
		line["mastery"] += int(result.get("mastery_awarded", 0))
		line["ether_spent"] += int(result.get("ether_spent", 0))
	_mutation += 1

func _blueprint(target: String, result: Dictionary, actual_operations: int) -> void:
	var plan: Dictionary = result["plan"].duplicate(true)
	# Only confirmed target outputs reach here. A replayed estimate never earns XP.
	plan["total"] = actual_operations
	g._engine._record_blueprint(target, plan)

func _dispatch_lines() -> void:
	if not _writable() or workshop.lines.is_empty(): return
	var count := workshop.lines.size()
	while true:
		var progressed := false
		var start := posmod(workshop.scheduler_cursor, count)
		for offset in count:
			var index := (start + offset) % count
			var line: Dictionary = workshop.lines[index]
			if line["queue"].is_empty():
				_clear_ready(line)
				continue
			var job: Dictionary = line["queue"][0]
			if line["paused"]:
				_set_status(job, "paused_user", "Линия остановлена игроком.")
				continue
			if _blocked.get(line["id"], []) == _token(): continue
			var target := String(job["target"])
			if job["mode"] == "stock" and int(g._engine.inventory.get(target, 0)) >= int(job["amount"]):
				_set_status(job, "waiting_inventory", _reason("stock"))
				_blocked[line["id"]] = _token()
				continue
			if job["mode"] == "batch" and int(job["produced"]) >= int(job["amount"]):
				line["queue"].pop_front()
				progressed = true
				_line_changed = true
				continue
			if int(line["stage_credit"]) <= 0: continue
			var discount := Game.BLUEPRINT_DISCOUNT if g._engine._blueprints.has(target) else 1.0
			var result := _operation(target, discount)
			if bool(result.get("failed", true)):
				var code := String(result.get("reason", "recipe"))
				_set_status(job, "running" if code == "busy" else "waiting_" + code, _reason(code))
				_blocked[line["id"]] = _token()
				continue
			_count(result, String(line["id"]))
			line["stage_credit"] = int(line["stage_credit"]) - 1
			job["route_operations"] = int(job["route_operations"]) + 1
			_set_status(job, "running", "")
			workshop.scheduler_cursor = (index + 1) % count
			_line_changed = true
			progressed = true
			if String(result.get("output", "")) == target:
				job["produced"] = int(job["produced"]) + 1
				_stats["items"] += 1
				_stats["lines"][line["id"]]["items"] += 1
				_blueprint(target, result, int(job["route_operations"]))
				job["route_operations"] = 0
				if job["mode"] == "batch" and int(job["produced"]) >= int(job["amount"]): line["queue"].pop_front()
			if line["queue"].is_empty(): _clear_ready(line)
		if not progressed: break

func _dispatch_manual() -> void:
	if not _manual_active() or not _manual_ready or _manual_block == _token(): return
	var job: Dictionary = g._engine._craft_job
	var target := String(job.get("item", ""))
	var discount := float(job.get("discount", 1.0))
	if not is_finite(discount) or discount <= 0.0 or discount > 1.0:
		discount = Game.BLUEPRINT_DISCOUNT if g._engine._blueprints.has(target) else 1.0
	var result := _operation(target, discount)
	if bool(result.get("failed", true)):
		var code := String(result.get("reason", "recipe"))
		job["status"] = "paused_" + code
		_stats["craft_status"] = code
		_manual_block = _token()
		return
	_count(result)
	_stats["craft_steps"] += 1
	job["completed"] = int(job.get("completed", 0)) + 1
	_manual_left -= 1
	_manual_ready = false
	if String(result.get("output", "")) == target:
		_blueprint(target, result, int(job["completed"]))
		g._engine._craft_job.clear()
		_stats["items"] += 1
		_stats["craft_items"] += 1
		_stats["craft_status"] = "complete"
	elif _manual_left <= 0:
		job["status"] = "paused_operation_cap"
		_stats["craft_status"] = "operation_cap"
	else:
		job["status"] = "running"
		_stats["craft_status"] = "running"

func _summarise() -> void:
	for line in workshop.lines:
		var info: Dictionary = _stats["lines"][line["id"]]
		info["queue_count"] = line["queue"].size()
		if workshop.is_read_only():
			info["status"] = "read_only"
		elif not workshop.unlocked:
			info["status"] = "locked"
		elif not line["queue"].is_empty():
			info["status"] = line["queue"][0]["status"]
			info["reason"] = line["queue"][0]["reason"]
			if _offline and int(_stages.get(line["id"], 0)) >= workshop.offline_stage_limit() and int(line["stage_credit"]) == 0:
				info["reason"] = "Достигнут предел автономных этапов."

func replay_offline(from_ts: float, to_ts: float) -> Dictionary:
	var empty := _blank()
	if _running or not is_finite(from_ts) or not is_finite(to_ts) or from_ts < 0.0 or to_ts < 0.0:
		return empty
	var watermark := workshop.last_simulated_at
	if workshop.is_read_only():
		var raw: Variant = workshop.export_state().get("last_simulated_at", 0.0)
		watermark = float(raw) if (raw is float or raw is int) and is_finite(float(raw)) and float(raw) >= 0.0 else 0.0
		watermark = maxf(watermark, _readonly_watermark)
	var start := maxf(from_ts, watermark)
	if to_ts <= start:
		empty["consumed_until"] = watermark
		empty["simulated_until"] = start
		return empty
	# The public replay transaction includes the final changed signal and the
	# watermark, not just the operation loop inside advance().
	var frozen: bool = g._saves._save_frozen
	g._saves._save_frozen = true
	var result := advance(to_ts - start, true)
	result["simulated_until"] = start + float(result["simulated_seconds"])
	result["consumed_until"] = to_ts
	# Consume below-minimum and capped-away time. No retry can spend it again.
	if workshop.is_read_only(): _readonly_watermark = to_ts
	else: workshop.last_simulated_at = to_ts
	g._saves._save_frozen = frozen
	return result
