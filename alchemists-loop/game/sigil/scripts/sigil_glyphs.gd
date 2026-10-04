class_name SigilGlyphs
extends RefCounted

## Библиотека символов круга.
##
## Основной источник — ВЕКТОРНЫЙ: собственные контуры в JSON (tools/build_glyphs.py).
## Причина: глифы Unicode Alchemical Symbols (U+1F700–U+1F77F) отсутствуют в
## шрифтах, которые Godot берёт по умолчанию, и без подключения шрифта с
## покрытием блока на карточке будут пустые квадраты. Векторный набор также
## гарантирует одинаковый вид на всех платформах и не зависит от лицензии
## Newton Sans / любого другого шрифта.
##
## Шрифтовый источник остаётся опциональным: если проекту нужен именно
## Unicode-алфавит, вызови [method set_font_source] — и глифы с замапленными
## символами будут браться из шрифта, остальные — из контуров.

const DATA_REL := "data/alchemical_glyphs.json"

const UNICODE_FALLBACK := {
	"sun": "☉", "moon": "☽", "mercury": "☿", "sulfur": "🜍", "salt": "🜔",
	"fire": "🜂", "water": "🜄", "earth": "🜃", "air": "🜁", "antimony": "🜋",
	"gold": "🜆", "silver": "🜎", "vitriol": "🜖", "philosopher_stone": "🝆",
	"serpent": "♑", "eye": "☉", "infinity": "∞", "spiral": "🜚",
}

static var _cache: Dictionary = {}
static var _font: Font = null
static var _font_map: Dictionary = {}
static var _missing: bool = false


static func set_font_source(font: Font, map: Dictionary = {}) -> void:
	_font = font
	_font_map = map.duplicate()
	_font_map.merge(UNICODE_FALLBACK, true)


static func clear_font_source() -> void:
	_font = null
	_font_map = {}


static func library() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if _missing:
		return {}
	var path := SigilAssets.find(DATA_REL)
	if path != "":
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("glyphs"):
				_cache = (parsed as Dictionary)["glyphs"]
				return _cache
	push_warning("SigilGlyphs: не найден alchemical_glyphs.json, круг будет без символов.")
	_missing = true
	return {}


static func reload() -> void:
	_cache = {}
	_missing = false


static func has(glyph_name: String) -> bool:
	return library().has(glyph_name)


static func names() -> PackedStringArray:
	var lib := library()
	var out := PackedStringArray()
	for k in lib.keys():
		out.append(str(k))
	out.sort()
	return out


static func categories_of(glyph_name: String) -> PackedStringArray:
	var lib := library()
	if not lib.has(glyph_name):
		return PackedStringArray()
	var out := PackedStringArray()
	for c in (lib[glyph_name] as Dictionary).get("cat", []):
		out.append(str(c))
	return out


static func by_category(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n in names():
		if categories_of(n).has(category):
			out.append(n)
	return out


static func pick_glyph(rng: SigilRng, wanted: PackedStringArray) -> String:
	## Сначала ищем по категориям ингредиента, потом по всем глифам.
	for cat in wanted:
		var pool := by_category(cat)
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
	var all := names()
	if all.is_empty():
		return ""
	return all[rng.randi_range(0, all.size() - 1)]


# ------------------------------------------------------------------ отрисовка

static func draw_glyph(ci: CanvasItem, glyph_name: String, center: Vector2, size: float,
		rotation: float = 0.0, color: Color = Color.WHITE, width: float = 1.0) -> void:
	if _font != null and _font_map.has(glyph_name):
		draw_unicode(ci, glyph_name, center, size, rotation, color)
		return
	var lib := library()
	if not lib.has(glyph_name):
		return
	var gl: Dictionary = lib[glyph_name]
	var fill := bool(gl.get("fill", false))

	ci.draw_set_transform(center, rotation, Vector2.ONE)
	_to_local(ci, gl.get("c", []), size, color, width, Vector2.ZERO)
	for p in gl.get("l", []):
		ci.draw_polyline(_pts(p, size), color, width, true)
	for p in gl.get("p", []):
		var pts := _pts(p, size)
		if fill:
			ci.draw_colored_polygon(pts, color)
		else:
			ci.draw_polyline(SigilGeometry.closed(pts), color, width, true)
	for a in gl.get("a", []):
		ci.draw_arc(Vector2.ZERO, float(a[2]) * size, float(a[3]), float(a[4]), 28, color, width, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_unicode(ci: CanvasItem, glyph_name: String, center: Vector2, size: float,
		rotation: float, color: Color) -> void:
	if _font == null or not _font_map.has(glyph_name):
		return
	var ch: String = _font_map[glyph_name]
	if not _font.has_char(ch.unicode_at(0)):
		return
	ci.draw_set_transform(center, rotation, Vector2.ONE)
	var baseline := Vector2(-size * 0.5, size * 0.36)
	ci.draw_string(_font, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * 1.1), color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _pts(poly: Array, size: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2((float(p[0]) - 0.5) * size, (float(p[1]) - 0.5) * size))
	return out


static func _to_local(ci: CanvasItem, circles: Array, size: float, color: Color, width: float, _off: Vector2) -> void:
	for c in circles:
		ci.draw_arc(Vector2.ZERO, float(c[2]) * size, 0.0, TAU, 32, color, width, true)
