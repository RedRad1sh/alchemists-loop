extends "res://main.gd"
const Fixture = preload("res://tests/workshop_fixture.gd")
const OPERATION_LIMIT := 4000
const ONLINE_TICKS := 60
const COMPARISON_BUDGET := 1200
const CATALOG_PATH := "res://../discovery-server/server/data/sigil_catalog.json"

# Keep the actual Game lifecycle, module setup and _build_ui.
func _run_selftest() -> void:
	set_process(false)
	_saves._save_frozen = true
	_online._net_enabled = false
	Net.set_process(false)
	Net._available = false
	Net.base_url = ""
	Net._queue.clear()
	Net._inflight.clear()
	SAVE_PATH = "user://alchemy_st_acceptance.json"
	TEMP_PATH = "user://alchemy_st_acceptance.tmp"
	BACKUP_PATH = "user://alchemy_st_acceptance.bak"
	if OS.get_cmdline_user_args().has("--workshop-shot"):
		_workshop_shot.call_deferred()
		return
	var suite: Script = load("res://tests/suite_workshop_acceptance.gd")
	await suite.run(self)
	if OS.get_cmdline_user_args().has("--workshop-economy"):
		var report := economy_report(self)
		var path := fresh_artifact("res://previews/workshop-economy.json")
		var file := FileAccess.open(path, FileAccess.WRITE)
		Selftest.check("acceptance machine readable report opens", file != null)
		if file != null:
			file.store_string(JSON.stringify(report, "\t", true, true))
			file.close()
			Selftest.check("acceptance written report roundtrips", JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary)
			print("WORKSHOP_ECONOMY_JSON: " + ProjectSettings.globalize_path(path))
	print("WORKSHOP_ACCEPTANCE_RESULT: %d/%d" % [Selftest._total - Selftest._fails, Selftest._total])
	get_tree().quit(0 if Selftest._fails == 0 else 1)

static func fresh_artifact(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var n := 2
	while FileAccess.file_exists(path.get_basename() + "-%d." % n + path.get_extension()):
		n += 1
	return path.get_basename() + "-%d." % n + path.get_extension()

static func _fixture(g: Game) -> WorkshopFixture:
	var fixture := Fixture.new(g)
	fixture.capture(g._workshop_scheduler)
	fixture.capture(g._sigil_ui)
	return fixture

static func _seed(g: Game, fixture: WorkshopFixture, depth := 99, blueprint := false) -> void:
	fixture.prepare_production()
	g._engine.inventory = {"fire": 3000, "water": 3000, "earth": 3000, "air": 3000}
	g._engine.known_recipes.clear()
	for recipe in g.RECIPES:
		if g._engine._content_layer(recipe["out"]) <= depth:
			g._engine.known_recipes[g._pair_key(recipe["a"], recipe["b"])] = true
			if blueprint:
				g._engine._blueprints[recipe["out"]] = {"total": 1, "ops": []}
	g._engine.upgrades.clear()
	g._engine.mastery_rank = 0
	g._engine.sage_gold = 0
	g._engine.regen_clock = 0.0
	g._engine._milestones_done.clear()
	g._guild._quest_brew.clear()
	g._guild._quest_tier.clear()
	g._guild._quests_done.clear()
	g._guild._order_done.clear()
	g._retention._circle_disc = 0
	g._contracts._fair_local_brews.clear()
	g._pages._spring_clock = 0.0
	g._pages._bench_target = ""
	g._pages._bench_on = false
	g._sigil._milestones_claimed.clear()
	g._workshop.reset_new_game()
	g._engine.ether = 100000
	g._engine.ether_overflow = 0

static func _context(discount := 1.0, manual := false) -> Dictionary:
	return {"source": "manual" if manual else "offline_workshop", "production": not manual, "discount": discount}

static func _ledger() -> Dictionary:
	return {"operations": 0, "gross_ether_spent": 0, "reward_ether": 0, "mastery": 0, "outputs": {}, "reason": "", "complete": true}

static func _unit(g: Game, target: String, ledger: Dictionary, discount := 1.0, manual := false) -> bool:
	# Replan from the actual shared inventory after every confirmed operation.
	while int(ledger["operations"]) < OPERATION_LIMIT:
		var plan: Dictionary = g._guild._plan_craft(target)
		if not plan.get("ok", false) or int(plan.get("total", 0)) <= 0 or int(plan.get("total", 0)) > Game.CRAFT_PLAN_HARD_LIMIT_OPERATIONS:
			ledger["reason"] = plan.get("reason", "plan_limit")
			ledger["complete"] = false
			return false
		var op: Dictionary = plan["ops"][0]
		var wallet := g._engine._available_ether()
		var quote := g._engine._pair_cost(op["a"], op["b"], discount)
		var result: Dictionary = g._engine._commit_brew(op["a"], op["b"], _context(discount, manual))
		if result.get("failed", true):
			ledger["reason"] = result.get("reason", "commit_rejected")
			ledger["complete"] = false
			return false
		var spent := int(result["ether_spent"])
		ledger["operations"] += 1
		ledger["gross_ether_spent"] += spent
		ledger["reward_ether"] += g._engine._available_ether() - wallet + spent
		ledger["mastery"] += int(result["mastery_awarded"])
		var output := String(result["output"])
		ledger["outputs"][output] = int(ledger["outputs"].get(output, 0)) + 1
		if spent != quote:
			ledger["reason"] = "actual_price_differs_from_pair_quote"
			ledger["complete"] = false
			return false
		if output == target:
			return true
	ledger["complete"] = false
	ledger["reason"] = "operation_limit"
	return false

static func _materials(g: Game, needs: Dictionary, ledger: Dictionary, discount := 1.0) -> bool:
	for target in needs:
		if target in Game.BASE_IDS:
			if int(g._engine.inventory.get(target, 0)) < int(needs[target]):
				ledger["complete"] = false
				ledger["reason"] = "base_stock_shortage"
				return false
			continue
		while int(g._engine.inventory.get(target, 0)) < int(needs[target]):
			if not _unit(g, target, ledger, discount):
				return false
	return true

static func acceptance_flow(g: Game) -> Dictionary:
	var fixture := _fixture(g)
	var original_inventory := g._engine.inventory.duplicate(true)
	var original_workshop := g._workshop.export_state()
	var original_save := g.SAVE_PATH
	_seed(g, fixture)
	g.SAVE_PATH = "user://alchemy_st_acceptance_flow.json"
	g.TEMP_PATH = "user://alchemy_st_acceptance_flow.tmp"
	g.BACKUP_PATH = "user://alchemy_st_acceptance_flow.bak"
	var w: Workshop = g._workshop
	var ledger := _ledger()
	var result := {}
	var person_ok := _unit(g, "person", ledger, 1.0, true)
	result["person_committed"] = person_ok and w.unlocked and int(g._engine.inventory.get("person", 0)) == 1
	result["mastery_from_commits"] = w.xp == ledger["mastery"] and w.xp == mini(6, g._engine._content_layer("person"))
	var xp_person := w.xp
	var materials_ok := _materials(g, Workshop.Rules.RANKS[1]["materials"], ledger)
	result["mastery_material_preparation"] = w.xp - xp_person
	result["materials_produced"] = materials_ok and g._engine.inventory.get("brick", 0) == 20 and g._engine.inventory.get("metal", 0) == 10
	var before := g._engine._available_ether()
	var xp := w.xp
	var bought := w.buy_rank(1)
	result["exact_rank_purchase"] = bought.get("ok", false) and w.rank == 1 and w.lines.size() == 2 and w.xp == xp \
		and g._engine.inventory.get("brick", -1) == 0 and g._engine.inventory.get("metal", -1) == 0 \
		and before - g._engine._available_ether() == int(Workshop.Rules.RANKS[1]["ether"])
	before = g._engine._available_ether()
	var inventory := g._engine.inventory.duplicate(true)
	var duplicate := w.buy_rank(1)
	result["duplicate_purchase_no_debit"] = not duplicate.get("ok", true) and g._engine.inventory == inventory and g._engine._available_ether() == before
	if w.lines.size() >= 2:
		var steam_before := int(g._engine.inventory.get("steam", 0))
		var dust_before := int(g._engine.inventory.get("dust", 0))
		w.enqueue(w.lines[0]["id"], {"target": "steam", "mode": "batch", "amount": 6})
		w.enqueue(w.lines[1]["id"], {"target": "dust", "mode": "batch", "amount": 6})
		xp = w.xp
		g._process(Game.BENCH_INTERVAL)
		result["two_real_lines"] = int(g._engine.inventory.get("steam", 0)) == steam_before + 3 \
			and int(g._engine.inventory.get("dust", 0)) == dust_before + 3 and w.xp == xp + 6
		g._saves._save_frozen = false
		var save_ok := g._saves._save_game()
		var saved := g._saves._read_save(g.SAVE_PATH)
		result["safe_snapshot"] = save_ok and saved.get("workshop", {}).get("rank", -1) == 1 \
			and saved.get("workshop", {}).get("xp", -1) == w.xp and same_json(saved.get("inventory"), g._engine.inventory)
		# Age ONLY this ST snapshot, then execute the actual load/grant/safe-save path.
		var timestamp := Time.get_unix_time_from_system() - 160.1
		saved["last_ts"] = timestamp
		saved["workshop"]["last_simulated_at"] = timestamp
		var file := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(saved, "\t", true, true))
			file.close()
		g._selftest = false
		g._saves._load_game()
		g._selftest = true
		var receipt: Dictionary = g._saves.get("_return_workshop")
		result["reload_offline_output"] = int(g._engine.inventory.get("steam", 0)) == steam_before + 6 \
			and int(g._engine.inventory.get("dust", 0)) == dust_before + 6 \
			and receipt.get("mastery", -1) == 6 and receipt.get("saved", false) and w.lines[0]["queue"].is_empty() and w.lines[1]["queue"].is_empty()
		inventory = g._engine.inventory.duplicate(true)
		xp = w.xp
		g._selftest = false
		g._saves._load_game()
		g._selftest = true
		result["reload_no_duplicate"] = g._engine.inventory == inventory and w.xp == xp
		g._saves._save_frozen = true
	# Unlock actual prestige with actual catalog-independent local discoveries.
	for target in ordered_outputs(g):
		if g._hub._prestige_gain() > 0:
			break
		if not g._engine.inventory.has(target) and not _unit(g, target, ledger):
			break
	xp = w.xp
	var rank := w.rank
	var line_ids: Array = []
	for line in w.lines:
		line_ids.append(line["id"])
		w.enqueue(line["id"], {"target": "brick", "mode": "batch", "amount": 3})
		line["phase_seconds"] = 17.0
	var gold := g._engine.sage_gold
	g._hub._do_prestige()
	result["prestige_keeps_equipment"] = g._engine.sage_gold > gold and w.unlocked and w.rank == rank and w.xp == xp and w.lines.size() == line_ids.size()
	var routes_empty := true
	for line in w.lines:
		routes_empty = routes_empty and line["queue"].is_empty() and line["phase_seconds"] == 0.0 and line["stage_credit"] == 0
	result["prestige_clears_routes"] = routes_empty and g._engine._craft_job.is_empty() and not g._engine.inventory.has("person")
	inventory = g._engine.inventory.duplicate(true)
	before = g._engine._available_ether()
	var unknown := w.enqueue(line_ids[0], {"target": "dust", "mode": "batch", "amount": 1})
	result["unknown_post_prestige_rejected"] = not unknown.get("ok", true) and inventory == g._engine.inventory and before == g._engine._available_ether()
	if w.lines.size() >= 2:
		w.enqueue(line_ids[0], {"target": "steam", "mode": "batch", "amount": 1})
		w.enqueue(line_ids[1], {"target": "stone", "mode": "batch", "amount": 1})
		g._process(Game.BENCH_INTERVAL)
		result["known_post_prestige_production"] = g._engine.inventory.get("steam", 0) == 1 \
			and g._engine.inventory.get("stone", 0) == 1 and w.xp == xp + 2 and w.rank == rank and g._engine._mode_unlocked("bench")
	result["network_quiet"] = Net._queue.is_empty() and Net._inflight.is_empty() and not Net._available and Net.base_url == ""
	result["operations"] = ledger["operations"]
	result["gross_ether_spent"] = ledger["gross_ether_spent"]
	result["reward_ether"] = ledger["reward_ether"]
	result["xp_at_person"] = xp_person
	for path in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	fixture.finish()
	result["fixture_restored"] = g._engine.inventory == original_inventory and same_json(g._workshop.export_state(), original_workshop) and g.SAVE_PATH == original_save
	return result

static func same_json(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

static func ordered_outputs(g: Game) -> Array:
	var depths := {}
	for recipe in g.RECIPES:
		depths[String(recipe["out"])] = g._engine._content_layer(recipe["out"])
	var items: Array = depths.keys()
	items.sort_custom(func(a: String, b: String) -> bool:
		return int(depths[a]) < int(depths[b]) if int(depths[a]) != int(depths[b]) else a < b)
	return items

func economy_report(g: Game) -> Dictionary:
	var report := {"schema": 1, "bounded": {"operation_limit": OPERATION_LIMIT,
		"chosen_budget": COMPARISON_BUDGET, "offline_seconds": [60, 3600, Game.OFFLINE_CAP_SEC],
		"max_events": 100000}, "assumptions": {"source": "real Game/Core/Guild/WorkshopScheduler/SigilManager",
		"network": false, "catalog": CATALOG_PATH, "prices": "Core._pair_cost and WorkshopBalance",
		"rewards": "tracked separately from gross ether spent", "unfinished": "reported as incomplete/stall"},
		"profiles": [], "catalog_offers": [], "budget_comparison": [], "chromatic": {},
		"finite_discoveries": [], "finite_discoveries_complete": false, "xp_at_person": 0,
		"xp_after_material_preparation": 0, "natural_scenario": {}}
	var catalog_file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if catalog_file != null:
		var parsed: Variant = JSON.parse_string(catalog_file.get_as_text())
		catalog_file.close()
		if parsed is Dictionary:
			for rarity in ["common", "epic", "legendary"]:
				for card in parsed.get("cards", []):
					if card is Dictionary and String(card.get("rarity", "")) == rarity:
						var recipe := g._sigil.make_card_recipe(card)
						var needs := {}
						for item in card.get("recipe", []):
							needs[String(item.get("item_id", ""))] = int(item.get("qty", 0))
						report["catalog_offers"].append({"id": card.get("id", ""), "rarity": rarity,
							"ether_cost": int(card.get("ether_cost", 0)), "ingredients": needs,
							"recipe_seed": recipe.compute_seed()})
						break
	var quote_fixture := _fixture(g)
	_seed(g, quote_fixture, 6)
	g._workshop.import_state({"version": 1, "unlocked": true, "rank": 3, "xp": 1000})
	for offer in report["catalog_offers"]:
		var quote: Dictionary = g._workshop.job_preview(String(offer["id"]), "batch", 1)
		report["budget_comparison"].append({"id": offer["id"], "rarity": offer["rarity"],
			"chosen_budget": COMPARISON_BUDGET, "catalog_ether_cost": offer["ether_cost"],
			"planner_ok": quote.get("ok", false), "planner_operations": quote.get("operations", 0),
			"planner_ether": quote.get("ether", 0), "exact_base_materials": quote.get("base_add", {}),
			"within_budget": quote.get("ok", false) and int(quote.get("ether", COMPARISON_BUDGET + 1)) <= COMPARISON_BUDGET})
	quote_fixture.finish()
	var chromatic_items := PackedStringArray()
	for offer in report["catalog_offers"]:
		for item in offer["ingredients"]:
			if item not in chromatic_items and g.ITEMS.has(item):
				chromatic_items.append(item)
				if chromatic_items.size() == 4: break
		if chromatic_items.size() == 4: break
	var chromatic := {"id": "acceptance_chromatic", "rarity": "chromatic", "is_chromatic": true,
		"ether_cost": 1200, "ingredients": []}
	for item in chromatic_items:
		chromatic["ingredients"].append({"item_id": item, "qty": 1})
	var chromatic_recipe: SigilRecipe = g._sigil.make_craft_recipe(chromatic)
	report["chromatic"] = {"status": "deterministic_catalog_derived_input", "ether_cost": 1200,
		"ingredients": chromatic["ingredients"], "recipe_seed": chromatic_recipe.compute_seed(),
		"valid": chromatic_items.size() == 4}
	var profiles := [{"name": "early", "depth": 2}, {"name": "intermediate", "depth": 4}, {"name": "developed", "depth": 6}]
	for profile in profiles:
		for lines in [1, 2, 4]:
			for autonomy in [0, 1, 2]:
				for blueprint in [false, true]:
					var row := {"profile": profile["name"], "lines": lines, "autonomy": autonomy,
						"blueprint": blueprint, "status": "complete", "operations": 0, "items": 0,
						"mastery": 0, "gross_ether_spent": 0, "reward_ether": 0, "simulated_seconds": 0.0,
						"stalls": [], "incomplete": false}
					var fixture := _fixture(g)
					_seed(g, fixture, profile["depth"], blueprint)
					var scenario_rank := mini(lines - 1, 3)
					g._workshop.import_state({"version": 1, "unlocked": true, "rank": scenario_rank, "xp": 1000})
					var effective_autonomy := mini(mini(autonomy, scenario_rank), 2)
					g._workshop.autonomy_level = effective_autonomy
					var target := "steam" if profile["depth"] <= 2 else ("brick" if profile["depth"] <= 4 else "tool")
					row["autonomy_effective"] = effective_autonomy
					row["equipment_rank"] = scenario_rank
					if effective_autonomy != autonomy:
						row["stalls"].append({"status": "equipment_rank_gate", "requested_autonomy": autonomy,
							"reason": "WorkshopBalance requires rank %d for autonomy %d." % [autonomy, autonomy]})
					var line_count := mini(lines, g._workshop.lines.size())
					for line_index in line_count:
						var line_target := target if line_index % 2 == 0 else "dust"
						if g._workshop.known_target_recipe(line_target):
							g._workshop.enqueue(g._workshop.lines[line_index]["id"], {"target": line_target, "mode": "batch", "amount": 1})
					var stats: Dictionary = g._workshop_scheduler.advance(Game.OFFLINE_CAP_SEC, true)
					row["operations"] = int(stats.get("steps", 0)); row["items"] = int(stats.get("items", 0))
					row["mastery"] = int(stats.get("mastery", 0)); row["gross_ether_spent"] = int(stats.get("ether_spent", 0))
					row["reward_ether"] = int(stats.get("ether_gained", 0)); row["simulated_seconds"] = float(stats.get("simulated_seconds", 0.0))
					row["status"] = stats.get("status", "unknown")
					for line_id in stats.get("lines", {}):
						var line_stats: Dictionary = stats["lines"][line_id]
						if int(line_stats.get("queue_count", 0)) > 0:
							row["incomplete"] = true
							row["stalls"].append({"line": line_id, "status": line_stats.get("status", ""), "reason": line_stats.get("reason", "")})
					report["profiles"].append(row)
					fixture.finish()
	var fixture := _fixture(g)
	_seed(g, fixture, 99)
	var natural_ledger := _ledger()
	_unit(g, "person", natural_ledger, 1.0, true)
	report["xp_at_person"] = g._workshop.xp
	_materials(g, Workshop.Rules.RANKS[1]["materials"], natural_ledger)
	report["xp_after_material_preparation"] = g._workshop.xp
	var discovery_limit := 0
	var eligible_discoveries := 0
	for candidate in ordered_outputs(g):
		var candidate_layer := g._engine._content_layer(candidate)
		if candidate_layer > 0 and candidate_layer < Workshop.Rules.INVALID_DEPTH and not g._engine.inventory.has(candidate):
			eligible_discoveries += 1
	for item in ordered_outputs(g):
		if discovery_limit >= OPERATION_LIMIT: break
		var layer := g._engine._content_layer(item)
		if layer <= 0 or layer >= Workshop.Rules.INVALID_DEPTH or g._engine.inventory.has(item): continue
		var before_xp := g._workshop.xp
		var discovered := _unit(g, item, natural_ledger)
		if not discovered:
			break
		discovery_limit = natural_ledger["operations"]
		report["finite_discoveries"].append({"item": item, "content_layer": layer,
			"mastery_per_unit": mini(layer, 6), "committed": true,
			"xp_before": before_xp, "xp_after": g._workshop.xp})
	report["finite_discoveries_complete"] = report["finite_discoveries"].size() == eligible_discoveries
	report["natural_scenario"] = {"operations": natural_ledger["operations"],
		"gross_ether_spent": natural_ledger["gross_ether_spent"], "mastery": natural_ledger["mastery"],
		"complete": report["finite_discoveries_complete"], "reason": natural_ledger["reason"]}
	fixture.finish()
	return report

func _workshop_shot() -> void:
	var fixture := _fixture(self)
	_seed(self, fixture)
	_engine.inventory["person"] = 1
	_engine.inventory["brick"] = 20
	_engine.inventory["metal"] = 10
	_engine.known_recipes[_pair_key("clay", "fire")] = true
	_engine.known_recipes[_pair_key("stone", "spark")] = true
	_workshop.unlocked = true; _workshop.xp = 100; _workshop.rank = 0
	_pages._ensure_modes(); _pages._select_mode("bench")
	_tabs_ref.current_tab = TAB_TOOLS
	_pages._ensure_modes(); _pages._select_mode("bench")
	var page: Node = _pages._mode_pages.get("bench")
	var view: Node = page.find_child("WorkshopView", true, false) if is_instance_valid(page) else null
	if view != null:
		view.call("refresh")
		var buy: Button = view.find_child("BuyEquipment", true, false)
		if buy != null: buy.pressed.emit()
		await get_tree().process_frame
		_workshop.enqueue(_workshop.lines[0]["id"], {"target": "steam", "mode": "batch", "amount": 2})
		_workshop.enqueue(_workshop.lines[1]["id"], {"target": "dust", "mode": "batch", "amount": 2})
		view.call("refresh")
		var first_job := view.find_child("JobInfo_" + String(_workshop.lines[0]["queue"][0]["id"]), true, false)
		var second_job := view.find_child("JobInfo_" + String(_workshop.lines[1]["queue"][0]["id"]), true, false)
		Selftest.check("acceptance shot binds two actual queued jobs", first_job != null and second_job != null
			and String(first_job.text).contains("Пар") and String(second_job.text).contains("Пыль"))
		print("WORKSHOP_SHOT_STATE: rank=%d lines=%d queued=%d" % [_workshop.rank, _workshop.lines.size(), _workshop.lines[0]["queue"].size() + _workshop.lines[1]["queue"].size()])
	else:
		push_error("WORKSHOP_SHOT_NO_REAL_VIEW")
	var scroll: ScrollContainer = null
	var ancestor: Node = view
	while ancestor != null:
		if ancestor is ScrollContainer:
			scroll = ancestor
			break
		ancestor = ancestor.get_parent()
	if scroll != null:
		scroll.scroll_vertical = maxi(0, int(view.global_position.y - scroll.global_position.y - 12.0))
	var line_one: Node = view.find_child("LineCard_1", true, false)
	var line_two: Node = view.find_child("LineCard_2", true, false)
	if scroll != null and line_one != null and line_two != null:
		scroll.scroll_vertical += maxi(0, int(line_one.global_position.y - 232.0))
		# Keep both real line cards in the portrait frame: the first card is tall,
		# so the second card remains partially visible with its queued target.
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 190)
	await get_tree().process_frame
	print("WORKSHOP_SHOT_LAYOUT: selected=%s unlocked=%s view_visible=%s view_size=%s page_visible=%s scrolled=%s scroll_size=%s lines=%s/%s" % [str(_pages._tools_sel), str(_engine._mode_unlocked("bench")), str(view.visible if view != null else false), str(view.size if view != null else Vector2.ZERO), str(page.visible if is_instance_valid(page) else false), str(scroll.scroll_vertical if scroll != null else -1), str(scroll.size if scroll != null else Vector2.ZERO), str(line_one.global_position if line_one != null else Vector2.ZERO), str(line_two.global_position if line_two != null else Vector2.ZERO)])
	if _popup != null: _popup.visible = false
	if _confirm != null: _confirm.visible = false
	if _sigil_ui != null: _sigil_ui._close_top_modal()
	await get_tree().process_frame; await get_tree().process_frame
	var viewport_texture: Texture2D = get_viewport().get_texture()
	var image: Image = viewport_texture.get_image() if viewport_texture != null else null
	var path := fresh_artifact("res://previews/workshop-production.png")
	var ok := image != null and image.get_width() == 540 and image.get_height() == 960 and image.save_png(path) == OK
	var width := image.get_width() if image != null else 0
	var height := image.get_height() if image != null else 0
	print("WORKSHOP_SHOT_SUCCESS: %s %dx%d %s" % [str(ok), width, height, ProjectSettings.globalize_path(path)])
	Selftest.check("acceptance production screenshot is actual portrait viewport", ok and is_instance_valid(view) and _workshop.rank == 1)
	fixture.finish(); get_tree().quit(0 if Selftest._fails == 0 else 1)
