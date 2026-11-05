extends RefCounted
class_name RoomCarousel
# Карусель комнат вкладки «Эксперимент»: одна нарисованная комната (плита) служит
# фоном обеим. На ней живут объекты-меню — колода Аркана на столе, доска
# контрактов на стене, свиток гильдии на полу; комната 2 — Мастерская, там на полу
# стоят устройства. Предметы ставятся долями плиты (см. plate_rect), поэтому
# комната остаётся комнатой при любом размере окна. Листается стрелками и
# свайпом; HUD и нижний бар общие. Запертый объект виден силуэтом и при тапе
# объясняет условие — навигация не прячется за разблокировку.
#
# Из PR #65 сюда не перенесено: «Круг дня» и дейли-сетка — их слой уже
# принадлежит Контрактной доске (Retention удалён).

var g: Game
var _host: Control = null
var _rooms: Array = []
var _plate: TextureRect = null
var _room_idx := 0
var _dots: Array = []
var _left_btn: Button = null
var _right_btn: Button = null
var _props: Dictionary = {}
var _scene_props: Array = []
var _press_x: float = -1.0
var _props_hidden_by_picker := false
var _scene_visible := true

const TOOL_TITLES := {"spring": "Родник", "bench": "Верстак", "retort": "Реторта"}
const TOOL_ICONS := {"spring": "fountain", "bench": "workbench", "retort": "retort"}
const PLATE_ART := "room_plate"
# Разрешение, в пикселях которого заданы plate_px у предметов. Текстура плиты
# может быть больше (апскейл) — размеры предметов от этого не должны меняться.
const PLATE_REF_PX := Vector2(1080.0, 1609.0)
# Устройства Мастерской стоят на полу комнаты; координаты — доли нарисованной
# плиты, чтобы они не «висели» в углах окна при любом размере экрана.
const TOOL_PLATE_UV := {
	"spring": Vector2(0.20, 0.72),
	"bench": Vector2(0.45, 0.73),
	"retort": Vector2(0.70, 0.72),
}
const TOOL_PLATE_PX := Vector2(230.0, 230.0)


func build(game: Game, page: VBoxContainer) -> void:
	g = game
	# Плита комнаты — фон ВСЕГО стартового экрана, а не картинка в рамке вкладки:
	# она живёт на корне сразу над общим фоном, поэтому шапка и нижний бар лежат
	# на нарисованной комнате. Слой 1 — над UIBackdrop, под остальным интерфейсом.
	_plate = TextureRect.new()
	_plate.name = "RoomPlate"
	_plate.texture = load(SceneProps.ROOM_DIR + PLATE_ART + ".png") as Texture2D
	_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.add_child(_plate)
	g.move_child(_plate, 1)

	# Слой сцены: предметы-меню, стрелки и точки поверх страницы вкладки, но под
	# нижним баром и модалками. Отдельный Control на корне нужен потому, что
	# страница обрезает детей по своим границам, а предметы стоят на всей плите.
	_host = Control.new()
	_host.name = "Rooms"
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.add_child(_host)

	# Комнаты (поле эксперимента и текст Мастерской) остаются в странице: это
	# поток вкладки, а не сцена поверх всего экрана.
	var page_host := Control.new()
	page_host.name = "RoomPages"
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(page_host)
	page_host.gui_input.connect(_on_gui_input)

	var r1 := VBoxContainer.new()
	r1.name = "RoomLab"
	r1.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r1.add_theme_constant_override("separation", 8)
	r1.gui_input.connect(_on_gui_input)
	page_host.add_child(r1)
	_rooms.append(r1)
	g._pages._build_experiment_location(r1)
	if g._pages._experiment_field != null:
		# Свайп по полу комнаты: плита сцены теперь не принимает ввод (она фон),
		# событие доходит до поля эксперимента.
		g._pages._experiment_field.gui_input.connect(_on_gui_input)
	# эксперимент рассчитывает, что скролл вкладки выключен; обёртка ломает его
	# поиск родителя — выключаем явно через цепочку страницы
	var margin := page.get_parent() as Control
	if margin != null:
		var scroll := margin.get_parent() as ScrollContainer
		if scroll != null:
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if page.get_parent() is MarginContainer:
		# Стартовый экран — комната целиком: поля вкладки не сужают сцену.
		var page_margin := page.get_parent() as MarginContainer
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			page_margin.add_theme_constant_override(side, 0)

	var r2 := VBoxContainer.new()
	r2.name = "RoomWorkshop"
	r2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r2.add_theme_constant_override("separation", 10)
	r2.visible = false
	r2.gui_input.connect(_on_gui_input)
	page_host.add_child(r2)
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
	# Слой сцены — всё окно, поэтому точки поднимаем над нижним баром.
	dots.offset_top = -BottomNav.NAV_H - 32
	dots.offset_bottom = -BottomNav.NAV_H - 24
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
	_host.resized.connect(_layout_scene)
	call_deferred("_layout_scene")


## Объекты-меню комнаты 1 — вырезки поверх нарисованной плиты: колода на столе,
## лист контракта на доске, свиток гильдии на полу. Предмет обязан быть именно
## вырезкой, а не невидимой тап-зоной: только по её альфе обводка ложится на
## контур, а не на прямоугольник зоны (претензия владельца: «ореолы квадратные»).
## Позиции и размеры — доли и пиксели плиты (PLATE_REF_PX).
func _build_scene_props() -> void:
	var deck := SceneProps.make_art_prop("prop_deck", Vector2(220.0, 165.0))
	deck.name = "Prop_Deck"
	deck.pressed.connect(func() -> void: g._sigil_ui._open_sigil_modal())
	_add_scene_prop(deck, Vector2(0.347, 0.390), Vector2(220.0, 165.0))

	# Доска: кликаем по листу, а не по раме — на листе и стоит бейдж-розетка.
	var board := SceneProps.make_art_prop("prop_contract", Vector2(220.0, 318.0))
	board.name = "Prop_Board"
	board.pressed.connect(func() -> void: g._open_contract_board())
	_add_scene_prop(board, Vector2(0.665, 0.285), Vector2(220.0, 318.0))
	_overlay(board, "prop_seal_gold", Rect2(0.0, 0.03, 0.44, 0.45))

	# Свиток гильдии — на полу у левой стены: под котлом он лежал прямо на нём.
	var guild := SceneProps.make_art_prop("prop_scroll", Vector2(258.0, 130.0))
	guild.name = "Prop_Scroll"
	guild.pressed.connect(func() -> void: g._progress_ui._open_progress_popup())
	_add_scene_prop(guild, Vector2(0.16, 0.87), Vector2(258.0, 130.0))

	# Устройства Мастерской — те же объекты сцены, но на полу второй комнаты.
	for key in ["spring", "bench", "retort"]:
		var prop := SceneProps.make_prop(TOOL_ICONS[key], 190)
		prop.name = "PropTool_" + String(key)
		prop.pressed.connect(_open_tool.bind(key))
		prop.set_meta("plate_uv", TOOL_PLATE_UV[key])
		prop.set_meta("plate_px", TOOL_PLATE_PX)
		_host.add_child(prop)
		_props[key] = prop


func _add_scene_prop(control: Control, uv: Vector2, px: Vector2) -> void:
	control.set_meta("plate_uv", uv)
	control.set_meta("plate_px", px)
	_host.add_child(control)
	_scene_props.append(control)


## Украшение поверх предмета (печать на листе): доли rect'а вместо пикселей,
## чтобы наклейка масштабировалась вместе с предметом. Ввод не принимает —
## клик всё равно принадлежит предмету.
func _overlay(btn: Control, art: String, frac: Rect2) -> void:
	var r := TextureRect.new()
	r.name = "Overlay_" + art
	r.texture = load(SceneProps.ROOM_DIR + art + ".png") as Texture2D
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = frac.position.x
	r.anchor_top = frac.position.y
	r.anchor_right = frac.end.x
	r.anchor_bottom = frac.end.y
	btn.add_child(r)


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
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var title := g._label("МАСТЕРСКАЯ", 20)
	title.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	title.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.03, 0.92))
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	var sub := g._label("Автоматика лаборатории: устройства созревают без тебя. Новые открываются вместе с веществами.", 13)
	sub.add_theme_color_override("font_color", UIStyle.CREAM)
	sub.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.03, 0.92))
	sub.add_theme_constant_override("outline_size", 5)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)


## Прямоугольник на плите в координатах экрана: доля uv → координаты при
## cover-масштабе плиты по всему окну. Плита — фон стартового экрана, поэтому
## и предметы считаются от окна, а не от площади вкладки.
func plate_rect(uv: Vector2, px: Vector2) -> Rect2:
	if _plate == null or _plate.texture == null:
		return Rect2()
	var tex := _plate.texture.get_size()
	var plate_rect_global := _plate.get_global_rect()
	if tex.x <= 0.0 or tex.y <= 0.0:
		return Rect2()
	if plate_rect_global.size.x <= 0.0 or plate_rect_global.size.y <= 0.0:
		return Rect2()
	var k := maxf(plate_rect_global.size.x / tex.x, plate_rect_global.size.y / tex.y)
	var shown := tex * k
	var origin := plate_rect_global.position + (plate_rect_global.size - shown) * 0.5
	var center := origin + uv * shown
	var disp := px * (shown.x / PLATE_REF_PX.x)
	return Rect2(center - disp * 0.5, disp)


func _place(control: Control, rect: Rect2) -> void:
	# plate_rect отдаёт экранные координаты, слой сцены — тоже полноэкранный;
	# переводим в локальные на случай вложенного хоста.
	var pos := rect.position - _host.global_position
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.custom_minimum_size = rect.size
	control.offset_left = pos.x
	control.offset_top = pos.y
	control.offset_right = pos.x + rect.size.x
	control.offset_bottom = pos.y + rect.size.y
	# Толщина кольца задана в экранных px: пересчитываем под масштаб плиты.
	var glow := control.get_meta("glow", null) as TextureRect
	if glow != null and glow.texture != null and glow.material is ShaderMaterial:
		(glow.material as ShaderMaterial).set_shader_parameter("thickness",
			SceneProps.OUTLINE_SCREEN_PX * float(glow.texture.get_width()) / maxf(rect.size.x, 1.0))


func _layout_scene() -> void:
	if _host == null:
		return
	for node in _scene_props:
		var ctrl := node as Control
		if ctrl == null:
			continue
		var px: Vector2 = ctrl.get_meta("plate_px", Vector2.ZERO)
		if px.x <= 0.0:
			continue
		var uv: Vector2 = ctrl.get_meta("plate_uv", Vector2(0.5, 0.5))
		_place(ctrl, plate_rect(uv, px))
	for key in _props:
		var tool: Control = _props[key]
		var tool_uv: Vector2 = TOOL_PLATE_UV.get(key, Vector2(0.5, 0.75))
		_place(tool, plate_rect(tool_uv, TOOL_PLATE_PX))
	if g != null and g._pages != null and g._pages._experiment_field != null:
		g._pages._fit_experiment_overlay()


## Под окном выбора реагентов предметы комнаты прячутся: они соседи страницы и
## иначе перекрыли бы список.
func set_props_visible(v: bool) -> void:
	_props_hidden_by_picker = not v
	_apply_prop_visibility()


## Сцена (плита + предметы) — только на стартовой вкладке; остальные разделы
## живут на общем фоне.
func set_scene_visible(v: bool) -> void:
	if _scene_visible == v:
		return
	_scene_visible = v
	if _plate != null:
		_plate.visible = v
	if _host != null:
		_host.visible = v


func _apply_prop_visibility() -> void:
	var lab := _room_idx == 0
	var scene_visible := lab and not _props_hidden_by_picker
	for p in _scene_props:
		(p as Control).visible = scene_visible
	for key in _props:
		(_props[key] as Control).visible = not lab


func _open_tool(key: String) -> void:
	if not g._engine._mode_unlocked(key):
		# Строка статуса на стартовом экране не видна: без тоста тап по запертому
		# устройству выглядел как неработающая кнопка.
		var hint: String = g._pages._mode_hint(key)
		g._online._set_status(hint)
		g._online._toast("%s: %s" % [TOOL_TITLES.get(key, key), hint])
		Sfx.error()
		return
	if key == "spring":
		# Родник — полноэкранный иммерсивный экран, его лист не заменяет.
		g._pages._open_spring_screen()
		return
	g._pages._open_device_screen(key, TOOL_TITLES.get(key, key))


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
	_apply_prop_visibility()
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
