extends RefCounted
class_name SuiteCoreBrew
# граф/орбы/варки/автварка (оп B1).

static func run(g: Game) -> void:
	# граф: достижимость всех веществ из стихий + монотонность слоёв
	var layers := {"fire": 0, "water": 0, "earth": 0, "air": 0}
	var changed := true
	var guard := 0
	while changed and guard < 200:
		changed = false
		guard += 1
		for r in g.RECIPES:
			var a := String(r["a"]); var b := String(r["b"]); var o := String(r["out"])
			var l := maxi(int(layers.get(a, 99)), int(layers.get(b, 99))) + 1
			if l < int(layers.get(o, 99)):
				layers[o] = l
				changed = true
	Selftest.check("graph layers settle", guard < 200)
	var mono := true
	for r in g.RECIPES:
		if int(layers.get(String(r["out"]), 99)) <= int(layers.get(String(r["a"]), 99)) \
				or int(layers.get(String(r["out"]), 99)) <= int(layers.get(String(r["b"]), 99)):
			mono = false
	Selftest.check("graph monotonic layers", mono)
	var reachable := {"fire": true, "water": true, "earth": true, "air": true}
	var rc := true
	while rc:
		rc = false
		for r in g.RECIPES:
			var o := String(r["out"])
			if not reachable.has(o) and reachable.has(String(r["a"])) and reachable.has(String(r["b"])):
				reachable[o] = true
				rc = true
	Selftest.check("graph reachable all", reachable.size() == g.ITEMS.size())
	# циклы в известных рецептах (серверный контент) не должны вешать _layer_of
	g.RECIPES.append({"a": "cyc_a", "b": "fire", "out": "cyc_b"})
	g.RECIPES.append({"a": "cyc_b", "b": "fire", "out": "cyc_a"})
	g._engine.known_recipes[g._pair_key("cyc_a", "fire")] = true
	g._engine.known_recipes[g._pair_key("cyc_b", "fire")] = true
	Selftest.check("layer cycle safe", g._engine._layer_of("cyc_a") >= (1 << 29) and g._engine._layer_of("cyc_b") >= (1 << 29))
	Selftest.check("layer cycle uncached", not g._engine._layer_cache.has("cyc_a") and not g._engine._layer_cache.has("cyc_b"))
	g.RECIPES.pop_back()
	g.RECIPES.pop_back()
	g._engine.known_recipes.erase(g._pair_key("cyc_a", "fire"))
	g._engine.known_recipes.erase(g._pair_key("cyc_b", "fire"))

	g._init_new_game()
	Selftest.check("new game bases", int(g._engine.inventory.get("fire", 0)) == 5 and g._engine.inventory.size() == 4)
	Selftest.check("new game known", g._engine.known_recipes.size() == 2)

	# орбы-источники и ячейки
	Selftest.check("source orbs 4", g._engine._source_orbs.size() == 4)
	Selftest.check("item orbs 57", g._engine._item_orbs.size() == 57)
	Selftest.check("slots exist", g._engine._slot_a != null and g._engine._slot_b != null)
	Selftest.check("brew disabled no pair", g._engine._can_brew() == false)

	# размещение в лунки + проверка selected
	g._engine.selected.clear()
	Selftest.check("place A", g._engine._place_into_slot("fire", "A") and g._engine.selected == ["fire"])
	Selftest.check("place B", g._engine._place_into_slot("water", "B") and g._engine.selected == ["fire", "water"])
	Selftest.check("discovery surcharge quoted", g._engine._pair_cost("fire", "water") == Game.BREW_COST + 4)
	Selftest.check("can brew now", g._engine._can_brew())

	# варка
	g.BREW_SECONDS = 0.05
	g._engine.inventory["fire"] = 5
	g._engine.inventory["water"] = 5
	g._engine.ether = 100
	var e0 := g._engine.ether
	await g._engine._brew()
	Selftest.check("brew steam", int(g._engine.inventory.get("steam", 0)) == 1 and g._engine.successes == 1)
	Selftest.check("brew cost", g._engine.ether <= e0 - Game.BREW_COST + 1)
	Selftest.check("known recipe loses surcharge", g._engine._pair_cost("fire", "water") == Game.BREW_COST)

	# неудача + возврат
	g._engine.inventory["fire"] = 3
	g._engine.selected = ["fire", "fire"]
	var e1 := g._engine.ether
	await g._engine._brew()
	Selftest.check("fail refund", g._engine.successes == 1 and g._engine.ether >= e1 - Game.BREW_COST + Game.FAILURE_REFUND - 1)

	# overflow is visible and spendable instead of being silently clipped at cap
	var overflow_ether := g._engine.ether
	var overflow_rank := g._engine.mastery_rank
	g._engine.ether = g._engine._max_ether()
	g._engine.ether_overflow = 0
	g._engine._grant_ether(50, "selftest")
	Selftest.check("overflow reserve", g._engine.ether == g._engine._max_ether() and g._engine.ether_overflow == 50)
	Selftest.check("overflow can fund brew", g._engine._spend_ether(20) and g._engine.ether_overflow == 50)
	g._engine.ether = 0
	g._engine.ether_overflow = Game.ETHER_MASTERY_BASE
	g._engine.mastery_rank = 0
	Selftest.check("mastery consumes reserve", g._engine._buy_mastery() and g._engine.mastery_rank == 1 and g._engine.ether_overflow == 0)
	g._engine.ether = overflow_ether
	g._engine.ether_overflow = 0
	g._engine.mastery_rank = overflow_rank

	# автоварка: планировщик цепочки
	g._engine.inventory["steam"] = 0  # убрать остатки прошлых варок
	var p_steam := g._guild._plan_craft("steam")
	Selftest.check("plan steam ok", bool(p_steam.get("ok", false)) and int(p_steam.get("total", 0)) == 1)
	var p_stone := g._guild._plan_craft("stone")
	Selftest.check("plan stone ok", bool(p_stone.get("ok", false)))
	var p_brick := g._guild._plan_craft("brick")
	Selftest.check("plan brick blocked", not bool(p_brick.get("ok", false)))  # рецепт глины ещё закрыт
	g._engine.known_recipes[g._pair_key("earth", "water")] = true
	g._engine.known_recipes[g._pair_key("clay", "fire")] = true
	var p_chain := g._guild._plan_craft("brick")
	Selftest.check("plan brick chain 2 ops", bool(p_chain.get("ok", false))
		and int(p_chain.get("total", 0)) == 2
		and p_chain["ops"].size() == 2)
	# исполнение цепочки: глина → кирпич (2 варки)
	g._engine.inventory["earth"] = 5
	g._engine.inventory["water"] = 5
	g._engine.inventory["fire"] = 5
	g._engine.ether = 100
	var chain_cost := g._engine._plan_ether_cost(p_chain)
	var ok_run: bool = await g._engine._run_auto_plan("brick", p_chain)
	Selftest.check("autocraft brick", ok_run and int(g._engine.inventory.get("brick", 0)) == 1
		and int(g._engine.inventory.get("clay", 0)) == 0 and int(g._engine.inventory.get("fire", 0)) == 4)
	Selftest.check("autocraft ether", g._engine.ether >= 100 - chain_cost and g._engine.ether <= 100 - chain_cost + 3)
	Selftest.check("autocraft stats", g._engine.attempts == 4 and g._engine.successes == 3)
	Selftest.check("blueprint after full route", g._engine._blueprints.has("brick")
		and float(g._engine._blueprints["brick"].get("discount", 1.0)) == Game.BLUEPRINT_DISCOUNT)

	# Длинный production не требует оплатить весь маршрут одним капом: этап
	# сохраняется после трёх операций и может быть продолжен позднее.
	var stage_inv := g._engine.inventory.duplicate(true)
	var stage_known := g._engine.known_recipes.duplicate(true)
	var stage_ether := g._engine.ether
	var stage_job := g._engine._craft_job.duplicate(true)
	var stage_blueprints := g._engine._blueprints.duplicate(true)
	g._engine.inventory.clear()
	for base in Game.BASE_IDS:
		g._engine.inventory[base] = 100
	g._engine.known_recipes.clear()
	for raw_recipe in g.RECIPES:
		var rr: Dictionary = raw_recipe
		g._engine.known_recipes[g._pair_key(String(rr["a"]), String(rr["b"]))] = true
	g._engine.ether = 1000
	g.BREW_SECONDS = 0.01
	var p_house := g._guild._plan_craft("house")
	var staged := await g._engine._run_auto_plan("house", p_house)
	Selftest.check("craft job pauses by stage", staged and not g._engine._craft_job.is_empty()
		and int(g._engine._craft_job.get("completed", 0)) == Game.CRAFT_STAGE_OPERATIONS)
	g._engine._craft_job = {
		"item": "house", "completed": 0, "total_estimate": int(p_house.get("total", 0)),
		"plan": p_house.duplicate(true), "discount": 1.0, "status": "paused_stage",
	}
	var offline_stage := g._saves._advance_craft_job_offline(3600.0)
	Selftest.check("offline craft stage", int(offline_stage.get("steps", 0)) == Game.CRAFT_STAGE_OPERATIONS
		and String(offline_stage.get("status", "")) == "operation_cap"
		and int(g._engine._craft_job.get("completed", 0)) == Game.CRAFT_STAGE_OPERATIONS)
	var saved_stack := int(g._engine.inventory.get("steam", 0))
	g._engine.inventory["steam"] = Game.CRAFT_INVENTORY_STACK_CAP
	Selftest.check("inventory pause reason", g._engine._production_pair_block("fire", "water") == "inventory")
	g._engine.inventory["steam"] = saved_stack
	g._engine.inventory = stage_inv
	g._engine.known_recipes = stage_known
	g._engine.ether = stage_ether
	g._engine._craft_job = stage_job
	g._engine._blueprints = stage_blueprints
	g._engine._production_discount = 1.0
	g.BREW_SECONDS = 0.05

	# нехватка базы: план отклоняется с понятной причиной
	g._engine.inventory["water"] = 0
	g._engine.inventory["steam"] = 0
	var p_short := g._guild._plan_craft("steam")
	Selftest.check("plan shortage", not bool(p_short.get("ok", false))
		and String(p_short.get("reason", "")).contains("добудь"))
	g._engine.inventory["water"] = 5

	# roundtrip, including a resumable job and its blueprint registry
	g._engine._craft_job = {"item": "house", "completed": 2, "total_estimate": 10,
		"plan": {"ops": [], "total": 10}, "discount": 1.0, "status": "paused_ether"}
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._engine._blueprints["house"] = {"version": 1, "item": "house", "operations": 10,
		"plan": {"ops": [], "total": 10}, "discount": Game.BLUEPRINT_DISCOUNT}
	g._saves._save_game()
	var s_before := int(g._engine.inventory.get("steam", 0))
	var k_before := g._engine.known_recipes.size()
	g._init_new_game()
	g._saves._load_game()
	Selftest.check("save roundtrip", int(g._engine.inventory.get("steam", 0)) == s_before
		and g._engine.known_recipes.size() >= k_before)
	Selftest.check("craft persistence", int(g._engine._craft_job.get("completed", -1)) == 2
		and g._engine._blueprints.has("house"))
	Selftest.check("experiment pending persistence", g._engine._experiment_pending_pair == ["fire", "water"])
	g._engine._craft_job.clear()
	g._engine._experiment_pending_pair.clear()
	var migration_path := "user://craft_v2_migration_test.json"
	var migration_file := FileAccess.open(migration_path, FileAccess.WRITE)
	migration_file.store_string(JSON.stringify({"version": 2, "inventory": {"fire": 1}, "known_recipes": []}))
	migration_file.close()
	var migrated := g._saves._read_save(migration_path)
	Selftest.check("save migration defaults", int(migrated.get("version", 0)) == Game.SAVE_VERSION
		and not migrated.has("craft_job") and not migrated.has("blueprints"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(migration_path))

	# серверные открытия переживают перезагрузку: после save/load видны без фетча мира
	g._online._apply_server_element({"slug": "sv_el", "name": "Серверное", "color": "#335566",
		"glyph": "fire", "d": "Лор", "layer": 2})
	g._online._register_server_recipe("sv_a", "sv_b", "sv_el")
	g._saves._save_game()
	g._init_new_game()
	g._saves._load_game()
	Selftest.check("server persist el", g.ITEMS.has("sv_el")
		and String(g.ITEMS["sv_el"]["name"]) == "Серверное")
	Selftest.check("server persist recipe", not g._online._find_recipe("sv_a", "sv_b").is_empty())
	g._online._restore_server_elements({})
	g._online._restore_server_recipes([])
