extends Control
class_name SpringScreen
# Иммерсивный экран Родника: фонтан растёт с уровнями (форма — сумма осей,
# материал — лучший оплаченный tier), вода течёт шейдером, на каждом тике
# короткий всплеск. Оси покупаются через Engine.spring_purchase.

# Все формы нарисованы на холсте 256×256, самая широкая занимает 224 px.
const CANVAS := 256.0
const ART_W := 224.0
const TIER_ASSET := ["steel", "steel", "obsidian", "crystal", "gold"]
const AXES := ["speed", "volume", "sources", "offline"]
const PIP_ON := Color(0.96, 0.78, 0.42)
const PIP_OFF := Color(0.42, 0.34, 0.26)

var _game: Game
var _scene: Control
var _center_w := ART_W
var _res_label: Label
var _res_sig := ""
var _fountain: Node2D
var _sprite: Sprite2D
var _water: Sprite2D
var _water_mat: ShaderMaterial
var _spray: GPUParticles2D
var _flow: ParticleProcessMaterial
var _orbs: Dictionary = {}
var _rows: Dictionary = {}
var _toggle_btn: Button
var _clock_prev := 0.0


func _build(game: Game) -> void:
	_game = game
	name = "SpringScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = ScreenRouter.SCREEN_Z

	var plate := TextureRect.new()
	plate.texture = load(SceneProps.ROOM_DIR + ScreenRouter.PLATE_ART + ".png") as Texture2D
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.modulate = Color(0.55, 0.5, 0.46)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(plate)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.modal_panel(UIStyle.BRASS_HI))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Тело между шапкой игры и нижней навигацией — как у экранов ScreenRouter,
	# иначе кнопка пуска уходит под бар.
	panel.offset_left = ScreenRouter.SIDE_M
	panel.offset_top = ScreenRouter.HEADER_H
	panel.offset_right = -ScreenRouter.SIDE_M
	panel.offset_bottom = -(BottomNav.NAV_H + ScreenRouter.NAV_GAP)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var back := _game._small_button("← назад", Vector2(104, 40))
	back.pressed.connect(_close)
	head.add_child(back)
	var title := _game._label("РОДНИК", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _game._font_semi != null:
		title.add_theme_font_override("font", _game._font_semi)
	head.add_child(title)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(104, 0)
	head.add_child(pad)

	# Запасы, которыми платят оси: видны, не уходя с экрана.
	_res_label = _game._label("", 12)
	_res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_res_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	col.add_child(_res_label)

	# Фонтан — главный герой экрана: забирает всю свободную высоту. Все его слои
	# в одной трансформации: вода и брызги не могут уехать от спрайта.
	_scene = Control.new()
	_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene.custom_minimum_size = Vector2(0, 160)
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.resized.connect(_layout_fountain)
	col.add_child(_scene)
	_fountain = Node2D.new()
	_scene.add_child(_fountain)
	_sprite = Sprite2D.new()
	_fountain.add_child(_sprite)
	_water = Sprite2D.new()
	_water.z_index = 1
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://assets/spring/spring_water.gdshader")
	_water.material = _water_mat
	_fountain.add_child(_water)
	_spray = GPUParticles2D.new()
	_spray.amount = 10
	_spray.lifetime = 0.6
	_spray.one_shot = true
	_spray.emitting = false
	_spray.z_index = 2
	_fountain.add_child(_spray)
	_flow = ParticleProcessMaterial.new()
	_flow.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	_flow.gravity = Vector3(0, -55, 0)
	_flow.initial_velocity_min = 26.0
	_flow.initial_velocity_max = 46.0
	_flow.scale_min = 0.25
	_flow.scale_max = 0.6
	_flow.direction = Vector3(0, -1, 0)
	_flow.spread = 42.0
	_spray.process_material = _flow

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for axis in AXES:
		grid.add_child(_build_axis_card(String(axis)))

	# Источники: выбор конкретных стихий — за игроком, число — купленная ступень.
	var orb_row := HBoxContainer.new()
	orb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	orb_row.add_theme_constant_override("separation", 10)
	col.add_child(orb_row)
	for item_id in Game.BASE_IDS:
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 2)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		var orb := _game._make_orb(item_id, 52)
		orb.tapped.connect(_on_source_tapped.bind(item_id))
		stack.add_child(orb)
		var mark := _game._label("", 12)
		mark.custom_minimum_size = Vector2(64, 16)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF
		stack.add_child(mark)
		orb_row.add_child(stack)
		_orbs[item_id] = {"orb": orb, "mark": mark}

	_toggle_btn = _game._round_brew_button("Пустить родник")
	_toggle_btn.custom_minimum_size = Vector2(184, 46)
	_toggle_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toggle_btn.pressed.connect(_on_toggle)
	col.add_child(_toggle_btn)
	_refresh()


func _layout_fountain() -> void:
	if _fountain == null or _scene == null:
		return
	_center_w = maxf(80.0, _scene.size.x)
	var s := minf(_center_w / ART_W, maxf(0.2, _scene.size.y) / CANVAS)
	_fountain.scale = Vector2(s, s)
	_fountain.position = _scene.size / 2.0
	_spray.position = Vector2(0.0, CANVAS * 0.22)


func _process(_delta: float) -> void:
	if _game == null:
		return
	# Игра идёт и под экраном: запасы меняются — цены и кнопки пересчитываются.
	if _stock_sig() != _res_sig:
		_refresh()
	var clock: float = _game._pages._spring_clock
	if clock < _clock_prev and _game._engine.spring_on:
		_spray.restart()
	_clock_prev = clock


# Карточка оси: название и «ур./всего», пипсы ступеней, текущее значение,
# цена следующей ступени и кнопка покупки.
func _build_axis_card(axis: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var head := HBoxContainer.new()
	var name_lbl := _game._label(_axis_title(axis), 14)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(name_lbl)
	var lvl_lbl := _game._label("", 12)
	lvl_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lvl_lbl.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	head.add_child(lvl_lbl)
	box.add_child(head)
	var pips := _game._label("", 13)
	pips.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(pips)
	var value := _game._label("", 14)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(value)
	var price := HFlowContainer.new()
	price.add_theme_constant_override("h_separation", 8)
	price.add_theme_constant_override("v_separation", 0)
	box.add_child(price)
	var btn := _game._small_button("Улучшить", Vector2(0, 36))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_purchase.bind(axis))
	box.add_child(btn)
	_rows[axis] = {"pips": pips, "lvl": lvl_lbl, "value": value, "price": price, "btn": btn}
	return card


func _axis_title(axis: String) -> String:
	match axis:
		"speed": return "Скорость"
		"volume": return "Объём"
		"sources": return "Источники"
		"offline": return "Офлайн"
	return axis


func _table(axis: String) -> Array:
	match axis:
		"speed": return SpringBalance.SPEED
		"volume": return SpringBalance.VOLUME
		"sources": return SpringBalance.SOURCES
		"offline": return SpringBalance.OFFLINE
	return []


func _count_axis_rows(axis: String) -> int:
	return _table(axis).size()


func _level(axis: String) -> int:
	return int(_game._engine.spring_levels.get(axis, 0))


func _axis_value(axis: String) -> String:
	var e = _game._engine
	match axis:
		"speed": return "%.2f с" % e.spring_interval()
		"volume": return "до %d" % e._spring_volume_cap()
		"sources": return "%d за тик" % (1 + _level("sources"))
		"offline": return _window_text(float(SpringBalance.OFFLINE_WINDOW_SEC[clampi(_level("offline"),
				0, SpringBalance.OFFLINE_WINDOW_SEC.size() - 1)]))
	return ""


func _window_text(seconds: float) -> String:
	if seconds < 3600.0:
		return "%d мин" % int(seconds / 60.0)
	return "%d ч" % int(seconds / 3600.0)


func _req_missing(price: Dictionary) -> String:
	var req: Dictionary = price.get("req", {})
	for axis in req:
		if _level(String(axis)) < int(req[axis]):
			return "%s %d+" % [_axis_title(String(axis)).to_lower(), int(req[axis])]
	return ""


func _refresh() -> void:
	if _game == null:
		return
	var e = _game._engine
	var stage := SpringSprite.form_stage(e.spring_levels)
	var tier := clampi(SpringSprite.material_tier(e.spring_levels), 0, TIER_ASSET.size() - 1)
	var stem := "res://assets/spring/spring_l%d_%s" % [stage + 1, TIER_ASSET[tier]]
	_sprite.texture = load(stem + ".png") as Texture2D
	# Водный слой — те же пиксели, что вода на рисунке: течение не уедет от струи.
	_water.texture = load(stem + "_water.png") as Texture2D
	_water.visible = _water.texture != null
	_layout_fountain()
	var flow_col: Color = _game._item_colors.get(e.spring_source, Color(0.75, 0.95, 1.0))
	_water_mat.set_shader_parameter("flow_color", flow_col)
	_flow.color = flow_col
	var speed := 0.0
	if e.spring_on:
		speed = clampf(6.0 / maxf(0.2, e.spring_interval()), 0.6, 3.2)
	_water_mat.set_shader_parameter("flow_speed", speed)

	var cap := 1 + _level("sources")
	for raw in Game.BASE_IDS:
		var id := String(raw)
		var entry: Dictionary = _orbs[id]
		var picked: bool = e.spring_sources.has(id)
		var room: bool = e.spring_sources.size() < cap
		var mark: Label = entry["mark"]
		mark.text = "источник" if picked else ("выбрать" if room else "сменить")
		mark.add_theme_color_override("font_color", PIP_ON if picked else UIStyle.TEXT_DIM)
		(entry["orb"] as ElementOrb).modulate = Color.WHITE if picked else Color(0.7, 0.68, 0.66)

	for axis in _rows:
		var row: Dictionary = _rows[axis]
		var table := _table(String(axis))
		var lvl := clampi(_level(String(axis)), 0, table.size())
		var pips := ""
		for i in table.size():
			pips += "●" if i < lvl else "○"
		(row["pips"] as Label).text = pips
		(row["pips"] as Label).add_theme_color_override("font_color", PIP_ON if lvl > 0 else PIP_OFF)
		(row["lvl"] as Label).text = "%d/%d" % [lvl, table.size()]
		(row["value"] as Label).text = _axis_value(String(axis))
		var price_box := row["price"] as Container
		for chip in price_box.get_children():
			chip.queue_free()
		var btn: Button = row["btn"]
		if lvl >= table.size():
			btn.text = "Максимум"
			btn.disabled = true
			continue
		var price: Dictionary = table[lvl]
		btn.text = "Улучшить"
		var ok := true
		var ether_need := int(price.get("ether", 0))
		ok = _add_chip(price_box, "эфир %d" % ether_need, e.ether >= ether_need) and ok
		var mats: Dictionary = price.get("materials", {})
		for mat in mats:
			ok = _add_chip(price_box, "%s %d" % [_game._online._item_name(String(mat)), int(mats[mat])],
					int(e.inventory.get(mat, 0)) >= int(mats[mat])) and ok
		var req := _req_missing(price)
		if req != "":
			ok = _add_chip(price_box, "сначала %s" % req, false) and ok
		btn.disabled = not ok

	_toggle_btn.text = "Остановить родник" if e.spring_on else "Пустить родник"
	_toggle_btn.disabled = not e._mode_unlocked("spring")
	_res_label.text = _res_text()
	_res_sig = _stock_sig()


func _res_text() -> String:
	var e = _game._engine
	var parts: Array = ["эфир %d" % e.ether]
	for raw in SpringBalance.MATERIAL_TIER:
		parts.append("%s %d" % [_game._online._item_name(String(raw)), int(e.inventory.get(raw, 0))])
	return " · ".join(parts)


func _stock_sig() -> String:
	var e = _game._engine
	var s := str(e.ether) + str(e.spring_levels) + str(e.spring_sources) + str(e.spring_on)
	for raw in SpringBalance.MATERIAL_TIER:
		s += "," + str(int(e.inventory.get(raw, 0)))
	return s


func _add_chip(parent: Control, text: String, enough: bool) -> bool:
	var chip := _game._label(text, 12)
	chip.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_theme_color_override("font_color", UIStyle.CREAM if enough else Color(0.92, 0.42, 0.34))
	parent.add_child(chip)
	return enough


func _purchase(axis: String) -> void:
	Sfx.click()
	var result: Dictionary = _game._engine.spring_purchase(axis)
	if not bool(result.get("ok", false)):
		_game._engine.status_text = String(result.get("error", ""))
	_game._saves._save_game()
	_refresh()


func _on_source_tapped(_orb: ElementOrb, item_id: String) -> void:
	Sfx.click()
	var e = _game._engine
	var sources: Array = e.spring_sources
	var i := sources.find(item_id)
	if i >= 0:
		if sources.size() <= 1:
			return  # последний источник не снимаем — родник должен капать
		sources.remove_at(i)
	else:
		# На полной мощности новая стихия вытесняет самую старую, а не получает отказ.
		if sources.size() >= 1 + _level("sources"):
			sources.pop_front()
		sources.append(item_id)
	e.spring_source = String(sources[0])
	_game._saves._save_game()
	_refresh()


func _on_toggle() -> void:
	_game._engine.spring_on = not _game._engine.spring_on
	_game._pages._spring_clock = 0.0
	Sfx.click()
	_game._saves._save_game()
	_refresh()


func _close() -> void:
	# queue_free() не освобождает узел в этом кадре, а main._spring_screen держит
	# ссылку на него: снимок свойств игры наткнулся бы на «previously freed».
	if _game != null:
		_game.set("_spring_screen", null)
	queue_free()
