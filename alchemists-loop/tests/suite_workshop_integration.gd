extends RefCounted
const Fixture = preload("res://tests/workshop_fixture.gd")

static func run(g: Game) -> void:
	Selftest.check("integration scheduler wired to real Game", g.get("_workshop_scheduler") != null)
	if g.get("_workshop_scheduler") == null:
		return
	var fixture := Fixture.new(g)
	fixture.capture(g.get("_workshop_scheduler"))
	fixture.prepare_production()
	var w: Workshop = g._workshop
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 100})
	for item in ["steam", "dust"]:
		g._engine.inventory[item] = 0
	w.enqueue(w.lines[0]["id"], {"target": "steam", "mode": "batch", "amount": 3})
	w.enqueue(w.lines[1]["id"], {"target": "dust", "mode": "batch", "amount": 3})
	g._process(40.0)
	Selftest.check("integration process runs two lines once", g._engine.inventory["steam"] == 3
		and g._engine.inventory["dust"] == 3 and w.xp == 106)
	Selftest.check("integration process clears completed batches", w.lines[0]["queue"].is_empty()
		and w.lines[1]["queue"].is_empty())
	# Persist fractions in the same snapshot as inventory, equipment and watermark.
	g._engine.regen_clock = 0.375
	g._pages._spring_clock = 2.25
	g._saves._save_frozen = false
	g._saves._save_game()
	g._saves._save_frozen = true
	var saved := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("integration save persists shared timer fractions", saved.get("regen_clock", -1) == 0.375
		and saved.get("spring_clock", -1) == 2.25)
	g._engine.regen_clock = 0.0
	g._pages._spring_clock = 0.0
	g._saves._load_game()
	Selftest.check("integration load restores shared timer fractions", g._engine.regen_clock == 0.375
		and g._pages._spring_clock == 2.25)
	# Actual save orchestrator uses one replay for every consumer.
	fixture.prepare_production()
	w.import_state({"version": 1, "unlocked": true, "rank": 1, "xp": 100})
	g._engine.inventory["steam"] = 0
	g._engine.inventory["dust"] = 0
	w.enqueue(w.lines[0]["id"], {"target": "steam", "mode": "batch", "amount": 6})
	w.enqueue(w.lines[1]["id"], {"target": "dust", "mode": "batch", "amount": 6})
	var now := Time.get_unix_time_from_system()
	g._last_ts = now - 160.1
	w.last_simulated_at = g._last_ts
	g._selftest = false
	g._saves._grant_offline()
	g._selftest = true
	Selftest.check("integration return replay produces multiple stages on both lines", g._engine.inventory["steam"] == 6
		and g._engine.inventory["dust"] == 6 and w.xp == 112)
	var summary: Variant = g._saves.get("_return_workshop")
	Selftest.check("integration return stores real per-line output and mastery", summary is Dictionary
		and summary.get("mastery", -1) == 12 and summary.get("lines", {}).size() == 2)
	var before := g._engine.inventory.duplicate(true)
	var xp := w.xp
	g._selftest = false
	g._saves._grant_offline()
	g._selftest = true
	Selftest.check("integration repeated return cannot replay resources", g._engine.inventory == before and w.xp == xp)
	g._engine.inventory["person"] = 0
	g._pages._ensure_modes()
	var bench: Node = g._pages._mode_pages.get("bench")
	Selftest.check("integration production page contains real WorkshopView", is_instance_valid(bench)
		and bench.find_child("WorkshopView", true, false) != null)
	# Permanent equipment also keeps the production entry point after prestige.
	g._engine.inventory.erase("person")
	Selftest.check("integration permanent unlock survives missing Person", g._engine._mode_unlocked("bench"))
	fixture.finish()
