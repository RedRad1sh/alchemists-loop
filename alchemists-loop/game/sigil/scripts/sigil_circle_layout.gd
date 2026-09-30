class_name SigilCircleLayout
extends RefCounted

## Чистое описание трансмутационного круга — без единого draw_*.
##
## Разделение «данные / отрисовка» сделано намеренно:
##  * крафтовый UI берёт из layout только [member slots] и двигает ингредиенты
##    мышью, ничего не рисуя;
##  * тесты проверяют детерминизм по структуре, а не по пикселям;
##  * рендер карточки и рендер экрана крафта используют один и тот же layout.

## Константами могут быть только литералы: вызов PackedFloat32Array([...])
## в Godot 4.3 — не константное выражение. weighted_pick берёт обычный
## массив, поэтому упаковка тут и не нужна.
const SECTOR_WEIGHTS := [1.0, 2.2, 2.2, 1.4, 2.6, 2.6, 1.2, 1.4, 2.2, 2.2, 1.2]
const SECTOR_VALUES := [5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 24]

var seed_value: int = 0
var center: Vector2 = Vector2.ZERO
var radius: float = 200.0

var sector_count: int = 8
var sector_step: float = TAU / 8.0
var rotation_offset: float = 0.0
var radial_mirror: bool = false

var radius_glyph: float = 0.90
var radius_slot: float = 0.68
var radius_bridge: float = 0.52
var radius_inner: float = 0.32
var icon_radius: float = 0.0
var glyph_size: float = 0.16

var glyph_names: PackedStringArray = PackedStringArray()
var glyph_angles: PackedFloat32Array = PackedFloat32Array()
var glyph_rotations: PackedFloat32Array = PackedFloat32Array()
var glyph_positions: PackedVector2Array = PackedVector2Array()

var slots: Array = []            ## Array[Dictionary], см. [method make_slot]
var bridges: Array = []          ## Array[PackedVector2Array]
var spokes: Array = []           ## Array[PackedVector2Array]
var rings: Array = []            ## Array[Dictionary] {ratio, width, dash, alpha, offset}
var wedges: Array = []           ## секторные сегменты {a0, a1, r0, r1, alpha}
var offset_ring: Dictionary = {} ## смещённое кольцо {center, radius, alpha}
var inner_shapes: Array = []     ## Array[PackedVector2Array]
var result_glyph: String = ""
var frame_seed: int = 0
var aura_bias: float = 0.0
var style_flags: Dictionary = {}


static func build(p_seed: int, recipe: SigilRecipe, p_center: Vector2, p_radius: float,
		options: SigilOptions) -> SigilCircleLayout:
	var L := new()
	L.seed_value = p_seed
	L.center = p_center
	L.radius = p_radius

	var rng := SigilRng.new(p_seed).fork("circle")

	L.sector_count = SECTOR_VALUES[rng.weighted_pick(SECTOR_WEIGHTS)]
	L.sector_step = TAU / float(L.sector_count)
	L.rotation_offset = rng.randf() * TAU
	L.radial_mirror = rng.chance(0.35)

	L.glyph_size = rng.randf_range(0.17, 0.24) * (1.0 if L.sector_count <= 8 else 0.88)
	L.result_glyph = _pick_result_glyph(rng, recipe)

	# --- кольца -------------------------------------------------------------
	# Радиусы не фиксированные, а набираются в случайном порядке: иначе у всех
	# карточек одинаковые «концентрические мишени» и глаз их сравнивает.
	var inner_ratios := PackedFloat32Array()
	inner_ratios.append(rng.randf_range(0.80, 0.94))
	inner_ratios.append(rng.randf_range(0.60, 0.76))
	for i in range(maxi(options.ring_count - 2, 0)):
		inner_ratios.append(rng.randf_range(0.32, 0.56))
	var arr := Array(inner_ratios)
	arr.sort()
	arr.reverse()
	var ring_ratios := PackedFloat32Array()
	ring_ratios.append(1.0)
	for v in arr:
		ring_ratios.append(float(v))
	for i in ring_ratios.size():
		var dash_mode := rng.randi_range(0, 2)
		L.rings.append({
			"ratio": ring_ratios[i],
			"width": rng.randf_range(0.6, 2.2) * (1.0 + float(i) * 0.15),
			"dash": 0 if dash_mode == 0 else rng.randi_range(6, 22),
			"dash_arc": dash_mode == 2,
			"alpha": clampf(0.95 - float(i) * 0.18, 0.25, 1.0),
			"offset": rng.randf() * TAU if dash_mode == 2 else 0.0,
		})

	# --- секторные сегменты -------------------------------------------------
	# Кусок кольца, залитый полупрозрачным: даёт кругу плоскость, а не набор
	# концентрических окружностей.
	if rng.chance(0.6):
		for i in rng.randi_range(1, 3):
			var a0 := L.rotation_offset + L.sector_step * float(rng.randi_range(0, L.sector_count - 1))
			var wedge := {
				"a0": a0,
				"a1": a0 + L.sector_step * rng.randf_range(0.35, 1.0),
				"r0": p_radius * rng.randf_range(0.66, 0.82),
				"r1": p_radius * rng.randf_range(0.88, 0.995),
				"alpha": rng.randf_range(0.05, 0.13),
			}
			L.wedges.append(wedge)

	# --- смещённое кольцо ----------------------------------------------------
	# Лёгкий эксцентриситет — «второй круг», как в настоящих трансмутациях.
	if rng.chance(0.45):
		var ang := rng.randf() * TAU
		var d := p_radius * rng.randf_range(0.10, 0.28)
		L.offset_ring = {
			"center": p_center + Vector2(cos(ang), sin(ang)) * d,
			"radius": p_radius * rng.randf_range(0.15, 0.30),
			"alpha": rng.randf_range(0.22, 0.45),
		}

	# --- глифы по секторам ---------------------------------------------------
	var palette_count := clampi(L.sector_count / 2 + rng.randi_range(1, 3), 3, 10)
	var glyph_pool := PackedStringArray()
	for i in palette_count:
		var cats := PackedStringArray(["spirit", "mind", "result", "time", "world"])
		if i == 0:
			cats = PackedStringArray([str(recipe.rarity), "result", "spirit"])
		glyph_pool.append(SigilGlyphs.pick_glyph(rng, cats))
		if glyph_pool[i] == "":
			glyph_pool[i] = "sphere"
	for i in L.sector_count:
		var name: String = glyph_pool[rng.randi_range(0, glyph_pool.size() - 1)]
		var angle := L.rotation_offset + L.sector_step * (float(i) + 0.5)
		L.glyph_names.append(name)
		L.glyph_angles.append(angle)
		L.glyph_positions.append(SigilGeometry.polar(p_center, p_radius * L.radius_glyph, angle))
		var rot := 0.0
		match options.glyph_rotation:
			SigilOptions.GlyphRotation.RADIAL:
				rot = angle + PI * 0.5
			SigilOptions.GlyphRotation.RANDOM:
				rot = rng.randf_range(-PI, PI)
			_:
				rot = 0.0
		L.glyph_rotations.append(rot)

	# --- слоты под ингредиенты ---------------------------------------------
	var order: PackedStringArray = recipe.ingredients
	if not recipe.order_sensitive:
		order = recipe.sorted_ingredients()
	var used := mini(order.size(), L.sector_count)
	var angles := SigilGeometry.spread_angles(used, L.sector_count, L.rotation_offset)
	for i in used:
		var ing: String = order[i]
		var glyph := SigilIngredients.glyph_for(ing)
		var slot_angle: float = angles[i]
		L.slots.append(L.make_slot(i, slot_angle, p_radius * L.radius_slot, true, ing, glyph))
	if options.mode == SigilOptions.Mode.DRAFT:
		for i in L.sector_count:
			var a := L.rotation_offset + L.sector_step * float(i)
			L.slots.append(L.make_slot(L.slots.size(), a, p_radius * L.radius_slot, false, "", ""))

	# --- связи --------------------------------------------------------------
	var slot_r := p_radius * L.radius_slot
	var bridge_r := p_radius * L.radius_bridge
	for i in L.slots.size():
		var s: Dictionary = L.slots[i]
		if not bool(s.get("filled", false)):
			continue
		var a: float = s["angle"]
		L.spokes.append(SigilGeometry.dashed_line(
			SigilGeometry.polar(p_center, slot_r * 0.92, a),
			SigilGeometry.polar(p_center, p_radius * L.radius_inner * 1.05, a),
			p_radius * 0.012, p_radius * 0.016))
	for i in L.slots.size():
		var s2: Dictionary = L.slots[i]
		if not bool(s2.get("filled", false)):
			continue
		var s3: Dictionary = L.slots[(i + 1) % L.slots.size()]
		if not bool(s3.get("filled", false)):
			continue
		L.bridges.append(SigilGeometry.chord(s2["angle"], s3["angle"],
			bridge_r * 0.78, bridge_r * 1.16, p_center))

	# --- внутренняя геометрия ------------------------------------------------
	L.inner_shapes = _build_inner(rng, p_center, p_radius, L.sector_count, L.rotation_offset)
	L.icon_radius = p_radius * options.icon_ratio * 0.5

	L.frame_seed = SigilRng.new(p_seed).fork("frame").next_u32()
	L.aura_bias = rng.randf()
	L.style_flags = {
		"mirror": L.radial_mirror,
		"ticks": rng.randi_range(0, L.sector_count),
		"spokes_dashed": rng.chance(0.5),
		"double_outer": rng.chance(0.45),
	}
	return L


## Слот ингредиента на кольце. Позиция выводится из центра layout, поэтому
## это метод инстанса: build() зовёт его у уже собранного L.
## Набор полей совпадает с python/sigilcore.py — от него зависит круг
## отрисовки и будущий crafting UI.
func make_slot(index: int, angle: float, slot_radius: float, filled: bool,
		ingredient: String, glyph: String) -> Dictionary:
	return {
		"index": index,
		"angle": angle,
		"position": SigilGeometry.polar(center, slot_radius, angle),
		"radius": slot_radius,
		"filled": filled,
		"ingredient": ingredient,
		"glyph": glyph,
	}


func slot_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in slots:
		out.append((s as Dictionary)["position"])
	return out


func icon_center() -> Vector2:
	return center


func result_bounds() -> Rect2:
	var r := radius * icon_radius
	return Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0)


static func _pick_result_glyph(rng: SigilRng, recipe: SigilRecipe) -> String:
	var cats := PackedStringArray(["result"])
	match recipe.result_type:
		&"planet":
			cats = PackedStringArray(["world", "result"])
		&"creature":
			cats = PackedStringArray(["life", "spirit", "result"])
		&"abstraction":
			cats = PackedStringArray(["mind", "result"])
		_:
			cats = PackedStringArray(["object", "result"])
	var g := SigilGlyphs.pick_glyph(rng, cats)
	return g if g != "" else "sphere"


static func _build_inner(rng: SigilRng, c: Vector2, r: float, sectors: int, offset: float) -> Array:
	var out: Array = []
	var kind := rng.randi_range(0, 4)
	var r_out := r * rng.randf_range(0.52, 0.62)
	match kind:
		0:
			var n := clampi(sectors, 5, 8)
			out.append(SigilGeometry.star_polygon(c, r_out, r_out * rng.randf_range(0.38, 0.55), n, offset))
			out.append(SigilGeometry.regular_polygon(c, r_out * 0.62, n, -offset))
		1:
			var n2 := clampi(sectors + rng.randi_range(-1, 1), 3, 12)
			out.append(SigilGeometry.regular_polygon(c, r_out, n2, offset))
			out.append(SigilGeometry.regular_polygon(c, r_out * 0.70, n2, -offset * 0.5))
			out.append(SigilGeometry.regular_polygon(c, r_out * 0.40, n2, offset * 0.25))
		2:
			for k in 3:
				out.append(SigilGeometry.arc_points(c, r_out * (1.0 - float(k) * 0.22), 0.0, TAU, 40))
		3:
			# Спирограф: завиток из двух окружностей. Оборотов немного —
			# иначе круг превращается в мочалку и ничего не читается.
			var poly := PackedVector2Array()
			var R := r_out
			var rr := r_out * rng.randf_range(0.22, 0.42)
			var d := r_out * rng.randf_range(0.55, 0.85)
			for i in 220:
				var t := TAU * float(i) / 18.0
				poly.append(c + Vector2((R - rr) * cos(t) + d * cos((R - rr) / rr * t),
					(R - rr) * sin(t) - d * sin((R - rr) / rr * t)))
			out.append(poly)
		_:
			var teeth := clampi(sectors, 6, 12)
			for i in teeth:
				var a := offset + TAU * float(i) / float(teeth)
				out.append(PackedVector2Array([
					SigilGeometry.polar(c, r_out * 0.42, a), SigilGeometry.polar(c, r_out, a)]))
	return out


func signature() -> String:
	## Стабильный отпечаток layout. Тесты детерминизма сравнивают его.
	var s := PackedStringArray()
	s.append("seed=%d" % seed_value)
	s.append("c=%.3f,%.3f r=%.3f" % [center.x, center.y, radius])
	s.append("sec=%d off=%.5f" % [sector_count, rotation_offset])
	s.append("gl=%s" % ",".join(glyph_names))
	# У PackedFloat32Array в Godot 4.3 нет map(), поэтому собираем строку вручную.
	var gr := PackedStringArray()
	for a in glyph_angles:
		gr.append("%.5f" % a)
	s.append("gr=%s" % ",".join(gr))
	for sl in slots:
		var d: Dictionary = sl
		s.append("sl%d:%.5f:%s:%d" % [int(d["index"]), float(d["angle"]),
			str(d["ingredient"]), int(bool(d["filled"]))])
	for b in bridges:
		s.append("br" + SigilGeometry.hash_points(b))
	for sp in spokes:
		s.append("sp" + SigilGeometry.hash_points(sp))
	for sh in inner_shapes:
		s.append("in" + SigilGeometry.hash_points(sh))
	for wg in wedges:
		var w: Dictionary = wg
		s.append("wg%.4f,%.4f,%.3f,%.3f,%.3f" % [float(w["a0"]), float(w["a1"]),
			float(w["r0"]), float(w["r1"]), float(w["alpha"])])
	if not offset_ring.is_empty():
		var oc: Vector2 = offset_ring["center"]
		s.append("or%.3f,%.3f,%.3f,%.3f" % [oc.x, oc.y, float(offset_ring["radius"]),
			float(offset_ring["alpha"])])
	s.append("res=%s" % result_glyph)
	return ("|".join(s)).sha256_text()
