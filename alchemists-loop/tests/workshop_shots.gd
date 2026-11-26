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
		if scroll != null:
			scroll.scroll_vertical = 100000
			await _settle()
			await _capture("workshop-queue-%dx%d" % [dimensions.x, dimensions.y])
		view._set_composer(0, true)
		await _settle()
		if scroll != null:
			var composer: Control = view._cards[0]["composer"]
			scroll.scroll_vertical = int(composer.global_position.y - scroll.global_position.y + scroll.scroll_vertical - 60.0)
			await _settle()
		await _capture("workshop-compose-%dx%d" % [dimensions.x, dimensions.y])
		if scroll != null:
			scroll.scroll_vertical = 100000
			await _settle()
			await _capture("workshop-compose-end-%dx%d" % [dimensions.x, dimensions.y])
		view._set_composer(0, false)
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
