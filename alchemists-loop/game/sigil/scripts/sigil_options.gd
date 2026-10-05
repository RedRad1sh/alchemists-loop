class_name SigilOptions
extends RefCounted

## Настройки рендера карточки. Входят в ключ кэша: смена любого поля
## даёт новый PNG, даже при том же рецепте.

enum Mode { COMPLETED, DRAFT }
enum GlyphRotation { UPRIGHT, RADIAL, RANDOM }

var card_size: Vector2i = Vector2i(512, 683)
var show_name: bool = true
var name_text: String = ""
var name_font_size: int = 30
var show_frame: bool = true
var frame_margin: float = 16.0
var frame_style: int = 0
## Доля радиуса круга, которую занимает центральный объект. 0.58 — объект
## становится главной точкой карточки; ниже 0.45 он теряется в круге.
var icon_ratio: float = 0.58
## Центральный объект поверх круга. Превью в меню крафтов рисует круг без
## объекта: на 280 px иконка превращается в шум. Полноразмерная карта — с ней.
var show_icon: bool = true
var pixel_grid: int = 0
var mode: int = Mode.COMPLETED
var glyph_rotation: int = GlyphRotation.RADIAL
var ring_count: int = 3
var render_scale: int = 1
var fluid_enabled: bool = true
var fluid_cpu_fallback: bool = false
var aura_enabled: bool = true
var save_png: bool = true
## Сторона PNG центрального элемента, когда рендерят иконку отдельно
## от карточки. На саму карточку не влияет.
var icon_size: int = 256


static func make(p: Dictionary = {}) -> SigilOptions:
	var o := new()
	if p.has("card_size"):
		var s: Vector2 = p["card_size"]
		o.card_size = Vector2i(int(s.x), int(s.y))
	o.show_name = bool(p.get("show_name", o.show_name))
	o.name_text = str(p.get("name_text", ""))
	o.name_font_size = int(p.get("name_font_size", o.name_font_size))
	o.show_frame = bool(p.get("show_frame", o.show_frame))
	o.icon_size = int(p.get("icon_size", o.icon_size))
	o.frame_margin = float(p.get("frame_margin", o.frame_margin))
	o.frame_style = int(p.get("frame_style", o.frame_style))
	o.icon_ratio = clampf(float(p.get("icon_ratio", o.icon_ratio)), 0.20, 0.85)
	o.show_icon = bool(p.get("show_icon", o.show_icon))
	o.pixel_grid = int(p.get("pixel_grid", 0))
	o.mode = int(p.get("mode", o.mode))
	o.glyph_rotation = int(p.get("glyph_rotation", o.glyph_rotation))
	o.ring_count = clampi(int(p.get("ring_count", o.ring_count)), 1, 5)
	o.render_scale = clampi(int(p.get("render_scale", o.render_scale)), 1, 4)
	o.fluid_enabled = bool(p.get("fluid_enabled", o.fluid_enabled))
	o.fluid_cpu_fallback = bool(p.get("fluid_cpu_fallback", o.fluid_cpu_fallback))
	o.aura_enabled = bool(p.get("aura_enabled", o.aura_enabled))
	o.save_png = bool(p.get("save_png", o.save_png))
	return o


func copy() -> SigilOptions:
	return make(to_dict())


func to_dict() -> Dictionary:
	return {
		"card_size": Vector2(card_size),
		"show_name": show_name, "name_text": name_text, "name_font_size": name_font_size,
		"show_frame": show_frame, "frame_margin": frame_margin, "frame_style": frame_style,
		"icon_ratio": icon_ratio, "pixel_grid": pixel_grid, "mode": mode,
		"show_icon": show_icon,
		"glyph_rotation": glyph_rotation, "ring_count": ring_count, "render_scale": render_scale,
		"fluid_enabled": fluid_enabled, "fluid_cpu_fallback": fluid_cpu_fallback,
		"aura_enabled": aura_enabled, "save_png": save_png,
	}


func cache_salt() -> String:
	return "|".join(PackedStringArray([
		"sz=%dx%d" % [card_size.x, card_size.y],
		"sc=%d" % render_scale,
		"nm=%d:%d" % [int(show_name), name_font_size],
		"fr=%d:%.1f:%d" % [int(show_frame), frame_margin, frame_style],
		"ic=%.3f:%d:%d" % [icon_ratio, pixel_grid, int(show_icon)],
		"md=%d" % mode,
		"gr=%d" % glyph_rotation,
		"rc=%d" % ring_count,
		"fl=%d%d" % [int(fluid_enabled), int(fluid_cpu_fallback)],
		"au=%d" % int(aura_enabled),
	]))


func effective_size() -> Vector2:
	return Vector2(card_size) * float(maxi(render_scale, 1))


func title_band_height() -> float:
	return float(name_font_size) * 2.2 + 30.0


func title_rect() -> Rect2:
	var s := effective_size()
	var h := title_band_height()
	return Rect2(0.0, s.y - h, s.x, h)


func art_rect() -> Rect2:
	var s := effective_size()
	var h := title_band_height()
	return Rect2(0.0, 0.0, s.x, s.y - h)


## Геометрия, общая для всех слоёв.
func circle_rect() -> Rect2:
	var name_h := title_band_height() if show_name else 0.0
	var s := effective_size()
	var area := Rect2(frame_margin, frame_margin,
		s.x - frame_margin * 2.0, s.y - frame_margin * 2.0 - name_h)
	area = area.grow(-6.0)
	var r := minf(area.size.x, area.size.y) * 0.5
	# Центр круга — центр области арта (под полосой имени), а НЕ всей карты:
	# при 300x540 вертикальный центр карты сместил бы круг вниз (name_h вычитается).
	# Так круг ровно по центру видимой области, аура/глифы не съезжают.
	var center := Vector2(area.position.x + area.size.x * 0.5,
		area.position.y + area.size.y * 0.5)
	return Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0)
