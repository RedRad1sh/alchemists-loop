extends RefCounted
class_name TradeUI
# S2 «Обмен картами»: подслой обмена внутри экрана «Друзья». Три состояния —
# список (этот таск), конструктор и подтверждение (Task 9), действия по офферам
# и их последствия (Task 10). Сеть — только через Net-сигналы, которые
# маршрутизирует main.gd; представление не считает недельный лимит само и не
# заводит свою коллекцию карт (спека §8.4).

const TITLE := "Обмен"

var g: Game
var _screen: Control = null
var _body: VBoxContainer = null
var _header: Label = null
var _incoming: VBoxContainer = null
var _outgoing: VBoxContainer = null
var _history: VBoxContainer = null
var _peer := ""
var _mode := 0
var _list := {}

func _init(game: Game) -> void:
	g = game

func is_open() -> bool:
	return _screen != null and _screen.visible

func open(peer: String) -> void:
	if _screen == null:
		build()
	_peer = peer
	_mode = 0
	_screen.visible = true
	Net.trade_list(g._online._device_id)
	_render()

func close() -> void:
	var was := is_open()
	_peer = ""
	if _screen != null:
		_screen.visible = false
	# Звук — только на закрытие видимого слоя: SocialUI дёргает _trade_close() и
	# при open(), и при close(), поэтому без гейда каждый вход в «Друзья» после
	# первого обмена давал бы фантомный клик при уже погашенном слое.
	if was:
		Sfx.click()

func on_list(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	_list = result
	_render()

func build() -> void:
	if _screen != null:
		return
	var root := Control.new()
	root.name = "TradeScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	# z = 21 и группа modal_ui — ровно как у `_confirm` в `_open_confirm`
	# (спека §8.2): слой перекрывает SocialUI (z = 20) и попадает в общий
	# предикат модалок.
	root.z_index = 21
	root.add_to_group("modal_ui")
	g._social_ui._screen.add_child(root)
	_screen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_header = g._label(TITLE, 17)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_header)
	var back := g._small_button("Назад", Vector2(84, 34), 0)
	back.pressed.connect(close)
	head.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

func _section(title: String) -> VBoxContainer:
	var t := g._label(title, 13)
	t.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_body.add_child(t)
	var body := VBoxContainer.new()
	body.name = title
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(body)
	return body

func _clear(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _render() -> void:
	if _screen == null or _body == null:
		return
	match _mode:
		_:
			_render_list()

func _render_list() -> void:
	_clear(_body)
	var nick := "Алхимик"
	var friend := g._social.friend_by_device(_peer)
	if not friend.is_empty():
		nick = String(friend.get("nick", "Алхимик"))
	# Заголовок: к кому обращён обмен. Остаток лимита накрутится в Task 10 —
	# до этого серверные числа в этот слой ещё не приходили.
	_header.text = "%s · %s" % [TITLE, nick]
	_incoming = _section("Мне предлагают")
	_outgoing = _section("Я предложил")
	_history = _section("История")
	for box in [_incoming, _outgoing, _history]:
		var wait := g._label("—", 12)
		wait.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		box.add_child(wait)
