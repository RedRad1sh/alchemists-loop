extends RefCounted
class_name DailyGrid
# Дейли-сетка «Дары цикла» (§11 дока): 7 дней по кругу, стрик сбрасывается
# при пропуске дня. Награды — только существующие сущности: эфир (уходит через
# overflow и не сгорает), ×2 добыча (source_boost), дружба со Светиком.
# Состояние (claim_day/streak) живёт в сейве.

var g: Game
var claim_day := ""
var streak := 0

var _dim: ColorRect = null
var _popup: CenterContainer = null
var _cells: Array = []
var _claim_btn: Button = null
var _head: Label = null

# [эфир, буст-секунды, дружба]
const REWARDS := [
	[30, 0, 0],
	[0, 600, 0],
	[0, 0, 3],
	[50, 0, 0],
	[0, 600, 0],
	[70, 0, 0],
	[120, 0, 5],
]


func _today() -> String:
	return Time.get_date_string_from_system()


func _yesterday() -> String:
	# Вчерашний день — по той же локальной календарной базе, что и _today().
	# Unix-арифметика (get_date_string_from_unix_time) даёт UTC: в часовой зоне
	# дальше UTC+1 вчерашний локальный день не совпадал с сегодняшним, и стрик
	# обнулялся при двух подряд дейликах.
	var d := Time.get_date_dict_from_system(false)
	return _prev_day(int(d["year"]), int(d["month"]), int(d["day"]))


static func _prev_day(year: int, month: int, day: int) -> String:
	var y := year
	var m := month
	var dd := day - 1
	if dd == 0:
		m -= 1
		if m == 0:
			m = 12
			y -= 1
		dd = _days_in_month(y, m)
	return "%04d-%02d-%02d" % [y, m, dd]


static func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
				return 29
			return 28
		4, 6, 9, 11:
			return 30
	return 31


func build(game: Game) -> void:
	g = game
	_dim = ColorRect.new()
	_dim.name = "DailyDim"
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.z_index = 30
	_dim.visible = false
	g.add_child(_dim)
	_popup = CenterContainer.new()
	_popup.name = "DailyPopup"
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.z_index = 31
	_popup.visible = false
	g.add_child(_popup)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.modal_panel(UIStyle.GOLD))
	_popup.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(440, 0)
	card.add_child(col)
	var t := g._label("ДАРЫ ЦИКЛА", 19)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", UIStyle.GOLD)
	col.add_child(t)
	_head = g._label("", 13)
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	col.add_child(_head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for i in REWARDS.size():
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(100, 74)
		grid.add_child(cell)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		cell.add_child(vbox)
		var d := g._label("День %d" % (i + 1), 12)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(d)
		var r := g._label(_reward_text(i), 13)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(r)
		_cells.append(cell)
	_claim_btn = g._small_button("Забрать", Vector2(160, 44), 2)
	_claim_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_claim_btn.pressed.connect(_on_claim)
	col.add_child(_claim_btn)
	var close_btn := g._small_button("Закрыть", Vector2(120, 40))
	close_btn.name = "DailyClose"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func() -> void: close())
	col.add_child(close_btn)


func _reward_text(i: int) -> String:
	var rw: Array = REWARDS[i]
	var parts: Array = []
	if int(rw[0]) > 0:
		parts.append("⚡%d" % int(rw[0]))
	if int(rw[1]) > 0:
		parts.append("×2 добыча")
	if int(rw[2]) > 0:
		parts.append("💛%d" % int(rw[2]))
	return " ".join(parts)


func is_open() -> bool:
	return _popup != null and _popup.visible


func open() -> void:
	_refresh()
	_dim.visible = true
	_popup.visible = true
	Sfx.click()


func close() -> void:
	_dim.visible = false
	_popup.visible = false
	Sfx.click()


func _refresh() -> void:
	var today := _today()
	var claimed_today := claim_day == today
	var day_idx := (streak - 1) % 7 if streak > 0 else 0
	_head.text = "Серия: %d дн. · возвращайся каждый день, чтобы не сбросить" % streak
	for i in _cells.size():
		var cell: PanelContainer = _cells[i]
		var sb: StyleBoxFlat
		if claimed_today and i == day_idx:
			sb = UIStyle.box(Color(0.10, 0.22, 0.20, 0.95), UIStyle.TEAL, 12, 2)
		elif not claimed_today and i == ((streak) % 7 if claim_day == _yesterday() else 0):
			sb = UIStyle.box(Color(0.20, 0.16, 0.08, 0.95), UIStyle.GOLD, 12, 2)
		else:
			sb = UIStyle.box(Color(0.06, 0.10, 0.15, 0.9), UIStyle.LINE, 12, 1)
		cell.add_theme_stylebox_override("panel", sb)
		if int((REWARDS[i] as Array)[2]) > 0 and not g._spirit._companion_unlocked:
			cell.tooltip_text = "Светик ещё спит: дружба накопится и применится после пробуждения"
		else:
			cell.tooltip_text = ""
	_claim_btn.disabled = claimed_today
	_claim_btn.text = "Забрано ✓" if claimed_today else "Забрать"


func _on_claim() -> void:
	var today := _today()
	if claim_day == today:
		return
	streak = streak + 1 if claim_day == _yesterday() else 1
	claim_day = today
	var rw: Array = REWARDS[(streak - 1) % REWARDS.size()]
	if int(rw[0]) > 0:
		g._engine._grant_ether(int(rw[0]), "daily_grid")
	if int(rw[1]) > 0:
		g._engine._source_boost_until = maxf(g._engine._source_boost_until,
				Time.get_unix_time_from_system()) + float(rw[1])
	if int(rw[2]) > 0:
		g._spirit._companion_gain(int(rw[2]))
	g._saves._save_game()
	g._engine._refresh_header()
	_refresh()
	Sfx.achievement()
