extends RefCounted
class_name Home
# Дом и декор (R7): тема/аура, страница дома, покупки, магазин декора, палитра,
# сериализация домика, гостевой домик. Своё состояние — поля ниже.

var g: Game

var _cosmetic_theme := "cobalt"
var _cosmetic_aura := "amber"
var _cosmetic_house := false
var _theme_btns := {}
var _aura_btns := {}
var _house_btn: Button = null
var _furniture_btns := {}
var _house_view: Control = null
var _furniture_shop: VBoxContainer = null
var _house_hint: Label = null
var house_furniture: Dictionary = {}   # категория -> id варианта (DECOR)
var house_layout: Dictionary = {}      # категория -> [ax, ay] пользовательской расстановки
var house_owned: Dictionary = {}   # категория -> Array[String] купленных id (коллекция, локально)
var _theme_custom_on := false
var _theme_custom := Color("#0d1219")
var _aura_custom_on := false
var _aura_custom := Color("#ffb85c")
var _cosmetic_wall := Color("#5a4d40")
var _cosmetic_floor := Color("#5d452f")
var _decor_cat_btns := {}
var _decor_cat_thumbs := {}   # категория -> HouseView-превью текущего варианта
var _decor_cat_labels := {}   # категория -> Label («Ковёр · 3/10»)
var _collection_lbl: Label = null
var _decor_cat_open := ""
var _decor_popup: Control = null
var _decor_list: VBoxContainer = null
var _decor_title: Label = null
var _decor_preview = null  # живое превью домика в магазине (HouseView, без анимации)
var _wall_btn: Button = null
var _floor_btn: Button = null
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
var _house_popup_view: Control = null
var _house_popup_title: Label = null

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
		g._bg_rect.color = _theme_now()
	if g._spirit._companion != null:
		g._spirit._companion.set_aura(_aura_now())
	_refresh_house_view()


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


func _decor_cat(cat_id: String) -> Dictionary:
	for c in Game.DECOR:
		if String(c["id"]) == cat_id:
			return c
	return {}


func _decor_item(cat_id: String, item_id: String) -> Dictionary:
	var cat := _decor_cat(cat_id)
	if cat.is_empty():
		return {}
	var items: Array = cat.get("items", [])
	for it in items:
		if String(it["id"]) == item_id:
			return it
	return items[0] if not items.is_empty() else {}


func _decor_current(cat_id: String) -> String:
	var v := String(house_furniture.get(cat_id, ""))
	if v == "":
		v = cat_id
	return v


func _decor_default(cat_id: String) -> String:
	var cat := _decor_cat(cat_id)
	var items: Array = cat.get("items", [])
	return String(items[0]["id"]) if not items.is_empty() else cat_id


func _decor_owned(cat_id: String, item_id: String) -> bool:
	if item_id == _decor_default(cat_id):
		return true
	return item_id in (house_owned.get(cat_id, []) as Array)


func _own_item(cat_id: String, item_id: String) -> void:
	if item_id == _decor_default(cat_id):
		return
	var arr: Array = house_owned.get(cat_id, [])
	if not arr.has(item_id):
		arr.append(item_id)
	house_owned[cat_id] = arr


func _decor_owned_count(cat_id: String) -> int:
	var seen := {_decor_default(cat_id): true}
	for v in house_owned.get(cat_id, []):
		seen[String(v)] = true
	return seen.size()


func _collection_owned() -> int:
	var n := 0
	for c in Game.DECOR:
		n += _decor_owned_count(String(c["id"]))
	return n


func _collection_total() -> int:
	var n := 0
	for c in Game.DECOR:
		n += (c.get("items", []) as Array).size()
	return n


func _house_furn() -> Dictionary:
	var t := {}
	for c in Game.DECOR:
		var cid := String(c["id"])
		t[cid] = _decor_current(cid)
	return t


func _decor_label(cat_id: String, item_id: String) -> String:
	var it := _decor_item(cat_id, item_id)
	var lab := String(it.get("label", ""))
	if lab != "":
		return lab
	var cat := _decor_cat(cat_id)
	return String(cat.get("label", cat_id))


func _decor_cost(cat_id: String, item_id: String) -> int:
	var it := _decor_item(cat_id, item_id)
	return int(it.get("cost", 0))


func _on_house_layout_changed(layout: Dictionary) -> void:
	# Перетаскивание — часть сохранённого состояния домика, а не только
	# временный рисунок текущего кадра.
	house_layout = layout.duplicate(true)
	g._saves._save_game()
	_upload_house()
	g._engine.status_text = "Расстановка домика сохранена."


func _refresh_house_view() -> void:
	_sync_house_view(_house_view)


func _sync_house_view(view) -> void:
	if view == null:
		return
	var tex: Texture2D = null
	if g._spirit._companion != null:
		tex = g._spirit._companion.sprite_tex("idle")
	view.set_state(_cosmetic_house, _house_furn(), tex, _aura_now(),
		_cosmetic_wall, _cosmetic_floor, house_layout)


func _build_house_page(page: VBoxContainer) -> void:
	var t := g._label("ДОМ СВЕТИКА", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	page.add_child(t)
	var sub := g._label("Уют, обстановка и произвольные цвета. Это навсегда и видно другим игрокам.", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	page.add_child(sub)

	_house_view = Game.HouseViewScript.new()
	_house_view.set_editable(true)
	_house_view.layout_changed.connect(_on_house_layout_changed)
	_house_view.custom_minimum_size = Vector2(0, 300)
	page.add_child(_house_view)
	_house_hint = g._label("", 12)
	_house_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_house_hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
	page.add_child(_house_hint)

	_house_btn = g._small_button("", Vector2(0, 46), 2)
	_house_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_house_btn.pressed.connect(_buy_house)
	page.add_child(_house_btn)

	page.add_child(g._label("Обстановка", 14))
	_collection_lbl = g._label("", 12)
	_collection_lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	page.add_child(_collection_lbl)
	_furniture_shop = VBoxContainer.new()
	_furniture_shop.add_theme_constant_override("separation", 6)
	page.add_child(_furniture_shop)
	for c in Game.DECOR:
		var cid := String(c["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_furniture_shop.add_child(row)
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(76, 50)
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(0.05, 0.08, 0.12, 0.9)
		fsb.set_corner_radius_all(8)
		frame.add_theme_stylebox_override("panel", fsb)
		row.add_child(frame)
		var thumb := Game.HouseViewScript.new()
		thumb.animate = false
		thumb.set_editable(false)
		thumb.custom_minimum_size = Vector2(76, 50)
		frame.add_child(thumb)
		_decor_cat_thumbs[cid] = thumb
		var lbl := g._label(String(c["label"]), 14)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		_decor_cat_labels[cid] = lbl
		var b := g._small_button("Выбрать", Vector2(160, 40), 1)
		b.pressed.connect(_open_decor_shop.bind(cid))
		row.add_child(b)
		_decor_cat_btns[cid] = b

	page.add_child(g._label("Тема лаборатории (фон)", 14))
	var theme_grid := GridContainer.new()
	theme_grid.columns = 2
	theme_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_grid.add_theme_constant_override("h_separation", 6)
	theme_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(theme_grid)
	for th in Game.WORKSHOP_THEMES:
		var b := g._small_button("", Vector2(0, 42))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_buy_theme.bind(String(th["id"]), int(th["cost"])))
		theme_grid.add_child(b)
		_theme_btns[String(th["id"])] = b
	var th_c := g._small_button("Палитра", Vector2(0, 42))
	th_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th_c.pressed.connect(_open_color_picker.bind("theme"))
	page.add_child(th_c)
	_theme_btns["__custom"] = th_c

	page.add_child(g._label("Аура Светика", 14))
	var aura_grid := GridContainer.new()
	aura_grid.columns = 2
	aura_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aura_grid.add_theme_constant_override("h_separation", 6)
	aura_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(aura_grid)
	for au in Game.WORKSHOP_AURAS:
		var b := g._small_button("", Vector2(0, 42))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_buy_aura.bind(String(au["id"]), int(au["cost"])))
		aura_grid.add_child(b)
		_aura_btns[String(au["id"])] = b
	var au_c := g._small_button("Палитра", Vector2(0, 42))
	au_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	au_c.pressed.connect(_open_color_picker.bind("aura"))
	page.add_child(au_c)
	_aura_btns["__custom"] = au_c

	page.add_child(g._label("Цвета домика (палитра)", 14))
	var home_row := HBoxContainer.new()
	home_row.add_theme_constant_override("separation", 6)
	page.add_child(home_row)
	_wall_btn = g._small_button("Стены", Vector2(0, 42))
	_wall_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wall_btn.pressed.connect(_open_color_picker.bind("wall"))
	home_row.add_child(_wall_btn)
	_floor_btn = g._small_button("Пол", Vector2(0, 42))
	_floor_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_floor_btn.pressed.connect(_open_color_picker.bind("floor"))
	home_row.add_child(_floor_btn)

	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 150)
	page.add_child(bottom_pad)
	_refresh_house_page()


func _open_workshop() -> void:
	_refresh_house_page()
	if g._tabs_ref != null:
		g._tabs_ref.current_tab = 3
	Sfx.click()


func _refresh_house_page() -> void:
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
		b.disabled = cur
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
		if sid == "hearth" and not g._retention._circle_hearth_aura():
			b.disabled = true
			b.text = "Очаг · веха 365"
			continue
		var cur := sid == _cosmetic_aura and not _aura_custom_on
		b.disabled = cur
		if cur:
			b.text = "%s ✓" % _aura_label(sid)
		else:
			b.text = "%s · %d ⚡" % [_aura_label(sid), _aura_cost(sid)]
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
			_house_btn.disabled = true
		else:
			_house_btn.text = "Построить домик Светика (−%d ⚡)" % Game.HOUSE_COST
			_house_btn.disabled = false
	if _furniture_shop != null:
		_furniture_shop.visible = _cosmetic_house
	if _collection_lbl != null:
		_collection_lbl.visible = _cosmetic_house
		_collection_lbl.text = "Коллекция: %d/%d · купленное ставится бесплатно" % [_collection_owned(), _collection_total()]
	for id in _decor_cat_btns:
		var cidx := String(id)
		var b: Button = _decor_cat_btns[id]
		b.disabled = not _cosmetic_house
		b.text = "%s ✓" % _decor_label(cidx, _decor_current(cidx))
		if _decor_cat_labels.has(cidx):
			var cat := _decor_cat(cidx)
			(_decor_cat_labels[cidx] as Label).text = "%s · %d/%d" % [String(cat.get("label", cidx)), _decor_owned_count(cidx), (cat.get("items", []) as Array).size()]
		if _decor_cat_thumbs.has(cidx):
			var th = _decor_cat_thumbs[cidx]
			th.set_solo(_decor_current(cidx))
	if _house_hint != null:
		_house_hint.text = "Светик парит в домике. Выбирай обстановку и цвета — всё видно гостям." if _cosmetic_house \
			else "Сначала построй домик — потом обставишь его."
	_refresh_house_view()


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
	_refresh_house_page()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	g._engine.status_text = "Тема «%s» применена. Лаборатория стала уютнее!" % _theme_label(id)
	Sfx.stage_up()


func _buy_aura(id: String, cost: int) -> void:
	if id == _cosmetic_aura and not _aura_custom_on:
		return
	if id == "hearth" and not g._retention._circle_hearth_aura():
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
	_refresh_house_page()
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
	_apply_cosmetic()
	_refresh_house_page()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	g._engine.status_text = "Домик готов! Светик теперь порхает над собственным гнёздышком."
	Sfx.legendary()


func _buy_furniture(cat_id: String, variant_id: String) -> void:
	if not _cosmetic_house:
		g._engine.status_text = "Сначала построй домик Светика."
		Sfx.error()
		return
	if _decor_current(cat_id) == variant_id:
		return
	if _decor_owned(cat_id, variant_id):
		# купленное ставится бесплатно
		house_furniture[cat_id] = variant_id
		_refresh_house_page()
		g._engine._refresh()
		g._saves._save_game()
		_upload_house()
		if _decor_popup != null and _decor_popup.visible and _decor_cat_open == cat_id:
			_rebuild_decor_popup()
		g._engine.status_text = "%s: «%s» — снова в домике!" % [_decor_cat(cat_id).get("label", cat_id), _decor_label(cat_id, variant_id)]
		Sfx.click()
		return
	var cost := _decor_cost(cat_id, variant_id)
	if g._engine._available_ether() < cost:
		g._engine.status_text = "Не хватает эфира: %s стоит %d ⚡." % [_decor_label(cat_id, variant_id), cost]
		Sfx.error()
		return
	g._engine._spend_ether(cost)
	house_furniture[cat_id] = variant_id
	_own_item(cat_id, variant_id)
	_refresh_house_page()
	g._engine._refresh()
	g._saves._save_game()
	_upload_house()
	# магазин живьём: новый ✓ и обновлённое превью домика
	if _decor_popup != null and _decor_popup.visible and _decor_cat_open == cat_id:
		_rebuild_decor_popup()
	g._engine.status_text = "%s: «%s» — теперь в домике!" % [_decor_cat(cat_id).get("label", cat_id), _decor_label(cat_id, variant_id)]
	Sfx.stage_up()


# ---------- магазин декора (отдельное окно на категорию) ----------

func _open_decor_shop(cat_id: String) -> void:
	if not _cosmetic_house:
		g._engine.status_text = "Сначала построй домик Светика."
		Sfx.error()
		return
	_decor_cat_open = cat_id
	_rebuild_decor_popup()
	if _decor_popup != null:
		_decor_popup.visible = true
	Sfx.click()


func _rebuild_decor_popup() -> void:
	if _decor_popup == null:
		return
	var cat := _decor_cat(_decor_cat_open)
	_decor_title.text = String(cat.get("label", "Обстановка"))
	_sync_house_view(_decor_preview)
	var items: Array = cat.get("items", [])
	# очистка списка
	for child in _decor_list.get_children():
		_decor_list.remove_child(child)
		child.queue_free()
	for it in items:
		var item_id := String(it["id"])
		var cur := _decor_current(_decor_cat_open) == item_id
		var owned := _decor_owned(_decor_cat_open, item_id)
		var card := HBoxContainer.new()
		card.add_theme_constant_override("separation", 8)
		_decor_list.add_child(card)
		# превью силуэта варианта: видно, ЧТО покупаешь (п.2)
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(104, 62)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.08, 0.12, 0.9)
		sb.set_corner_radius_all(10)
		sb.border_color = Color(1.0, 0.9, 0.4, 0.9) if cur else Color(0, 0, 0, 0.35)
		sb.set_border_width_all(2 if cur else 1)
		frame.add_theme_stylebox_override("panel", sb)
		card.add_child(frame)
		var prev := Game.HouseViewScript.new()
		prev.animate = false
		prev.set_editable(false)
		prev.custom_minimum_size = Vector2(104, 62)
		frame.add_child(prev)
		prev.set_solo(item_id)
		var lbl := g._label(String(it["label"]), 13)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = true
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(lbl)
		var btn := g._small_button("", Vector2(92, 40), 0 if cur else 1)
		if cur:
			btn.text = "Есть ✓"
			btn.disabled = true
		elif owned:
			btn.text = "Поставить"
			btn.pressed.connect(_buy_furniture.bind(_decor_cat_open, item_id))
		else:
			btn.text = "%d ⚡" % int(it["cost"])
			btn.pressed.connect(_buy_furniture.bind(_decor_cat_open, item_id))
		card.add_child(btn)


func _close_decor_popup() -> void:
	if _decor_popup != null:
		_decor_popup.visible = false
	_refresh_house_page()
	# после магазина — наверх страницы, к домику: результат выбора виден сразу (п.3)
	if g._tabs_ref != null and g._tabs_ref.current_tab == 3:
		g._demo_harness._set_page_scroll(0)
	Sfx.click()


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
			_refresh_house_page()
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
	_refresh_house_page()
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
	_refresh_house_page()
	if persist:
		g._saves._save_game()
		_upload_house()


func _swatch_button(hex: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(42, 42)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(hex)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
	return b


# ---------- домик: сериализация для сервера ----------

func _house_json() -> Dictionary:
	return {
		"v": 1,
		"built": _cosmetic_house,
		"theme": _cosmetic_theme,
		"aura": _cosmetic_aura,
		"theme_custom": _theme_custom.to_html(false) if _theme_custom_on else "",
		"aura_custom": _aura_custom.to_html(false) if _aura_custom_on else "",
		"wall": _cosmetic_wall.to_html(false),
		"floor": _cosmetic_floor.to_html(false),
		"furniture": house_furniture,
		"layout": house_layout,
	}


func _upload_house() -> void:
	if not g._online._net_enabled or not _cosmetic_house:
		return
	if g._online._net_nick == "" or g._online._device_id == "":
		return
	Net.house_save(g._online._device_id, g._online._net_nick, _house_json())


# ---------- окна: магазин декора / палитра / гостевой домик ----------

func _build_decor_popup() -> void:
	var root := Control.new()
	root.name = "DecorPopup"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	# Магазин — modal surface, а не обычный sibling страницы. Выводим его
	# глобально поверх TabContainer, домика, фона и нижней панели.
	root.z_as_relative = false
	root.z_index = 100
	g.add_child(root)
	_decor_popup = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 0
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 1
	root.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	_decor_title = g._label("Обстановка", 18)
	_decor_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_decor_title)
	# живое превью домика: результат выбора виден сразу, не выходя из магазина (п.3)
	_decor_preview = Game.HouseViewScript.new()
	_decor_preview.animate = false
	_decor_preview.set_editable(false)
	_decor_preview.custom_minimum_size = Vector2(0, 168)
	col.add_child(_decor_preview)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	# VBox с фиксированной шириной вместо GridContainer: сетка схлопывала колонку,
	# подписи разъезжались в столбик, а строки растягивались (п.1)
	_decor_list = VBoxContainer.new()
	_decor_list.custom_minimum_size = Vector2(344, 0)
	_decor_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_decor_list)
	var close := g._small_button("Закрыть", Vector2(0, 46), 0)
	close.pressed.connect(_close_decor_popup)
	col.add_child(close)


func _build_color_picker() -> void:
	var root := Control.new()
	root.name = "ColorPicker"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
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
	var ok := g._small_button("Готово", Vector2(0, 46), 2)
	ok.pressed.connect(_confirm_color_picker)
	col.add_child(ok)
	_cp_ok = ok


func _build_house_popup() -> void:
	var root := Control.new()
	root.name = "HousePopup"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
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
	_house_popup_view = Game.HouseViewScript.new()
	_house_popup_view.set_editable(false)
	_house_popup_view.custom_minimum_size = Vector2(0, 260)
	col.add_child(_house_popup_view)
	var close := g._small_button("Закрыть", Vector2(0, 46), 0)
	close.pressed.connect(_close_house_popup)
	col.add_child(close)


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
	var built := bool(h.get("built", false))
	var wall := _color_from_hex(String(h.get("wall", "")), Color("#5a4d40"))
	var floor := _color_from_hex(String(h.get("floor", "")), Color("#5d452f"))
	var aura := _color_from_hex(String(h.get("aura_custom", "")), Color.TRANSPARENT)
	if aura.a == 0.0 or aura == Color.TRANSPARENT:
		aura = _aura_color(String(h.get("aura", "amber")))
	# Серверный JSON может содержать только купленные варианты. Для гостевого
	# просмотра сначала восстанавливаем дефолтный полный набор, иначе
	# настольная лампа окажется без стола и ошибочно станет напольной.
	var furn := {}
	for c in Game.DECOR:
		var default_cat := String(c["id"])
		furn[default_cat] = _decor_default(default_cat)
	if typeof(h.get("furniture")) == TYPE_DICTIONARY:
		for k in h["furniture"]:
			var cat := String(k)
			var vid := String(h["furniture"][k])
			var item := _decor_item(cat, vid)
			if not item.is_empty() and String(item.get("id", "")) == vid:
				furn[cat] = vid
	var tex: Texture2D = g._spirit._companion.sprite_tex("idle") if g._spirit._companion != null else null
	var layout: Dictionary = {}
	if typeof(h.get("layout", {})) == TYPE_DICTIONARY:
		layout = h.get("layout", {}) as Dictionary
	_house_popup_title.text = "Домик: %s" % nick
	_house_popup_view.set_state(built, furn, tex, aura, wall, floor, layout)
	_house_popup_view.set_editable(false)


func _open_player_house(nick: String) -> void:
	if _house_popup != null:
		_house_popup.visible = true
	_house_popup_title.text = "Домик: %s" % nick
	_apply_player_house(nick, {})
	Net.house_get(nick)


func _close_house_popup() -> void:
	if _house_popup != null:
		_house_popup.visible = false
	Sfx.click()
