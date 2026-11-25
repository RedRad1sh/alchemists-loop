extends Node
## Кадры консистентности нижних вкладок и расширенная приёмка social/news.
## Запуск (ОКНО, не --headless):
##   "<Godot_console.exe>" --path . --scene res://tests/ui_consistency_shots.tscn
##   [-- --capture-dir=C:/path/to/captures]

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

	# Дополнительные кадры тех же вкладок с именами из расширенной приёмки.
	g._bottom_nav._on_pressed("world")
	await _settle()
	await _capture("consistency-world")
	g._bottom_nav._on_pressed("tools")
	await _settle()
	await _capture("consistency-tools")
	g._bottom_nav._on_pressed("rating")
	await _settle()
	await _capture("consistency-rating")
	g._bottom_nav._on_pressed("friends")
	await _settle()
	await _capture("consistency-friends")

	# Переработка мессенджинга: атрибуция превью в списке, плашка шапки и
	# футеры ленты, стикер + pending, пикер эмодзи/стикеров, честный поиск.
	g._social.on_inbox({"ok": true, "friends": [
		{"device_id": "npc-spirit", "nick": "Светик", "unread": 0, "avatar": {},
			"last_seen": "", "last_msg_preview": "Я рядом, если что", "last_msg_from_me": false},
		{"device_id": "dev-b", "nick": "Николя", "unread": 2, "avatar": {},
			"last_seen": "2026-10-10T07:10:00", "last_msg_preview": "го к котлу", "last_msg_from_me": true},
		{"device_id": "dev-c", "nick": "Аня", "unread": 0, "avatar": {},
			"last_seen": "2026-10-09T21:00:00", "last_msg_preview": "Скинула печать, забери", "last_msg_from_me": false}],
		"incoming": [], "outgoing": [], "unread_total": 2, "requests_total": 0})
	g._social_ui._refresh_list()
	await _settle()
	await _capture("msg-list")
	g._social_ui._open_thread("dev-b")
	await _settle()
	await _capture("msg-thread")
	g._social.optimistic_send("dev-b", "ещё одно")
	var rows: Array = g._social.threads["dev-b"]
	rows.append({"id": 14, "from_me": true, "body": Social.sticker_body("hi"),
		"sent_at": "2026-10-10T07:20:00"})
	g._social_ui.refresh_thread()
	await _settle()
	var tsc := g._social_ui._thread_scroll
	tsc.scroll_vertical = int(tsc.get_v_scroll_bar().max_value)
	await _settle()
	await _capture("msg-sticker-pending")
	g._social.optimistic.erase("dev-b")
	g._social._seed_demo()
	g._social_ui.refresh_thread()
	await _settle()
	var pick_b := g._social_ui._body.find_child("PickerBtn", true, false) as Button
	if pick_b != null:
		pick_b.pressed.emit()
		await _settle()
		await _capture("msg-picker-emoji")
		var seg := g._social_ui._body.find_child("PickerSegments", true, false)
		if seg != null and seg.get_child_count() == 2:
			(seg.get_child(1) as Button).pressed.emit()
			await _settle()
			await _capture("msg-picker-stickers")
		g._social_ui._picker_hide()
	g._social_ui._close_thread()
	await _settle()
	g._social_ui._pending_search_nick = "Несуществующий"
	g._social_ui._err_line.text = "Ищем алхимика…"
	Net.house_result.emit({"ok": true, "found": false, "nick": "Несуществующий", "avatar": {}})
	await _settle()
	await _capture("msg-search-notfound")

	# Клик-анимация шапки и кнопок на цепях.
	g._bottom_nav._on_pressed("lab")
	await _settle()
	await _capture("hud-rest")
	var buttons := [g.find_child("EtherChip", true, false), g._hub._up_btn, g.find_child("ShopBtn", true, false)]
	for button in buttons:
		if button == null:
			continue
		button.button_down.emit()
		var press := button.get_meta("press_tween", null) as Tween
		if press != null and press.is_valid():
			press.pause()
			press.custom_step(0.06)
	await _capture("hud-press")
	for button in buttons:
		if button == null:
			continue
		button.button_up.emit()
		var back := button.get_meta("press_tween", null) as Tween
		if back != null and back.is_valid():
			back.pause()
			back.custom_step(0.16)
	await _capture("hud-back")

	# Новости «Алхимического вестника»: сидированный RSS → модалка → статья;
	# битый ответ → error-состояние с «Повторить». Сеть не трогаем.
	g._bottom_nav._on_pressed("tools")
	await _settle()
	g._open_news()
	await _settle()
	var news_rss := """<?xml version="1.0" encoding="UTF-8"?>
	<rss version="2.0"><channel><title>Алхимический вестник</title>
	<item><title>Ротация печатей у родника</title><description>Смотрители сменили печати у родника: серная ушла на покой, медная приняла вахту. Вода отзывается на новые знаки чуть теплее обычного.</description><content:encoded># Вахта печатей

Смотрители сменили печати у родника: **серная** ушла на покой, **медная** приняла вахту.

- вода отзывается на новые знаки чуть теплее
- медь даёт двойные очки до воскресенья

&gt; Берегите эфир: подсказки экономят часы.

![Печать родника](/api/news/images/1)</content:encoded><pubDate>Wed, 12 Nov 2026 09:00:00 +0000</pubDate><guid>news-1</guid><category>родник</category></item>
	<item><title>Найдена редкая пара: эфир и соль</title><description>Алхимик из северной мастерской сообщил о находке: эфир и соль дают устойчивый светящийся осадок. Гильдия просит присылать образцы котлов.</description><pubDate>Mon, 10 Nov 2026 18:30:00 +0000</pubDate><guid>news-2</guid><category>находки</category></item>
	<item><title>Ярмарка обменов открывается в пятницу</title><description>В пятницу у старой печи откроется ярмарка обменов. Приносите лишние печати и склянки — меняем без пошлины, по-честному.</description><pubDate>Sat, 08 Nov 2026 12:00:00 +0000</pubDate><guid>news-3</guid><category>события</category></item>
	<item><title>Светик советует: не жалейте эфира на подсказки</title><description>Дух родника напоминает: эфир копится сам, а подсказки экономят часы.</description><pubDate>Wed, 05 Nov 2026 08:00:00 +0000</pubDate><guid>news-4</guid><category>советы</category></item>
	</channel></rss>"""
	g._news_ui.seed_rss(news_rss)
	await _settle()
	await _capture("news-modal")
	var sticker := load("res://assets/spirits/stickers_512/hi.png") as Texture2D
	if sticker != null:
		News.save_cached("/api/news/images/1", sticker.get_image())
	var card0 := g._news_ui._cards.find_child("NewsCard_0", true, false) as Control
	if card0 != null:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		card0.gui_input.emit(ev)
	await _settle()
	await _capture("news-article")
	g._news_ui._close_article()
	await _settle()
	g._news_ui.seed_error()
	await _settle()
	await _capture("news-error")
	g._news_ui.close()
	await _settle()
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
