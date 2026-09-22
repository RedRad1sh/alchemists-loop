class_name CreatureVisual
extends Node2D
# Процедурное существо: НИ ОДНОГО спрайта. Рисуется кодом по фенотипу.
# «Желейный» объём: мягкие радиальные градиенты (Art.soft).
# Визуальные вехи по стадиям:
#   stage>=2 «Колония»  — клетки-спутники вокруг (почкование)
#   stage>=3            — усики-антенны на голове
#   pattern>=2          — полосы поперёк тела (зебра)
#   spikes>0 (хитин)    — графитовые пластины-«крышечки» + янтарные шипы
#   stage>=6 «Венец»    — вращающееся золотое кольцо-орбита
#   stage>=7            — второе кольцо + усиление
#   glow>1.8 «легенда»  — многослойная аура + кольца + лучи + искры

const MORPH_TIME := 1.1
const INT_KEYS := ["segments", "eyes", "tail", "spikes", "pattern", "seed", "stage", "gene_count"]

var _cur: Dictionary = PhenotypeEngine.default_pheno()
var _from: Dictionary = {}
var _to: Dictionary = {}
var _morph_t := 1.0
var _time := 0.0
var _bounce := 0.0

func _ready() -> void:
	_cur = PhenotypeEngine.default_pheno()
	_to = _cur.duplicate(true)
	_from = _cur.duplicate(true)

func current_pheno() -> Dictionary:
	if _morph_t >= 1.0:
		return _to
	return _interp(_from, _to, _morph_t)

func set_genome_ids(ids: Array) -> void:
	_from = current_pheno()
	_to = PhenotypeEngine.compute(ids)
	_morph_t = 0.0
	queue_redraw()

func bounce() -> void:
	_bounce = 1.0

func _process(delta: float) -> void:
	_time += delta
	if _morph_t < 1.0:
		_morph_t = minf(_morph_t + delta / MORPH_TIME, 1.0)
	if _bounce > 0.0:
		_bounce = maxf(_bounce - delta * 2.4, 0.0)
	queue_redraw()

# ---------- интерполяция фенотипов (морф) ----------

func _interp(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out: Dictionary = {}
	for k in b.keys():
		var va = a.get(k)
		var vb = b[k]
		if va == null:
			out[k] = vb
		elif typeof(va) == TYPE_COLOR and typeof(vb) == TYPE_COLOR:
			out[k] = (va as Color).lerp(vb as Color, t)
		elif typeof(va) == TYPE_FLOAT and typeof(vb) == TYPE_FLOAT:
			out[k] = lerpf(va as float, vb as float, t)
		elif INT_KEYS.has(k):
			out[k] = va if t < 0.5 else vb
		else:
			out[k] = vb
	return out

# ---------- «желейные» примитивы ----------

func _soft(pos: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(Art.soft(),
		Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, color)

func _jelly(pos: Vector2, radius: float, color: Color) -> void:
	# тело-желе: полупрозрачные края + внутренний свет + нижняя тень + блик
	_soft(pos, radius, Color(color.r, color.g, color.b, 0.95))
	_soft(pos, radius * 0.45, Color(1, 1, 1, 0.13))
	_soft(pos + Vector2(0, radius * 0.33), radius * 0.9, Color(0, 0, 0, 0.14))
	_soft(pos + Vector2(-radius * 0.32, -radius * 0.34), radius * 0.5,
		Color(1, 1, 1, 0.28))

# ---------- отрисовка ----------

func _draw() -> void:
	var p := current_pheno()
	if p.is_empty():
		return
	var s := 1.0 + 0.16 * _bounce
	var size: float = clampf(p["size"], 0.5, 3.2) * s
	var segs: int = p["segments"]
	var col1: Color = p["color1"]
	var col2: Color = p["color2"]
	var glow: float = clampf(p["glow"], 0.0, 2.8)
	var seed: int = p["seed"]
	var stage: int = p["stage"]
	var pulse: float = clampf(p["pulse"], 1.0, 2.6)

	var u := 44.0 * size
	var spine_len := u * (2.0 + float(segs) * 0.85)
	var max_len := 560.0
	if spine_len > max_len:
		u = u * max_len / spine_len
		spine_len = max_len

	var center := Vector2.ZERO
	var col_glow := Color8(120, 255, 215).lerp(col1, 0.35).lerp(col2, 0.25)
	var breath := 0.5 + 0.5 * sin(_time * 2.2)

	# --- мягкое свечение вокруг существа ---
	if glow > 0.03:
		_soft(center, u * (1.8 + 1.1 * glow) * (1.0 + 0.07 * sin(_time * 1.8)),
			Color(col_glow.r, col_glow.g, col_glow.b, 0.05 + 0.05 * glow))
		_soft(center, u * (0.9 + 0.6 * glow) * (1.0 + 0.07 * sin(_time * 1.8 + 1.0)),
			Color(col_glow.r, col_glow.g, col_glow.b, 0.06 + 0.05 * glow))

	# --- тень на «дне» ---
	_soft(Vector2(0, u * 1.5), u * 1.2, Color(0, 0, 0, 0.22))

	if segs <= 1:
		_draw_cell(p, u, seed, col1, col2, pulse)
	else:
		_draw_worm(p, u, spine_len, segs, seed, col1, col2, pulse)

	# глаза — поверх всего
	if p["eyes"] > 0:
		_draw_eyes(p, u, segs, glow)

	# --- легендарная аура (quantum_aura): кольца + лучи + искры ---
	if glow > 1.8:
		_draw_legend_aura(u, spine_len, col_glow)

	# --- «Венец творения»: золотые кольца-орбиты ---
	if stage >= 6:
		_draw_crown_rings(stage, u, spine_len, breath)

# ---------- формы ----------

func _spine_pos(t: float, u: float, spine_len: float) -> Vector2:
	var x := lerpf(-spine_len * 0.5, spine_len * 0.5, t)
	var y := sin(x * 0.011 + _time * 2.8) * u * 0.20
	return Vector2(x, y)

func _rad_at(t: float, u: float) -> float:
	return u * (0.42 + 0.5 * t)

# ---------- клетка ----------

func _draw_cell(p: Dictionary, u: float, seed: int, col1: Color, col2: Color, pulse: float) -> void:
	var r := u * (1.0 + 0.075 * sin(_time * 3.2 * pulse))
	var stage: int = p["stage"]

	# клетки-спутники (колония) — позади основной
	if stage >= 2:
		var n := 3 + mini(stage - 2, 2)
		for k in n:
			var ang := TAU * float(k) / float(n) + _time * 0.45
			var srad := r * (1.75 + 0.25 * sin(_time * 1.3 + float(k)))
			var spos := Vector2(cos(ang), sin(ang)) * srad
			draw_line(spos, Vector2.ZERO, Color(col2.r, col2.g, col2.b, 0.18),
				maxf(u * 0.04, 1.0))   # мостик цитоплазмы
			_soft(spos, r * 0.42, Color(col2.r, col2.g, col2.b, 0.75))
			_soft(spos + Vector2(0, r * 0.14), r * 0.38, Color(0, 0, 0, 0.12))
			_soft(spos + Vector2(-r * 0.10, -r * 0.12), r * 0.16, Color(1, 1, 1, 0.20))
			_soft(spos, r * 0.18, Color(1, 1, 1, 0.10))

	# тело клетки
	_jelly(Vector2.ZERO, r, col1)
	# ядро
	_soft(Vector2.ZERO, r * 0.55, col2)
	_soft(Vector2(-r * 0.15, -r * 0.15), r * 0.3, Color(1, 1, 1, 0.18))
	# органеллы
	for k in 5:
		var ang := TAU * float(k) / 5.0 + float(seed % 9) * 0.4 + _time * 0.1
		var org := Vector2(cos(ang), sin(ang)) * r * 0.34
		_soft(org, r * 0.11, Color(col2.r, col2.g, col2.b, 0.45))

	# узор: пятна
	var pattern: int = p["pattern"]
	if pattern > 0:
		var dots := 6 + pattern * 3
		for k in dots:
			var ang := TAU * float(k) / float(dots) + float(seed % 40) * 0.1
			var pr := r * (0.46 + 0.10 * sin(float(seed % 7) + float(k)))
			_soft(Vector2(cos(ang), sin(ang)) * pr, r * 0.17,
				Color(1, 1, 1, 0.12 + 0.05 * float(pattern)))

	# хитиновые шипы-лучи (радиолярия)
	var spikes: int = p["spikes"]
	if spikes > 0:
		var armored := Color8(44, 58, 72)
		# тёмное внутреннее кольцо-«панцирь»
		_soft(Vector2.ZERO, r * 1.12, Color(armored.r, armored.g, armored.b, 0.55))
		draw_arc(Vector2.ZERO, r * 1.08, 0, TAU, 48, Color(0.55, 0.65, 0.72, 0.5), 5.0)
		var n := 10 + mini(spikes * 2, 14)
		for k in n:
			var ang := TAU * float(k) / float(n) + _time * 0.25
			var dir := Vector2(cos(ang), sin(ang))
			var base := dir * (r * 1.06)
			var tip := dir * (r + u * 0.34)
			draw_colored_polygon(PackedVector2Array(
				[base, base + dir.orthogonal() * u * 0.075, tip]), Color8(255, 196, 110))
			_soft(tip, u * 0.06, Color(1, 1, 1, 0.5))
		_jelly(Vector2.ZERO, r * 0.92, col1.darkened(0.2))

	# жгутики или реснички
	var tail: int = p["tail"]
	if tail > 0:
		for j in tail:
			var off_y := lerpf(-u * 0.22, u * 0.22, float(j) / float(tail))
			_tail_chain(Vector2(-r * 0.7, off_y), u, j, col2)
	else:
		var cilia := 14
		for a in cilia:
			var ang := TAU * float(a) / float(cilia)
			var dir := Vector2(cos(ang), sin(ang))
			var p0 := dir * (r * 0.92)
			var len_c := u * (0.14 + 0.07 * sin(_time * 4.0 + float(a)))
			_soft(p0 + dir * len_c * 0.5, u * 0.05, Color(col1.r, col1.g, col1.b, 0.35))

# ---------- червь ----------

func _draw_worm(p: Dictionary, u: float, spine_len: float, segs: int, seed: int,
		col1: Color, col2: Color, pulse: float) -> void:
	var stage: int = p["stage"]
	var spikes: int = p["spikes"]
	var armored := spikes > 0
	# цвета хитина: холодный графит с сохранением оттенка
	var body1 := col1 if not armored else col1.lerp(Color8(56, 72, 92), 0.55)
	var body2 := col2 if not armored else col2.lerp(Color8(40, 54, 72), 0.65)
	var plate_col := body1.lightened(0.10)
	var plate_edge := Color(0.75, 0.85, 0.95, 0.35)
	var amber := Color8(255, 200, 120)

	# хвосты-жгутики — позади тела
	var tail: int = p["tail"]
	if tail > 0:
		var rear := _spine_pos(0.02, u, spine_len)
		for j in tail:
			var off_y := lerpf(-u * 0.2, u * 0.2, float(j) / float(tail))
			_tail_chain(rear + Vector2(0, off_y), u, j, body2)

	# сегменты (хвост -> голова)
	for i in segs:
		var t := float(i) / float(maxi(segs - 1, 1))
		var pos := _spine_pos(t, u, spine_len)
		var rad := _rad_at(t, u) * (1.0 + 0.055 * sin(_time * 3.4 * pulse + float(i)))
		var col := body2.lerp(body1, t)
		var lum := 0.5 + 0.5 * sin(_time * 2.2 + float(i) * 0.9)
		_jelly(pos, rad, col.lightened(0.05 * lum))

	# узор-полосы (зебра, pattern>=2) поверх сегментов
	var pattern: int = p["pattern"]
	if pattern >= 2:
		for i in range(segs):
			if i % 2 == 0:
				continue
			var t := float(i) / float(maxi(segs - 1, 1))
			var pos := _spine_pos(t, u, spine_len)
			var rad := _rad_at(t, u)
			draw_arc(pos, rad * 0.98, 0, TAU, 20,
				Color(1, 1, 1, 0.10 + 0.03 * float(pattern)), maxf(u * 0.13, 2.0))

	# хитиновые пластины-«крышечки» сверху каждого сегмента
	if armored:
		for i in segs:
			var t := float(i) / float(maxi(segs - 1, 1))
			var pos := _spine_pos(t, u, spine_len)
			var rad := _rad_at(t, u)
			# тёмная пластина по верхней половине
			draw_arc(pos, rad * 0.94, PI, TAU, 18,
				Color(plate_col.r, plate_col.g, plate_col.b, 0.9), maxf(rad * 0.55, 3.0))
			# светлая кромка сверху
			draw_arc(pos, rad * 0.88, PI + 0.35, TAU - 0.35, 12, plate_edge,
				maxf(u * 0.05, 1.2))

	# янтарные шипы по бокам (поверх пластин)
	if armored:
		for k in spikes:
			var tq := 0.16 + 0.66 * float(k) / float(maxi(spikes - 1, 1))
			var pos := _spine_pos(tq, u, spine_len)
			var side := -1.0 if k % 2 == 0 else 1.0
			var b := _rad_at(tq, u) * 0.5
			var sway := sin(_time * 2.6 + float(k)) * u * 0.06
			var tip := pos + Vector2(sway, side * (u * 0.40 + u * 0.10 * sin(_time * 3.0 + float(k))))
			draw_colored_polygon(PackedVector2Array(
				[pos + Vector2(-b, 0), pos + Vector2(b, 0), tip]), amber)
			draw_colored_polygon(PackedVector2Array(
				[pos + Vector2(-b * 0.4, 0), pos + Vector2(b * 0.4, 0), tip * 0.92 + pos * 0.08]), amber.lightened(0.25))
			_soft(tip, u * 0.06, Color(1, 1, 1, 0.5))

	# узор-пятна (поверх всего, кроме брони)
	if pattern >= 1 and not armored:
		var dots: int = segs * (1 + pattern)
		for d in dots:
			var tq := (float(d) + 0.5) / float(dots)
			var pos := _spine_pos(tq, u, spine_len)
			var off := sin(float(seed % 13) + float(d) * 1.7) * _rad_at(tq, u) * 0.5
			pos.y += off * 0.6
			_soft(pos, u * (0.13 + 0.03 * float(pattern)), Color(1, 1, 1, 0.10 + 0.03 * float(pattern)))

		# усики-антенны на голове (развитая нервная система)
	if stage >= 3:
		var head := _spine_pos(1.0, u, spine_len)
		var hr := _rad_at(1.0, u)
		for side: float in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			var tipy := hr * (1.3 + 0.25 * sin(_time * 3.1 + side))
			for seg in 4:
				var tt := float(seg) / 3.0
				var px := head.x + hr * 0.8 + tt * (u * 0.8)
				var py := head.y + side * (hr * 0.5 + tt * hr * 0.95 + 0.18 * sin(_time * 3.5 + tt * 2.0) * u * 0.2)
				pts.append(Vector2(px, py))
			draw_polyline(pts, Color(col1.r, col1.g, col1.b, 0.85), maxf(u * 0.05, 1.4))
			_soft(pts[pts.size() - 1], u * 0.09, Color(1, 1, 1, 0.5))
			_soft(pts[pts.size() - 1], u * 0.16, Color(0.9, 1.0, 0.8, 0.25))

func _tail_chain(anchor: Vector2, u: float, j: int, col: Color) -> void:
	for st in 7:
		var t := float(st)
		var pos := anchor + Vector2(-(t + 1.0) * u * 0.34,
			sin(_time * 6.0 + t * 1.2 + float(j) * 2.0) * u * 0.16 * (t + 1.0) * 0.4)
		var rad := maxf(u * 0.15 * (1.0 - t / 8.5), 1.6)
		_soft(pos, rad, Color(col.r, col.g, col.b, 0.7))
		if st == 0:
			_soft(pos, rad * 0.4, Color(1, 1, 1, 0.3))

func _draw_eyes(p: Dictionary, u: float, segs: int, glow: float) -> void:
	var head := Vector2.ZERO
	if segs > 1:
		head = _spine_pos(1.0, u, u * (2.0 + float(segs) * 0.85))
		head.x += u * 0.1
	else:
		head = Vector2(u * 0.3, -u * 0.08)
	var n: int = p["eyes"]
	for i in n:
		var er := u * 0.17
		var pos := head
		if n == 1:
			pos = head + Vector2(u * 0.18, 0)
			er = u * 0.30
		else:
			var side := lerpf(-1.0, 1.0, float(i) / float(maxi(n - 1, 1)))
			pos = head + Vector2(u * 0.26, side * u * 0.42)
		if glow > 0.5:
			_soft(pos, er * 1.9, Color(0.55, 1.0, 0.85, 0.10 * glow))
		# глазное яблоко
		_soft(pos, er * 1.15, Color(1, 1, 1, 0.92))
		_soft(pos, er * 0.92, Color(1, 1, 1, 0.95))
		# радужка + зрачок
		var iris := Color8(46, 170, 150) if glow < 0.8 else Color8(220, 120, 255)
		_soft(pos + Vector2(er * 0.16, 0), er * 0.52, iris)
		_soft(pos + Vector2(er * 0.34, 0), er * 0.3, Color8(18, 24, 30))
		_soft(pos + Vector2(er * 0.45, -er * 0.18), er * 0.13, Color(1, 1, 1, 0.9))

# ---------- легендарная аура ----------

func _draw_legend_aura(u: float, spine_len: float, col_glow: Color) -> void:
	var r_out := maxf(u * 2.3, spine_len * 0.55)
	var violet := Color(0.72, 0.42, 1.0)
	# пульсирующие кольца
	var k1 := 1.0 + 0.06 * sin(_time * 2.6)
	var k2 := 1.0 + 0.06 * sin(_time * 2.6 + 1.4)
	draw_set_transform(Vector2.ZERO, _time * 0.8, Vector2(k1, k1 * 0.42))
	draw_arc(Vector2.ZERO, r_out, 0, TAU, 56, Color(violet.r, violet.g, violet.b, 0.50), 3.5)
	draw_set_transform(Vector2.ZERO, -_time * 0.55, Vector2(k2 * 0.8, k2 * 0.35))
	draw_arc(Vector2.ZERO, r_out * 0.78, 0, TAU, 48, Color(0.9, 0.6, 1.0, 0.32), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# лучи
	for i in 6:
		var ang := TAU * float(i) / 6.0 + _time * 0.18
		var a := 0.10 + 0.08 * sin(_time * 3.0 + float(i) * 1.7)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dir * r_out * 0.62, dir * r_out * 1.02,
			Color(1.0, 0.8, 1.0, a), maxf(u * 0.09, 1.6))
	# искры
	for i in 18:
		var ang := TAU * float(i) / 18.0 + _time * 0.6
		var rr := r_out * (1.05 + 0.15 * sin(_time * 2.0 + float(i) * 2.3))
		var pos := Vector2(cos(ang), sin(ang)) * rr
		var a := 0.14 + 0.10 * sin(_time * 3.4 + float(i))
		_soft(pos, u * 0.10, Color(1.0, 0.8, 1.0, maxf(a, 0.03)))

# ---------- «Венец творения» ----------

func _draw_crown_rings(stage: int, u: float, spine_len: float, breath: float) -> void:
	var r_out := maxf(u * 2.1, spine_len * 0.52) * (1.0 + 0.03 * breath)
	var gold := Color(1.0, 0.85, 0.45)
	var gold_a := 0.5 + 0.12 * breath
	draw_set_transform(Vector2.ZERO, _time * 0.45, Vector2(1.0, 0.30))
	draw_arc(Vector2.ZERO, r_out, 0, TAU, 64, Color(gold.r, gold.g, gold.b, gold_a), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if stage >= 7:
		var r2 := r_out * 1.16
		draw_set_transform(Vector2.ZERO, -_time * 0.32, Vector2(1.0, 0.22))
		draw_arc(Vector2.ZERO, r2, 0, TAU, 64, Color(1.0, 0.72, 1.0, gold_a * 0.6), 1.6)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
