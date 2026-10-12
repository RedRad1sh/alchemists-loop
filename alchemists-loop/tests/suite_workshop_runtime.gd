extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")

static func run(g: Game) -> void:
	var before := Selftest._total
	var failures := Selftest._fails
	var fixture := Fixture.new(g)
	fixture.capture(g._workshop_scheduler)
	g.SAVE_PATH = "user://alchemy_st_workshop_runtime.json"
	g.TEMP_PATH = "user://alchemy_st_workshop_runtime.tmp"
	g.BACKUP_PATH = "user://alchemy_st_workshop_runtime.bak"
	_wipe(g)
	_freed_floater(g, fixture)
	_same_world(g, fixture)
	_new_world(g, fixture)
	_prestige_world(g, fixture)
	_reentrant_reset(g, fixture, "new_game")
	_reentrant_reset(g, fixture, "prestige")
	_wipe(g)
	fixture.finish()
	print("WORKSHOP_RUNTIME_CHECKS: %d/%d" % [Selftest._total - before - (Selftest._fails - failures), Selftest._total - before])

static func _freed_floater(g: Game, fixture) -> void:
	fixture.prepare_production()
	var first := Label.new()
	var freed := Label.new()
	var last := Label.new()
	g.add_child(first)
	g.add_child(freed)
	g.add_child(last)
	first.position.y = 100.0
	last.position.y = 200.0
	g.floaters = [{"l": first, "t": 0.0, "life": 2.0},
		{"l": freed, "t": 0.0, "life": 2.0}, {"l": last, "t": 0.0, "life": 2.0}]
	# A restored fixture can retain this Object after its Label has been freed.
	freed.free()
	g._process(0.125)
	Selftest.check("runtime process removes previously freed floater", g.floaters.size() == 2
		and g.floaters[0]["l"] == first and g.floaters[1]["l"] == last)
	Selftest.check("runtime process continues past freed floater without abort", first.position.y == 93.5
		and last.position.y == 193.5 and g.floaters[0]["t"] == 0.125 and g.floaters[-1]["t"] == 0.125)
	g.floaters.clear()
	first.free()
	last.free()

static func _prepare_world(g: Game, fixture) -> float:
	fixture.prepare_production()
	for item in g.ITEMS:
		if g._engine.inventory.size() >= Game.PRESTIGE_MIN + 5:
			break
		g._engine.inventory[item] = 5
	g._engine.inventory["steam"] = 0
	g._engine.mastery_rank = 7
	g._engine.ether_overflow = 123
	g._engine.regen_clock = 0.875
	g._engine.autosave_clock = 9.0
	g._engine._gift_clock = 119.0
	g._pages._spring_clock = 5.25
	g._pages._bench_clock = 9.0
	var future := Time.get_unix_time_from_system() + 31536000.0
	g._last_ts = future
	var w: Workshop = g._workshop
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 400,
		"autonomy_level": 1, "last_simulated_at": future})
	w.enqueue(w.lines[0]["id"], {"target": "steam", "mode": "batch", "amount": 6})
	w.lines[0]["phase_seconds"] = 9.0
	w.lines[1]["stage_credit"] = 2
	w.scheduler_cursor = 1
	return future

static func _save(g: Game) -> Dictionary:
	g._saves._save_frozen = false
	var ok := g._saves._save_game()
	g._saves._save_frozen = true
	Selftest.check("runtime actual world snapshot writes successfully", ok)
	return g._saves._read_save(g.SAVE_PATH)

static func _same_world(g: Game, fixture) -> void:
	var future := _prepare_world(g, fixture)
	g._process(0.0)
	var saved := _save(g)
	Selftest.check("runtime ordinary process and save retain future monotone world stamp",
		g._last_ts == future and g._workshop.last_simulated_at == future
		and saved.get("last_ts") == future and saved.get("workshop", {}).get("last_simulated_at") == future)
	Selftest.check("runtime ordinary process retains fractional resource phases",
		g._engine.regen_clock == 0.875 and g._pages._spring_clock == 5.25)

static func _new_world(g: Game, fixture) -> void:
	var future := _prepare_world(g, fixture)
	var earliest := Time.get_unix_time_from_system()
	var seen := {"calls": 0, "fresh": true}
	var on_reset := func() -> void:
		seen["calls"] += 1
		seen["fresh"] = seen["fresh"] and g._last_ts >= earliest and g._last_ts < future \
			and g._engine.regen_clock == 0.0 and g._pages._spring_clock == 0.0
	g._workshop.changed.connect(on_reset)
	var reset := g._init_new_game()
	g._workshop.changed.disconnect(on_reset)
	Selftest.check("runtime explicit new game rebases far future world time", reset
		and g._last_ts >= earliest and g._last_ts <= Time.get_unix_time_from_system()
		and g._workshop.last_simulated_at >= earliest and g._workshop.last_simulated_at < future)
	Selftest.check("runtime new game resets resource and world phases", g._engine.regen_clock == 0.0
		and g._pages._spring_clock == 0.0 and g._pages._bench_clock == 0.0
		and g._engine._gift_clock == 0.0 and g._engine.autosave_clock == 0.0)
	Selftest.check("runtime new game reset callback sees fresh shared world clocks", seen["calls"] == 1 and seen["fresh"])
	Selftest.check("runtime new game clears permanent equipment and old queue", not g._workshop.unlocked
		and g._workshop.rank == 0 and g._workshop.xp == 0 and g._workshop.autonomy_level == 0
		and _empty_phases(g._workshop) and g._engine.mastery_rank == 0)
	var saved := _save(g)
	Selftest.check("runtime new game durable stamp cannot preserve previous future world", saved.get("last_ts", future) < future
		and saved.get("last_ts", 0.0) >= earliest
		and saved.get("workshop", {}).get("last_simulated_at") == saved.get("last_ts"))

static func _prestige_world(g: Game, fixture) -> void:
	var future := _prepare_world(g, fixture)
	var earliest := Time.get_unix_time_from_system()
	var gold := g._engine.sage_gold
	var gain := g._hub._prestige_gain()
	var seen := {"calls": 0, "fresh": true}
	var on_reset := func() -> void:
		seen["calls"] += 1
		seen["fresh"] = seen["fresh"] and g._last_ts >= earliest and g._last_ts < future \
			and g._engine.regen_clock == 0.0 and g._pages._spring_clock == 0.0
	g._workshop.changed.connect(on_reset)
	g._hub._do_prestige()
	g._workshop.changed.disconnect(on_reset)
	Selftest.check("runtime prestige rebases far future world time", gain > 0
		and g._engine.sage_gold == gold + gain and g._last_ts >= earliest
		and g._last_ts <= Time.get_unix_time_from_system() and g._workshop.last_simulated_at >= earliest
		and g._workshop.last_simulated_at < future)
	Selftest.check("runtime prestige resets resource and world phases", g._engine.regen_clock == 0.0
		and g._pages._spring_clock == 0.0 and g._pages._bench_clock == 0.0
		and g._engine._gift_clock == 0.0 and g._engine.autosave_clock == 0.0 and _empty_phases(g._workshop))
	Selftest.check("runtime prestige reset callback sees fresh shared world clocks", seen["calls"] == 1 and seen["fresh"])
	Selftest.check("runtime prestige retains mastery equipment autonomy reserve and ArchiveSeal",
		g._workshop.unlocked and g._workshop.rank == 1 and g._workshop.xp == 400
		and g._workshop.autonomy_level == 1 and g._engine.mastery_rank == 7 and g._engine.ether_overflow == 123)
	var saved := _save(g)
	Selftest.check("runtime prestige durable stamp cannot preserve previous future world", saved.get("last_ts", future) < future
		and saved.get("last_ts", 0.0) >= earliest
		and saved.get("workshop", {}).get("last_simulated_at") == saved.get("last_ts"))

static func _empty_phases(w: Workshop) -> bool:
	if w.scheduler_cursor != 0:
		return false
	for line in w.lines:
		if not line["queue"].is_empty() or line["phase_seconds"] != 0.0 or line["stage_credit"] != 0:
			return false
	return true

static func _world_snapshot(g: Game) -> Dictionary:
	return {"inventory": g._engine.inventory.duplicate(true), "recipes": g._engine.known_recipes.duplicate(true),
		"ether": g._engine.ether, "reserve": g._engine.ether_overflow, "seal": g._engine.mastery_rank,
		"gold": g._engine.sage_gold, "epoch": g._engine.brew_epoch, "last_ts": g._last_ts,
		"regen": g._engine.regen_clock, "spring": g._pages._spring_clock,
		"workshop": g._workshop.export_state().duplicate(true)}

static func _reentrant_reset(g: Game, fixture, action: String) -> void:
	_prepare_world(g, fixture)
	var observed := {"calls": 0, "guard": false, "unchanged": false, "new_game": true}
	# Real synthesis emits changed synchronously while Core still owns its short
	# resource commit guard. Attempting a reset must not replace that world.
	var on_synthesis := func() -> void:
		if observed["calls"] != 0:
			return
		observed["calls"] += 1
		observed["guard"] = not g._engine._resource_mutation_allowed()
		var before := _world_snapshot(g)
		if action == "new_game":
			observed["new_game"] = g._init_new_game()
		else:
			g._hub._do_prestige()
		observed["unchanged"] = _world_snapshot(g) == before
	g._workshop.changed.connect(on_synthesis)
	var ether := g._engine.ether
	var fire := int(g._engine.inventory["fire"])
	var water := int(g._engine.inventory["water"])
	var xp := g._workshop.xp
	var result := g._engine._commit_brew("fire", "water", {"source": "workshop", "production": true, "discount": 1.0})
	g._workshop.changed.disconnect(on_synthesis)
	Selftest.check("runtime " + action + " callback runs inside actual resource transaction", observed["calls"] == 1 and observed["guard"])
	Selftest.check("runtime " + action + " callback cannot replace committing world", observed["unchanged"]
		and (action != "new_game" or observed["new_game"] == false))
	Selftest.check("runtime " + action + " rejection lets original transaction commit exactly once", not result.get("failed", true)
		and result.get("ether_spent") == Game.BREW_COST and g._engine.ether == ether - Game.BREW_COST
		and g._engine.inventory["fire"] == fire - 1 and g._engine.inventory["water"] == water - 1
		and g._engine.inventory["steam"] == 1 and g._workshop.xp == xp + 1 and g._engine._resource_mutation_allowed())
	var epoch := g._engine.brew_epoch
	if action == "new_game":
		Selftest.check("runtime new game allowed after callback guard releases", g._init_new_game() and g._engine.brew_epoch == epoch + 1)
	else:
		g._hub._do_prestige()
		Selftest.check("runtime prestige allowed after callback guard releases", g._engine.brew_epoch == epoch + 1 and _empty_phases(g._workshop))
	var failed := g._engine._commit_brew("fire", "fire", {"source": "workshop", "production": true, "discount": 1.0})
	Selftest.check("runtime " + action + " guard also releases after rejected transaction", failed.get("failed", false)
		and g._engine._resource_mutation_allowed() and g._init_new_game())

static func _wipe(g: Game) -> void:
	for path in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
