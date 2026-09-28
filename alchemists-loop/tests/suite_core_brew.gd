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
	# Каждый предмет инвентаря обязан иметь ячейку-орб (e248b61: cells создаются
	# только для известных игроку веществ).
	# MUTATION: убрать _add_lab_reagent_cell для нового предмета — краснеет.
	var orbs_cover := true
	for raw_id in g._engine.inventory:
		if not g._engine._item_orbs.has(String(raw_id)):
			orbs_cover = false
	Selftest.check("item orbs cover inventory", orbs_cover)
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
	var lv0 := g._spirit._companion_level
	await g._engine._brew()
	# Level-up during brew grants 20*lv each step (spirit.gd); the assertion is
	# about the brew CHARGE, so subtract those grants back out.
	var lv_grant := 0
	for k in range(lv0 + 1, g._spirit._companion_level + 1):
		lv_grant += 20 * k
	Selftest.check("brew steam", int(g._engine.inventory.get("steam", 0)) == 1 and g._engine.successes == 1)
	Selftest.check("brew cost", g._engine.ether - lv_grant <= e0 - Game.BREW_COST + 1)
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

	# ============ U31 (A2): ранг печати удлиняет этап автоварки ============
	var u31_rank := g._engine.mastery_rank
	g._engine.mastery_rank = 0
	Selftest.check("u31 stage ops base", g._engine._stage_ops() == Game.CRAFT_STAGE_OPERATIONS)
	g._engine.mastery_rank = 2
	Selftest.check("u31 below first rank", g._engine._stage_ops() == 3)
	g._engine.mastery_rank = 3
	Selftest.check("u31 rank 3 widens", g._engine._stage_ops() == 4)
	g._engine.mastery_rank = 6
	Selftest.check("u31 still 4 at rank 6", g._engine._stage_ops() == 4)
	g._engine.mastery_rank = 7
	Selftest.check("u31 rank 7 widens", g._engine._stage_ops() == 5)
	g._engine.mastery_rank = 50
	Selftest.check("u31 capped at 5", g._engine._stage_ops() == 5)
	var u31_mono := true
	var u31_prev := -1
	for u31_r in range(0, 60):
		g._engine.mastery_rank = u31_r
		var u31_now := g._engine._stage_ops()
		if u31_now < u31_prev:
			u31_mono = false
		u31_prev = u31_now
	Selftest.check("u31 monotonic", u31_mono)
	g._engine.mastery_rank = u31_rank

	# ============ U34 (A2): строка печати называет ближайший порог ============
	g._engine.mastery_rank = 2
	Selftest.check("u34 text at rank 2", g._hub._mastery_next_benefit(2).contains("автоварки"))
	g._engine.mastery_rank = 4
	Selftest.check("u34 text at rank 4", g._hub._mastery_next_benefit(4).contains("сосуд"))
	Selftest.check("u34 text elsewhere", g._hub._mastery_next_benefit(10).contains("реторта"))
	var u34_nonempty := true
	for u34_r in range(1, 12):
		if g._hub._mastery_next_benefit(u34_r).is_empty():
			u34_nonempty = false
	Selftest.check("u34 never empty", u34_nonempty)
	g._engine.mastery_rank = u31_rank

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
		and int(g._engine._craft_job.get("completed", 0)) == g._engine._stage_ops())
	g._engine._craft_job = {
		"item": "house", "completed": 0, "total_estimate": int(p_house.get("total", 0)),
		"plan": p_house.duplicate(true), "discount": 1.0, "status": "paused_stage",
	}
	var offline_stage := g._saves._advance_craft_job_offline(3600.0)
	Selftest.check("offline craft stage", int(offline_stage.get("steps", 0)) == g._engine._stage_ops()
		and String(offline_stage.get("status", "")) == "operation_cap"
		and int(g._engine._craft_job.get("completed", 0)) == g._engine._stage_ops())
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
	# U9 (T12): новый старт с висящим экспериментом теперь отказывается —
	# это и проверяем, затем очищаем bookkeeping вручную и гоняем round-trip.
	var wiped := g._init_new_game()
	Selftest.check("new game refuses with pending experiment", not wiped
		and g._engine._experiment_pending_pair == ["fire", "water"])
	g._engine._experiment_pending_pair.clear()
	g._engine._craft_job.clear()
	g._engine._blueprints.clear()
	g._engine.inventory.clear()
	g._engine.known_recipes.clear()
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

	# ================= U9 (T11): мьютекс потребляющих трасс + fail-closed списание ====
	# Снимок мира: блоки U9 меняют инвентарь/квесты (в т.ч. форс-престиж), а
	# последующим сюитам нужно богатое состояние этого места (разблокировки
	# режимов, покупка улучшений). В конце — точный restore.
	var u9_snap := {
		"inventory": g._engine.inventory.duplicate(true),
		"known": g._engine.known_recipes.duplicate(true),
		"upgrades": g._engine.upgrades.duplicate(true),
		"blueprints": g._engine._blueprints.duplicate(true),
		"rejected": g._engine._rejected_pairs.duplicate(true),
		"milestones": g._engine._milestones_done.duplicate(true),
		"quests_done": g._guild._quests_done.duplicate(true),
		"quest_brew": g._guild._quest_brew.duplicate(true),
		"quest_tier": g._guild._quest_tier.duplicate(true),
		"order_done": g._guild._order_done.duplicate(true),
		"log_events": g._hub._log_events.duplicate(true),
	}
	var u9_ether := g._engine.ether
	var u9_overflow := g._engine.ether_overflow
	var u9_mastery := g._engine.mastery_rank
	var u9_sage := g._engine.sage_gold
	var u9_att0 := g._engine.attempts
	var u9_suc0 := g._engine.successes
	var u9_taps0 := g._engine._source_taps
	var u9_last := g._engine._last_pair.duplicate(true)
	var u9_qch0 := g._guild._quest_challenge
	# U9-фикс I2: состояние, которое блок U9 тоже мутирует (через _init_new_game,
	# шаги верстака и тик _process), — дополняем снимок/restore.
	var u9_exp_day := g._engine._experiment_day
	var u9_exp_cnt := g._engine._experiment_count
	var u9_exp_last := g._engine._experiment_last_at
	var u9_spring_on := g._engine.spring_on
	var u9_spring_src := g._engine.spring_source
	var u9_gift_clock := g._engine._gift_clock
	var u9_bench_clock := g._pages._bench_clock
	g._init_new_game()
	g.BREW_SECONDS = 0.05
	g._engine.ether = 1000
	var u9_plan := g._guild._plan_craft("steam")
	# (a) верстак + ручная варка на последний юнит: стек не в минус, выход один
	g._engine.inventory["fire"] = 1
	g._engine.inventory["water"] = 1
	g._engine.inventory.erase("steam")
	g._engine.selected = ["fire", "water"]
	g._engine._run_bench_plan("steam", u9_plan)
	Selftest.check("bench takes the consume mutex", g._pages._bench_busy and not g._engine._can_brew())
	var manual_vs_bench: Dictionary = await g._engine._brew()
	Selftest.check("manual brew refused while bench runs", bool(manual_vs_bench.get("failed", false))
		and String(manual_vs_bench.get("reason", "")) == "gate")
	await g.get_tree().create_timer(1.0).timeout
	Selftest.check("bench consumed the last units exactly once", int(g._engine.inventory.get("fire", 0)) == 0
		and int(g._engine.inventory.get("water", 0)) == 0 and int(g._engine.inventory.get("steam", 0)) == 1
		and not g._pages._bench_busy and not g._engine.brewing)
	var u9_attempts := g._engine.attempts
	var commit_empty := g._engine._commit_brew("fire", "water")
	Selftest.check("commit fails closed without ingredients", bool(commit_empty.get("failed", false))
		and String(commit_empty.get("reason", "")) == "ingredients"
		and int(g._engine.inventory.get("fire", 0)) == 0 and int(g._engine.inventory.get("steam", 0)) == 1
		and g._engine.attempts == u9_attempts)
	# (б) эксперимент/верстак/автоплан отвергаются посреди ручной варки
	g._engine.inventory["fire"] = 4
	g._engine.inventory["water"] = 4
	g._engine.selected = ["fire", "water"]
	g._engine._brew()
	Selftest.check("brew sets busy before await", g._engine.brewing)
	# U9-фикс I1: fire+water была в known_recipes с бутстрапа новой игры, и
	# отказ проходил по гейту «уже известна» даже без мьютекса (вакусно).
	# fire+air — не известна (после _init_new_game открыты только fire+water и
	# earth+fire), не отклонена, в запасе (fire=4, air=5), эфир/кулдаун/лимит
	# проходима — без гейта brewing||_auto||_bench_busy в _experiment_status
	# вернулась бы ok:true, а с ним — ok:false именно с причиной мьютекса.
	var u9_exp := g._engine._experiment_status("fire", "air")
	Selftest.check("experiment refused during brew", not bool(u9_exp.get("ok", false))
		and String(u9_exp.get("reason", "")).contains("Котёл занят варкой или производством")
		and g._engine._experiment_pending_pair.is_empty())
	var u9_bench_refused: bool = await g._engine._run_bench_plan("steam", u9_plan)
	Selftest.check("bench refused during brew", not u9_bench_refused and not g._pages._bench_busy)
	var u9_auto_refused: bool = await g._engine._run_auto_plan("steam", u9_plan)
	Selftest.check("auto plan refused during brew", not u9_auto_refused and not g._engine._auto)
	await g.get_tree().create_timer(1.0).timeout
	Selftest.check("manual brew survived the mutex window", not g._engine.brewing
		and int(g._engine.inventory.get("steam", 0)) == 2 and int(g._engine.inventory.get("fire", 0)) == 3)
	# (в) упавший шаг автоплана не двигает completed: ингредиенты перехвачены во время await
	g._engine._craft_job.clear()
	g._engine.inventory["fire"] = 2
	g._engine.inventory["water"] = 2
	g._engine.inventory.erase("steam")
	g._engine.selected = []
	g.BREW_SECONDS = 1.0
	g._engine._run_auto_plan("steam", u9_plan)
	g._engine.inventory["fire"] = 0
	await g.get_tree().create_timer(2.0).timeout
	Selftest.check("failed auto step keeps completed at zero", int(g._engine._craft_job.get("completed", -1)) == 0
		and String(g._engine._craft_job.get("status", "")) == "paused_ingredients"
		and int(g._engine.inventory.get("steam", 0)) == 0 and int(g._engine.inventory.get("fire", 0)) == 0
		and not g._engine._auto)
	g.BREW_SECONDS = 0.05

	# ================= U9 (T12): гейты сброса посреди варки + brew_epoch =================
	g._init_new_game()
	for i in 35:
		g._engine.inventory["st_ep_%d" % i] = 1
	g._engine.inventory["fire"] = 5
	g._engine.inventory["water"] = 5
	g._engine.ether = 500
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._engine._source_taps = 7
	g._engine.selected = ["fire", "water"]
	var u9_epoch := g._engine.brew_epoch
	g._engine._brew()
	g._hub._open_prestige_confirm()
	Selftest.check("prestige confirm refuses during brew", not g._hub._prestige_popup.visible
		and not g._hub._prestige_dim.visible)
	Selftest.check("new game refuses during brew", not g._init_new_game()
		and g._engine.brew_epoch == u9_epoch and g._engine.inventory.size() == 39)
	g._hub._do_prestige()
	Selftest.check("prestige bumps epoch and clears experiment bookkeeping", g._engine.brew_epoch > u9_epoch
		and g._engine._experiment_pending_pair.is_empty() and g._engine._source_taps == 0)
	await g.get_tree().create_timer(1.0).timeout
	Selftest.check("aborted mid-brew prestige: no debit no reward", int(g._engine.inventory.get("fire", 0)) == 3
		and int(g._engine.inventory.get("steam", 0)) == 0 and g._engine.attempts == 0
		and g._engine.successes == 0 and not g._engine.brewing)
	# (e) смена поколения mid-await: все три корутины выходят, не трогая новый мир
	g._engine.inventory["fire"] = 4
	g._engine.inventory["water"] = 4
	g._engine.ether = 1000
	g._engine.selected = ["fire", "water"]
	g._engine._brew()
	g._engine.brew_epoch += 1
	await g.get_tree().create_timer(1.0).timeout
	Selftest.check("epoch bump aborts manual brew silently", int(g._engine.inventory.get("fire", 0)) == 4
		and g._engine.attempts == 0 and not g._engine.brewing)
	g._engine.selected = []
	g._engine._run_bench_plan("steam", u9_plan)
	g._engine.brew_epoch += 1
	await g.get_tree().create_timer(1.0).timeout
	Selftest.check("epoch bump releases bench without commit", not g._pages._bench_busy
		and int(g._engine.inventory.get("fire", 0)) == 4 and int(g._engine.inventory.get("steam", 0)) == 0)
	g._engine._craft_job.clear()
	g._engine._run_auto_plan("steam", u9_plan)
	g._engine.brew_epoch += 1
	await g.get_tree().create_timer(1.0).timeout
	Selftest.check("epoch bump releases auto plan", not g._engine._auto and not g._engine.brewing
		and int(g._engine.inventory.get("fire", 0)) == 4 and int(g._engine.inventory.get("steam", 0)) == 0
		and float(g._engine._production_discount) == 1.0)
	# поздние ответы эксперимента после сброса: дропаются без начислений/возвратов
	var u9_inv_snapshot := g._engine.inventory.duplicate(true)
	var u9_avail0 := g._engine._available_ether()
	var u9_rejected := g._engine._rejected_pairs.size()
	g._online._experiment_outcome({"slug": "st_ghost", "name": "Призрак", "color": "#112233", "glyph": "fire"},
		"fire", "water")
	g._engine._finish_experiment_inputs("fire", "water", true)
	g._engine._experiment_failed("fire", "water")
	Selftest.check("stale experiment responses dropped after reset", g._engine.inventory == u9_inv_snapshot
		and g._engine._available_ether() == u9_avail0 and not g.ITEMS.has("st_ghost")
		and g._engine._rejected_pairs.size() == u9_rejected
		and g._engine._experiment_pending_pair.is_empty())
	# restore: возвращаем мир в состояние перед блоком U9 (для последующих сюит)
	g._engine.inventory = u9_snap["inventory"]
	g._engine.known_recipes = u9_snap["known"]
	g._engine.upgrades = u9_snap["upgrades"]
	g._engine._blueprints = u9_snap["blueprints"]
	g._engine._rejected_pairs = u9_snap["rejected"]
	g._engine._milestones_done = u9_snap["milestones"]
	g._guild._quests_done = u9_snap["quests_done"]
	g._guild._quest_brew = u9_snap["quest_brew"]
	g._guild._quest_tier = u9_snap["quest_tier"]
	g._guild._order_done = u9_snap["order_done"]
	g._hub._log_events = u9_snap["log_events"]
	g._engine.ether = u9_ether
	g._engine.ether_overflow = u9_overflow
	g._engine.mastery_rank = u9_mastery
	g._engine.sage_gold = u9_sage
	g._engine.attempts = u9_att0
	g._engine.successes = u9_suc0
	g._engine._source_taps = u9_taps0
	g._engine._last_pair = u9_last
	g._guild._quest_challenge = u9_qch0
	g._engine._experiment_day = u9_exp_day
	g._engine._experiment_count = u9_exp_cnt
	g._engine._experiment_last_at = u9_exp_last
	g._engine.spring_on = u9_spring_on
	g._engine.spring_source = u9_spring_src
	g._engine._gift_clock = u9_gift_clock
	g._pages._bench_clock = u9_bench_clock
	g._engine.selected.clear()
	g._engine.brewing = false
	g._engine._auto = false
	g._engine._auto_cancel = false
	g._engine._auto_new.clear()
	g._engine._craft_job.clear()
	g._engine._experiment_pending_pair.clear()
	g._engine._production_discount = 1.0
	g._engine._layer_cache.clear()
	g._engine._cost_cache.clear()
	g._pages._bench_busy = false
	g.BREW_SECONDS = 0.05
	# U9-фикс I2: флаги чипов режимов и сейв selftest должны отражать
	# восстановленный мир, а не форс-престиж из блока U9.
	g._pages._ensure_modes()
	g._saves._save_game()
