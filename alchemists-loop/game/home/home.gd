extends RefCounted
class_name Home
# Полноэкранный дом: RoomView, лоток обстановки, Светик, палитра и гости.
# Экономика и социальные действия остаются в существующих модулях.

var g: Game

var _cosmetic_theme := "cobalt"
var _cosmetic_aura := "amber"
var _cosmetic_house := false
var _theme_btns := {}
var _aura_btns := {}
var _house_btn: Button = null
var _house_screen: Control = null
var house_tasks_done: Array = []   # β: id выполненных поручений (одноразовые, без таймеров)
var house_unlocked: Array = []     # β: id разблокированных предметов (награды поручений)
var house_placements: Array[Dictionary] = []   # β: расстановка в метрах (раскладка B)
var _task_rows := {}               # id -> Label строки на странице дома
var house_visited_day: Dictionary = {}   # γ: nick -> "YYYY-MM-DD" (локальный кэш кнопки)
var house_gift_week := ""                # γ: ISO-неделя последнего недельного подарка хосту
var house_gift_count := 0                # γ: подарков уже выдано на текущей неделе
var _guests_lbl: Label = null            # γ: строка о гостях на странице дома
var _guests_row: HBoxContainer = null    # S1 (задача 7): кнопки «в друзья» у гостей из house_visitors
var _house_visit_btn: Button = null      # γ: кнопка визита в гостевом попапе (собирается один раз)
var _house_popup_nick := ""              # γ: чей домик сейчас открыт в гостевом попапе
var _theme_custom_on := false
var _theme_custom := Color("#0d1219")
var _aura_custom_on := false
var _aura_custom := Color("#ffb85c")
## WHITE = родной albedo GLB: `RoomBuilder.tint_room` при белом тоне не трогает
## материал. Прежние коричневые дефолты перемножались с альбедо и затемняли
## стены/пол у всех, кто косметику не покупал.
var _cosmetic_wall := Color.WHITE
var _cosmetic_floor := Color.WHITE
var _wall_btn: Button = null
var _floor_btn: Button = null
var _floor_mat := "planks"
var _wall_mat := "timber"
var _mat_btns := {}  # "floor:<id>"/"wall:<id>" -> Button
var _color_picker: Control = null
var _color_target := ""
var _cp_swatch: PanelContainer = null
var _cp_r: HSlider = null
var _cp_g: HSlider = null
var _cp_b: HSlider = null
var _cp_hex: Label = null
var _cp_ok: Button = null
var _cp_old := Color.WHITE  # значение до открытия пикера (для отката)
var _cp_old_on := false  # был ли кастом включён (theme/aura)
var _custom_unlocked: Dictionary = {}  # цель -> true (разблокировка куплена)
var _house_popup: Control = null
var _house_popup_view: RoomView = null
var _house_popup_title: Label = null

var _house_room: RoomView = null
var _house_toolbar: HBoxContainer
var _house_flip_btn: Button
var _house_remove_btn: Button
var _card_press := {}
var _house_overlay: Control = null
var _house_tray: PanelContainer = null
var _house_tray_open := false
var _house_decor_tab: VBoxContainer = null
var _house_spirit_tab: VBoxContainer = null
var _house_cozy_tab: VBoxContainer = null
var _house_tab_scrolls := {}
var _house_tab_btns := {}
var _house_cards: HBoxContainer = null
var _house_cat_btns := {}
var _shop_cat := "window"
var _house_collection_lbl: Label = null
var _house_spirit_node = null  # существующий Companion: аура, уровень, сердечки
var _house_spirit_t := 0.0
var _house_spirit_lean := 0.0
var _house_affinity_lbl: Label = null
var _house_lift_tween: Tween = null
var _house_editor_ui: Control = null
var _house_bottom: HBoxContainer = null
var _house_hint_panel: PanelContainer = null
var _house_hint_lbl: Label = null
var _house_hint_touch := DisplayServer.is_touchscreen_available()
var _house_hint_until := 0
var _house_tray_progress := 0.0
var _house_landscape := false
var _house_ui_size := Vector2.ZERO
var _house_ui_scale := 0.0
var _house_cards_scroll: ScrollContainer = null
var _house_tray_fixed_min := 0.0
var _house_tray_cards_min := 0.0
var _house_tray_k := 1.0
var _host_showcase_lbl: Label = null
var _host_flame: Polygon2D = null
var _host_spirit = null


func _open_house_tray() -> void:
	if not _cosmetic_house:
		_show_house_hint("Сначала построй домик Светика.")
		Sfx.error()
		return
	_house_room.cancel_ghost()
	_card_press.clear()
	_house_tray_open = true
	_house_tray.visible = true
	_refresh_house_tray()
	_layout_house_editor()
	_animate_house_tray(1.0)
	_refresh_house_hint()
	Sfx.click()


func _house_tray_room_rect() -> Rect2:
	return _house_room.get_global_transform().affine_inverse() * _house_tray.get_global_rect()


func _set_house_tray_progress(value: float) -> void:
	_house_tray_progress = value
	if _house_tray == null or _house_editor_ui == null:
		return
	_house_tray.position = Vector2((_house_editor_ui.size.x - _house_tray.size.x) * 0.5,
		_house_editor_ui.size.y - _house_tray.size.y * value)
	var top_px := (_house_hint_panel.position.y + _house_hint_panel.size.y + 12.0) * _house_ui_scale
	_house_room.set_tray_lift(_house_tray_room_rect().size.y * 0.5 * value, top_px * value)
	if _house_bottom != null:
		_house_bottom.visible = not _house_tray_open and is_zero_approx(value)
	if _house_toolbar != null:
		# Пока лоток закрыт, тулбар стоит над «Обстановкой»; открытый лоток
		# поднимает его над своей кромкой, чтобы кнопки оставались доступны.
		_house_toolbar.offset_bottom = -maxf(68.0, _house_tray.size.y * value + 8.0)
		_house_toolbar.offset_top = _house_toolbar.offset_bottom - 48.0


func _lift_house_room() -> void:
	_set_house_tray_progress(_house_tray_progress)


func _animate_house_tray(to: float) -> void:
	if _house_lift_tween != null:
		_house_lift_tween.kill()
	_house_lift_tween = g.create_tween()
	_house_lift_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_house_lift_tween.tween_method(_set_house_tray_progress, _house_tray_progress, to, 0.18)
	if is_zero_approx(to):
		_house_lift_tween.tween_callback(func() -> void:
			_house_tray.visible = false
			_on_house_selection(_house_room.selected_index()))


func _close_house_tray(immediate := false) -> void:
	_house_tray_open = false
	_card_press.clear()
	if _house_room != null:
		_house_room.cancel_ghost()
	if _house_tray != null:
		if immediate or not _house_tray.visible:
			if _house_lift_tween != null:
				_house_lift_tween.kill()
				_house_lift_tween = null
			_set_house_tray_progress(0.0)
			_house_tray.visible = false
		else:
			_animate_house_tray(0.0)
	if _house_room != null:
		_on_house_selection(_house_room.selected_index())
	_refresh_house_hint()
	Sfx.click()


func _toggle_house_tray() -> void:
	if _house_tray_open:
		_close_house_tray()
	else:
		_open_house_tray()


func _buy_house_item(id: String) -> bool:
	if not _cosmetic_house or not HouseItems.exists(id):
		return false
	var item := HouseItems.get_item(id)
	if bool(item.get("reward", false)) or house_unlocked.has(id):
		return false
	var cost := int(item.get("cost", 0))
	if g._engine._available_ether() < cost:
		_show_house_hint("Не хватает эфира: «%s» стоит %d." % [String(item["label"]), cost])
		Sfx.error()
		return false
	g._engine._spend_ether(cost)
	_unlock_item(id)
	_refresh_house_tray()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	_show_house_hint("«%s» куплено. Можно поставить." % String(item["label"]))
	_house_react("charged")
	Sfx.stage_up()
	return true


func _on_room_placement(p: Dictionary) -> bool:
	if not _cosmetic_house or not house_unlocked.has(String(p.get("id", ""))):
		return false
	if house_placements.size() >= HouseLayout.MAX_ITEMS:
		_show_house_hint("В комнате тесно: больше %d предметов не влезет." % HouseLayout.MAX_ITEMS)
		Sfx.error()
		return false
	var clean := Placement.snap_record(p)
	if not Placement.valid(clean, house_placements):
		_show_house_hint("Здесь не помещается.")
		Sfx.error()
		return false
	house_placements.append(clean)
	_house_room.set_layout(house_placements)
	_check_house_tasks()
	_refresh_house_tray()
	g._saves._save_game()
	_upload_house()
	return true


func _place_from_tray(id: String) -> void:
	_start_tray_placement(id, _house_room.get_local_mouse_position())


func _start_tray_placement(id: String, at: Vector2, pointer := TouchDrag.NO_POINTER) -> void:
	if not _cosmetic_house or not house_unlocked.has(id) or _house_room.read_only:
		return
	if house_placements.size() >= HouseLayout.MAX_ITEMS:
		_show_house_hint("В комнате тесно: больше %d предметов не влезет." % HouseLayout.MAX_ITEMS)
		_house_react("sad_soft")
		return
	var return_y := _house_tray_room_rect().position.y
	_close_house_tray(true)
	_house_hint_until = 0
	_house_room.tray_return_y = return_y
	_house_room.begin_placement(id, at, pointer)
	_refresh_house_hint()


func _on_card_input(event: InputEvent, id: String, picture: Control) -> void:
	if not house_unlocked.has(id) or not _house_tray_open:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	var at: Vector2 = picture.get_global_transform_with_canvas() * event.position
	at = _house_room.get_global_transform_with_canvas().affine_inverse() * at
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_card_press = {"at": at, "pointer": TouchDrag.MOUSE_POINTER, "id": id}
		else:
			_card_press.clear()
	elif event is InputEventScreenTouch:
		if event.canceled:
			if _card_press.get("pointer", -1) == event.index:
				_card_press.clear()
		elif event.pressed and _card_press.is_empty():
			_card_press = {"at": at, "pointer": event.index, "id": id}
		elif not event.pressed and _card_press.get("pointer", -1) == event.index:
			_card_press.clear()


func _on_house_pointer_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	_house_hint_touch = event is InputEventScreenTouch or event is InputEventScreenDrag
	_refresh_house_hint()
	if _card_press.is_empty():
		return
	var pointer := int(_card_press["pointer"])
	if event is InputEventScreenTouch:
		if event.index == pointer and (event.canceled or not event.pressed):
			_card_press.clear()
		return
	if event is InputEventMouseButton:
		if pointer == TouchDrag.MOUSE_POINTER and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_card_press.clear()
		return
	if not _house_tray_open or not (event is InputEventMouseMotion or event is InputEventScreenDrag):
		return
	if event is InputEventScreenDrag and event.index != pointer:
		return
	if event is InputEventMouseMotion and pointer != TouchDrag.MOUSE_POINTER:
		return
	var local := _house_room.make_input_local(event)
	var at: Vector2 = local.position
	var delta: Vector2 = at - (_card_press["at"] as Vector2)
	var slop := TouchDrag.TAP_SLOP / _house_room.effective_screen_scale()
	if event is InputEventScreenDrag:
		# Поперечный свайп отдаём штатному ScrollContainer, не превращая его в перенос.
		if absf(delta.x) > slop and absf(delta.x) >= absf(delta.y):
			_card_press.clear()
			return
		if delta.y >= -slop or -delta.y <= absf(delta.x):
			return
	elif delta.length() <= slop:
		return
	var id := String(_card_press["id"])
	_card_press.clear()
	_start_tray_placement(id, at, pointer)
	g.get_viewport().set_input_as_handled()


func _set_shop_cat(cat: String) -> void:
	if not HouseItems.CATS.has(cat):
		return
	_shop_cat = cat
	_refresh_house_tray()


func _set_house_tab(tab: String) -> void:
	for id in _house_tab_scrolls:
		(_house_tab_scrolls[id] as Control).visible = String(id) == tab
	for id in _house_tab_btns:
		(_house_tab_btns[id] as Button).disabled = String(id) == tab
	_refresh_house_tray()


func _refresh_house_tray() -> void:
	if _house_cards != null:
		_rebuild_decor_cards()
	for cat in _house_cat_btns:
		(_house_cat_btns[cat] as Button).disabled = String(cat) == _shop_cat
	if _house_collection_lbl != null:
		_house_collection_lbl.text = "Коллекция: %d/%d · купленное ставится бесплатно" % [house_unlocked.size(), HouseItems.ITEMS.size()]
	_refresh_house_screen()


func _house_spirit_tick(delta: float) -> void:
	if _house_popup != null and _house_popup.visible and _host_spirit != null:
		_host_spirit.position = _house_popup_view.spirit_screen_pos() - _host_spirit.size * 0.5
	if _house_screen != null and _house_screen.visible:
		_layout_house_editor()
		_refresh_house_hint()
	if _house_spirit_node == null or _house_room == null or _house_screen == null or not _house_screen.visible or not _cosmetic_house:
		return
	_house_spirit_t += delta
	_house_spirit_lean = move_toward(_house_spirit_lean, 0.0, delta * 20.0)
	var base := _house_room.spirit_screen_pos()
	var breath := 1.0 + 0.035 * sin(_house_spirit_t * 2.2)
	var sway := sin(_house_spirit_t * 1.4) * 1.5
	_house_spirit_node.position = base + Vector2(sway + _house_spirit_lean, 0.0) - _house_spirit_node.size * 0.5
	_house_spirit_node.scale = Vector2(breath, 2.0 - breath)
	_house_spirit_node.rotation = deg_to_rad(_house_spirit_lean * 0.33)
	var aura := _aura_now()
	if _house_spirit_node._aura != aura:
		_house_spirit_node.set_aura(aura)

func _init(game: Game) -> void:
	g = game

func _theme_color(t: String) -> Color:
	match t:
		"ember":
			return Color("#1a0e0e")
		"moss":
			return Color("#0e1410")
		"violet":
			return Color("#120f1a")
		_:
			return Color("#0d1219")


func _aura_color(a: String) -> Color:
	match a:
		"rose":
			return Color("#ff8fb3")
		"aqua":
			return Color("#7fe0e0")
		"violet":
			return Color("#b78aff")
		"hearth":
			return Color("#ff7a2e")
		_:
			return Color("#ffb85c")


func _theme_now() -> Color:
	return _theme_custom if _theme_custom_on else _theme_color(_cosmetic_theme)


func _aura_now() -> Color:
	return _aura_custom if _aura_custom_on else _aura_color(_cosmetic_aura)


func _apply_cosmetic() -> void:
	if g._bg_rect != null:
		var c := _theme_now()
		g._bg_rect.color = Color(c.r, c.g, c.b, UIBackdrop.TINT_ALPHA)
	if g._spirit._companion != null:
		g._spirit._companion.set_aura(_aura_now())
	if _house_room != null:
		_house_room.set_room_tint(_cosmetic_wall, _cosmetic_floor, _floor_mat, _wall_mat)


func _theme_label(id: String) -> String:
	for t in Game.WORKSHOP_THEMES:
		if String(t["id"]) == id:
			return String(t["label"])
	return id


func _aura_label(id: String) -> String:
	for a in Game.WORKSHOP_AURAS:
		if String(a["id"]) == id:
			return String(a["label"])
	return id


func _theme_cost(id: String) -> int:
	for t in Game.WORKSHOP_THEMES:
		if String(t["id"]) == id:
			return int(t["cost"])
	return 0


func _aura_cost(id: String) -> int:
	for a in Game.WORKSHOP_AURAS:
		if String(a["id"]) == id:
			return int(a["cost"])
	return 0


func _showcase_bottles() -> int:
	return mini(9, maxi(0, g._progress_ui._ach_world_first))


func _showcase_flame_color() -> Color:
	# цвет самого редкого вещества в запасе: слой считает _rarity_of, цвет берём у вещества
	var best_tier := -1
	var best := Color(1.0, 0.62, 0.25)
	for raw_id in g._engine.inventory:
		var id := String(raw_id)
		if not g.ITEMS.has(id):
			continue
		var r: Dictionary = g._engine._rarity_of(id)
		if int(r["tier"]) > best_tier:
			best_tier = int(r["tier"])
			best = g._item_colors.get(id, r["color"])
	return best


func _showcase_window_caption() -> String:
	# Честность (спека §6): без связи окно показывает заглушку, а не вчерашнюю цель.
	if g._online._net_nick == "" or g._contracts._day_hint == "":
		return "цель мира — после связи"
	return "мир: " + g._contracts._day_hint


func _build_house_cozy_tab() -> void:
	var page := _house_cozy_tab
	page.add_child(_cozy_caption("Тема лаборатории (фон)"))
	var theme_grid := GridContainer.new()
	theme_grid.columns = 2
	theme_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_grid.add_theme_constant_override("h_separation", 6)
	theme_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(theme_grid)
	for th in Game.WORKSHOP_THEMES:
		var b := _option_button()
		b.pressed.connect(_buy_theme.bind(String(th["id"]), int(th["cost"])))
		theme_grid.add_child(b)
		_theme_btns[String(th["id"])] = b
	var th_c := _option_button("Палитра")
	th_c.pressed.connect(_open_color_picker.bind("theme"))
	page.add_child(th_c)
	_theme_btns["__custom"] = th_c

	page.add_child(_cozy_caption("Аура Светика"))
	var aura_grid := GridContainer.new()
	aura_grid.columns = 2
	aura_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aura_grid.add_theme_constant_override("h_separation", 6)
	aura_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(aura_grid)
	for au in Game.WORKSHOP_AURAS:
		var b := _option_button()
		b.pressed.connect(_buy_aura.bind(String(au["id"]), int(au["cost"])))
		aura_grid.add_child(b)
		_aura_btns[String(au["id"])] = b
	var au_c := _option_button("Палитра")
	au_c.pressed.connect(_open_color_picker.bind("aura"))
	page.add_child(au_c)
	_aura_btns["__custom"] = au_c

	_add_mat_grid(page, "Пол домика", "floor", Game.FLOOR_MATS)
	_add_mat_grid(page, "Стены домика", "wall", Game.WALL_MATS)

	page.add_child(_cozy_caption("Цвета домика (палитра)"))
	var home_row := HBoxContainer.new()
	home_row.add_theme_constant_override("separation", 6)
	page.add_child(home_row)
	_wall_btn = _option_button("Стены")
	_wall_btn.pressed.connect(_open_color_picker.bind("wall"))
	home_row.add_child(_wall_btn)
	_floor_btn = _option_button("Пол")
	_floor_btn.pressed.connect(_open_color_picker.bind("floor"))
	home_row.add_child(_floor_btn)

	_house_btn = _option_button("", UIStyle.GOLD)
	_house_btn.pressed.connect(_buy_house)
	page.add_child(_house_btn)


func _add_mat_grid(page: Control, title: String, kind: String, mats: Array) -> void:
	page.add_child(_cozy_caption(title))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	for m in mats:
		var b := _option_button()
		b.pressed.connect(_buy_mat.bind(kind, String(m["id"]), int(m["cost"])))
		grid.add_child(b)
		_mat_btns["%s:%s" % [kind, String(m["id"])]] = b


func _buy_mat(kind: String, id: String, cost: int) -> void:
	var current := _floor_mat if kind == "floor" else _wall_mat
	if id == current:
		return
	var key := "mat_%s_%s" % [kind, id]
	if cost > 0 and not bool(_custom_unlocked.get(key, false)):
		if g._engine._available_ether() < cost:
			g._engine.status_text = "Не хватает эфира: материал стоит %d ⚡." % cost
			Sfx.error()
			return
		g._engine._spend_ether(cost)
		_custom_unlocked[key] = true
	if kind == "floor":
		_floor_mat = id
	else:
		_wall_mat = id
	_apply_cosmetic()
	_refresh_house_screen()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	Sfx.stage_up()


func _open_workshop() -> void:
	_refresh_house_screen()
	_open_house_screen()
	Sfx.click()


func _open_house_screen() -> void:
	if _house_screen == null:
		return
	_house_screen.visible = true
	_house_room.visible = true
	# Экран дома непрозрачный и на всё окно, поэтому переводим его на device-пиксели.
	# При canvas_items ландшафт даёт узлу UI масштаб 1.778: глифы растеризуются
	# в 16 px и дважды ресемплируются, текст становится мыльным.
	g.get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_house_room.reset_camera()
	_layout_house_editor()
	_refresh_house_screen()
	if _house_tray_open:
		_lift_house_room()
	_house_spirit_tick(0.0)


func _close_house_screen() -> void:
	_close_house_tray(true)
	g.get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if _house_room != null:
		_house_room.cancel_placement()
		_house_room.visible = false
	if _house_toolbar != null:
		_house_toolbar.visible = false
	if _house_spirit_node != null:
		_house_spirit_node.set_process(false)
	if _house_screen != null:
		_house_screen.visible = false
	Sfx.click()


func _build_house_screen() -> void:
	var root := Control.new()
	root.name = "HouseScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 20
	root.add_to_group("modal_ui")
	g.add_child(root)
	_house_screen = root
	_house_room = RoomView.new()
	_house_room.name = "HouseRoom"
	_house_room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_house_room.visible = false
	_house_room.placement_requested.connect(_on_room_placement)
	_house_room.placement_moved.connect(_on_room_moved)
	_house_room.placement_removed.connect(_on_room_removed)
	_house_room.selection_changed.connect(_on_house_selection)
	_house_room.ghost_moved.connect(_on_room_ghost_moved)
	_house_room.placement_reaction.connect(func(valid: bool) -> void: _house_react("laugh" if valid else "sad_soft"))
	_house_room.hint.connect(_show_house_hint)
	_house_room.pointer_input.connect(_on_house_pointer_input)
	_house_room.placement_returned.connect(_open_house_tray)
	root.add_child(_house_room)
	_build_house_spirit(root)
	var ui := Control.new()
	ui.name = "HouseEditorUI"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ui)
	_house_editor_ui = ui
	_build_house_overlay(ui)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 12
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	var title := g._label("ДОМ СВЕТИКА", 16)
	title.add_theme_color_override("font_color", Color("#f0c987"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _ghost_button("Закрыть", Vector2(96, 40))
	close.name = "CloseHouse"
	close.pressed.connect(_close_house_screen)
	top.add_child(close)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_top = -56
	bottom.offset_bottom = -12
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	_house_bottom = bottom
	var tray_btn := _bar_button("Обстановка", Vector2(176, 44), UIStyle.GOLD)
	tray_btn.name = "OpenTray"
	tray_btn.pressed.connect(_toggle_house_tray)
	bottom.add_child(tray_btn)
	_house_hint_panel = PanelContainer.new()
	_house_hint_panel.name = "HouseHint"
	_house_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_house_hint_panel.add_theme_stylebox_override("panel", _tray_panel_style())
	ui.add_child(_house_hint_panel)
	_house_hint_lbl = g._label("", 12)
	_house_hint_lbl.set_meta("tray_font", 12)
	_house_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_house_hint_panel.add_child(_house_hint_lbl)
	_build_house_toolbar(ui)
	_layout_house_editor()
	_build_house_tray(ui)
	root.resized.connect(_layout_house_editor)
	_house_ui_size = Vector2.ZERO
	_layout_house_editor()


func _layout_house_editor() -> void:
	if _house_editor_ui == null or _house_room == null:
		return
	# Net-масштаб UI держим ровно 1.0: дробный апскейл узла размывает глифы и
	# 9-срезы текстур, поэтому инвертируем масштаб экрана без нижнего порога,
	# а физический размер шрифтов и кнопок задаёт `_house_tray_k`.
	var factor := 1.0 / _house_room.effective_screen_scale()
	var local_size := _house_screen.size / factor
	var k := clampf(minf(local_size.x, local_size.y) / 480.0, 1.0, 1.6)
	var changed := local_size != _house_ui_size or not is_equal_approx(factor, _house_ui_scale) or not is_equal_approx(k, _house_tray_k)
	if changed:
		_house_ui_size = local_size
		_house_ui_scale = factor
		_house_tray_k = k
		_house_editor_ui.scale = Vector2.ONE * factor
		_house_editor_ui.size = local_size
		_house_landscape = local_size.x > local_size.y
		_restyle_house_tray()
	if _house_hint_panel != null:
		var hint_width := minf(480.0, local_size.x - (300.0 if _house_landscape else 24.0))
		# autowrap метки считается от её ширины: без заданной минимальной ширины
		# панель в момент раскладки измеряется на ширине 1 и раздувает свою
		# минимальную высоту до сотен пикселей, после чего размер перестаёт
		# пересчитываться (панель залипает на завышенной высоте).
		_house_hint_lbl.custom_minimum_size.x = maxf(1.0, hint_width - 12.0)
		_house_hint_panel.size = Vector2(hint_width, 34.0 * _house_tray_k)
		_house_hint_panel.position = Vector2((local_size.x - _house_hint_panel.size.x) * 0.5, 14.0 if _house_landscape else 66.0)
	if _house_tray != null:
		# Лоток — 25% высоты в портрете и 36% в ландшафте (было 37%/44%): панель
		# не должна съедать экран, на котором игрок расставляет мебель.
		var fraction := clampf(local_size.y * 0.36, 186.0, 216.0) if _house_landscape else clampf(local_size.y * 0.25, 232.0, 288.0)
		if changed:
			_house_collection_lbl.visible = local_size.x >= 420.0
			# Ряд карточек не прокручивается по вертикали (палец с карточки едет в
			# комнату), поэтому ниже своей высоты он не ужмется. Хром меряем по факту:
			# собранная вручную константа «126 px шапки» недооценивала панель на 14 px,
			# и каждый кадр `_layout_house_editor` возвращал лотку высоту меньше минимума
			# содержимого — Godot раздувал её сам, а подъём комнаты оставался
			# посчитанным от устаревшей высоты.
			_house_cards_scroll.custom_minimum_size.y = 0.0
			_rebuild_decor_cards()
			_house_tray_cards_min = _house_cards.get_combined_minimum_size().y
			_house_tray_fixed_min = maxf(0.0, _house_tray.get_combined_minimum_size().y - _house_tray_cards_min)
		var height := maxf(fraction, _house_tray_fixed_min + _house_tray_cards_min)
		_house_cards_scroll.custom_minimum_size.y = maxf(0.0, height - _house_tray_fixed_min)
		# Лоток — полоса во всю ширину: центрированная панель оставляла по бокам
		# пустые поля, а справа внутри неё — мёртвую зону до «×».
		_house_tray.size = Vector2(local_size.x, height)
		_set_house_tray_progress(_house_tray_progress)


func _show_house_hint(text: String) -> void:
	g._engine.status_text = text
	if _house_hint_lbl != null:
		_house_hint_lbl.text = text
		_house_hint_until = Time.get_ticks_msec() + 3000


func _refresh_house_hint() -> void:
	if _house_hint_lbl == null:
		return
	_house_hint_panel.visible = _cosmetic_house
	if Time.get_ticks_msec() < _house_hint_until:
		return
	if _house_room._touch != null and _house_room._touch.ghost_exists():
		_house_hint_lbl.text = "Отпусти, чтобы поставить · верни вниз, чтобы отменить"
	elif _house_tray_open:
		_house_hint_lbl.text = "Листай вбок · тяни купленное вверх в комнату" if _house_hint_touch else "Тяни купленное в комнату · покупка отдельно"
	elif _house_room.selected_index() >= 0:
		# Подсказка обязана называть сами кнопки: тулбар появляется при выборе, но
		# игрок не связывал «Отразить»/«Убрать» с выбранным предметом.
		_house_hint_lbl.text = "«Отразить»/«Убрать» внизу · тяни предмет · тап мимо — снять" if _house_hint_touch else "«Отразить»/«Убрать» внизу · тяни предмет · Del — убрать"
	else:
		_house_hint_lbl.text = "Тап — выбрать · два пальца — масштаб и сдвиг" if _house_hint_touch else "Клик — выбрать · колесо — масштаб · правая кнопка — сдвиг"


func _build_house_toolbar(parent: Control) -> void:
	_house_toolbar = HBoxContainer.new()
	_house_toolbar.name = "HouseItemToolbar"
	_house_toolbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_house_toolbar.offset_left = 12
	_house_toolbar.offset_right = -12
	_house_toolbar.offset_top = -116
	_house_toolbar.offset_bottom = -68
	_house_toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_house_toolbar.add_theme_constant_override("separation", 8)
	_house_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_house_toolbar.visible = false
	parent.add_child(_house_toolbar)
	_house_flip_btn = _bar_button("Отразить", Vector2(124, 48), UIStyle.TEXT)
	_house_flip_btn.name = "HouseFlip"
	_house_flip_btn.pressed.connect(_house_room.flip_selected)
	_house_toolbar.add_child(_house_flip_btn)
	_house_remove_btn = _bar_button("Убрать", Vector2(124, 48), Color("e8907e"))
	_house_remove_btn.name = "HouseRemove"
	_house_remove_btn.pressed.connect(_house_room.remove_selected)
	_house_toolbar.add_child(_house_remove_btn)


## Кнопка поверх комнаты: то же тёмное стекло, что у лотка и подсказки; роль
## различается только цветом текста и рамки, форма у всех одна.
func _bar_button(text: String, min_size: Vector2, accent: Color) -> Button:
	var b := g._small_button(text, min_size, 0)
	b.custom_minimum_size = min_size
	var glass := Color(0.035, 0.055, 0.085, 0.94)
	var edge := Color(UIStyle.LINE.r, UIStyle.LINE.g, UIStyle.LINE.b, 0.6)
	var normal := _bar_box(glass, edge)
	var hover := _bar_box(glass.lightened(0.08), Color(accent.r, accent.g, accent.b, 0.7))
	var pressed := _bar_box(glass.darkened(0.3), accent)
	var disabled := _bar_box(Color(glass.r, glass.g, glass.b, 0.7), Color(edge.r, edge.g, edge.b, 0.3))
	disabled.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", accent.lightened(0.15))
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", accent)
	b.add_theme_color_override("font_disabled_color", Color(UIStyle.TEXT_DIM.r, UIStyle.TEXT_DIM.g, UIStyle.TEXT_DIM.b, 0.45))
	return b


func _bar_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := UIStyle.box(bg, edge, 12, 1)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	return _padded(sb, 16.0, 6.0) as StyleBoxFlat


func _on_house_selection(index: int) -> void:
	if _house_toolbar == null:
		return
	# Лоток тулбар не прячет: выбранный предмет можно отразить/убрать, не закрывая
	# обстановку; `_place_house_toolbar` поднимает его над лотком.
	var on := index >= 0 and index < house_placements.size() and _cosmetic_house and not _house_room.read_only
	_house_toolbar.visible = on
	if on:
		var item := HouseItems.get_item(String(house_placements[index]["id"]))
		_house_flip_btn.disabled = not bool(item.get("flip_ok", false))
	_refresh_house_hint()


func _on_room_moved(index: int, p: Dictionary) -> void:
	if not _cosmetic_house or index < 0 or index >= house_placements.size():
		return
	# RoomView уже снапнул и проверил именно эту запись.
	house_placements[index] = p.duplicate(true)
	_check_house_tasks()
	g._saves._save_game()
	_upload_house()
	_house_react("curious")


func _on_room_removed(index: int) -> void:
	if not _cosmetic_house or index < 0 or index >= house_placements.size():
		return
	house_placements.remove_at(index)
	_check_house_tasks()
	g._saves._save_game()
	_upload_house()


func _on_room_ghost_moved(p: Dictionary) -> void:
	var at := _house_room._camera.unproject_position(Vector3(float(p["x"]), float(p["y"]), float(p["z"]))) / _house_room._px_scale
	var displacement := at.x - _house_room.spirit_screen_pos().x
	_house_spirit_lean = clampf(displacement * 0.03, -6.0, 6.0)


func _house_react(key: String) -> void:
	if _house_spirit_node != null and _house_screen != null and _house_screen.visible:
		_house_spirit_node.set_sprite(key, 1.1)


## Панель лотка и подсказки: тёмное матовое стекло лаборатории с тенью ВВЕРХ на
## комнату. Без текстур: 9-срез доски растягивался под ширину панели и в ландшафте
## давал мыльные полосы вместо дерева. Лоток приезжает без скруглений (radius 0).
func _tray_panel_style(radius: int = 14) -> StyleBoxFlat:
	var sb := UIStyle.box(Color(0.035, 0.055, 0.085, 0.94),
		Color(UIStyle.LINE.r, UIStyle.LINE.g, UIStyle.LINE.b, 0.6), radius)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, -5)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 6.0
	return sb


## Плоская кнопка лотка: у неактивных элементов нет ни рамки, ни заливки, поэтому
## строка вкладок или чипов не превращается в частокол пилюль. Единственный громкий
## акцент — активный элемент: он же `disabled` (повторное нажатие бессмысленно), и
## его стиль — полупрозрачная золотая плашка. Базовые высота и шрифт домножаются на
## `_house_tray_k` в `_restyle_house_tray`, чтобы панель жила в пикселях экрана.
func _flat_button(text: String, base_h: float, base_font: int, role: String) -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta("tray_font", base_font)
	b.set_meta("tray_h", base_h)
	# Поля одинаковы во всех состояниях: иначе кнопка меняет ширину под курсором
	# и строка вкладок/чипов прыгает.
	var hover := _padded(UIStyle.box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0), 10.0, 2.0)
	var pressed := _padded(UIStyle.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0), 10.0, 2.0)
	b.add_theme_stylebox_override("normal", _padded(StyleBoxEmpty.new(), 10.0, 2.0))
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if role == "tab":
		var active := UIStyle.box(Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.16),
			Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.75), 0)
		b.add_theme_stylebox_override("disabled", _padded(active, 10.0, 2.0))
		b.add_theme_color_override("font_disabled_color", UIStyle.GOLD)
		b.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	else:
		b.add_theme_stylebox_override("disabled", _padded(StyleBoxEmpty.new(), 10.0, 2.0))
		b.add_theme_color_override("font_disabled_color",
			Color(UIStyle.TEXT_DIM.r, UIStyle.TEXT_DIM.g, UIStyle.TEXT_DIM.b, 0.55))
	b.add_theme_color_override("font_hover_color", UIStyle.TEXT)
	b.add_theme_color_override("font_pressed_color", UIStyle.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", UIStyle.TEXT)
	return b


static func _padded(sb: StyleBox, h: float, v: float) -> StyleBox:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## Кнопка вне лотка без заливки («Закрыть»): та же семья, что и плоские кнопки лотка.
func _ghost_button(text: String, min_size: Vector2) -> Button:
	var b := g._small_button(text, min_size, 0)
	var hover := _padded(UIStyle.box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 8), 12.0, 4.0)
	var pressed := _padded(UIStyle.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 8), 12.0, 4.0)
	b.add_theme_stylebox_override("normal", _padded(StyleBoxEmpty.new(), 12.0, 4.0))
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UIStyle.TEXT)
	b.add_theme_color_override("font_pressed_color", UIStyle.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", UIStyle.TEXT)
	return b


## Вариант выбора в «Уюте»: текущий пункт отличим от недоступного — золотая
## плашка как у активной вкладки лотка, а не тусклый disabled.
## Плитка «Уюта» живёт внутри стеклянного лотка: контур без заливки, hover —
## лёгкий свет, текущий выбор — та же золотая плашка, что у активной вкладки.
func _option_button(text := "", accent := UIStyle.TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 40
	b.set_meta("tray_font", 13)
	b.set_meta("tray_h", 40)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if g._font_semi != null:
		b.add_theme_font_override("font", g._font_semi)
	var line := Color(UIStyle.LINE.r, UIStyle.LINE.g, UIStyle.LINE.b, 0.55)
	b.add_theme_stylebox_override("normal", _option_box(Color(1, 1, 1, 0.02), line))
	b.add_theme_stylebox_override("hover", _option_box(Color(1, 1, 1, 0.07), Color(accent.r, accent.g, accent.b, 0.6)))
	var pressed := _option_box(Color(1, 1, 1, 0.12), accent)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", accent.lightened(0.15))
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", accent)
	_set_option_state(b, false)
	return b


func _option_box(bg: Color, edge: Color) -> StyleBoxFlat:
	return _padded(UIStyle.box(bg, edge, 8, 1), 10.0, 4.0) as StyleBoxFlat


func _set_option_state(b: Button, current: bool, locked := false) -> void:
	b.disabled = current or locked
	if current:
		b.add_theme_stylebox_override("disabled", _option_box(
			Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.16),
			Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.75)))
		b.add_theme_color_override("font_disabled_color", UIStyle.GOLD)
	else:
		b.add_theme_stylebox_override("disabled", _option_box(Color(0, 0, 0, 0),
			Color(UIStyle.LINE.r, UIStyle.LINE.g, UIStyle.LINE.b, 0.25)))
		b.add_theme_color_override("font_disabled_color",
			Color(UIStyle.TEXT_DIM.r, UIStyle.TEXT_DIM.g, UIStyle.TEXT_DIM.b, 0.5))


func _cozy_caption(text: String) -> Label:
	var l: Label = g._label(text, 12)
	l.set_meta("tray_font", 12)
	l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	return l


## Применяет `_house_tray_k` к шрифтам и высотам, помеченным метами в `_flat_button`
## и билдерах: раскладка пересобирается только при смене размера/ориентации/масштаба.
func _restyle_house_tray() -> void:
	if _house_editor_ui == null:
		return
	for node in _house_editor_ui.find_children("*", "Control", true, false):
		if node.has_meta("tray_font"):
			node.add_theme_font_size_override("font_size", maxi(9, roundi(float(node.get_meta("tray_font")) * _house_tray_k)))
		if node.has_meta("tray_h"):
			node.custom_minimum_size.y = float(node.get_meta("tray_h")) * _house_tray_k


func _build_house_overlay(parent: Control) -> void:
	var center := CenterContainer.new()
	center.name = "HouseBuildOverlay"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	_house_overlay = center
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(320, 0)
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	var cap := g._label("Домик Светика ещё не построен", 16)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	var b := g._small_button("Построить домик (−%d ⚡)" % Game.HOUSE_COST, Vector2(280, 52), 2)
	b.name = "BuildHouse"
	b.pressed.connect(_buy_house)
	vb.add_child(b)


func _build_house_tray(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "HouseTray"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _tray_panel_style(0))
	parent.add_child(panel)
	_house_tray = panel
	panel.resized.connect(_lift_house_room)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	col.add_child(header)
	var tab_scroll := ScrollContainer.new()
	tab_scroll.name = "TrayTabs"
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tab_scroll)
	var tabs := HBoxContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tabs)
	_house_collection_lbl = g._label("", 11)
	_house_collection_lbl.set_meta("tray_font", 11)
	_house_collection_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_house_collection_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_house_collection_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_house_collection_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_house_collection_lbl)
	var close := _flat_button("×", 30, 16, "link")
	close.name = "CloseTray"
	close.tooltip_text = "Закрыть обстановку"
	close.custom_minimum_size.x = 30.0
	close.pressed.connect(_close_house_tray)
	header.add_child(close)
	for t in [["decor", "Обстановка"], ["spirit", "Светик"], ["cozy", "Уют"]]:
		var id := String(t[0])
		var b := _flat_button(String(t[1]), 30, 13, "tab")
		b.name = "Tab_" + id
		b.pressed.connect(_set_house_tab.bind(id))
		tabs.add_child(b)
		_house_tab_btns[id] = b
		var scroll := ScrollContainer.new()
		scroll.name = "TrayContent_" + id
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if id == "decor" else ScrollContainer.SCROLL_MODE_AUTO
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(scroll)
		_house_tab_scrolls[id] = scroll
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 4)
		scroll.add_child(body)
		match id:
			"decor": _house_decor_tab = body
			"spirit": _house_spirit_tab = body
			"cozy": _house_cozy_tab = body
	_build_house_decor_tab()
	_build_house_spirit_tab()
	_build_house_cozy_tab()
	_set_house_tab("decor")


func _build_house_decor_tab() -> void:
	var chip_scroll := ScrollContainer.new()
	chip_scroll.name = "CategoryChips"
	chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	chip_scroll.custom_minimum_size.y = 26
	chip_scroll.set_meta("tray_h", 26)
	_house_decor_tab.add_child(chip_scroll)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chip_scroll.add_child(chips)
	var labels := ["Окна", "Двери", "Столы", "Ковры", "Кровати", "Украшения"]
	for i in HouseItems.CATS.size():
		var cat := String(HouseItems.CATS[i])
		var b := _flat_button(String(labels[i]), 26, 12, "tab")
		b.name = "Cat_" + cat
		b.pressed.connect(_set_shop_cat.bind(cat))
		chips.add_child(b)
		_house_cat_btns[cat] = b
	var scroll := ScrollContainer.new()
	scroll.name = "DecorCards"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 16
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_house_decor_tab.add_child(scroll)
	_house_cards_scroll = scroll
	_house_cards = HBoxContainer.new()
	_house_cards.add_theme_constant_override("separation", 6)
	scroll.add_child(_house_cards)


func _rebuild_decor_cards() -> void:
	_card_press.clear()
	for c in _house_cards.get_children():
		_house_cards.remove_child(c)
		c.queue_free()
	var k := _house_tray_k
	var card_w := 116.0 * k
	var prev_h := (84.0 if not _house_landscape else 62.0) * k
	for raw in HouseItems.items_in_cat(_shop_cat):
		var it: Dictionary = raw
		var id := String(it["id"])
		# Карточка — колонка «превью, имя, действие» без собственной рамки: мебель
		# должна быть самым заметным элементом лотка, а не её плашка.
		var card := VBoxContainer.new()
		card.name = id
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.custom_minimum_size = Vector2(card_w, 0)
		card.add_theme_constant_override("separation", 2)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_theme_constant_override("separation", 2)
		card.add_child(content)
		var pic := TextureRect.new()
		pic.name = "Picture"
		pic.texture = load(String(it["sprite"]))
		var tint := String(it.get("tint", ""))
		pic.self_modulate = Color(tint) if tint != "" else Color.WHITE
		pic.custom_minimum_size = Vector2(card_w, prev_h)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_PASS if house_unlocked.has(id) else Control.MOUSE_FILTER_IGNORE
		pic.gui_input.connect(_on_card_input.bind(id, pic))
		content.add_child(pic)
		var name_lbl := g._label(String(it["label"]), 11)
		name_lbl.set_meta("tray_font", 11)
		# Название в одну строку: перенос стоил карточке высоты, которая отнималась
		# у комнаты. Полное имя видно в подсказке при наведении.
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.tooltip_text = String(it["label"])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := _flat_button("", 18, 11, "link")
		btn.name = "Action"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if house_unlocked.has(id):
			btn.text = "Поставить"
			btn.add_theme_color_override("font_color", UIStyle.TEAL_DIM)
			btn.add_theme_color_override("font_hover_color", UIStyle.TEAL)
			btn.pressed.connect(_place_from_tray.bind(id))
		elif bool(it.get("reward", false)):
			btn.text = "За поручение"
			btn.disabled = true
		else:
			btn.text = "Купить · %d ⚡" % int(it["cost"])
			btn.add_theme_color_override("font_color", UIStyle.GOLD)
			btn.pressed.connect(_buy_house_item.bind(id))
		content.add_child(name_lbl)
		content.add_child(btn)
		_house_cards.add_child(card)


func _build_house_spirit(parent: Control) -> void:
	# Не игнорирующий TextureRect: переносим готовый Companion со всеми
	# сердечками и уровнем дружбы, используя те же импортированные спрайты.
	_house_spirit_node = (load("res://game/home/companion.gd") as GDScript).new()
	_house_spirit_node.name = "HouseSpirit"
	_house_spirit_node.size = Vector2(96, 96)
	_house_spirit_node.pivot_offset = Vector2(48, 48)
	parent.add_child(_house_spirit_node)
	_house_spirit_node.set_bubble_allowed(false)
	_house_spirit_node.tapped.connect(func() -> void:
		# Штатный диалог был ниже z=20 полноэкранного дома.
		g._spirit._companion_dim.z_index = 22
		g._spirit._companion_dlg.z_index = 23
		for button in g._spirit._companion_dlg.find_children("*", "Button", true, false):
			(button as Button).custom_minimum_size.y = maxf((button as Button).custom_minimum_size.y, 48)
		g._spirit._on_companion_tapped())


func _build_house_spirit_tab() -> void:
	_house_affinity_lbl = g._label("", 12)
	_house_spirit_tab.add_child(_house_affinity_lbl)
	_house_spirit_tab.add_child(g._label("Поручения Светика", 14))
	_house_spirit_tab.add_child(g._label("Поставь мебель как он просит — и получишь то, что не купить.", 12))
	for ht in Game.HOUSE_TASKS:
		var row := g._label("", 12)
		_house_spirit_tab.add_child(row)
		_task_rows[String(ht["id"])] = row
	_guests_lbl = g._label("Пока никто не заглядывал.", 12)
	_house_spirit_tab.add_child(_guests_lbl)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 60
	_house_spirit_tab.add_child(scroll)
	_guests_row = HBoxContainer.new()
	_guests_row.name = "GuestFriendActions"
	_guests_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_guests_row)
	_refresh_task_rows()


func _refresh_house_screen() -> void:
	for id in _theme_btns:
		var b: Button = _theme_btns[id]
		var sid := String(id)
		if sid == "__custom":
			b.disabled = false
			if not bool(_custom_unlocked.get("theme", false)):
				b.text = "Палитра · %d ⚡" % int(Game.CUSTOM_COSTS["theme"])
			else:
				b.text = "Палитра ✓" if _theme_custom_on else "Палитра"
			continue
		var cur := sid == _cosmetic_theme and not _theme_custom_on
		_set_option_state(b, cur)
		if cur:
			b.text = "%s ✓" % _theme_label(sid)
		else:
			b.text = "%s · %d ⚡" % [_theme_label(sid), _theme_cost(sid)]
	for id in _aura_btns:
		var b: Button = _aura_btns[id]
		var sid := String(id)
		if sid == "__custom":
			b.disabled = false
			if not bool(_custom_unlocked.get("aura", false)):
				b.text = "Палитра · %d ⚡" % int(Game.CUSTOM_COSTS["aura"])
			else:
				b.text = "Палитра ✓" if _aura_custom_on else "Палитра"
			continue
		if sid == "hearth" and not g._contracts.hearth_aura():
			_set_option_state(b, false, true)
			b.text = "Очаг · веха 365"
			continue
		var cur := sid == _cosmetic_aura and not _aura_custom_on
		_set_option_state(b, cur)
		if cur:
			b.text = "%s ✓" % _aura_label(sid)
		else:
			b.text = "%s · %d ⚡" % [_aura_label(sid), _aura_cost(sid)]
	for key in _mat_btns:
		var b: Button = _mat_btns[key]
		var parts := String(key).split(":")
		var m := DecorData.floor_mat(parts[1]) if parts[0] == "floor" else DecorData.wall_mat(parts[1])
		var cur := parts[1] == (_floor_mat if parts[0] == "floor" else _wall_mat)
		var owned := int(m["cost"]) == 0 or bool(_custom_unlocked.get("mat_%s_%s" % [parts[0], parts[1]], false))
		_set_option_state(b, cur)
		if cur:
			b.text = "%s ✓" % String(m["label"])
		elif owned:
			b.text = String(m["label"])
		else:
			b.text = "%s · %d ⚡" % [String(m["label"]), int(m["cost"])]
	if _wall_btn != null:
		if not bool(_custom_unlocked.get("wall", false)):
			_wall_btn.text = "Стены · %d ⚡" % int(Game.CUSTOM_COSTS["wall"])
		else:
			_wall_btn.text = "Стены %s" % _cosmetic_wall.to_html(false)
	if _floor_btn != null:
		if not bool(_custom_unlocked.get("floor", false)):
			_floor_btn.text = "Пол · %d ⚡" % int(Game.CUSTOM_COSTS["floor"])
		else:
			_floor_btn.text = "Пол %s" % _cosmetic_floor.to_html(false)
	if _house_btn != null:
		if _cosmetic_house:
			_house_btn.text = "Домик построен ✓"
			_set_option_state(_house_btn, true)
		else:
			_house_btn.text = "Построить домик Светика (−%d ⚡)" % Game.HOUSE_COST
			_set_option_state(_house_btn, false)
	if _house_overlay != null:
		_house_overlay.visible = not _cosmetic_house
	if _house_room != null:
		_house_room.set_built(_cosmetic_house)
		_house_room.set_layout(house_placements)
		_house_room.set_room_tint(_cosmetic_wall, _cosmetic_floor, _floor_mat, _wall_mat)
	if _house_spirit_node != null:
		_house_spirit_node.visible = _cosmetic_house
	if _house_affinity_lbl != null:
		_house_affinity_lbl.text = g._spirit._companion_affinity_line()
	if _house_screen != null:
		for button in _house_screen.find_children("*", "Button", true, false):
			var b := button as Button
			# Лоток исключениями не раздувается: именно этот обход поднимал каждую
			# его кнопку до 48 px, и шапка панелей (вкладки + чипы + карточка)
			# занимала половину лотка. Плоские кнопки лотка (`_flat_button`) заявлены
			# на 26-30 px осознанно; тулбар предмета остаётся 48 px — он вне лотка.
			if _house_tray != null and _house_tray.is_ancestor_of(b):
				continue
			b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 48)
	_refresh_task_rows()


func _buy_theme(id: String, cost: int) -> void:
	if id == _cosmetic_theme and not _theme_custom_on:
		return
	if g._engine._available_ether() < cost:
		g._engine.status_text = "Не хватает эфира: тема стоит %d ⚡." % cost
		Sfx.error()
		return
	g._engine._spend_ether(cost)
	_cosmetic_theme = id
	_theme_custom_on = false
	_apply_cosmetic()
	_refresh_house_screen()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	g._engine.status_text = "Тема «%s» применена. Лаборатория стала уютнее!" % _theme_label(id)
	Sfx.stage_up()


func _buy_aura(id: String, cost: int) -> void:
	if id == _cosmetic_aura and not _aura_custom_on:
		return
	if id == "hearth" and not g._contracts.hearth_aura():
		g._engine.status_text = "Аура «Очаг» — награда вехи: 365 дней у очага Дневного круга."
		Sfx.error()
		return
	if g._engine._available_ether() < cost:
		g._engine.status_text = "Не хватает эфира: аура стоит %d ⚡." % cost
		Sfx.error()
		return
	g._engine._spend_ether(cost)
	_cosmetic_aura = id
	_aura_custom_on = false
	_apply_cosmetic()
	_refresh_house_screen()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	g._engine.status_text = "Аура «%s» зажглась вокруг Светика!" % _aura_label(id)
	Sfx.stage_up()


func _buy_house() -> void:
	if _cosmetic_house:
		return
	if g._engine._available_ether() < Game.HOUSE_COST:
		g._engine.status_text = "Не хватает эфира: домик стоит %d ⚡." % Game.HOUSE_COST
		Sfx.error()
		return
	g._engine._spend_ether(Game.HOUSE_COST)
	_cosmetic_house = true
	# С домиком даётся только кровать; остальное игрок покупает или получает
	# поручениями.
	var bed := HouseItems.base_item("bed")
	_unlock_item(bed)
	house_placements.clear()
	for rec in HouseLayout.default_placements():
		if String(rec.get("id", "")) == bed:
			house_placements.append(rec)
	_apply_cosmetic()
	_refresh_house_screen()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	_check_house_tasks()
	Sfx.legendary()


# ---------- палитра произвольных цветов ----------

func _target_color(target: String) -> Color:
	match target:
		"theme":
			return _theme_custom if _theme_custom_on else _theme_color(_cosmetic_theme)
		"aura":
			return _aura_custom if _aura_custom_on else _aura_color(_cosmetic_aura)
		"wall":
			return _cosmetic_wall
		"floor":
			return _cosmetic_floor
	return Color.WHITE


func _open_color_picker(target: String) -> void:
	_color_target = target
	var c := _target_color(target)
	_cp_old = c
	_cp_old_on = _theme_custom_on if target == "theme" else (_aura_custom_on if target == "aura" else true)
	_cp_r.value = c.r * 255.0
	_cp_g.value = c.g * 255.0
	_cp_b.value = c.b * 255.0
	_cp_update()
	if _cp_ok != null:
		if bool(_custom_unlocked.get(target, false)):
			_cp_ok.text = "Готово"
		else:
			_cp_ok.text = "Готово · %d ⚡" % int(Game.CUSTOM_COSTS.get(target, 0))
	if _color_picker != null:
		_color_picker.visible = true
	Sfx.click()


func _cp_target_label(t: String) -> String:
	match t:
		"theme":
			return "фон"
		"aura":
			return "аура Светика"
		"wall":
			return "стены"
		"floor":
			return "пол"
	return t


func _confirm_color_picker() -> void:
	var t := _color_target
	var cost := int(Game.CUSTOM_COSTS.get(t, 0))
	if cost > 0 and not bool(_custom_unlocked.get(t, false)):
		if g._engine._available_ether() < cost:
			# откат живого предпросмотра: вернуть цвет и флаг как было
			_set_custom_color(t, _cp_old, false)
			if t == "theme":
				_theme_custom_on = _cp_old_on
			elif t == "aura":
				_aura_custom_on = _cp_old_on
			_apply_cosmetic()
			_refresh_house_screen()
			g._engine._refresh()
			_close_color_picker()
			g._engine.status_text = "Кастомный цвет (%s) стоит %d ⚡ — пока не хватает." % [_cp_target_label(t), cost]
			Sfx.error()
			return
		g._engine._spend_ether(cost)
		_custom_unlocked[t] = true
		g._engine.status_text = "Кастомный цвет (%s) разблокирован за %d ⚡!" % [_cp_target_label(t), cost]
		Sfx.stage_up()
	_set_custom_color(t, _cp_current(), true)
	g._engine._refresh()
	_close_color_picker()


func _close_color_picker() -> void:
	if _color_picker != null:
		_color_picker.visible = false
	Sfx.click()


# Отмена палитры по Esc: кнопки Cancel у пикера нет, а слайдер применяет цвет
# живьём (_on_cp_slider) — просто скрыть означало бы оставить применённый, но
# не купленный кастом. Откатываем ровно как в ветке «не хватило эфира».
func _cancel_color_picker() -> void:
	var t := _color_target
	_set_custom_color(t, _cp_old, false)
	if t == "theme":
		_theme_custom_on = _cp_old_on
	elif t == "aura":
		_aura_custom_on = _cp_old_on
	_apply_cosmetic()
	_refresh_house_screen()
	g._engine._refresh()
	_close_color_picker()


func _on_cp_slider(_v: float) -> void:
	_cp_update()
	# живой предпросмотр: применяем сразу, сохраняем при закрытии
	_set_custom_color(_color_target, _cp_current(), false)


func _cp_current() -> Color:
	return Color(_cp_r.value / 255.0, _cp_g.value / 255.0, _cp_b.value / 255.0)


func _cp_update() -> void:
	var c := _cp_current()
	var sb := _cp_swatch.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = c
	if _cp_hex != null:
		_cp_hex.text = c.to_html(false)


func _set_custom_color(target: String, c: Color, persist := true) -> void:
	match target:
		"theme":
			_theme_custom = c
			_theme_custom_on = true
		"aura":
			_aura_custom = c
			_aura_custom_on = true
		"wall":
			_cosmetic_wall = c
		"floor":
			_cosmetic_floor = c
	_apply_cosmetic()
	_refresh_house_screen()
	if persist:
		g._saves._save_game()
		_upload_house()


func _swatch_button(hex: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(48, 48)
	var sb := UIStyle.box(Color(hex), Color(0, 0, 0, 0), 8, 2)
	var hover := UIStyle.box(Color(hex), Color(1, 1, 1, 0.55), 8, 2)
	var pressed := UIStyle.box(Color(hex), UIStyle.GOLD, 8, 2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# ---------- поручения дома (β) ----------

const TASK_AFFINITY := 8   # дружба за выполненное поручение: валюта дома, не эфир (спека §1)


static func house_task_satisfied(task: Dictionary, placements: Array) -> bool:
	var a := _first_of_cat(placements, String(task["a"]))
	var b := _first_of_cat(placements, String(task["b"]))
	if a.is_empty() or b.is_empty():
		return false
	var fa := Placement.footprint(a)
	var fb := Placement.footprint(b)
	if String(task["rule"]) == "over":
		return float(a["y"]) >= float(task.get("min_y", 1.2)) and fa.intersects(fb, false)
	return Placement.gap(fa, fb) <= float(task["gap"]) + 1e-6


static func _first_of_cat(placements: Array, cat: String) -> Dictionary:
	for raw in placements:
		var p: Dictionary = raw
		var item := HouseItems.get_item(String(p.get("id", "")))
		if String(item.get("cat", "")) == cat:
			return p
	return {}


func _grant_task_reward(task: Dictionary) -> String:
	var id := String(task.get("give", ""))
	if id == "" or not HouseItems.exists(id):
		return ""
	if not _unlock_item(id):
		return ""
	var it := HouseItems.get_item(id)
	return String(it["label"])


func _unlock_item(id: String) -> bool:
	if not HouseItems.exists(id) or house_unlocked.has(id):
		return false
	house_unlocked.append(id)
	return true


func _complete_house_task(task: Dictionary) -> void:
	var tid := String(task["id"])
	if house_tasks_done.has(tid):
		return
	house_tasks_done.append(tid)
	var got := _grant_task_reward(task)
	g._spirit._companion_gain(TASK_AFFINITY)
	g._spirit._companion_react("quest_done", String(task.get("text", "")))
	if got == "":
		g._online._set_status("Поручение выполнено: %s. Светик доволен." % String(task["text"]))
	else:
		g._online._set_status("Поручение Светика выполнено: %s — подарок: %s" % [String(task["text"]), got])
	g._saves._save_game()
	_refresh_task_rows()


func _check_house_tasks() -> void:
	if not _cosmetic_house:
		return
	for task in Game.HOUSE_TASKS:
		var tid := String(task["id"])
		if house_tasks_done.has(tid):
			continue
		if house_task_satisfied(task, house_placements):
			_complete_house_task(task)


func _refresh_task_rows() -> void:
	for raw_id in _task_rows:
		var tid := String(raw_id)
		var b: Label = _task_rows[tid]
		if house_tasks_done.has(tid):
			b.text = "✓ " + _task_text(tid)
			b.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
		else:
			b.text = "· " + _task_text(tid)
			b.add_theme_color_override("font_color", Color(0.62, 0.7, 0.76))


func _task_text(id: String) -> String:
	for t in Game.HOUSE_TASKS:
		if String(t["id"]) == id:
			return String(t["text"])
	return id


# ---------- домик: сериализация для сервера ----------

func _house_json() -> Dictionary:
	return {
		"v": 2,
		"built": _cosmetic_house,
		"theme": _cosmetic_theme,
		"aura": _cosmetic_aura,
		"theme_custom": _theme_custom.to_html(false) if _theme_custom_on else "",
		"aura_custom": _aura_custom.to_html(false) if _aura_custom_on else "",
		"wall": _cosmetic_wall.to_html(false),
		"floor": _cosmetic_floor.to_html(false),
		"floor_mat": _floor_mat,
		"wall_mat": _wall_mat,
		"items": house_placements.duplicate(true),
		"world_first": g._progress_ui._ach_world_first,
	}


static func _parse_guest_house(h: Dictionary) -> Dictionary:
	var out := {"built": false, "items": []}
	if int(h.get("v", 0)) != 2:
		return out
	var model := HouseLayout.parse({"unlocked": [], "placements": h.get("items", [])})
	return {"built": bool(h.get("built", false)), "items": model.placements}


func _upload_house() -> void:
	if not g._online._net_enabled or not _cosmetic_house:
		return
	if g._online._net_nick == "" or g._online._device_id == "":
		return
	Net.house_save(g._online._device_id, g._online._net_nick, _house_json())


# ---------- окна: палитра / гостевой домик ----------

func _build_color_picker() -> void:
	var root := Control.new()
	root.name = "ColorPicker"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 21
	g.add_child(root)
	_color_picker = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var t := g._label("ПАЛИТРА", 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var prev_row := HBoxContainer.new()
	prev_row.add_theme_constant_override("separation", 10)
	col.add_child(prev_row)
	_cp_swatch = PanelContainer.new()
	_cp_swatch.custom_minimum_size = Vector2(64, 40)
	var sb0 := StyleBoxFlat.new()
	sb0.bg_color = Color.WHITE
	sb0.set_corner_radius_all(8)
	_cp_swatch.add_theme_stylebox_override("panel", sb0)
	prev_row.add_child(_cp_swatch)
	_cp_hex = g._label("#ffffff", 16)
	_cp_hex.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prev_row.add_child(_cp_hex)
	var sw_grid := GridContainer.new()
	sw_grid.columns = 6
	sw_grid.add_theme_constant_override("h_separation", 8)
	sw_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(sw_grid)
	for hex in Game.COLOR_SWATCHES:
		var hx := String(hex)
		var sw := _swatch_button(hx)
		sw.pressed.connect(func() -> void:
			var c := Color(hx)
			_cp_r.value = c.r * 255.0
			_cp_g.value = c.g * 255.0
			_cp_b.value = c.b * 255.0
			_cp_update()
			_set_custom_color(_color_target, c, false))
		sw_grid.add_child(sw)
	for tag in ["R", "G", "B"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var lab := g._label(tag, 13)
		lab.custom_minimum_size = Vector2(18, 0)
		row.add_child(lab)
		var sl := HSlider.new()
		sl.custom_minimum_size.y = 48
		sl.min_value = 0.0
		sl.max_value = 255.0
		sl.step = 1.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(_on_cp_slider)
		row.add_child(sl)
		if tag == "R":
			_cp_r = sl
		elif tag == "G":
			_cp_g = sl
		else:
			_cp_b = sl
	var ok := g._small_button("Готово", Vector2(0, 48), 2)
	ok.pressed.connect(_confirm_color_picker)
	col.add_child(ok)
	_cp_ok = ok


func _build_house_popup() -> void:
	var root := Control.new()
	root.name = "HousePopup"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 21
	g.add_child(root)
	_house_popup = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(400, 0)
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	_house_popup_title = g._label("Домик", 18)
	_house_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_house_popup_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(_house_popup_title)
	# γ: кнопка отклика гостя. Попап собирается один раз на старте (main.gd), здесь
	# нет ни хоста, ни актуального состояния визита — поэтому видимость и адресат
	# назначаются при открытии домика (_open_player_house), а нажатие только
	# подтверждает отметку и прячет кнопку: сам запрос шлёт _on_net_house_result.
	_house_visit_btn = g._small_button("Засвидетельствовать визит", Vector2(0, 48), 1)
	_house_visit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_house_visit_btn.visible = false
	_house_visit_btn.pressed.connect(func() -> void:
		_mark_visited(_house_popup_nick)
		_house_visit_btn.visible = false
	)
	col.add_child(_house_visit_btn)
	var room_host := Control.new()
	room_host.custom_minimum_size = Vector2(0, 520)
	col.add_child(room_host)
	_house_popup_view = RoomView.new()
	_house_popup_view.read_only = true
	_house_popup_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_host.add_child(_house_popup_view)
	_host_spirit = (load("res://game/home/companion.gd") as GDScript).new()
	_host_spirit.size = Vector2(96, 96)
	_host_spirit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_host.add_child(_host_spirit)
	_host_spirit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_spirit.set_bubble_allowed(false)
	var showcase := PanelContainer.new()
	showcase.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	showcase.offset_top = -56
	showcase.add_theme_stylebox_override("panel", _tray_panel_style())
	room_host.add_child(showcase)
	var row := HBoxContainer.new()
	showcase.add_child(row)
	var flame_host := Control.new()
	flame_host.custom_minimum_size = Vector2(24, 40)
	flame_host.tooltip_text = "Пламя витрины"
	flame_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(flame_host)
	_host_flame = Polygon2D.new()
	_host_flame.polygon = PackedVector2Array([
		Vector2(12, 38), Vector2(3, 30), Vector2(3, 23), Vector2(8, 15),
		Vector2(9, 24), Vector2(15, 3), Vector2(17, 16), Vector2(22, 25), Vector2(21, 32)])
	flame_host.add_child(_host_flame)
	_host_showcase_lbl = g._label("", 12)
	_host_showcase_lbl.name = "HostShowcase"
	_host_showcase_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_host_showcase_lbl)
	var close := _ghost_button("Закрыть", Vector2(0, 48))
	close.pressed.connect(_close_house_popup)
	col.add_child(close)
	for button in root.find_children("*", "Button", true, false):
		(button as Button).custom_minimum_size.y = maxf((button as Button).custom_minimum_size.y, 48)


func _color_from_hex(hex: String, fallback: Color) -> Color:
	if hex == "":
		return fallback
	var h := hex if hex.begins_with("#") else "#" + hex
	if not h.is_valid_html_color():
		return fallback
	return Color(h)


func _apply_player_house(nick: String, h: Dictionary) -> void:
	if _house_popup_view == null:
		return
	var parsed := _parse_guest_house(h)
	var wall := _color_from_hex(String(h.get("wall", "")), Color.WHITE)
	var floor := _color_from_hex(String(h.get("floor", "")), Color.WHITE)
	var aura := _color_from_hex(String(h.get("aura_custom", "")), Color.TRANSPARENT)
	if aura.a == 0.0 or aura == Color.TRANSPARENT:
		aura = _aura_color(String(h.get("aura", "amber")))
	_house_popup_view.set_built(bool(parsed["built"]))
	_house_popup_view.set_layout(parsed["items"])
	_house_popup_view.set_room_tint(wall, floor, String(h.get("floor_mat", "planks")), String(h.get("wall_mat", "timber")))
	_house_popup_view.reset_camera()
	_house_popup_view.read_only = true
	_host_spirit.visible = bool(parsed["built"])
	_host_spirit.set_aura(aura)
	_house_popup_title.text = "Домик: %s" % nick
	var host_first := maxi(0, int(h.get("world_first", 0)))
	_host_showcase_lbl.text = "Колбы: %d · %s" % [mini(9, host_first), _showcase_window_caption()]
	_host_flame.color = _showcase_flame_color()


func _open_player_house(nick: String) -> void:
	_house_popup_nick = nick
	if _house_visit_btn != null:
		_house_visit_btn.visible = _visit_allowed(nick)
	if _house_popup != null:
		_house_popup.visible = true
	_house_popup_title.text = "Домик: %s" % nick
	_apply_player_house(nick, {})
	Net.house_get(nick)


func _close_house_popup() -> void:
	if _house_popup != null:
		_house_popup.visible = false
	Sfx.click()


# ---------- γ: визиты, гости и недельный подарок ----------

func _today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


func _visit_allowed(host_nick: String) -> bool:
	if not g._online._net_enabled or g._online._device_id == "":
		return false
	if host_nick == g._online._net_nick:
		return false
	return String(house_visited_day.get(host_nick, "")) != _today_key()


func _mark_visited(host_nick: String) -> void:
	house_visited_day[host_nick] = _today_key()


func _on_house_profile(week_visits: int, visitors: Array) -> void:
	# Спека §7.2: строка о гостях и лента «кто именно». Имена приходят только из
	# GET /api/me по своему device_id — чужой GET /api/house их не отдаёт.
	var parts := PackedStringArray()
	for v in visitors.slice(0, 3):
		var d: Dictionary = v
		var n := String(d.get("nick", ""))
		if n != "":
			parts.append(n)
	if _guests_lbl != null:
		if parts.is_empty():
			if week_visits == 0:
				_guests_lbl.text = "Пока никто не заглядывал."
			else:
				_guests_lbl.text = "За неделю тебя навестили: %d" % week_visits
		else:
			var names := ", ".join(parts)
			# длинные ники (24 символа на максимуме) не должны превращать строку в простыню
			if names.length() > 40:
				_guests_lbl.text = "За неделю тебя навестили: %d" % week_visits
			else:
				_guests_lbl.text = "За неделю тебя навестили: %s" % names
	# S1 §9.3 (задача 7): карточка гостя — кнопка «в друзья» на каждого гостя
	# строки (ник, не device_id — сервер резолвит сам; боты-гости получат отказ
	# кодом `bot` — по R8 он приходит глобальным тостом из main.gd). Снятие с
	# родителя перед queue_free — паттерн F1: пересборка идёт из-под Net-сигнала.
	if _guests_row != null:
		for c in _guests_row.get_children():
			_guests_row.remove_child(c)
			c.queue_free()
		for n in parts:
			SocialUI.attach(g, _guests_row, n)
	_check_house_gift(week_visits)


func _check_house_gift(week_visits: int) -> void:
	# Награда хосту в обход эфира (спека §7.3): источник истины числа — сервер,
	# начисление — клиент, ровно как с my_points из /api/challenge.
	var due: int = mini(2, int(week_visits / 3.0))
	var wk := _iso_week_id()
	if house_gift_week != wk:
		house_gift_week = wk
		house_gift_count = 0
	while house_gift_count < due:
		var got := _grant_free_variant()
		house_gift_count += 1
		if got == "":
			break  # всё выкуплено: инкремент уже сделан, цикла на весь прогон не будет
		g._online._set_status("Гости принесли тебе %s" % got)
		g._saves._save_game()


func _grant_free_variant() -> String:
	var ids: Array = []
	for id in HouseItems.ITEMS:
		var it: Dictionary = HouseItems.ITEMS[id]
		if not bool(it.get("reward", false)) and not house_unlocked.has(String(id)):
			ids.append(String(id))
	if ids.is_empty():
		return ""
	ids.sort()
	# стабильный по неделе выбор стартового предмета: две недели — разные подарки
	var start: int = absi(_iso_week_id().hash()) % ids.size()
	for i in ids.size():
		var id := String(ids[(start + i) % ids.size()])
		if _unlock_item(id):
			var it := HouseItems.get_item(id)
			return String(it["label"])
	return ""


static func _days_from_civil(y: int, m: int, d: int) -> int:
	# Число суток с 1970-01-01 (алгоритм H. Hinnant, civil_from_days наоборот).
	# Нужен потому, что ISO-неделя привязана к четвергу, а разница четвергов — в сутках.
	var yy := y - (1 if m <= 2 else 0)
	var era := int(yy / 400.0)
	var yoe := yy - era * 400
	var mp := m - 3 if m > 2 else m + 9
	var doy := int((153 * mp + 2) / 5.0) + d - 1
	var doe := yoe * 365 + int(yoe / 4.0) - int(yoe / 100.0) + doy
	return era * 146097 + doe - 719468


static func _iso_week_of(y: int, m: int, d: int) -> String:
	# ISO 8601: неделя с понедельника; её номер и её год задаёт четверг этой недели.
	var z := _days_from_civil(y, m, d)
	var wday := ((z + 3) % 7) + 1  # 1=Пн..7=Вс: 1970-01-01 был четвергом
	var thu := z + 4 - wday
	var iy := y
	if thu < _days_from_civil(y, 1, 1):
		iy = y - 1  # четверг ещё в прошлом году
	elif thu >= _days_from_civil(y + 1, 1, 1):
		iy = y + 1  # четверг уже в следующем году
	var ordinal := thu - _days_from_civil(iy, 1, 1)
	return "%04d-W%02d" % [iy, int(ordinal / 7.0) + 1]


static func _iso_week_id() -> String:
	var d := Time.get_date_dict_from_system()
	return _iso_week_of(int(d["year"]), int(d["month"]), int(d["day"]))
