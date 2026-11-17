extends Node
## Оконная приёмка Task 7: настоящий экран реторты, стадии формы 0/3/5.
## Запуск: Godot --path . --scene res://tests/retort_shots.tscn

var _game: Game
var _layout_lines := PackedStringArray()
var _layout_narrow := 0

func _ready() -> void:
	_game = load("res://main.tscn").instantiate() as Game
	if _game == null:
		push_error("RETORT-SHOTS: main.tscn не инстанцируется")
		get_tree().quit(1)
		return
	_game.SAVE_PATH = "user://alchemy_retort_shots.json"
	_game.TEMP_PATH = "user://alchemy_retort_shots.tmp"
	_game.BACKUP_PATH = "user://alchemy_retort_shots.bak"
	add_child(_game)
	_game._saves._save_frozen = true
	_game._online._net_enabled = false
	_game.set_process(false)
	Net.set_process(false)
	Net.base_url = ""
	Net._available = false
	for i in 3:
		await get_tree().process_frame
	if _game._shop != null and _game._shop.has_method("_close_consent"):
		_game._shop._close_consent()
	if _game._popup != null:
		_game._popup.visible = false
	if _game._confirm != null:
		_game._confirm.visible = false
	if _game._saves._return_popup != null:
		_game._saves._return_popup.visible = false
	if _game._saves._return_dim != null:
		_game._saves._return_dim.visible = false
	# Реторта открывается после 10 веществ: _ensure_modes не строит её страницу
	# на пустом новом мире, поэтому сначала даём реальный минимум открытий.
	for raw_id in _game.ITEMS:
		_game._engine.inventory[String(raw_id)] = 1
		if _game._engine.inventory.size() >= 12:
			break
	_game._pages._ensure_modes()
	_game._demo_open_device("retort")
	if not _game._pages._mode_pages.has("retort") or _game._screens.key() != "retort":
		push_error("RETORT-SHOTS: реальная страница реторты не открылась")
		get_tree().quit(1)
		return

	var stages := [
		{"stage": 0, "levels": {}},
		{"stage": 3, "levels": {"queue": 2, "offline": 2, "slots": 2, "speed": 2, "complexity": 3, "blend": 1, "cap": 2, "equip": 0}},
		{"stage": 5, "levels": {"queue": 4, "offline": 4, "slots": 3, "speed": 4, "complexity": 5, "blend": 3, "cap": 3, "equip": 2}},
	]
	for entry in stages:
		for axis in _game._retort._cube_levels:
			_game._retort._cube_levels[axis] = int((entry["levels"] as Dictionary).get(axis, 0))
		_game._retort._refresh_retort_page()
		var actual := RetortSprite.form_stage(_game._retort._cube_levels)
		if actual != int(entry["stage"]):
			push_error("RETORT-SHOTS: неверная стадия %d != %d" % [actual, int(entry["stage"])])
			get_tree().quit(1)
			return
		for i in 3:
			await get_tree().process_frame
		await _capture("retort_stage_%d" % actual)

	# Batch F: наполненные данные и отдельный кадр каждой подстраницы.
	for id in ["fire-0", "water-0", "earth-2", "fire-3", "fire-4", "blend-fire"]:
		_game._retort._essence_add(id, 7)
	_game._retort.queue_set([{"sub": "fire"}, {"sub": "water"}])
	_game._retort._open_queue_picker()
	_game._retort._on_retort_pick("earth")
	if _game._retort._queue != [{"sub": "fire"}, {"sub": "water"}, {"sub": "earth"}]:
		push_error("RETORT-SHOTS: пикер не добавил вещество в программу")
		get_tree().quit(1)
		return
	var full_program: Array = []
	for sub in ["fire", "water", "earth", "fire", "water", "earth"]:
		full_program.append({"sub": sub})
	if not _game._retort.queue_set(full_program):
		push_error("RETORT-SHOTS: программа из шести шагов не поместилась")
		get_tree().quit(1)
		return
	_game._retort.queue_toggle(true)
	var now := Time.get_unix_time_from_system()
	_game._retort._retort_slots[0] = {"sub": "fire", "name": "Огонь", "essence": "fire-0", "tier": 0, "started": now - 100.0, "dur": 1.0}
	_game._retort._retort_slots[1] = {"sub": "water", "name": "Вода", "essence": "water-0", "tier": 0, "started": now, "dur": 28800.0}
	_game._retort._blend = {"out": "blend-fire", "started": now - 100.0, "dur": 1.0}
	_game._retort._refresh_retort_page()
	_game._retort._select_retort_tab("queue", false)
	for i in 4:
		await get_tree().process_frame
	var queue_rail := _game._retort._queue_flow.get_parent() as ScrollContainer
	var tap_ok := await _exercise_queue_tap(queue_rail, 1)
	print("RETORT-QUEUE-TAP ok=%s" % str(tap_ok))
	if not tap_ok:
		get_tree().quit(1)
		return
	for i in 4:
		await get_tree().process_frame
	var swipe_ok := await _exercise_queue_swipe(queue_rail)
	print("RETORT-QUEUE-SWIPE ok=%s scroll=%d" % [str(swipe_ok), queue_rail.scroll_horizontal])
	if not swipe_ok:
		get_tree().quit(1)
		return
	queue_rail.scroll_horizontal = 0
	var page := _game._pages._mode_pages.get("retort") as VBoxContainer
	for tab in ["cube", "essences", "tree", "queue"]:
		_game._retort._select_retort_tab(tab, false)
		if page != null and page.get_parent() != null and page.get_parent().get_parent() is ScrollContainer:
			(page.get_parent().get_parent() as ScrollContainer).scroll_vertical = 0
		for i in 4:
			await get_tree().process_frame
		await _capture("retort_tab_" + tab)
		_dump_layout(_game, tab)
	_write_layout_dump()
	print("RETORT-SHOTS done")
	get_tree().quit(0)

func _exercise_queue_tap(rail: ScrollContainer, index: int) -> bool:
	var at := rail.get_global_rect().position + Vector2(float(index) * 104.0 + 52.0, 60.0)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = at
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = at
	get_viewport().push_input(release, true)
	for i in 2:
		await get_tree().process_frame
	return _game._retort._queue_selected == index


func _exercise_queue_swipe(rail: ScrollContainer) -> bool:
	var bar := rail.get_h_scroll_bar()
	if bar.max_value <= bar.page:
		return false
	var center := rail.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = center
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var motion := InputEventScreenDrag.new()
	motion.index = 0
	motion.position = center + Vector2(-96, 0)
	motion.relative = Vector2(-96, 0)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = motion.position
	get_viewport().push_input(release, true)
	for i in 4:
		await get_tree().process_frame
	return rail.scroll_horizontal > 0


func _capture(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://previews/%s.png" % stem
	var err := image.save_png(path)
	print("RETORT-SHOT stem=%s size=%dx%d err=%d path=%s" % [stem, image.get_width(), image.get_height(), err, ProjectSettings.globalize_path(path)])
	if err != OK:
		get_tree().quit(1)

func _dump_layout(root: Node, tab: String) -> void:
	var lines := PackedStringArray()
	var stats := {"narrow": 0}
	_dump_node(root, lines, stats)
	_layout_lines.append("TAB=" + tab)
	_layout_lines.append_array(lines)
	_layout_narrow += int(stats["narrow"])


func _write_layout_dump() -> void:
	_layout_lines.append("NARROW_BUTTONS=%d" % _layout_narrow)
	var file := FileAccess.open("res://previews/retort_v2_layout.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_layout_lines))
		file.close()
	print("RETORT-LAYOUT narrow_buttons=%d path=%s" % [_layout_narrow, ProjectSettings.globalize_path("res://previews/retort_v2_layout.txt")])

func _dump_node(node: Node, lines: PackedStringArray, stats: Dictionary) -> void:
	if node is Button or node is OptionButton:
		var control := node as Control
		var text := String(node.get("text")) if node is Button else "OptionButton"
		lines.append("%s text=\"%s\" size=%.1fx%.1f visible=%s" % [node.get_class(), text, control.size.x, control.size.y, str(control.is_visible_in_tree())])
		if control.is_visible_in_tree() and control.size.x < 40.0:
			stats["narrow"] = int(stats["narrow"]) + 1
	for child in node.get_children():
		_dump_node(child, lines, stats)
