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
var _ws_plate: TextureRect = null
var _jamb: Control = null
# Положение камеры между комнатами: 0 — лаборатория, 1 — Мастерская.
var _pan := 0.0
var _turn_tween: Tween = null
var _room_idx := 0
var _dots: Array = []
var _left_btn: Button = null
var _right_btn: Button = null
var _props: Dictionary = {}
var _scene_props: Array = []
var _press_x: float = -1.0
var _props_hidden_by_picker := false
var _scene_visible := true

const TOOL_TITLES := {"spring": "Родник", "bench": "Верстак", "retort": "Реторта", "letters": "Письма"}
const PLATE_ART := "room_plate"
# Разрешение, в пикселях которого заданы plate_px у предметов. Текстура плиты
# может быть больше (апскейл) — размеры предметов от этого не должны меняться.
const PLATE_REF_PX := Vector2(1080.0, 1609.0)
# Мастерская нарисована отдельной комнатой: свой фон, свои опорные пиксели.
const WS_PLATE_ART := "workshop_plate"
const WS_PLATE_REF_PX := Vector2(704.0, 1520.0)
const WS_FOCUS_UV_Y := 0.68
const WS_FOCUS_SCREEN_Y := 0.55
const TOOL_ART := {"spring": "prop_spring", "bench": "prop_bench", "retort": "prop_retort"}
const TOOL_ORDER := ["retort", "spring", "bench"]
const TOOL_PLATE_UV := {
	"spring": Vector2(0.26, 0.720),
	"retort": Vector2(0.50, 0.587),
	"bench": Vector2(0.82, 0.760),
}
# Вырезки не квадратные: размер повторяет пропорции нового арта (родник 1440x2588,
# реторта 659x2243, верстак 744x858). Расстановка — по layout_preview владельца:
# родник у левой стены, высокая реторта по центру на полу, верстак справа с зазором
# от реторты (левый край верстака правее стойки реторты, как в превью).
const TOOL_PLATE_PX := {
	"spring": Vector2(370.0, 665.0),
	"retort": Vector2(266.0, 906.0),
	"bench": Vector2(400.0, 461.0),
}
# Доля высоты вырезки, где предмет касается опоры: там ложится контактная тень,
# без неё вырезка на живописном полу выглядит наклейкой.
const TOOL_BASE_V := {"bench": 0.98, "retort": 0.99, "spring": 0.99}
# Фоны комнат не продолжают друг друга, поэтому переход — поворот камеры:
# обе плиты едут вместе, а стык закрывает резной косяк из фона Мастерской.
const TURN_SEC := 0.32
const JAMB_ART := "workshop_jamb"
const JAMB_W := 37.0
const JAMB_SHADOW_W := 28.0


func build(game: Game, page: VBoxContainer) -> void:
	g = game
	# Плита комнаты — фон ВСЕГО стартового экрана, а не картинка в рамке вкладки:
	# она живёт на корне сразу над общим фоном, поэтому шапка и нижний бар лежат
	# на нарисованной комнате. Слой 1 — над UIBackdrop, под остальным интерфейсом.
	_plate = _make_plate("RoomPlate", PLATE_ART)
	g.add_child(_plate)
	g.move_child(_plate, 1)
	_ws_plate = _make_plate("RoomPlateWorkshop", WS_PLATE_ART)
	# Фон Мастерской вытянутее экрана: центральная обрезка увела бы пол с
	# устройствами под нижний бар. Раскладка с фокусом — в _layout_ws_plate.
	_ws_plate.stretch_mode = TextureRect.STRETCH_SCALE
	_ws_plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ws_plate.visible = false
	g.add_child(_ws_plate)
	g.move_child(_ws_plate, 2)

	# Слой сцены: предметы-меню, стрелки и точки поверх страницы вкладки, но под
	# нижним баром и модалками. Отдельный Control на корне нужен потому, что
	# страница обрезает детей по своим границам, а предметы стоят на всей плите.
	_host = Control.new()
	_host.name = "Rooms"
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.add_child(_host)
	_jamb = _make_jamb()
	_host.add_child(_jamb)

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
		var d := TextureRect.new()
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.custom_minimum_size = Vector2(8, 8)
		d.size = Vector2(8, 8)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(d)
		_dots.append(d)

	_build_scene_props()
	# Навигация — поверх предметов: вырезка у края экрана не должна перекрывать
	# стрелку и запирать игрока в комнате.
	_host.move_child(_left_btn, -1)
	_host.move_child(_right_btn, -1)
	_host.move_child(dots, -1)
	_refresh_chrome()
	refresh_unlocks()
	_host.resized.connect(_on_resized)
	call_deferred("_on_resized")


func _make_plate(node_name: String, art: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	r.texture = load(SceneProps.ROOM_DIR + art + ".png") as Texture2D
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


## Косяк на стыке комнат: резная стойка из фона Мастерской, повторённая по
## высоте, и мягкие тени по бокам — стык читается как угол стены, а не разрыв.
func _make_jamb() -> Control:
	var root := Control.new()
	root.name = "RoomJamb"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	for side in [-1.0, 1.0]:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.03, 0.02, 0.015, 0.7))
		grad.set_color(1, Color(0.03, 0.02, 0.015, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 32
		gt.height = 4
		gt.fill_from = Vector2(0.5 - side * 0.5, 0.0)
		gt.fill_to = Vector2(0.5 + side * 0.5, 0.0)
		var sh := TextureRect.new()
		sh.name = "ShadowR" if side > 0.0 else "ShadowL"
		sh.texture = gt
		sh.stretch_mode = TextureRect.STRETCH_SCALE
		sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sh)
	var post := TextureRect.new()
	post.name = "Post"
	post.texture = load(SceneProps.ROOM_DIR + JAMB_ART + ".png") as Texture2D
	post.stretch_mode = TextureRect.STRETCH_TILE
	post.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(post)
	return root


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

	# Письма — свиток на полу у левой стены. Раньше тут лежала карта прогресса,
	# но она дублировала значок заданий в шапке.
	var letters := SceneProps.make_art_prop("prop_scroll", Vector2(258.0, 130.0))
	letters.name = "Prop_Letters"
	letters.pressed.connect(_open_tool.bind("letters"))
	_add_scene_prop(letters, Vector2(0.16, 0.87), Vector2(258.0, 130.0))

	# Устройства Мастерской — вырезки на её собственном фоне. Порядок добавления
	# = порядок отрисовки: дальняя реторта позади, ближний Родник поверх неё.
	for key in TOOL_ORDER:
		var prop := SceneProps.make_art_prop(TOOL_ART[key], TOOL_PLATE_PX[key], true)
		prop.name = "PropTool_" + String(key)
		prop.pressed.connect(_open_tool.bind(key))
		var shadow := _contact_shadow(float(TOOL_BASE_V[key]))
		prop.add_child(shadow)
		prop.move_child(shadow, 0)
		_host.add_child(prop)
		_props[key] = prop


func _contact_shadow(base_v: float) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.012, 0.008, 0.78))
	grad.set_color(1, Color(0.02, 0.012, 0.008, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 128
	gt.height = 32
	var r := TextureRect.new()
	r.name = "ContactShadow"
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.04
	r.anchor_right = 0.96
	r.anchor_top = base_v - 0.06
	r.anchor_bottom = base_v + 0.06
	return r


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


## Прямоугольник на плите в координатах экрана: доля uv → координаты при
## cover-масштабе плиты по всему окну. Плита — фон стартового экрана, поэтому
## и предметы считаются от окна, а не от площади вкладки.
func plate_rect(uv: Vector2, px: Vector2) -> Rect2:
	return _rect_on(_plate, PLATE_REF_PX, uv, px)


## То же для фона Мастерской: у неё свои пропорции, опорные пиксели и фокус
## по высоте (см. _layout_ws_plate) — поэтому считаем от его rect напрямую.
func workshop_rect(uv: Vector2, px: Vector2) -> Rect2:
	if _ws_plate == null or _ws_plate.size.x <= 0.0:
		return Rect2()
	var r := _ws_plate.get_global_rect()
	var disp := px * (r.size.x / WS_PLATE_REF_PX.x)
	return Rect2(r.position + uv * r.size - disp * 0.5, disp)


func _layout_ws_plate(dx: float) -> void:
	if _ws_plate == null or _ws_plate.texture == null or g == null:
		return
	var view := g.size
	var tex := _ws_plate.texture.get_size()
	var shown := tex * maxf(view.x / tex.x, view.y / tex.y)
	_ws_plate.size = shown
	# Высота пола и прилавка (доля фона WS_FOCUS_UV_Y) встаёт чуть ниже середины
	# экрана; кламп не даёт плите открыть край окна.
	var y := clampf(view.y * WS_FOCUS_SCREEN_Y - WS_FOCUS_UV_Y * shown.y, view.y - shown.y, 0.0)
	_ws_plate.position = Vector2(dx + (view.x - shown.x) * 0.5, y)


func _rect_on(plate: TextureRect, ref_px: Vector2, uv: Vector2, px: Vector2) -> Rect2:
	if plate == null or plate.texture == null:
		return Rect2()
	var tex := plate.texture.get_size()
	var plate_rect_global := plate.get_global_rect()
	if tex.x <= 0.0 or tex.y <= 0.0:
		return Rect2()
	if plate_rect_global.size.x <= 0.0 or plate_rect_global.size.y <= 0.0:
		return Rect2()
	var k := maxf(plate_rect_global.size.x / tex.x, plate_rect_global.size.y / tex.y)
	var shown := tex * k
	var origin := plate_rect_global.position + (plate_rect_global.size - shown) * 0.5
	var center := origin + uv * shown
	var disp := px * (shown.x / ref_px.x)
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
		_place(_props[key], workshop_rect(TOOL_PLATE_UV[key], TOOL_PLATE_PX[key]))
	_place_jamb()
	if g != null and g._pages != null and g._pages._experiment_field != null:
		g._pages._fit_experiment_overlay()


func _place_jamb() -> void:
	if _jamb == null or _ws_plate == null or _ws_plate.texture == null:
		return
	var view := _host.size
	var tex := _ws_plate.texture.get_size()
	var k := maxf(view.x / tex.x, view.y / tex.y)
	var post_w := JAMB_W * k
	var shadow_w := JAMB_SHADOW_W * k
	var seam_x := (1.0 - _pan) * view.x
	_jamb.position = Vector2(seam_x - post_w * 0.5 - shadow_w, 0.0)
	_jamb.size = Vector2(post_w + shadow_w * 2.0, view.y)
	var post := _jamb.get_node("Post") as TextureRect
	# Тайл не масштабирует текстуру: стойку рисуем в пикселях арта и ужимаем узел.
	post.scale = Vector2(k, k)
	post.position = Vector2(shadow_w, 0.0)
	post.size = Vector2(JAMB_W, view.y / k)
	var sl := _jamb.get_node("ShadowL") as Control
	sl.position = Vector2.ZERO
	sl.size = Vector2(shadow_w, view.y)
	var sr := _jamb.get_node("ShadowR") as Control
	sr.position = Vector2(shadow_w + post_w, 0.0)
	sr.size = Vector2(shadow_w, view.y)


func _on_resized() -> void:
	_set_pan(_pan)


## Камера между комнатами: плиты и страницы комнат сдвигаются на долю ширины,
## косяк стоит на стыке. В покое видна одна комната, косяка нет.
func _set_pan(p: float) -> void:
	if g == null or _plate == null:
		return
	_pan = clampf(p, 0.0, 1.0)
	var w := g.size.x
	_shift(_plate, -_pan * w)
	_layout_ws_plate((1.0 - _pan) * w)
	_shift(_rooms[0], -_pan * w)
	_shift(_rooms[1], (1.0 - _pan) * w)
	_plate.visible = _scene_visible and _pan < 1.0
	_ws_plate.visible = _scene_visible and _pan > 0.0
	(_rooms[0] as Control).visible = _pan < 1.0
	(_rooms[1] as Control).visible = _pan > 0.0
	_jamb.visible = _pan > 0.0 and _pan < 1.0
	_apply_prop_visibility()
	_layout_scene()


func _shift(c: Control, dx: float) -> void:
	c.offset_left = dx
	c.offset_right = dx


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
		_plate.visible = v and _pan < 1.0
	if _ws_plate != null:
		_ws_plate.visible = v and _pan > 0.0
	if _host != null:
		_host.visible = v


func _apply_prop_visibility() -> void:
	var lab_visible := _pan < 1.0 and not _props_hidden_by_picker
	for p in _scene_props:
		(p as Control).visible = lab_visible
	for key in _props:
		(_props[key] as Control).visible = _pan > 0.0


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
	_room_idx = i
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	var target := float(i)
	if Juice.enabled and not g._selftest and g.is_inside_tree():
		_turn_tween = g.create_tween()
		_turn_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_turn_tween.tween_method(_set_pan, _pan, target, TURN_SEC)
	else:
		# Selftest и выключенный juice: комната встаёт сразу, без промежуточных кадров.
		_set_pan(target)
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
		(_dots[i] as TextureRect).texture = load("res://assets/ui/kit_01b/13_page_dot_active.png" if i == _room_idx else "res://assets/ui/kit_01b/12_page_dot_inactive.png")


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
