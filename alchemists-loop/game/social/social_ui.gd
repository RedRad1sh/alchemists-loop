extends RefCounted
class_name SocialUI
# Фулскрин-экран «Друзья»: список, заявки, поиск и личная лента.
# Сеть остаётся в Net/Social; этот класс отвечает только за представление,
# переходы между уровнями и безопасные действия поверх кэша.

const SPIRIT_INPUT_HINT := "Светик писем не читает — он же дух"

var g: Game
var _screen: Control = null
var _body: VBoxContainer = null
var _list_scroll: ScrollContainer = null
var _thread_scroll: ScrollContainer = null
var _thread_col: VBoxContainer = null
var _saved_scroll := 0
var _tab := 0
var _peer := ""
var _confirm: Control = null
var _err_line: Label = null
var _search_card: Control = null
var _pending_search_nick := ""

func _init(game: Game) -> void:
	g = game

func build() -> void:
	if _screen != null:
		return
	var root := Control.new()
	root.name = "SocialScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 20
	root.add_to_group("modal_ui")
	g.add_child(root)
	_screen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _confirm != null and _confirm.visible:
				_confirm_close()
			elif _peer != "":
				_close_thread()
			else:
				close()
	)
	root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var panel := PanelContainer.new()
	panel.name = "SocialPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", g._panel_style(Color(0.055, 0.065, 0.10, 0.99), 18))
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(UIWidgets.section(g, "ДРУЗЬЯ"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close_b := g._small_button("Закрыть", Vector2(116, 40), 1)
	close_b.pressed.connect(close)
	head.add_child(close_b)

	_body = VBoxContainer.new()
	_body.name = "SocialBody"
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)
	_err_line = g._label("", 13)
	_err_line.name = "SocialError"
	_err_line.add_theme_color_override("font_color", Color("#e6a84a"))
	box.add_child(_err_line)

	# Поиск карточки получает ответ из уже существующего house endpoint.
	Net.house_result.connect(_on_house_result)

func open(tab: int = 0) -> void:
	if _screen == null:
		build()
	_tab = clampi(tab, 0, 1)
	_peer = ""
	_confirm_close()
	_screen.visible = true
	_refresh_list()
	if g._social != null:
		g._social.refresh()

func close() -> void:
	_confirm_close()
	_peer = ""
	if _screen != null:
		_screen.visible = false
	Sfx.click()

func visible_thread() -> String:
	return _peer

func show_send_error(code: String) -> void:
	if _err_line != null:
		_err_line.text = _detail_text(code)

static func _detail_text(code: String) -> String:
	match code:
		"target_not_found": return "Такого алхимика нет."
		"bot": return "Это ученик гильдии, заявки он не принимает."
		"self": return "Нельзя отправить заявку самому себе."
		"blocked": return "Между вами стена."
		"already_friends": return "Вы уже друзья."
		"friend_limit": return "Больше 50 друзей не взять."
		"pending_limit": return "Слишком много неотвеченных заявок."
		"daily_limit": return "Письма на сегодня кончились."
		"too_long": return "Слишком длинное письмо."
		"empty": return "Пустое письмо."
		"not_friends": return "Вы больше не друзья."
		"npc": return SPIRIT_INPUT_HINT + "."
		"bad_device_id": return "Странное имя устройства."
		"request_not_found": return "Этой заявки уже нет."
		"race_lost": return "Заявка не прошла, попробуй ещё раз."
		"not_registered": return "Профиль ещё не зарегистрирован."
		"missing_peer": return "Не выбран собеседник."
		"offline": return "Мир не на связи"
		"": return ""
	return "Сервер не понял запрос."

func _refresh_list() -> void:
	if _body == null:
		return
	# F1: нажатая кнопка/строка зовёт перестройку из-под собственного сигнала —
	# мгновенный free() убивает эмиттера посреди emission («freed while emitting»,
	# рантайм валится). Снимаем с родителя сразу (имя свободно для нового узла в
	# том же кадре), объект доживает до конца кадра.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_search_card = null
	var seg := HBoxContainer.new()
	seg.name = "SocialSegments"
	_body.add_child(seg)
	var titles := ["Друзья (%d)" % g._social.friends().size(),
		"Заявки (%d)" % g._social.requests_total()]
	for i in 2:
		var b := g._small_button(titles[i], Vector2(140, 34), 2 if i == _tab else 0)
		b.pressed.connect(func() -> void:
			_tab = i
			_refresh_list()
		)
		seg.add_child(b)
	_search_row()
	var scroll := ScrollContainer.new()
	scroll.name = "SocialListScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)
	_list_scroll = scroll
	var col := VBoxContainer.new()
	col.name = "SocialRows"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	_err_line.text = ""
	if _tab == 0:
		if g._social.friends().is_empty():
			col.add_child(UIWidgets.empty(g, "Пока никого. Найди по нику или добавь того, кто заходил в твой дом."))
		for f in g._social.friends():
			if f is Dictionary:
				col.add_child(_friend_row(f))
	else:
		if g._social.incoming().is_empty():
			col.add_child(UIWidgets.empty(g, "Новых заявок нет."))
		for request in g._social.incoming():
			if request is Dictionary:
				col.add_child(_request_row(request))

func _search_row() -> void:
	var row := HBoxContainer.new()
	row.name = "SocialSearch"
	var edit := LineEdit.new()
	edit.name = "NickInput"
	edit.placeholder_text = "Ник игрока"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var find_b := g._small_button("Найти", Vector2(96, 34), 1)
	find_b.pressed.connect(func() -> void:
		var nick := edit.text.strip_edges()
		if nick != "":
			_search(nick)
	)
	edit.text_submitted.connect(func(nick: String) -> void:
		if nick.strip_edges() != "":
			_search(nick.strip_edges())
	)
	row.add_child(find_b)
	_body.add_child(row)

func _search(nick: String) -> void:
	_pending_search_nick = nick
	if g._online.social_rating_cache_has(nick):
		_show_card(g._online.social_rating_row_by_nick(nick))
		return
	_err_line.text = "Ищем алхимика…"
	Net.house_get(nick)

func _on_house_result(result: Dictionary) -> void:
	if _screen == null or not _screen.visible or _pending_search_nick == "":
		return
	var nick := String(result.get("nick", _pending_search_nick))
	if nick != _pending_search_nick:
		return
	_pending_search_nick = ""
	if result.get("ok", false) != true and not result.has("found"):
		_err_line.text = _detail_text(String(result.get("detail", "")))
		return
	_show_card(result)

func _show_card(data: Dictionary) -> void:
	if _search_card != null and is_instance_valid(_search_card):
		_search_card.queue_free()
	_search_card = _search_card_for(data)
	# Карточка вставляется сразу после строки поиска, над длинным списком.
	var idx := 0
	for child in _body.get_children():
		if child.name == "SocialSearch":
			idx = child.get_index() + 1
			break
	_body.add_child(_search_card)
	_body.move_child(_search_card, idx)

func _search_card_for(data: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "SearchCard"
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.08, 0.14, 0.19, 0.96), 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var nick := String(data.get("nick", _pending_search_nick))
	var avatar := Avatar.new()
	avatar.custom_minimum_size = Vector2(40, 40)
	avatar.setup_spec(data.get("avatar", {}) if data.get("avatar", {}) is Dictionary else {}, 40)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(avatar)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(g._label(nick, 15))
	var seen := Social.last_seen_text(String(data.get("last_seen", "")), Time.get_date_string_from_system())
	if seen != "":
		var seen_l := g._label(seen, 12)
		seen_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		info.add_child(seen_l)
	row.add_child(info)
	attach(g, row, nick)
	return card

static func _friend_state_text(nick: String, s: Social) -> String:
	if not s.friend_by_nick(nick).is_empty():
		return "в друзьях"
	if s.is_outgoing_to(nick):
		return "заявка отправлена"
	return "в друзья"

static func attach(game: Game, row: HBoxContainer, nick: String) -> Button:
	var text := _friend_state_text(nick, game._social)
	var b := game._small_button(text, Vector2(110, 30), 1 if text == "в друзья" else 0)
	b.disabled = text != "в друзья"
	if text == "в друзья":
		b.pressed.connect(func() -> void:
			Net.friend_request(game._online._device_id, nick)
		)
	row.add_child(b)
	return b

func _friend_row(friend: Dictionary) -> Control:
	var dev := String(friend.get("device_id", ""))
	var row := HBoxContainer.new()
	row.name = "FriendRow_%s" % dev
	row.custom_minimum_size = Vector2(0, 50)
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_thread(dev)
	)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(40, 40)
	var spec = friend.get("avatar", {})
	av.setup_spec(spec if spec is Dictionary else {}, 40)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(av)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nick := String(friend.get("nick", "Алхимик"))
	info.add_child(g._label(nick, 14))
	var seen := Social.last_seen_text(String(friend.get("last_seen", "")), Time.get_date_string_from_system())
	if seen != "":
		var seen_l := g._label(seen, 11)
		seen_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		info.add_child(seen_l)
	row.add_child(info)
	var preview := g._label(Social.preview_cut(String(friend.get("last_msg_preview", "")), 60), 11)
	preview.autowrap_mode = TextServer.AUTOWRAP_OFF
	preview.size_flags_horizontal = Control.SIZE_SHRINK_END
	preview.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	row.add_child(preview)
	var unread := int(friend.get("unread", 0))
	if unread > 0:
		var badge := g._label("•" + str(unread), 12)
		badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		badge.add_theme_color_override("font_color", UIStyle.GOLD)
		row.add_child(badge)
	if dev != Social.SPIRIT_DEVICE:
		var more := g._small_button("⋮", Vector2(34, 34), 0)
		more.tooltip_text = "Удалить или заблокировать"
		more.pressed.connect(_open_confirm.bind(dev))
		row.add_child(more)
	return row

func _request_row(request: Dictionary) -> Control:
	var dev := String(request.get("device_id", ""))
	var row := HBoxContainer.new()
	row.name = "RequestRow_%s" % dev
	row.custom_minimum_size = Vector2(0, 50)
	row.add_theme_constant_override("separation", 8)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(40, 40)
	var spec = request.get("avatar", {})
	av.setup_spec(spec if spec is Dictionary else {}, 40)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(av)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(g._label(String(request.get("nick", "Алхимик")), 14))
	var seen := Social.last_seen_text(String(request.get("last_seen", "")), Time.get_date_string_from_system())
	if seen != "":
		var seen_l := g._label(seen, 11)
		seen_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		info.add_child(seen_l)
	row.add_child(info)
	var accept := g._small_button("Принять", Vector2(86, 34), 1)
	accept.pressed.connect(func() -> void:
		Net.friend_respond(g._online._device_id, dev, true)
	)
	row.add_child(accept)
	var reject := g._small_button("Отклонить", Vector2(96, 34), 0)
	reject.pressed.connect(func() -> void:
		Net.friend_respond(g._online._device_id, dev, false)
	)
	row.add_child(reject)
	return row

func _open_thread(peer: String) -> void:
	if _list_scroll != null:
		_saved_scroll = _list_scroll.scroll_vertical
	_peer = peer
	if g._social != null:
		g._social.load_thread(peer)
	_build_thread()

func _build_thread() -> void:
	# F1: тот же приём, что в _refresh_list — строка списка может открыть ленту
	# из своего gui_input, освобождать её мгновенно нельзя.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var head := HBoxContainer.new()
	head.name = "ThreadHeader"
	var back := g._small_button("Назад", Vector2(96, 34), 1)
	back.pressed.connect(_close_thread)
	head.add_child(back)
	var friend := g._social.friend_by_device(_peer)
	var nick := Social.SPIRIT_NICK if _peer == Social.SPIRIT_DEVICE else String(friend.get("nick", "Алхимик"))
	var title := g._label(nick, 16)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	_body.add_child(head)
	_thread_scroll = ScrollContainer.new()
	_thread_scroll.name = "ThreadScroll"
	_thread_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_thread_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_thread_scroll)
	_thread_col = VBoxContainer.new()
	_thread_col.name = "ThreadBubbles"
	_thread_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thread_col.add_theme_constant_override("separation", 5)
	_thread_scroll.add_child(_thread_col)
	_rebuild_bubbles()
	if _peer == Social.SPIRIT_DEVICE:
		var spirit_note := g._label(SPIRIT_INPUT_HINT, 13)
		spirit_note.name = "SpiritNoInput"
		spirit_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spirit_note.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		_body.add_child(spirit_note)
	else:
		if not Net.is_available():
			_body.add_child(UIWidgets.banner(g, "Мир не на связи", Color("#e6a84a")))
		var input_row := HBoxContainer.new()
		input_row.name = "ThreadInput"
		var edit := LineEdit.new()
		edit.name = "MessageInput"
		edit.placeholder_text = "Написать сообщение"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var send := g._small_button("Отправить", Vector2(104, 34), 1)
		if not Net.is_available():
			edit.editable = false
			send.disabled = true
		var submit := func() -> void:
			var body := edit.text.strip_edges()
			if body == "":
				return
			g._social.send_message(_peer, body)
			edit.text = ""
			refresh_thread()
		send.pressed.connect(submit)
		edit.text_submitted.connect(func(_text: String) -> void: submit.call())
		input_row.add_child(edit)
		input_row.add_child(send)
		_body.add_child(input_row)

func _rebuild_bubbles() -> void:
	if _thread_col == null:
		return
	# F1: пересборка пузырей идёт из signal-колбэков (on_messages/on_send),
	# мгновенный free() недопустим — см. _refresh_list.
	for child in _thread_col.get_children():
		_thread_col.remove_child(child)
		child.queue_free()
	var previous_day := ""
	var index := 0
	for message in g._social.thread(_peer):
		if not message is Dictionary:
			continue
		var sent_at := String(message.get("sent_at", ""))
		var day := sent_at.substr(0, 10) if sent_at.length() >= 10 else ""
		if day != "" and day != previous_day:
			var date_l := g._label(_ru_date(day), 11)
			date_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			date_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
			_thread_col.add_child(date_l)
			previous_day = day
		var bubble := PanelContainer.new()
		bubble.name = "Bubble_%d" % index
		bubble.custom_minimum_size = Vector2(180, 0)
		bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if bool(message.get("from_me", false)) else Control.SIZE_SHRINK_BEGIN
		var accent := UIStyle.TEAL if bool(message.get("from_me", false)) else UIStyle.LINE
		bubble.add_theme_stylebox_override("panel", g._panel_style(Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.96), 12))
		var label := g._label(String(message.get("body", "")), 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(180, 28)
		bubble.add_child(label)
		_thread_col.add_child(bubble)
		index += 1

static func _ru_date(iso_day: String) -> String:
	if iso_day.length() < 10:
		return iso_day
	var parts := iso_day.split("-")
	if parts.size() < 3:
		return iso_day
	var month := int(parts[1])
	var names := ["", "января", "февраля", "марта", "апреля", "мая", "июня",
		"июля", "августа", "сентября", "октября", "ноября", "декабря"]
	return "%s %s" % [parts[2], names[month] if month > 0 and month < names.size() else parts[1]]

func refresh_thread() -> void:
	if _peer != "":
		_rebuild_bubbles()

func _close_thread() -> void:
	_peer = ""
	_confirm_close()
	_refresh_list()
	if _list_scroll != null:
		_list_scroll.scroll_vertical = _saved_scroll

func _open_confirm(peer: String) -> void:
	var friend := g._social.friend_by_device(peer)
	var nick := String(friend.get("nick", "Алхимик"))
	if _confirm == null:
		_confirm = Control.new()
		_confirm.name = "SocialConfirm"
		_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
		_confirm.z_index = 21
		_confirm.add_to_group("modal_ui")
		_screen.add_child(_confirm)
	# F5: одно удаление вместо дубля (ConfirmDim снимался дважды); снятие с
	# родителя сразу освобождает имена для новых узлов в том же кадре.
	for child in _confirm.get_children():
		_confirm.remove_child(child)
		child.queue_free()
	var dim := ColorRect.new()
	dim.name = "ConfirmDim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", g._panel_style(Color(0.10, 0.08, 0.13, 1.0), 16))
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := g._label("Действие с другом", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body := g._label("Переписка с %s будет удалена у вас обоих." % nick, 14)
	body.name = "ConfirmBody"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)
	var remove := g._small_button("Удалить из друзей", Vector2(0, 40), 0)
	remove.pressed.connect(func() -> void:
		Net.friend_remove(g._online._device_id, peer)
		_confirm_close()
	)
	col.add_child(remove)
	var block := g._small_button("Заблокировать", Vector2(0, 40), 0)
	block.pressed.connect(func() -> void:
		Net.friend_block(g._online._device_id, peer)
		_confirm_close()
	)
	col.add_child(block)
	var cancel := g._small_button("Отмена", Vector2(0, 38), 1)
	cancel.pressed.connect(_confirm_close)
	col.add_child(cancel)
	_confirm.visible = true

func _confirm_close() -> void:
	if _confirm != null:
		_confirm.visible = false

func _on_friend_action_result(result: Dictionary) -> void:
	if result.get("ok", false) == true:
		g._social.refresh()
		g._engine._refresh_header()
		if _screen != null and _screen.visible and _peer == "":
			_refresh_list()
	else:
		show_send_error(_refusal_code(result))

static func _refusal_code(result: Dictionary) -> String:
	# T8 Step 0 (ruling контролёра), единый разбор отказа для err-line-поверхностей
	# (respond в main.gd, remove/block здесь). detail не типизирован: 422-список
	# → «unmapped»; сквозной HTTP 422 под гейтом T28 (net.gd:501-502, не трогаем)
	# приходит БЕЗ ключа detail, только error:"HTTP 422" — тоже «unmapped», иначе
	# отказ молча теряется (нарушение глобального ограничения «422 показывать
	# „Сервер не понял запрос“»). Офлайн (detail отсутствует, 422 в error нет)
	# остаётся пустой строкой, как раньше. Мутации: снять строку с contains("422")
	# — краснеют 422-кейсы _refusal_422; убрать пустое условие → краснеют
	# offline-пины того же блока.
	var detail = result.get("detail", "")
	var code: String = detail if detail is String else "unmapped"
	if code == "" and String(result.get("error", "")).contains("422"):
		code = "unmapped"
	return code
