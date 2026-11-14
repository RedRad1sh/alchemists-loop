extends Node
## Кадры консистентности нижних вкладок (претензии владельца 2026-11-12):
## «Друзья» того же размера и с той же рамкой, единый верхний отступ на всех
## вкладках, клик-анимация кнопок верхней панели. Плюс кадры переработки
## мессенджинга (msg-*): список с атрибуцией, лента с плашкой/футерами,
## стикер и pending, пикер, поиск not-found.
## Запуск (ОКНО, не --headless):
##   "<Godot_console.exe>" --path . --scene res://tests/ui_consistency_shots.tscn
## Вывод: captures/preview/consistency-*.png, затем get_tree().quit(0).

var g: Game


func _ready() -> void:
	g = load("res://main.tscn").instantiate() as Game
	add_child(g)
	# Реальный сейв читаем (в нём прогресс), но запись глушим: кадры не должны
	# трогать данные игрока.
	g._saves._save_frozen = true
	for i in 3:
		await get_tree().process_frame
	if g._shop != null and g._shop.has_method("_close_consent"):
		g._shop._close_consent()
		await get_tree().create_timer(0.2).timeout
	g._online._net_enabled = false

	# Мир и «Ещё»: содержимое должно стартовать с одной верхней линии.
	g._bottom_nav._on_pressed("world")
	await _settle()
	await _capture("consistency-world")
	g._bottom_nav._on_pressed("tools")
	await _settle()
	await _capture("consistency-tools")
	g._bottom_nav._on_pressed("rating")
	await _settle()
	await _capture("consistency-rating")

	# Друзья: размер и рамка как у остальных разделов.
	g._social._seed_demo()
	g._bottom_nav._on_pressed("friends")
	await _settle()
	await _capture("consistency-friends")

	# Переработка мессенджинга: атрибуция превью в списке, плашка шапки и
	# футеры ленты, стикер + pending, пикер эмодзи/стикеров, честный поиск.
	g._social.on_inbox({"ok": true, "friends": [
		{"device_id": "npc-spirit", "nick": "Светик", "unread": 0, "avatar": {},
			"last_seen": "", "last_msg_preview": "Я рядом, если что", "last_msg_from_me": false},
		{"device_id": "dev-b", "nick": "Николя", "unread": 2, "avatar": {},
			"last_seen": "2026-10-10T07:10:00", "last_msg_preview": "го к котлу", "last_msg_from_me": true},
		{"device_id": "dev-c", "nick": "Аня", "unread": 0, "avatar": {},
			"last_seen": "2026-10-09T21:00:00", "last_msg_preview": "Скинула печать, забери", "last_msg_from_me": false}],
		"incoming": [], "outgoing": [], "unread_total": 2, "requests_total": 0})
	g._social_ui._refresh_list()
	await _settle()
	await _capture("msg-list")
	g._social_ui._open_thread("dev-b")
	await _settle()
	await _capture("msg-thread")
	g._social.optimistic_send("dev-b", "ещё одно")
	var rows: Array = g._social.threads["dev-b"]
	rows.append({"id": 14, "from_me": true, "body": Social.sticker_body("hi"),
		"sent_at": "2026-10-10T07:20:00"})
	g._social_ui.refresh_thread()
	await _settle()
	# Новые пузыри внизу ленты — докручиваем, иначе кадр покажет только верх.
	var tsc := g._social_ui._thread_scroll
	tsc.scroll_vertical = int(tsc.get_v_scroll_bar().max_value)
	await _settle()
	await _capture("msg-sticker-pending")
	g._social.optimistic.erase("dev-b")
	g._social._seed_demo()
	g._social_ui.refresh_thread()
	await _settle()
	var pick_b := g._social_ui._body.find_child("PickerBtn", true, false) as Button
	if pick_b != null:
		pick_b.pressed.emit()
		await _settle()
		await _capture("msg-picker-emoji")
		var seg := g._social_ui._body.find_child("PickerSegments", true, false)
		if seg != null and seg.get_child_count() == 2:
			(seg.get_child(1) as Button).pressed.emit()
			await _settle()
			await _capture("msg-picker-stickers")
		g._social_ui._picker_hide()
	g._social_ui._close_thread()
	await _settle()
	g._social_ui._pending_search_nick = "Несуществующий"
	g._social_ui._err_line.text = "Ищем алхимика…"
	Net.house_result.emit({"ok": true, "found": false, "nick": "Несуществующий", "avatar": {}})
	await _settle()
	await _capture("msg-search-notfound")

	# Клик-анимация шапки И кнопок на цепях: покой -> сжатие -> возврат пружиной.
	# Главная вкладка («Стол»): только на ней видны боковые колонки на цепях
	# (sides.visible = tab == TAB_EXPERIMENT), поэтому снимаем именно здесь.
	g._bottom_nav._on_pressed("lab")
	await _settle()
	await _capture("consistency-hud-rest")
	var chip := g.find_child("EtherChip", true, false) as Button
	var chain_left := g._hub._up_btn as Button
	var chain_right := g.find_child("ShopBtn", true, false) as Button
	var pressed_buttons := []
	for b in [chip, chain_left, chain_right]:
		if b != null:
			pressed_buttons.append(b)
	for b in pressed_buttons:
		b.button_down.emit()
		var press := b.get_meta("press_tween") as Tween
		if press != null and press.is_valid():
			press.pause()
			press.custom_step(0.06)
		print("PRESS_SCALE ", b.name, " ", b.scale)
	await _capture("consistency-hud-press")
	for b in pressed_buttons:
		b.button_up.emit()
		var back := b.get_meta("press_tween") as Tween
		if back != null and back.is_valid():
			back.pause()
			back.custom_step(0.16)
		print("BACK_SCALE ", b.name, " ", b.scale)
	await _capture("consistency-hud-back")
	# Новости «Алхимического вестника»: сидированный RSS → модалка с
	# карточками; битый ответ → error-состояние с «Повторить». Данные сидим
	# напрямую (паттерн блока мессенджинга выше), сеть не трогаем.
	g._bottom_nav._on_pressed("tools")
	await _settle()
	g._open_news()
	await _settle()
	var news_rss := """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Алхимический вестник</title>
<item><title>Ротация печатей у родника</title><description>Смотрители сменили печати у родника: серная ушла на покой, медная приняла вахту. Вода отзывается на новые знаки чуть теплее обычного.</description><content:encoded># Вахта печатей

Смотрители сменили печати у родника: **серная** ушла на покой, **медная** приняла вахту.

- вода отзывается на новые знаки чуть теплее
- медь даёт двойные очки до воскресенья

&gt; Берегите эфир: подсказки экономят часы.

![Печать родника](/api/news/images/1)</content:encoded><pubDate>Wed, 12 Nov 2026 09:00:00 +0000</pubDate><guid>news-1</guid><category>родник</category></item>
<item><title>Найдена редкая пара: эфир и соль</title><description>Алхимик из северной мастерской сообщил о находке: эфир и соль дают устойчивый светящийся осадок. Гильдия просит присылать образцы котлов.</description><pubDate>Mon, 10 Nov 2026 18:30:00 +0000</pubDate><guid>news-2</guid><category>находки</category></item>
<item><title>Ярмарка обменов открывается в пятницу</title><description>В пятницу у старой печи откроется ярмарка обменов. Приносите лишние печати и склянки — меняем без пошлины, по-честному.</description><pubDate>Sat, 08 Nov 2026 12:00:00 +0000</pubDate><guid>news-3</guid><category>события</category></item>
<item><title>Светик советует: не жалейте эфира на подсказки</title><description>Дух родника напоминает: эфир копится сам, а подсказки экономят часы.</description><pubDate>Wed, 05 Nov 2026 08:00:00 +0000</pubDate><guid>news-4</guid><category>советы</category></item>
</channel></rss>"""
	g._news_ui.seed_rss(news_rss)
	await _settle()
	await _capture("news-modal")
	# Статья: картинку кладём в кэш (риг герметичен), открываем первую карточку.
	var sticker := load("res://assets/spirits/stickers_512/hi.png") as Texture2D
	if sticker != null:
		News.save_cached("/api/news/images/1", sticker.get_image())
	var card0 := g._news_ui._cards.find_child("NewsCard_0", true, false) as Control
	if card0 != null:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		card0.gui_input.emit(ev)
	await _settle()
	await _capture("news-article")
	g._news_ui._close_article()
	await _settle()
	g._news_ui.seed_error()
	await _settle()
	await _capture("news-error")
	g._news_ui.close()
	await _settle()
	get_tree().quit(0)


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/nkucherenko/agent-coding/captures/preview/" + label + ".png"
	print("CONSISTENCY_SHOT ", label, " ok=", img.save_png(path), " size=", img.get_size())