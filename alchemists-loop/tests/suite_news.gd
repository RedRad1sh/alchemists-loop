extends RefCounted
class_name SuiteNews
# «Новости»: чистые News.parse_rss/format_date + модалка NewsUI во вкладке
# «Ещё». Герметично: ответы сидируем напрямую (паттерн social-рига), сеть не
# трогаем. Мутации, красящие блок: сломать разбор item/экранирование, убрать
# error-состояние или «Повторить», поставить шапке StyleBoxTexture, сбить
# кегли 16/14/11.

const RSS := """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Алхимический вестник</title>
<item><title>Ротация печатей &amp; огней</title><description>Смотрители сменили печати &lt;серные&gt;.</description><content:encoded># Вахта печатей

Серная ушла на покой, **медная** приняла вахту.
- вода теплее
- знаки отзываются
&gt; берегите эфир
![Печать](/api/news/images/1)</content:encoded><pubDate>Wed, 12 Nov 2026 09:00:00 +0000</pubDate><guid>news-1</guid><category>родник</category></item>
<item><title>Находка недели</title><description>Эфир и соль дают осадок.</description><pubDate>Mon, 10 Nov 2026 18:30:00 +0000</pubDate><guid>news-2</guid><category>находки</category></item>
<item><title>Ярмарка обменов</title><description>В пятницу у старой печи.</description><pubDate>Sat, 08 Nov 2026 12:00:00 +0000</pubDate><guid>news-3</guid><category>события</category></item>
</channel></rss>"""

const EMPTY_RSS := '<?xml version="1.0"?><rss version="2.0"><channel><title>Вестник</title></channel></rss>'

static func run(g: Game) -> void:
	_parse()
	_format()
	_md()
	_ui(g)
	await _article(g)

static func _parse() -> void:
	var items := News.parse_rss(RSS)
	Selftest.check("news parse: 3 items", items.size() == 3)
	if items.size() == 3:
		var a := items[0]
		Selftest.check("news parse: fields unescaped", String(a.get("title", "")) == "Ротация печатей & огней"
			and String(a.get("body", "")) == "Смотрители сменили печати <серные>."
			and String(a.get("tag", "")) == "родник"
			and String(a.get("date_raw", "")).contains("12 Nov 2026"))
		Selftest.check("news parse: order kept", String(items[2].get("title", "")) == "Ярмарка обменов")
		Selftest.check("news parse: content:encoded kept",
			String(a.get("content", "")).contains("**медная**")
			and String(a.get("content", "")).contains("![Печать](/api/news/images/1)")
			and String(a.get("content", "")).contains("> берегите эфир"))
	Selftest.check("news parse: garbage -> []", News.parse_rss("мусор").is_empty()
		and News.parse_rss("").is_empty()
		and News.parse_rss("<html><body>не rss</body></html>").is_empty())
	Selftest.check("news parse: empty channel -> []", News.parse_rss(EMPTY_RSS).is_empty())

static func _format() -> void:
	Selftest.check("news date: 12 ноября", News.format_date("Wed, 12 Nov 2026 09:00:00 +0000") == "12 ноября")
	Selftest.check("news date: 1 мая", News.format_date("Fri, 01 May 2026 00:00:00 GMT") == "1 мая")
	Selftest.check("news date: garbage -> empty", News.format_date("мусор") == ""
		and News.format_date("") == "" and News.format_date("32 Smth 2026") == "")

static func _ui(g: Game) -> void:
	g._tabs_ref.current_tab = Game.TAB_TOOLS
	var btn := g.find_child("NewsOpenButton", true, false) as Button
	Selftest.check("news button lives in tools tab", btn != null)
	if btn == null:
		return
	btn.pressed.emit()
	var ui = g.get("_news_ui")
	Selftest.check("news modal opens from tools", ui != null and ui.is_open())
	if ui == null:
		return
	Selftest.check("news modal starts loading", ui._status.text == "Достаём свитки…")
	ui.seed_rss(RSS)
	var cards: Array = ui._cards.find_children("NewsCard_*", "", true, false)
	Selftest.check("news cards render", cards.size() == 3)
	if cards.size() == 3:
		var card: Control = cards[0]
		var title := card.find_child("NewsTitle", true, false) as Label
		var body := card.find_child("NewsBody", true, false) as Label
		var date := card.find_child("NewsDate", true, false) as Label
		var tag := card.find_child("NewsTag", true, false) as Label
		Selftest.check("news card font sizes 16/14/11", title != null and body != null
			and date != null and tag != null
			and title.get_theme_font_size("font_size") == 16
			and body.get_theme_font_size("font_size") == 14
			and date.get_theme_font_size("font_size") == 11
			and tag.get_theme_font_size("font_size") == 11)
		Selftest.check("news card date formatted", date != null and date.text == "12 ноября")
		Selftest.check("news card tag chip", tag != null and tag.text == "родник")
	var header := ui._screen.find_child("NewsHeader", true, false) as PanelContainer
	Selftest.check("news header is flat StyleBoxFlat", header != null
		and header.get_theme_stylebox("panel") is StyleBoxFlat
		and not (header.get_theme_stylebox("panel") is StyleBoxTexture))
	# F1: повторный сид из-под сигнала не плодит дубли и не free()ит эмиттера.
	ui.seed_rss(RSS)
	Selftest.check("news rebuild keeps exactly 3 cards",
		ui._cards.find_children("NewsCard_*", "", true, false).size() == 3)
	# Ошибка и «Повторить».
	ui.seed_error()
	Selftest.check("news error state", ui._status.text == "Вестник не дошёл. Проверь связь."
		and ui._retry.visible)
	var before: int = ui.request_count
	ui._retry.pressed.emit()
	Selftest.check("news retry re-requests", ui.request_count == before + 1
		and ui._status.text == "Достаём свитки…")
	# Пустой канал и мусор.
	ui.seed_rss(EMPTY_RSS)
	Selftest.check("news empty state", ui._status.text == "Пока тихо…")
	ui.seed_rss("<rss><broken")
	Selftest.check("news garbage response -> error", ui._status.text == "Вестник не дошёл. Проверь связь.")
	# Закрытие возвращает во «Ещё».
	var close_b := ui._screen.find_child("NewsClose", true, false) as Button
	Selftest.check("news close button exists", close_b != null)
	if close_b != null:
		close_b.pressed.emit()
	Selftest.check("news close returns to tools", not ui.is_open()
		and g._tabs_ref.current_tab == Game.TAB_TOOLS)

static func _md() -> void:
	var resolve := func(_url: String) -> String: return "user://news_img/x.png"
	var bb := News.md_to_bbcode(
		"# Заголовок\n\nТекст **жир** и *кур*.\n- пункт\n> цитата\n![Печать](/api/news/images/1)",
		resolve)
	Selftest.check("news md: heading styled",
		bb.contains("[font_size=20]") and bb.contains("[color=#E5BC70]"))
	Selftest.check("news md: bold/italic", bb.contains("[b]жир[/b]") and bb.contains("[i]кур[/i]"))
	Selftest.check("news md: bullet", bb.contains("•  пункт"))
	Selftest.check("news md: quote", bb.contains("[i]цитата[/i]"))
	Selftest.check("news md: brackets escaped", News.md_to_bbcode("[b]", resolve).contains("[lb]b[rb]"))
	Selftest.check("news md: image resolved", bb.contains("[img=360]user://news_img/x.png[/img]"))
	var bb2 := News.md_to_bbcode("![Печать](/api/news/images/1)",
		func(_u: String) -> String: return "")
	Selftest.check("news md: unresolved image -> alt",
		not bb2.contains("[img=") and bb2.contains("Печать"))
	var urls := News.image_urls("![a](/api/news/images/1)\nтекст\n![b](http://x/i.png)")
	Selftest.check("news md: image_urls", urls.size() == 2
		and urls[0] == "/api/news/images/1" and urls[1] == "http://x/i.png")
	Selftest.check("news md: cache_path stable",
		News.cache_path("/api/news/images/1") == News.cache_path("/api/news/images/1")
		and News.cache_path("/api/news/images/1").begins_with("user://news_img/"))

static func _article(g: Game) -> void:
	g._tabs_ref.current_tab = Game.TAB_TOOLS
	var btn := g.find_child("NewsOpenButton", true, false) as Button
	if btn == null:
		Selftest.check("news article: open button exists", false)
		return
	btn.pressed.emit()
	var ui = g.get("_news_ui")
	if ui == null:
		Selftest.check("news article: ui exists", false)
		return
	ui.seed_rss(RSS)
	var cards: Array = ui._cards.find_children("NewsCard_*", "", true, false)
	if cards.is_empty():
		Selftest.check("news article: cards exist", false)
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(cards[0] as Control).gui_input.emit(click)
	Selftest.check("news article opens on card click",
		ui._article_scroll.visible and not ui._scroll.visible)
	# Иначе хвост статьи (последние строки при max scroll) уходит под бар.
	Selftest.check("news modal above bottom nav",
		ui._screen.z_index > g._bottom_nav.bar.z_index)
	var body := ui._article_scroll.find_child("NewsArticleBody", true, false) as RichTextLabel
	Selftest.check("news article body is bbcode RichTextLabel", body != null and body.bbcode_enabled)
	# Колонка статьи обязана занимать ширину панели, а не схлопываться до
	# минимума кнопки «Назад»: иначе текст рвётся по слову и [img] режется.
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	Selftest.check("news article body fills panel width",
		body != null and body.size.x >= ui._article_scroll.size.x - 8.0)
	if body != null:
		Selftest.check("news article md rendered",
			body.text.contains("[b]") and body.get_parsed_text().contains("медная"))
	var title := ui._article_scroll.find_child("NewsArticleTitle", true, false) as Label
	Selftest.check("news article title", title != null and title.text == "Ротация печатей & огней")
	# Картинка из кэша: кладём файл вручную — рендер обязан подставить [img=…].
	var cache := News.cache_path("/api/news/images/1")
	if cache != "":
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		News.save_cached("/api/news/images/1", img)
	if not ui._items.is_empty():
		ui._render_article(ui._items[0])
	Selftest.check("news article cached image", body != null and body.text.contains("[img="))
	var back_b := ui._article_scroll.find_child("NewsBack", true, false) as Button
	Selftest.check("news article back button exists", back_b != null)
	var before: int = ui.request_count
	if back_b != null:
		back_b.pressed.emit()
	Selftest.check("news article back returns to list",
		ui._scroll.visible and not ui._article_scroll.visible and ui.request_count == before)
	ui.close()