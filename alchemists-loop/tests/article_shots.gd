extends Node
## Скретч-риг статьи-путеводителя: снимает реальные экраны как иллюстрации
## (docs/articles/images/art-*.png), затем сидирует сам md в «Вестник» и
## снимает, как статья выглядит в модалке (captures/preview/article-*.png).
## Запуск (ОКНО, не --headless):
##   "<Godot_console.exe>" --path . --scene res://tests/article_shots.tscn
## После приёмки файл удалить (скретч).

var g: Game

const IMG_DIR := "C:/Users/nkucherenko/agent-coding/docs/articles/images/"
const MD_PATH := "C:/Users/nkucherenko/agent-coding/docs/articles/alchemists-loop-current-features.md"
const PREVIEW := "C:/Users/nkucherenko/agent-coding/captures/preview/"


func _ready() -> void:
	g = load("res://main.tscn").instantiate() as Game
	add_child(g)
	g._saves._save_frozen = true
	for i in 3:
		await get_tree().process_frame
	if g._shop != null and g._shop.has_method("_close_consent"):
		g._shop._close_consent()
		await get_tree().create_timer(0.2).timeout
	g._online._net_enabled = false

	g._bottom_nav._on_pressed("lab")
	await _settle()
	await _img("art-lab")
	g._rooms.set_room(1)
	await get_tree().create_timer(0.9).timeout
	await _settle()
	await _img("art-room2")
	g._rooms.set_room(0)
	await get_tree().create_timer(0.9).timeout
	await _settle()
	g._bottom_nav._on_pressed("world")
	await _settle()
	await _img("art-world")
	g._home._open_house_screen()
	await _settle()
	await _img("art-house")
	g._home._close_house_screen()
	await _settle()

	var md := FileAccess.get_file_as_string(MD_PATH)
	for url in News.image_urls(md):
		var im := Image.load_from_file(IMG_DIR + url.get_file())
		if im != null:
			News.save_cached(url, im)
	g._bottom_nav._on_pressed("tools")
	await _settle()
	g._open_news()
	await _settle()
	var esc := md.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
	var rss := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rss version=\"2.0\"><channel><title>Алхимический вестник</title><item><title>Мастерская алхимика: что уже работает</title><description>Путеводитель по текущей версии игры: комнаты, механики и как они связаны.</description><content:encoded>" + esc + "</content:encoded><pubDate>Wed, 12 Nov 2026 09:00:00 +0000</pubDate><guid>guide-1</guid><category>путеводитель</category></item></channel></rss>"
	g._news_ui.seed_rss(rss)
	await _settle()
	await _img("art-news")
	# Список только что снят — кладём его в кэш, чтобы картинка в статье совпала.
	var news_im := Image.load_from_file(IMG_DIR + "art-news.png")
	if news_im != null:
		News.save_cached("images/art-news.png", news_im)
	var card0 := g._news_ui._cards.find_child("NewsCard_0", true, false) as Control
	if card0 != null:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		card0.gui_input.emit(ev)
	await _settle()
	_diag("a1")
	await _shot("article-1")
	var sc := g._news_ui._article_scroll
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value * 0.45)
	await _settle()
	await _shot("article-2")
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	await _settle()
	await _settle()
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	await _settle()
	_diag("a3")
	await _shot("article-3")
	get_tree().quit(0)


func _diag(tag: String) -> void:
	var ui := g._news_ui
	var panel := ui._screen.find_child("NewsPanel", true, false) as Control
	print("DIAG ", tag,
		" base=", Net.base_url,
		" list_vis=", ui._scroll.visible,
		" art_vis=", ui._article_scroll.visible,
		" sv=", ui._article_scroll.scroll_vertical,
		" max=", ui._article_scroll.get_v_scroll_bar().max_value,
		" items=", ui._items.size(),
		" cards=", ui._cards.get_child_count(),
		" panel=", panel.get_global_rect(),
		" art_rect=", ui._article_scroll.get_global_rect(),
		" list_rect=", ui._scroll.get_global_rect(),
		" body=", ui._article_body.size,
		" vp=", get_viewport().size)


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _img(label: String) -> void:
	await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	print("ART_IMG ", label, " ok=", im.save_png(IMG_DIR + label + ".png"))


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	print("ART_SHOT ", label, " ok=", im.save_png(PREVIEW + label + ".png"))