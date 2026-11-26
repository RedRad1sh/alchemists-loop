extends Node
## Кадры экрана Мастерской (верстак) для визуальной приёмки.
## Запуск (ОКНО, не --headless):
##   "<Godot_console.exe>" --path . --scene res://tests/workshop_shots.tscn -- --capture-dir=C:/path

var g: Game
var output_dir := "user://workshop_shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	g = load("res://main.tscn").instantiate() as Game
	g.SAVE_PATH = "user://alchemy_workshop_shots.json"
	g.TEMP_PATH = "user://alchemy_workshop_shots.tmp"
	g.BACKUP_PATH = "user://alchemy_workshop_shots.bak"
	add_child(g)
	g._saves._save_frozen = true
	g._online._net_enabled = false
	await _settle()
	g._shop._close_consent()
	g._popup.hide()
	g._confirm.hide()
	g._saves._return_popup.hide()
	g._saves._return_dim.hide()
	_seed()
	g._engine.inventory["person"] = 1
	g._pages._ensure_modes()
	await _settle()
	print("WORKSHOP_HAS_BENCH ", g._pages._mode_pages.has("bench"))
	g._pages._workshop_view.refresh()
	for dimensions in [Vector2i(540, 960), Vector2i(360, 800)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		g._pages._open_device_screen("bench", "Верстак")
		await _settle()
		var view = g._pages._workshop_view
		view._set_composer(0, false)
		await _settle()
		var scroll := _scroll_of(view)
		if scroll != null:
			scroll.scroll_vertical = 0
		await _settle()
		await _capture("workshop-top-%dx%d" % [dimensions.x, dimensions.y])
		if OS.get_cmdline_user_args().has("--widths"):
			for sec in ["lines", "compose", "equip"]:
				view._show_section(sec)
				await _settle()
				_dump_widths(view, sec, dimensions.x)
			view._show_section("lines")
			await _settle()
		if scroll != null:
			scroll.scroll_vertical = 100000
			await _settle()
			await _capture("workshop-queue-%dx%d" % [dimensions.x, dimensions.y])
		view._set_composer(0, true)
		await _settle()
		if scroll != null:
			scroll.scroll_vertical = 0
			await _settle()
		await _capture("workshop-compose-%dx%d" % [dimensions.x, dimensions.y])
		if scroll != null:
			scroll.scroll_vertical = 100000
			await _settle()
			await _capture("workshop-compose-end-%dx%d" % [dimensions.x, dimensions.y])
		view._set_composer(0, false)
		view._show_section("equip")
		await _settle()
		if scroll != null:
			scroll.scroll_vertical = 0
			await _settle()
		await _capture("workshop-equip-%dx%d" % [dimensions.x, dimensions.y])
		view._show_section("lines")
		g._screens.close()
	print("WORKSHOP_SHOTS done")
	get_tree().quit()


func _seed() -> void:
	g._engine.inventory = {"fire": 12, "water": 9, "earth": 14, "air": 7, "person": 1}
	g._engine.known_recipes.clear()
	var n := 0
	for recipe in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(recipe["a"]), String(recipe["b"]))] = true
		g._engine.inventory[String(recipe["out"])] = n % 5
		n += 1
		if n > 14:
			break
	g._engine.ether = 640
	g._workshop.unlocked = true
	g._workshop.rank = 1
	g._workshop.materialize_lines()
	var targets: Array = []
	for item in g._engine.inventory:
		if g._workshop.known_target_recipe(String(item)):
			targets.append(String(item))
	if not g._workshop.lines.is_empty() and targets.size() > 1:
		var line_id := String(g._workshop.lines[0]["id"])
		g._workshop.enqueue(line_id, {"target": targets[0], "mode": "batch", "amount": 3})
		g._workshop.enqueue(line_id, {"target": targets[1], "mode": "stock", "amount": 5})
		g._workshop.lines[0]["phase_seconds"] = 14.0
		if g._workshop.lines.size() > 1:
			g._workshop.enqueue(String(g._workshop.lines[1]["id"]), {"target": targets[2] if targets.size() > 2 else targets[0], "mode": "batch", "amount": 2})
			g._workshop.lines[1]["paused"] = true
	if g._pages._workshop_view != null:
		g._pages._workshop_view.refresh()


func _scroll_of(node: Node) -> ScrollContainer:
	var n := node
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func _settle() -> void:
	for _i in 6:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := output_dir.path_join(file_name + ".png")
	image.save_png(path if path.is_absolute_path() else ProjectSettings.globalize_path(path))
	print("WORKSHOP_CAPTURE ", path)


## Диагностика переполнения по ширине: узлы, чей минимум шире родителя.
func _dump_widths(root: Control, tag: String, screen_w: int) -> void:
	print("WIDTH %s screen=%d view=%.0f min=%.0f" % [tag, screen_w, root.size.x, root.get_combined_minimum_size().x])
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and (c as Control).is_visible_in_tree():
				var cc := c as Control
				var m := cc.get_combined_minimum_size().x
				if screen_w < 400 and m > 200.0:
					print("  WIDE %s min=%.0f size=%.0f" % [str(root.get_path_to(cc)), m, cc.size.x])
				stack.append(cc)
