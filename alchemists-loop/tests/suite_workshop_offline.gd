extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")
const Cases = preload("res://tests/suite_workshop_scheduler.gd")
const PATH := "res://game/lab/workshop_scheduler.gd"

static func run(g: Game) -> void:
	var before := Selftest._total
	var failures := Selftest._fails
	Selftest.check("offline shared scheduler API exists", FileAccess.file_exists(PATH))
	if not FileAccess.file_exists(PATH): return
	var script: Script = load(PATH)
	if script == null or not script.can_instantiate(): return
	var fixture := Fixture.new(g)
	_timing(g, script, fixture)
	_resources(g, script, fixture)
	_manual(g, script, fixture)
	_watermark(g, script, fixture)
	_stage_boundaries(g, script, fixture)
	fixture.finish()
	print("WORKSHOP_OFFLINE_CHECKS: %d/%d" % [Selftest._total - before - (Selftest._fails - failures), Selftest._total - before])

static func _timing(g: Game, script: Script, fixture) -> void:
	var w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	var s = script.new(g, w)
	var r: Dictionary = s.replay_offline(1000.0, 1059.0)
	Selftest.check("offline below 60s grants nothing and consumes watermark", r.get("steps", -1) == 0
		and r.get("ether_gained", -1) == 0 and w.last_simulated_at == 1059.0 and w.lines[0]["phase_seconds"] == 0.0)
	w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1080.0)
	Selftest.check("offline 80 seconds matures exactly one basic stage", r.get("steps", -1) == 3
		and w.lines[0]["phase_seconds"] == 0.0)
	w = Cases.prepare(g, fixture)
	s = script.new(g, w)
	Selftest.check("online 80 seconds matures two basic stages", s.advance(80.0).get("steps", -1) == 6)
	w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	w.lines[0]["phase_seconds"] = 10.0
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1060.0)
	Selftest.check("offline preserves partial phase and applies half factor once", r.get("steps", -1) == 3
		and w.lines[0]["phase_seconds"] == 0.0)
	for level in [0, 1, 2]:
		w = Cases.prepare(g, fixture, ["steam", "dust"], "batch", 1000)
		w.autonomy_level = level
		g._engine.inventory["fire"] = 10000
		g._engine.inventory["water"] = 10000
		g._engine.inventory["earth"] = 10000
		g._engine.inventory["air"] = 10000
		g._engine.ether = 100000
		w.last_simulated_at = 1000.0
		s = script.new(g, w)
		r = s.replay_offline(1000.0, 1000.0 + Game.OFFLINE_CAP_SEC * 2.0)
		var stages: int = [60, 120, 240][level]
		Selftest.check("offline autonomy stage cap per line level %d" % level, r.get("steps", -1) == stages * 6
			and r["lines"]["line_1"].get("stages", -1) == stages and r["lines"]["line_2"].get("stages", -1) == stages)
		Selftest.check("offline consumes capped-away window level %d" % level,
			w.last_simulated_at == 1000.0 + Game.OFFLINE_CAP_SEC * 2.0
			and r.get("simulated_seconds", -1) == Game.OFFLINE_CAP_SEC
			and s.replay_offline(1000.0, w.last_simulated_at).get("steps", -1) == 0)

static func _resources(g: Game, script: Script, fixture) -> void:
	var w = Cases.prepare(g, fixture)
	g._engine.ether = 0
	g._engine.inventory["steam"] = 0
	w.last_simulated_at = 1000.0
	var s = script.new(g, w)
	var rate: float = g._engine._ether_rate()
	var r: Dictionary = s.replay_offline(1000.0, 1800.0)
	Selftest.check("offline regen between stages resumes ether-starved production", r.get("steps", 0) > 3
		and r.get("ether_gained", 0) > 0 and r.get("ether_spent", 0) > 0
		and g._engine.ether == r["ether_gained"] - r["ether_spent"])
	Selftest.check("offline real mastery is sum of actual outputs", r.get("mastery", -1) == r.get("steps", -2)
		and w.xp == r.get("mastery", -1))
	w = Cases.prepare(g, fixture, ["steam", "steam"])
	w.last_simulated_at = 1000.0
	g._engine.inventory["fire"] = 0
	g._engine.inventory["plant"] = 0
	g._engine.spring_on = true
	g._engine.spring_source = "fire"
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 4600.0)
	Selftest.check("offline one spring feeds shared stock once per absence", r.get("spring_items", -1) == Game.SPRING_OFFLINE_MAX
		and r.get("steps", -1) == Game.SPRING_OFFLINE_MAX and g._engine.inventory["fire"] == 0)
	Selftest.check("offline spring itself awards no mastery", w.xp == r.get("steps", -1))
	w = Cases.prepare(g, fixture)
	w.lines.clear()
	g._engine.ether = g._engine._max_ether() - 1
	g._engine.ether_overflow = 37
	g._engine.regen_clock = 0.25
	s = script.new(g, w)
	rate = g._engine._ether_rate()
	r = s.advance(10.0)
	Selftest.check("shared regen fills active cap without overflow", r.get("ether_gained", -1) == 1
		and g._engine.ether == g._engine._max_ether() and g._engine.ether_overflow == 37)
	Selftest.check("shared regen preserves only fractional clock", is_equal_approx(g._engine.regen_clock, fposmod(0.25 + rate * 10.0, 1.0)))
	g._engine.inventory["plant"] = 0
	g._engine.spring_on = true
	g._engine.spring_source = "water"
	var xp: int = w.xp
	r = s.advance(Game.SPRING_INTERVAL * 3.0)
	Selftest.check("online spring catches all event arrivals without mastery", r.get("spring_items", -1) == 3 and w.xp == xp)

static func _manual(g: Game, script: Script, fixture) -> void:
	var w = Cases.prepare(g, fixture, ["steam"])
	w.last_simulated_at = 1000.0
	g._engine.inventory["brick"] = 0
	g._engine.inventory["clay"] = 0
	g._engine._craft_job = {"item": "brick", "completed": 0, "total_estimate": 999,
		"discount": 1.0, "status": "paused_ether", "plan": {"total": 999, "ops": []}}
	var s = script.new(g, w)
	var r: Dictionary = s.replay_offline(1000.0, 1080.0)
	Selftest.check("offline manual chain uses real target completion instead of stale estimate", r.get("craft_steps", -1) == 2
		and r.get("craft_status", "") == "complete" and g._engine._craft_job.is_empty()
		and g._engine.inventory["brick"] == 1 and g._engine._blueprints.has("brick"))
	Selftest.check("offline manual and lines share actual aggregate stats", r.get("steps", -1) == 5
		and r.get("items", -1) == 4 and r.get("mastery", -1) == 6)
	w = Cases.prepare(g, fixture, ["steam"])
	w.last_simulated_at = 1000.0
	g._engine.inventory["house"] = 0
	g._engine._craft_job = {"item": "house", "completed": 0, "total_estimate": 30,
		"discount": 1.0, "status": "paused", "plan": {"total": 30, "ops": []}}
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 2000.0)
	Selftest.check("offline manual chain bounded to one existing stage", r.get("craft_steps", -1) == 3
		and g._engine._craft_job.get("completed", -1) == 3
		and g._engine._craft_job.get("status", "") == "paused_operation_cap"
		and not g._engine._blueprints.has("house"))
	w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	g._engine.inventory["fire"] = 1
	g._engine.inventory["water"] = 1
	g._engine._craft_job = {"item": "steam", "completed": 0, "discount": 1.0}
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1080.0)
	Selftest.check("offline chronology manual early operation consumes last shared input", r.get("craft_steps", -1) == 1
		and r.get("steps", -1) == 1 and g._engine.inventory["steam"] == 1)
	Selftest.check("offline manual source leaves network queue empty", Net._queue.is_empty() and g._engine._resource_mutation_allowed())

static func _watermark(g: Game, script: Script, fixture) -> void:
	var w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1080.0
	var s = script.new(g, w)
	var r: Dictionary = s.replay_offline(1000.0, 1160.0)
	Selftest.check("offline starts at persisted watermark", r.get("steps", -1) == 3 and w.last_simulated_at == 1160.0)
	var state: Dictionary = w.export_state()
	var inventory: Dictionary = g._engine.inventory.duplicate(true)
	for endpoint in [1160.0, 1100.0]:
		r = s.replay_offline(1000.0, endpoint)
		Selftest.check("offline repeated or backwards clock grants nothing " + str(endpoint), r.get("steps", -1) == 0
			and r.get("ether_gained", -1) == 0 and w.export_state() == state and g._engine.inventory == inventory)
	for frozen in [true, false]:
		g._saves._save_frozen = frozen
		r = s.replay_offline(w.last_simulated_at, w.last_simulated_at + 80.0)
		Selftest.check("offline restores prior save freeze " + str(frozen), g._saves._save_frozen == frozen)
	g._saves._save_frozen = true
	w = Cases.prepare(g, fixture, ["brick"])
	w.last_simulated_at = 1000.0
	w.lines[0]["stage_credit"] = 3
	g._engine.inventory["clay"] = 0
	g._engine.ether = g._engine._pair_cost("earth", "water")
	s = script.new(g, w)
	s.advance(0.0)
	state = w.export_state()
	var xp: int = w.xp
	w.import_state(state)
	s = script.new(g, w)
	g._engine.ether = 100
	r = s.advance(0.0)
	Selftest.check("offline saved midchain uses paid intermediate without repeated debit XP", r.get("steps", -1) == 2
		and r.get("items", -1) == 1 and w.xp == xp + 3 and g._engine.inventory["brick"] == 1)
	w = Cases.prepare(g, fixture)
	w.import_state({"version": 999, "last_simulated_at": 1000.0, "opaque": "preserve"})
	state = w.export_state()
	g._engine.ether = 0
	s = script.new(g, w)
	r = s.replay_offline(900.0, 1080.0)
	Selftest.check("offline future version uses preserved watermark and stays read-only", r.get("steps", -1) == 0
		and r.get("ether_gained", 0) > 0 and w.export_state() == state)
	Selftest.check("offline future same-session repeat cannot duplicate shared regen",
		s.replay_offline(900.0, 1080.0).get("ether_gained", -1) == 0)

static func _stage_boundaries(g: Game, script: Script, fixture) -> void:
	var w = Cases.prepare(g, fixture, ["clay"])
	w.last_simulated_at = 1000.0
	g._engine.inventory["earth"] = 1
	g._engine.inventory["water"] = 1
	g._engine.inventory["brick"] = 0
	g._engine.inventory["clay"] = 0
	g._engine._craft_job = {"item": "brick", "completed": 0, "discount": 1.0}
	# Known clay itself is deliberately inaccessible to the manual planner until
	# the production line supplies it; no earth remains for rebuilding it.
	g._engine.known_recipes.erase(g._pair_key("earth", "water"))
	var s = script.new(g, w)
	var r: Dictionary = s.replay_offline(1000.0, 1080.0)
	Selftest.check("offline unavailable manual recipe never auto-discovers", r.get("craft_steps", -1) == 0
		and g._engine._craft_job.get("status", "") == "paused_recipe" and w.xp == 0)
	w = Cases.prepare(g, fixture, ["steam", "dust"], "batch", 1)
	w.last_simulated_at = 1000.0
	# Each queue finishes two tiny jobs. Its cap counts stages, not jobs.
	w.enqueue("line_1", {"target": "steam", "mode": "batch", "amount": 1})
	w.enqueue("line_2", {"target": "dust", "mode": "batch", "amount": 1})
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1080.0)
	Selftest.check("offline queue completion carries remaining stage across jobs", r.get("items", -1) == 4
		and r["lines"]["line_1"]["stages"] == 1 and r["lines"]["line_2"]["stages"] == 1
		and w.lines[0]["queue"].is_empty() and w.lines[1]["queue"].is_empty())
	w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	w.lines[0]["phase_seconds"] = 39.0
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1060.0)
	Selftest.check("offline carries partial effective phase across endpoint", r.get("steps", -1) == 3
		and is_equal_approx(float(w.lines[0]["phase_seconds"]), 29.0))
	Selftest.check("offline next replay completes saved phase without doubling factor", s.replay_offline(1060.0, 1120.0).get("steps", -1) == 3
		and is_equal_approx(float(w.lines[0]["phase_seconds"]), 19.0))
	Selftest.check("offline event count bounded independently of rendering frames", int(r.get("events", 10000000)) < 1000)
	w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	w.lines.clear()
	g._engine.ether = 0
	g._engine.regen_clock = 0.25
	var rate: float = g._engine._ether_rate()
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1060.0)
	Selftest.check("offline regen uses full existing rate and preserved fraction", r.get("ether_gained", -1) == int(floor(0.25 + 60.0 * rate))
		and is_equal_approx(g._engine.regen_clock, fposmod(0.25 + 60.0 * rate, 1.0)))
	w = Cases.prepare(g, fixture)
	w.last_simulated_at = 1000.0
	g._saves._save_frozen = false
	var seen := {"signals": 0, "all_frozen": true}
	var on_changed := func() -> void:
		seen["signals"] += 1
		seen["all_frozen"] = seen["all_frozen"] and g._saves._save_frozen
	w.changed.connect(on_changed)
	s = script.new(g, w)
	r = s.replay_offline(1000.0, 1080.0)
	w.changed.disconnect(on_changed)
	Selftest.check("offline every changed callback stays save-frozen until replay watermark", seen["signals"] > 0
		and seen["all_frozen"] and not g._saves._save_frozen and w.last_simulated_at == 1080.0)
	g._saves._save_frozen = true
