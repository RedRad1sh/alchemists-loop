extends Node

var g: Game
var output_dir := "user://ui_consistency_shots"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	g = load("res://main.tscn").instantiate() as Game
	g.SAVE_PATH = "user://alchemy_ui_consistency_shots.json"
	g.TEMP_PATH = "user://alchemy_ui_consistency_shots.tmp"
	g.BACKUP_PATH = "user://alchemy_ui_consistency_shots.bak"
	add_child(g)
	g._saves._save_frozen = true
	g._online._net_enabled = false
	g.set_process(false)
	await _settle()
	g._shop._close_consent()
	g._popup.hide()
	g._confirm.hide()
	g._saves._return_popup.hide()
	g._saves._return_dim.hide()
	Selftest._total = 0
	Selftest._fails = 0
	await load("res://tests/suite_navigation_fixes.gd")._check_bottom_tab_consistency(g)
	g._social._seed_demo()
	var original_scale := get_window().content_scale_size
	var original_size := get_window().size
	for dimensions in [Vector2i(540, 960), Vector2i(360, 800)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		for tab in ["world", "tools", "rating", "friends"]:
			g._bottom_nav._on_pressed(tab)
			await _settle()
			await _capture("%s-%dx%d" % [tab, dimensions.x, dimensions.y])
	get_window().content_scale_size = original_scale
	get_window().size = original_size
	g._bottom_nav._on_pressed("lab")
	await _settle()
	await _capture("hud-rest")
	var buttons := [g.find_child("EtherChip", true, false), g._hub._up_btn, g.find_child("ShopBtn", true, false)]
	for button in buttons:
		button.button_down.emit()
		var press := button.get_meta("press_tween", null) as Tween
		if press != null and press.is_valid():
			press.pause()
			press.custom_step(0.06)
	await _capture("hud-press")
	for button in buttons:
		button.button_up.emit()
		var back := button.get_meta("press_tween", null) as Tween
		if back != null and back.is_valid():
			back.pause()
			back.custom_step(0.16)
	await _capture("hud-back")
	print("UI_CONSISTENCY ", Selftest._total - Selftest._fails, "/", Selftest._total, " failures=", Selftest._fails)
	get_tree().quit(0 if Selftest._fails == 0 else 1)

func _settle() -> void:
	for frame in 4:
		await get_tree().process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := output_dir.path_join(label + ".png")
	var result := image.save_png(path)
	Selftest.check("capture saved " + label, result == OK)
	print("UI_CAPTURE ", ProjectSettings.globalize_path(path), " size=", image.get_size())
