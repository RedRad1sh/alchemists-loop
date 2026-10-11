extends RefCounted
class_name SuiteSocial
# S1 «Друзья и переписка» (клиент): net-методы, кэш Social, экран SocialUI,
# бейдж, тост, Esc/z-order, сейв-ключи. Герметично: Net в ST drenage-offline,
# поэтому сборку запросов проверяем через _build_request (шаблон
# suite_resonance_net.gd:72-80), состояние — прямыми эмиссиями результата.
# Мутации, красящие этот блок: удалить/переименовать метод, сменить path,
# перепутать поле body, снять signal-эмиссию в _dispatch.

static func run(g: Game) -> void:
	_net_requests(g)
	_dispatch_emits(g)
	_pure_logic(g)
	_cache(g)
	_save_keys(g)
	_wiring(g)
	_screen(g)
	_segment_press(g)
	_esc_stack(g)
	_thread(g)
	_confirm(g)
	_search_helpers(g)
	_send_failures(g)
	_friend_buttons(g)

static func _net_requests(_g: Game) -> void:
	# вызов реальных методов: в ST Net синхронно сливает очередь в offline,
	# поэтому вызовы безопасны и доказывают, что методы существуют и не падают
	Net.social_inbox("dev 1")
	Net.messages("dev1", "dev2", 7)
	Net.message_send("dev1", "dev2", "прив")
	Net.friend_request("dev1", "Николя")
	Net.friend_respond("dev1", "dev2", true)
	Net.friend_remove("dev1", "dev2")
	Net.friend_block("dev1", "dev2")
	Net.friend_unblock("dev1", "dev2")
	# сборка запроса проверяется через generic _build_request (Net — синглтон)
	var r: Dictionary = Net._build_request({
		"kind": "social_inbox", "path": "/social/inbox?device_id=dev%201"})
	Selftest.check("social inbox GET path",
		int(r["method"]) == HTTPClient.METHOD_GET
		and String(r["url"]).ends_with("/api/social/inbox?device_id=dev%201"))
	r = Net._build_request({"kind": "messages",
		"path": "/messages?device_id=dev1&peer_device=dev2&since_id=7"})
	Selftest.check("messages GET path",
		int(r["method"]) == HTTPClient.METHOD_GET
		and String(r["url"]).contains("/api/messages?")
		and String(r["url"]).ends_with("since_id=7"))
	r = Net._build_request({"kind": "message_send", "path": "/message/send",
		"body": {"device_id": "dev1", "peer_device": "dev2", "body": "прив"}})
	Selftest.check("send POST body", int(r["method"]) == HTTPClient.METHOD_POST
		and JSON.parse_string(r["body"]) == {"device_id": "dev1", "peer_device": "dev2", "body": "прив"})
	r = Net._build_request({"kind": "friend_request", "path": "/friend/request",
		"body": {"device_id": "dev1", "target_nick": "Николя"}})
	Selftest.check("friend request POST", int(r["method"]) == HTTPClient.METHOD_POST
		and JSON.parse_string(r["body"])["target_nick"] == "Николя")

static func _dispatch_emits(_g: Game) -> void:
	# Каждый из 8 social-сигналов обязан прийти ровно один раз на свой kind:
	# ловит снятие/порчу ветки `signal.emit(parsed)` в Net._dispatch.
	# _dispatch(req, parsed): первый аргумент — запись очереди (важен "kind"),
	# второй — разобранный ответ; герметично вызываем напрямую, без сети.
	var counts := {}
	Net.social_inbox_result.connect(func(_r: Dictionary) -> void: counts["social_inbox"] = int(counts.get("social_inbox", 0)) + 1)
	Net.messages_result.connect(func(_r: Dictionary) -> void: counts["messages"] = int(counts.get("messages", 0)) + 1)
	Net.message_send_result.connect(func(_r: Dictionary) -> void: counts["message_send"] = int(counts.get("message_send", 0)) + 1)
	Net.friend_request_result.connect(func(_r: Dictionary) -> void: counts["friend_request"] = int(counts.get("friend_request", 0)) + 1)
	Net.friend_respond_result.connect(func(_r: Dictionary) -> void: counts["friend_respond"] = int(counts.get("friend_respond", 0)) + 1)
	Net.friend_remove_result.connect(func(_r: Dictionary) -> void: counts["friend_remove"] = int(counts.get("friend_remove", 0)) + 1)
	Net.friend_block_result.connect(func(_r: Dictionary) -> void: counts["friend_block"] = int(counts.get("friend_block", 0)) + 1)
	Net.friend_unblock_result.connect(func(_r: Dictionary) -> void: counts["friend_unblock"] = int(counts.get("friend_unblock", 0)) + 1)
	for kind in ["social_inbox", "messages", "message_send", "friend_request",
			"friend_respond", "friend_remove", "friend_block", "friend_unblock"]:
		Net._dispatch({"kind": String(kind)}, {})
	Selftest.check("dispatch emits social_inbox", int(counts.get("social_inbox", 0)) == 1)
	Selftest.check("dispatch emits messages", int(counts.get("messages", 0)) == 1)
	Selftest.check("dispatch emits message_send", int(counts.get("message_send", 0)) == 1)
	Selftest.check("dispatch emits friend_request", int(counts.get("friend_request", 0)) == 1)
	Selftest.check("dispatch emits friend_respond", int(counts.get("friend_respond", 0)) == 1)
	Selftest.check("dispatch emits friend_remove", int(counts.get("friend_remove", 0)) == 1)
	Selftest.check("dispatch emits friend_block", int(counts.get("friend_block", 0)) == 1)
	Selftest.check("dispatch emits friend_unblock", int(counts.get("friend_unblock", 0)) == 1)

static func _pure_logic(g: Game) -> void:
	# Мутации: сменить порог «99+», сломать «вчера», обрезать пословно не по
	# пробелу, применить not-ok инбокс поверх кэша, не откатить optimistic.
	Selftest.check("badge 0 -> plain", Social.badge_for(0) == "Друзья")
	Selftest.check("badge 2 -> dot", Social.badge_for(2) == "Друзья •2")
	Selftest.check("badge 150 -> cap", Social.badge_for(150) == "Друзья •99+")
	Selftest.check("seen today", Social.last_seen_text("2026-10-10T09:00:00", "2026-10-10") == "был(а) сегодня")
	Selftest.check("seen yesterday", Social.last_seen_text("2026-10-09T23:59:59", "2026-10-10") == "был(а) вчера")
	Selftest.check("seen 3 days", Social.last_seen_text("2026-10-07T09:00:00", "2026-10-10") == "был(а) 3 дня назад")
	Selftest.check("seen empty", Social.last_seen_text("", "2026-10-10") == "")
	Selftest.check("preview short", Social.preview_cut("привет", 60) == "привет")
	Selftest.check("preview cut word", Social.preview_cut("a b c d e f g h i j k l m n o p q r s t u v w x y z a b c d e f g h i j k l m n o p q r s t u v w x y z", 60).length() <= 60)
	Selftest.check("preview no-space fits", Social.preview_cut("х".repeat(80), 60).length() <= 60)

static func _cache(g: Game) -> void:
	# Мутации: ok=false затирает кэш; absent keys падают; 422-список роняет
	# разбор; optimistic не убирается при отказе.
	var s := Social.new(g)
	s.on_inbox({"ok": false, "detail": "not_registered"})
	Selftest.check("not ok keeps cache empty", s.friends().is_empty())
	s.on_inbox({"ok": true, "friends": [
		{"device_id": "npc-spirit", "nick": "Светик", "unread": 1,
		 "last_msg_preview": "Здравствуй", "last_msg_at": "2026-10-10T08:00:00",
		 "last_seen": "", "avatar": {}},
		{"device_id": "dev-b", "nick": "Николя", "unread": 0,
		 "last_msg_preview": "", "last_msg_at": "", "last_seen": "2026-10-09T12:00:00",
		 "avatar": {}}],
		"incoming": [{"device_id": "dev-c", "nick": "Аня", "avatar": {},
			"last_seen": "", "requested_at": "2026-10-10T07:00:00"}],
		"outgoing": [{"nick": "Варя", "requested_at": ""}],
		"unread_total": 1, "requests_total": 1, "friend_limit": 50})
	Selftest.check("inbox applied", s.friends().size() == 2 and s.unread_total() == 1)
	Selftest.check("friend by nick", s.friend_by_nick("Николя").get("device_id", "") == "dev-b")
	Selftest.check("outgoing by nick", s.is_outgoing_to("Варя"))
	s.set_awaiting_peer("dev-b")
	s.on_send({"ok": false, "offline": true})
	s.optimistic_send("dev-b", "горстка")
	Selftest.check("optimistic visible", s.thread("dev-b").size() == 1
		and s.thread("dev-b")[0].get("pending", false))
	s.on_send({"ok": false, "detail": "daily_limit"})
	Selftest.check("optimistic rolled back", s.thread("dev-b").is_empty())

static func _save_keys(g: Game) -> void:
	# Мутации: key переименован; старый сейв без ключей роняет загрузку.
	var s := Social.new(g)
	s.on_inbox({"ok": true, "friends": [{"device_id": "d", "nick": "N", "unread": 2}],
		"incoming": [], "outgoing": [], "unread_total": 2, "requests_total": 0})
	var data := s.to_save()
	Selftest.check("save shape", data.has("social_cache") and data.has("social_last_read"))
	var t := Social.new(g)
	t.from_save({})                       # старый сейв — не падает
	Selftest.check("legacy save ok", t.friends().is_empty())
	t.from_save(data)
	Selftest.check("roundtrip", t.unread_total() == 2)

static func _wiring(g: Game) -> void:
	# Мутации: убрать кнопку «Друзья» из ether_row, сузить её ниже 96,
	# не звать _refresh_header после inbox (бейдж не отрендерится).
	# Проверки экрана (z-группа, скрытость) — в сюите Task 4,SocialUI ещё нет.
	# g.get() вместо g._social_btn: до реализации поля прямой доступ дал бы
	# SCRIPT ERROR и молча сорвал бы прогон — а нам нужны честные FAIL-строки.
	var b: Button = g.get("_social_btn")
	Selftest.check("social button exists", b != null)
	Selftest.check("button width holds badge", b != null and b.custom_minimum_size.x >= 96)
	g._social.on_inbox({"ok": true, "friends": [], "incoming": [],
		"outgoing": [], "unread_total": 2, "requests_total": 0})
	g._engine._refresh_header()
	Selftest.check("badge renders after inbox", b != null and b.text == "Друзья •2")
	# Не оставляем мусор в живом кэше: ниже по прогону идут другие сюиты.
	g._social.on_inbox({"ok": true, "friends": [], "incoming": [],
		"outgoing": [], "unread_total": 0, "requests_total": 0})
	g._engine._refresh_header()


static func _screen(g: Game) -> void:
	var ui = g.get("_social_ui")
	Selftest.check("social screen built", ui != null and ui._screen != null)
	if ui == null or ui._screen == null:
		return
	Selftest.check("social screen hidden", not ui._screen.visible)
	Selftest.check("social screen z20 group", ui._screen.z_index == 20
		and ui._screen.is_in_group("modal_ui"))
	g._social._seed_demo()
	ui.open(0)
	# F2: сверяем отрисованное содержимое, а не эхо поля `_tab` (open(tab) сам
	# его пишет): 3 друга и ноль заявок в сид-мире, затем наоборот.
	Selftest.check("friends tab renders rows", ui._body != null
		and ui._body.find_children("FriendRow_*", "", true, false).size() == 3
		and ui._body.find_children("RequestRow_*", "", true, false).is_empty())
	ui.open(1)
	Selftest.check("requests tab renders rows", ui._body != null
		and ui._body.find_children("RequestRow_*", "", true, false).size() == 1
		and ui._body.find_children("FriendRow_*", "", true, false).is_empty())
	ui.close()


static func _segment_press(g: Game) -> void:
	# F1 (Critical): перестройка списка из-под собственного pressed не должна
	# free() нажавшую кнопку/строку. Мутации: вернуть `child.free()` в
	# _refresh_list/_build_thread — краснеют «survives rebuild» (кнопка мертва в
	# тот же момент); вернуть чистый queue_free() без remove_child — краснеет
	# «exactly one fresh segments» (старый узел ещё ребёнок _body).
	var ui = g.get("_social_ui")
	if ui == null or ui._screen == null or ui._body == null:
		Selftest.check("segment press available", false)
		return
	g._social._seed_demo()
	ui.open(0)
	var seg: HBoxContainer = ui._body.find_child("SocialSegments", true, false)
	if seg == null or seg.get_child_count() < 2:
		Selftest.check("segment press: seg buttons found", false)
		ui.close()
		return
	var requests_b: Button = seg.get_child(1) as Button
	if requests_b == null:
		Selftest.check("segment press: seg button is Button", false)
		ui.close()
		return
	requests_b.pressed.emit()
	Selftest.check("pressed segment button survives rebuild", is_instance_valid(requests_b))
	var fresh: Array = ui._body.find_children("SocialSegments", "", true, false)
	Selftest.check("exactly one fresh segments after press", fresh.size() == 1)
	Selftest.check("press switches rendered rows",
		ui._body.find_children("RequestRow_*", "", true, false).size() == 1
		and ui._body.find_children("FriendRow_*", "", true, false).is_empty())
	if fresh.size() == 1:
		var friends_b: Button = (fresh[0] as HBoxContainer).get_child(0) as Button
		if friends_b != null:
			friends_b.pressed.emit()
			Selftest.check("second segment press survives rebuild", is_instance_valid(friends_b))
			Selftest.check("friends rows rendered after return press",
				ui._body.find_children("FriendRow_*", "", true, false).size() == 3)
	# «Назад» в ленте — тот же hazard: _close_thread перестраивает _body,
	# освобождая нажавшую кнопку.
	ui._open_thread("dev-b")
	var header: HBoxContainer = ui._body.find_child("ThreadHeader", true, false)
	if header == null or header.get_child_count() == 0:
		Selftest.check("back button available", false)
		ui.close()
		return
	var back_b: Button = header.get_child(0) as Button
	if back_b == null:
		Selftest.check("back button is Button", false)
		ui.close()
		return
	back_b.pressed.emit()
	Selftest.check("pressed back button survives rebuild", is_instance_valid(back_b))
	Selftest.check("list rebuilt after back press", ui._peer == ""
		and ui._body.find_children("SocialSegments", "", true, false).size() == 1
		and ui._body.find_children("FriendRow_*", "", true, false).size() == 3)
	ui.close()


static func _esc_stack(g: Game) -> void:
	# Task 4 Step (план): Esc-стек — закрытие идёт по слоям социалки
	# (модалка → лента → список → экран), а не проваливается сквозь экран к
	# поверхности под ним; ad-предикат обязан видеть соц-поверхности.
	# Мутации: снять соц-ветки в sigil_ui._close_top_modal — первый же Esc
	# «съедается» lower-поверхностью и красит кейсы; снять зеркало в
	# _modal_open_for_ads — краснеет предикат.
	var ui = g.get("_social_ui")
	if ui == null or ui._screen == null:
		Selftest.check("esc stack available", false)
		return
	var base := g._modal_open_for_ads()
	Selftest.check("esc stack clean before social esc test", base == false)
	g._social._seed_demo()
	ui.open(0)
	ui._open_thread("dev-b")
	ui._open_confirm("dev-b")
	Selftest.check("ads predicate holds social confirm", g._modal_open_for_ads() == true)
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_ESCAPE
	Selftest.check("esc closes confirm first", g._handle_esc(k) == true
		and ui._confirm != null and not ui._confirm.visible
		and ui._screen.visible and ui._peer == "dev-b")
	Selftest.check("esc closes thread to list next", g._handle_esc(k) == true
		and ui._peer == "" and ui._screen.visible)
	Selftest.check("ads predicate holds social screen", g._modal_open_for_ads() == true)
	Selftest.check("esc closes social screen last", g._handle_esc(k) == true
		and not ui._screen.visible)
	Selftest.check("ads predicate releases social surfaces", g._modal_open_for_ads() == base)


static func _thread(g: Game) -> void:
	var ui = g.get("_social_ui")
	if ui == null:
		Selftest.check("social thread available", false)
		return
	g._social._seed_demo()
	ui.open(0)
	# Task 5 Step: скролл списка сохраняется при уходе в ленту и восстанавливается
	# после возврата. want == 42 отсекает clamp-ловушку: в headless нет кадров
	# раскладки, диапазон прокрутки ScrollContainer не пересчитывается (ни resize,
	# ни запрос min-size не помогают) и запись клампится в 0. Задаём ползунку
	# рабочий диапазон — не меньше того, что посчитал бы кадр в живой игре (строки
	# списка заведомо выше вьюпорта), — и только потом пишем позицию.
	ui._list_scroll.get_v_scroll_bar().max_value = 300
	ui._list_scroll.scroll_vertical = 42
	var want: int = ui._list_scroll.scroll_vertical
	ui._open_thread("dev-b")
	Selftest.check("thread opens", ui._peer == "dev-b")
	Selftest.check("list scroll captured on open", want == 42 and ui._saved_scroll == want)
	# Офлайн-плашка Task 5: в ST Net недоступен → «Мир не на связи» видима в ленте.
	var banner_seen := false
	for n in ui._body.find_children("*", "Label", true, false):
		if String(n.text) == "Мир не на связи":
			banner_seen = true
	Selftest.check("offline banner visible in thread", banner_seen)
	Selftest.check("thread has bubbles", ui._body.find_child("Bubble_0", true, false) != null
		and ui._body.find_child("Bubble_2", true, false) != null)
	# Возврат перестраивает список: _close_thread восстанавливает позицию на
	# свежем ScrollContainer. Без кадров раскладки его ползунок имеет range 0
	# и запись клампится, а единственный синхронный пересчёт — вход в дерево —
	# как раз обнуляет range. Поэтому раздаём диапазон в момент child_entered_tree
	# и повторяем по ready (после него пересчётов больше нет): строка
	# восстановления пишется в живой range. Убери её из _close_thread — value
	# останется 0 и кейс «thread closes to list» покраснеет, тавтологии 0==0 нет.
	var give_range := func(sc: ScrollContainer) -> void:
		sc.get_v_scroll_bar().max_value = 300
	var on_child := func(n: Node) -> void:
		var sc := n as ScrollContainer
		if sc != null:
			give_range.call(sc)
			sc.ready.connect(func() -> void: give_range.call(sc))
	ui._body.child_entered_tree.connect(on_child)
	ui._close_thread()
	ui._body.child_entered_tree.disconnect(on_child)
	Selftest.check("thread closes to list", ui._peer == ""
		and ui._list_scroll.scroll_vertical == ui._saved_scroll)
	ui._open_thread(Social.SPIRIT_DEVICE)
	Selftest.check("spirit has no input", ui._body.find_child("SpiritNoInput", true, false) != null
		and ui._body.find_child("ThreadInput", true, false) == null)
	ui.close()


static func _confirm(g: Game) -> void:
	var ui = g.get("_social_ui")
	if ui == null:
		Selftest.check("social confirm available", false)
		return
	g._social._seed_demo()
	ui.open(0)
	ui._open_confirm("dev-b")
	var body: Label = null
	if ui._confirm != null:
		body = ui._confirm.find_child("ConfirmBody", true, false) as Label
	Selftest.check("confirm z21", ui._confirm != null and ui._confirm.z_index == 21)
	Selftest.check("confirm honest copy", body != null
		and String(body.text).contains("Николя")
		and String(body.text).contains("будет удалена у вас обоих"))
	# Task 6 Step: «Удалить из друзей» кликом шлёт Net.friend_remove (в ST —
	# offline-результат, не краш) и закрывает подтверждение; после применения
	# нового инбокса без dev-b строка и бейдж исчезают в отрисованном списке.
	# Мутации: снять Net.friend_remove в обработчике кнопки, снять _confirm_close
	# после pick, не обновлять список после on_inbox.
	var remove_btn: Button = null
	for n in ui._confirm.find_children("*", "Button", true, false):
		if n is Button and String(n.text) == "Удалить из друзей":
			remove_btn = n
	if remove_btn == null:
		Selftest.check("remove button found", false)
		ui.close()
		return
	var fired := {"n": 0}
	var cb := func(_r: Dictionary) -> void: fired["n"] = int(fired["n"]) + 1
	Net.friend_remove_result.connect(cb)
	remove_btn.pressed.emit()
	if Net.friend_remove_result.is_connected(cb):
		Net.friend_remove_result.disconnect(cb)
	Selftest.check("remove click sends friend_remove", int(fired["n"]) == 1)
	Selftest.check("confirm closes after remove pick", not ui._confirm.visible)
	g._social.on_inbox({"ok": true, "friends": [
		{"device_id": "npc-spirit", "nick": "Светик", "unread": 0, "avatar": {},
			"last_seen": "", "last_msg_preview": ""},
		{"device_id": "dev-c", "nick": "Аня", "unread": 0, "avatar": {},
			"last_seen": "", "last_msg_preview": ""}],
		"incoming": [], "outgoing": [], "unread_total": 0, "requests_total": 0})
	ui._refresh_list()
	Selftest.check("removed friend row disappears",
		ui._body.find_children("FriendRow_dev-b", "", true, false).is_empty()
		and ui._body.find_children("FriendRow_*", "", true, false).size() == 2)
	g._engine._refresh_header()
	Selftest.check("badge clears after inbox applied", g._social_btn.text == "Друзья")
	ui._confirm_close()
	ui.close()


static func _search_helpers(g: Game) -> void:
	var s := Social.new(g)
	s._seed_demo()
	Selftest.check("friend state text", SocialUI._friend_state_text("Николя", s) == "в друзьях"
		and SocialUI._friend_state_text("Мирра", s) == "заявка отправлена"
		and SocialUI._friend_state_text("Некто", s) == "в друзья")


static func _send_failures(g: Game) -> void:
	# F3/F4 (мутационно-реактивные): снять ветку race_lost в _detail_text —
	# краснеет 1-й кейс; снять offline-ветку или type-guard detail в
	# Social.on_send — краснеют «offline notice»/«unmapped copy» (422-список
	# иначе падает на String-параметр show_send_error, pending-пузырёк исчезает
	# молча). Опасные результаты шём через Net.signal-эмиссию: runtime-ошибка
	# внутри коннекта не рвёт кадр сюиты (Signal::emit — C++-граница), проверки
	# ниже исполняются честно даже при откате фикса. В ST main.gd держит
	# социал-коннекты за гейтом _net_enabled = not _selftest (main.gd:604),
	# поэтому обработчик подключаем временно сами — ровно как рантайм
	# (main.gd:641) — и снимаем после проверок. Пир dev-x не заведён в
	# threads — thread() остаётся видимостью optimistic-хвоста.
	Selftest.check("race_lost copy", SocialUI._detail_text("race_lost")
		== "Заявка не прошла, попробуй ещё раз.")
	var ui = g.get("_social_ui")
	if ui == null or ui._err_line == null:
		Selftest.check("send failure feedback wired", false)
		return
	if not Net.message_send_result.is_connected(g._social.on_send):
		Net.message_send_result.connect(g._social.on_send)
	g._social.set_awaiting_peer("dev-x")
	g._social.optimistic_send("dev-x", "горстка эфира")
	Net.message_send_result.emit({"ok": false, "offline": true})
	Selftest.check("offline refuse shows offline notice",
		ui._err_line.text == "Мир не на связи")
	Selftest.check("offline refuse rolls back pending", g._social.thread("dev-x").is_empty())
	g._social.optimistic_send("dev-x", "вторая горстка")
	Net.message_send_result.emit({"ok": false, "detail": [{"loc": ["body"]}]})
	Selftest.check("422 list detail maps to unmapped copy",
		ui._err_line.text == "Сервер не понял запрос.")
	Selftest.check("422 refuse rolls back pending", g._social.thread("dev-x").is_empty())
	if Net.message_send_result.is_connected(g._social.on_send):
		Net.message_send_result.disconnect(g._social.on_send)
	g._social.set_awaiting_peer("")


static func _friend_buttons(g: Game) -> void:
	# Task 7: кнопки «в друзья» в строках рейтинга и карточке гостя + R8-тост.
	# Мутации: не позвать SocialUI.attach в _render_rating_rows (краснеют
	# «rating rows…»); не перестраивать строку гостей в _on_house_profile
	# (краснеет «guest card…»); снять коннект/хендлер friend_request_result в
	# main.gd (краснеют «R8…»); перепутать ветки _friend_state_text (краснеют
	# текстовые проверки состояний); снять disabled/состояние в attach.
	g._social._seed_demo()
	# attach точечно: состояние из кэша по нику, ширина Vector2(110,30) (высоту
	# _small_button клампит к 38 — сверяем только заказанную ширину), тап →
	# Net.friend_request (в ST drainage-offline — эмиссия безопасна и ловится).
	var row := HBoxContainer.new()
	var fresh: Button = SocialUI.attach(g, row, "Некто")
	Selftest.check("attach fresh: text/state/size", fresh != null and fresh.text == "в друзья"
		and not fresh.disabled and fresh.custom_minimum_size.x == 110
		and row.get_child_count() == 1)
	var fr_fired := {"n": 0}
	var fr_cb := func(_r: Dictionary) -> void: fr_fired["n"] = int(fr_fired["n"]) + 1
	Net.friend_request_result.connect(fr_cb)
	fresh.pressed.emit()
	if Net.friend_request_result.is_connected(fr_cb):
		Net.friend_request_result.disconnect(fr_cb)
	Selftest.check("attach press sends friend_request", int(fr_fired["n"]) == 1)
	var done: Button = SocialUI.attach(g, row, "Николя")
	Selftest.check("attach friend: «в друзьях» disabled", done.text == "в друзьях" and done.disabled)
	var sent: Button = SocialUI.attach(g, row, "Мирра")
	Selftest.check("attach outgoing: «заявка отправлена» disabled",
		sent.text == "заявка отправлена" and sent.disabled)
	row.queue_free()
	# Строки рейтинга: билдер _render_rating_rows зовёт attach(g, row, nick)
	# после имени — состояние пересчитывается на каждой перерисовке вкладки.
	if g._online._rating_list == null:
		Selftest.check("rating rows available", false)
	else:
		g._online._render_rating_rows({"ok": true, "rows": [
			{"rank": 1, "nick": "Николя", "discoveries": 3, "elements": 2, "points": 5},
			{"rank": 2, "nick": "Мирра", "discoveries": 1, "elements": 1, "points": 2},
			{"rank": 3, "nick": "Некто", "discoveries": 0, "elements": 0, "points": 0}]})
		var texts: Array = []
		for b in g._online._rating_list.find_children("*", "Button", true, false):
			texts.append(String((b as Button).text))
		Selftest.check("rating rows carry per-nick friend states",
			texts.count("в друзьях") == 1 and texts.count("заявка отправлена") == 1
			and texts.count("в друзья") == 1)
		for c in g._online._rating_list.get_children():
			g._online._rating_list.remove_child(c)
			c.queue_free()
	# Карточка гостя (home.gd, свой профиль house_visitors): ряд кнопок рядом со
	# строкой гостей. get() — до реализации поля прямой g._home._guests_row дал бы
	# ошибку компляции сюты вместо честного FAIL.
	var grows: HBoxContainer = g._home.get("_guests_row")
	if grows == null:
		Selftest.check("guest friend row exists", false)
	else:
		var wk_old = g._home.get("house_gift_week")
		var cnt_old = g._home.get("house_gift_count")
		g._home._on_house_profile(1, [{"nick": "Николя"}, {"nick": "Мирра"}, {"nick": "Некто"}])
		var gt: Array = []
		for c in grows.get_children():
			gt.append(String((c as Button).text))
		Selftest.check("guest card shows friend states",
			gt == ["в друзьях", "заявка отправлена", "в друзья"])
		g._home._on_house_profile(0, [])
		g._home.set("house_gift_week", wk_old)
		g._home.set("house_gift_count", cnt_old)
	# R8: единая точка отказа заявки — глобальный тост из main.gd. Опасные
	# результаты шём через Net-эмиссию (Signal::emit — C++-граница, рантайм-
	# ошибка хендлера не рвёт кадр сюты; паттерн _send_failures). Хендлер и
	# коннект в ST гейтятся _net_enabled, поэтому вешаем связку сами.
	var handler_exists: bool = g.has_method("_on_friend_request_result")
	Selftest.check("R8 handler exists in main", handler_exists)
	if handler_exists:
		var bound := Callable(g, "_on_friend_request_result")
		if not Net.friend_request_result.is_connected(bound):
			Net.friend_request_result.connect(bound)
		var stack_before := 0
		if g._online._toast_stack != null:
			stack_before = g._online._toast_stack.get_child_count()
		Net.friend_request_result.emit({"ok": false, "detail": "bot"})
		var toast_texts: Array = []
		if g._online._toast_stack != null:
			for p in g._online._toast_stack.get_children():
				var l := Online._find_toast_label(p as PanelContainer)
				if l != null:
					toast_texts.append(l.text)
		Selftest.check("R8 bot refusal surfaces as global toast",
			toast_texts.has("Это ученик гильдии, заявки он не принимает."))
		var stack_after := 0
		if g._online._toast_stack != null:
			stack_after = g._online._toast_stack.get_child_count()
		Net.friend_request_result.emit({"ok": false, "detail": [{"loc": ["body"]}]})
		var stack_now := 0
		if g._online._toast_stack != null:
			stack_now = g._online._toast_stack.get_child_count()
		Selftest.check("R8 non-String detail adds no toast", stack_now == stack_after)
		var inbox_fired := {"n": 0}
		var in_cb := func(_r: Dictionary) -> void: inbox_fired["n"] = int(inbox_fired["n"]) + 1
		Net.social_inbox_result.connect(in_cb)
		Net.friend_request_result.emit({"ok": true})
		if Net.social_inbox_result.is_connected(in_cb):
			Net.social_inbox_result.disconnect(in_cb)
		Selftest.check("R8 ok refreshes inbox", int(inbox_fired["n"]) == 1)
		if Net.friend_request_result.is_connected(bound):
			Net.friend_request_result.disconnect(bound)
		if g._online._toast_stack != null:
			while g._online._toast_stack.get_child_count() > stack_before:
				var last := g._online._toast_stack.get_child(g._online._toast_stack.get_child_count() - 1)
				g._online._toast_stack.remove_child(last)
				last.queue_free()
