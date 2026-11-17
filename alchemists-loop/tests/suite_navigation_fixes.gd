extends RefCounted

static func run(g: Game) -> void:
	Selftest.check("upgrades do not contain brewing multipliers", g.find_child("UpQtyRow", true, false) == null)
	for mode in ["brew", "experiment"]:
		g._bottom_nav._on_pressed("lab")
		g._pages._set_cauldron_mode(mode, false)
		await _click_nav(g, 1)
		Selftest.check("real dock click leaves " + mode + " for world", g._tabs_ref.current_tab == Game.TAB_WORLD and not g._screens.is_open())
	await _click_nav(g, 3)
	await _click_nav(g, 2)
	Selftest.check("friends replace rather than cover previous tab", g._social_ui.is_open() and not g._tabs_ref.visible and not g._rooms._scene_visible)
	await _click_nav(g, 3)
	Selftest.check("return to same tab restores content", not g._social_ui.is_open() and g._tabs_ref.visible and g._tabs_ref.current_tab == Game.TAB_RATING)
	await _click_nav(g, 0)
	Selftest.check("room returns after friends", g._tabs_ref.visible and g._rooms._scene_visible)
	g._pages._set_cauldron_mode("brew", false)
	await _click_nav(g, 2)
	Selftest.check("friends replace brewing", g._social_ui.is_open() and not g._screens.is_open() and not g._tabs_ref.visible)
	await _click_nav(g, 0)
	var quantities := g.find_child("BrewQtyRow", true, false)
	Selftest.check("brewing contains quantity choices", quantities != null and quantities.get_child_count() == 3)
	if quantities != null:
		var inventory := g._engine.inventory.duplicate()
		var known := g._engine.known_recipes.duplicate()
		g._engine.inventory = {"fire": 1000, "water": 1000}
		g._engine.known_recipes[g._pair_key("fire", "water")] = true
		for i in 3:
			var amount: int = [1, 10, 100][i]
			(quantities.get_child(i) as Button).pressed.emit()
			g._engine._auto_craft("steam")
			var plan: Dictionary = g._engine._pending_plan
			Selftest.check("brewing quantity plans x%d" % amount, int(plan.get("total", 0)) == amount and int(plan.get("ops", [{}])[0].get("n", 0)) == amount)
			g._hide_confirm()
		var ether := g._engine.ether
		var overflow := g._engine.ether_overflow
		var brew_seconds := g.BREW_SECONDS
		var blueprints := g._engine._blueprints.duplicate(true)
		g._engine.ether = 10000
		g._engine.ether_overflow = 10000
		g.BREW_SECONDS = 0.001
		(quantities.get_child(1) as Button).pressed.emit()
		g._engine._auto_craft("steam")
		var batch_plan: Dictionary = g._engine._pending_plan
		g._hide_confirm()
		await g._engine._run_auto_plan("steam", batch_plan)
		Selftest.check("batch pauses after stage without losing remaining quantity", int(g._engine._craft_job.get("amount", 0)) == 10 and int(g._engine._craft_job.get("produced", 0)) == g._engine._stage_ops())
		(quantities.get_child(0) as Button).pressed.emit()
		for stage in 10:
			if g._engine._craft_job.is_empty():
				break
			g._engine._auto_craft("steam")
			batch_plan = g._engine._pending_plan
			g._hide_confirm()
			await g._engine._run_auto_plan("steam", batch_plan)
		Selftest.check("resumed batch produces exactly ten and consumes ten pairs", g._engine._craft_job.is_empty() and int(g._engine.inventory.get("steam", 0)) == 10 and int(g._engine.inventory.get("fire", 0)) == 990 and int(g._engine.inventory.get("water", 0)) == 990)
		g._engine._craft_job = {"item": "steam", "amount": 10, "produced": 0, "completed": 0, "total_estimate": 10, "discount": 1.0}
		g._workshop_scheduler.advance(120.0, true)
		Selftest.check("offline batch remains active after first output", not g._engine._craft_job.is_empty() and int(g._engine._craft_job.get("produced", 0)) == g._engine._stage_ops())
		for stage in 10:
			if g._engine._craft_job.is_empty():
				break
			g._workshop_scheduler.advance(120.0, true)
		Selftest.check("offline batch finishes at ten outputs", g._engine._craft_job.is_empty() and int(g._engine.inventory.get("steam", 0)) == 20)
		g._engine._craft_job.clear()
		g._engine.ether = ether
		g._engine.ether_overflow = overflow
		g._engine._blueprints = blueprints
		g.BREW_SECONDS = brew_seconds
		g._engine.inventory = inventory
		g._engine.known_recipes = known
		g._engine._pending_plan = {}
		g._engine._pending_item = ""
		g._engine._refresh()

static func _click_nav(g: Game, index: int) -> void:
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var button: Button = g._bottom_nav._items[index].btn
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	g.get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = down
		g.get_viewport().push_input(event, true)
	await g.get_tree().process_frame
