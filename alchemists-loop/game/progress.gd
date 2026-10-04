extends RefCounted
class_name Progress
# Прогресс (R4): попап заданий/достижений, ачивки, комплекты стихий, бонусная математика.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _prog_dim: Control = null
var _prog_popup: Control = null
var _ach_done: Dictionary = {}
var _ach_world_first := 0
var _ach_updating := false
var _set_done: Dictionary = {}
var _ach_map: AchievementMapView = null
var _prog_tabs: TabContainer = null

func _init(game: Game) -> void:
	g = game

# ---------- задания Светика и достижения (попап) ----------

func _build_progress_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "ProgDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_prog_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_prog_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	col.custom_minimum_size = Vector2(466, 0)
	card.add_child(col)
	var t := g._label("КАРТА ПРОГРЕССА", 19)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)

	_prog_tabs = TabContainer.new()
	_prog_tabs.name = "ProgressPages"
	_prog_tabs.custom_minimum_size = Vector2(0.0, 570.0)
	_prog_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prog_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_prog_tabs)

	_ach_map = AchievementMapView.new()
	_ach_map.name = "Карта"
	_ach_map.setup(g)
	_prog_tabs.add_child(_ach_map)

	var quests_page := _new_progress_list_page("Светик")
	quests_page.add_child(g._label("ЗАДАНИЯ СВЕТИКА", 15))
	g._guild._quest_rows = VBoxContainer.new()
	g._guild._quest_rows.add_theme_constant_override("separation", 5)
	g._guild._quest_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	quests_page.add_child(g._guild._quest_rows)

	var sets_page := _new_progress_list_page("Комплекты")
	sets_page.add_child(g._label("КОМПЛЕКТЫ СТИХИЙ", 15))
	g._set_rows = VBoxContainer.new()
	g._set_rows.add_theme_constant_override("separation", 5)
	g._set_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	sets_page.add_child(g._set_rows)

	var orders_page := _new_progress_list_page("Заказы")
	orders_page.add_child(g._label("ЗАКАЗЫ ГИЛЬДИИ", 15))
	g._guild._order_rows = VBoxContainer.new()
	g._guild._order_rows.add_theme_constant_override("separation", 5)
	g._guild._order_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	orders_page.add_child(g._guild._order_rows)

	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_prog_dim.visible = false
		_prog_popup.visible = false
		Sfx.click())
	col.add_child(close)


func _new_progress_list_page(page_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_prog_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(margin)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 7)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(inner)
	return inner

func _open_progress_popup() -> void:
	_rebuild_quest_rows()
	_rebuild_ach_rows()
	_rebuild_set_rows()
	_rebuild_order_rows()
	_prog_tabs.current_tab = 0
	_prog_dim.visible = true
	_prog_popup.visible = true
	Sfx.click()

func _rebuild_quest_rows() -> void:
	for child in g._guild._quest_rows.get_children():
		g._guild._quest_rows.remove_child(child)
		child.queue_free()
	for q in Game.SPIRIT_QUESTS:
		var id := String(q["id"])
		var done := g._guild._quests_done.has(id)
		var prog := g._guild._quest_progress(q)
		var target := g._guild._quest_target(q)
		var line := "✓ %s" % String(q["title"]) if done else "• %s — %d/%d" % [String(q["title"]), mini(prog, target), target]
		var lbl := g._label(line, 12)
		if done:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.62, 0.5))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
		g._guild._quest_rows.add_child(lbl)
		var sub_txt := String(q.get("hint", ""))
		if int(q.get("aff", 0)) > 0:
			sub_txt += " · +%d дружбы" % int(q.get("aff", 0))
		sub_txt += " · навсегда +%d кап, +%.1f/с" % [Game.QUEST_CAP, Game.QUEST_REGEN]
		var sub := g._label(sub_txt, 11)
		sub.add_theme_color_override("font_color", Color(0.55, 0.66, 0.72))
		g._guild._quest_rows.add_child(sub)

func _upgrades_total() -> int:
	var t := 0
	for k in g._engine.upgrades:
		t += int(g._engine.upgrades[k])
	return t

func _ach_progress(a: Dictionary) -> int:
	match String(a.get("kind", "")):
		"items": return g._engine.inventory.size()
		"recipes": return g._engine.known_recipes.size()
		"successes": return g._engine.successes
		"fails": return maxi(0, g._engine.attempts - g._engine.successes)
		"world_first": return _ach_world_first
		"challenge": return g._guild._quest_challenge
		"legend": return int(g._guild._quest_tier.get(4, 0))
		"affinity": return g._spirit._companion_level_for(g._spirit._companion_affinity)
		"upgrades": return _upgrades_total()
		"sets": return _set_done.size()
	return 0

func _ach_update() -> void:
	# начислить награды за новые достижения; без сайд-эффектов в selftest
	if g._selftest or _ach_updating:
		return
	_ach_updating = true
	_sets_update()
	var newly: Array = []
	for a in Game.ACHIEVEMENTS:
		var id := String(a["id"])
		if _ach_done.has(id):
			continue
		if _ach_progress(a) >= int(a.get("param", 1)):
			_ach_done[id] = true
			g._engine._grant_ether(int(a.get("ether", 0)), "achievement")
			newly.append(a)
	_ach_updating = false
	_refresh_achievement_map()
	if not newly.is_empty():
		g._saves._save_game()
		_notify_achievements(newly)

func _notify_achievements(newly: Array) -> void:
	var names := PackedStringArray()
	var total := 0
	for a in newly:
		names.append(String(a["title"]))
		total += int(a.get("ether", 0))
	if newly.size() == 1:
		g._online._set_status("ДОСТИЖЕНИЕ: %s (+%d ⚡, +%d кап, +%.1f/с навсегда)" % [names[0], total, Game.ACH_CAP, Game.ACH_REGEN])
	else:
		g._online._set_status("ДОСТИЖЕНИЯ: %s (+%d ⚡, +%d кап, +%.1f/с навсегда)" % [" · ".join(names), total, Game.ACH_CAP * newly.size(), Game.ACH_REGEN * newly.size()])
	g._spirit._companion_react("achievement", names[0])
	Sfx.divide()
	Input.vibrate_handheld(20)
	if not g._selftest:
		g._hub._log_event("Достижение: %s" % " · ".join(names))

func _ach_requirement(a: Dictionary) -> String:
	var p := int(a.get("param", 1))
	match String(a.get("kind", "")):
		"items": return "Открой %d веществ" % p
		"recipes": return "Узнай %d рецептов" % p
		"successes": return "Проведи %d успешных варок" % p
		"fails": return "Получи %d «туманов»" % p
		"world_first": return "Соверши %d мировых открытий" % p
		"challenge": return "Выполни цель дня %d раз(а)" % p
		"legend": return "Получи легендарное вещество"
		"affinity": return "Достигни %d уровня дружбы со Светиком" % p
		"upgrades": return "Купи %d уровней улучшений" % p
		"sets": return "Собери %d комплекта стихий" % p
	return ""

func _rebuild_ach_rows() -> void:
	# Compatibility entry point for the popup flow; the map only mirrors current
	# achievement and resonance state and never grants or persists anything.
	if _ach_map != null and is_instance_valid(_ach_map):
		_ach_map.refresh()


func _refresh_achievement_map() -> void:
	if (
		_ach_map != null
		and is_instance_valid(_ach_map)
		and _prog_popup != null
		and _prog_popup.visible
	):
		_ach_map.refresh()


func _cat_title(cat: String) -> String:
	for st in Game.CATEGORY_SETS:
		if String(st["cat"]) == cat:
			return String(st["title"])
	return ""

func _cat_total(cat: String) -> int:
	var t := 0
	for k in Game.CATEGORY_OF:
		if Game.CATEGORY_OF[k] == cat:
			t += 1
	return t

func _cat_found(cat: String) -> int:
	var f := 0
	for k in Game.CATEGORY_OF:
		if Game.CATEGORY_OF[k] == cat and g._engine.inventory.has(k):
			f += 1
	return f

func _sets_update() -> void:
	# завершение комплекта стихии = награда (все вещества категории открыты)
	var newly: Array = []
	for st in Game.CATEGORY_SETS:
		var cat := String(st["cat"])
		if _set_done.has(cat):
			continue
		if _cat_found(cat) >= _cat_total(cat):
			_set_done[cat] = true
			g._engine._grant_ether(int(st["ether"]), "element_set")
			g._spirit._companion_gain(int(st.get("aff", 0)))
			newly.append(st)
	if not newly.is_empty():
		g._saves._save_game()
		for st in newly:
			g._spirit._companion_react("set_done", String(st["title"]))
			if not g._selftest:
				g._hub._log_event("Комплект стихии: %s" % String(st["title"]))
		g._online._set_status("КОМПЛЕКТ: %s (+%d ⚡)" % [String(newly.back()["title"]), int(newly.back()["ether"])])
		Sfx.legendary()

func _rebuild_order_rows() -> void:
	for child in g._guild._order_rows.get_children():
		g._guild._order_rows.remove_child(child)
		child.queue_free()
	g._guild._orders_refresh()
	var lbl: Label
	if g._guild._order_targets_cache.is_empty():
		lbl = g._label("Заказы появятся завтра.", 12)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
		g._guild._order_rows.add_child(lbl)
		return
	for slug in g._guild._order_targets_cache:
		var s2 := String(slug)
		var done := g._guild._order_done.has(s2)
		var line := "✓ Свари «%s»" % g._online._item_name(s2) if done else "• Свари «%s»" % g._online._item_name(s2)
		lbl = g._label(line + " · +%d ⚡" % g._guild._order_bounty(s2), 12)
		if done:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.62, 0.5))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
		g._guild._order_rows.add_child(lbl)
	if g._guild._order_done.size() == g._guild._order_targets_cache.size():
		lbl = g._label("Бонус за все заказы: +100 ⚡ и +5 дружбы — получен!", 12)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
		g._guild._order_rows.add_child(lbl)

func _rebuild_set_rows() -> void:
	for child in g._set_rows.get_children():
		g._set_rows.remove_child(child)
		child.queue_free()
	for st in Game.CATEGORY_SETS:
		var cat := String(st["cat"])
		var done := _set_done.has(cat)
		var line := "✓ %s" % String(st["title"]) if done else "• %s — %d/%d" % [String(st["title"]), _cat_found(cat), _cat_total(cat)]
		var lbl := g._label(line + " · +%d ⚡" % int(st["ether"]), 12)
		if done:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.62, 0.5))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
		g._set_rows.add_child(lbl)

func _quest_cap_bonus() -> int:
	return Game.QUEST_CAP * g._guild._quests_done.size()

func _quest_regen_bonus() -> float:
	return Game.QUEST_REGEN * g._guild._quests_done.size()

func _ach_cap_bonus() -> int:
	return Game.ACH_CAP * _ach_done.size()

func _ach_regen_bonus() -> float:
	return Game.ACH_REGEN * _ach_done.size()
