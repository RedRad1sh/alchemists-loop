extends Control
class_name ContractBoard

# §5.2/§5.4: доска. Ничего не считает: состояние берёт из Contracts, награду просит
# через claim() (решение 3) и только рисует.

const RAIL := 40.0
const CORNER := 48.0
const SHELF_H := 28.0
const ROW_DY := 8.0
const WEEKLY_DY := 40.0
const BAND_DX := 4.0
const NOTE_GAP := 8.0
const CARD_GAP := 4.0
const SIGN_SIZE := Vector2(300, 84)
const RING_SIZE := Vector2(44, 44)
const NOTE_SIZE := Vector2(132, 88)
const POPUP_SIZE := Vector2(276, 366)
const NOTE_TICK := 1.0

const BOARD_TITLE := "Контрактная доска"
const POPUP_TITLE := "Получено"
const CAP_HINT := "Склад забит: часть награды не влезла"
const DECOR_MISSING_HINT := "в каталоге пока нет"
const SIGN_INK := Color(0.93, 0.86, 0.70)
const NOTE_INK := Color(0.16, 0.11, 0.07)

var g: Game
var _w := 0.0
var _h := 0.0
var _bg: TextureRect
var _rails: Array = []
var _corners: Array = []
var _shelf_daily: TextureRect
var _shelf_weekly: TextureRect
var _sign: TextureRect
var _sign_word: Label
var _ring: TextureButton
var _daily_row: Control
var _weekly_row: Control
var _notes: Control
var _cards: Array = []
var _popup: Control
var _note_clock := 0.0
var _closed := false
var _wired := false

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

func _build_layers() -> void:
	_bg = _layer("board_planks.png", "Planks")
	# Доска тайлится: один брусок 256 px на весь экран, а не растянутая картинка (§5.2.1).
	_bg.stretch_mode = TextureRect.STRETCH_TILE
	_bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	_rails = [_layer("frame_h.png", "RailTop"), _layer("frame_h.png", "RailBottom"),
		_layer("frame_v.png", "RailLeft"), _layer("frame_v.png", "RailRight")]
	(_rails[1] as TextureRect).flip_v = true
	(_rails[3] as TextureRect).flip_h = true

	# Один кованый уголок, четыре раза зеркалом (§5.2.2).
	_corners = []
	for i in range(4):
		var corner := _layer("corner_iron.png", "Corner%d" % i)
		corner.flip_h = (i & 1) == 1
		corner.flip_v = (i & 2) == 2
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

	_ring = TextureButton.new()
	_ring.name = "Ring"
	_ring.texture_normal = ContractCard.tex("ring_pull.png")
	_ring.ignore_texture_size = true
	_ring.stretch_mode = TextureButton.STRETCH_SCALE
	_ring.mouse_filter = Control.MOUSE_FILTER_STOP
	_ring.pressed.connect(_on_close)
	add_child(_ring)

func _add_card(row: Control) -> void:
	var card := ContractCard.new(g)
	card.name = "Card%d" % _cards.size()
	card.claimed.connect(_on_claim)
	row.add_child(card)
	_cards.append(card)

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

	_sign.position = Vector2((_w - SIGN_SIZE.x) / 2.0, RAIL + 4.0)
	_sign.size = SIGN_SIZE
	_sign_word.size = SIGN_SIZE

	var inner := _w - 2.0 * RAIL
	_notes.position = Vector2(RAIL + BAND_DX, RAIL + SIGN_SIZE.y + 16.0)
	_notes.size = Vector2(inner - 2.0 * BAND_DX, 2.0 * (NOTE_SIZE.y + NOTE_GAP))
	_shelf_daily.position = Vector2(RAIL, _notes.position.y + _notes.size.y + 4.0)
	_shelf_daily.size = Vector2(inner, SHELF_H)
	_shelf_weekly.position = Vector2(RAIL, _shelf_daily.position.y + SHELF_H + ROW_DY
		+ ContractCard.DAILY_SIZE.y + WEEKLY_DY)
	_shelf_weekly.size = Vector2(inner, SHELF_H)
	_daily_row.position = Vector2(RAIL, _shelf_daily.position.y + SHELF_H)
	_daily_row.size = Vector2(inner, ContractCard.DAILY_SIZE.y)
	_weekly_row.position = Vector2(RAIL, _shelf_weekly.position.y + SHELF_H)
	_weekly_row.size = Vector2(inner, ContractCard.WEEKLY_SIZE.y)
	_place(_daily_row, ContractCard.DAILY_SIZE)
	_place(_weekly_row, ContractCard.WEEKLY_SIZE)
	_ring.position = Vector2(_w - RAIL - RING_SIZE.x - 6.0, RAIL + 6.0)
	_ring.size = RING_SIZE
	_layout_notes()

static func _place(row: Control, sz: Vector2) -> void:
	var n := row.get_child_count()
	if n == 0:
		return
	var total := float(n) * sz.x + float(n - 1) * CARD_GAP
	var x0 := (row.size.x - total) / 2.0
	for i in range(n):
		(row.get_child(i) as Control).position = Vector2(x0 + float(i) * (sz.x + CARD_GAP), 0.0)

func refresh() -> void:
	var all := g._contracts.daily() + g._contracts.weekly()
	for i in range(_cards.size()):
		var card := _cards[i] as ContractCard
		if i < all.size():
			card.setup(all[i] as Dictionary)
			card.visible = true
		else:
			card.visible = false
	_relayout()

func _layout_notes() -> void:
	# remove_child + queue_free: освобождение отложено до конца кадра, и без remove_child
	# полоса на один кадр осталась бы с двумя наборами записок.
	for ch in _notes.get_children():
		_notes.remove_child(ch)
		ch.queue_free()
	var per_row := maxi(1, int((_notes.size.x + NOTE_GAP) / (NOTE_SIZE.x + NOTE_GAP)))
	var i := 0
	for raw in g._contracts.active_buffs():
		var note := _make_note(raw as Dictionary)
		_notes.add_child(note)
		note.position = Vector2(float(i % per_row) * (NOTE_SIZE.x + NOTE_GAP),
			float(i / per_row) * (NOTE_SIZE.y + NOTE_GAP))
		i += 1

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
	ok.position = Vector2((POPUP_SIZE.x - 120.0) / 2.0, POPUP_SIZE.y - 58.0)
	ok.pressed.connect(_on_reward_ok)
	pop.add_child(ok)
	_popup = pop

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
