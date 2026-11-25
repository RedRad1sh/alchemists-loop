extends RefCounted
class_name SocialUI
# Фулскрин-экран «Друзья»: список, заявки, поиск и личная лента.
# Сеть остаётся в Net/Social; этот класс отвечает только за представление,
# переходы между уровнями и безопасные действия поверх кэша.

const Kit = preload("res://game/ui/menu_kit.gd")
const ModalStyle = preload("res://game/ui/friends_v2_styleboxes.gd")
const SPIRIT_INPUT_HINT := "Светик писем не читает — он же дух"
const STICKER_DIR := "res://assets/spirits/stickers_512/"
# Ходовые эмодзи для чата (docs/social-emoji-and-stickers.md §1, без
# специальных алхимических значков — они не рендерятся системным шрифтом).
const EMOJI_SET: Array[String] = [
	"⚡", "✨", "💛", "🔥", "💧", "💨", "🌿", "💎",
	"🌸", "🍄", "🏠", "⚗️", "🫧", "🌫️", "📜", "🌠",
	"🏅", "🌍", "🔮", "🕯️", "🏆", "👑", "🎁", "💡",
	"✉️", "⏳", "💤", "✅", "❌", "😊", "😂", "🤔",
]

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
var _trade: TradeUI = null
var _err_line: Label = null
var _search_card: Control = null
var _pending_search_nick := ""
var _picker: Control = null
var _picker_tab := 0

func _init(game: Game) -> void:
	g = game

func build() -> void:
	if _screen != null:
		return
	var root := Control.new()
	root.name = "SocialScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 16
	root.add_to_group("modal_ui")
	g.add_child(root)
	_screen = root

	# Раздел нижнего меню, как Мир и Рейтинг: тот же rect и та же рамка, что у
	# остальных вкладок. Rect выводим из видимой раскладки Root VBox (шапка +
	# зазор): скрытый TabContainer при ресайзе не пересчитывается, его rect брать
	# нельзя.
	var tabs_root := g._tabs_ref.get_parent() as VBoxContainer
	tabs_root.resized.connect(_sync_rect)
	_sync_rect()

	# Рамка на весь rect раздела (как панель TabContainer у остальных вкладок),
	# поля страницы — внутри неё, один в один как _make_page.
	var panel := PanelContainer.new()
	panel.name = "SocialPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UIStyle.tab_panel())
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "SocialMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 2)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", int(UIStyle.PAGE_TOP_M))
	margin.add_theme_constant_override("margin_bottom", 0)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	# Заголовок в стиле секций «Настроек»; закрытие — только нижним баром,
	# крестик здесь дублировал навигацию.
	box.add_child(UIWidgets.section(g, "ДРУЗЬЯ"))

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

func _sync_rect() -> void:
	if _screen == null:
		return
	var tabs_root := g._tabs_ref.get_parent() as VBoxContainer
	var hud: Control = g._hud.row
	# TabContainer рисует рамку вокруг области контента: скрытый tab bar всё равно
	# резервирует высоту сверху, поэтому рамка «Друзей» начинается на той же линии.
	var bar_h: float = g._tabs_ref.get_tab_bar().get_combined_minimum_size().y
	var top: float = hud.global_position.y + hud.size.y \
		+ float(tabs_root.get_theme_constant("separation")) + bar_h
	var bottom: float = tabs_root.global_position.y + tabs_root.size.y
	_screen.global_position = Vector2(tabs_root.global_position.x, top)
	_screen.size = Vector2(tabs_root.size.x, bottom - top)

func open(tab: int = 0) -> void:
	if _screen == null:
		build()
	_sync_rect()
	_tab = clampi(tab, 0, 1)
	_peer = ""
	_confirm_close()
	_trade_close()
	if g._screens != null:
		g._screens.close()
	g._tabs_ref.hide()
	if g._rooms != null:
		g._rooms.set_scene_visible(false)
	_screen.visible = true
	_refresh_list()
	if g._social != null:
		g._social.refresh()
	if g._bottom_nav != null:
		g._bottom_nav._repaint()

func close() -> void:
	_confirm_close()
	_trade_close()
	_peer = ""
	if _screen != null:
		_screen.visible = false
	g._tabs_ref.show()
	if g._rooms != null:
		g._rooms.set_scene_visible(g._tabs_ref.current_tab == Game.TAB_EXPERIMENT)
	if g._bottom_nav != null:
		g._bottom_nav._repaint()
	Sfx.click()

func is_open() -> bool:
	return _screen != null and _screen.visible

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
	_picker = null
	var seg := HBoxContainer.new()
	seg.name = "SocialSegments"
	_body.add_child(seg)
	var titles := ["Друзья (%d)" % g._social.friends().size(),
		"Заявки (%d)" % g._social.requests_total()]
	for i in 2:
		var b := g._small_button(titles[i], Vector2(0, 42))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		var style := ModalStyle.make_tab_active() if i == _tab else ModalStyle.make_tab_inactive()
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", Color("e5bc70") if i == _tab else Color("c6b294"))
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
	edit.custom_minimum_size.y = 42
	edit.add_theme_stylebox_override("normal", ModalStyle.make_search_input())
	edit.add_theme_stylebox_override("focus", ModalStyle.make_search_input())
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var find_b := g._small_button("Найти", Vector2(96, 42), 1)
	Kit.cta(find_b)
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
		_pending_search_nick = ""
		_err_line.text = ""
		_show_card(g._online.social_rating_row_by_nick(nick))
		return
	_err_line.text = "Ищем алхимика…"
	Net.house_get(nick)

func _on_house_result(result: Dictionary) -> void:
	if _screen == null or not _screen.visible:
		return
	var verdict := search_verdict(result, _pending_search_nick)
	if verdict == "ignore":
		return
	_pending_search_nick = ""
	match verdict:
		"error":
			_search_card_drop()
			_err_line.text = _detail_text(String(result.get("detail", "")))
		"not_found":
			_search_card_drop()
			_err_line.text = "Такого алхимика нет."
		"show":
			_err_line.text = ""
			_show_card(result)

func _search_card_drop() -> void:
	if _search_card != null and is_instance_valid(_search_card):
		_search_card.get_parent().remove_child(_search_card)
		_search_card.queue_free()
	_search_card = null

func _show_card(data: Dictionary) -> void:
	_search_card_drop()
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

static func search_verdict(result: Dictionary, pending: String) -> String:
	# Карточка строится только на тот ник, который реально искали: чужой/устаревший
	# ответ игнорируется, found=false — «нет такого алхимика», а не карточка.
	if pending == "":
		return "ignore"
	if String(result.get("nick", pending)) != pending:
		return "ignore"
	if result.get("ok", false) != true:
		return "error"
	if result.get("found", false) != true:
		return "not_found"
	return "show"

static func _friend_state_text(nick: String, s: Social) -> String:
	if not s.friend_by_nick(nick).is_empty():
		return "в друзьях"
	if s.is_outgoing_to(nick):
		return "заявка отправлена"
	return "в друзья"

static func attach(game: Game, row: HBoxContainer, nick: String) -> Button:
	var text := _friend_state_text(nick, game._social)
	# FIX-E (ширина подписи): «заявка отправлена» — 131 px тем же шрифтом
	# подписей кнопок (font_size 14, _font_semi; замер get_string_size в
	# selftest), при content_margin 12+12 в Vector2(110,30) не влезает
	# (доступно 86). Это состояние расширяем до 156 px (131+24=155, +1 на
	# округление); короткие «в друзьях»/«в друзья» держим на прежней ширине,
	# чтобы не распирать ряды рейтинга и карточку гостя.
	var min_w := 156.0 if text == "заявка отправлена" else 110.0
	var b := game._small_button(text, Vector2(min_w, 30), 1 if text == "в друзья" else 0)
	b.disabled = text != "в друзья"
	if text == "в друзья":
		b.pressed.connect(func() -> void:
			Net.friend_request(game._online._device_id, nick)
		)
	row.add_child(b)
	return b

func _friend_row(friend: Dictionary) -> Control:
	var dev := String(friend.get("device_id", ""))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	column.add_child(row)
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
	var spec = {"kind": "spirit"} if dev == Social.SPIRIT_DEVICE else friend.get("avatar", {})
	av.setup_spec(spec if spec is Dictionary else {}, 40)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(av)
	Kit.avatar_ring(av)
	# Имя, «был(а)» и превью — одна колонка с обрезкой многоточием: превью
	# отдельной колонкой без обрезки съедало ширину, и имя падало по букве.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	var nick := String(friend.get("nick", "Алхимик"))
	info.add_child(_one_line(g._label(nick, 15)))
	var seen := Social.last_seen_text(String(friend.get("last_seen", "")), Time.get_date_string_from_system())
	var sub := Social.preview_line(friend)
	if sub == "":
		sub = seen
	if sub != "":
		var sub_l := _one_line(g._label(sub, 12))
		sub_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		info.add_child(sub_l)
	row.add_child(info)
	var unread := int(friend.get("unread", 0))
	if unread > 0:
		var badge := UIStyle.count_badge()
		badge.text = "99+" if unread > 99 else str(unread)
		badge.visible = true
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -10.0
		badge.offset_right = 6.0
		badge.offset_top = -4.0
		badge.offset_bottom = 12.0
		av.add_child(badge)
	if dev != Social.SPIRIT_DEVICE:
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_END
		column.add_child(actions)
		var swap := g._small_button("Обменять", Vector2(96, 44), 0)
		swap.tooltip_text = "Предложить обмен или подарок"
		swap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swap.pressed.connect(_open_trade.bind(dev))
		actions.add_child(swap)
		var more := g._small_button("⋮", Vector2(44, 44), 0)
		more.tooltip_text = "Удалить или заблокировать"
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		more.pressed.connect(_open_confirm.bind(dev))
		actions.add_child(more)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ModalStyle.make_friend_row())
	panel.add_child(column)
	return panel


func _one_line(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.custom_minimum_size.x = 0
	return l

func _request_row(request: Dictionary) -> Control:
	var dev := String(request.get("device_id", ""))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.name = "RequestRow_%s" % dev
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(40, 40)
	var spec = request.get("avatar", {})
	av.setup_spec(spec if spec is Dictionary else {}, 40)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(av)
	Kit.avatar_ring(av)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_one_line(g._label(String(request.get("nick", "Алхимик")), 14)))
	var seen := Social.last_seen_text(String(request.get("last_seen", "")), Time.get_date_string_from_system())
	if seen != "":
		var seen_l := _one_line(g._label(seen, 11))
		seen_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		info.add_child(seen_l)
	row.add_child(info)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(actions)
	var accept := g._small_button("Принять", Vector2(86, 44), 1)
	accept.pressed.connect(func() -> void:
		Net.friend_respond(g._online._device_id, dev, true)
	)
	actions.add_child(accept)
	var reject := g._small_button("Отклонить", Vector2(96, 44), 0)
	reject.pressed.connect(func() -> void:
		Net.friend_respond(g._online._device_id, dev, false)
	)
	actions.add_child(reject)
	Kit.cta(accept)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ModalStyle.make_friend_row())
	panel.add_child(column)
	return panel

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
	_picker = null
	var head := HBoxContainer.new()
	head.name = "ThreadHeader"
	head.add_theme_constant_override("separation", 8)
	var back := g._small_button("", Vector2(44, 40), 0)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.tooltip_text = "Назад"
	UIIcon.into_button(back, "chevron_right", 20)
	var back_icon := back.find_child("Icon_chevron_right", true, false) as TextureRect
	if back_icon != null:
		# Шеврон в ките смотрит вправо — для «Назад» зеркалим.
		back_icon.flip_h = true
	Kit.press_feedback(back)
	back.pressed.connect(_close_thread)
	head.add_child(back)
	var friend := g._social.friend_by_device(_peer)
	var nick := Social.SPIRIT_NICK if _peer == Social.SPIRIT_DEVICE else String(friend.get("nick", "Алхимик"))
	# Плашка заголовка: плоская панель с тонкой латунной кромкой — рисованная
	# доска кита мылилась при растяжении (претензия приёмки 2026-11-12).
	var plaque := PanelContainer.new()
	plaque.name = "ThreadPlaque"
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.custom_minimum_size = Vector2(0, 60)
	var plaque_sb := StyleBoxFlat.new()
	plaque_sb.bg_color = Color(0.17, 0.13, 0.09, 0.95)
	plaque_sb.border_color = Color(0.85, 0.68, 0.40, 0.35)
	plaque_sb.set_border_width_all(1)
	plaque_sb.set_corner_radius_all(8)
	plaque_sb.content_margin_left = 12
	plaque_sb.content_margin_right = 12
	plaque_sb.content_margin_top = 8
	plaque_sb.content_margin_bottom = 8
	plaque.add_theme_stylebox_override("panel", plaque_sb)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	plaque.add_child(prow)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(36, 36)
	var spec = {"kind": "spirit"} if _peer == Social.SPIRIT_DEVICE else friend.get("avatar", {})
	av.setup_spec(spec if spec is Dictionary else {}, 36)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(av)
	Kit.avatar_ring(av)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tcol.add_theme_constant_override("separation", 0)
	var title := g._label(nick, 16)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(title)
	var seen := Social.last_seen_text(String(friend.get("last_seen", "")), Time.get_date_string_from_system())
	if seen != "":
		var seen_l := g._label(seen, 11)
		seen_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		tcol.add_child(seen_l)
	prow.add_child(tcol)
	head.add_child(plaque)
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
		input_row.add_theme_constant_override("separation", 6)
		var edit := LineEdit.new()
		edit.name = "MessageInput"
		edit.placeholder_text = "Написать сообщение"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pick := g._small_button("", Vector2(44, 40), 0)
		pick.name = "PickerBtn"
		pick.tooltip_text = "Эмодзи и стикеры"
		var pick_icon := TextureRect.new()
		pick_icon.texture = load(STICKER_DIR + "hi.png")
		pick_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pick_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pick_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		pick_icon.offset_left = -13
		pick_icon.offset_right = 13
		pick_icon.offset_top = -13
		pick_icon.offset_bottom = 13
		pick_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pick.add_child(pick_icon)
		Kit.press_feedback(pick)
		pick.pressed.connect(_toggle_picker.bind(edit))
		var send := g._small_button("Отправить", Vector2(104, 40), 1)
		Kit.cta(send)
		Kit.press_feedback(send)
		if not Net.is_available():
			edit.editable = false
			send.disabled = true
			pick.disabled = true
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
		input_row.add_child(pick)
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
		var from_me := bool(message.get("from_me", false))
		var body := String(message.get("body", ""))
		var sid := Social.sticker_id(body)
		var bubble := PanelContainer.new()
		bubble.name = "Bubble_%d" % index
		bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if from_me else Control.SIZE_SHRINK_BEGIN
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		bubble.add_child(inner)
		if sid != "":
			# Стикер — картинка без фона пузыря; статус/время тем же футером.
			bubble.custom_minimum_size = Vector2(140, 0)
			bubble.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			var img := TextureRect.new()
			img.name = "StickerImage"
			img.texture = load(STICKER_DIR + sid + ".png")
			img.custom_minimum_size = Vector2(140, 140)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(img)
		else:
			bubble.custom_minimum_size = Vector2(180, 0)
			var accent := UIStyle.TEAL if from_me else UIStyle.LINE
			bubble.add_theme_stylebox_override("panel", g._panel_style(Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.96), 12))
			var label := g._label(body, 15)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.custom_minimum_size = Vector2(180, 28)
			inner.add_child(label)
		var footer := g._label(_bubble_footer(message, from_me, sent_at), 10)
		footer.name = "BubbleFooter"
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if from_me else HORIZONTAL_ALIGNMENT_LEFT
		footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		inner.add_child(footer)
		_thread_col.add_child(bubble)
		index += 1

static func _bubble_footer(message: Dictionary, from_me: bool, sent_at: String) -> String:
	if not from_me:
		return Social.message_time(sent_at)
	if message.get("pending", false) == true:
		return "отправляется…"
	var t := Social.message_time(sent_at)
	return "отправлено" + (" · " + t if t != "" else "")

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

func _toggle_picker(edit: LineEdit) -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker_hide()
		return
	_picker_tab = 0
	var panel := PanelContainer.new()
	panel.name = "SocialPicker"
	panel.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.07, 0.05, 0.97), 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var seg := HBoxContainer.new()
	seg.name = "PickerSegments"
	seg.add_theme_constant_override("separation", 6)
	for i in 2:
		var b := g._small_button(["Эмодзи", "Стикеры"][i], Vector2(0, 36))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := ModalStyle.make_tab_active() if i == _picker_tab else ModalStyle.make_tab_inactive()
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", Color("e5bc70") if i == _picker_tab else Color("c6b294"))
		b.pressed.connect(_picker_segment.bind(i, edit))
		seg.add_child(b)
	box.add_child(seg)
	var content := VBoxContainer.new()
	content.name = "PickerContent"
	box.add_child(content)
	_picker = panel
	# Пикер встаёт прямо над строкой ввода, не перекрывая пузыри.
	var idx := 0
	for child in _body.get_children():
		if child.name == "ThreadInput":
			idx = child.get_index()
			break
	_body.add_child(panel)
	_body.move_child(panel, idx)
	_picker_fill(content, edit)

func _picker_hide() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.get_parent().remove_child(_picker)
		_picker.queue_free()
	_picker = null

func _picker_segment(i: int, edit: LineEdit) -> void:
	if _picker == null or not is_instance_valid(_picker):
		return
	_picker_tab = i
	var seg: HBoxContainer = _picker.find_child("PickerSegments", true, false)
	if seg != null:
		for j in seg.get_child_count():
			var b := seg.get_child(j) as Button
			if b == null:
				continue
			var style := ModalStyle.make_tab_active() if j == i else ModalStyle.make_tab_inactive()
			for state in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(state, style)
			b.add_theme_color_override("font_color", Color("e5bc70") if j == i else Color("c6b294"))
	var content: VBoxContainer = _picker.find_child("PickerContent", true, false)
	if content == null:
		return
	# F1: нажатая кнопка сегмента лежит в seg, не в content — перестройка
	# содержимого её не освобождает.
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_picker_fill(content, edit)

func _picker_fill(content: VBoxContainer, edit: LineEdit) -> void:
	if _picker_tab == 0:
		var grid := GridContainer.new()
		grid.name = "EmojiGrid"
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		for i in EMOJI_SET.size():
			var e := EMOJI_SET[i]
			var b := g._small_button(e, Vector2(40, 40), 0)
			b.name = "Emoji_%d" % i
			b.add_theme_font_size_override("font_size", 20)
			b.pressed.connect(func() -> void:
				if not is_instance_valid(edit):
					return
				var pos := edit.caret_column
				edit.text = edit.text.substr(0, pos) + e + edit.text.substr(pos)
				edit.caret_column = pos + e.length()
				edit.grab_focus()
			)
			grid.add_child(b)
		content.add_child(grid)
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "StickerScroll"
		scroll.custom_minimum_size = Vector2(0, 280)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(scroll)
		var grid := GridContainer.new()
		grid.name = "StickerGrid"
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		for id in Social.STICKER_IDS:
			var b := g._small_button("", Vector2(132, 132), 0)
			# _small_button клампит высоту в 38-42 — стикеру нужен свой размер.
			b.custom_minimum_size = Vector2(132, 132)
			b.name = "Sticker_%s" % id
			var img := TextureRect.new()
			img.texture = load(STICKER_DIR + id + ".png")
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			img.offset_left = 8
			img.offset_right = -8
			img.offset_top = 8
			img.offset_bottom = -8
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(img)
			b.pressed.connect(func() -> void:
				g._social.send_message(_peer, Social.sticker_body(id))
				refresh_thread()
				_picker_hide()
			)
			grid.add_child(b)

func _close_thread() -> void:
	_peer = ""
	_confirm_close()
	_refresh_list()
	if _list_scroll != null:
		# FIX-D: свежесозданный ScrollContainer ещё не посчитал range прокрутки —
		# синхронная запись клампится в 0 в живой игре; отложенная приходит после
		# расклада кадра и ложится в настоящий диапазон.
		_list_scroll.set_deferred("scroll_vertical", _saved_scroll)

func _open_trade(peer: String) -> void:
	if _trade == null:
		_trade = TradeUI.new(g)
	_trade.open(peer)

func _trade_close() -> void:
	if _trade != null:
		_trade.close()

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
