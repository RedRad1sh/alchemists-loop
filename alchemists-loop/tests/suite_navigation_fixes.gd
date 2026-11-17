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
	await _check_bottom_tab_consistency(g)

static func _check_bottom_tab_consistency(g: Game) -> void:
	var tops := {}
	var nav_for := {Game.TAB_WORLD: 1, Game.TAB_RATING: 3, Game.TAB_TOOLS: 4}
	for tab in [Game.TAB_WORLD, Game.TAB_RATING, Game.TAB_TOOLS]:
		await _click_nav(g, int(nav_for[tab]))
		await g.get_tree().process_frame
		var page := g._tabs_ref.get_tab_control(tab) as ScrollContainer
		page.scroll_vertical = 0
		await g.get_tree().process_frame
		var margin := page.get_child(0) as MarginContainer
		Selftest.check("page uses shared top indent tab %d" % tab,
			margin.get_theme_constant("margin_top") == 10)
		var first: Control = margin.get_child(0) as Control
		while first is Container and first.get_child_count() > 0:
			first = first.get_child(0) as Control
		tops[tab] = first.global_position.y
		Selftest.check("page heading uses shared typography tab %d" % tab,
			first is Label and first.get_theme_font_size("font_size") == 13
			and first.get_theme_font("font") == g._font_semi)
	Selftest.check("world, rating and settings share one top line",
		is_equal_approx(tops[Game.TAB_WORLD], tops[Game.TAB_RATING])
		and is_equal_approx(tops[Game.TAB_WORLD], tops[Game.TAB_TOOLS]))
	var tabs_rect := g._tabs_ref.get_global_rect()
	var bar_h := g._tabs_ref.get_tab_bar().get_combined_minimum_size().y
	tabs_rect.position.y += bar_h
	tabs_rect.size.y -= bar_h
	await _click_nav(g, 2)
	await g.get_tree().process_frame
	var friends_panel := g._social_ui._screen.find_child("SocialPanel", true, false) as PanelContainer
	var friends_rect := friends_panel.get_global_rect()
	Selftest.check("friends frame matches the tab rect",
		friends_rect.position.distance_to(tabs_rect.position) < 1.0
		and friends_rect.size.distance_to(tabs_rect.size) < 1.0)
	var friends_frame := friends_panel.get_theme_stylebox("panel") as StyleBoxTexture
	var tabs_frame := g._tabs_ref.get_theme_stylebox("panel") as StyleBoxTexture
	Selftest.check("friends frame is the tab frame",
		friends_frame != null and tabs_frame != null
		and friends_frame.texture == tabs_frame.texture)
	var friends_margin := friends_panel.find_child("SocialMargin", true, false)
	var friends_header: Control = null
	if friends_margin != null:
		friends_header = friends_margin.get_child(0).get_child(0) as Control
	Selftest.check("friends header has no redundant close button",
		friends_header != null and friends_header.find_children("*", "Button", true, false).is_empty())
	var friends_title := friends_header.get_child(0) as Label if friends_header != null else null
	Selftest.check("friends heading matches section typography",
		friends_title != null and friends_title.get_theme_font_size("font_size") == 13
		and friends_title.get_theme_font("font") == g._font_semi)
	var translator := EnTranslation.new()
	var headings := {
		"МИР ЖИВЫХ ОТКРЫТИЙ": "WORLD OF LIVE DISCOVERIES",
		"ГОНКА ПЕРВООТКРЫТИЙ": "DISCOVERY RACE",
		"СВЕЖИЕ ОТКРЫТИЯ": "RECENT DISCOVERIES",
		"ЗАЛ СЛАВЫ": "HALL OF FAME",
		"ТОП ДЛИННЫХ ЦЕПОЧЕК": "LONGEST RECIPE CHAINS",
		"ВСЕ ВЕЩЕСТВА": "ALL ELEMENTS",
		"РОДОСЛОВНАЯ": "LINEAGE",
	}
	for source in headings:
		Selftest.check("section heading remains translated: " + source,
			translator.translate_string(source) == headings[source])
	await _click_nav(g, 0)
	for key in ["EtherChip", "ProfileEntry", "ShopBtn"]:
		var button := g.find_child(key, true, false) as Button
		Selftest.check("HUD button exists " + key, button != null)
		if button == null:
			continue
		button.button_down.emit()
		await g.get_tree().create_timer(0.1).timeout
		Selftest.check("HUD button compresses on press " + key, button.scale.x < 0.99)
		button.button_up.emit()
		await g.get_tree().create_timer(0.3).timeout
		Selftest.check("HUD button springs back after release " + key,
			button.scale.distance_to(Vector2.ONE) < 0.01)

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
