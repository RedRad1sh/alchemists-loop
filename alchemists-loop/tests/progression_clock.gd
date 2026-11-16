extends RefCounted
class_name ProgressionClock

var game: Game
var active_seconds := 0.0
var offline_seconds := 0.0
var active_player_seconds := 0.0
var _now := 0.0
var segments: Array = []
var ledger: ProgressionLedger

func _init(target_game: Game) -> void:
	game = target_game

func set_time_source(callback: Callable) -> void:
	if game._selftest:
		game.game_clock = callback

func set_virtual_epoch(epoch: float) -> void:
	if not game._selftest or _now != 0.0 or not is_finite(epoch) or epoch <= 0.0:
		return
	_now = epoch
	game._last_ts = epoch
	game._workshop.last_simulated_at = epoch
	set_time_source(now)

func advance_active(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0.0:
		return
	var from := _now
	if ledger != null:
		ledger.perform(game, "retort_active", func(): return game._retort._queue_advance(_now, false))
	else:
		game._retort._queue_advance(_now, false)
	# Small chronological segments preserve queue maturities without a separate
	# retort timeline. All economy production remains in the common scheduler.
	var left := seconds
	while left > 0.000001:
		var step := minf(left, 3600.0)
		if game._retort._queue_on:
			for i in range(Game.RETORT_SLOT_MAX):
				if game._retort._retort_busy(i):
					var slot: Dictionary = game._retort._retort_slot(i)
					var due := float(slot.get("started", 0.0)) + float(slot.get("dur", 0.0))
					if due > _now:
						step = minf(step, due - _now)
		var stats: Dictionary = {}
		if ledger != null:
			stats = ledger.perform(game, "scheduler_active", func(): return game._workshop_scheduler.advance(step, false))
		else:
			stats = game._workshop_scheduler.advance(step, false)
		_now += step
		if ledger != null:
			ledger.perform(game, "retort_active", func(): return game._retort._queue_advance(_now, false))
		else:
			game._retort._queue_advance(_now, false)
		segments.append({"from_timestamp": _now - step, "until_timestamp": _now,
			"active_seconds": step, "offline_seconds": 0.0, "scheduler": stats})
		left -= step
	active_seconds += _now - from
	if game.game_clock.is_valid():
		game._last_ts = _now
		game._workshop.last_simulated_at = _now

func replay_offline(from_ts: float, to_ts: float) -> void:
	if not is_finite(from_ts) or not is_finite(to_ts) or to_ts <= from_ts:
		return
	var watermark := float(game._workshop.last_simulated_at)
	var start := maxf(from_ts, watermark)
	if to_ts <= start:
		return
	if game.game_clock.is_valid():
		_now = maxf(_now, to_ts)
		# Saves owns replay, retort window, durable watermark and checkpoint.
		if ledger != null:
			ledger.perform(game, "save_offline_replay", func(): game._saves._grant_offline())
		else:
			game._saves._grant_offline()
	else:
		game._workshop_scheduler.replay_offline(from_ts, to_ts)
		game._retort._queue_offline_replay(start, to_ts)
		offline_seconds += to_ts - start
		_now = maxf(_now, to_ts)
		return
	offline_seconds += to_ts - start
	segments.append({"from_timestamp": start, "until_timestamp": to_ts,
		"active_seconds": 0.0, "offline_seconds": to_ts - start,
		"scheduler": game._saves._return_workshop.duplicate(true)})

func now() -> float:
	return _now

func snapshot() -> Dictionary:
	return {"now": _now, "active_seconds": active_seconds, "offline_seconds": offline_seconds,
		"active_player_seconds": active_player_seconds, "simulated_real_seconds": active_seconds + offline_seconds}
