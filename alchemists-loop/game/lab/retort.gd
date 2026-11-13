extends RefCounted
class_name Retort
# Ночная реторта (R6): долгий сосуд 8–24 ч, эссенции, выбор вещества.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _retort_slots: Array = []
var _essence_inv: Dictionary = {}
var _essence_codex: Dictionary = {}
var _legacy_cap_bonus: int = 0
var _cube_levels := {"queue": 0, "offline": 0, "slots": 0, "speed": 0, "complexity": 0, "blend": 0, "cap": 0, "equip": 0}
var _queue: Array = []
var _queue_on: bool = false
var _queue_cursor: int = 0
var _queue_window_start: float = 0.0
var _blend: Dictionary = {}
var _retort_head: Label = null
var _retort_desc: Label = null
var _retort_cards: VBoxContainer = null
var _retort_ess: Label = null
var _retort_art_scene: Control = null
var _retort_art: Node2D = null
var _retort_sprite: Sprite2D = null
var _retort_fluid: Sprite2D = null
var _retort_drops: Sprite2D = null
var _retort_fluid_mat: ShaderMaterial = null
var _retort_drops_mat: ShaderMaterial = null
var _retort_ui: Array = []
var _retort_dim: ColorRect = null
var _retort_popup: CenterContainer = null
var _retort_list: VBoxContainer = null
var _retort_pick_slot := -1
var _retort_pick_queue := false
var _retort_pages: Dictionary = {}
var _retort_tab_buttons: Dictionary = {}
var _retort_tab := "cube"

const AXES := ["queue", "offline", "slots", "speed", "complexity", "blend", "cap", "equip"]
const ELEMENTS := ["fire", "water", "earth", "air"]
const PIP_ON := Color(0.96, 0.78, 0.42)
const PIP_OFF := Color(0.42, 0.34, 0.26)
var _rows: Dictionary = {}
var _essence_cells: Dictionary = {}
var _codex_list: HFlowContainer = null
var _queue_flow: HBoxContainer = null
var _queue_rail: ScrollContainer = null
var _queue_add_btn: Button = null
var _queue_toggle: Button = null
var _queue_status: Label = null
var _queue_selected: int = -1
var _queue_replace_index: int = -1
var _queue_edit_actions: VBoxContainer = null
var _queue_replace_btn: Button = null
var _queue_remove_btn: Button = null
var _queue_press_position := Vector2.ZERO
var _queue_pressing: bool = false
var _blend_buttons: Dictionary = {}
var _blend_state: Label = null
var _blend_collect_btn: Button = null

func _init(game: Game) -> void:
	g = game

# ---------- ночная реторта: долгий сосуд 8–24 ч ----------

func _retort_now(when: float = -1.0) -> float:
	return when if when >= 0.0 else Time.get_unix_time_from_system()

func _retort_hours_for_tier(tier: int) -> float:
	var base := Game.RETORT_BASE_HOURS * (1.0 + float(maxi(0, tier)) * 0.5)
	var speed: float = RetortBalance.SPEED_FACTOR[clampi(_level("speed"), 0, RetortBalance.SPEED_FACTOR.size() - 1)]
	return maxf(Game.MASTERY_RETORT_MIN_HOURS, base * speed * _retort_mastery_factor())

func _retort_mastery_factor() -> float:
	# A2: каждый ранг ≥ 2 снимает 6 % срока; ранг 1 — без бонуса. Пол — 6 ч.
	var ranks := maxi(0, g._engine.mastery_rank - 1)
	return maxf(0.0, 1.0 - Game.MASTERY_RETORT_SPEED * float(ranks))

func _retort_hours_text(tier: int) -> String:
	return "%d ч" % int(_retort_hours_for_tier(tier))

func _retort_slots_open() -> int:
	return mini(1 + _level("slots"), Game.RETORT_SLOT_MAX)

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

func essence_of(sub: String) -> String:
	var tier := int(g._engine._rarity_of(sub).get("tier", 0))
	if RetortBalance.is_material(sub):
		tier = mini(tier, 2)
	var element := RetortBalance.element_of(sub)
	var category := String(g.ITEMS.get(sub, {}).get("category", ""))
	if not category.is_empty():
		element = String(RetortBalance.ELEMENT_BY_CATEGORY.get(category, "earth"))
	return "%s-%d" % [element, tier]

func essence_count(id: String) -> int:
	return int(_essence_inv.get(id, 0))

func essence_known(id: String) -> bool:
	return _essence_codex.has(id)

func _essence_add(id: String, n: int = 1) -> void:
	_essence_inv[id] = int(_essence_inv.get(id, 0)) + n
	_essence_codex[id] = true

func _essence_can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if essence_count(String(id)) < int(cost[id]):
			return false
	return true

func _essence_spend(cost: Dictionary) -> void:
	for id in cost:
		_essence_inv[id] = int(_essence_inv.get(id, 0)) - int(cost[id])

func migrate_legacy_essences(old_ess: Dictionary) -> void:
	for sub in old_ess:
		var id := essence_of(String(sub))
		_essence_codex[id] = true
		_essence_inv[id] = int(_essence_inv.get(id, 0)) + 1
	_legacy_cap_bonus = Game.RETORT_CAP_EACH * mini(old_ess.size(), Game.RETORT_CAP_FIRST)

func _essence_cap_bonus() -> int:
	return _legacy_cap_bonus

func _level(axis: String) -> int:
	return int(_cube_levels.get(axis, 0))

func _max_distill_tier() -> int:
	return RetortBalance.COMPLEXITY_MAX_TIER[clampi(_level("complexity"), 0, RetortBalance.COMPLEXITY_MAX_TIER.size() - 1)]

func _axis_table(axis: String) -> Array:
	match axis:
		"queue": return RetortBalance.QUEUE
		"offline": return RetortBalance.OFFLINE
		"slots": return RetortBalance.SLOTS
		"speed": return RetortBalance.SPEED
		"complexity": return RetortBalance.COMPLEXITY
		"blend": return RetortBalance.BLEND
		"cap": return RetortBalance.CAP
		"equip": return RetortBalance.EQUIP
	return []

func cube_purchase(axis: String) -> Dictionary:
	var table := _axis_table(axis)
	var lvl := _level(axis)
	if lvl >= table.size():
		return {"ok": false, "error": "Максимум"}
	var price: Dictionary = table[lvl]
	var req: Dictionary = price.get("req", {})
	for r in req:
		if _level(String(r)) < int(req[r]):
			return {"ok": false, "error": "Сначала %s %d" % [r, int(req[r])]}
	var cost: Dictionary = price.get("essences", {})
	if not _essence_can_afford(cost):
		return {"ok": false, "error": "Не хватает эссенций"}
	_essence_spend(cost)
	_cube_levels[axis] = lvl + 1
	if axis == "equip":
		g._workshop.materialize_lines()
		g._workshop.changed.emit()
	return {"ok": true}

func _essence_cap_line_bonus() -> int:
	var total := 0
	for i in mini(_level("cap"), RetortBalance.CAP.size()):
		total += int(RetortBalance.CAP[i].get("cap", 0))
	return total

func _workshop_bonus_lines() -> int:
	var n := 0
	for i in mini(_level("equip"), RetortBalance.EQUIP.size()):
		n += int(RetortBalance.EQUIP[i].get("lines", 0))
	return n

func _workshop_speed_factor() -> float:
	var f := 1.0
	for i in mini(_level("equip"), RetortBalance.EQUIP.size()):
		f *= float(RetortBalance.EQUIP[i].get("speed", 1.0))
	return f

func _queue_depth() -> int:
	return RetortBalance.QUEUE_DEPTH[clampi(_level("queue"), 0, RetortBalance.QUEUE_DEPTH.size() - 1)]

func _offline_window() -> float:
	return RetortBalance.OFFLINE_WINDOW_SEC[clampi(_level("offline"), 0, RetortBalance.OFFLINE_WINDOW_SEC.size() - 1)]

func queue_set(program: Array) -> bool:
	if program.size() > _queue_depth():
		return false
	_queue = program.duplicate(true)
	_queue_cursor = 0
	return true

func queue_toggle(on: bool) -> void:
	_queue_on = on
	_queue_window_start = Time.get_unix_time_from_system()

func _queue_advance(now: float = -1.0, offline: bool = false) -> void:
	if not _queue_on:
		return
	var t := _retort_now(now)
	# Занятые сосуды остаются доступны после миграции даже при уменьшенной оси ячеек.
	for i in Game.RETORT_SLOT_MAX:
		if _retort_ready(i, t):
			_retort_collect(i, t)
	if _queue.is_empty() or (offline and t - _queue_window_start >= _offline_window()):
		return
	for i in _retort_slots_open():
		if _retort_busy(i):
			continue
		var started := false
		for attempt in _queue.size():
			var idx := (_queue_cursor + attempt) % _queue.size()
			if not _queue[idx] is Dictionary:
				continue
			var sub := String(_queue[idx].get("sub", ""))
			if not g.ITEMS.has(sub):
				continue
			if int(g._engine.inventory.get(sub, 0)) >= 1 and int(g._engine._rarity_of(sub).get("tier", 0)) <= _max_distill_tier():
				if _retort_start(i, sub, t):
					_queue_cursor = (idx + 1) % _queue.size()
					started = true
					break
		if not started:
			break # нет вещества ни для одного шага — ждём, программа не сгорает

func _queue_offline_replay(from_ts: float, to_ts: float) -> void:
	# Событийный проход: каждое созревание собирается в свой момент, после чего
	# свободный сосуд сразу получает следующий шаг программы. Один вызов на now
	# терял все промежуточные циклы длинного офлайн-окна.
	if not _queue_on:
		return
	var t := maxf(0.0, from_ts)
	var finish := maxf(t, to_ts)
	_queue_window_start = t
	var deadline := t + _offline_window()
	while true:
		_queue_advance(t, true)
		if _queue.is_empty() or t >= deadline:
			break
		var next_t := INF
		for i in Game.RETORT_SLOT_MAX:
			if not _retort_busy(i):
				continue
			var slot := _retort_slot(i)
			var ready_at := float(slot.get("started", 0.0)) + float(slot.get("dur", 0.0))
			next_t = minf(next_t, ready_at)
		if next_t == INF or next_t > minf(finish, deadline):
			break
		t = next_t
	if finish > t:
		# Созревшее за пределами окна можно забрать, но новые циклы там не стартуют.
		_queue_advance(finish, true)

func _blend_hours() -> float:
	var blend_factor := 0.6 if _level("blend") >= 2 else 1.0
	return 12.0 * RetortBalance.SPEED_FACTOR[clampi(_level("speed"), 0, RetortBalance.SPEED_FACTOR.size() - 1)] * blend_factor

func blend_ready(now: float = -1.0) -> bool:
	if _blend.is_empty():
		return false
	return _retort_now(now) - float(_blend.get("started", 0.0)) >= float(_blend.get("dur", 0.0))

func blend_start(element: String, now: float = -1.0) -> bool:
	if _level("blend") < 1 or not _blend.is_empty() or not RetortBalance.BLEND_RECIPES.has(element):
		return false
	var cost := {}
	for id in RetortBalance.BLEND_RECIPES[element]:
		cost[id] = int(cost.get(id, 0)) + 1
	if not _essence_can_afford(cost):
		return false
	_essence_spend(cost)
	_blend = {"out": "blend-" + element, "started": _retort_now(now), "dur": _blend_hours() * 3600.0}
	return true

func blend_collect(now: float = -1.0) -> Dictionary:
	if not blend_ready(now):
		return {"ok": false}
	var out := String(_blend.get("out", ""))
	_blend = {}
	_essence_add(out, 1)
	return {"ok": true, "essence": out}

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
	if tier > _max_distill_tier():
		return false
	var dur := _retort_hours_for_tier(tier) * 3600.0
	g._engine.inventory[sub] = int(g._engine.inventory[sub]) - 1
	g._engine._spring_burn(sub)
	_retort_slots[slot] = {"sub": sub, "name": g._online._item_name(sub),
		"essence": essence_of(sub), "tier": tier,
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
		g._engine._spring_unburn(sub)
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
	var essence := String(s.get("essence", ""))
	if essence == "":
		essence = essence_of(sub)
	_retort_slots[slot] = {"sub": "", "name": "", "started": 0.0, "dur": 0.0}
	_essence_add(essence, 1)
	var res := {"ok": true, "essence": essence, "name": nm}
	if not g._selftest:
		g._online._set_status("Эссенция «%s»: %s." % [nm, essence])
		g._hub._log_event("Реторта: эссенция «%s» (%s)" % [nm, essence])
		Sfx.discovery()
		Input.vibrate_handheld(25)
		g._engine._refresh()
		g._saves._save_game()
	_refresh_retort_page()
	return res

func _build_retort_page(container: VBoxContainer) -> void:
	_retort_ui.clear()
	_rows.clear()
	_essence_cells.clear()
	_retort_pages.clear()
	_retort_tab_buttons.clear()
	_blend_buttons.clear()
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.name = "RetortV2"
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	col.add_child(g._label("Экспериментальный куб", 18))
	_retort_desc = g._label("Дистиллируй вещества в типизированные эссенции и вложи их в постоянные улучшения.", 12)
	_retort_desc.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	col.add_child(_retort_desc)
	_retort_head = g._label("", 13)
	col.add_child(_retort_head)

	var tabs := HFlowContainer.new()
	tabs.name = "RetortTabs"
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	col.add_child(tabs)
	var tab_specs := [["cube", "Куб"], ["essences", "Эссенции"], ["tree", "Улучшения"], ["queue", "Очередь"]]
	for spec in tab_specs:
		var key := String(spec[0])
		var chip := g._small_button(String(spec[1]), Vector2(0, 40))
		chip.name = "RetortTab_" + key
		chip.toggle_mode = true
		chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		chip.pressed.connect(_select_retort_tab.bind(key))
		tabs.add_child(chip)
		_retort_tab_buttons[key] = chip
	for spec in tab_specs:
		var key := String(spec[0])
		var page := VBoxContainer.new()
		page.name = "RetortPage_" + key
		page.add_theme_constant_override("separation", 10)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(page)
		_retort_pages[key] = page

	# Общий аппарат остаётся над активной вкладкой; жидкие слои живут в трансформации 512×512.
	var apparatus := _retort_section(col, "Аппарат")
	col.move_child(apparatus.get_parent(), tabs.get_index() + 1)
	_retort_art_scene = Control.new()
	_retort_art_scene.custom_minimum_size = Vector2(0, 216)
	_retort_art_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retort_art_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_retort_art_scene.resized.connect(_layout_retort_art)
	apparatus.add_child(_retort_art_scene)
	_retort_art = Node2D.new()
	_retort_art_scene.add_child(_retort_art)
	_retort_sprite = Sprite2D.new()
	_retort_art.add_child(_retort_sprite)
	_retort_fluid = Sprite2D.new()
	_retort_fluid.z_index = 1
	_retort_fluid_mat = ShaderMaterial.new()
	_retort_fluid_mat.shader = load("res://assets/spring/spring_water.gdshader")
	_retort_fluid.material = _retort_fluid_mat
	_retort_art.add_child(_retort_fluid)
	_retort_drops = Sprite2D.new()
	_retort_drops.z_index = 2
	_retort_drops_mat = ShaderMaterial.new()
	_retort_drops_mat.shader = load("res://assets/retort/retort_drops.gdshader")
	_retort_drops.material = _retort_drops_mat
	_retort_drops.position = Vector2(-186, 70)
	_retort_drops.scale = Vector2(84.0 / 512.0, 84.0 / 512.0)
	_retort_art.add_child(_retort_drops)

	# 2. Все 24 типа видны сразу: неизвестные обозначены знаком вопроса.
	var inventory := _retort_section(_retort_pages["essences"], "Инвентарь эссенций")
	var essence_grid := GridContainer.new()
	essence_grid.columns = 3
	essence_grid.add_theme_constant_override("h_separation", 6)
	essence_grid.add_theme_constant_override("v_separation", 6)
	inventory.add_child(essence_grid)
	for id in _essence_ids():
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_stylebox_override("panel", UIStyle.panel())
		essence_grid.add_child(cell)
		var text := g._label("?", 12)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(text)
		_essence_cells[id] = text

	# 3. Улучшения куба и два внешних sink'а.
	var tree := _retort_section(_retort_pages["tree"], "Улучшения экспериментального куба")
	var axis_grid := GridContainer.new()
	axis_grid.columns = 2
	axis_grid.add_theme_constant_override("h_separation", 8)
	axis_grid.add_theme_constant_override("v_separation", 8)
	tree.add_child(axis_grid)
	for axis in AXES:
		axis_grid.add_child(_build_axis_card(axis))

	# 4. Программа редактируется компактными чипами через общий пикер веществ.
	var queue_box := _retort_section(_retort_pages["queue"], "Авто-очередь")
	_queue_status = g._label("", 12)
	_queue_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_queue_status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	queue_box.add_child(_queue_status)
	var queue_line := HBoxContainer.new()
	queue_line.name = "RetortQueueLine"
	queue_line.add_theme_constant_override("separation", 6)
	queue_box.add_child(queue_line)
	var queue_rail := ScrollContainer.new()
	queue_rail.name = "RetortQueueRail"
	queue_rail.custom_minimum_size = Vector2(0, 136)
	queue_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	queue_rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_rail.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_queue_rail = queue_rail
	queue_rail.gui_input.connect(_on_queue_rail_gui_input)
	queue_line.add_child(queue_rail)
	_queue_flow = HBoxContainer.new()
	_queue_flow.name = "RetortQueueProgram"
	_queue_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_flow.add_theme_constant_override("separation", 0)
	queue_rail.add_child(_queue_flow)
	_queue_edit_actions = VBoxContainer.new()
	_queue_edit_actions.name = "RetortQueueEditActions"
	_queue_edit_actions.visible = false
	_queue_edit_actions.custom_minimum_size = Vector2(88, 30)
	_queue_edit_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_queue_edit_actions.add_theme_constant_override("separation", 6)
	queue_line.add_child(_queue_edit_actions)
	_queue_replace_btn = g._small_button("Заменить", Vector2(88, 30))
	_queue_replace_btn.custom_minimum_size = Vector2(88, 30)
	_queue_replace_btn.add_theme_font_size_override("font_size", 12)
	_queue_replace_btn.name = "RetortQueueReplace"
	_queue_replace_btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	_queue_replace_btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_queue_replace_btn.pressed.connect(_open_queue_replace)
	_queue_edit_actions.add_child(_queue_replace_btn)
	_queue_remove_btn = g._small_button("Убрать", Vector2(80, 30))
	_queue_remove_btn.custom_minimum_size = Vector2(80, 30)
	_queue_remove_btn.add_theme_font_size_override("font_size", 12)
	_queue_remove_btn.name = "RetortQueueRemoveSelected"
	_queue_remove_btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	_queue_remove_btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_queue_remove_btn.pressed.connect(_queue_remove_selected)
	_queue_edit_actions.add_child(_queue_remove_btn)
	var queue_actions := HBoxContainer.new()
	queue_actions.add_theme_constant_override("separation", 8)
	queue_box.add_child(queue_actions)
	_queue_add_btn = g._small_button("+ Добавить", Vector2(118, 40), 1)
	_queue_add_btn.name = "RetortQueueAdd"
	_queue_add_btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	_queue_add_btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_queue_add_btn.pressed.connect(_open_queue_picker)
	queue_actions.add_child(_queue_add_btn)
	_queue_toggle = g._small_button("Пустить", Vector2(0, 40), 1)
	_queue_toggle.name = "RetortQueueToggle"
	_queue_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_toggle.autowrap_mode = TextServer.AUTOWRAP_OFF
	_queue_toggle.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_queue_toggle.pressed.connect(func() -> void: _on_queue_toggled(not _queue_on))
	queue_actions.add_child(_queue_toggle)
	var queue_hint := g._label("Реторта повторяет программу по кругу, пока есть вещества и свободные сосуды.", 11)
	queue_hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	queue_box.add_child(queue_hint)

	# 5. Кодекс — только фактически открытые эссенции, счётчик отделён от запасов.
	var codex := _retort_section(_retort_pages["essences"], "Кодекс эссенций")
	_retort_ess = g._label("", 12)
	_retort_ess.add_theme_color_override("font_color", UIStyle.CREAM)
	codex.add_child(_retort_ess)
	_codex_list = HFlowContainer.new()
	_codex_list.add_theme_constant_override("h_separation", 10)
	_codex_list.add_theme_constant_override("v_separation", 4)
	codex.add_child(_codex_list)

	# 6. Сосуды остаются внизу страницы: состояние, таймер, сбор и отмена.
	var slots := _retort_section(_retort_pages["cube"], "Слоты сосудов")
	_retort_cards = VBoxContainer.new()
	_retort_cards.add_theme_constant_override("separation", 8)
	slots.add_child(_retort_cards)
	for i in Game.RETORT_SLOT_MAX:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIStyle.panel())
		_retort_cards.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		var title := g._label("Слот %d" % (i + 1), 14)
		box.add_child(title)
		var state := g._label("", 12)
		state.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		box.add_child(state)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var primary := g._small_button("", Vector2(0, 44), 1)
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.pressed.connect(_on_retort_primary.bind(i))
		row.add_child(primary)
		var cancel := g._small_button("Отмена", Vector2(0, 44))
		cancel.pressed.connect(_on_retort_cancel.bind(i))
		row.add_child(cancel)
		_retort_ui.append({"title": title, "state": state, "primary": primary, "cancel": cancel})
	var hint := g._label("Забрать раньше срока нельзя, отмена возвращает вещество. Реторта и купаж работают офлайн.", 11)
	hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	slots.add_child(hint)

	var blend := _retort_section(_retort_pages["cube"], "Купаж")
	_blend_state = g._label("", 12)
	_blend_state.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	blend.add_child(_blend_state)
	var blend_row := HFlowContainer.new()
	blend_row.add_theme_constant_override("h_separation", 6)
	blend_row.add_theme_constant_override("v_separation", 6)
	blend.add_child(blend_row)
	for element in ELEMENTS:
		var b := g._small_button(_element_title(element), Vector2(104, 40))
		b.pressed.connect(_on_blend_start.bind(element))
		blend_row.add_child(b)
		_blend_buttons[element] = b
	_blend_collect_btn = g._small_button("Забрать купаж", Vector2(0, 40), 1)
	_blend_collect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blend_collect_btn.pressed.connect(_on_blend_collect)
	blend.add_child(_blend_collect_btn)
	_select_retort_tab(_retort_tab, false)
	_refresh_retort_page()

func _select_retort_tab(tab: String, audible := true) -> void:
	if not _retort_pages.has(tab):
		return
	_retort_tab = tab
	for key in _retort_pages:
		var page := _retort_pages[key] as Control
		if is_instance_valid(page):
			page.visible = String(key) == tab
	for key in _retort_tab_buttons:
		var chip := _retort_tab_buttons[key] as Button
		if not is_instance_valid(chip):
			continue
		var selected := String(key) == tab
		chip.set_pressed_no_signal(selected)
		UIStyle.style_button(chip, 1 if selected else 0)
	if audible:
		Sfx.click()


func _retort_section(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = title.replace(" ", "")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIStyle.panel())
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var heading := g._label(title, 15)
	heading.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	box.add_child(heading)
	return box

func _essence_ids() -> Array:
	var ids: Array = []
	for element in ELEMENTS:
		for tier in 5:
			ids.append("%s-%d" % [element, tier])
	for element in ELEMENTS:
		ids.append("blend-" + element)
	return ids

func _element_title(element: String) -> String:
	match element:
		"fire": return "Огонь"
		"water": return "Вода"
		"earth": return "Земля"
		"air": return "Воздух"
	return element

func _axis_title(axis: String) -> String:
	match axis:
		"queue": return "Глубина очереди"
		"offline": return "Оффлайн-окно"
		"slots": return "Ячейки"
		"speed": return "Скорость"
		"complexity": return "Сложность"
		"blend": return "Купаж"
		"cap": return "Эссенциальная ёмкость"
		"equip": return "Эссенциальное оборудование"
	return axis

func _build_axis_card(axis: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var head := HBoxContainer.new()
	var name_lbl := g._label(_axis_title(axis), 13)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	var lvl_lbl := g._label("", 12)
	lvl_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lvl_lbl.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	head.add_child(lvl_lbl)
	box.add_child(head)
	var pips := g._label("", 13)
	pips.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(pips)
	var value := g._label("", 12)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(value)
	var price := HFlowContainer.new()
	price.add_theme_constant_override("h_separation", 8)
	price.add_theme_constant_override("v_separation", 0)
	box.add_child(price)
	var btn := g._small_button("Улучшить", Vector2(0, 36))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_purchase.bind(axis))
	box.add_child(btn)
	_rows[axis] = {"pips": pips, "lvl": lvl_lbl, "value": value, "price": price, "btn": btn}
	return card

func _axis_value(axis: String) -> String:
	match axis:
		"queue": return "%d шагов" % _queue_depth()
		"offline": return "%d ч" % int(_offline_window() / 3600.0)
		"slots": return "%d сосудов" % _retort_slots_open()
		"speed": return "×%.1f ко времени" % float(RetortBalance.SPEED_FACTOR[clampi(_level("speed"), 0, RetortBalance.SPEED_FACTOR.size() - 1)])
		"complexity": return "тир до %d" % _max_distill_tier()
		"blend": return "открыт" if _level("blend") > 0 else "закрыт"
		"cap": return "+%d к капу" % _essence_cap_line_bonus()
		"equip": return "+%d линий мастерской" % _workshop_bonus_lines()
	return ""

func _req_missing(price: Dictionary) -> String:
	var req: Dictionary = price.get("req", {})
	for axis in req:
		if _level(String(axis)) < int(req[axis]):
			return "%s %d+" % [_axis_title(String(axis)).to_lower(), int(req[axis])]
	return ""

func _add_essence_chip(parent: Control, id: String, need: int) -> bool:
	var have := essence_count(id)
	var chip := g._label("%s %d/%d" % [id, have, need], 12)
	chip.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_theme_color_override("font_color", UIStyle.CREAM if have >= need else Color(0.92, 0.42, 0.34))
	parent.add_child(chip)
	return have >= need

func _purchase(axis: String) -> void:
	Sfx.click()
	var result := cube_purchase(axis)
	if not bool(result.get("ok", false)):
		g._online._set_status(String(result.get("error", "")))
	g._saves._save_game()
	_refresh_retort_page()

func _queue_append(sub: String) -> bool:
	if _queue.size() >= _queue_depth():
		g._online._set_status("Программа не помещается в глубину очереди.")
		return false
	if not g.ITEMS.has(sub) or int(g._engine.inventory.get(sub, 0)) < 1 \
			or int(g._engine._rarity_of(sub).get("tier", 0)) > _max_distill_tier():
		g._online._set_status("Это вещество сейчас нельзя перегнать.")
		return false
	var program := _queue.duplicate(true)
	program.append({"sub": sub})
	if not queue_set(program):
		return false
	g._saves._save_game()
	_refresh_retort_page()
	Sfx.click()
	return true


func _on_queue_rail_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var relative := Vector2.ZERO
		var active := _queue_pressing
		if event is InputEventScreenDrag:
			relative = (event as InputEventScreenDrag).relative
		else:
			var motion := event as InputEventMouseMotion
			relative = motion.relative
			active = active and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if active and is_instance_valid(_queue_rail):
			_queue_rail.scroll_horizontal -= int(relative.x)
			_queue_rail.accept_event()
		return
	var at := Vector2.ZERO
	var pressed := false
	var tracked := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tracked = mb.button_index == MOUSE_BUTTON_LEFT
		at = mb.position
		pressed = mb.pressed
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		tracked = true
		at = touch.position
		pressed = touch.pressed
	if not tracked:
		return
	if pressed:
		_queue_pressing = true
		_queue_press_position = at
		return
	if not _queue_pressing:
		return
	_queue_pressing = false
	if at.distance_to(_queue_press_position) > 8.0 or not is_instance_valid(_queue_rail):
		return
	var index := int((at.x + float(_queue_rail.scroll_horizontal)) / 104.0)
	_queue_select(index)


func _queue_select(index: int) -> void:
	if index < 0 or index >= _queue.size():
		return
	_queue_selected = index
	_refresh_queue_editor()
	Sfx.click()


func _queue_remove_selected() -> void:
	_queue_remove(_queue_selected)


func _queue_remove(index: int) -> void:
	if index < 0 or index >= _queue.size():
		return
	var program := _queue.duplicate(true)
	program.remove_at(index)
	queue_set(program)
	_queue_selected = -1
	_queue_replace_index = -1
	g._saves._save_game()
	_refresh_retort_page()
	Sfx.click()


func _queue_replace(index: int, sub: String) -> bool:
	if index < 0 or index >= _queue.size():
		return false
	if not g.ITEMS.has(sub) or int(g._engine.inventory.get(sub, 0)) < 1 \
			or int(g._engine._rarity_of(sub).get("tier", 0)) > _max_distill_tier():
		g._online._set_status("Это вещество сейчас нельзя перегнать.")
		return false
	var program := _queue.duplicate(true)
	program[index] = {"sub": sub}
	if not queue_set(program):
		return false
	_queue_selected = index
	g._saves._save_game()
	_refresh_retort_page()
	Sfx.click()
	return true


func _open_queue_replace() -> void:
	if _queue_selected < 0 or _queue_selected >= _queue.size():
		return
	_queue_replace_index = _queue_selected
	_open_retort_picker(-1, true)


func _open_queue_picker() -> void:
	if _queue.size() >= _queue_depth():
		g._online._set_status("Программа не помещается в глубину очереди.")
		Sfx.error()
		return
	_queue_replace_index = -1
	_open_retort_picker(-1, true)


func _on_queue_toggled(on: bool) -> void:
	queue_toggle(on)
	g._saves._save_game()
	_refresh_retort_page()

func _on_blend_start(element: String) -> void:
	if not blend_start(element):
		g._online._set_status("Купаж недоступен: проверь уровень и редкие эссенции.")
		Sfx.error()
	else:
		Sfx.click()
	g._saves._save_game()
	_refresh_retort_page()

func _on_blend_collect() -> void:
	var result := blend_collect()
	if not bool(result.get("ok", false)):
		return
	Sfx.discovery()
	g._engine._refresh()
	g._saves._save_game()
	_refresh_retort_page()

func _layout_retort_art() -> void:
	if _retort_art_scene == null or _retort_art == null:
		return
	var s := minf(_retort_art_scene.size.x / 512.0, _retort_art_scene.size.y / 512.0)
	_retort_art.scale = Vector2(s, s)
	_retort_art.position = _retort_art_scene.size / 2.0

func _retort_flow_color() -> Color:
	var element := ""
	if not _blend.is_empty():
		element = String(_blend.get("out", "")).trim_prefix("blend-")
	else:
		for i in _retort_slots_open():
			if _retort_busy(i):
				element = String(_retort_slot(i).get("essence", "")).split("-")[0]
				break
	if element.is_empty():
		element = "water"
	return g._item_colors.get(element, Color(0.75, 0.95, 1.0))

func _refresh_retort_art() -> void:
	if _retort_sprite == null or _retort_fluid == null or _retort_drops == null:
		return
	var stem := RetortSprite.texture_stem(_cube_levels)
	_retort_sprite.texture = load(stem + ".png") as Texture2D
	_retort_fluid.texture = load(stem + "_fluid.png") as Texture2D
	_retort_fluid.visible = _retort_fluid.texture != null
	_retort_drops.texture = _retort_fluid.texture
	_retort_drops.visible = RetortSprite.form_stage(_cube_levels) >= 2
	_layout_retort_art()
	var flow_col := _retort_flow_color()
	_retort_fluid_mat.set_shader_parameter("flow_color", flow_col)
	_retort_drops_mat.set_shader_parameter("flow_color", flow_col)
	var flow_speed := 1.0 + float(_level("speed")) * 0.35
	_retort_fluid_mat.set_shader_parameter("flow_speed", flow_speed)
	_retort_drops_mat.set_shader_parameter("flow_speed", flow_speed)

func _refresh_retort_page() -> void:
	_refresh_retort_art()
	if _retort_head == null or _retort_cards == null or _retort_ess == null:
		return
	if _retort_ui.size() < Game.RETORT_SLOT_MAX:
		return
	var n := _essence_codex.size()
	_retort_head.text = "Открыто эссенций: %d/24 · бонус капа: +%d" % [n, _essence_cap_bonus() + _essence_cap_line_bonus()]

	for id in _essence_cells:
		var cell := _essence_cells[id] as Label
		if not is_instance_valid(cell):
			continue
		if essence_known(id):
			cell.text = "%s · ×%d" % [id, essence_count(id)]
			cell.add_theme_color_override("font_color", UIStyle.CREAM if essence_count(id) > 0 else UIStyle.TEXT_DIM)
		else:
			cell.text = "?"
			cell.add_theme_color_override("font_color", UIStyle.TEXT_DIM)

	for raw_axis in _rows:
		var axis := String(raw_axis)
		var row: Dictionary = _rows[axis]
		var table := _axis_table(axis)
		var lvl := clampi(_level(axis), 0, table.size())
		var pips := ""
		for i in table.size():
			pips += "●" if i < lvl else "○"
		(row["pips"] as Label).text = pips
		(row["pips"] as Label).add_theme_color_override("font_color", PIP_ON if lvl > 0 else PIP_OFF)
		(row["lvl"] as Label).text = "%d/%d" % [lvl, table.size()]
		(row["value"] as Label).text = _axis_value(axis)
		var price_box := row["price"] as Container
		for chip in price_box.get_children():
			price_box.remove_child(chip)
			chip.queue_free()
		var btn: Button = row["btn"]
		if lvl >= table.size():
			btn.text = "Максимум"
			btn.disabled = true
			continue
		var price: Dictionary = table[lvl]
		btn.text = "Улучшить"
		var ok := true
		var cost: Dictionary = price.get("essences", {})
		for id in cost:
			ok = _add_essence_chip(price_box, String(id), int(cost[id])) and ok
		var req := _req_missing(price)
		if req != "":
			var chip := g._label("сначала %s" % req, 12)
			chip.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_theme_color_override("font_color", Color(0.92, 0.42, 0.34))
			price_box.add_child(chip)
			ok = false
		btn.disabled = not ok

	_refresh_queue_editor()
	_refresh_blend()

	if is_instance_valid(_codex_list):
		for child in _codex_list.get_children():
			_codex_list.remove_child(child)
			child.queue_free()
		var known := 0
		for id in _essence_ids():
			if not essence_known(id):
				continue
			known += 1
			var entry := g._label(id, 12)
			entry.autowrap_mode = TextServer.AUTOWRAP_OFF
			entry.add_theme_color_override("font_color", UIStyle.CREAM)
			_codex_list.add_child(entry)
		_retort_ess.text = "Открыто %d из 24 · неизвестно %d" % [known, 24 - known]
		if known == 0:
			var empty := g._label("Первая дистилляция откроет запись в кодексе.", 12)
			empty.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
			_codex_list.add_child(empty)

	var open := _retort_slots_open()
	for i in Game.RETORT_SLOT_MAX:
		var u: Dictionary = _retort_ui[i]
		var title: Label = u["title"]
		var state: Label = u["state"]
		var primary: Button = u["primary"]
		var cancel: Button = u["cancel"]
		if i >= open and not _retort_busy(i):
			title.text = "Слот %d — закрыт" % (i + 1)
			state.text = "Откроется за улучшение оси «Ячейки»."
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
			var essence := String(s.get("essence", essence_of(sub)))
			state.text = "«%s» → эссенция %s" % [g._clean_str(s.get("name", sub)), essence]
			primary.text = "Забрать эссенцию"
			primary.disabled = false
			cancel.visible = false
		else:
			state.text = "«%s» булькает… осталось %s." % [g._clean_str(s.get("name", sub)), _retort_left_text(_retort_left(i))]
			primary.text = "Зреет…"
			primary.disabled = true
			cancel.visible = true
	if g._pages._mode_chips.has("retort"):
		(g._pages._mode_chips["retort"] as Button).text = "Реторта ●" if _retort_any_ready() else "Реторта"

func _refresh_queue_editor() -> void:
	if not is_instance_valid(_queue_toggle) or not is_instance_valid(_queue_status) \
			or not is_instance_valid(_queue_flow) or not is_instance_valid(_queue_add_btn) \
			or not is_instance_valid(_queue_edit_actions):
		return
	_queue_toggle.text = "Стоп" if _queue_on else "Пустить"
	_queue_toggle.disabled = _queue.is_empty() and not _queue_on
	_queue_add_btn.disabled = _queue.size() >= _queue_depth()
	var state := "запущена" if _queue_on else "остановлена"
	_queue_status.text = "%d/%d шагов · офлайн %d ч · %s" % [
		_queue.size(), _queue_depth(), int(_offline_window() / 3600.0), state]
	if _queue_selected < 0 or _queue_selected >= _queue.size():
		_queue_selected = -1
	var has_selection := _queue_selected >= 0
	_queue_edit_actions.visible = has_selection
	for child in _queue_flow.get_children():
		_queue_flow.remove_child(child)
		child.queue_free()
	if _queue.is_empty():
		var empty := g._label("Программа пуста — добавь первое вещество.", 12)
		empty.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		_queue_flow.add_child(empty)
		return
	for i in _queue.size():
		var step: Dictionary = _queue[i]
		var sub := String(step.get("sub", ""))
		var full_name := g._online._item_name(sub)
		var element := essence_of(sub).split("-")[0]
		var flow_color: Color = g._item_colors.get(element, Color(0.75, 0.95, 1.0))
		var vessel_step := Button.new()
		vessel_step.name = "RetortQueueStep%d" % (i + 1)
		vessel_step.custom_minimum_size = Vector2(104, 132)
		vessel_step.tooltip_text = full_name
		vessel_step.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vessel_step.pressed.connect(_queue_select.bind(i))
		UIStyle.style_cell(vessel_step, i == _queue_selected, 1.0)
		_queue_flow.add_child(vessel_step)
		var channel := TextureRect.new()
		channel.name = "Channel"
		channel.texture = load("res://assets/retort/queue_channel.svg") as Texture2D
		channel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		channel.stretch_mode = TextureRect.STRETCH_SCALE
		channel.position = Vector2(0, 76)
		channel.size = Vector2(104, 36)
		channel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vessel_step.add_child(channel)
		for layer_name in ["Liquid", "Vessel"]:
			var layer := TextureRect.new()
			layer.name = layer_name
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var suffix := "_liquid" if layer_name == "Liquid" else ""
			layer.texture = load("res://assets/retort/queue_round_flask%s.svg" % suffix) as Texture2D
			layer.modulate = flow_color if layer_name == "Liquid" else Color.WHITE
			layer.position = Vector2(12, 0)
			layer.size = Vector2(80, 80)
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vessel_step.add_child(layer)
		var name_label := g._label(full_name, 11)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.position = Vector2(6, 108)
		name_label.size = Vector2(92, 20)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vessel_step.add_child(name_label)
		var selection := TextureRect.new()
		selection.name = "Selection"
		selection.texture = load("res://assets/retort/queue_selection.svg") as Texture2D
		selection.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		selection.stretch_mode = TextureRect.STRETCH_SCALE
		selection.position = Vector2.ZERO
		selection.size = Vector2(104, 132)
		selection.visible = i == _queue_selected
		selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vessel_step.add_child(selection)

func _refresh_blend() -> void:
	if not is_instance_valid(_blend_state) or not is_instance_valid(_blend_collect_btn):
		return
	for element in _blend_buttons:
		var b := _blend_buttons[element] as Button
		if not is_instance_valid(b):
			continue
		var cost := {}
		for id in RetortBalance.BLEND_RECIPES.get(element, []):
			cost[id] = 1
		b.disabled = _level("blend") < 1 or not _blend.is_empty() or not _essence_can_afford(cost)
		b.tooltip_text = "%s-3 + %s-4 → blend-%s" % [element, element, element]
	if _level("blend") < 1:
		_blend_state.text = "Сосуд купажа закрыт. Улучши ось «Купаж»."
	elif _blend.is_empty():
		_blend_state.text = "Купаж: тир 3 + тир 4 одной стихии → составная эссенция."
	else:
		var out := String(_blend.get("out", ""))
		if blend_ready():
			_blend_state.text = "Купаж готов: %s." % out
		else:
			var left := maxf(0.0, float(_blend.get("started", 0.0)) + float(_blend.get("dur", 0.0)) - _retort_now())
			_blend_state.text = "Купаж %s зреет… осталось %s." % [out, _retort_left_text(left)]
	_blend_collect_btn.visible = not _blend.is_empty()
	_blend_collect_btn.disabled = not blend_ready()

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
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_retort_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_retort_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.modal_panel())
	UIStyle.decorate_frame(card)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(360, 0)
	card.add_child(col)
	var t := g._label("ЧТО ПОЛОЖИТЬ В РЕТОРТУ?", 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var sub := g._label("вещество → эссенция (стихия, тир)", 13)
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
		Juice.close(_retort_dim, _retort_popup)
		Sfx.click())
	col.add_child(close)

func _open_retort_picker(slot: int, for_queue := false) -> void:
	_retort_pick_slot = slot
	_retort_pick_queue = for_queue
	_rebuild_retort_rows()
	Juice.open(_retort_dim, _retort_popup)
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
		UIStyle.style_row(b)
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
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(nm)
		var tier := int(g._engine._rarity_of(id).get("tier", 0))
		var ess := essence_of(id)
		var gated := tier > _max_distill_tier()
		b.disabled = gated
		b.tooltip_text = "%s · %s" % [ess, _retort_hours_text(tier)]
		var tag := g._label(("заперт (сложность)" if gated else ess) + " · ×%d" % int(g._engine.inventory.get(id, 0)), 12)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.add_theme_color_override("font_color", Color(0.92, 0.42, 0.34) if gated else UIStyle.TEXT_DIM)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tag)
		_retort_list.add_child(b)

func _on_retort_pick(sub: String) -> void:
	var slot := _retort_pick_slot
	var for_queue := _retort_pick_queue
	var replace_index := _queue_replace_index
	_retort_pick_slot = -1
	_retort_pick_queue = false
	_queue_replace_index = -1
	Juice.close(_retort_dim, _retort_popup)
	if for_queue:
		if replace_index >= 0:
			if not _queue_replace(replace_index, sub):
				Sfx.error()
		elif not _queue_append(sub):
			Sfx.error()
		return
	if _retort_start(slot, sub):
		g._engine._refresh()
	else:
		g._online._set_status("Не вышло положить в реторту.")
		Sfx.error()
		g._engine._refresh()
