extends RefCounted

class WatermarkBypass extends WorkshopScheduler:
	func replay_offline(from_ts: float, to_ts: float) -> Dictionary:
		return advance(to_ts - from_ts, true)

class EarlyRetort extends Retort:
	func _retort_ready(slot: int, _when: float = -1.0) -> bool:
		return _retort_busy(slot)

class PrestigeLoss extends Hub:
	func _do_prestige() -> void:
		super._do_prestige()
		g._workshop.xp = 0

static func apply(game: Game, name: String) -> bool:
	match name:
		"missing_recipe":
			game.RECIPES = game.RECIPES.filter(func(r): return r.out != "steam")
		"lower_ether_source":
			var overrides: Dictionary = game.balance.metadata().resolved_overrides
			overrides["ether.base_regen"] = 0.0
			game.balance = BalanceConfig.resolve(overrides, "mutation-no-ether")
		"watermark_bypass":
			game._workshop_scheduler = WatermarkBypass.new(game, game._workshop)
		"early_retort_collection":
			game._retort = EarlyRetort.new(game)
		"skipped_sigil_result":
			game.set_meta("progression_sigil_mode", "pending")
		"prestige_keep_loss":
			game._hub = PrestigeLoss.new(game)
		_:
			return false
	return true

static func run(game: Game) -> Dictionary:
	var results := {}
	var recipes := game.RECIPES.duplicate(true)
	game.RECIPES = game.RECIPES.filter(func(r): return r.out != "steam")
	var missing := ProgressionRunner.new(game)
	var unreachable := missing.run_phases({"steam": true}, 1)
	results["missing_recipe"] = unreachable.verdict == "fail" and unreachable.phases.discovery.reason == "graph_no_reachable_frontier"
	game.RECIPES = recipes

	game.balance = BalanceConfig.resolve({"ether.base_regen": 0.0}, "no-ether")
	game._engine.ether = 0
	game._engine.ether_overflow = 0
	var starved := ProgressionRunner.new(game, 1, game.balance)
	results["lower_ether_source"] = not ProgressionStrategy.wait_ether(game, 12, starved.clock) and ProgressionStrategy.last_reason == "ether_no_regeneration"
	game.balance = BalanceConfig.baseline()

	var scheduler := game._workshop_scheduler
	game._workshop_scheduler = WatermarkBypass.new(game, game._workshop)
	var replay := ProgressionRunner.new(game)
	replay.clock.set_virtual_epoch(1794614400.0)
	game._engine.ether = 0
	results["watermark_bypass"] = not replay._replay_check()
	game._workshop_scheduler = scheduler

	var retort := game._retort
	game._retort = EarlyRetort.new(game)
	game._engine.inventory["fire"] = 1
	var early_runner := ProgressionRunner.new(game)
	early_runner.clock.set_virtual_epoch(1794614400.0)
	results["early_retort_collection"] = not early_runner._ensure_essence("fire-0", 1)
	game._retort = retort

	var fixture: RefCounted = load("res://tests/progression_sigil_fixture.gd").new()
	fixture.install(game)
	fixture.mode = "pending"
	game._engine.inventory = {"fire": 20, "water": 20, "earth": 20, "air": 20}
	game._engine.ether = 180
	var pending := ProgressionRunner.new(game)
	var crafted := pending.craft_available_sigils()
	results["skipped_sigil_result"] = crafted == 0 and not game._sigil_ui._sigil_pending_craft.is_empty() and game._sigil.copies_of(fixture.crafts[0].card_id) == 0
	game._sigil_ui._on_sigil_craft_failed("mutation_cleanup")
	fixture.manager.transport = Callable()

	var hub := game._hub
	game._hub = PrestigeLoss.new(game)
	game._engine.inventory.clear()
	for id in game.ITEMS.keys().slice(0, 40):
		game._engine.inventory[id] = 1
	game._workshop.xp = 100
	var prestige := ProgressionRunner.new(game)
	prestige.clock.set_virtual_epoch(1794614400.0)
	results["prestige_keep_loss"] = not prestige._prestige_cycle() and not prestige.prestige_proof
	game._hub = hub
	return results
