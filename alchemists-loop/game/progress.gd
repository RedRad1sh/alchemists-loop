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
var _ach_rows: VBoxContainer = null

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
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(330, 0)
	card.add_child(col)
	var t := g._label("ЗАДАНИЯ И ДОСТИЖЕНИЯ", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	inner.add_child(g._label("Задания Светика", 16))
	g._guild._quest_rows = VBoxContainer.new()
	g._guild._quest_rows.add_theme_constant_override("separation", 4)
	inner.add_child(g._guild._quest_rows)
	inner.add_child(g._label("Достижения", 16))
	_ach_rows = VBoxContainer.new()
	_ach_rows.add_theme_constant_override("separation", 4)
	inner.add_child(_ach_rows)
	inner.add_child(g._label("Комплекты стихий", 16))
	g._set_rows = VBoxContainer.new()
	g._set_rows.add_theme_constant_override("separation", 4)
	inner.add_child(g._set_rows)
	inner.add_child(g._label("Заказы гильдии", 16))
	g._guild._order_rows = VBoxContainer.new()
	g._guild._order_rows.add_theme_constant_override("separation", 4)
	inner.add_child(g._guild._order_rows)
	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_prog_dim.visible = false
		_prog_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _open_progress_popup() -> void:
	_rebuild_quest_rows()
	_rebuild_ach_rows()
	_rebuild_set_rows()
	_rebuild_order_rows()
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
		# Достижения карточек (Аркан Сигилов). Источник — серверная коллекция:
		# _server_collection (уникальные card_id), не локальный _collection.
		"sigil_total": return g._sigil._server_collection.size()
		"sigil_first_rarity": return 1 if g._sigil.has_rarity(int(a.get("param", 0))) else 0
		"sigil_set_count":
			var best := 0
			for s in g._sigil.catalog_sets():
				var ids: Array = (s as Dictionary).get("card_ids", [])
				var per := 0
				for cid in ids:
					if g._sigil.has_collected(str(cid)):
						per += 1
				best = maxi(best, per)
			return best
		"sigil_sets_full":
			var full := 0
			for s in g._sigil.catalog_sets():
				var ids: Array = (s as Dictionary).get("card_ids", [])
				if ids.is_empty():
					continue
				var per := 0
				for cid in ids:
					if g._sigil.has_collected(str(cid)):
						per += 1
				if per == ids.size():
					full += 1
			return full
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
		# Достижения карточек (Аркан Сигилов) — тексты из спеки §1 дословно.
		"sigil_total": return "Собери первый сигил" if p == 1 else "Собери %d сигилов" % p
		"sigil_first_rarity":
			match p:
				0: return "Собери карту обычной редкости"
				1: return "Собери карту редкой редкости"
				2: return "Собери карту эпической редкости"
				3: return "Собери карту легендарной редкости"
				4: return "Собери хроматический сигил"
			return ""
		"sigil_set_count": return "Собери %d карт одного комплекта" % p
		"sigil_sets_full": return "Собери все четыре комплекта" if p == 4 else "Собери комплект целиком"
	return ""

func _rebuild_ach_rows() -> void:
	for child in _ach_rows.get_children():
		_ach_rows.remove_child(child)
		child.queue_free()
	var head := g._label("Выполнено: %d / %d" % [_ach_done.size(), Game.ACHIEVEMENTS.size()], 12)
	head.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	_ach_rows.add_child(head)
	for a in Game.ACHIEVEMENTS:
		var id := String(a["id"])
		var done := _ach_done.has(id)
		var prog := mini(_ach_progress(a), int(a.get("param", 1)))
		var line := "✓ %s" % String(a["title"]) if done else "• %s — %d/%d" % [String(a["title"]), prog, int(a.get("param", 1))]
		var lbl := g._label(line + " · +%d ⚡" % int(a.get("ether", 0)), 12)
		if done:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.62, 0.5))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
		_ach_rows.add_child(lbl)
		var req := _ach_requirement(a)
		var sub_txt := req
		if sub_txt == "":
			sub_txt = "Продолжай варить и открывать"
		sub_txt += " · навсегда +%d кап, +%.2f/с" % [Game.ACH_CAP, Game.ACH_REGEN]
		var sub := g._label(sub_txt, 11)
		sub.add_theme_color_override("font_color", Color(0.55, 0.66, 0.72))
		_ach_rows.add_child(sub)
	var res_head := g._label("Отголоски мира (повторов всего: %d)" % g._resonance._res_total, 12)
	res_head.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	_ach_rows.add_child(res_head)
	for m in Game.RES_MILES:
		var mi := int(m)
		var rline := "✓ %d — %s" % [mi, g._resonance._res_mile_reward_text(mi)] if g._resonance._res_done.has(mi) \
			else "• %d — %d/%d · %s" % [mi, mini(g._resonance._res_total, mi), mi, g._resonance._res_mile_reward_text(mi)]
		var rlbl := g._label(rline, 12)
		if g._resonance._res_done.has(mi):
			rlbl.add_theme_color_override("font_color", Color(0.45, 0.62, 0.5))
		else:
			rlbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
		_ach_rows.add_child(rlbl)

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
