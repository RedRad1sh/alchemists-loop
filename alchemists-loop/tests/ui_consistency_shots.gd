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
	g._online._target_state = {
		"id": "pt-ui-shot-target", "kind": "llm", "name": "Скрытая цель",
		"hint": "Соедини привычное с неожиданным.", "status": "active",
		"successful_steps": 2, "spent_ether": 34, "generation": 1,
	}
	g._online._target_view_state = ""
	g._online._render_personal_target_state()
	var original_scale := get_window().content_scale_size
	var original_size := get_window().size
	for dimensions in [Vector2i(540, 960), Vector2i(360, 800)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		for tab in ["world", "tools", "rating", "friends"]:
			g._bottom_nav._on_pressed(tab)
			await _settle()
			await _capture("%s-%dx%d" % [tab, dimensions.x, dimensions.y])
		g._screens.close()
		g._social_ui.close()
		g._tabs_ref.current_tab = Game.TAB_EXPERIMENT
		await _settle()
		g._online._target_view_state = ""
		g._online._render_personal_target_state()
		await _capture("experiment-room-%dx%d" % [dimensions.x, dimensions.y])
		g._pages._open_cauldron_screen()
		await _settle()
		g._online._target_view_state = ""
		g._online._render_personal_target_state()
		var target_rect := g._pages._experiment_target_card.get_global_rect()
		var pot_rect := g._pages._experiment_cauldron.get_global_rect()
		var recipe_rect := g._pages._experiment_recipe_line.get_global_rect()
		var clear_rect := g._pages._experiment_clear_button.get_global_rect()
		var viewport_rect := get_viewport().get_visible_rect()
		Selftest.check("personal target card and cauldron fit %dx%d" % [dimensions.x, dimensions.y],
			viewport_rect.encloses(target_rect) and viewport_rect.encloses(pot_rect)
			and target_rect.end.y <= pot_rect.position.y)
		Selftest.check("personal target ribbon leaves cauldron controls clear %dx%d" % [dimensions.x, dimensions.y],
			not target_rect.intersects(recipe_rect) and not target_rect.intersects(clear_rect))
		await _capture("experiment-cauldron-%dx%d" % [dimensions.x, dimensions.y])
		for part_name in ["PersonalTargetCard", "TargetHead", "TargetName", "TargetState", "TargetDetailsButton", "TargetSeal"]:
			var part := g._pages._experiment_field.find_child(part_name, true, false) as Control
			if part != null:
				var part_text := ""
				if part is Label:
					part_text = (part as Label).text
				print("UI_GEOM ", part_name, " rect=", part.get_global_rect(), " visible=", part.is_visible_in_tree(), " text=", part_text)
		var details_toggle := g._pages._experiment_field.find_child("TargetDetailsButton", true, false) as Button
		var details := g._pages._experiment_field.find_child("TargetDetails", true, false) as Control
		print("UI_DETAILS_BEFORE ", dimensions, " rect=", details.get_global_rect(), " min=", details.get_combined_minimum_size(),
				" offsets=", details.offset_left, ",", details.offset_top, ",", details.offset_right, ",", details.offset_bottom)
		if details_toggle != null and details != null:
			details_toggle.pressed.emit()
			await _settle()
			for part_name in ["TargetDetails", "TargetHint", "TargetStats", "IconCenter"]:
				var part := g._pages._experiment_field.find_child(part_name, true, false) as Control
				if part != null:
					print("UI_GEOM ", part_name, " rect=", part.get_global_rect(), " min=", part.get_combined_minimum_size(),
						" visible=", part.is_visible_in_tree(), " anchors=", part.anchor_left, ",", part.anchor_top, ",", part.anchor_right, ",", part.anchor_bottom,
						" offsets=", part.offset_left, ",", part.offset_top, ",", part.offset_right, ",", part.offset_bottom,
						" flags=", part.size_flags_horizontal, ",", part.size_flags_vertical)
			Selftest.check("personal target details stay compact %dx%d" % [dimensions.x, dimensions.y],
				details.visible and viewport_rect.encloses(details.get_global_rect())
					and absf(details.size.y - g._pages.TARGET_DETAILS_H) <= 0.5)
			await _capture("experiment-details-%dx%d" % [dimensions.x, dimensions.y])
			details_toggle.pressed.emit()
			await _settle()
		g._screens.close()
		await _settle()
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
