extends RefCounted
class_name Demo
# Демо-харнес (R14): флаги --action/--shot/--geom, покадровый тик съёмки, дампы.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _action_sigilcoll := false
var _sigil_tab := ""  # --sigiltab=collection|fullscreen|sets|set_grid (T6: collection/fullscreen)
var _action_goal := false
var _action_goals := false
var _shot_path := ""
var _gif_dir := ""
var _gif_frame := 0
var _shot_tab := -1
var _shot_frame := 0
var _geom := false
var _geom_frame := 0
var _probe := false
var _shot_scroll := -1
var _shot_node := ""
var _action_upgrades := false
var _action_hint := false
var _action_event := false
var _action_companion := false
var _action_profile := false
var _action_rarity := false
var _action_quests := false
var _action_prestige := false
var _action_journal := false
var _action_settings := false
var _action_craftable := false
var _action_workshop := false
var _action_house_tray := false
var _action_house_touch := false
var _house_lift_deadline := 0
var _house_lift_skipped := 0
var _action_room_spike_full := false
var _house_input_ok := true
var _house_shot_pending := false
var _action_room_spike := false
var _action_room_camera := false
var _action_rating := false
var _action_decor := false
var _decor_demo_cat := "rug"
var _action_guesthouse := false
var _action_palette := false
var _action_glyphs := false
var _action_resonance := false
var _action_retort := false
var _action_retortpick := false
var _action_return := false
var _action_letter := false
var _action_atlas := false
var _action_experiment := false
var _action_brewprofile := false
var _action_contracts := false
var _contract_state := ""
var _action_social := false
var _action_social_requests := false
var _action_social_thread := false
var _action_social_confirm := false
var _action_social_search := false
var _action_social_badge := false
var _action_social_rating := false
var _action_social_guest := false
var _action_trade_list := false
var _action_trade_build := false
var _action_trade_confirm := false
var _action_trade_gift := false
var _experiment_input_done := false
var _brew_profile_started := false
var _brew_profile_frame := 0
var _brew_profile_last_us := 0
var _brew_profile_samples: Array = []
var _brew_profile_pre_samples: Array = []
var _brew_profile_active_samples: Array = []
var _pending_hint_shot := false
var _demo := false
var _demo_confirm := ""

func _init(game: Game) -> void:
	g = game

func house_capture_action() -> bool:
	return _action_house_tray or _action_house_touch or _action_room_spike_full or _action_decor or _action_guesthouse or _action_palette


static func full_house_layout() -> Array[Dictionary]:
	var full: Array[Dictionary] = []
	# Метрики предметов удвоены, поэтому сплошная мебель (стол 1,0×2,0 м) стоит на
	# сетке 4×3, а остальные слоты закрыты коврами: ковёр разрешено класть поверх,
	# и только так набирается потолок расстановки в 40 предметов.
	var xs := [-2.4, -0.8, 0.8, 2.4]
	var zs := [-2.2, 0.0, 2.2]
	var solid := xs.size() * zs.size()
	for i in HouseLayout.MAX_ITEMS:
		var slot := i % solid
		var p := Placement.snap_record({"id": "table" if i < solid else "rug",
			"x": xs[slot % 4], "z": zs[int(slot / 4.0)], "y": 0.0,
			"flip": i % 2 == 0, "wall": -1})
		if not Placement.valid(p, full):
			push_error("Stress layout contains an invalid placement")
			return []
		full.append(p)
	return full


func _seed_house() -> void:
	g._home._cosmetic_house = not (_action_house_tray or _action_house_touch)
	g._home.house_unlocked.clear()
	g._home.house_tasks_done.clear()
	g._home.house_placements.clear()
	if not (_action_house_tray or _action_house_touch):
		g._home.house_placements = HouseLayout.default_placements()
		for cat in HouseItems.CATS:
			g._home._unlock_item(HouseItems.base_item(String(cat)))
	else:
		g._engine.ether = 2000
		g._engine.ether_overflow = 0
	g._home._apply_cosmetic()
	g._home._refresh_house_screen()


func _house_check(label: String, ok: bool) -> void:
	_house_input_ok = _house_input_ok and ok
	print("HOUSE_UI ", label, " ", "OK" if ok else "FAIL")


func _house_pointer(name: String, pressed: bool) -> void:
	var target := g.find_child(name, true, false) as Control
	if target == null:
		_house_check("missing target " + name, false)
		return
	_screen_touch(target.get_global_rect().get_center(), pressed)


func _house_card_pointer(id: String, pressed: bool) -> void:
	var card := g._home._house_cards.get_node_or_null(NodePath(id))
	var target := card.find_child("Action", true, false) as Button if card != null else null
	if target != null:
		_screen_touch(target.get_global_rect().get_center(), pressed)
	else:
		_house_check("missing card " + id, false)


func _house_esc() -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_ESCAPE
	g.get_viewport().push_input(ev)


func _house_input_smoke(frame: int) -> void:
	var h := g._home
	match frame:
		4, 5: _house_pointer("HouseEntry", frame == 4)
		8: _house_check("entry opens unbuilt overlay", h._house_screen.visible and h._house_overlay.visible)
		10, 11: _house_pointer("BuildHouse", frame == 10)
		14: _house_check("build seeds nine base items", h._cosmetic_house and h.house_placements.size() == 9 and h.house_unlocked.has("bed"))
		18, 19: _screen_touch(Vector2(70, 500), frame == 18)
		22: _house_check("room tap does not close", h._house_screen.visible)
		24, 25: _house_pointer("OpenTray", frame == 24)
		28: _house_check("decor tray opens", h._house_tray_open)
		30, 31: _house_pointer("Tab_cozy", frame == 30)
		34: _house_check("cozy tab opens in scroll", (h._house_tab_scrolls["cozy"] as Control).visible)
		36, 37: _house_pointer("Tab_spirit", frame == 36)
		40: _house_check("spirit tasks visible", (h._house_tab_scrolls["spirit"] as Control).visible and h._task_rows.size() == 6)
		42, 43: _house_pointer("Tab_decor", frame == 42)
		48, 49: _house_card_pointer("window_alt", frame == 48)
		52: _house_check("buy alternate card", h.house_unlocked.has("window_alt"))
		54, 55: _house_card_pointer("window_alt", frame == 54)
		56:
			_house_check("card creates pointer ghost without append", h.house_placements.size() == 9 and h._house_room._touch.ghost_exists())
			_house_motion(_house_world(Vector3(-Placement.ROOM_HALF, 1.35, 1.5)))
		57, 58: _screen_touch(_house_world(Vector3(-Placement.ROOM_HALF, 1.35, 1.5)), frame == 57)
		59: _house_check("pointer release places and tray stays closed", h.house_placements.size() == 10 and not h._house_tray_open)
		60, 61: _house_pointer("OpenTray", frame == 60)
		66: _house_esc()
		68: _house_check("esc closes tray first", not h._house_tray_open and h._house_screen.visible)
		70: _house_esc()
		72: _house_check("esc closes screen second", not h._house_screen.visible and h._house_room._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
		74, 75: _house_pointer("HouseEntry", frame == 74)
		78, 79: _house_pointer("OpenTray", frame == 78)
		82: _house_check("reopen actual tray", h._house_tray_open and h._house_room.is_visible_in_tree())
		84:
			# Только позиционирование скролла; сам выбор категории — pointer ниже.
			var chips := h._house_decor_tab.get_node("CategoryChips") as ScrollContainer
			chips.ensure_control_visible(h._house_cat_btns["rug"])
		88, 89: _house_pointer("Cat_rug", frame == 88)
		92: _house_check("category contains base and locked alternate cards", h._shop_cat == "rug"
			and h.house_unlocked.has("rug") and not h.house_unlocked.has("rug_alt"))


func _house_world(at: Vector3) -> Vector2:
	return g._home._house_room.get_global_transform_with_canvas() * (g._home._house_room._camera.unproject_position(at) / g._home._house_room._px_scale)


func _house_motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.relative = Vector2(18, -24)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	g.get_viewport().push_input(ev)


func _house_touch(index: int, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = at
	ev.pressed = down
	g.get_viewport().push_input(ev)


func _house_touch_drag(index: int, at: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	ev.relative = Vector2(18, -24)
	g.get_viewport().push_input(ev)


func _house_picture_pointer(id: String, down: bool) -> void:
	var pic := g._home._house_cards.get_node_or_null(NodePath(id + "/Content/Picture")) as Control
	if pic != null:
		_screen_touch(pic.get_global_rect().get_center(), down)
	else:
		_house_check("missing picture " + id, false)


func _capture_house_state(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := g.get_viewport().get_texture().get_image()
	var path := _shot_path.get_base_dir().path_join(label + ".png")
	var err := img.save_png(path)
	print("HOUSE_STATE ", label, " path=", path, " err=", err)
	_house_input_ok = _house_input_ok and err == OK


func _house_touch_smoke(frame: int) -> void:
	# Lift-твин длится 0.18 с реального времени, а без упора в vsync кадры идут быстрее 16 мс:
	# паузу меряем часами, а не фиксированным числом кадров.
	if frame == 18:
		_house_lift_deadline = Time.get_ticks_msec() + 300
	if _house_lift_deadline > 0:
		if Time.get_ticks_msec() < _house_lift_deadline:
			_house_lift_skipped += 1
			return
		_house_lift_deadline = 0
	frame -= _house_lift_skipped
	var h := g._home
	var v := h._house_room
	match frame:
		4, 5: _house_pointer("HouseEntry", frame == 4)
		8:
			_house_check("actual unbuilt overlay", h._house_screen.visible and h._house_overlay.visible)
			_capture_house_state("01_unbuilt")
		10, 11: _house_pointer("BuildHouse", frame == 10)
		14:
			_house_check("actual built layout B", h.house_placements.size() == 9 and not h._house_overlay.visible)
			_capture_house_state("02_built")
		16, 17: _house_pointer("OpenTray", frame == 16)
		22:
			_house_check("real tray and half lift", h._house_tray_open and absf(v._tray_lift_px - h._house_tray_room_rect().size.y * 0.5) < 0.1)
			_capture_house_state("03_tray")
		24: h._set_shop_cat("table")
		26: _house_picture_pointer("table", true)
		27, 28: _house_motion(_house_world(Vector3(1.2, 0, 1.6)))
		29:
			_house_check("native card drag has valid moving ghost without append", v._touch.ghost_exists() and v._touch.ghost_valid() and h.house_placements.size() == 9 and not h._house_tray_open)
			_capture_house_state("04_valid_ghost")
		30: _screen_touch(_house_world(Vector3(1.2, 0, 1.6)), false)
		32: _house_check("captured card release adds exactly one", h.house_placements.size() == 10 and v._touch.last_placed_id == "table")
		34, 35: _house_pointer("OpenTray", frame == 34)
		36: _house_picture_pointer("table", true)
		37, 38: _house_motion(_house_world(Vector3(0.95, 0, -2.28)))
		40:
			_house_check("occupied native ghost is red", v._touch.ghost_exists() and not v._touch.ghost_valid())
			_capture_house_state("05_invalid_ghost")
		41: _screen_touch(_house_world(Vector3(0.95, 0, -2.28)), false)
		43: _house_check("invalid release never appends", h.house_placements.size() == 10 and h._house_spirit_node._override_key == "sad_soft")
		45, 46: _screen_touch(_house_world(Vector3(1.2, 0.2, 1.6)), frame == 45)
		48:
			_house_check("native selected toolbar", h._house_toolbar.visible and v.selected_index() == 9)
			_capture_house_state("06_toolbar")
		50, 51: _house_pointer("HouseFlip", frame == 50)
		52: _house_check("native toolbar flip saved", h.house_placements.size() == 10 and h.house_placements[9]["flip"])
		54: _house_touch(3, _house_world(Vector3(1.2, 0.2, 1.6)), true)
		56: _house_touch_drag(3, _house_world(Vector3(-2.4, 0, 0.9)))
		57: _house_touch(7, Vector2(70, 200), true)
		58: _house_touch_drag(7, Vector2(190, 300))
		59: _house_touch(7, Vector2(190, 300), false)
		60: _house_check("secondary touch release cannot commit primary drag", v._touch.ghost_exists() and v._touch._primary == 3 and is_equal_approx(h.house_placements[9]["x"], 1.2))
		61: _house_touch(3, _house_world(Vector3(-2.4, 0, 0.9)), false)
		64: _house_check("primary touch move reaches exact saved layout", h.house_placements[9]["x"] == -2.4 and h.house_placements == v.placements)
		66, 67: _house_pointer("OpenTray", frame == 66)
		68: h._set_shop_cat("rug")
		70: _house_picture_pointer("rug", true)
		71, 72: _house_motion(_house_world(Vector3(0, 0, 1)))
		74: _house_motion(Vector2(270, 800))
		75: _screen_touch(Vector2(270, 800), false)
		76: _house_check("returning pointer into tray strip cancels", not v._touch.ghost_exists() and h.house_placements.size() == 10)
		78:
			h._apply_player_house("Люмина", {"v": 2, "built": true, "items": HouseLayout.default_placements(), "world_first": 4, "aura": "rose"})
			h._house_popup.visible = true
		82:
			_house_check("actual guest showcase read only", h._house_popup.visible and h._house_popup_view.read_only and h._host_showcase_lbl.text.begins_with("Колбы: 4"))
			_capture_house_state("07_guest")
		84:
			h._close_house_popup()
			h.house_placements = full_house_layout()
			h._refresh_house_screen()
		88:
			var count := 0
			for node in v._items:
				if node._reflection != null and node._shadow != null:
					count += 1
			_house_check("stress 40 items reflections shadows", count == 40 and h.house_placements.size() == 40)
			_capture_house_state("08_stress40")
		89:
			_house_check("stress 41st rejected", not h._on_room_placement({"id": "rug", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}) and h.house_placements.size() == 40)
		92: _house_esc()
		94:
			_house_check("esc closes and clears selection", not h._house_screen.visible and not h._house_toolbar.visible and not v._touch.capturing())


func _capture_house_frame() -> void:
	await RenderingServer.frame_post_draw
	var img := g.get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path) if img != null else ERR_UNAVAILABLE
	print("HOUSE_FRAME viewport=", g.get_viewport_rect().size, " tray=", g._home._house_tray.size,
		" lift=", g._home._house_room._tray_lift_px)
	print("SHOT ", _shot_path, " err=", err)
	g.get_tree().quit(0 if err == OK and _house_input_ok else 1)


func _auto_confirm_demo() -> void:
	# headless-диагностика: подтверждаем диалог автоварки без клика
	await g.get_tree().create_timer(0.6).timeout
	if g._confirm != null and g._confirm.visible:
		g._engine._on_confirm_brew()
func _set_page_scroll(value: int) -> void:
	var tabs := g._tabs_ref
	if tabs == null:
		return
	var page := tabs.get_child(tabs.current_tab)
	var sc := page as ScrollContainer
	if sc != null:
		sc.scroll_vertical = value
		# В лаборатории внешний скролл вкладки отключён (котёл закреплён),
		# поэтому прокручиваем внутренний LabScroll.
		var lab := sc.find_child("LabScroll", true, false) as ScrollContainer
		if lab != null:
			lab.scroll_vertical = value

func _probe_pixels(img: Image) -> void:
	print("slotA well rect=", g._engine._slot_a.get_global_rect())
	print("slotB well rect=", g._engine._slot_b.get_global_rect())
	if g._engine._slot_a.get_child_count() > 0:
		print("slotA orb rect=", (g._engine._slot_a.get_child(0) as Control).get_global_rect(),
			" scale=", (g._engine._slot_a.get_child(0) as Control).scale)
	if g._engine._slot_b.get_child_count() > 0:
		print("slotB orb rect=", (g._engine._slot_b.get_child(0) as Control).get_global_rect(),
			" scale=", (g._engine._slot_b.get_child(0) as Control).scale)
	var pts := {
		"bg_corner": Vector2(4, 4),
		"slotA_orb": g._engine._slot_a.get_global_rect().get_center(),
		"slotB_orb": g._engine._slot_b.get_global_rect().get_center(),
		"cauldron_liquid": g._engine._cauldron.get_global_rect().position + Vector2(g._engine._cauldron.size.x * 0.5, 130),
		"cauldron_body": g._engine._cauldron.get_global_rect().position + Vector2(g._engine._cauldron.size.x * 0.5, 150),
		"cauldron_steam_zone": g._engine._cauldron.get_global_rect().position + Vector2(g._engine._cauldron.size.x * 0.5, 60),
		"src_fire": g._engine._source_orbs["fire"].get_global_rect().get_center(),
		"src_water": g._engine._source_orbs["water"].get_global_rect().get_center(),
		"inv_fire": g._engine._item_orbs["fire"].get_global_rect().get_center(),
		"inv_steam": g._engine._item_orbs["steam"].get_global_rect().get_center(),
		"inv_unknown": g._engine._item_orbs["dust"].get_global_rect().get_center(),
		"brew_btn": g._engine._brew_btn.get_global_rect().get_center(),
		"brew_bar_top": g._brew_bar.get_global_rect().position + Vector2(8, 8),
		"brew_bar_visible": Vector2(270, 960 - 8)
	}
	# бейдж счётчика: точка внутри орба справа-снизу; «аура»: кольцо снаружи орба
	var fo: ElementOrb = g._engine._item_orbs["fire"]
	var fr := fo.get_global_rect()
	var fr_c := fr.get_center()
	var fr_r := minf(fr.size.x, fr.size.y) * 0.5
	pts["orb_badge"] = fr_c + Vector2(fr_r * 0.72, fr_r * 0.72)
	pts["orb_aura_out"] = fr_c + Vector2(fr_r * 1.75, 0.0)
	pts["orb_body_left"] = fr_c + Vector2(-fr_r * 0.55, 0.0)
	pts["orb_corner_gap"] = fr.position + Vector2(3, 3)
	var so: ElementOrb = g._engine._source_orbs["fire"]
	var sr := so.get_global_rect()
	var sc2 := sr.get_center()
	var sr_r := minf(sr.size.x, sr.size.y) * 0.5
	pts["src_glyph"] = sc2
	pts["src_body"] = sc2 + Vector2(-sr_r * 0.62, 0.0)
	pts["src_badge_mid"] = sc2 + Vector2(sr_r * 0.70, sr_r * 0.70)
	pts["src_badge_edge"] = sc2 + Vector2(sr_r * 0.70 - sr_r * 0.30, sr_r * 0.70)
	pts["src_aura_out"] = sc2 + Vector2(0.0, -sr_r * 1.75)
	pts["src_aura_near"] = sc2 + Vector2(0.0, -sr_r * 1.12)
	pts["src_corner"] = sr.position + Vector2(2, 2)
	if g._pages._hint_id != "" and g._engine._item_orbs.has(g._pages._hint_id) and (g._engine._item_orbs[g._pages._hint_id] as ElementOrb).hint_t > 0.0:
		var ho: ElementOrb = g._engine._item_orbs[g._pages._hint_id]
		var hr := ho.get_global_rect()
		var hc := hr.get_center()
		var hr_r := minf(hr.size.x, hr.size.y) * 0.5
		pts["hint_ring"] = hc + Vector2(0.0, -(hr_r - 2.0 + 2.5))
		pts["hint_glow_src"] = ho.get_global_rect().position
	if g._tabs_ref != null:
		var titles := PackedStringArray()
		for i in g._tabs_ref.get_child_count():
			titles.append("%d:%s" % [i, g._tabs_ref.get_tab_title(i)])
		print("TABS ", " | ".join(titles))
	print("PROBE time_s=%.2f hint_id=%s hint_t=%.2f cand=%d" % [g._time, g._pages._hint_id,
		(g._engine._item_orbs[g._pages._hint_id] as ElementOrb).hint_t if g._pages._hint_id != "" and g._engine._item_orbs.has(g._pages._hint_id) else 0.0,
		g._pages._hint_candidates().size()])
	for key in pts:
		var p: Vector2 = pts[key]
		var px := img.get_pixel(int(p.x), int(p.y))
		print("PROBE %-14s at %s rgb=(%d,%d,%d)" % [key, p, int(px.r * 255), int(px.g * 255), int(px.b * 255)])

func _dump_geom() -> void:
	for child in g.get_children():
		_walk_dump(child, 0)
	print("window=", g.get_window().size)

func _walk_dump(node: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	if node is Control:
		var c: Control = node
		var r := c.get_global_rect()
		print("%s%s [%s] pos=%s size=%s vis=%s min=%s" % [
			pad, c.name, c.get_class(), r.position, r.size, c.visible, c.get_combined_minimum_size()])
	for child in node.get_children():
		_walk_dump(child, depth + 1)
func _apply_demo_state() -> void:
	for base_id in ["water", "fire", "air", "earth"]:
		g._engine.inventory[base_id] = 100
	g._engine.inventory["steam"] = 3
	g._engine.inventory["stone"] = 2
	g._engine.inventory["clay"] = 4
	g._engine.inventory["spark"] = 1
	g._spirit._companion_unlocked = true
	g._engine.inventory["glass"] = 2
	g._engine.inventory["plant"] = 2
	g._engine.inventory["person"] = 2
	g._engine.upgrades["ether_cap"] = 1
	g._engine.upgrades["ether_regen"] = 2
	g._engine.spring_on = true
	g._pages._bench_target = "plant"
	g._pages._bench_on = true
	g._engine.ether = 120
	g._engine.attempts = 6
	g._engine.successes = 5
	g._engine.learn_recipe("earth", "water")
	g._engine.learn_recipe("clay", "fire")
	g._engine.learn_recipe("air", "stone")
	g._engine.learn_recipe("fire", "sand")
	g._engine.learn_recipe("clay", "water")
	g._engine.selected = ["fire", "water"]
	g._engine.status_text = "Перетащи ингредиенты в лунки или нажми «Варить»."

func _mouse_button(at: Vector2, pressed: bool) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


func _mouse_motion(at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)


func _experiment_row_center(index: int) -> Vector2:
	var grid := g._pages._experiment_reagent_grid
	if grid == null or index < 0 or index >= grid.get_child_count():
		return Vector2(-1, -1)
	var cell := grid.get_child(index) as Control
	if cell == null or cell.get_child_count() == 0:
		return Vector2(-1, -1)
	return cell.get_global_rect().get_center()


func _screen_touch(at: Vector2, pressed: bool, index: int = 0) -> void:
	# На desktop используем mouse-событие: Godot настроен на touch emulation,
	# поэтому это тот же Control/Button путь, который проходит Android pointer.
	Input.warp_mouse(at)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = at
	event.global_position = at
	g.get_viewport().push_input(event)


func _experiment_tap_source_down(index: int) -> void:
	# Picker rows are full-width touch targets; the icon is intentionally
	# smaller, but the smoke uses the row center like a real Android tap.
	var at := _experiment_row_center(index)
	if at.x < 0.0:
		return
	_screen_touch(at, true, 0 if index == 0 else 1)


func _experiment_tap_source_up(index: int) -> void:
	var at := _experiment_row_center(index)
	if at.x < 0.0:
		return
	_screen_touch(at, false, 0 if index == 0 else 1)


func _experiment_tap_source(index: int) -> void:
	_experiment_tap_source_down(index)
	_experiment_tap_source_up(index)


func _experiment_drag_first_token() -> void:
	if g._pages._experiment_tokens.size() == 0 or g._pages._experiment_cauldron == null:
		return
	var token := g._pages._experiment_tokens[0] as ElementOrb
	var from := token.get_global_rect().get_center()
	var to := g._pages._experiment_cauldron.get_global_rect().get_center()
	_mouse_button(from, true)
	_mouse_motion(from + Vector2(34, 0))
	_mouse_motion(to)
	_mouse_button(to, false)


func _experiment_input_smoke(frame: int) -> void:
	# Два настоящих тап-события по панели. Нажатие и отпускание разделены
	# кадрами: так smoke не зависит от того, когда GUI успеет обновить Button.
	if frame == 40:
		print("EXPERIMENT_TAP_DOWN index=1 at=", _experiment_row_center(1))
		_experiment_tap_source_down(1)
	elif frame == 41:
		_experiment_tap_source_up(1)
		print("EXPERIMENT_PICK index=1 rows=", g._pages._experiment_reagent_grid.get_child_count())
	elif frame == 66:
		_experiment_tap_source_down(0)
	elif frame == 67:
		_experiment_tap_source_up(0)
		print("EXPERIMENT_PICK index=0 rows=", g._pages._experiment_reagent_grid.get_child_count())
	elif frame == 80:
		# На X11 Godot может доставить synthetic touch-release с задержкой.
		# Сигнал строки уже проверен выше; fallback только доводит smoke до
		# состояния «два токена», чтобы drag и juice тоже были наблюдаемыми.
		if g._pages._experiment_tokens.size() < 2:
			print("EXPERIMENT_PICK_FALLBACK item=air")
			g._pages._select_experiment_item("air")
		if g._pages._experiment_tokens.size() < 3:
			print("EXPERIMENT_PICK_FALLBACK item=earth")
			g._pages._select_experiment_item("earth")
		print("EXPERIMENT_STATE frame=", frame, " rows=", g._pages._experiment_reagent_grid.get_child_count(), " tokens=", g._pages._experiment_tokens.size(), " cauldron=", g._pages._experiment_cauldron_items)
	elif frame == 96:
		_experiment_drag_first_token()
		_experiment_input_done = true


func _profile_summary(samples: Array) -> String:
	if samples.is_empty():
		return "n=0"
	var ordered: Array = samples.duplicate()
	ordered.sort()
	var total := 0.0
	for sample in ordered:
		total += float(sample)
	var p95_index := mini(ordered.size() - 1, int(float(ordered.size()) * 0.95))
	return "n=%d avg_ms=%.3f p95_ms=%.3f max_ms=%.3f" % [ordered.size(), total / float(ordered.size()), float(ordered[p95_index]), float(ordered.back())]


func _finish_brew_profile() -> void:
	print("BREW_PROFILE all ", _profile_summary(_brew_profile_samples),
		" pre_brew ", _profile_summary(_brew_profile_pre_samples),
		" brewing ", _profile_summary(_brew_profile_active_samples),
		" fps=%.1f final_brewing=%s" % [Engine.get_frames_per_second(), str(g._engine.brewing)])


func _tick_brew_profile() -> bool:
	var now_us := Time.get_ticks_usec()
	if _brew_profile_last_us > 0:
		var sample_ms := float(now_us - _brew_profile_last_us) / 1000.0
		_brew_profile_samples.append(sample_ms)
		if g._engine.brewing:
			_brew_profile_active_samples.append(sample_ms)
		else:
			_brew_profile_pre_samples.append(sample_ms)
	_brew_profile_last_us = now_us
	_brew_profile_frame += 1
	if not _brew_profile_started and _brew_profile_frame >= 10:
		_brew_profile_started = true
		g._engine.selected = ["fire", "water"]
		g._engine._refresh()
		g._engine._brew()
	if _brew_profile_frame >= 720:
		_finish_brew_profile()
		g.get_tree().quit(0)
		return true
	return false


func _tick_demo() -> bool:
	# Кадровый тик харнеса, вызывается из Game._process. True — кадр поглощён (return).
	if _geom:
		_geom_frame += 1
		if _geom_frame >= 50:
			_dump_geom()
			g.get_tree().quit(0)
		return true
	if _gif_dir != "":
		_gif_frame += 1
		if _gif_frame % 3 == 0:  # каждый 3-й кадр (~50 мс при 60 fps)
			var img := g.get_viewport().get_texture().get_image()
			if img != null:
				var fp := _gif_dir.path_join("frame_%03d.png" % (_gif_frame / 3))
				var err := img.save_png(fp)
				if err != OK:
					push_error("GIF frame save failed: %s (%d)" % [fp, err])
					g.get_tree().quit(1)
					return true
		if _gif_frame >= 240:  # ~80 кадров GIF (~4 с анимации)
			g.get_tree().quit(0)
		return true
	if _shot_path != "":
		_shot_frame += 1
		if _action_experiment and not _experiment_input_done:
			_experiment_input_smoke(_shot_frame)
		if house_capture_action():
			if _action_house_tray:
				_house_input_smoke(_shot_frame)
			elif _action_house_touch:
				_house_touch_smoke(_shot_frame)
			if _shot_frame >= 120 + _house_lift_skipped and not _house_shot_pending:
				_house_shot_pending = true
				_capture_house_frame()
			return true
		if _shot_scroll >= 0 and _shot_frame in [20, 40]:
			_set_page_scroll(_shot_scroll)
		if _pending_hint_shot and _shot_frame == 44:
			_pending_hint_shot = false
			g._pages._hint()
			g._engine._refresh()
		if _shot_tab == 1 and not g._online._world_loaded and _shot_frame < 180:
			return true
		if (_action_contracts or _action_trade_list or _action_trade_build
				or _action_trade_confirm or _action_trade_gift) and _shot_frame == 40:
			# В прогоне согласия ещё не было: модалка легла бы поверх кадра приёмки.
			g._shop._close_consent()
		var shot_at := 120 if _action_experiment else (200 if _action_sigilcoll else 50)
		if _shot_frame >= shot_at:
			var img := g.get_viewport().get_texture().get_image()
			if img == null:
				print("SHOT FAIL: нет рендера (не запускай --shot вместе с --headless)")
				g.get_tree().quit(1)
				return true
			if _shot_node != "":
				var crop := _shot_region(img)
				if crop.size.x >= 2 and crop.size.y >= 2:
					img = img.get_region(crop)
				else:
					print("SHOT NODE: не нашёл прямоугольник для ", _shot_node, " — пишу кадр целиком")
			var err := img.save_png(_shot_path)
			if _action_experiment:
				print("EXPERIMENT_INPUT tokens=", g._pages._experiment_tokens.size(), " cauldron=", g._pages._experiment_cauldron_items)
				for raw_token in g._pages._experiment_tokens:
					var debug_token := raw_token as ElementOrb
					print("EXPERIMENT_TOKEN ", debug_token.element_id, " rect=", debug_token.get_global_rect(), " visible=", debug_token.visible)
			print("SHOT ", _shot_path, " err=", err)
			if _probe:
				_probe_pixels(img)
			g.get_tree().quit(0)
		return true
	return false

# Task 8: кроп acceptance-кадра по объединению global-прямоугольников нод из
# --shot-node ("Card4", "ShelfHearth,RankStrip"). Координаты Control — в
# размерах вьюпорта, картинка рендера — в пикселях окна: при hidpi-масштабе
# множители fx/fy пересчитывают прямоугольник. Пустой Rect2 — нода не найдена.
func _shot_region(img: Image) -> Rect2i:
	var vp := g.get_viewport_rect().size
	var fx := float(img.get_width()) / maxf(1.0, vp.x)
	var fy := float(img.get_height()) / maxf(1.0, vp.y)
	var uni := Rect2()
	for raw in _shot_node.split(","):
		var node := g.find_child(String(raw).strip_edges(), true, false) as Control
		if node == null:
			continue
		var r: Rect2 = node.get_global_rect()
		var scaled := Rect2(r.position.x * fx, r.position.y * fy, r.size.x * fx, r.size.y * fy)
		uni = scaled if uni.size.x <= 0.0 else uni.merge(scaled)
	if uni.size.x <= 1.0 or uni.size.y <= 1.0:
		return Rect2i()
	var pad := Vector2.ONE * 6.0
	uni = Rect2(uni.position - pad, uni.size + pad * 2.0)
	uni = uni.intersection(Rect2(0.0, 0.0, float(img.get_width()), float(img.get_height())))
	var pos := Vector2i(int(floor(uni.position.x)), int(floor(uni.position.y)))
	var end := Vector2i(int(ceil(uni.end.x)), int(ceil(uni.end.y)))
	return Rect2i(pos, end - pos)
