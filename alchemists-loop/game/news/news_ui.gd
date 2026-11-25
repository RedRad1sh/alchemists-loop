extends RefCounted
class_name NewsUI
# Модалка «Алхимический вестник» поверх вкладки «Ещё». Плоский минимализм:
# StyleBoxFlat с латунной кромкой, без рисованных «мыльных» плашек кита.
# Сеть — один HTTPRequest на Net.base_url + /api/news/rss (таймаут 8 с);
# ответы можно сидировать напрямую (seed_rss/seed_error) — так делают
# selftest и риг кадров. Пересборка карточек — remove_child + queue_free
# (F1: не free()ить эмиттера посреди сигнала).

const Kit = preload("res://game/ui/menu_kit.gd")
const TIMEOUT_SEC := 8.0

var g: Game
var _screen: Control = null
var _cards: VBoxContainer = null
var _scroll: ScrollContainer = null
var _article_scroll: ScrollContainer = null
var _status: Label = null
var _retry: Button = null
var _http: HTTPRequest = null
var _article_title: Label = null
var _article_body: RichTextLabel = null
var _current_article: Dictionary = {}
var _items: Array[Dictionary] = []
var request_count := 0

func _init(game: Game) -> void:
	g = game

func _flat(bg: Color, edge: Color, radius: int, mh: float, mv: float) -> StyleBoxFlat:
	var sb := UIStyle.box(bg, edge, radius, 1)
	sb.content_margin_left = mh
	sb.content_margin_right = mh
	sb.content_margin_top = mv
	sb.content_margin_bottom = mv
	return sb

func build() -> void:
	if _screen != null:
		return
	var root := Control.new()
	root.name = "NewsScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 21
	root.add_to_group("modal_ui")
	root.visible = false
	g.add_child(root)
	_screen = root
	var dim := ColorRect.new()
	dim.name = "NewsDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var panel := PanelContainer.new()
	panel.name = "NewsPanel"
	panel.add_theme_stylebox_override("panel",
		_flat(Color(0.12, 0.09, 0.07, 0.97), Color(0.85, 0.68, 0.40, 0.28), 10, 12, 12))
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	# Шапка: плоская тёмная панель с латунной кромкой, заголовок 16,
	# закрытие — тёмное дерево + иконка (не белая cta).
	var head := PanelContainer.new()
	head.name = "NewsHeader"
	head.add_theme_stylebox_override("panel",
		_flat(Color(0.17, 0.13, 0.09, 0.95), Color(0.85, 0.68, 0.40, 0.35), 8, 12, 8))
	box.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head.add_child(head_row)
	var title := g._label("Алхимический вестник", 16)
	title.name = "NewsHeaderTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_row.add_child(title)
	var close_b := g._icon_row_button("x", "Закрыть")
	close_b.name = "NewsClose"
	Kit.press_feedback(close_b)
	close_b.pressed.connect(close)
	head_row.add_child(close_b)
	# Состояния: загрузка / ошибка с «Повторить» / пусто.
	var state := VBoxContainer.new()
	state.name = "NewsState"
	state.add_theme_constant_override("separation", 8)
	box.add_child(state)
	_status = g._label("", 14)
	_status.name = "NewsStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	state.add_child(_status)
	_retry = g._small_button("Повторить", Vector2(140, 40), 0)
	_retry.name = "NewsRetry"
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Kit.press_feedback(_retry)
	_retry.pressed.connect(_start_request)
	_retry.visible = false
	state.add_child(_retry)
	# Тело: скролл с плоскими карточками новостей.
	var scroll := ScrollContainer.new()
	scroll.name = "NewsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.name = "NewsCards"
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 8)
	scroll.add_child(_cards)
	_scroll = scroll
	# Страница статьи: «Назад к списку» + заголовок + Markdown-тело (BBCode).
	_article_scroll = ScrollContainer.new()
	_article_scroll.name = "NewsArticleScroll"
	_article_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_article_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_article_scroll.visible = false
	box.add_child(_article_scroll)
	var abox := VBoxContainer.new()
	abox.name = "NewsArticleBox"
	abox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abox.add_theme_constant_override("separation", 8)
	_article_scroll.add_child(abox)
	var back := g._small_button("Назад к списку", Vector2(170, 40), 0)
	back.name = "NewsBack"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	Kit.press_feedback(back)
	back.pressed.connect(_close_article)
	abox.add_child(back)
	_article_title = g._label("", 18)
	_article_title.name = "NewsArticleTitle"
	_article_title.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	abox.add_child(_article_title)
	_article_body = RichTextLabel.new()
	_article_body.name = "NewsArticleBody"
	_article_body.bbcode_enabled = true
	_article_body.fit_content = true
	_article_body.scroll_active = false
	_article_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_article_body.add_theme_font_size_override("normal_font_size", 14)
	_article_body.add_theme_color_override("default_color", UIStyle.CREAM)
	abox.add_child(_article_body)
	_http = HTTPRequest.new()
	_http.name = "NewsHTTP"
	_http.timeout = TIMEOUT_SEC
	_http.request_completed.connect(_on_request_completed)
	root.add_child(_http)

func open() -> void:
	if _screen == null:
		build()
	_screen.visible = true
	_start_request()

func close() -> void:
	if _screen != null:
		_screen.visible = false
	Sfx.click()

func is_open() -> bool:
	return _screen != null and _screen.visible

## Запрос ленты. В герметичном прогоне (selftest) сеть не трогаем — ответ
## сидируется напрямую; счётчик запросов растёт в любом случае.
func _start_request() -> void:
	request_count += 1
	_clear_cards()
	if _article_scroll != null:
		_article_scroll.visible = false
	if _scroll != null:
		_scroll.visible = true
	_show_state("Достаём свитки…", false)
	if Net.base_url != "" and not SelftestMode.isolated():
		_http.request(Net.base_url + "/api/news/rss")

func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if _screen == null:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		seed_error()
		return
	_apply_xml(body.get_string_from_utf8())

## Прямой сид ответа (selftest/риг): тот же путь, что и успешный HTTP.
func seed_rss(xml: String) -> void:
	_apply_xml(xml)

func seed_error() -> void:
	_clear_cards()
	_show_state("Вестник не дошёл. Проверь связь.", true)

func _apply_xml(xml: String) -> void:
	var items := News.parse_rss(xml)
	if not items.is_empty():
		_render(items)
	elif News.is_valid_rss(xml):
		_clear_cards()
		_show_state("Пока тихо…", false)
	else:
		seed_error()

func _show_state(text: String, retry_visible: bool) -> void:
	_status.text = text
	_status.visible = true
	_retry.visible = retry_visible

func _clear_cards() -> void:
	if _cards == null:
		return
	# F1: пересборка идёт из signal-колбэков — мгновенный free() недопустим.
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()

func _render(items: Array[Dictionary]) -> void:
	_clear_cards()
	_items = items
	_status.visible = false
	_retry.visible = false
	var i := 0
	for item in items:
		_cards.add_child(_card(item, i))
		i += 1

func _on_card_input(event: InputEvent, item: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_open_article(item)

func _open_article(item: Dictionary) -> void:
	_scroll.visible = false
	_status.visible = false
	_retry.visible = false
	_article_scroll.visible = true
	_render_article(item)
	Sfx.click()

func _close_article() -> void:
	_article_scroll.visible = false
	_scroll.visible = true
	Sfx.click()

## Полная статья: Markdown → BBCode, картинки из кэша (user://news_img).
func _render_article(item: Dictionary) -> void:
	_current_article = item
	_article_title.text = String(item.get("title", ""))
	var md := String(item.get("content", ""))
	if md.strip_edges() == "":
		md = String(item.get("body", ""))
	_article_body.text = News.md_to_bbcode(md, _resolve_image)
	_article_scroll.scroll_vertical = 0
	_prefetch_images(md)

## Кэш есть → путь для [img]; нет → "" (markdown покажет alt-текст).
func _resolve_image(url: String) -> String:
	var path := News.cache_path(url)
	if FileAccess.file_exists(path):
		return path
	return ""

## Докачка картинок статьи. В герметичном прогоне сеть не трогаем.
func _prefetch_images(md: String) -> void:
	if SelftestMode.isolated() or Net.base_url == "" or _screen == null:
		return
	for url in News.image_urls(md):
		if FileAccess.file_exists(News.cache_path(url)):
			continue
		var full := url if url.begins_with("http") else Net.base_url + url
		var req := HTTPRequest.new()
		req.name = "NewsImgHTTP"
		req.timeout = TIMEOUT_SEC
		req.request_completed.connect(_on_image_downloaded.bind(url, req))
		_screen.add_child(req)
		req.request(full)

func _on_image_downloaded(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, url: String, req: HTTPRequest) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)
	if err != OK:
		return
	News.save_cached(url, img)
	if _article_scroll != null and _article_scroll.visible and not _current_article.is_empty():
		_render_article(_current_article)

func _card(item: Dictionary, idx: int) -> Control:
	var card := PanelContainer.new()
	card.name = "NewsCard_%d" % idx
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(item))
	card.add_theme_stylebox_override("panel",
		_flat(Color(0.15, 0.11, 0.08, 0.92), Color(0.85, 0.68, 0.40, 0.22), 8, 12, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	col.add_child(meta)
	var date := g._label(News.format_date(String(item.get("date_raw", ""))), 11)
	date.name = "NewsDate"
	date.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# В HBox autowrap-лейбл имеет нулевую минимальную ширину и схлопывается
	# в столбик по букве — дата и тег однострочные.
	date.autowrap_mode = TextServer.AUTOWRAP_OFF
	date.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	meta.add_child(date)
	var tag := g._label(String(item.get("tag", "")), 11)
	tag.name = "NewsTag"
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	tag.add_theme_stylebox_override("normal",
		_flat(Color(0.85, 0.68, 0.40, 0.12), Color(0.85, 0.68, 0.40, 0.35), 6, 6, 2))
	meta.add_child(tag)
	var title := g._label(String(item.get("title", "")), 16)
	title.name = "NewsTitle"
	col.add_child(title)
	var body := g._label(String(item.get("body", "")), 14)
	body.name = "NewsBody"
	body.add_theme_color_override("font_color", Color(UIStyle.CREAM, 0.92))
	col.add_child(body)
	var more := g._label("Читать далее →", 11)
	more.name = "NewsMore"
	more.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	col.add_child(more)
	return card