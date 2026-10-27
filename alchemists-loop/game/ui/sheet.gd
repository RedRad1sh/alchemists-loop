extends RefCounted
class_name BottomSheet
# Bottom-sheet (перенос из PR #65): устройство открывается компактным листом
# поверх сцены, а не перескоком на вкладку «Инструменты». Контент — существующий
# бокс из _mode_pages: на открытии он переезжает в лист (reparent), на закрытии
# возвращается, поэтому refresh-логика и контракты тестов не трогаются.
# z-порядок ниже модалок (dim 20 / popup 21), чтобы попап перекрывал лист.

const DIM_Z := 18
const PANEL_Z := 19
const SHEET_H := 600

var g: Game
var _dim: ColorRect = null
var _panel: PanelContainer = null
var _title: Label = null
var _host_box: VBoxContainer = null
var _cur_box: Control = null
var _orig_parent: Control = null


func build(game: Game) -> void:
	g = game
	_dim = ColorRect.new()
	_dim.name = "SheetDim"
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.z_index = DIM_Z
	_dim.visible = false
	_dim.gui_input.connect(_on_dim_input)
	g.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.name = "Sheet"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -SHEET_H
	_panel.offset_bottom = 0
	_panel.z_index = PANEL_Z
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UIStyle.modal_panel())
	g.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_title = g._label("", 17)
	_title.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := g._small_button("Закрыть", Vector2(110, 40))
	close_btn.name = "SheetClose"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 10)
	scroll.add_child(margin)
	_host_box = VBoxContainer.new()
	_host_box.add_theme_constant_override("separation", 8)
	_host_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_host_box)


func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		close()


func is_open() -> bool:
	return _panel != null and _panel.visible


func open(key: String, title: String) -> void:
	if _panel == null or not g._pages._mode_pages.has(key):
		return
	close()
	var box: Control = g._pages._mode_pages[key]
	if box == null:
		return
	_cur_box = box
	_orig_parent = box.get_parent() as Control
	# add_child не переносит узел с родителем — только reparent.
	box.reparent(_host_box)
	box.visible = true
	_title.text = title
	_dim.visible = true
	_panel.visible = true
	_panel.offset_top = -420
	var tw := g.create_tween()
	tw.tween_property(_panel, "offset_top", -SHEET_H, 0.16)
	Sfx.click()


func close() -> void:
	if _cur_box != null and is_instance_valid(_orig_parent):
		_cur_box.reparent(_orig_parent)
		# возвращаем видимость под управление выбором раздела инструментов
		g._pages._apply_tools_selection()
	_cur_box = null
	_orig_parent = null
	if _dim != null:
		_dim.visible = false
	if _panel != null:
		_panel.visible = false
