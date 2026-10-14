extends Control
class_name SpringScreen

var _game: Node
var _axis_rows := {}

func _build(game: Node) -> void:
	_game = game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 0
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.12, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var header := HBoxContainer.new()
	header.offset_top = 16
	header.offset_left = 16
	header.offset_right = -16
	add_child(header)
	var back_btn := Button.new()
	back_btn.text = "← Назад"
	back_btn.pressed.connect(_close)
	header.add_child(back_btn)
	var title := Label.new()
	title.text = "РОДНИК"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var vbox := VBoxContainer.new()
	vbox.offset_top = 64
	vbox.offset_bottom = -110
	vbox.offset_left = 16
	vbox.offset_right = -16
	add_child(vbox)
	_build_axis_row(vbox, "speed", "Скорость")
	_build_axis_row(vbox, "volume", "Объём")
	_build_axis_row(vbox, "sources", "Источники")
	_build_axis_row(vbox, "offline", "Офлайн")
	var toggle_btn := Button.new()
	toggle_btn.text = "Пустить родник"
	toggle_btn.pressed.connect(_toggle_spring)
	vbox.add_child(toggle_btn)

func _build_axis_row(parent: VBoxContainer, axis: String, label: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)
	var lvl: int = _game._engine.spring_levels.get(axis, 0)
	var dots := ""
	for i in 7:
		dots += "●" if i < lvl else "○"
	var dots_label := Label.new()
	dots_label.text = dots
	row.add_child(dots_label)
	var upgrade_btn := Button.new()
	upgrade_btn.text = "Улучшить"
	upgrade_btn.pressed.connect(_purchase.bind(axis))
	row.add_child(upgrade_btn)
	_axis_rows[axis] = row

func _purchase(axis: String) -> void:
	var result: Dictionary = _game._engine.spring_purchase(axis)
	if result["ok"]:
		_refresh()
	else:
		_game._engine.status_text = result["error"]

func _toggle_spring() -> void:
	_game._engine.spring_on = not _game._engine.spring_on
	_refresh()

func _refresh() -> void:
	pass

func _count_axis_rows(axis: String) -> int:
	match axis:
		"speed": return SpringBalance.SPEED.size()
		"volume": return SpringBalance.VOLUME.size()
		"sources": return SpringBalance.SOURCES.size()
		"offline": return SpringBalance.OFFLINE.size()
	return 0

func _close() -> void:
	queue_free()
