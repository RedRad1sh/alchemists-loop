extends RefCounted
class_name RoomCarousel
# Карусель комнат вкладки «Эксперимент» (перенос из PR #65): комната 1 — стол
# эксперимента, в его углах живут объекты-меню (колода Аркана, доска контрактов,
# свиток гильдии); комната 2 — Мастерская с устройствами. Листается стрелками и
# свайпом; HUD и нижний бар общие. Запертый объект виден силуэтом и при тапе
# объясняет условие — навигация не прячется за разблокировку.
#
# Из PR #65 сюда не перенесено: «Круг дня» и дейли-сетка — их слой уже
# принадлежит Контрактной доске (Retention удалён).

var g: Game
var _host: Control = null
var _rooms: Array = []
var _room_idx := 0
var _dots: Array = []
var _left_btn: Button = null
var _right_btn: Button = null
var _props: Dictionary = {}
var _scene_props: Array = []
var _press_x: float = -1.0

const TOOL_TITLES := {"spring": "Родник", "bench": "Верстак", "retort": "Реторта"}
const TOOL_ICONS := {"spring": "fountain", "bench": "workbench", "retort": "retort"}


func build(game: Game, page: VBoxContainer) -> void:
	g = game
	_host = Control.new()
	_host.name = "Rooms"
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.clip_contents = true
	_host.gui_input.connect(_on_gui_input)
	page.add_child(_host)

	var r1 := VBoxContainer.new()
	r1.name = "RoomLab"
	r1.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r1.add_theme_constant_override("separation", 8)
	_host.add_child(r1)
	_rooms.append(r1)
	g._pages._build_experiment_location(r1)
	# эксперимент рассчитывает, что скролл вкладки выключен; обёртка ломает его
	# поиск родителя — выключаем явно через цепочку страницы
	var margin := page.get_parent() as Control
	if margin != null:
		var scroll := margin.get_parent() as ScrollContainer
		if scroll != null:
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var r2 := VBoxContainer.new()
	r2.name = "RoomWorkshop"
	r2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r2.add_theme_constant_override("separation", 10)
	r2.visible = false
	_host.add_child(r2)
	_rooms.append(r2)
	_build_workshop(r2)

	_left_btn = _make_arrow(false)
	_left_btn.pressed.connect(func() -> void: set_room(_room_idx - 1))
	_host.add_child(_left_btn)
	_right_btn = _make_arrow(true)
	_right_btn.pressed.connect(func() -> void: set_room(_room_idx + 1))
	_host.add_child(_right_btn)

	var dots := HBoxContainer.new()
	dots.name = "Dots"
	dots.add_theme_constant_override("separation", 6)
	dots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dots.offset_top = -18
	dots.offset_bottom = -10
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(dots)
	for i in _rooms.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(8, 8)
		d.size = Vector2(8, 8)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(d)
		_dots.append(d)

	_build_scene_props()
	_refresh_chrome()
	refresh_unlocks()


## Объекты-меню комнаты 1: та же навигация, что у кнопок шапки, но внутри сцены.
func _build_scene_props() -> void:
	var deck := SceneProps.make_prop("deck", 64, "Аркан")
	deck.name = "Prop_Deck"
	deck.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	deck.offset_left = 8
	deck.offset_right = 72
	deck.offset_top = -238
	deck.offset_bottom = -174
	deck.pressed.connect(func() -> void: g._sigil_ui._open_sigil_modal())
	_host.add_child(deck)
	_scene_props.append(deck)

	var board := SceneProps.make_prop("board", 64, "Доска")
	board.name = "Prop_Board"
	board.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	board.offset_left = -72
	board.offset_right = -8
	board.offset_top = -238
	board.offset_bottom = -174
	board.pressed.connect(func() -> void: g._open_contract_board())
	_host.add_child(board)
	_scene_props.append(board)

	var scroll := SceneProps.make_prop("scroll", 56, "Гильдия")
	scroll.name = "Prop_Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	scroll.offset_left = -64
	scroll.offset_top = 40
	scroll.offset_right = -8
	scroll.offset_bottom = 96
	scroll.pressed.connect(func() -> void: g._progress_ui._open_progress_popup())
	_host.add_child(scroll)
	_scene_props.append(scroll)


func _make_arrow(right: bool) -> Button:
	var btn := Button.new()
	btn.name = "ArrowRight" if right else "ArrowLeft"
	btn.custom_minimum_size = Vector2(44, 64)
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT if right else Control.PRESET_CENTER_LEFT)
	if right:
		btn.offset_left = -48
		btn.offset_right = -4
	else:
		btn.offset_left = 4
		btn.offset_right = 48
	btn.offset_top = -32
	btn.offset_bottom = 32
	var tex := UIIcon.texture("chevron_right")
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.flip_h = not right
		r.modulate = UIStyle.BRASS_HI
		r.custom_minimum_size = Vector2(28, 28)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(r)
	else:
		btn.text = ">" if right else "<"
		btn.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	return btn


func _build_workshop(box: VBoxContainer) -> void:
	var title := g._label("МАСТЕРСКАЯ", 20)
	title.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	box.add_child(title)
	var sub := g._label("Автоматика лаборатории: устройства созревают без тебя. Новые открываются вместе с веществами.", 13)
	sub.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	for key in ["spring", "bench", "retort"]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		row.add_child(cell)
		var prop := SceneProps.make_prop(TOOL_ICONS[key], 96, TOOL_TITLES[key])
		prop.pressed.connect(_open_tool.bind(key))
		cell.add_child(prop)
		_props[key] = prop


func _open_tool(key: String) -> void:
	if not g._engine._mode_unlocked(key):
		g._online._set_status(g._pages._mode_hint(key))
		Sfx.error()
		return
	if key == "spring":
		# Родник — полноэкранный иммерсивный экран, его лист не заменяет.
		g._pages._open_spring_screen()
		return
	g._sheet.open(key, TOOL_TITLES.get(key, key))


func refresh_unlocks() -> void:
	for key in _props:
		var btn: Button = _props[key]
		var locked := not g._engine._mode_unlocked(key)
		SceneProps.set_locked(btn, locked)
		btn.tooltip_text = g._pages._mode_hint(key) if locked else TOOL_TITLES[key]


func set_room(i: int) -> void:
	i = clampi(i, 0, _rooms.size() - 1)
	if i == _room_idx:
		return
	var old: Control = _rooms[_room_idx]
	var nxt: Control = _rooms[i]
	_room_idx = i
	# Видимость переключаем сразу (детерминизм тестов и мгновенный отклик),
	# tween — только мягкое появление новой комнаты.
	old.visible = false
	nxt.modulate.a = 0.0
	nxt.visible = true
	var tw := g.create_tween()
	tw.tween_property(nxt, "modulate:a", 1.0, 0.14)
	Sfx.click()
	_refresh_chrome()


func room_index() -> int:
	return _room_idx


func _refresh_chrome() -> void:
	if _left_btn != null:
		_left_btn.visible = _room_idx > 0
	if _right_btn != null:
		_right_btn.visible = _room_idx < _rooms.size() - 1
	for p in _scene_props:
		(p as Control).visible = _room_idx == 0
	for i in _dots.size():
		(_dots[i] as ColorRect).color = UIStyle.BRASS_HI if i == _room_idx else UIStyle.TEXT_MUTED


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_x = mb.position.x
			else:
				_end_swipe(mb.position.x)
	elif event is InputEventScreenTouch:
		# Сенсор: на телефоне свайп приходил только как InputEventScreenTouch —
		# с мышью карусель листалась, на устройстве нет.
		var st := event as InputEventScreenTouch
		if st.pressed:
			_press_x = st.position.x
		else:
			_end_swipe(st.position.x)


func _end_swipe(release_x: float) -> void:
	if _press_x < 0.0:
		# релиз без предыдущего нажатия (эмуляция мыши из тач-события) — не листаем
		return
	var dx := release_x - _press_x
	_press_x = -1.0
	if dx < -60.0:
		set_room(_room_idx + 1)
	elif dx > 60.0:
		set_room(_room_idx - 1)
