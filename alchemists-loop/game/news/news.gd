extends RefCounted
class_name News
# «Алхимический вестник»: чистые хелперы RSS (паттерн game/social/social.gd).
# Сеть живёт в NewsUI; здесь только разбор ленты и формат даты — static,
# чтобы selftest звал их без сборки Game.

const MONTHS_RU := ["января", "февраля", "марта", "апреля", "мая", "июня",
	"июля", "августа", "сентября", "октября", "ноября", "декабря"]
const MONTHS_EN := ["jan", "feb", "mar", "apr", "may", "jun",
	"jul", "aug", "sep", "oct", "nov", "dec"]

## RSS 2.0 → массив словарей {title, body, tag, date_raw, content}. body —
## краткое описание (description), content — полная статья (content:encoded).
## Мусор/пустой канал → []. XMLParser сам снимает экранирование (&amp; &lt; &gt;).
static func parse_rss(xml: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if xml.strip_edges() == "":
		return out
	var p := XMLParser.new()
	if p.open_buffer(xml.to_utf8_buffer()) != OK:
		return out
	var in_item := false
	var field := ""
	var cur := {}
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := p.get_node_name()
				if n == "item":
					in_item = true
					cur = {"title": "", "body": "", "tag": "", "date_raw": "", "content": ""}
				elif in_item:
					match n:
						"title": field = "title"
						"description": field = "body"
						"content:encoded": field = "content"
						"pubDate": field = "date_raw"
						"category": field = "tag"
						_: field = ""
			XMLParser.NODE_ELEMENT_END:
				var n := p.get_node_name()
				if n == "item":
					if in_item and String(cur.get("title", "")) != "":
						out.append(cur)
					in_item = false
					field = ""
				elif n == "title" or n == "description" or n == "pubDate" \
						or n == "category" or n == "content:encoded":
					field = ""
			XMLParser.NODE_TEXT:
				if in_item and field != "":
					cur[field] = String(cur.get(field, "")) + p.get_node_data()
	return out

## Отличает валидный пустой канал («Пока тихо…») от битого ответа (error).
## Требуем закрытый корень </rss>: XMLParser терпим к обрыву на EOF, и без
## этой проверки «<rss><broken» выглядел бы валидным пустым каналом.
static func is_valid_rss(xml: String) -> bool:
	var p := XMLParser.new()
	if p.open_buffer(xml.to_utf8_buffer()) != OK:
		return false
	var saw_rss := false
	var closed_rss := false
	while true:
		var err := p.read()
		if err == ERR_FILE_EOF:
			break
		if err != OK:
			return false
		if p.get_node_type() == XMLParser.NODE_ELEMENT and p.get_node_name() == "rss":
			saw_rss = true
		elif p.get_node_type() == XMLParser.NODE_ELEMENT_END and p.get_node_name() == "rss":
			closed_rss = true
	return saw_rss and closed_rss

## RFC822 («Wed, 12 Nov 2026 09:00:00 +0000») → «12 ноября». Мусор → "".
static func format_date(rfc822: String) -> String:
	var parts := rfc822.strip_edges().split(" ", false)
	if parts.size() < 4:
		return ""
	var day := int(parts[1])
	var month := MONTHS_EN.find(parts[2].to_lower().substr(0, 3))
	if day < 1 or day > 31 or month < 0:
		return ""
	return "%d %s" % [day, MONTHS_RU[month]]

## Markdown статьи → BBCode для RichTextLabel. Подмножество: заголовки
## #/##/###, **жирный**, *курсив*, списки «- », цитаты «> », картинки
## ![alt](url). resolve(url) → путь кэша или "" (тогда показываем alt).
## Литеральные [ ] экранируются в [lb]/[rb], чтобы не стать BBCode-тегами.
const IMG_WIDTH := 360
const HEAD_COLOR := "#E5BC70"
const QUOTE_COLOR := "#9a8f7f"

static func md_to_bbcode(md: String, resolve: Callable) -> String:
	var out: Array[String] = []
	for line in md.split("\n"):
		out.append(_md_line(line, resolve))
	return "\n".join(out)

static func _md_line(line: String, resolve: Callable) -> String:
	var s := line
	var prefix := ""
	var suffix := ""
	if s.begins_with("### "):
		s = s.substr(4)
		prefix = "[font_size=16][color=%s][b]" % HEAD_COLOR
		suffix = "[/b][/color][/font_size]"
	elif s.begins_with("## "):
		s = s.substr(3)
		prefix = "[font_size=18][color=%s][b]" % HEAD_COLOR
		suffix = "[/b][/color][/font_size]"
	elif s.begins_with("# "):
		s = s.substr(2)
		prefix = "[font_size=20][color=%s][b]" % HEAD_COLOR
		suffix = "[/b][/color][/font_size]"
	elif s.begins_with("> "):
		s = s.substr(2)
		prefix = "[color=%s][i]" % QUOTE_COLOR
		suffix = "[/i][/color]"
	elif s.begins_with("- "):
		s = "•  " + s.substr(2)
	return prefix + _md_inline(s, resolve) + suffix

static func _md_inline(s: String, resolve: Callable) -> String:
	# Картинки вынимаем ДО экранирования скобок: ![alt](url) → токен.
	var re_img := RegEx.new()
	re_img.compile("!\\[([^\\]]*)\\]\\(([^)]+)\\)")
	var tokens: Array[String] = []
	var matches := re_img.search_all(s)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var path := String(resolve.call(m.get_string(2)))
		var repl: String
		if path != "":
			repl = "[img=%d]%s[/img]" % [IMG_WIDTH, path]
		else:
			repl = "[color=%s]%s[/color]" % [QUOTE_COLOR, _escape_brackets(m.get_string(1))]
		s = s.substr(0, m.get_start()) + "\u0000%d\u0000" % tokens.size() + s.substr(m.get_end())
		tokens.append(repl)
	s = _escape_brackets(s)
	s = _re_replace(s, "\\*\\*([^*]+)\\*\\*", "[b]$1[/b]")
	s = _re_replace(s, "\\*([^*]+)\\*", "[i]$1[/i]")
	for i in tokens.size():
		s = s.replace("\u0000%d\u0000" % i, tokens[i])
	return s

static func _escape_brackets(s: String) -> String:
	# Sentinel-проход: прямая замена «[»→«[lb]» портит последующую замену
	# «]», т.к. вставленный «[lb]» сам содержит «]».
	return s.replace("[", "\u0001").replace("]", "\u0002") \
		.replace("\u0001", "[lb]").replace("\u0002", "[rb]")

static func _re_replace(s: String, pattern: String, repl: String) -> String:
	var re := RegEx.new()
	re.compile(pattern)
	var matches := re.search_all(s)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		s = s.substr(0, m.get_start()) + repl.replace("$1", m.get_string(1)) + s.substr(m.get_end())
	return s

## URL картинок из markdown (порядок появления, с дублями).
static func image_urls(md: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("!\\[[^\\]]*\\]\\(([^)]+)\\)")
	for m in re.search_all(md):
		out.append(m.get_string(1))
	return out

## Путь кэша картинки: user://news_img/<md5(url)>.tres. Именно .tres
## (ImageTexture), а не сырой PNG: ResourceLoader грузит из user:// только
## ресурсы, сырой PNG RichTextLabel в [img] не видит.
static func cache_path(url: String) -> String:
	return "user://news_img/%s.tres" % url.md5_text()

## Кладёт картинку в кэш как ImageTexture (.tres).
static func save_cached(url: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute("user://news_img")
	ResourceSaver.save(ImageTexture.create_from_image(img), cache_path(url))