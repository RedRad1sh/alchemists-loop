extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")
const Scheduler = preload("res://game/lab/workshop_scheduler.gd")

class CountingScheduler extends WorkshopScheduler:
	var replay_calls := 0
	var advance_calls := 0
	var initial_regen := 0.0
	var initial_spring := 0.0
	func replay_offline(from_ts: float, to_ts: float) -> Dictionary:
		replay_calls += 1
		initial_regen = g._engine.regen_clock
		initial_spring = g._pages._spring_clock
		return super(from_ts, to_ts)
	func advance(delta_seconds: float, offline := false) -> Dictionary:
		advance_calls += 1
		return super(delta_seconds, offline)

static func run(g: Game) -> void:
	var before := Selftest._total
	var failures := Selftest._fails
	var fixture := Fixture.new(g)
	var original_scheduler = g._workshop_scheduler
	g.SAVE_PATH = "user://alchemy_st_workshop_saves.json"
	g.TEMP_PATH = "user://alchemy_st_workshop_saves.tmp"
	g.BACKUP_PATH = "user://alchemy_st_workshop_saves.bak"
	_wipe(g)
	_snapshot(g, fixture)
	_validation(g, fixture)
	_replay(g, fixture)
	_future_restart(g, fixture)
	_failures(g, fixture)
	_adapters(g, fixture)
	_popup(g, fixture)
	_wipe(g)
	g._workshop_scheduler = original_scheduler
	fixture.finish()
	print("WORKSHOP_SAVES_CHECKS: %d/%d" % [Selftest._total - before - (Selftest._fails - failures), Selftest._total - before])

static func _prepare(g: Game, fixture, targets: Array = []) -> Workshop:
	fixture.prepare_production()
	g._engine.mastery_rank = 0
	g._engine.regen_clock = 0.0
	g._pages._spring_clock = 0.0
	g._sigil._milestones_claimed = {}
	g._pages._bench_target = ""
	g._pages._bench_clock = 0.0
	g._saves._save_frozen = true
	var w: Workshop = g._workshop
	w.import_state({"version": 1, "unlocked": true, "rank": maxi(0, targets.size() - 1),
		"xp": 400, "last_simulated_at": 1000.0})
	for i in targets.size():
		g._engine.inventory[targets[i]] = 0
		w.enqueue(w.lines[i]["id"], {"target": targets[i], "mode": "batch", "amount": 6})
	g._workshop_scheduler = CountingScheduler.new(g, w)
	g._last_ts = 1000.0
	return w

static func _snapshot(g: Game, fixture) -> void:
	var w := _prepare(g, fixture, ["steam", "dust"])
	w.autonomy_level = 1
	w.lines[0]["phase_seconds"] = 12.5
	w.scheduler_cursor = 1
	g._engine.regen_clock = 0.375
	g._pages._spring_clock = 2.25
	g._saves._save_frozen = false
	var earliest := Time.get_unix_time_from_system()
	var ok: Variant = g._saves.call("_save_game")
	var saved := g._saves._read_save(g.SAVE_PATH)
	var state: Dictionary = saved.get("workshop", {})
	Selftest.check("saves successful atomic write returns true", ok == true)
	Selftest.check("saves online watermark uses authoritative save time", float(state.get("last_simulated_at", 0.0)) >= earliest
		and float(state.get("last_simulated_at", INF)) <= Time.get_unix_time_from_system()
		and state.get("last_simulated_at") == saved.get("last_ts")
		and w.last_simulated_at == state.get("last_simulated_at") and g._last_ts == saved.get("last_ts"))
	Selftest.check("saves one snapshot contains fractions resources equipment queues cursor", saved.get("regen_clock", -1) == 0.375
		and saved.get("spring_clock", -1) == 2.25 and _same_json(saved.get("inventory"), g._engine.inventory)
		and state.get("xp") == 400 and state.get("rank") == 1 and state.get("autonomy_level") == 1
		and state.get("scheduler_cursor") == 1 and _same_json(state.get("lines"), w.lines))
	g._saves._save_frozen = true
	g._engine.regen_clock = 0.0
	g._pages._spring_clock = 0.0
	w.reset_new_game()
	g._saves._load_game()
	Selftest.check("saves actual load restores fractional clocks and full workshop", g._engine.regen_clock == 0.375
		and g._pages._spring_clock == 2.25 and _same_json(w.export_state(), state) and g._saves._save_frozen)
	var during_load := {"calls": 0, "blocked": true}
	var try_partial_save := func() -> void:
		during_load["calls"] += 1
		during_load["blocked"] = during_load["blocked"] and g._saves.call("_save_game") == false
	w.changed.connect(try_partial_save)
	g._saves._save_frozen = false
	g._saves._load_game()
	w.changed.disconnect(try_partial_save)
	Selftest.check("saves loading blocks partial restoration callbacks then restores unfrozen policy", during_load["calls"] > 0
		and during_load["blocked"] and not g._saves._save_frozen)
	g._selftest = false
	g._engine.regen_clock = 0.0
	g._pages._spring_clock = 0.0
	g._saves._load_game()
	g._selftest = true
	Selftest.check("saves restored clocks enter the one shared replay before any grant", g._workshop_scheduler.initial_regen == 0.375
		and g._workshop_scheduler.initial_spring == 2.25 and g._workshop_scheduler.replay_calls == 1)
	var future := Time.get_unix_time_from_system() + 3600.0
	w.last_simulated_at = future
	g._last_ts = future + 10.0
	g._saves._save_frozen = false
	g._saves._save_game()
	saved = g._saves._read_save(g.SAVE_PATH)
	Selftest.check("saves backward clock cannot lower either persisted watermark", saved.get("last_ts") == future + 10.0
		and saved["workshop"]["last_simulated_at"] == future + 10.0 and w.last_simulated_at == future + 10.0)
	g._saves._save_frozen = true

static func _validation(g: Game, fixture) -> void:
	_prepare(g, fixture)
	g._saves._save_frozen = false
	g._saves._save_game()
	g._saves._save_frozen = true
	var data := g._saves._read_save(g.SAVE_PATH)
	for bad in [null, "0.25", true, -0.1, {}, [], 1.0, 2.0]:
		data["regen_clock"] = bad
		data["spring_clock"] = bad if not bad is float or bad < 1.0 else Game.SPRING_INTERVAL
		_write(g.SAVE_PATH, data)
		g._engine.regen_clock = 0.5
		g._pages._spring_clock = 0.5
		g._saves._load_game()
		Selftest.check("saves invalid clocks rejected on actual load " + str(bad), g._engine.regen_clock == 0.0
			and g._pages._spring_clock == 0.0)
	data.erase("regen_clock")
	data.erase("spring_clock")
	_write(g.SAVE_PATH, data)
	g._engine.regen_clock = 0.75
	g._pages._spring_clock = 0.75
	g._saves._load_game()
	Selftest.check("saves missing legacy clocks reset instead of leaking previous world", g._engine.regen_clock == 0.0
		and g._pages._spring_clock == 0.0)
	for bad in [NAN, INF, -INF, -1.0, 1.0]:
		g._engine.regen_clock = bad
		g._pages._spring_clock = bad if bad < 1.0 or not is_finite(bad) else Game.SPRING_INTERVAL
		g._saves._save_frozen = false
		g._saves._save_game()
		g._saves._save_frozen = true
		data = g._saves._read_save(g.SAVE_PATH)
		Selftest.check("saves never serializes invalid finite or nonfinite clock " + str(bad), data.get("regen_clock", -1) == 0.0
			and data.get("spring_clock", -1) == 0.0)

static func _grant(g: Game) -> void:
	var selftest: bool = g._selftest
	g._selftest = false
	g._saves._grant_offline()
	g._selftest = selftest

static func _replay(g: Game, fixture) -> void:
	var w := _prepare(g, fixture, ["steam", "dust"])
	g._engine._craft_job = {"item": "steam", "completed": 0, "discount": 1.0, "total_estimate": 1}
	g._engine.inventory["person"] = 1
	g._engine.inventory["plant"] = 1
	g._engine.spring_on = true
	g._engine.spring_source = "fire"
	g._last_ts = Time.get_unix_time_from_system() - 160.1
	w.last_simulated_at = g._last_ts
	var seen := {"calls": 0, "frozen": true, "writes_blocked": true}
	var save_during_commit := func() -> void:
		seen["calls"] += 1
		seen["frozen"] = seen["frozen"] and g._saves._save_frozen
		seen["writes_blocked"] = seen["writes_blocked"] and g._saves.call("_save_game") == false
	w.changed.connect(save_during_commit)
	g._saves._save_frozen = false
	_grant(g)
	w.changed.disconnect(save_during_commit)
	var scheduler = g._workshop_scheduler
	var receipt: Variant = g._saves.get("_return_workshop")
	Selftest.check("saves orchestrator calls one replay and one advance for all consumers", scheduler.replay_calls == 1
		and scheduler.advance_calls == 1 and g._engine.inventory["steam"] == 7 and g._engine.inventory["dust"] == 6)
	Selftest.check("saves callbacks stay frozen until replay watermark and restore policy", seen["calls"] > 0
		and seen["frozen"] and seen["writes_blocked"] and not g._saves._save_frozen)
	Selftest.check("saves receipt projects only actual shared and manual and line counters", receipt is Dictionary
		and receipt.get("steps") == 13 and receipt.get("mastery") == 13
		and receipt.get("craft_steps") == 1 and g._saves._return_craft_steps == 1
		and g._saves._return_bench_steps == 12 and g._saves._return_bench_items == 12
		and g._saves._return_spring == receipt.get("spring_items")
		and g._saves._return_ether == receipt.get("ether_gained") and receipt.get("saved") == true)
	var saved := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("saves replay durable snapshot includes final resources and watermark", _same_json(saved.get("inventory"), g._engine.inventory)
		and saved["workshop"]["xp"] == w.xp and saved.get("last_ts") == g._last_ts
		and saved["workshop"]["last_simulated_at"] == w.last_simulated_at
		and saved.get("regen_clock") == g._engine.regen_clock and saved.get("spring_clock") == g._pages._spring_clock)
	var inventory := g._engine.inventory.duplicate(true)
	var xp := w.xp
	g._saves._load_game()
	Selftest.check("saves real repeated reload grants no resources or mastery twice", g._engine.inventory == inventory and w.xp == xp)
	g._saves._save_frozen = true
	g._last_ts = Time.get_unix_time_from_system() - 80.1
	w.last_simulated_at = g._last_ts
	_grant(g)
	receipt = g._saves.get("_return_workshop")
	Selftest.check("saves previously frozen replay stays frozen and reports nondurable receipt", g._saves._save_frozen
		and receipt is Dictionary and receipt.get("saved") == false)

static func _future_restart(g: Game, fixture) -> void:
	var w := _prepare(g, fixture)
	var raw := {"version": 999, "last_simulated_at": Time.get_unix_time_from_system() - 160.1,
		"lines": [{"opaque": ["future", 5]}], "xp": 54321, "unknown": {"keep": true}}
	w.import_state(raw)
	g._last_ts = raw["last_simulated_at"]
	g._engine.ether = 0
	g._engine.inventory["person"] = 1
	g._engine.inventory["plant"] = 1
	g._engine.spring_on = true
	g._engine.spring_source = "fire"
	g._saves._save_frozen = false
	_grant(g)
	var saved := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("saves future block remains immutable while shared resources replay", _same_json(saved.get("workshop"), raw)
		and saved.get("ether", 0) > 0 and saved.get("last_ts", 0) > raw["last_simulated_at"])
	var ether := g._engine.ether
	var inventory := g._engine.inventory.duplicate(true)
	# Recreate the scheduler, removing its in-memory read-only high-water mark.
	g._workshop_scheduler = CountingScheduler.new(g, w)
	var selftest: bool = g._selftest
	g._selftest = false
	g._saves._load_game()
	g._selftest = selftest
	Selftest.check("saves future process restart uses external watermark exactly once", g._engine.ether == ether
		and g._engine.inventory == inventory and _same_json(w.export_state(), raw)
		and g._workshop_scheduler.replay_calls == 1)
	g._saves._save_frozen = true

static func _failures(g: Game, fixture) -> void:
	var w := _prepare(g, fixture)
	g._saves._save_frozen = false
	g._saves._save_game()
	var durable := _text(g.SAVE_PATH)
	var timestamp := g._last_ts
	var watermark := w.last_simulated_at
	var temp := g.TEMP_PATH
	g.TEMP_PATH = "user://alchemy_st_missing_saves_directory/fail.tmp"
	g._engine.inventory["fire"] = 37
	var result: Variant = g._saves.call("_save_game")
	Selftest.check("saves failed temp open returns false and preserves durable snapshot", result == false and _text(g.SAVE_PATH) == durable)
	Selftest.check("saves failed write cannot claim a new durable in-memory watermark", g._last_ts == timestamp and w.last_simulated_at == watermark)
	g.TEMP_PATH = temp
	var save := g.SAVE_PATH
	g.SAVE_PATH = "user://alchemy_st_missing_saves_directory/fail.json"
	result = g._saves.call("_save_game")
	Selftest.check("saves failed final install returns false and preserves prior save", result == false and _text(save) == durable
		and g._last_ts == timestamp and w.last_simulated_at == watermark)
	g.SAVE_PATH = save
	g._saves._save_frozen = true
	Selftest.check("saves frozen save is not reported durable", g._saves.call("_save_game") == false and _text(save) == durable)

static func _adapters(g: Game, fixture) -> void:
	var w := _prepare(g, fixture, ["steam", "dust"])
	g._engine._craft_job = {"item": "steam", "completed": 0, "discount": 1.0, "total_estimate": 1}
	g._pages._bench_target = "steam"
	g._pages._bench_on = true
	g._saves._saves_bench_probe = false
	Selftest.check("saves bench adapter retains selftest opt-in gate", g._saves._advance_bench_offline(80.0).is_empty()
		and g._workshop_scheduler.advance_calls == 0)
	g._saves._saves_bench_probe = true
	var result := g._saves._advance_bench_offline(80.0)
	Selftest.check("saves bench adapter simulates one shared window but reports lines only", g._workshop_scheduler.advance_calls == 1
		and result.get("steps") == 6 and result.get("items") == 6
		and g._engine.inventory["steam"] == 4 and g._engine.inventory["dust"] == 3)
	w = _prepare(g, fixture, ["dust"])
	g._engine._craft_job = {"item": "steam", "completed": 0, "discount": 1.0, "total_estimate": 1}
	result = g._saves._advance_craft_job_offline(80.0)
	Selftest.check("saves craft adapter simulates one shared window but reports manual only", g._workshop_scheduler.advance_calls == 1
		and result.get("steps") == 1 and result.get("status") == "complete"
		and g._engine.inventory["steam"] == 1 and g._engine.inventory["dust"] == 3)
	w.rank = 2
	w.autonomy_level = 2
	g._pages._bench_target = "brick"
	g._sigil._milestones_claimed = {"earth": [13]}
	Selftest.check("saves legacy ticks reflect category speed and current autonomy", g._saves._bench_offline_ticks(160.0) == 4
		and g._saves._bench_offline_ticks(Game.OFFLINE_CAP_SEC * 4.0) == 240)

static func _popup(g: Game, fixture) -> void:
	var w := _prepare(g, fixture, ["steam", "dust"])
	g._engine.inventory["earth"] = 0
	g._last_ts = Time.get_unix_time_from_system() - 80.1
	w.last_simulated_at = g._last_ts
	_grant(g)
	var receipt: Dictionary = g._saves.get("_return_workshop")
	Selftest.check("saves per-line receipt names actual target outputs and blocked queue", receipt["lines"]["line_1"]["outputs"].get("steam", -1) == 3
		and receipt["lines"]["line_1"]["mastery"] == 3 and receipt["lines"]["line_2"]["items"] == 0
		and receipt["lines"]["line_2"]["queue_count"] == 1 and receipt["lines"]["line_2"]["status"] == "waiting_ingredients")
	g._saves._refresh_return_popup()
	var text := ""
	for label in g._saves._return_list.get_children():
		if label is Label: text += label.text + "\n"
	Selftest.check("saves return popup renders both line identities actual operations output mastery queue", text.contains("line_1")
		and text.contains("line_2") and text.contains("Мастерство") and text.contains("операц")
		and text.contains("очеред") and text.contains(g._online._item_name("steam")))
	Selftest.check("saves return distinguishes processed time from blocked batch", text.contains("ингредиент")
		and not text.contains("Верстак в фоне") and not text.contains("Котёл уже был полон"))

static func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()

static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

static func _same_json(actual: Variant, expected: Variant) -> bool:
	# Godot's Dictionary equality distinguishes nested int/float values. JSON
	# decodes all numbers as floats; compare every field in the same numeric domain.
	return JSON.parse_string(JSON.stringify(actual, "", true, true)) == JSON.parse_string(JSON.stringify(expected, "", true, true))

static func _wipe(g: Game) -> void:
	for path in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
