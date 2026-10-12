extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")
const PATH := "res://game/lab/workshop_scheduler.gd"

class CountingGuild extends Guild:
	var plans := 0
	func _init(game: Game) -> void:
		super(game)
	func _plan_craft(target: String) -> Dictionary:
		plans += 1
		return super(target)

static func run(g: Game) -> void:
	var before := Selftest._total
	var failures := Selftest._fails
	Selftest.check("scheduler module API exists", FileAccess.file_exists(PATH))
	if not FileAccess.file_exists(PATH):
		return
	var script: Script = load(PATH)
	Selftest.check("scheduler module instantiates", script != null and script.can_instantiate())
	if script == null or not script.can_instantiate():
		return
	if g.get("_workshop_scheduler") == null:
		print("SCHEDULER WIRING PENDING: local module tested; controller integration absent")
	var fixture := Fixture.new(g)
	_basic(g, script, fixture)
	_contention(g, script, fixture)
	_waiting(g, script, fixture)
	_routes(g, script, fixture)
	_bounds(g, script, fixture)
	_revalidation(g, script, fixture)
	fixture.finish()
	print("WORKSHOP_SCHEDULER_CHECKS: %d/%d" % [Selftest._total - before - (Selftest._fails - failures), Selftest._total - before])

static func prepare(g: Game, fixture, targets: Array = ["steam"], mode := "batch", amount := 100):
	fixture.prepare_production()
	g._sigil._milestones_claimed = {}
	var w = g._workshop
	w.reset_new_game()
	w.unlocked = true
	w.rank = targets.size() - 1
	w.lines.clear()
	w.scheduler_cursor = 0
	g._engine.mastery_rank = 0
	g._engine.regen_clock = 0.0
	g._pages._spring_clock = 0.0
	for i in targets.size():
		var line: Dictionary = w._new_line("line_%d" % (i + 1))
		w.lines.append(line)
		g._engine.inventory[targets[i]] = 0
		w.enqueue(line["id"], {"target": targets[i], "mode": mode, "amount": amount})
	return w

static func _basic(g: Game, script: Script, fixture) -> void:
	var w = prepare(g, fixture, ["steam", "dust"])
	var s = script.new(g, w)
	var xp: int = w.xp
	var r: Dictionary = s.advance(39.0)
	Selftest.check("scheduler 39 seconds preserves independent unfinished phases", r.get("steps", -1) == 0
		and w.lines[0]["phase_seconds"] == 39.0 and w.lines[1]["phase_seconds"] == 39.0)
	r = s.advance(1.0)
	Selftest.check("scheduler two different lines each work at 40 seconds", r.get("steps", -1) == 6
		and g._engine.inventory["steam"] == 3 and g._engine.inventory["dust"] == 3)
	Selftest.check("scheduler stats count real outputs mastery and contextual ether", r.get("items", -1) == 6
		and r.get("mastery", -1) == 6 and w.xp == xp + 6 and r.get("ether_spent", -1) == 68
		and (r.get("lines", {}) as Dictionary).size() == 2)
	Selftest.check("scheduler zero advance cannot mint another stage", s.advance(0.0).get("steps", -1) == 0)
	w = prepare(g, fixture, ["steam", "dust"])
	w.lines[1]["phase_seconds"] = 20.0
	s = script.new(g, w)
	r = s.advance(20.0)
	Selftest.check("scheduler phases are independent", r.get("steps", -1) == 3
		and g._engine.inventory["steam"] == 0 and g._engine.inventory["dust"] == 3
		and w.lines[0]["phase_seconds"] == 20.0)
	for rank in [3, 7]:
		w = prepare(g, fixture)
		g._engine.mastery_rank = rank
		s = script.new(g, w)
		Selftest.check("scheduler stage follows mastery rank %d" % rank,
			s.advance(40.0).get("steps", -1) == (4 if rank == 3 else 5))

static func _contention(g: Game, script: Script, fixture) -> void:
	var w = prepare(g, fixture, ["steam", "steam"])
	g._engine.inventory["fire"] = 1
	g._engine.inventory["water"] = 1
	var s = script.new(g, w)
	var r: Dictionary = s.advance(40.0)
	Selftest.check("scheduler shared last input is committed once", r.get("steps", -1) == 1
		and g._engine.inventory["steam"] == 1 and g._engine.inventory["fire"] == 0
		and w.lines[0]["queue"][0]["produced"] == 1 and w.lines[1]["queue"][0]["produced"] == 0)
	Selftest.check("scheduler cursor persists next contender after successful debit", w.scheduler_cursor == 1)
	g._engine.inventory["fire"] = 1
	g._engine.inventory["water"] = 1
	r = s.advance(0.0)
	Selftest.check("scheduler next ready line wins replenished last input", r.get("steps", -1) == 1
		and w.lines[1]["queue"][0]["produced"] == 1)
	w = prepare(g, fixture, ["steam", "steam"], "stock", 5)
	w.lines[1]["queue"][0]["amount"] = 10
	s = script.new(g, w)
	r = s.advance(160.0)
	Selftest.check("scheduler same stock targets 5 and 10 produce shared maximum 10", g._engine.inventory["steam"] == 10
		and r.get("items", -1) == 10 and w.lines[0]["queue"].size() == 1 and w.lines[1]["queue"].size() == 1)
	g._engine.inventory["steam"] = 9
	r = s.advance(0.0)
	Selftest.check("scheduler stock consumes retained stage only for missing shared unit", g._engine.inventory["steam"] == 10
		and r.get("items", -1) == 1)

static func _waiting(g: Game, script: Script, fixture) -> void:
	var w = prepare(g, fixture, ["steam", "dust"])
	w.set_line_paused("line_1", true)
	var s = script.new(g, w)
	Selftest.check("scheduler paused line does not block others", s.advance(40.0).get("steps", -1) == 3
		and g._engine.inventory["steam"] == 0 and w.lines[0]["phase_seconds"] == 0.0)
	w.set_line_paused("line_1", false)
	Selftest.check("scheduler unpaused line resumes timer", s.advance(40.0).get("steps", -1) == 6)
	w = prepare(g, fixture, ["steam", "dust"])
	g._engine.known_recipes.erase(g._pair_key("fire", "water"))
	s = script.new(g, w)
	Selftest.check("scheduler waiting recipe does not block working line", s.advance(40.0).get("steps", -1) == 3
		and w.lines[0]["queue"][0]["status"] == "waiting_recipe")
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	Selftest.check("scheduler learned recipe retries retained ready stage", s.advance(0.0).get("steps", -1) == 3)
	w = prepare(g, fixture)
	g._engine.inventory["fire"] = 0
	s = script.new(g, w)
	s.advance(400.0)
	Selftest.check("scheduler starvation retains at most one stage", w.lines[0]["stage_credit"] == 3
		and w.lines[0]["phase_seconds"] == 0.0 and w.lines[0]["queue"][0]["status"] == "waiting_ingredients")
	for i in 3:
		Selftest.check("scheduler unchanged zero retry yields nothing %d" % i, s.advance(0.0).get("steps", -1) == 0)
	g._engine.inventory["fire"] = 100
	Selftest.check("scheduler new resources resume only retained stage", s.advance(0.0).get("steps", -1) == 3)
	Selftest.check("scheduler starvation never banks extra elapsed intervals", s.advance(0.0).get("steps", -1) == 0
		and s.advance(39.0).get("steps", -1) == 0 and s.advance(1.0).get("steps", -1) == 3)
	for gate in ["brewing", "_auto", "bench"]:
		w = prepare(g, fixture)
		s = script.new(g, w)
		if gate == "bench": g._pages._bench_busy = true
		else: g._engine.set(gate, true)
		Selftest.check("scheduler manual priority blocks commits but matures timer " + gate,
			s.advance(40.0).get("steps", -1) == 0 and w.lines[0]["stage_credit"] == 3)
		if gate == "bench": g._pages._bench_busy = false
		else: g._engine.set(gate, false)
		Selftest.check("scheduler freed manual priority resumes ready stage " + gate, s.advance(0.0).get("steps", -1) == 3)

static func _routes(g: Game, script: Script, fixture) -> void:
	var w = prepare(g, fixture, ["brick", "steam"])
	w.lines[0]["queue"][0]["amount"] = 1
	g._engine.inventory["clay"] = 0
	g._engine.inventory["brick"] = 0
	w.enqueue("line_1", {"target": "dust", "mode": "batch", "amount": 1})
	var s = script.new(g, w)
	var r: Dictionary = s.advance(40.0)
	Selftest.check("scheduler queue progresses after own batch target output", w.lines[0]["queue"].is_empty()
		and g._engine.inventory["brick"] == 1 and g._engine.inventory["dust"] == 1 and r.get("items", -1) == 5)
	Selftest.check("scheduler real multi-operation route blueprint exists only after target", g._engine._blueprints.has("brick")
		and int(g._engine._blueprints["brick"]["operations"]) == 2)
	w = prepare(g, fixture, ["brick"])
	g._engine.inventory["clay"] = 0
	g._engine.ether = g._engine._pair_cost("earth", "water")
	# Ready stage at t=0: no regeneration is hidden in this cancellation test.
	w.lines[0]["stage_credit"] = 3
	s = script.new(g, w)
	r = s.advance(0.0)
	Selftest.check("scheduler midchain keeps actual route progress and intermediate", r.get("steps", -1) == 1
		and w.lines[0]["queue"][0]["route_operations"] == 1 and g._engine.inventory["clay"] == 1
		and not g._engine._blueprints.has("brick"))
	w.remove_job("line_1", w.lines[0]["queue"][0]["id"])
	s.advance(0.0)
	Selftest.check("scheduler cancellation retains paid intermediate without XP replay", g._engine.inventory["clay"] == 1 and w.xp == 1)
	w = prepare(g, fixture)
	w.lines[0]["stage_credit"] = 5
	g._engine.mastery_rank = 0
	s = script.new(g, w)
	Selftest.check("scheduler revalidates stage size after equipment change", s.advance(0.0).get("steps", -1) == 3)

static func _bounds(g: Game, script: Script, fixture) -> void:
	var w = prepare(g, fixture)
	var s = script.new(g, w)
	var state: Dictionary = w.export_state()
	for delta in [-1.0, NAN, INF]:
		Selftest.check("scheduler invalid delta has no mutations " + str(delta), s.advance(delta).get("steps", -1) == 0
			and w.export_state() == state)
	w.lines[0]["phase_seconds"] = INF
	Selftest.check("scheduler corrupt phase cannot create unlimited stages", s.advance(1.0).get("steps", -1) == 0
		and is_finite(float(w.lines[0]["phase_seconds"])))
	w = prepare(g, fixture)
	w.unlocked = false
	g._engine.ether = 0
	state = w.export_state()
	s = script.new(g, w)
	var r: Dictionary = s.advance(10.0)
	Selftest.check("scheduler locked workshop leaves lines and XP while regenerating", w.export_state() == state
		and r.get("steps", -1) == 0 and r.get("ether_gained", 0) > 0)
	w = prepare(g, fixture)
	w.import_state({"version": 999, "lines": [{"opaque": true}], "last_simulated_at": 1000.0})
	state = w.export_state()
	g._engine.ether = 0
	s = script.new(g, w)
	r = s.advance(10.0)
	Selftest.check("scheduler future workshop remains byte-equivalent while regenerating", w.export_state() == state
		and r.get("steps", -1) == 0 and r.get("ether_gained", 0) > 0)

static func _revalidation(g: Game, script: Script, fixture) -> void:
	var w = prepare(g, fixture, ["steam"], "stock", 3)
	var s = script.new(g, w)
	s.advance(40.0)
	Selftest.check("scheduler stock status waits immediately at exact stage output", w.lines[0]["queue"][0]["status"] == "waiting_inventory")
	Selftest.check("scheduler route progress resets only after actual target output", w.lines[0]["queue"][0]["route_operations"] == 0
		and g._engine._blueprints["steam"]["operations"] == 1)
	w = prepare(g, fixture, ["steam", "steam"], "batch", 2)
	g._engine.inventory["steam"] = 50
	s = script.new(g, w)
	var r: Dictionary = s.advance(40.0)
	Selftest.check("scheduler two batches count only own outputs even with existing shared stock", r.get("items", -1) == 4
		and g._engine.inventory["steam"] == 54 and w.lines[0]["queue"].is_empty() and w.lines[1]["queue"].is_empty())
	w = prepare(g, fixture)
	g._engine.inventory["steam"] = Game.CRAFT_INVENTORY_STACK_CAP
	s = script.new(g, w)
	r = s.advance(40.0)
	Selftest.check("scheduler shared global stack cap refuses debit and XP", r.get("steps", -1) == 0 and w.xp == 0
		and g._engine.inventory["fire"] == 100 and w.lines[0]["queue"][0]["status"] == "waiting_inventory")
	g._engine.inventory["steam"] -= 1
	Selftest.check("scheduler inventory consumption resumes one ready operation", s.advance(0.0).get("steps", -1) == 1
		and g._engine.inventory["steam"] == Game.CRAFT_INVENTORY_STACK_CAP)
	w = prepare(g, fixture, ["brick", "steam"])
	g._sigil._milestones_claimed = {}
	s = script.new(g, w)
	s.advance(20.0)
	g._sigil._milestones_claimed = {"earth": [13]}
	r = s.advance(0.0)
	Selftest.check("scheduler sigil category speed change revalidates existing phase", r.get("steps", -1) == 3
		and g._engine.inventory["brick"] == 1 and g._engine.inventory["steam"] == 0)
	Selftest.check("scheduler category speed keeps other line phase", w.lines[1]["phase_seconds"] == 20.0)
	w = prepare(g, fixture, ["brick"])
	g._engine.inventory["clay"] = 0
	g._engine.known_recipes.erase(g._pair_key("earth", "water"))
	s = script.new(g, w)
	r = s.advance(40.0)
	Selftest.check("scheduler unknown dependency stays recipe waiting without debit", r.get("steps", -1) == 0
		and w.lines[0]["queue"][0]["status"] == "waiting_recipe" and w.xp == 0)
	g._engine.known_recipes[g._pair_key("earth", "water")] = true
	Selftest.check("scheduler learned dependency resumes ready route", s.advance(0.0).get("steps", -1) == 3)
	w = prepare(g, fixture)
	g._engine.inventory["fire"] = 0
	g._engine.ether = g._engine._max_ether()
	var original := g._guild
	var probe := CountingGuild.new(g)
	g._guild = probe
	s = script.new(g, w)
	s.advance(40.0)
	# The first changed-resource signature is settled before measuring frames.
	s.advance(0.0)
	var calls := probe.plans
	for i in 10: s.advance(0.01)
	Selftest.check("scheduler blocked resource signature avoids planner calls each frame", probe.plans == calls)
	g._engine.inventory["fire"] = 100
	Selftest.check("scheduler real inventory signature change retries planner", s.advance(0.0).get("steps", -1) == 3 and probe.plans > calls)
	g._guild = original
