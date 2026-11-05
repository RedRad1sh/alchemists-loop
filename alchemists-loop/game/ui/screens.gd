extends RefCounted
class_name ScreenRouter
# Экран механики вместо модалки (претензия владельца: «ты не модалки делай, ты
# полноценные экраны должен открыть»). Главный экран — комната, она же роутер:
# тап по предмету открывает его экран на весь экран, а не окно поверх комнаты.
#
# Слои: комната (плита+предметы) при открытом экране гаснет целиком — экран
# забирает её фон себе, только приближённый к предмету (focus_on). Ниже экрана
# remain фон игры, выше — нижний бар (z=17, тап по нему закрывает экран) и
# модалки (dim 20 / popup 21): попап по-прежнему перекрывает экран.
#
# Контент — существующие узлы механик: на открытии они переезжают в host
# (reparent), на закрытии возвращаются, поэтому refresh-логика и контракты
# тестов не разъезжаются. Прокручиваемый контент лежит на текстурной панели с
# полями (panel), экран котла — нет (fill: он сам правит координаты на проекции
# плиты).

const SCREEN_Z := 16
const HEADER_H := 52.0
const NAV_GAP := 6.0
const SIDE_M := 12.0
const TOP_M := 6.0
const BOTTOM_M := 10.0
const PAD_M := 14.0
const PLATE_REF_PX := Vector2(1080.0, 1609.0)
const PLATE_ART := "room_plate"

var g: Game
var root: Control = null
var backdrop: TextureRect = null
var host: Control = null
var panel: PanelContainer = null
var scroll: ScrollContainer = null
var host_box: VBoxContainer = null
var title_label: Label = null
var back_btn: Button = null
var node: Control = null

var _key := ""
var _orig_parent: Control = null
var _on_close: Callable = Callable()
var _fill := false
# Проекция плиты: cover без приближения + коэффициент фокуса. Хранятся, чтобы
# plate_rect() отдавал тем же предметам те же места, что и плите в комнате.
# `_shown` — это rect фона, собранный под пропорцию текстуры: KEEP_ASPECT_COVERED
# не режет плиту, и точка uv лежит ровно на corner + uv*shown*s. Rect по размеру
# root обрезал бы верх и низ плиты, а котёл у нижнего края арта уезжал бы за
# экран (кадр варки: половина котла отсутствовала).
var _shown := Vector2.ZERO
var _s := 1.0
# Верхний левый угол плиты на экране после клампа покрытием — из него же
# считает свои прямоугольники plate_rect(), чтобы предмет стоял там, где он
# нарисован, а не там, куда его попросил фокус.
var _corner := Vector2.ZERO
var _focus_center := Vector2.ZERO
var _focus_uv := Vector2(0.5, 0.5)
var _focus_px := Vector2(520.0, 685.0)
var _focus_w := 0.0


func build(game: Game) -> void:
	g = game
	root = Control.new()
	root.name = "Screens"
	root.z_index = SCREEN_Z
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.add_child(root)

	backdrop = TextureRect.new()
	backdrop.name = "ScreenBackdrop"
	backdrop.texture = load(SceneProps.ROOM_DIR + PLATE_ART + ".png") as Texture2D
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TOP_LEFT вместо FULL_RECT: position/scale/pivot фокуса заданы явно, и
	# якоря не должны спорить с ними при каждом ресайзе.
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.add_child(backdrop)

	host = Control.new()
	host.name = "ScreenHost"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.add_child(host)

	# Контент лежит на текстурной панели с полями, а не на краске плиты. Это то,
	# что давал удалённый bottom-sheet; без панели экран механики — голый текст
	# от края до края поверх доски контрактов (кадр «Верстак», претензия владельца
	# «вся вёрстка в окнах полетела»). Экран при этом остаётся полноэкранным:
	# панель занимает всё тело под шапкой, а не висит окном по центру.
	panel = PanelContainer.new()
	panel.name = "ScreenPanel"
	panel.add_theme_stylebox_override("panel", UIStyle.modal_panel(UIStyle.BRASS_HI))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = SIDE_M
	panel.offset_top = TOP_M
	panel.offset_right = -SIDE_M
	panel.offset_bottom = -BOTTOM_M
	host.add_child(panel)

	scroll = ScrollContainer.new()
	scroll.name = "ScreenScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)

	var pad := MarginContainer.new()
	pad.name = "ScreenPadding"
	# Без EXPAND_FILL ScrollContainer даёт ребёнку его минимальную ширину, а
	# минимум autowrap-лейбла — одна буква: текст «Верстака» сложился в колонку
	# по 3 знака (кадр windows-hd2).
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, PAD_M)
	scroll.add_child(pad)

	host_box = VBoxContainer.new()
	host_box.name = "ScreenBody"
	host_box.add_theme_constant_override("separation", 8)
	host_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(host_box)

	var head := HBoxContainer.new()
	head.name = "ScreenHeader"
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.add_child(head)
	back_btn = g._small_button("← В комнату", Vector2(126, 40), 1)
	back_btn.name = "ScreenBack"
	back_btn.pressed.connect(close)
	head.add_child(back_btn)
	title_label = g._label("", 17)
	title_label.name = "ScreenTitle"
	# autowrap в HBox считает минимум по ширине одной буквы: заголовок раздувал
	# шапку до 221 px и тянул за собой кнопку «В комнату» (контейнер не сжимает
	# детей ниже минимума). Заголовок — одна строка.
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	title_label.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.03, 0.92))
	title_label.add_theme_constant_override("outline_size", 6)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)

	root.resized.connect(_relayout)
	call_deferred("_relayout")


## Нижняя граница контента: над баром навигации, иначе последний ряд уезжает
## под панель (как на старом экране вкладки).
func _body_rect() -> Rect2:
	var w := root.size.x
	var nav := BottomNav.NAV_H + NAV_GAP
	var top := HEADER_H + (48.0 if _key in ["cauldron", "brew"] else 0.0)
	return Rect2(0.0, top, w, maxf(0.0, root.size.y - top - nav))


func _relayout() -> void:
	if root == null or root.size.x <= 0.0 or root.size.y <= 0.0:
		return
	var body := _body_rect()
	backdrop.size = _cover_shown()
	host.position = body.position
	host.size = body.size
	var head := back_btn.get_parent() as Control
	if head != null:
		head.position = Vector2(12.0, 6.0)
		head.size = Vector2(root.size.x - 24.0, HEADER_H - 12.0)
	_apply_focus()
	if _key in ["cauldron", "brew"]:
		g._pages._fit_cauldron_modes()
	if _key == "cauldron":
		g._pages._fit_experiment_overlay()


## Нейтральная проекция плиты: без приближения, центр плиты в центре экрана.
## Открытие нового экрана обязано её вернуть, иначе зум котла пережил бы закрытие.
func reset_focus() -> void:
	focus_on(Vector2(0.5, 0.5), PLATE_REF_PX, 0.0,
			root.global_position + root.size * 0.5)


## Приближение плиты: uv-точка предмета должна встать в center и стать target_w
## пикселей шириной — ровно там, где её рисует плита, если фокусу хватает
## покрытия (см. _project).
func focus_on(uv: Vector2, px: Vector2, target_w: float, center: Vector2) -> void:
	_focus_uv = uv
	_focus_px = px
	_focus_w = target_w
	_focus_center = center
	_apply_focus()


## Cover-размер плиты: rect, в котором KEEP_ASPECT_COVERED рисует текстуру
## целиком, без обрезки. По обеим осям он не меньше root, поэтому смещение фона
## всегда имеет запас — и котёл у нижнего края арта остаётся в кадре.
func _cover_shown() -> Vector2:
	if backdrop == null or backdrop.texture == null or root.size.x <= 0.0:
		return root.size
	var tex := backdrop.texture.get_size()
	return tex * maxf(root.size.x / tex.x, root.size.y / tex.y)


## Проекция фокуса: масштаб под target_w и угол плиты под center — но без
## записи в backdrop, чтобы экран перебирал раскладки по предсказанию кадра.
func _project(uv: Vector2, px: Vector2, target_w: float, center: Vector2) -> Dictionary:
	var shown := _cover_shown()
	var s := 1.0
	var disp_x := px.x * (shown.x / PLATE_REF_PX.x)
	if target_w > 0.0 and disp_x > 0.0:
		s = target_w / disp_x
	# 1.0 — это кадр комнаты. Ниже не уходить: уменьшенная плита перестала бы
	# покрывать root, и по краям экрана выглянул бы интерфейс игры (шапка с
	# «Дом» и «Лавка»).
	s = clampf(s, 1.0, 8.0)
	var raw := _root_local(center) - uv * shown * s
	# Угол клампится покрытием: плита обязана накрывать root целиком, иначе
	# фокус у края обнажает противоположную сторону экрана.
	var corner := Vector2(
			clampf(raw.x, root.size.x - shown.x * s, 0.0),
			clampf(raw.y, root.size.y - shown.y * s, 0.0))
	return {"shown": shown, "s": s, "corner": corner}


func _apply_focus() -> void:
	if backdrop == null or backdrop.texture == null or root.size.x <= 0.0:
		return
	var f := _project(_focus_uv, _focus_px, _focus_w, _focus_center)
	_shown = f["shown"]
	_s = f["s"]
	_corner = f["corner"]
	backdrop.size = _shown
	backdrop.pivot_offset = Vector2.ZERO
	backdrop.position = _corner
	backdrop.scale = Vector2(_s, _s)


## Прямоугольник плиты в экранных координатах при текущем фокусе — тот же
## договор, что у RoomCarousel.plate_rect, только с приближением.
func plate_rect(uv: Vector2, px: Vector2) -> Rect2:
	return _rect_at(uv, px, _shown, _s, _corner)


## Тот же кадр, который поставит focus_on(), но никуда не записывая: страница
## котла выбирает сторону лотка до применения фокуса.
func projected_item_rect(uv: Vector2, px: Vector2, target_w: float,
		center: Vector2) -> Rect2:
	var f := _project(uv, px, target_w, center)
	return _rect_at(uv, px, f["shown"], f["s"], f["corner"])


func _rect_at(uv: Vector2, px: Vector2, shown: Vector2, s: float,
		corner: Vector2) -> Rect2:
	if shown.x <= 0.0:
		return Rect2()
	var disp := px * (shown.x / PLATE_REF_PX.x) * s
	return Rect2(root.global_position + corner + uv * shown * s - disp * 0.5, disp)


func _root_local(global_pos: Vector2) -> Vector2:
	return global_pos - root.global_position


func key() -> String:
	return _key


func is_open() -> bool:
	return root != null and root.visible and _key != ""


## fill=true — контент сам правит свои координаты (поле эксперимента: котёл и
## жетоны на проекции плиты); иначе контент живёт в прокручиваемой колонке.
func open(key: String, title: String, content: Control,
		on_close: Callable = Callable(), fill: bool = false) -> void:
	if root == null or content == null:
		return
	if _key == key:
		return
	close()
	_key = key
	node = content
	_orig_parent = content.get_parent() as Control
	_on_close = on_close
	_fill = fill
	# Фон экрана стартует с нейтрального кадра: зум предыдущего экрана не должен
	# пережить его закрытие.
	reset_focus()
	# add_child не переносит узел с родителем — только reparent.
	panel.visible = not fill
	content.reparent(host if fill else host_box)
	content.visible = true
	if fill:
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		(content as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text = title
	root.visible = true
	_relayout()
	if g._rooms != null:
		g._rooms.set_scene_visible(false)
	Sfx.click()


func close() -> void:
	var was := _key
	var back := node
	var parent := _orig_parent
	var paged := not _fill
	var cb := _on_close
	_key = ""
	node = null
	_orig_parent = null
	_on_close = Callable()
	_fill = false
	if is_instance_valid(back) and is_instance_valid(parent):
		(back as Control).set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		back.reparent(parent)
		# видимость колонок возвращается под управление выбора в «Инструментах»;
		# поле эксперимента в комнате видно и так — оно в потоке вкладки.
		if paged:
			g._pages._apply_tools_selection()
	if root != null:
		root.visible = false
	if g._rooms != null and g._tabs_ref != null:
		g._rooms.set_scene_visible(g._tabs_ref.current_tab == Game.TAB_EXPERIMENT)
	if was != "" and cb.is_valid():
		cb.call()
