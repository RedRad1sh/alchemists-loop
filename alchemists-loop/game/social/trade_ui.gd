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
var _offer := {"give": {}, "want": {}, "gift": false}
var _picking := ""          # "give" | "want" | "" — идёт ли выбор карты
var _note := ""             # строка серверного отказа (код → текст через _detail_text)

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

## Контракт выбранной карты — спека §8.3: четыре поля, ни одним больше.
## card_id пуст => это экземпляр (хроматик) по craft_id, и он всегда последний.
func pick(card_id: String, craft_id: String, copies: int,
		display_name: String) -> Dictionary:
	return {"card_id": card_id, "craft_id": craft_id,
		"is_last": craft_id != "" or copies <= 1,
		"display_name": display_name}

## Всё, что можно отдать прямо сейчас: виды карт из серверной коллекции и
## внекомплектные экземпляры. Локальная коллекция (sigil_crafts на клиенте)
## для этого не заводится (§8.4) — источник один: кэш /api/sigil/collection.
func entries() -> Array:
	var out: Array = []
	var coll: Dictionary = g._sigil.server_collection()
	for cid in coll:
		var copies := int((coll[cid] as Dictionary).get("copies", 0))
		if copies <= 0:
			continue
		var nm := str(g._sigil.card(str(cid)).get("fallback_name", cid))
		out.append(pick(str(cid), "", copies, nm))
	for x in g._sigil.server_extras():
		if not (x is Dictionary):
			continue
		var craft := str((x as Dictionary).get("craft_id", ""))
		if craft == "":
			continue
		var nm := str((x as Dictionary).get("llm_name", ""))
		if nm == "":
			nm = "Внекомплектная"
		out.append(pick("", craft, 1, nm))
	return out

func can_confirm() -> bool:
	if _offer["give"] == {}:
		return false
	return bool(_offer["gift"]) or _offer["want"] != {}

func open_builder() -> void:
	_picking = ""
	_note = ""
	_mode = 1
	_render()

func open_confirm() -> void:
	if not can_confirm():
		_note = "Выбери карту"
		_mode = 1
		_render()
		return
	_mode = 2
	_render()

func on_offer(result: Dictionary) -> void:
	_on_write_result(result, true)

func on_gift(result: Dictionary) -> void:
	_on_write_result(result, false)

func _on_write_result(result: Dictionary, is_offer: bool) -> void:
	if result.get("ok", false) == true:
		_offer = {"give": {}, "want": {}, "gift": false}
		_picking = ""
		_note = ""
		if is_offer:
			_mode = 0          # оффер виден в «Я предложил»
			Net.trade_list(g._online._device_id)
		_render()
		return
	_note = _detail_text(String(result.get("detail", "")))
	_render()

## Коды сервера (§7) → текст. Единая таблица на весь слой: отказ offer и отказ
## accept/cancel/gift обязаны звучать одинаково, иначе игрок решит, что это
## разные механизмы.
static func _detail_text(code: String) -> String:
	match code:
		"not_registered": return "Сначала заведись в мире — тогда обмен откроется"
		"not_friends": return "Меняться можно только с друзьями"
		"not_found": return "Такого обмена уже нет"
		"not_pending": return "Этот обмен уже закрыт"
		"not_maker": return "Отменить оффер может только тот, кто его предложил"
		"too_many_open": return "Слишком много висящих предложений — закрой часть"
		"week_limit": return "Недельный лимит исчерпан — сброс в понедельник"
		"expired": return "Предложение просрочилось: ему больше недели"
		"card_not_owned": return "Этой карты у тебя уже нет"
		"unknown_card": return "Такую карту мир не знает"
		"bad_selector": return "Нужно выбрать ровно одну карту"
		"self_deal": return "Себе менять нельзя"
		# Голый card_gone отдаёт только gift (server.py:5805 и :5810): целевой
		# craft_id уже занят у получателя, либо строка ушла из-под нас.
		"card_gone": return "Подарок не дошёл: карта ушла или такая же уже у него"
		"card_gone:maker": return "У предложившего карты больше нет"
		"card_gone:taker": return "У тебя больше нет карты для обмена"
		_: return "Мир не понял запрос"

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
		1:
			_render_builder()
		2:
			_render_confirm()
		3:
			_render_builder()
		_:
			_render_list()

func _render_list() -> void:
	_clear(_body)
	# Заголовок: к кому обращён обмен. Остаток лимита накрутится в Task 10 —
	# до этого серверные числа в этот слой ещё не приходили.
	_header.text = "%s · %s" % [TITLE, _nick()]
	var new_btn := g._small_button("Предложить обмен", Vector2(180, 40), 0)
	new_btn.pressed.connect(open_builder)
	_body.add_child(new_btn)
	_incoming = _section("Мне предлагают")
	_outgoing = _section("Я предложил")
	_history = _section("История")
	for box in [_incoming, _outgoing, _history]:
		var wait := g._label("—", 12)
		wait.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		box.add_child(wait)

func _slot_text(e) -> String:
	if not (e is Dictionary) or (e as Dictionary).is_empty():
		return "не выбрана"
	return String((e as Dictionary).get("display_name", ""))

func _render_builder() -> void:
	_clear(_body)
	_header.text = "%s · %s" % [TITLE, _nick()]
	_body.add_child(g._label("Что отдаю", 13))
	var give := g._small_button(_slot_text(_offer["give"]), Vector2(260, 40), 0)
	give.name = "GiveSlot"
	give.pressed.connect(_pick_for.bind("give"))
	_body.add_child(give)
	_body.add_child(g._label("Что прошу взамен", 13))
	var want := g._small_button(_slot_text(_offer["want"]), Vector2(260, 40), 0)
	want.name = "WantSlot"
	want.disabled = bool(_offer["gift"])     # подарок = односторонняя передача
	want.pressed.connect(_pick_for.bind("want"))
	_body.add_child(want)
	var gift_btn := g._small_button(
		"Подарить" if not bool(_offer["gift"]) else "Подарок: да", Vector2(140, 34), 0)
	gift_btn.pressed.connect(_toggle_gift)
	_body.add_child(gift_btn)
	if _note != "":
		var note := g._label(_note, 12)
		note.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(note)
	if _picking != "":
		_body.add_child(g._label("Выбери карту", 13))
		for e in entries():
			var nm := String(e["display_name"])
			if bool(e["is_last"]):
				nm += " — последняя"
			var b := g._small_button(nm, Vector2(260, 40), 0)
			b.pressed.connect(_choose.bind(e))
			_body.add_child(b)
		var cancel := g._small_button("Отменить выбор", Vector2(150, 34), 0)
		cancel.pressed.connect(_stop_picking)
		_body.add_child(cancel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	var next := g._small_button("Дальше", Vector2(120, 40), 0)
	next.disabled = not can_confirm()
	next.pressed.connect(open_confirm)
	row.add_child(next)
	var back := g._small_button("Назад", Vector2(96, 34), 0)
	back.pressed.connect(_back_to_list)
	row.add_child(back)

func _toggle_gift() -> void:
	_offer["gift"] = not bool(_offer["gift"])
	if bool(_offer["gift"]):
		_offer["want"] = {}
	_render()

func _pick_for(slot: String) -> void:
	_picking = slot
	_mode = 3
	_render()

func _stop_picking() -> void:
	_picking = ""
	_mode = 1
	_render()

func _choose(e: Dictionary) -> void:
	_offer[_picking] = e
	_picking = ""
	_mode = 1
	_note = ""
	_render()

func _back_to_list() -> void:
	_picking = ""
	_mode = 0
	_render()

func _render_confirm() -> void:
	_clear(_body)
	_header.text = "%s · %s" % [TITLE, _nick()]
	var give: Dictionary = _offer["give"]
	var want: Dictionary = _offer["want"]
	_body.add_child(g._label("Ты отдаёшь: %s" % String(give.get("display_name", "")), 14))
	if bool(_offer["gift"]):
		_body.add_child(g._label("Подарок (%s): без встречной карты" % _nick(), 13))
	else:
		_body.add_child(g._label("Ты получаешь: %s" % String(want.get("display_name", "")), 14))
	if bool(give.get("is_last", false)) or (not bool(_offer["gift"])
			and bool(want.get("is_last", false))):
		# Единственная защита «последней копии» (спека §5.3): сервер такую сделку
		# не блокирует, поэтому название последствия обязано быть на этом экране.
		var warn := g._label(
			"Это твоя последняя копия вида. Отдав её, теряешь карту из "
			+ "коллекции: прогресс достижений по сигилам и невыбранные вехи "
			+ "комплекта пересчитываются по тому, что осталось.", 13)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(warn)
	if _note != "":
		var note := g._label(_note, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color("#e6a84a"))
		_body.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	var go := g._small_button("Подарить" if bool(_offer["gift"]) else "Предложить",
		Vector2(150, 40), 0)
	go.pressed.connect(_send)
	row.add_child(go)
	var edit := g._small_button("Изменить", Vector2(110, 34), 0)
	edit.pressed.connect(open_builder)
	row.add_child(edit)

func _send() -> void:
	var dev := g._online._device_id
	var give: Dictionary = _offer["give"]
	if bool(_offer["gift"]):
		Net.trade_gift(dev, _peer, String(give.get("card_id", "")),
			String(give.get("craft_id", "")))
		return
	var want: Dictionary = _offer["want"]
	Net.trade_offer(dev, _peer, String(give.get("card_id", "")),
		String(give.get("craft_id", "")), String(want.get("card_id", "")),
		String(want.get("craft_id", "")))

func _nick() -> String:
	var friend := g._social.friend_by_device(_peer)
	if friend.is_empty():
		return "Алхимик"
	return String(friend.get("nick", "Алхимик"))
