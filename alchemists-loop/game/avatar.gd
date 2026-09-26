# avatar.gd — процедурный аватар игрока.
#
# Детерминирован из строки-сида (ник игрока) по ТОМУ ЖЕ алгоритму, что на
# сервере (discovery-server/server/server.py: avatar_for). Поэтому аватар,
# присланный сервером, и локальная отрисовка всегда совпадают.
#
# Аватар = цветной круг + (опционально) кольцо-акцент + векторный символ.
# Рисуется кодом, без внешних ассетов.
class_name Avatar
extends Control

# Палитра построена по цветовому кругу: 10 оттенков через равные 36°,
# одинаковая насыщенность/светлота (S≈0.47, V≈0.80) — соседние цвета не
# сливаются, а набор в целом гармоничен (мягкий, но различимый).
const PALETTE: Array[Color] = [
	Color("#cc6c6c"), Color("#cca66c"), Color("#b9cc6c"), Color("#7fcc6c"), Color("#6ccc92"),
	Color("#6ccccc"), Color("#6c92cc"), Color("#7f6ccc"), Color("#b96ccc"), Color("#cc6ca6"),
]

var _bg := Color(0.5, 0.5, 0.55)
var _accent := Color(0.92, 0.92, 0.95)
var _sym := 0
var _ring := false
var _glyph := 0.56  # доля радиуса под символ

static func spec_for(seed: String) -> Dictionary:
	var hex: String = ("avatar_" + seed).sha256_text()
	var h0 := hex.substr(0, 2).hex_to_int()
	var h1 := hex.substr(2, 2).hex_to_int()
	var h2 := hex.substr(4, 2).hex_to_int()
	var h3 := hex.substr(6, 2).hex_to_int()
	var bg_idx := h0 % PALETTE.size()
	# Акцент — split-complementary по цветовому кругу: отступ 4..6 позиций
	# (144°..180°), чтобы символ/кольцо всегда контрастировали с фоном и не сливались.
	var accent_idx := (bg_idx + 4 + h1 % 3) % PALETTE.size()
	return {
		"bg": PALETTE[bg_idx],
		"accent": PALETTE[accent_idx],
		"sym": h2 % 12,
		"ring": (h3 & 1) == 1,
	}

func setup(seed: String, size_px: float) -> void:
	_apply(spec_for(seed), size_px)

# Из словаря сервера {bg: "#rrggbb", accent, sym, ring}
func setup_spec(spec: Dictionary, size_px: float) -> void:
	_apply({
		"bg": _hex(spec.get("bg", "#8a8f98")),
		"accent": _hex(spec.get("accent", "#e8e8ef")),
		"sym": int(spec.get("sym", 0)),
		"ring": bool(spec.get("ring", false)),
	}, size_px)

func _hex(v: Variant) -> Color:
	var s := String(v).strip_edges()
	if s.begins_with("#") and s.length() == 7:
		return Color(s)
	return Color(0.55, 0.55, 0.6)

func _apply(spec: Dictionary, size_px: float) -> void:
	_bg = spec["bg"]
	_accent = spec["accent"]
	_sym = int(spec["sym"])
	_ring = bool(spec["ring"])
	custom_minimum_size = Vector2(size_px, size_px)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_redraw()

func _draw() -> void:
	var d := minf(size.x, size.y)
	if d <= 0.0:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r := d * 0.5
	# фон — мягкий, с лёгким объёмом (блик сверху, тень снизу)
	draw_circle(c, r, _bg)
	draw_circle(c + Vector2(0, r * 0.55), r * 0.66, Color(0, 0, 0, 0.09))
	draw_circle(c + Vector2(-r * 0.30, -r * 0.34), r * 0.46, Color(1, 1, 1, 0.12))
	draw_circle(c + Vector2(-r * 0.16, -r * 0.20), r * 0.24, Color(1, 1, 1, 0.10))
	# ободок
	draw_arc(c, r - 0.5, 0, TAU, 40, Color(0, 0, 0, 0.18), 1.0, true)
	# внешнее кольцо-акцент (мягче)
	if _ring:
		draw_arc(c, r * 0.78, 0, TAU, 48, Color(_accent, 0.85), maxf(1.5, r * 0.15), true)
	# символ: мягкий акцент + лёгкая тень для глубины
	_draw_symbol(_sym, c + Vector2(r * 0.015, r * 0.03), r * _glyph, Color(0, 0, 0, 0.18))
	_draw_symbol(_sym, c, r * _glyph, _accent.lightened(0.06))

func _poly(pts: PackedVector2Array, col: Color) -> void:
	draw_colored_polygon(pts, col)

func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w, true)

func _draw_symbol(sym: int, c: Vector2, s: float, col: Color) -> void:
	match sym:
		0:  # ромб
			_poly(PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)
		1:  # звезда (5 лучей)
			_poly(_star_points(c, s, s * 0.45, 5), col)
		2:  # полумесяц
			draw_circle(c + Vector2(s * 0.22, 0), s * 0.82, col)
			draw_circle(c + Vector2(s * 0.5, 0), s * 0.74, _bg)
		3:  # капля
			draw_circle(c + Vector2(0, s * 0.28), s * 0.62, col)
			_poly(PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(-s * 0.62, s * 0.28), c + Vector2(s * 0.62, s * 0.28)]), col)
		4:  # пламя
			_poly(PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s * 0.62, s * 0.5),
				c + Vector2(s * 0.3, s * 0.9), c + Vector2(0, s),
				c + Vector2(-s * 0.3, s * 0.9), c + Vector2(-s * 0.62, s * 0.5)]), col)
		5:  # лист
			_poly(PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s * 0.72, s * 0.2),
				c + Vector2(0, s), c + Vector2(-s * 0.72, s * 0.2)]), col)
			_line(c + Vector2(0, -s), c + Vector2(0, s), _bg, maxf(1.0, s * 0.12))
		6:  # молния
			_poly(PackedVector2Array([
				c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.45, s * 0.15),
				c + Vector2(-s * 0.05, s * 0.15), c + Vector2(-s * 0.2, s),
				c + Vector2(s * 0.45, -s * 0.15), c + Vector2(s * 0.05, -s * 0.15)]), col)
		7:  # снежинка
			for ang in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
				var dir := Vector2(cos(ang), sin(ang))
				_line(c - dir * s, c + dir * s, col, maxf(1.0, s * 0.14))
		8:  # глаз
			draw_arc(c, s * 0.95, 0, TAU, 40, col, maxf(1.0, s * 0.14), true)
			draw_circle(c, s * 0.32, col)
			draw_circle(c + Vector2(s * 0.1, -s * 0.08), s * 0.1, Color(1, 1, 1, 0.9))
		9:  # сердце
			draw_circle(c + Vector2(-s * 0.34, -s * 0.3), s * 0.4, col)
			draw_circle(c + Vector2(s * 0.34, -s * 0.3), s * 0.4, col)
			_poly(PackedVector2Array([
				c + Vector2(-s * 0.68, -s * 0.1), c + Vector2(s * 0.68, -s * 0.1),
				c + Vector2(0, s)]), col)
		10:  # кольцо с точкой
			draw_arc(c, s * 0.85, 0, TAU, 40, col, maxf(1.0, s * 0.16), true)
			draw_circle(c, s * 0.22, col)
		11:  # волны
			_wave(c + Vector2(0, -s * 0.4), s, col)
			_wave(c + Vector2(0, s * 0.4), s, col)

func _star_points(c: Vector2, r_out: float, r_in: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var ang := -PI / 2.0 + PI * i / n
		var rr := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	return pts

func _wave(center: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var x := lerpf(-s, s, t)
		var y := sin(t * PI * 2.0) * s * 0.32
		pts.append(center + Vector2(x, y))
	draw_polyline(pts, col, maxf(1.0, s * 0.1), true)
