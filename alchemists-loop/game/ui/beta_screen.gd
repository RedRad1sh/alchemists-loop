extends CanvasLayer

var _screen: Control
var _status: Label
var _code: LineEdit
var _submit: Button
var _badge: Button

func _ready() -> void:
	layer = 80
	_badge = Button.new()
	_badge.text = "БЕТА · доступ по приглашению"
	_badge.position = Vector2(12, 46)
	_badge.pressed.connect(open)
	add_child(_badge)
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var backdrop := TextureRect.new()
	backdrop.texture = load("res://assets/ui/theme/backdrop_room.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.05, 0.03, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(center)
	var panel := PanelContainer.new()
	var wood := StyleBoxTexture.new()
	wood.texture = load("res://assets/ui/theme/frame_panel.png")
	wood.set_texture_margin_all(24)
	wood.content_margin_left = 24
	wood.content_margin_right = 24
	wood.content_margin_top = 28
	wood.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", wood)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 340
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var title := Label.new()
	title.text = "ЗАКРЫТАЯ БЕТА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("e9c98a"))
	col.add_child(title)
	var intro := Label.new()
	intro.text = "Лаборатория для друзей\nВведи приглашение от владельца сервера."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(intro)
	_code = LineEdit.new()
	_code.placeholder_text = "Инвайт-код"
	_code.max_length = 128
	_code.custom_minimum_size.y = 48
	_code.text = BetaAccess.pending_code
	_code.text_submitted.connect(func(_text: String): _activate())
	col.add_child(_code)
	_submit = Button.new()
	_submit.text = "Войти по приглашению"
	_submit.custom_minimum_size.y = 48
	_submit.pressed.connect(_activate)
	col.add_child(_submit)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(340, 60)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var note := Label.new()
	note.text = "Тестовые покупки — без списаний.\nПрогресс беты хранится отдельно от релиза."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 13)
	col.add_child(note)
	var close := Button.new()
	close.text = "Продолжить локально"
	close.custom_minimum_size.y = 44
	close.pressed.connect(func(): _screen.hide())
	col.add_child(close)
	BetaAccess.status_changed.connect(_refresh)
	BetaAccess.access_changed.connect(_on_access_changed)
	_refresh()
	_screen.visible = not BetaAccess.can_send_gameplay()

func open() -> void:
	_screen.show()
	_code.grab_focus()
	_refresh()

func _activate() -> void:
	BetaAccess.activate(_code.text)
	_refresh()

func _on_access_changed() -> void:
	if BetaAccess.can_send_gameplay():
		_code.clear()
		_screen.hide()
	_refresh()

func _refresh() -> void:
	_status.text = BetaAccess.status
	_submit.disabled = BetaAccess.activating
	_badge.text = "БЕТА · доступ сохранён" if BetaAccess.can_send_gameplay() else "БЕТА · войти по инвайту"
	_badge.tooltip_text = BetaAccess.status
