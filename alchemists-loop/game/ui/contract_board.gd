extends Control
class_name ContractBoard

# §5.2/§5.4: доска. Ничего не считает: состояние берёт из Contracts, награду просит
# через claim() (решение 3) и только рисует.

const RAIL := 40.0
const CORNER := 48.0
const SHELF_H := 28.0
const ROW_DY := 8.0
const BAND_DX := 4.0
const NOTE_GAP := 8.0
const CARD_GAP := 4.0
const SIGN_SIZE := Vector2(300, 84)
const CLOSE_SIZE := Vector2(118, 38)
const SCROLL_STEP := 72.0
const SCROLL_HINT_SIZE := Vector2(160, 24)
const NOTE_SIZE := Vector2(132, 88)
const POPUP_SIZE := Vector2(276, 366)
const NOTE_TICK := 1.0
const SEAL_HOLD := 0.26
# доска v2 (Task 7, спека §5): полка очага под дневным рядом и строка ранга
# над нижним рельсом.
const HEARTH_H := 56.0
const RANK_H := 56.0
const RANK_NOTE := Vector2(150, 48)
const FLAME_INK := Color(1.0, 0.72, 0.30)
# Слои отрисовки: контент листается под рамой, поэтому рама, строка ранга,
# подсказка и кнопка закрытия обязаны лежать выше него.
const Z_RAIL := 2
const Z_CORNER := 3
const Z_RANK := 4
const Z_HINT := 5
const Z_CLOSE := 6

const BOARD_TITLE := "Контрактная доска"
const CLOSE_TEXT := "Закрыть"
const CLOSE_TIP := "Закрыть доску и вернуться в Дом"
const HINT_MORE := "▼ листай вниз"
const HINT_TOP := "▲ наверх"
const HINT_MID := "▲▼ листай"
const POPUP_TITLE := "Получено"
const CAP_HINT := "Склад забит: часть награды не влезла"
const DECOR_MISSING_HINT := "в каталоге пока нет"
const SIGN_INK := Color(0.93, 0.86, 0.70)
const NOTE_INK := Color(0.16, 0.11, 0.07)
# §D: текст не должен касаться кромки текстуры; §C: светлые чернила по латуни.
const BTN_M := 10.0
const PLATE_INK := Color(0.95, 0.88, 0.72)
const PLATE_INK_DIM := Color(0.72, 0.66, 0.53)
# Невытягиваемые поля plate_brass.png (224x64 @2x): 36 px держат гвоздик вместе
# с гнездом, 10 px — латунную кромку и запечённую тень под ней.
const PLATE_SIDE_FIELD := 36.0
const PLATE_EDGE_FIELD := 10.0

var g: Game
var _w := 0.0
var _h := 0.0
var _bg: TextureRect
var _strip_bg: TextureRect
var _strip_shadow: ColorRect
var _strip_cut: ColorRect
var _rails: Array = []
var _corners: Array = []
var _shelf_daily: TextureRect
var _shelf_weekly: TextureRect
var _shelf_hearth: Control
var _hearth_bar: TextureRect
var _hearth_box: HBoxContainer
var _hearth_btn: Button
var _hearth_flame: Label
var _rank_strip: Control
var _rank_symbol: CircleRankSymbol
var _rank_title: Label
var _mile_days: TextureRect
var _mile_pts: TextureRect
var _mile_days_word: Label
var _mile_pts_word: Label
var _sign: TextureRect
var _sign_word: Label
var _close_btn: Button
var _mask_top: Control
var _mask_bottom: Control
var _scroll_hint: Label
var _drag_from := NAN
var _notes_sig_cache := ""
var _daily_row: Control
var _weekly_row: Control
var _notes: Control
var _cards: Array = []
var _popup: Control
var _note_clock := 0.0
var _closed := false
var _wired := false
var _scroll_y := 0.0
var _scroll_max := 0.0

static func open(game: Game) -> void:
	if game.get_node_or_null("ContractBoard") != null:
		Sfx.click()
		return
	# Баг, который владелец уже ловил: два полноэкранных экрана поверх друга (§7).
	var s := game.get_node_or_null("SpringScreen")
	if s != null and s.has_method("_on_close"):
		s._on_close()
	game._close_sigil_collection()
	var board := ContractBoard.new(game)
	game.add_child(board)
	board.build()
	Juice.open(null, board)
	Sfx.click()

static func close_any(root: Node) -> void:
	var b := root.get_node_or_null("ContractBoard")
	if b != null and b.has_method("_on_close"):
		b._on_close()

func _init(game: Game) -> void:
	g = game
	name = "ContractBoard"
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 22

func build() -> void:
	_build_layers()
	for i in range(ContractsBalance.DAILY_SHOWN):
		_add_card(_daily_row)
	for i in range(ContractsBalance.WEEKLY_SHOWN):
		_add_card(_weekly_row)
	g.get_viewport().size_changed.connect(_relayout)
	_wired = true
	refresh()

func _layer(fname: String, node_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	r.texture = ContractCard.tex(fname)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

## §C: кнопка доски одевается в латунную плашку, а не перекрашивается глобально.
## `main.gd::_small_button` общая с Домом, Духом и Лабораторией, поэтому берётся
## она же (шрифт, размер, минимальная высота) и только подменяются stylebox'ы:
## жёлтые кнопки темы на доске выглядели чужеродными наклейками поверх дерева.
## Статическая и с полем `m`: карточка контракта тоже рисует плашку (кнопка
## «Влить» в ряду жилы), а `ContractBoard._mm` карточка уже зовёт статически.
static func style_plate(b: Button, m: float = BTN_M) -> void:
	var sb := StyleBoxTexture.new()
	sb.texture = ContractCard.tex("plate_brass.png")
	sb.texture_margin_left = PLATE_SIDE_FIELD
	sb.texture_margin_right = PLATE_SIDE_FIELD
	sb.texture_margin_top = PLATE_EDGE_FIELD
	sb.texture_margin_bottom = PLATE_EDGE_FIELD
	for k in ["content_margin_left", "content_margin_top",
			"content_margin_right", "content_margin_bottom"]:
		sb.set(k, m)
	var sbh: StyleBoxTexture = sb.duplicate()
	sbh.modulate_color = Color(1.08, 1.08, 1.08)
	var sbp: StyleBoxTexture = sb.duplicate()
	sbp.modulate_color = Color(0.94, 0.94, 0.94)
	# «1 px вниз» при нажатии: texture_offset в Godot 4 нет, сдвигаем поля контента.
	sbp.content_margin_top = m - 1.0
	sbp.content_margin_bottom = m + 1.0
	var sbd: StyleBoxTexture = sb.duplicate()
	sbd.modulate_color = Color(0.55, 0.55, 0.55)
	for pair in [["normal", sb], ["hover", sbh], ["pressed", sbp], ["disabled", sbd]]:
		b.add_theme_stylebox_override(pair[0], pair[1])
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color"]:
		b.add_theme_color_override(c, PLATE_INK)
	b.add_theme_color_override("font_disabled_color", PLATE_INK_DIM)

func _build_layers() -> void:
	_bg = _layer("board_planks.png", "Planks")
	# Доска тайлится: один брусок 256 px на весь экран, а не растянутая картинка (§5.2.1).
	_bg.stretch_mode = TextureRect.STRETCH_TILE
	_bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	_rails = [_layer("frame_h.png", "RailTop"), _layer("frame_h.png", "RailBottom"),
		_layer("frame_v.png", "RailLeft"), _layer("frame_v.png", "RailRight")]
	(_rails[1] as TextureRect).flip_v = true
	(_rails[3] as TextureRect).flip_h = true
	# Рама рисуется поверх листающегося контента: бумага, уехавшая под рельс,
	# должна исчезать под деревом, а не поверх него.
	for raw in _rails:
		(raw as TextureRect).z_index = Z_RAIL

	# Один кованый уголок, четыре раза зеркалом (§5.2.2).
	_corners = []
	for i in range(4):
		var corner := _layer("corner_iron.png", "Corner%d" % i)
		corner.flip_h = (i & 1) == 1
		corner.flip_v = (i & 2) == 2
		corner.z_index = Z_CORNER
		_corners.append(corner)

	_shelf_daily = _layer("shelf_bar.png", "ShelfDaily")
	_shelf_weekly = _layer("shelf_bar.png", "ShelfWeekly")

	_sign = _layer("sign_hang.png", "Sign")
	_sign_word = g._label(BOARD_TITLE, 18)
	_sign_word.name = "SignWord"
	_sign_word.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sign_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Парадный шрифт — тот же, что у заголовка шапки: доска не должна выглядеть
	# приложенной к игре системным Manrope.
	if g._font_runic != null:
		_sign_word.add_theme_font_override("font", g._font_runic)
	elif g._font_xbold != null:
		_sign_word.add_theme_font_override("font", g._font_xbold)
	_sign_word.add_theme_color_override("font_color", SIGN_INK)
	_sign.add_child(_sign_word)

	# Ряды — обычные Control, не контейнеры: карточка фиксированного размера, а контейнер
	# растянул бы бумагу до custom_minimum_size соседа (решение Task 9, п.5).
	_daily_row = Control.new()
	_daily_row.name = "DailyRow"
	_daily_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_daily_row)
	_weekly_row = Control.new()
	_weekly_row.name = "WeeklyRow"
	_weekly_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weekly_row)

	_notes = Control.new()
	_notes.name = "Notes"
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notes)

	# Полка очага (доска v2, спека §5): та же доска-полка, на ней — полешко и
	# пламя серии. Иммерсивность: реальная текстура shelf_bar, не Label-полоса.
	_shelf_hearth = Control.new()
	_shelf_hearth.name = "ShelfHearth"
	_shelf_hearth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shelf_hearth)
	_hearth_bar = TextureRect.new()
	_hearth_bar.name = "HearthBar"
	_hearth_bar.texture = ContractCard.tex("shelf_bar.png")
	_hearth_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hearth_bar.stretch_mode = TextureRect.STRETCH_SCALE
	_hearth_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shelf_hearth.add_child(_hearth_bar)
	_hearth_box = HBoxContainer.new()
	_hearth_box.name = "HearthBox"
	_hearth_box.add_theme_constant_override("separation", 8)
	_hearth_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shelf_hearth.add_child(_hearth_box)
	_hearth_btn = g._small_button("", Vector2(168, 40), 2)
	_hearth_btn.name = "HearthBtn"
	style_plate(_hearth_btn)
	_hearth_btn.pressed.connect(_on_hearth_pressed)
	_hearth_box.add_child(_hearth_btn)
	_hearth_flame = g._label("", 16)
	_hearth_flame.name = "HearthFlame"
	# g._label ставит autowrap: серия «✦✦» переносилась в два ряда и на кадре
	# выглядела двумя отдельными искрами рядом с кнопкой, а не серией.
	_hearth_flame.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hearth_flame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hearth_flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hearth_flame.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hearth_flame.add_theme_color_override("font_color", FLAME_INK)
	_hearth_box.add_child(_hearth_flame)

	# Маски ввода поверх полос рамы: листаясь, бумага уходит под рельс и под
	# строку ранга, и клик по ней там был бы кликом по невидимому контракту.
	# Добавлены ДО строки ранга и кнопки закрытия, чтобы те перехватывали ввод
	# раньше маски (Godot разбирает детей с конца).
	_mask_top = _input_mask("MaskTop")
	_mask_bottom = _input_mask("MaskBottom")

	# Строка ранга (спека §5): символ + титул + два бумажных свитка вех, над
	# нижним рельсом.
	_rank_strip = Control.new()
	_rank_strip.name = "RankStrip"
	_rank_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_strip.z_index = Z_RANK
	add_child(_rank_strip)
	# §A: строка ранга — плашка футера. Непрозрачная доска гасит бумаги, ушедшие
	# под неё при прокрутке (маска нижнего края ловит только ввод), а 2 px тени
	# над плашкой и 1 px светлого среза дают ей толщину рейки.
	_strip_bg = TextureRect.new()
	_strip_bg.name = "StripBg"
	_strip_bg.texture = ContractCard.tex("board_planks.png")
	_strip_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_strip_bg.stretch_mode = TextureRect.STRETCH_TILE
	_strip_bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_strip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_strip.add_child(_strip_bg)
	_strip_shadow = ColorRect.new()
	_strip_shadow.name = "StripShadow"
	_strip_shadow.color = Color(0.04, 0.02, 0.01, 0.55)
	_strip_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_shadow.position = Vector2(0.0, -2.0)
	_rank_strip.add_child(_strip_shadow)
	_strip_cut = ColorRect.new()
	_strip_cut.name = "StripCut"
	_strip_cut.color = Color(1.0, 0.86, 0.62, 0.16)
	_strip_cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_strip.add_child(_strip_cut)
	_rank_symbol = CircleRankSymbol.new()
	_rank_symbol.name = "RankSymbol"
	_rank_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_strip.add_child(_rank_symbol)
	_rank_title = g._label("", 14)
	_rank_title.name = "RankTitle"
	_rank_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_rank_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if g._font_semi != null:
		_rank_title.add_theme_font_override("font", g._font_semi)
	_rank_title.add_theme_color_override("font_color", SIGN_INK)
	_rank_strip.add_child(_rank_title)
	_mile_days = _rank_note("MileDays", "Вехи дней: закрывай дневные контракты — дни считаются в круг")
	_mile_pts = _rank_note("MilePts", "Вехи очков: тир закрытого контракта приносит вечные очки")
	_rank_strip.add_child(_mile_days)
	_rank_strip.add_child(_mile_pts)
	_mile_days_word = _mile_days.get_node("Word") as Label
	_mile_pts_word = _mile_pts.get_node("Word") as Label

	_scroll_hint = g._label("", 12)
	_scroll_hint.name = "ScrollHint"
	_scroll_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scroll_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scroll_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_hint.z_index = Z_HINT
	_scroll_hint.add_theme_color_override("font_color", SIGN_INK)
	add_child(_scroll_hint)

	# Закрытие — подписанная кнопка, как на каждом другом экране: кованое
	# кольцо без надписи игрок принимал за декор и не находил выход.
	_close_btn = g._small_button(CLOSE_TEXT, CLOSE_SIZE, 2)
	_close_btn.name = "Close"
	style_plate(_close_btn)
	_close_btn.tooltip_text = CLOSE_TIP
	_close_btn.z_index = Z_CLOSE
	_close_btn.pressed.connect(_on_close)
	add_child(_close_btn)

func _input_mask(node_name: String) -> Control:
	var m := Control.new()
	m.name = node_name
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(m)
	return m

func _add_card(row: Control) -> void:
	var card := ContractCard.new(g)
	card.name = "Card%d" % _cards.size()
	card.claimed.connect(_on_claim)
	row.add_child(card)
	_cards.append(card)

# Бумажный свиток вех в строке ранга: real paper_note.png +(child Label, как
# записки баффов — правило immersive UI, не Label-простыня.
func _rank_note(node_name: String, tip: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	r.texture = ContractCard.tex("paper_note.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.tooltip_text = tip
	var w := g._label("", 10)
	w.name = "Word"
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.add_theme_color_override("font_color", NOTE_INK)
	w.position = Vector2(4.0, 4.0)
	w.size = RANK_NOTE - Vector2(8.0, 8.0)
	r.add_child(w)
	return r

func _relayout() -> void:
	var vp: Vector2 = g.get_viewport_rect().size
	_w = vp.x
	_h = vp.y
	position = Vector2.ZERO
	size = vp
	_bg.size = vp

	_rails[0].size = Vector2(_w, RAIL)
	_rails[1].position = Vector2(0.0, _h - RAIL)
	_rails[1].size = Vector2(_w, RAIL)
	_rails[2].position = Vector2(0.0, RAIL)
	_rails[2].size = Vector2(RAIL, _h - 2.0 * RAIL)
	_rails[3].position = Vector2(_w - RAIL, RAIL)
	_rails[3].size = Vector2(RAIL, _h - 2.0 * RAIL)
	for i in range(_corners.size()):
		var corner := _corners[i] as TextureRect
		corner.size = Vector2(CORNER, CORNER)
		corner.position = Vector2(0.0 if (i & 1) == 0 else _w - CORNER,
			0.0 if (i & 2) == 0 else _h - CORNER)

	var inner := _w - 2.0 * RAIL
	# Контент листается: восемь бумаг (4 дневных + 4 недельных) в портрете
	# 540×960 дают ~1360 px при видимой полосе ~824 px. Первый проход без
	# сдвига измеряет настоящую высоту (wrapping-_place пересчитывает её сам),
	# второй — сдвигает на уже ограниченный _scroll_y.
	_layout_flow(RAIL, inner)
	var view_bottom := _h - RAIL - RANK_H
	var nat_bottom := _weekly_row.position.y + _weekly_row.size.y
	_scroll_max = maxf(0.0, nat_bottom - view_bottom)
	_scroll_y = clampf(_scroll_y, 0.0, _scroll_max)
	if _scroll_y > 0.0:
		_layout_flow(RAIL - _scroll_y, inner)

	# Строка ранга — над нижним рельсом (спека §5), ниже её только сам рельс.
	_rank_strip.position = Vector2(RAIL, _h - RAIL - RANK_H)
	_rank_strip.size = Vector2(inner, RANK_H)
	_strip_bg.size = Vector2(inner, RANK_H)
	_strip_shadow.size = Vector2(inner, 2.0)
	_strip_cut.position = Vector2(0.0, 0.0)
	_strip_cut.size = Vector2(inner, 1.0)
	_rank_symbol.position = Vector2(2.0, (RANK_H - 48.0) / 2.0)
	_rank_symbol.size = Vector2(48.0, 48.0)
	_mile_pts.position = Vector2(inner - RANK_NOTE.x, (RANK_H - RANK_NOTE.y) / 2.0)
	_mile_pts.size = RANK_NOTE
	_mile_days.position = Vector2(inner - 2.0 * RANK_NOTE.x - 4.0, _mile_pts.position.y)
	_mile_days.size = RANK_NOTE
	_rank_title.position = Vector2(56.0, 0.0)
	_rank_title.size = Vector2(_mile_days.position.x - 62.0, RANK_H)

	_mask_top.position = Vector2.ZERO
	_mask_top.size = Vector2(_w, RAIL)
	_mask_bottom.position = Vector2(0.0, view_bottom)
	_mask_bottom.size = Vector2(_w, _h - view_bottom)
	# Кнопка закрытия — в правом краю верхнего рельса: вывеска по центру
	# (x 120..420), а правый уголок начинается с _w - CORNER.
	_close_btn.position = Vector2(_w - CORNER - CLOSE_SIZE.x - 4.0, (RAIL - CLOSE_SIZE.y) / 2.0)
	_close_btn.size = CLOSE_SIZE
	_scroll_hint.position = Vector2((_w - SCROLL_HINT_SIZE.x) / 2.0,
		view_bottom - SCROLL_HINT_SIZE.y - 2.0)
	_scroll_hint.size = SCROLL_HINT_SIZE
	_refresh_scroll_hint()
	_layout_notes()

# Поток контента: вывеска → записки баффов → дневная полка и ряд → очаг →
# недельная полка и ряд. `top` — верх видимой полосы с учётом прокрутки.
func _layout_flow(top: float, inner: float) -> void:
	_sign.position = Vector2((_w - SIGN_SIZE.x) / 2.0, top + 4.0)
	_sign.size = SIGN_SIZE
	_sign_word.size = SIGN_SIZE
	_notes.position = Vector2(RAIL + BAND_DX, top + SIGN_SIZE.y + 16.0)
	_notes.size = Vector2(inner - 2.0 * BAND_DX, 2.0 * (NOTE_SIZE.y + NOTE_GAP))
	_shelf_daily.position = Vector2(RAIL, _notes.position.y + _notes.size.y + 4.0)
	_shelf_daily.size = Vector2(inner, SHELF_H)
	_daily_row.position = Vector2(RAIL, _shelf_daily.position.y + SHELF_H)
	_daily_row.size = Vector2(inner, ContractCard.DAILY_SIZE.y)
	_place(_daily_row, ContractCard.DAILY_SIZE)
	# Доска v2 (Task 7): полка очага — ПОСЛЕ дневного ряда, поэтому её точка
	# привязки читается фактической высотой ряда, которую вернул wrapping-_place.
	_shelf_hearth.position = Vector2(RAIL, _daily_row.position.y + _daily_row.size.y + ROW_DY)
	_shelf_hearth.size = Vector2(inner, HEARTH_H)
	_hearth_bar.position = Vector2(0.0, HEARTH_H - SHELF_H)
	_hearth_bar.size = Vector2(inner, SHELF_H)
	_hearth_box.position = Vector2(8.0, HEARTH_H - SHELF_H - 30.0)
	_hearth_box.size = Vector2(inner - 16.0, 40.0)
	_shelf_weekly.position = Vector2(RAIL, _shelf_hearth.position.y + HEARTH_H + ROW_DY)
	_shelf_weekly.size = Vector2(inner, SHELF_H)
	_weekly_row.position = Vector2(RAIL, _shelf_weekly.position.y + SHELF_H)
	_weekly_row.size = Vector2(inner, ContractCard.WEEKLY_SIZE.y)
	_place(_weekly_row, ContractCard.WEEKLY_SIZE)

func _scroll_to(v: float) -> void:
	var y := clampf(v, 0.0, _scroll_max)
	if is_equal_approx(y, _scroll_y):
		return
	_scroll_y = y
	_relayout()

func _scroll_by(dy: float) -> void:
	_scroll_to(_scroll_y + dy)

func _refresh_scroll_hint() -> void:
	if _scroll_max <= 0.0:
		_scroll_hint.visible = false
		return
	_scroll_hint.visible = true
	if _scroll_y <= 0.0:
		_scroll_hint.text = HINT_MORE
	elif _scroll_y >= _scroll_max:
		_scroll_hint.text = HINT_TOP
	else:
		_scroll_hint.text = HINT_MID

## Колесо и перетаскивание листают доску. Drag обязателен: игра портретная и
## целевая платформа — Android, где колеса нет вовсе.
func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			accept_event()
			_scroll_by(SCROLL_STEP)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			accept_event()
			_scroll_by(-SCROLL_STEP)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_from = mb.global_position.y if mb.pressed else NAN
			return
	var mm := ev as InputEventMouseMotion
	if mm == null or is_nan(_drag_from):
		return
	accept_event()
	_scroll_by(_drag_from - mm.global_position.y)
	_drag_from = mm.global_position.y

# Доска v2 (Task 7, спека §2): ряд — wrapping-сетка. Карточки фиксированного
# размера, сколько влезает в ширину ряда — ровно столько в линии; остаток
# уходит на вторую линию, а высота ряда пересчитывается и читается _relayout
# ФАКТИЧЕСКИМ значением (полка очага и недельная полка привязаны от неё).
static func _place(row: Control, sz: Vector2) -> void:
	var n := row.get_child_count()
	if n == 0:
		return
	var per_row := maxi(1, int((row.size.x + CARD_GAP) / (sz.x + CARD_GAP)))
	var rows := int(ceil(float(n) / float(per_row)))
	row.size = Vector2(row.size.x, float(rows) * sz.y + float(rows - 1) * ROW_DY)
	for i in range(n):
		@warning_ignore("integer_division")
		var r := i / per_row
		var cnt := mini(per_row, n - r * per_row)
		var total := float(cnt) * sz.x + float(cnt - 1) * CARD_GAP
		var x0 := (row.size.x - total) / 2.0
		(row.get_child(i) as Control).position = Vector2(
			x0 + float(i % per_row) * (sz.x + CARD_GAP), float(r) * (sz.y + ROW_DY))

func refresh() -> void:
	var all := g._contracts.daily() + g._contracts.weekly()
	for i in range(_cards.size()):
		var card := _cards[i] as ContractCard
		if i < all.size():
			card.setup(all[i] as Dictionary)
			card.visible = true
		else:
			card.visible = false
	_refresh_hearth()
	_refresh_rank()
	_relayout()

# Очаг (спека §5): полешко раз в день, пламя — шкала серии.
func _refresh_hearth() -> void:
	var c := g._contracts
	var claimable := c.hearth_claimable()
	_hearth_btn.text = "Полешко: +%d ⚡" % c.hearth_reward() if claimable else "Забрано ✓"
	_hearth_btn.disabled = not claimable
	_hearth_flame.text = c.flame()

func _refresh_rank() -> void:
	var c := g._contracts
	var lvl := c.rank_level()
	_rank_symbol.setup(lvl)
	_rank_title.text = c.rank_title(lvl)
	_mile_days_word.text = "Вехи дней: %s" % c.mile_strip("дней", Game.CIRCLE_DAY_MILES, c._mdays)
	_mile_pts_word.text = "Вехи очков: %s" % c.mile_strip("очков", Game.CIRCLE_PTS_MILES, c._mpts)

func _on_hearth_pressed() -> void:
	Sfx.click()
	var lvl_before := g._contracts.rank_level()
	g._contracts.claim_hearth()
	Juice.pop(_hearth_flame, UIStyle.TEAL)
	if g._contracts.rank_level() > lvl_before:
		Juice.pop(_rank_symbol, UIStyle.GOLD)
		Juice.ring(_rank_symbol, _rank_symbol.get_global_rect().get_center(), UIStyle.GOLD, 60.0)

func _layout_notes() -> void:
	# Прокрутка зовёт _relayout на каждое событие пальца/колеса; без подписи
	# полоса пересобирала бы записки 60 раз в секунду на ровном месте.
	var buffs: Array = g._contracts.active_buffs()
	var sig := _notes_sig(buffs)
	if sig == _notes_sig_cache and _notes.get_child_count() == buffs.size():
		return
	_notes_sig_cache = sig
	# remove_child + queue_free: освобождение отложено до конца кадра, и без remove_child
	# полоса на один кадр осталась бы с двумя наборами записок.
	for ch in _notes.get_children():
		_notes.remove_child(ch)
		ch.queue_free()
	var per_row := maxi(1, int((_notes.size.x + NOTE_GAP) / (NOTE_SIZE.x + NOTE_GAP)))
	var i := 0
	for raw in buffs:
		var note := _make_note(raw as Dictionary)
		_notes.add_child(note)
		note.position = Vector2(float(i % per_row) * (NOTE_SIZE.x + NOTE_GAP),
			float(i / per_row) * (NOTE_SIZE.y + NOTE_GAP))
		i += 1

func _notes_sig(buffs: Array) -> String:
	var parts: Array = ["%d" % int(_notes.size.x)]
	for raw in buffs:
		var b := raw as Dictionary
		parts.append("%s:%d" % [String(b["id"]), int(b["left"])])
	return "|".join(parts)

func _make_note(b: Dictionary) -> TextureButton:
	var id := String(b["id"])
	var shown := _mm(int(b["left"]))
	var note := TextureButton.new()
	note.name = "Note_%s" % id
	note.texture_normal = ContractCard.tex("paper_note.png")
	note.ignore_texture_size = true
	note.stretch_mode = TextureButton.STRETCH_SCALE
	note.mouse_filter = Control.MOUSE_FILTER_STOP
	note.size = NOTE_SIZE
	note.set_meta("id", id)
	note.set_meta("time", shown)
	note.set_meta("title", String(b["title"]))
	note.set_meta("effect", String(ContractsBalance.BUFF_TEXT.get(id, "")))
	note.set_meta("pct", "%d%%" % int(round(100.0 * float(b["power"]))))
	note.set_meta("shown_detail", false)
	# Наведение — полная расшифровка: что за бафф, что делает, насколько силён.
	note.tooltip_text = "%s — %s (+%s), осталось %s" % [String(b["title"]),
		String(ContractsBalance.BUFF_TEXT.get(id, "")), String(note.get_meta("pct")), shown]
	note.pressed.connect(_on_note_pressed.bind(note))

	var w := g._label(shown, 13)
	w.name = "Time"
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.clip_text = true
	w.add_theme_color_override("font_color", NOTE_INK)
	w.position = Vector2(6.0, 24.0)
	w.size = Vector2(NOTE_SIZE.x - 12.0, 50.0)
	note.add_child(w)

	# Гвоздь поверх записки — тот же приём, что у бумаг Task 9: приколотый лист,
	# а не нарисованный кодом кружок.
	var pin := TextureRect.new()
	pin.name = "Pin"
	pin.texture = ContractCard.tex("nail_brass.png")
	pin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pin.stretch_mode = TextureRect.STRETCH_SCALE
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin.position = Vector2(NOTE_SIZE.x / 2.0 - 16.0, -16.0)
	pin.size = Vector2(32.0, 32.0)
	note.add_child(pin)
	return note

static func _word_of(note: Node) -> Label:
	for ch in note.get_children():
		var l := ch as Label
		if l != null:
			return l
	return null

func _on_note_pressed(note: Node) -> void:
	Sfx.click()
	var w := _word_of(note)
	if w == null:
		return
	if bool(note.get_meta("shown_detail", false)):
		w.text = String(note.get_meta("time"))
		note.set_meta("shown_detail", false)
		return
	w.text = "%s\n%s · %s" % [String(note.get_meta("title")),
		String(note.get_meta("effect")), String(note.get_meta("pct"))]
	note.set_meta("shown_detail", true)

func _process(delta: float) -> void:
	if _notes == null:
		return
	_note_clock += delta
	if _note_clock < NOTE_TICK:
		return
	_note_clock = 0.0
	_layout_notes()

static func _mm(total: int) -> String:
	var t := maxi(0, total)
	return "%d:%02d" % [int(float(t) / 3600.0), int(fmod(float(t), 3600.0) / 60.0)]

func _on_claim(id: String) -> void:
	var result := g._contracts.claim(id)
	if Juice.enabled and bool(result["ok"]):
		# Состояние списано СРАЗУ; только выдача ждёт, пока штамп сядет.
		var t := create_tween()
		t.tween_interval(SEAL_HOLD)
		t.tween_callback(_after_claim.bind(result))
	else:
		_after_claim(result)


func _after_claim(result: Dictionary) -> void:
	refresh()
	if bool(result["ok"]):
		_show_reward(result)

func _reward_text(r: Dictionary) -> String:
	var lines: Array = []
	var mats := r["materials"] as Dictionary
	var names: Array = []
	for raw_id in mats:
		var item_id := String(raw_id)
		names.append("%s ×%d" % [g._online._item_name(item_id), int(mats[raw_id])])
	if not names.is_empty():
		lines.append(", ".join(names))
	var buff := String(r["buff"])
	if buff != "":
		lines.append("%s +%d%% · %s" % [String(ContractsBalance.BUFF_TITLE.get(buff, "")),
			int(round(100.0 * float(r["power"]))), _mm(int(r["duration"]))])
	var decor := String(r["decor"])
	if decor != "":
		var decor_line := String(ContractsBalance.DECOR_LABEL.get(decor, ""))
		if bool(r["missing_decor"]):
			decor_line = "%s (%s)" % [decor_line, DECOR_MISSING_HINT]
		lines.append(decor_line)
	if bool(r["truncated"]):
		lines.append(CAP_HINT)
	return "\n".join(lines)

func _show_reward(result: Dictionary) -> void:
	_close_reward()
	var pop := Control.new()
	pop.name = "RewardPopup"
	pop.mouse_filter = Control.MOUSE_FILTER_STOP
	pop.size = POPUP_SIZE
	pop.position = Vector2((_w - POPUP_SIZE.x) / 2.0, (_h - POPUP_SIZE.y) / 2.0)
	add_child(pop)
	var paper := TextureRect.new()
	paper.name = "Paper"
	paper.texture = ContractCard.tex("paper_weekly.png")
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = POPUP_SIZE
	pop.add_child(paper)
	var title := g._label(POPUP_TITLE, 18)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if g._font_semi != null:
		title.add_theme_font_override("font", g._font_semi)
	title.add_theme_color_override("font_color", NOTE_INK)
	title.position = Vector2(0.0, 18.0)
	title.size = Vector2(POPUP_SIZE.x, 26.0)
	pop.add_child(title)
	var body := g._label(_reward_text(result), 13)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.clip_text = true
	body.add_theme_color_override("font_color", NOTE_INK)
	body.position = Vector2(18.0, 54.0)
	body.size = Vector2(POPUP_SIZE.x - 36.0, POPUP_SIZE.y - 122.0)
	pop.add_child(body)
	var ok := g._small_button("OK", Vector2(120, 44))
	ok.name = "Ok"
	style_plate(ok)
	ok.position = Vector2((POPUP_SIZE.x - 120.0) / 2.0, POPUP_SIZE.y - 58.0)
	ok.pressed.connect(_on_reward_ok)
	pop.add_child(ok)
	_popup = pop
	Juice.open(null, pop)

func _on_reward_ok() -> void:
	Sfx.click()
	_close_reward()

func _close_reward() -> void:
	if _popup == null:
		return
	var pop := _popup
	_popup = null
	remove_child(pop)
	pop.queue_free()

func _on_close() -> void:
	if _closed:
		return
	_closed = true
	Sfx.click()
	_close_reward()
	if _wired:
		g.get_viewport().size_changed.disconnect(_relayout)
		_wired = false
	queue_free()
