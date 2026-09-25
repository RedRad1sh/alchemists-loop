extends RefCounted
class_name Retort
# Ночная реторта (R6): долгий сосуд 8–24 ч, эссенции, выбор вещества.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _retort_slots: Array = []
var _essences: Dictionary = {}
var _retort_head: Label = null
var _retort_desc: Label = null
var _retort_cards: VBoxContainer = null
var _retort_ess: Label = null
var _retort_ui: Array = []
var _retort_dim: ColorRect = null
var _retort_popup: CenterContainer = null
var _retort_list: VBoxContainer = null
var _retort_pick_slot := -1

func _init(game: Game) -> void:
	g = game

# ---------- ночная реторта: долгий сосуд 8–24 ч ----------

func _retort_now(when: float = -1.0) -> float:
	return when if when >= 0.0 else Time.get_unix_time_from_system()

func _retort_hours_for_tier(tier: int) -> float:
	var base := Game.RETORT_BASE_HOURS * (1.0 + float(maxi(0, tier)) * 0.5)
	return maxf(Game.MASTERY_RETORT_MIN_HOURS, base * _retort_mastery_factor())

func _retort_mastery_factor() -> float:
	# A2: каждый ранг ≥ 2 снимает 6 % срока; ранг 1 — без бонуса. Пол — 6 ч.
	var ranks := maxi(0, g._engine.mastery_rank - 1)
	return maxf(0.0, 1.0 - Game.MASTERY_RETORT_SPEED * float(ranks))

func _retort_hours_text(tier: int) -> String:
	return "%d ч" % int(_retort_hours_for_tier(tier))

func _retort_slots_open() -> int:
	var n := 1
	if _essences.size() >= 3:
		n += 1
	if g._engine.sage_gold > 0:
		n += 1
	if g._engine.mastery_rank >= Game.MASTERY_RETORT_SLOT_RANK:
		n += 1
	return mini(n, Game.RETORT_SLOT_MAX)

func _retort_slot(i: int) -> Dictionary:
	# сосудов физически RETORT_SLOT_MAX; пустой — {sub: ""}; чинит сейвы до реторты
	while _retort_slots.size() < Game.RETORT_SLOT_MAX:
		_retort_slots.append({"sub": "", "name": "", "started": 0.0, "dur": 0.0})
	if i < 0 or i >= _retort_slots.size():
		return {}
	return _retort_slots[i]

func _retort_busy(i: int) -> bool:
	return String(_retort_slot(i).get("sub", "")) != ""

func _retort_ready(i: int, when: float = -1.0) -> bool:
	var s := _retort_slot(i)
	if String(s.get("sub", "")) == "":
		return false
	return _retort_now(when) - float(s.get("started", 0.0)) >= float(s.get("dur", 0.0))

func _retort_left(i: int, when: float = -1.0) -> float:
	var s := _retort_slot(i)
	if String(s.get("sub", "")) == "":
		return 0.0
	return maxf(0.0, float(s.get("started", 0.0)) + float(s.get("dur", 0.0)) - _retort_now(when))

func _retort_left_text(sec: float) -> String:
	var s := maxi(0, int(sec))
	if s >= 3600:
		return "%d ч %d мин" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d мин" % (s / 60)
	return "%d с" % s

func _essence_cap_bonus() -> int:
	return Game.RETORT_CAP_EACH * mini(_essences.size(), Game.RETORT_CAP_FIRST)

func _retort_any_ready(when: float = -1.0) -> bool:
	for i in Game.RETORT_SLOT_MAX:
		if _retort_ready(i, when):
			return true
	return false

func _retort_hello_line(when: float = -1.0) -> String:
	# фраза Светика при входе про реторту ("" — нечего сказать)
	if _retort_any_ready(when):
		return "Реторта готова — неси кружку!"
	var best := -1.0
	for i in Game.RETORT_SLOT_MAX:
		if _retort_busy(i):
			var left := _retort_left(i, when)
			if best < 0.0 or left < best:
				best = left
	if best >= 0.0:
		return "Реторта побулькивает, осталось %s!" % _retort_left_text(best)
	return ""

func _retort_candidates() -> Array:
	var res: Array = []
	for raw_id in g._engine.inventory:
		var sid := String(raw_id)
		if int(g._engine.inventory.get(sid, 0)) < 1 or not g.ITEMS.has(sid):
			continue
		res.append(sid)
	res.sort_custom(func(x: String, y: String) -> bool:
		var tx := int(g._engine._rarity_of(x).get("tier", 0))
		var ty := int(g._engine._rarity_of(y).get("tier", 0))
		if tx != ty:
			return tx < ty
		return g._online._item_name(x) < g._online._item_name(y))
	return res

func _retort_start(slot: int, sub: String, when: float = -1.0) -> bool:
	# положить вещество в сосуд (1 шт. списывается); false — нельзя
	if slot < 0 or slot >= _retort_slots_open():
		return false
	if _retort_busy(slot):
		return false
	if int(g._engine.inventory.get(sub, 0)) < 1 or not g.ITEMS.has(sub):
		return false
	var tier := int(g._engine._rarity_of(sub).get("tier", 0))
	var dur := _retort_hours_for_tier(tier) * 3600.0
	g._engine.inventory[sub] = int(g._engine.inventory[sub]) - 1
	_retort_slots[slot] = {"sub": sub, "name": g._online._item_name(sub),
		"started": _retort_now(when), "dur": dur}
	if not g._selftest:
		g._online._set_status("Реторта: «%s» настаивается %s." % [g._online._item_name(sub), _retort_hours_text(tier)])
		g._hub._log_event("Реторта: заложено «%s» на %s" % [g._online._item_name(sub), _retort_hours_text(tier)])
		Sfx.draft_open()
		g._saves._save_game()
	_refresh_retort_page()
	return true

func _retort_cancel(slot: int) -> bool:
	# отменить без потерь: вещество возвращается в запасы
	if not _retort_busy(slot):
		return false
	var s := _retort_slot(slot)
	var sub := String(s.get("sub", ""))
	_retort_slots[slot] = {"sub": "", "name": "", "started": 0.0, "dur": 0.0}
	if sub != "":
		g._engine.inventory[sub] = int(g._engine.inventory.get(sub, 0)) + 1
	if not g._selftest:
		g._online._set_status("Реторта: «%s» возвращено в запасы." % g._clean_str(s.get("name", sub)))
		Sfx.click()
		g._saves._save_game()
	_refresh_retort_page()
	return true

func _retort_collect(slot: int, when: float = -1.0) -> Dictionary:
	# забрать созревшую эссенцию; рано или пусто — {ok: false}
	if not _retort_ready(slot, when):
		return {"ok": false}
	var s := _retort_slot(slot)
	var sub := String(s.get("sub", ""))
	var nm := g._clean_str(s.get("name", sub))
	_retort_slots[slot] = {"sub": "", "name": "", "started": 0.0, "dur": 0.0}
	var unique := not _essences.has(sub)
	var perm := false
	if unique:
		_essences[sub] = nm
		perm = _essences.size() <= Game.RETORT_CAP_FIRST
	var gain := 0
	if not perm:
		gain = Game.RETORT_REPEAT_ETHER
		g._engine._grant_ether(gain, "retort_repeat")
	var res := {"ok": true, "name": nm, "unique": unique, "perm": perm, "gain": gain}
	if not g._selftest:
		if perm:
			g._online._set_status("ЭССЕНЦИЯ «%s»: +%d к капу навсегда!" % [nm, Game.RETORT_CAP_EACH])
		elif unique:
			g._online._set_status("Эссенция «%s»: +%d ⚡." % [nm, gain])
		else:
			g._online._set_status("Эссенция «%s» (повтор): +%d ⚡." % [nm, gain])
		g._hub._log_event("Реторта: эссенция «%s»%s" % [nm, " (+" + str(Game.RETORT_CAP_EACH) + " кап)" if perm else " (+" + str(gain) + " ⚡)"])
		Sfx.discovery()
		Input.vibrate_handheld(25)
		g._engine._refresh()
		g._saves._save_game()
	_refresh_retort_page()
	return res

func _build_retort_page(container: VBoxContainer) -> void:
	_retort_ui.clear()
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	col.add_child(g._label("Ночная реторта", 17))
	var cap_note := "Первые %d уникальных эссенций дают +%d к капу навсегда каждая." % [Game.RETORT_CAP_FIRST, Game.RETORT_CAP_EACH]
	_retort_desc = g._label("Положи вещество на ночь — к утру созреет эссенция. " + cap_note, 12)
	_retort_desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(_retort_desc)
	_retort_head = g._label("", 13)
	col.add_child(_retort_head)
	_retort_cards = VBoxContainer.new()
	_retort_cards.add_theme_constant_override("separation", 8)
	col.add_child(_retort_cards)
	for i in Game.RETORT_SLOT_MAX:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		_retort_cards.add_child(card)
		var title := g._label("Слот %d" % (i + 1), 14)
		card.add_child(title)
		var state := g._label("", 12)
		state.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
		card.add_child(state)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var primary := g._small_button("", Vector2(0, 44))
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.pressed.connect(_on_retort_primary.bind(i))
		row.add_child(primary)
		var cancel := g._small_button("Отмена", Vector2(0, 44))
		cancel.pressed.connect(_on_retort_cancel.bind(i))
		row.add_child(cancel)
		_retort_ui.append({"title": title, "state": state, "primary": primary, "cancel": cancel})
	_retort_ess = g._label("", 12)
	_retort_ess.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
	col.add_child(_retort_ess)
	var hint := g._label("Забрать раньше срока нельзя, но отменить можно без потерь. Реторта зреет, даже пока игра закрыта, — и никогда не портится.", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.66, 0.72))
	col.add_child(hint)
	_refresh_retort_page()

func _refresh_retort_page() -> void:
	if _retort_head == null or _retort_cards == null or _retort_ess == null:
		return
	if _retort_ui.size() < Game.RETORT_SLOT_MAX:
		return
	var n := _essences.size()
	_retort_head.text = "Эссенций собрано: %d · бонус капа: +%d" % [n, _essence_cap_bonus()]
	var open := _retort_slots_open()
	for i in Game.RETORT_SLOT_MAX:
		var u: Dictionary = _retort_ui[i]
		var title: Label = u["title"]
		var state: Label = u["state"]
		var primary: Button = u["primary"]
		var cancel: Button = u["cancel"]
		if i >= open:
			title.text = "Слот %d — закрыт" % (i + 1)
			if i == 1:
				state.text = "Откроется за 3 уникальные эссенции (%d/3)." % mini(n, 3)
			elif i == 2:
				state.text = "Откроется за Перегонку (престиж)."
			else:
				state.text = "Откроется за Печать мастерства: ранг %d (сейчас %d)." % [Game.MASTERY_RETORT_SLOT_RANK, g._engine.mastery_rank]
			primary.visible = false
			cancel.visible = false
			continue
		title.text = "Слот %d" % (i + 1)
		primary.visible = true
		var s := _retort_slot(i)
		var sub := String(s.get("sub", ""))
		if sub == "":
			state.text = "Пуст. Положи вещество — и возвращайся завтра."
			primary.text = "Выбрать вещество…"
			primary.disabled = false
			cancel.visible = false
		elif _retort_ready(i):
			state.text = "«%s» настоялось! Эссенция готова." % g._clean_str(s.get("name", sub))
			primary.text = "Забрать эссенцию"
			primary.disabled = false
			cancel.visible = false
		else:
			state.text = "«%s» булькает… осталось %s." % [g._clean_str(s.get("name", sub)), _retort_left_text(_retort_left(i))]
			primary.text = "Зреет…"
			primary.disabled = true
			cancel.visible = true
	if _essences.is_empty():
		_retort_ess.text = "Пока ни одной эссенции."
	else:
		var names := PackedStringArray()
		for k in _essences:
			names.append("«%s»" % g._clean_str(_essences[k]))
		_retort_ess.text = "Собраны: %s" % " · ".join(names)
	if g._pages._mode_chips.has("retort"):
		(g._pages._mode_chips["retort"] as Button).text = "Реторта ●" if _retort_any_ready() else "Реторта"

func _on_retort_primary(i: int) -> void:
	if not _retort_busy(i):
		_open_retort_picker(i)
		return
	if _retort_ready(i):
		_retort_collect(i)
		g._engine._refresh()

func _on_retort_cancel(i: int) -> void:
	if _retort_cancel(i):
		g._engine._refresh()

func _build_retort_picker() -> void:
	var dim := ColorRect.new()
	dim.name = "RetortDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	g.add_child(dim)
	_retort_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	g.add_child(center)
	_retort_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(360, 0)
	card.add_child(col)
	var t := g._label("ЧТО ПОЛОЖИТЬ В РЕТОРТУ?", 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var sub := g._label("Чем глубже вещество, тем дольше настой — и тем ценнее эссенция.", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	col.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_retort_list = VBoxContainer.new()
	_retort_list.add_theme_constant_override("separation", 6)
	_retort_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_retort_list)
	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_retort_dim.visible = false
		_retort_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _open_retort_picker(slot: int) -> void:
	_retort_pick_slot = slot
	_rebuild_retort_rows()
	_retort_dim.visible = true
	_retort_popup.visible = true
	Sfx.click()

func _rebuild_retort_rows() -> void:
	for child in _retort_list.get_children():
		_retort_list.remove_child(child)
		child.queue_free()
	var cands := _retort_candidates()
	if cands.is_empty():
		var none := g._label("Нет веществ с запасом — добудь что-нибудь из источников.", 13)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		_retort_list.add_child(none)
		return
	for sid in cands:
		var id := String(sid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.11, 0.16, 0.9)
		sb.set_corner_radius_all(12)
		sb.border_color = Color(0.3, 0.4, 0.5, 0.35)
		sb.set_border_width_all(1)
		var sb_h: StyleBoxFlat = sb.duplicate()
		sb_h.bg_color = Color(0.13, 0.18, 0.25, 1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb_h)
		b.add_theme_stylebox_override("pressed", sb_h)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_on_retort_pick.bind(id))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var orb := g._engine._mini_orb(id, 34)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(orb)
		var nm := g._label(g._online._item_name(id), 15)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(nm)
		var tier := int(g._engine._rarity_of(id).get("tier", 0))
		var tag := g._label("%s · ×%d" % [_retort_hours_text(tier), int(g._engine.inventory.get(id, 0))], 12)
		tag.add_theme_color_override("font_color", Color(0.55, 0.66, 0.72))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tag)
		_retort_list.add_child(b)

func _on_retort_pick(sub: String) -> void:
	var slot := _retort_pick_slot
	_retort_pick_slot = -1
	_retort_dim.visible = false
	_retort_popup.visible = false
	if _retort_start(slot, sub):
		g._engine._refresh()
	else:
		g._online._set_status("Не вышло положить в реторту.")
		Sfx.error()
		g._engine._refresh()
