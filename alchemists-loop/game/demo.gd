extends RefCounted
class_name Demo
# Демо-харнес (R14): флаги --action/--shot/--geom, покадровый тик съёмки, дампы.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _action_circle := false
var _action_sigilcoll := false
var _sigil_tab := ""  # --sigiltab=collection|fullscreen|sets|set_grid (T6: collection/fullscreen)
var _action_week := false
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
	g._engine.known_recipes[g._pair_key("earth", "water")] = true
	g._engine.known_recipes[g._pair_key("clay", "fire")] = true
	g._engine.known_recipes[g._pair_key("air", "stone")] = true
	g._engine.known_recipes[g._pair_key("fire", "sand")] = true
	g._engine.known_recipes[g._pair_key("clay", "water")] = true
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
					return
		if _gif_frame >= 240:  # ~80 кадров GIF (~4 с анимации)
			g.get_tree().quit(0)
		return true
	if _shot_path != "":
		_shot_frame += 1
		if _action_experiment and not _experiment_input_done:
			_experiment_input_smoke(_shot_frame)
		if _shot_scroll >= 0 and _shot_frame in [20, 40]:
			_set_page_scroll(_shot_scroll)
		if _pending_hint_shot and _shot_frame == 44:
			_pending_hint_shot = false
			g._pages._hint()
			g._engine._refresh()
		if _shot_tab == 1 and not g._online._world_loaded and _shot_frame < 180:
			return true
		var shot_at := 120 if _action_experiment else (200 if _action_sigilcoll else 50)
		if _shot_frame >= shot_at:
			var img := g.get_viewport().get_texture().get_image()
			if img == null:
				print("SHOT FAIL: нет рендера (не запускай --shot вместе с --headless)")
				g.get_tree().quit(1)
				return true
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
