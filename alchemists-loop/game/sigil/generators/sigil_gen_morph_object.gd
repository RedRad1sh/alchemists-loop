class_name SigilGenMorphObject
extends SigilIconGenerator

## Процедурный генератор центрального объекта.
## Рисует только объект внутри rect: без рамки, карты, ауры и круга.
## Вариативность — структурная: seed выбирает топологию и силуэт, затем
## создаёт соединённые части объекта, фасеты и характерный знак.
##
## Необязательные поля ctx / recipe.properties:
##   icon_family: "machine", "clay", "mineral", "vessel", "organic" или "relic"
##   icon_form:   зафиксировать один из форм ниже
##
## Если icon_form не задан, каждый seed выбирает отдельную конструкцию
## внутри подходящего семейства. Никакие готовые иконки не поворачиваются.

const DEFAULT_GRID := 34


func type_name() -> StringName:
	return &"morph_object"


func description() -> String:
	return "Центральный объект из seed: новая топология и силуэт, пиксельная отрисовка"


func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var canvas := new_canvas(rect, ctx, DEFAULT_GRID)
	var g := float(canvas.grid)
	var center := Vector2((g - 1.0) * 0.5, (g - 1.0) * 0.5)

	# Потоки разделены: изменение фасетов не меняет выбранный силуэт.
	var shape_rng := rng.fork("morph/blueprint")
	var part_rng := rng.fork("morph/parts")
	var detail_rng := rng.fork("morph/details")
	var material_rng := rng.fork("morph/material")
	var family := _family_from_context(ctx)

	# Raw clay gets an earth palette; machine colors stay alchemical/cool.
	var hue_min := 0.035 if family == "clay" else 0.52
	var hue_max := 0.105 if family == "clay" else 0.68
	var body_fallback := Color.from_hsv(material_rng.randf_range(hue_min, hue_max), 0.56, 0.74)
	var body := palette(ctx, "body", body_fallback)
	var dark := palette(ctx, "deep", body.darkened(0.58))
	var warm_high := Color(0.98, 0.82, 0.61) if family == "clay" else Color(1.0, 0.96, 0.84)
	var highlight := palette(ctx, "high", body.lerp(warm_high, 0.60))
	var accent_fallback := body.lerp(Color(1.0, 0.84, 0.60), 0.32) if family == "clay" else Color.from_hsv(fposmod(body.h + 0.14, 1.0), 0.76, 0.96)
	var accent := palette(ctx, "accent", accent_fallback)
	var ink_fallback := Color(0.22, 0.10, 0.045) if family == "clay" else Color(0.91, 0.90, 0.84)
	var ink := palette(ctx, "ink", ink_fallback)
	var secondary_base := palette(ctx, "belly", body.lerp(highlight, 0.42))
	var secondary := secondary_base.lerp(accent, detail_rng.randf_range(0.06, 0.18))
	var requested_form := _context_string(ctx, "icon_form", "")
	var form := requested_form if requested_form != "" else _choose_form(family, shape_rng)

	match form:
		"gearbox", "rotor", "walker", "engine", "boiler", "gear_train", "pump", "drill", "loom", "winch", "gear_press", "crane", "mill", "bellows", "crystal_regulator":
			_draw_machine(canvas, form, center, g, part_rng, body, dark, highlight, accent, secondary)
		"clay_lump", "clay_fold", "clay_coil", "clay_slab", "clay_wedge", "clay_cracked", "clay_pinched", "clay_kneaded", "clay_roll", "clay_puck", "clay_block", "clay_gathered":
			_draw_clay(canvas, form, center, g, part_rng, body, dark, highlight, accent, secondary)
		"shard", "geode", "strata", "tablet", "cluster", "vein_nodule", "stalactite":
			_draw_mineral(canvas, form, center, g, part_rng, body, dark, highlight, accent, secondary)
		"vessel", "retort", "censer":
			_draw_vessel(canvas, form, center, g, part_rng, body, dark, highlight, accent, secondary)
		"branch", "bloom", "root":
			_draw_organic(canvas, form, center, g, part_rng, body, dark, highlight, accent, secondary)
		"talisman", "totem", "relic", "split_core":
			_draw_relic(canvas, form, center, g, part_rng, body, dark, highlight, accent, secondary)
		_:
			# Неизвестный form не приводит к пустой карте: seed выбирает
			# один из семействых вариантов, но сохраняет заданную семантику.
			_draw_relic(canvas, _choose_form("relic", shape_rng), center, g,
				part_rng, body, dark, highlight, accent, secondary)

	# Мягкий пиксельный объём, затем отдельный внешний контур.
	canvas.shade_highlight(center + Vector2(-1.0, -2.0), g * 0.38, highlight, 0.10, 0.58)
	canvas.outline(ink, true)  # тонкая обводка (единый стиль)
	canvas.draw(ci, rect)


func _context_string(ctx: Dictionary, key: String, fallback: String) -> String:
	if ctx.has(key):
		return str(ctx[key]).strip_edges().to_lower()
	var properties: Dictionary = {}
	if ctx.has("properties") and typeof(ctx["properties"]) == TYPE_DICTIONARY:
		properties = ctx["properties"]
	if properties.has(key):
		return str(properties[key]).strip_edges().to_lower()
	return fallback


func _family_from_context(ctx: Dictionary) -> String:
	# Treat a result explicitly named as clay more specifically than the broad
	# legacy family "mineral"; raw clay must never become a geode by accident.
	var result_token := _context_string(ctx, "result_type", "")
	if result_token.contains("clay") or result_token.contains("глин"):
		return "clay"
	var token := _context_string(ctx, "icon_family", "")
	if token == "":
		token = _context_string(ctx, "result_type", "")
	if token == "":
		token = _context_string(ctx, "material", "")

	if token.contains("mach") or token.contains("engine") or token.contains("gear") or token.contains("механ"):
		return "machine"
	if token.contains("clay") or token.contains("глин"):
		return "clay"
	if token.contains("earth") or token.contains("stone") or token.contains("mineral") or token.contains("земл") or token.contains("кам"):
		return "mineral"
	if token.contains("liquid") or token.contains("vessel") or token.contains("glass") or token.contains("жид") or token.contains("сосуд"):
		return "vessel"
	if token.contains("plant") or token.contains("organic") or token.contains("root") or token.contains("раст") or token.contains("орган"):
		return "organic"
	if token.contains("relic") or token.contains("artifact") or token.contains("артеф"):
		return "relic"
	return "any"


func _choose_form(family: String, rng: SigilRng) -> String:
	var forms: Array[String] = []
	match family:
		"machine":
			# Seed selects a named mechanism; part_rng only varies its attached parts.
			forms = ["boiler", "rotor", "walker", "pump", "drill", "loom", "winch", "gear_press", "crane", "mill", "bellows", "crystal_regulator"]
		"clay":
			# Raw clay morphology only: no crystals, geodes, or geological strata.
			forms = ["clay_lump", "clay_fold", "clay_coil", "clay_slab", "clay_wedge", "clay_cracked", "clay_pinched", "clay_kneaded", "clay_roll", "clay_puck", "clay_block", "clay_gathered"]
		"mineral":
			forms = ["shard", "geode", "strata", "tablet", "cluster", "vein_nodule", "stalactite"]
		"vessel":
			forms = ["vessel", "retort", "censer"]
		"organic":
			forms = ["branch", "bloom", "root"]
		"relic":
			forms = ["talisman", "totem", "relic", "split_core"]
		_:
			forms = ["shard", "gearbox", "vessel", "branch", "talisman", "split_core", "clay_lump"]
	return forms[rng.randi_range(0, forms.size() - 1)]


# ───────────────────────────── MACHINE ──────────────────────────────────────

func _draw_machine(c: SigilPixelCanvas, form: String, m: Vector2, g: float,
		rng: SigilRng, body: Color, dark: Color, hi: Color, accent: Color,
		secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	# New blueprints use explicit layouts with parts attached to named anchors.
	match form:
		"boiler":
			_draw_boiler(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"walker":
			_draw_walker_blueprint(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"gear_train":
			_draw_gear_train(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"pump":
			_draw_pump(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"drill":
			_draw_drill(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"loom":
			_draw_loom(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"winch":
			_draw_winch(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"gear_press":
			_draw_gear_press(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"crane":
			_draw_crane(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"mill":
			_draw_mill(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"bellows":
			_draw_bellows(c, m, g, rng, body, dark, hi, accent, secondary)
			return
		"crystal_regulator":
			_draw_crystal_regulator(c, m, g, rng, body, dark, hi, accent, secondary)
			return
	match form:
		"gearbox":
			# Корпус с реальными выступами и опорами, а не шар в ореоле.
			var w := rng.randf_range(g * 0.19, g * 0.25)
			var h := rng.randf_range(g * 0.20, g * 0.25)
			var housing := PackedVector2Array([
				Vector2(cx - w * 0.58, cy - h), Vector2(cx + w * 0.52, cy - h * 0.90),
				Vector2(cx + w, cy - h * 0.40), Vector2(cx + w * 0.88, cy + h * 0.62),
				Vector2(cx + w * 0.40, cy + h), Vector2(cx - w * 0.82, cy + h * 0.85),
				Vector2(cx - w, cy + h * 0.20), Vector2(cx - w * 0.90, cy - h * 0.52)])
			c.fill_polygon(housing, body)
			# Два основания и башенка делают у объекта узнаваемый профиль.
			c.fill_rect(int(cx - w * 0.62), int(cy + h * 0.78), int(cx - w * 0.20), int(cy + h * 1.20), dark)
			c.fill_rect(int(cx + w * 0.24), int(cy + h * 0.78), int(cx + w * 0.62), int(cy + h * 1.20), dark)
			var tower_w := rng.randf_range(g * 0.10, g * 0.15)
			c.fill_rect(int(cx - tower_w), int(cy - h * 1.35), int(cx + tower_w), int(cy - h * 0.78), secondary)
			c.fill_rect(int(cx - tower_w - 1.0), int(cy - h * 1.42), int(cx + tower_w + 1.0), int(cy - h * 1.29), hi)
			# Сменное число зубцов и положение бокового вала меняют саму форму.
			var side := -1.0 if rng.chance(0.5) else 1.0
			var teeth := rng.randi_range(3, 6)
			for i in range(teeth):
				var yy := cy - h * 0.42 + float(i) * (h * 0.82 / float(maxi(teeth - 1, 1)))
				var tx := cx + side * (w + rng.randf_range(1.0, 3.0))
				c.fill_rect(int(tx - 1.0), int(yy - 1.0), int(tx + 1.0), int(yy + 1.0), hi if i % 2 == 0 else accent)
			c.line(cx - w * 0.67, cy, cx + w * 0.62, cy, dark)
			c.disc(cx, cy, maxf(2.0, g * 0.065), accent, true)
			c.disc(cx, cy, maxf(1.0, g * 0.027), hi)

		"rotor":
			# Несимметричная турбина: лопасти — части одного силуэта,
			# у каждой отдельные длина и ширина.
			var count := rng.randi_range(3, 5)
			var phase := rng.randf_range(-0.25, 0.25)
			for i in range(count):
				var a := phase + TAU * float(i) / float(count)
				var length := rng.randf_range(g * 0.22, g * 0.34)
				var width := rng.randf_range(g * 0.055, g * 0.105)
				var dir := Vector2(cos(a), sin(a))
				var side := Vector2(-dir.y, dir.x)
				var start := m + dir * g * 0.075
				var end := m + dir * length
				var blade := PackedVector2Array([
					start + side * width, start - side * width,
					end - side * width * 0.42 + dir * width * 0.7,
					end + side * width * 0.58])
				c.fill_polygon(blade, body if i % 2 == 0 else secondary)
				c.line(start.x, start.y, end.x, end.y, dark)
			# Узкий корпус и выступающий вал не позволяют спутать объект с руной.
			c.fill_polygon(_regular_poly(m, g * 0.17, g * 0.20, 6, rng, 0.12), dark)
			c.fill_rect(int(cx - g * 0.055), int(cy + g * 0.15), int(cx + g * 0.055), int(cy + g * 0.36), hi)
			c.disc(cx, cy, g * 0.075, accent, true)
			c.disc(cx, cy, g * 0.030, hi)

		"engine":
			# Вертикальная машина с камерой, клапаном и поршневыми боковинами.
			# Её силуэт заметно отличается от коробки и турбины.
			var hw := g * rng.randf_range(0.18, 0.24)
			var hh := g * rng.randf_range(0.20, 0.26)
			var chamber := PackedVector2Array([
				Vector2(cx - hw * 0.66, cy - hh), Vector2(cx + hw * 0.60, cy - hh * 0.92),
				Vector2(cx + hw, cy - hh * 0.50), Vector2(cx + hw * 0.82, cy + hh * 0.72),
				Vector2(cx + hw * 0.48, cy + hh), Vector2(cx - hw * 0.56, cy + hh * 0.90),
				Vector2(cx - hw, cy + hh * 0.42), Vector2(cx - hw * 0.86, cy - hh * 0.47)])
			c.fill_polygon(chamber, body)
			var chimney_w := g * rng.randf_range(0.055, 0.09)
			c.fill_rect(int(cx - chimney_w), int(cy - hh * 1.42), int(cx + chimney_w), int(cy - hh * 0.80), dark)
			c.fill_rect(int(cx - chimney_w - 1.0), int(cy - hh * 1.48), int(cx + chimney_w + 1.0), int(cy - hh * 1.34), hi)
			var piston_side := -1.0 if rng.chance(0.5) else 1.0
			var piston_x := cx + piston_side * (hw + g * 0.045)
			c.fill_rect(int(piston_x - g * 0.045), int(cy - hh * 0.42), int(piston_x + g * 0.045), int(cy + hh * 0.44), secondary)
			c.fill_rect(int(piston_x - g * 0.075), int(cy - hh * 0.48), int(piston_x + g * 0.075), int(cy - hh * 0.34), hi)
			c.line(cx - hw * 0.52, cy + hh * 0.20, cx + hw * 0.52, cy + hh * 0.20, dark)
			c.disc(cx, cy - hh * 0.12, g * 0.065, accent, true)
			c.disc(cx, cy - hh * 0.12, g * 0.026, hi)
			c.fill_rect(int(cx - hw * 0.70), int(cy + hh * 0.82), int(cx - hw * 0.32), int(cy + hh * 1.14), dark)
			c.fill_rect(int(cx + hw * 0.28), int(cy + hh * 0.82), int(cx + hw * 0.66), int(cy + hh * 1.14), dark)

		"walker":
			# Механический тотем: голова, корпус и конечности имеют
			# разную геометрию; seed меняет число и длину сегментов.
			var head_y := cy - g * rng.randf_range(0.21, 0.27)
			var body_y := cy + g * rng.randf_range(-0.02, 0.06)
			var head := PackedVector2Array([
				Vector2(cx - g * 0.14, head_y + g * 0.05), Vector2(cx - g * 0.10, head_y - g * 0.09),
				Vector2(cx + g * 0.07, head_y - g * 0.12), Vector2(cx + g * 0.15, head_y - g * 0.01),
				Vector2(cx + g * 0.12, head_y + g * 0.10), Vector2(cx - g * 0.05, head_y + g * 0.13)])
			c.fill_polygon(head, secondary)
			var torso := PackedVector2Array([
				Vector2(cx - g * 0.18, body_y - g * 0.08), Vector2(cx - g * 0.11, body_y - g * 0.18),
				Vector2(cx + g * 0.12, body_y - g * 0.16), Vector2(cx + g * 0.20, body_y + g * 0.16),
				Vector2(cx + g * 0.08, body_y + g * 0.26), Vector2(cx - g * 0.16, body_y + g * 0.19)])
			c.fill_polygon(torso, body)
			c.line(cx, head_y + g * 0.12, cx, body_y - g * 0.13, hi)
			var limb_side := -1.0 if rng.chance(0.5) else 1.0
			var arm_len := rng.randf_range(g * 0.20, g * 0.33)
			c.line(cx - g * 0.12, body_y - g * 0.02, cx - g * 0.12 - arm_len, body_y + g * 0.10, dark)
			c.line(cx + g * 0.12, body_y - g * 0.02, cx + g * 0.12 + arm_len * (1.0 if limb_side < 0.0 else 0.72), body_y + g * 0.12, dark)
			c.line(cx - g * 0.08, body_y + g * 0.18, cx - g * rng.randf_range(0.10, 0.20), cy + g * 0.39, dark)
			c.line(cx + g * 0.08, body_y + g * 0.18, cx + g * rng.randf_range(0.10, 0.20), cy + g * 0.39, dark)
			c.disc(cx - g * 0.12 - arm_len, body_y + g * 0.10, g * 0.045, accent)
			c.disc(cx, head_y + g * 0.01, g * 0.035, hi)
			c.fill_rect(int(cx - g * 0.20), int(cy + g * 0.37), int(cx - g * 0.04), int(cy + g * 0.42), secondary)
			c.fill_rect(int(cx + g * 0.04), int(cy + g * 0.37), int(cx + g * 0.20), int(cy + g * 0.42), secondary)

		_:
			_draw_gearbox(c, m, g, rng, body, dark, hi, accent, secondary)


func _draw_gearbox(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var rx := g * rng.randf_range(0.20, 0.25)
	var ry := g * rng.randf_range(0.18, 0.23)
	var points := PackedVector2Array([
		Vector2(cx - rx * 0.72, cy - ry), Vector2(cx + rx * 0.50, cy - ry * 0.88),
		Vector2(cx + rx, cy - ry * 0.28), Vector2(cx + rx * 0.88, cy + ry * 0.68),
		Vector2(cx + rx * 0.20, cy + ry), Vector2(cx - rx * 0.80, cy + ry * 0.78),
		Vector2(cx - rx, cy + ry * 0.10), Vector2(cx - rx * 0.90, cy - ry * 0.55)])
	c.fill_polygon(points, body)
	c.fill_rect(int(cx - rx * 0.55), int(cy - ry * 1.28), int(cx + rx * 0.40), int(cy - ry * 0.80), secondary)
	c.fill_rect(int(cx - rx * 0.28), int(cy - ry * 1.48), int(cx + rx * 0.12), int(cy - ry * 1.25), hi)
	c.line(cx - rx * 0.62, cy + ry * 0.25, cx + rx * 0.62, cy - ry * 0.10, dark)
	c.disc(cx + rx * 0.18, cy - ry * 0.06, g * 0.060, accent, true)
	c.disc(cx + rx * 0.18, cy - ry * 0.06, g * 0.025, hi)
	# Болты разнесены по контуру и меняют количество/позицию.
	for i in range(rng.randi_range(2, 5)):
		var a := rng.randf_range(-PI, PI)
		var bx := cx + cos(a) * rx * 0.77
		var by := cy + sin(a) * ry * 0.72
		c.disc(bx, by, g * 0.027, hi)


# ───────────────────────────── MINERAL ──────────────────────────────────────

func _draw_mineral(c: SigilPixelCanvas, form: String, m: Vector2, g: float,
		rng: SigilRng, body: Color, dark: Color, hi: Color, accent: Color,
		secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	match form:
		"cluster":
			_draw_crystal_cluster(c, m, g, rng, body, dark, hi, accent, secondary)
		"vein_nodule":
			_draw_vein_nodule(c, m, g, rng, body, dark, hi, accent, secondary)
		"stalactite":
			_draw_stalactite(c, m, g, rng, body, dark, hi, accent, secondary)
		"shard":
			var pts := _jagged_poly(m, g * rng.randf_range(0.24, 0.30), g * rng.randf_range(0.29, 0.35), rng.randi_range(6, 9), g, rng, 0.29, -PI * 0.5)
			c.fill_polygon(pts, body)
			var peak := pts[0]
			var shoulder := pts[1]
			var foot := pts[pts.size() - 1]
			c.fill_polygon(PackedVector2Array([peak, shoulder, m, foot]), secondary)
			for i in range(1, pts.size(), 2):
				c.line(m.x, m.y, pts[i].x, pts[i].y, dark)
			c.fill_polygon(PackedVector2Array([pts[2], pts[3], m]), hi)
			c.disc(cx + rng.randf_range(-g * 0.07, g * 0.07), cy + rng.randf_range(-g * 0.04, g * 0.08), g * 0.045, accent)

		"geode":
			var rx := g * rng.randf_range(0.26, 0.30)
			var ry := g * rng.randf_range(0.25, 0.31)
			var shell := _jagged_poly(m, rx, ry, rng.randi_range(7, 10), g, rng, 0.20, -PI * 0.5)
			c.fill_polygon(shell, body)
			var cavity := PackedVector2Array([
				Vector2(cx - rx * 0.52, cy - ry * 0.42), Vector2(cx - rx * 0.12, cy - ry * 0.62),
				Vector2(cx + rx * 0.43, cy - ry * 0.40), Vector2(cx + rx * 0.56, cy + ry * 0.12),
				Vector2(cx + rx * 0.17, cy + ry * 0.53), Vector2(cx - rx * 0.45, cy + ry * 0.30)])
			c.fill_polygon(cavity, dark)
			var crystal_count := rng.randi_range(3, 6)
			for i in range(crystal_count):
				var px := cx + rng.randf_range(-rx * 0.38, rx * 0.38)
				var py := cy + rng.randf_range(-ry * 0.28, ry * 0.20)
				var ph := rng.randf_range(g * 0.10, g * 0.23)
				var pw := rng.randf_range(g * 0.035, g * 0.075)
				var crystal := PackedVector2Array([
					Vector2(px - pw, py + ph * 0.55), Vector2(px - pw * 0.35, py - ph),
					Vector2(px + pw * 0.55, py + ph * 0.30), Vector2(px + pw, py + ph * 0.66)])
				c.fill_polygon(crystal, accent if i % 2 == 0 else hi)
			c.line(cx - rx * 0.62, cy + ry * 0.12, cx - rx * 0.40, cy + ry * 0.66, dark)

		"clay_lump":
			# Неровный связный сгусток из 2–4 масс, не миниатюрная планета.
			var lobes := rng.randi_range(2, 4)
			var centers: Array[Vector2] = []
			for i in range(lobes):
				var x := cx + rng.randf_range(-g * 0.16, g * 0.16)
				var y := cy + rng.randf_range(-g * 0.19, g * 0.18)
				var rx := rng.randf_range(g * 0.11, g * 0.19)
				var ry := rng.randf_range(g * 0.10, g * 0.18)
				centers.append(Vector2(x, y))
				c.ellipse(x, y, rx, ry, body if i % 2 == 0 else secondary)
			# Соединительные перешейки гарантируют цельную массу.
			for i in range(centers.size() - 1):
				var a := centers[i]
				var b := centers[i + 1]
				c.line(a.x, a.y, b.x, b.y, body)
			for i in range(rng.randi_range(2, 4)):
				var y := cy + rng.randf_range(-g * 0.16, g * 0.19)
				var half := rng.randf_range(g * 0.08, g * 0.22)
				c.line(cx - half, y, cx + half, y + rng.randf_range(-1.2, 1.2), dark if i % 2 == 0 else hi)
			c.disc(cx + rng.randf_range(-g * 0.12, g * 0.12), cy - g * 0.04, g * 0.045, accent)

		"strata":
			var rx := g * rng.randf_range(0.24, 0.30)
			var ry := g * rng.randf_range(0.22, 0.29)
			var mass := _jagged_poly(m, rx, ry, rng.randi_range(7, 9), g, rng, 0.17, -PI * 0.5)
			c.fill_polygon(mass, body)
			var band_count := rng.randi_range(3, 5)
			for i in range(band_count):
				var t := float(i + 1) / float(band_count + 1)
				var y := cy - ry * 0.62 + t * ry * 1.22
				var half := rx * (0.75 - absf(t - 0.52) * 0.62) * rng.randf_range(0.77, 1.0)
				c.line(cx - half, y, cx + half, y + rng.randf_range(-1.0, 1.0), dark if i % 2 == 0 else secondary)
			c.fill_polygon(PackedVector2Array([
				Vector2(cx - rx * 0.48, cy - ry * 0.45), Vector2(cx - rx * 0.10, cy - ry * 0.90),
				Vector2(cx + rx * 0.18, cy - ry * 0.40), Vector2(cx + rx * 0.02, cy + ry * 0.02)]), hi)
			c.disc(cx + rx * 0.28, cy + ry * 0.20, g * 0.045, accent)

		"tablet":
			var w := g * rng.randf_range(0.21, 0.27)
			var h := g * rng.randf_range(0.28, 0.34)
			var slab := PackedVector2Array([
				Vector2(cx - w * 0.72, cy - h), Vector2(cx + w * 0.68, cy - h * 0.88),
				Vector2(cx + w, cy - h * 0.55), Vector2(cx + w * 0.87, cy + h * 0.88),
				Vector2(cx - w * 0.58, cy + h), Vector2(cx - w, cy + h * 0.63)])
			c.fill_polygon(slab, body)
			c.fill_polygon(PackedVector2Array([slab[0], slab[1], Vector2(cx + w * 0.04, cy - h * 0.02)]), secondary)
			c.line(cx - w * 0.55, cy - h * 0.30, cx + w * 0.48, cy - h * 0.22, dark)
			c.line(cx - w * 0.38, cy + h * 0.04, cx + w * 0.40, cy + h * 0.10, dark)
			c.line(cx - w * 0.20, cy + h * 0.37, cx + w * 0.25, cy + h * 0.31, accent)
			c.line(cx + w * 0.06, cy - h * 0.80, cx - w * 0.10, cy + h * 0.72, hi)

		_:
			_draw_mineral(c, "shard", m, g, rng, body, dark, hi, accent, secondary)


# ───────────────────────────── VESSEL ───────────────────────────────────────

func _draw_vessel(c: SigilPixelCanvas, form: String, m: Vector2, g: float,
		rng: SigilRng, body: Color, dark: Color, hi: Color, accent: Color,
		secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	if form == "censer":
		var bowl := _jagged_poly(Vector2(cx, cy + g * 0.08), g * 0.25, g * 0.19, 7, g, rng, 0.12, -PI * 0.5)
		c.fill_polygon(bowl, body)
		c.fill_rect(int(cx - g * 0.04), int(cy + g * 0.24), int(cx + g * 0.04), int(cy + g * 0.35), dark)
		c.fill_rect(int(cx - g * 0.14), int(cy + g * 0.34), int(cx + g * 0.14), int(cy + g * 0.40), secondary)
		c.line(cx, cy - g * 0.06, cx, cy - g * 0.37, hi)
		c.disc(cx, cy - g * 0.42, g * 0.04, accent)
		for i in range(rng.randi_range(2, 4)):
			var sx := cx + rng.randf_range(-g * 0.12, g * 0.12)
			var sy := cy - g * rng.randf_range(0.10, 0.28)
			c.disc(sx, sy, g * 0.025, hi)
		return

	# Колба: самостоятельный контур «горлышко—плечи—брюхо—основание».
	var nw := rng.randf_range(g * 0.08, g * 0.14)
	var neck_top := cy - g * rng.randf_range(0.38, 0.44)
	var neck_bottom := cy - g * rng.randf_range(0.10, 0.17)
	var body_rx := rng.randf_range(g * 0.22, g * 0.28)
	var body_ry := rng.randf_range(g * 0.22, g * 0.27)
	var vessel := PackedVector2Array([
		Vector2(cx - nw, neck_top), Vector2(cx + nw, neck_top),
		Vector2(cx + nw, neck_bottom), Vector2(cx + body_rx * 0.58, cy - body_ry * 0.55),
		Vector2(cx + body_rx, cy + body_ry * 0.34), Vector2(cx + body_rx * 0.68, cy + body_ry * 0.91),
		Vector2(cx, cy + body_ry), Vector2(cx - body_rx * 0.73, cy + body_ry * 0.82),
		Vector2(cx - body_rx, cy + body_ry * 0.22), Vector2(cx - body_rx * 0.54, cy - body_ry * 0.56),
		Vector2(cx - nw, neck_bottom)])
	c.fill_polygon(vessel, body)
	# Горлышко/ободок и жидкость — разные плоскости, контур остаётся читаемым.
	c.fill_rect(int(cx - nw - 1.0), int(neck_top - 1.0), int(cx + nw + 1.0), int(neck_top + 2.0), hi)
	c.line(cx - nw, neck_bottom, cx + nw, neck_bottom, secondary)
	var liquid_y := cy + rng.randf_range(g * 0.06, g * 0.20)
	var liquid_w := body_rx * rng.randf_range(0.56, 0.77)
	c.line(cx - liquid_w, liquid_y, cx + liquid_w, liquid_y + rng.randf_range(-1.2, 1.2), accent)
	c.fill_rect(int(cx - body_rx * 0.46), int(cy + body_ry * 0.72), int(cx + body_rx * 0.46), int(cy + body_ry * 0.80), dark)
	c.fill_rect(int(cx - nw * 0.56), int(neck_top + g * 0.08), int(cx - nw * 0.20), int(neck_bottom - g * 0.04), hi)
	c.disc(cx + rng.randf_range(-g * 0.08, g * 0.08), cy + rng.randf_range(-g * 0.06, g * 0.12), g * 0.035, hi)
	if form == "retort" or rng.chance(0.55):
		# Боковой изогнутый отвод меняет внешний силуэт колбы.
		var side := -1.0 if rng.chance(0.5) else 1.0
		c.line(cx + side * body_rx * 0.68, cy - body_ry * 0.36,
			cx + side * g * 0.38, cy - body_ry * 0.56, secondary)
		c.line(cx + side * g * 0.38, cy - body_ry * 0.56,
			cx + side * g * 0.40, cy - body_ry * 0.78, secondary)


# ───────────────────────────── ORGANIC ──────────────────────────────────────

func _draw_organic(c: SigilPixelCanvas, form: String, m: Vector2, g: float,
		rng: SigilRng, body: Color, dark: Color, hi: Color, accent: Color,
		secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var root_form := form == "root"
	var base_y := cy + g * 0.29
	var trunk_top := cy - g * rng.randf_range(0.22, 0.32)
	var trunk_w := g * rng.randf_range(0.05, 0.10)
	c.line(cx, base_y, cx + rng.randf_range(-g * 0.05, g * 0.05), trunk_top, body)
	c.fill_rect(int(cx - trunk_w), int(cy - g * 0.02), int(cx + trunk_w), int(cy + g * 0.22), body)

	var branch_count := rng.randi_range(3, 6)
	var branch_rows := maxi(ceili(float(branch_count) / 2.0), 1)
	for i in range(branch_count):
		var side := -1.0 if i % 2 == 0 else 1.0
		var level := float(floori(float(i) / 2.0) + 1) / float(branch_rows)
		var y0 := base_y - level * g * 0.47
		var reach := rng.randf_range(g * 0.12, g * 0.26)
		var tip := Vector2(cx + side * reach, y0 - rng.randf_range(g * 0.02, g * 0.14))
		c.line(cx, y0, tip.x, tip.y, dark if root_form else body)
		if form == "bloom":
			var r := rng.randf_range(g * 0.045, g * 0.085)
			c.ellipse(tip.x, tip.y, r * 1.10, r * 0.72, secondary if i % 2 == 0 else body)
			c.disc(tip.x, tip.y, g * 0.027, accent)
		else:
			var leaf_w := rng.randf_range(g * 0.05, g * 0.11)
			var leaf_h := rng.randf_range(g * 0.07, g * 0.13)
			var leaf := PackedVector2Array([
				Vector2(tip.x, tip.y - leaf_h), Vector2(tip.x + side * leaf_w, tip.y - leaf_h * 0.20),
				Vector2(tip.x + side * leaf_w * 0.25, tip.y + leaf_h * 0.60),
				Vector2(tip.x - side * leaf_w * 0.48, tip.y + leaf_h * 0.16)])
			c.fill_polygon(leaf, accent if i % 2 == 0 else secondary)
			c.line(tip.x, tip.y - leaf_h * 0.55, tip.x + side * leaf_w * 0.55, tip.y + leaf_h * 0.23, dark)

	if root_form:
		for i in range(rng.randi_range(2, 4)):
			var x := cx + rng.randf_range(-g * 0.06, g * 0.06)
			c.line(x, base_y - g * 0.02, x + rng.randf_range(-g * 0.20, g * 0.20), base_y + g * 0.11, dark)
	else:
		c.disc(cx, trunk_top, g * 0.065, accent, true)
		c.disc(cx, trunk_top, g * 0.028, hi)


# ───────────────────────────── RELIC / GENERIC ──────────────────────────────

func _draw_relic(c: SigilPixelCanvas, form: String, m: Vector2, g: float,
		rng: SigilRng, body: Color, dark: Color, hi: Color, accent: Color,
		secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	match form:
		"totem":
			var count := rng.randi_range(3, 5)
			var seg_h := g * rng.randf_range(0.105, 0.14)
			var total_h := seg_h * float(count)
			var y := cy - total_h * 0.5
			for i in range(count):
				var width := g * rng.randf_range(0.14, 0.23) * (1.0 if i % 2 == 0 else 0.82)
				var xoff := rng.randf_range(-g * 0.08, g * 0.08)
				var piece := PackedVector2Array([
					Vector2(cx + xoff - width, y), Vector2(cx + xoff + width * 0.8, y + g * 0.01),
					Vector2(cx + xoff + width, y + seg_h * 0.70), Vector2(cx + xoff + width * 0.45, y + seg_h),
					Vector2(cx + xoff - width * 0.72, y + seg_h * 0.92)])
				c.fill_polygon(piece, body if i % 2 == 0 else secondary)
				c.line(cx + xoff - width * 0.55, y + seg_h * 0.18,
					cx + xoff + width * 0.48, y + seg_h * 0.20, hi if i == count - 1 else dark)
				y += seg_h * 0.86
			c.disc(cx, cy, g * 0.055, accent)

		"split_core":
			# Две неодинаковые массы, перемычка и смещённый внутренний узел.
			var sep := rng.randf_range(g * 0.09, g * 0.16)
			var left := Vector2(cx - sep, cy + rng.randf_range(-g * 0.03, g * 0.08))
			var right := Vector2(cx + sep, cy - rng.randf_range(-g * 0.03, g * 0.08))
			var lr := rng.randf_range(g * 0.13, g * 0.19)
			var rr := rng.randf_range(g * 0.12, g * 0.20)
			c.line(left.x + lr * 0.55, left.y, right.x - rr * 0.55, right.y, dark)
			c.fill_polygon(_jagged_poly(left, lr, lr * 0.85, rng.randi_range(5, 7), g, rng, 0.16, -PI * 0.5), body)
			c.fill_polygon(_jagged_poly(right, rr, rr * 0.90, rng.randi_range(5, 8), g, rng, 0.18, -PI * 0.5), secondary)
			c.disc(left.x, left.y, g * 0.043, hi)
			c.disc(right.x, right.y, g * 0.055, accent)

		"talisman":
			var width := g * rng.randf_range(0.22, 0.28)
			var height := g * rng.randf_range(0.25, 0.33)
			var pendant := PackedVector2Array([
				Vector2(cx, cy - height), Vector2(cx + width * 0.70, cy - height * 0.48),
				Vector2(cx + width, cy + height * 0.20), Vector2(cx + width * 0.30, cy + height),
				Vector2(cx - width * 0.62, cy + height * 0.82), Vector2(cx - width, cy - height * 0.10),
				Vector2(cx - width * 0.55, cy - height * 0.60)])
			c.fill_polygon(pendant, body)
			c.fill_polygon(PackedVector2Array([
				Vector2(cx, cy - height * 0.68), Vector2(cx + width * 0.48, cy - height * 0.16),
				Vector2(cx, cy + height * 0.58), Vector2(cx - width * 0.45, cy - height * 0.10)]), secondary)
			c.line(cx, cy - height * 0.70, cx, cy + height * 0.72, dark)
			c.disc(cx + rng.randf_range(-g * 0.04, g * 0.04), cy, g * 0.055, accent)
			c.disc(cx, cy, g * 0.024, hi)

		"relic":
			# Смешанный объект: корпус, разный верхний/нижний узел и боковой
			# придаток. Это отдельный силуэт, не «астролябия с новым углом».
			var pts := _jagged_poly(m, g * rng.randf_range(0.20, 0.27), g * rng.randf_range(0.23, 0.30), rng.randi_range(5, 8), g, rng, 0.22, -PI * 0.5)
			c.fill_polygon(pts, body)
			var side := -1.0 if rng.chance(0.5) else 1.0
			var ytop := cy - g * rng.randf_range(0.28, 0.39)
			c.fill_rect(int(cx - g * 0.06), int(ytop), int(cx + g * 0.06), int(cy - g * 0.18), secondary)
			c.line(cx + side * g * 0.12, cy, cx + side * g * 0.31, cy - g * 0.05, dark)
			c.disc(cx + side * g * 0.33, cy - g * 0.05, g * 0.055, accent)
			c.fill_polygon(PackedVector2Array([pts[0], pts[1], m]), hi)
			c.disc(cx, cy + g * 0.08, g * 0.05, dark)
			c.disc(cx, cy + g * 0.08, g * 0.025, hi)

		_:
			_draw_relic(c, "relic", m, g, rng, body, dark, hi, accent, secondary)


# ───────────────────────────── GEOMETRY HELPERS ────────────────────────────

func _regular_poly(center: Vector2, rx: float, ry: float, sides: int,
		rng: SigilRng, jitter: float = 0.0) -> PackedVector2Array:
	return _jagged_poly(center, rx, ry, sides, 128.0, rng, jitter, -PI * 0.5)


func _jagged_poly(center: Vector2, rx: float, ry: float, sides: int, grid: float,
		rng: SigilRng, jitter: float = 0.18, phase: float = -PI * 0.5) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(sides, 3)
	for i in range(count):
		var base_angle := phase + TAU * float(i) / float(count)
		var angle := base_angle + rng.randf_range(-0.12, 0.12)
		var radius := rng.randf_range(1.0 - jitter, 1.0 + jitter)
		var p := Vector2(center.x + cos(angle) * rx * radius,
			center.y + sin(angle) * ry * radius)
		p.x = clampf(p.x, 2.0, grid - 3.0)
		p.y = clampf(p.y, 2.0, grid - 3.0)
		points.append(p)
	return points


# ─────────────────── BLUEPRINT-LED MACHINE VARIANTS ────────────────────────
# Each template attaches its details to a named anchor (chamber, axle,
# frame, outlet, or support). This is a construction constraint, not proof that
# every resulting silhouette reads as a meaningful object.

func _draw_boiler(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var w := g * rng.randf_range(0.25, 0.29)
	var h := g * rng.randf_range(0.16, 0.20)
	var chamber := PackedVector2Array([
		Vector2(cx - w * 0.62, cy - h * 0.67), Vector2(cx - w * 0.42, cy - h),
		Vector2(cx + w * 0.38, cy - h), Vector2(cx + w * 0.62, cy - h * 0.62),
		Vector2(cx + w * 0.58, cy + h * 0.57), Vector2(cx + w * 0.34, cy + h * 0.80),
		Vector2(cx - w * 0.44, cy + h * 0.80), Vector2(cx - w * 0.62, cy + h * 0.50)])
	c.fill_polygon(chamber, body)
	var chimney_w := g * rng.randf_range(0.055, 0.085)
	c.fill_rect(int(cx - chimney_w), int(cy - h * 1.52), int(cx + chimney_w), int(cy - h * 0.82), dark)
	c.fill_rect(int(cx - chimney_w - 1.0), int(cy - h * 1.56), int(cx + chimney_w + 1.0), int(cy - h * 1.43), hi)
	c.fill_rect(int(cx - w * 0.36), int(cy + h * 0.08), int(cx + w * 0.34), int(cy + h * 0.53), dark)
	c.fill_polygon(PackedVector2Array([
		Vector2(cx, cy + h * 0.12), Vector2(cx + w * 0.22, cy + h * 0.48),
		Vector2(cx - w * 0.20, cy + h * 0.48)]), accent)
	var side := -1.0 if rng.chance(0.5) else 1.0
	var sx := cx + side * w * 0.58
	c.line(sx, cy - h * 0.24, cx + side * (w + g * 0.11), cy - h * 0.24, secondary)
	c.line(cx + side * (w + g * 0.11), cy - h * 0.24, cx + side * (w + g * 0.11), cy + h * 0.03, secondary)
	c.fill_rect(int(cx - w * 0.46), int(cy + h * 0.77), int(cx - w * 0.18), int(cy + h * 1.02), dark)
	c.fill_rect(int(cx + w * 0.18), int(cy + h * 0.77), int(cx + w * 0.46), int(cy + h * 1.02), dark)


func _draw_gear_train(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var w := g * rng.randf_range(0.25, 0.29)
	var h := g * rng.randf_range(0.15, 0.19)
	var chassis := PackedVector2Array([
		Vector2(cx - w * 0.82, cy - h * 0.62), Vector2(cx - w * 0.58, cy - h),
		Vector2(cx + w * 0.60, cy - h), Vector2(cx + w * 0.84, cy - h * 0.52),
		Vector2(cx + w * 0.76, cy + h * 0.64), Vector2(cx + w * 0.38, cy + h),
		Vector2(cx - w * 0.62, cy + h * 0.88), Vector2(cx - w * 0.84, cy + h * 0.36)])
	c.fill_polygon(chassis, body)
	c.fill_rect(int(cx - w * 0.55), int(cy + h * 0.84), int(cx - w * 0.28), int(cy + h * 1.10), dark)
	c.fill_rect(int(cx + w * 0.28), int(cy + h * 0.82), int(cx + w * 0.54), int(cy + h * 1.10), dark)
	var radius := g * rng.randf_range(0.082, 0.103)
	var centers := [Vector2(cx - w * 0.25, cy), Vector2(cx + w * 0.25, cy)]
	for j in range(2):
		var gear_center: Vector2 = centers[j]
		var r := radius if j == 0 else radius * rng.randf_range(0.82, 1.06)
		c.disc(gear_center.x, gear_center.y, r, dark, true)
		for k in range(8):
			var a := TAU * float(k) / 8.0
			c.line(gear_center.x + cos(a) * r * 0.78, gear_center.y + sin(a) * r * 0.78,
				gear_center.x + cos(a) * r * 1.20, gear_center.y + sin(a) * r * 1.20,
				hi if k % 2 == 0 else secondary)
		c.disc(gear_center.x, gear_center.y, maxf(1.0, r * 0.32), accent if j == 0 else secondary)
		c.disc(gear_center.x, gear_center.y, maxf(0.65, r * 0.12), hi)
	c.line(cx - w * 0.72, cy - h * 0.25, cx + w * 0.72, cy - h * 0.25, dark)
	c.line(cx + w * 0.34, cy, cx + w * 0.98, cy, hi)


func _draw_pump(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var w := g * rng.randf_range(0.16, 0.20)
	var h := g * rng.randf_range(0.18, 0.23)
	var tank := PackedVector2Array([
		Vector2(cx - w * 0.70, cy - h * 0.68), Vector2(cx - w * 0.46, cy - h),
		Vector2(cx + w * 0.46, cy - h), Vector2(cx + w * 0.70, cy - h * 0.68),
		Vector2(cx + w * 0.62, cy + h * 0.62), Vector2(cx + w * 0.38, cy + h * 0.87),
		Vector2(cx - w * 0.38, cy + h * 0.87), Vector2(cx - w * 0.62, cy + h * 0.62)])
	c.fill_polygon(tank, body)
	c.fill_rect(int(cx - w * 0.42), int(cy - h * 0.12), int(cx + w * 0.42), int(cy + h * 0.40), dark)
	c.fill_rect(int(cx - w * 0.35), int(cy + h * 0.12), int(cx + w * 0.35), int(cy + h * 0.34), accent)
	c.fill_rect(int(cx - w * 0.48), int(cy + h * 0.84), int(cx + w * 0.48), int(cy + h * 1.02), dark)
	c.fill_rect(int(cx - g * 0.035), int(cy - h * 1.34), int(cx + g * 0.035), int(cy - h * 0.78), hi)
	var side := -1.0 if rng.chance(0.5) else 1.0
	c.line(cx, cy - h * 1.30, cx + side * g * 0.24, cy - h * 1.48, secondary)
	c.line(cx + side * g * 0.24, cy - h * 1.48, cx + side * g * 0.28, cy - h * 1.28, secondary)
	c.line(cx + side * w * 0.66, cy - h * 0.35, cx + side * (w + g * 0.14), cy - h * 0.35, hi)
	c.line(cx + side * (w + g * 0.14), cy - h * 0.35, cx + side * (w + g * 0.14), cy - h * 0.08, hi)


func _draw_drill(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var variant := rng.randi_range(0, 1)
	if variant == 1:
		var w := g * rng.randf_range(0.13, 0.17)
		var h := g * rng.randf_range(0.18, 0.23)
		var rig := PackedVector2Array([
			Vector2(cx - w, cy - h * 0.55), Vector2(cx - w * 0.78, cy - h),
			Vector2(cx + w * 0.78, cy - h), Vector2(cx + w, cy - h * 0.55),
			Vector2(cx + w * 0.72, cy + h * 0.18), Vector2(cx - w * 0.72, cy + h * 0.18)])
		c.fill_polygon(rig, body)
		c.fill_rect(int(cx - g * 0.035), int(cy - h * 0.92), int(cx + g * 0.035), int(cy + h * 0.28), dark)
		c.fill_polygon(PackedVector2Array([
			Vector2(cx - g * 0.09, cy + h * 0.18), Vector2(cx + g * 0.09, cy + h * 0.18),
			Vector2(cx, cy + g * 0.39)]), hi)
		c.line(cx - w * 0.70, cy - h * 0.30, cx - w * 0.27, cy + h * 0.30, secondary)
		c.line(cx + w * 0.70, cy - h * 0.30, cx + w * 0.27, cy + h * 0.30, secondary)
		c.fill_rect(int(cx - g * 0.24), int(cy + h * 0.28), int(cx + g * 0.24), int(cy + h * 0.34), dark)
		c.line(cx - g * 0.19, cy - h * 0.48, cx + g * 0.19, cy - h * 0.48, accent)
		return
	var direction := -1.0 if rng.chance(0.5) else 1.0
	var x0 := cx - direction * g * 0.29
	var tip := cx + direction * g * 0.39
	var casing := PackedVector2Array([
		Vector2(x0, cy - g * 0.13), Vector2(cx - direction * g * 0.19, cy - g * 0.21),
		Vector2(cx + direction * g * 0.10, cy - g * 0.16), Vector2(cx + direction * g * 0.19, cy - g * 0.08),
		Vector2(cx + direction * g * 0.19, cy + g * 0.08), Vector2(cx + direction * g * 0.10, cy + g * 0.16),
		Vector2(cx - direction * g * 0.19, cy + g * 0.21), Vector2(x0, cy + g * 0.13)])
	c.fill_polygon(casing, body)
	var panel_x0 := minf(x0, cx - direction * g * 0.18)
	var panel_x1 := maxf(x0, cx - direction * g * 0.18)
	c.fill_rect(int(panel_x0), int(cy - g * 0.075), int(panel_x1), int(cy + g * 0.075), secondary)
	c.line(cx + direction * g * 0.16, cy, tip, cy, hi)
	c.fill_polygon(PackedVector2Array([
		Vector2(cx + direction * g * 0.19, cy - g * 0.12), Vector2(tip, cy),
		Vector2(cx + direction * g * 0.19, cy + g * 0.12)]), dark)
	var grip_a := x0 - direction * g * 0.06
	var grip_b := x0 + direction * g * 0.02
	c.fill_rect(int(minf(grip_a, grip_b)), int(cy - g * 0.25), int(maxf(grip_a, grip_b)), int(cy + g * 0.25), dark)
	for i in range(3):
		var xx := x0 - direction * g * (0.02 + 0.045 * float(i))
		c.line(xx, cy - g * 0.14, xx, cy + g * 0.14, hi if i == 1 else dark)
	c.fill_rect(int(cx - g * 0.07), int(cy + g * 0.14), int(cx + g * 0.07), int(cy + g * 0.32), dark)


func _draw_loom(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var style := rng.randi_range(0, 2)
	if style == 0:
		var w := g * rng.randf_range(0.27, 0.31)
		var h := g * rng.randf_range(0.14, 0.18)
		var left := cx - w
		var right := cx + w
		var top := cy - h
		var bottom := cy + h
		c.fill_rect(int(left), int(top), int(right), int(top + g * 0.055), body)
		c.fill_rect(int(left), int(bottom - g * 0.055), int(right), int(bottom), dark)
		c.fill_rect(int(left), int(top), int(left + g * 0.055), int(bottom), dark)
		c.fill_rect(int(right - g * 0.055), int(top), int(right), int(bottom), dark)
		c.fill_rect(int(left + g * 0.02), int(bottom), int(left + g * 0.18), int(bottom + g * 0.09), secondary)
		c.fill_rect(int(right - g * 0.18), int(bottom), int(right - g * 0.02), int(bottom + g * 0.09), secondary)
		var count := rng.randi_range(4, 7)
		for i in range(count):
			var x := left + g * 0.09 + float(i) * (w * 2.0 - g * 0.18) / float(maxi(count - 1, 1))
			c.line(x, top + g * 0.06, x, bottom - g * 0.06, hi if i % 2 == 0 else secondary)
		var ybar := cy + rng.randf_range(-g * 0.05, g * 0.05)
		c.fill_rect(int(cx - w * 0.55), int(ybar - g * 0.04), int(cx + w * 0.55), int(ybar + g * 0.04), accent)
		var shuttle_x := cx + rng.randf_range(-w * 0.25, w * 0.25)
		c.fill_rect(int(shuttle_x - g * 0.07), int(ybar - g * 0.09), int(shuttle_x + g * 0.07), int(ybar + g * 0.09), dark)
		c.disc(left + g * 0.08, cy, g * 0.045, body)
		c.disc(right - g * 0.08, cy, g * 0.045, body)
	elif style == 1:
		# Upright tapestry frame with flared feet and two protruding thread spools.
		var w := g * rng.randf_range(0.17, 0.21)
		var h := g * rng.randf_range(0.28, 0.33)
		var top := cy - h
		var bottom := cy + h * 0.84
		c.fill_rect(int(cx - w), int(top), int(cx + w), int(top + g * 0.065), body)
		c.fill_rect(int(cx - w * 0.84), int(top + g * 0.04), int(cx - w * 0.58), int(bottom), dark)
		c.fill_rect(int(cx + w * 0.58), int(top + g * 0.04), int(cx + w * 0.84), int(bottom), dark)
		c.fill_rect(int(cx - w * 1.40), int(bottom), int(cx - w * 0.40), int(bottom + g * 0.08), secondary)
		c.fill_rect(int(cx + w * 0.40), int(bottom), int(cx + w * 1.40), int(bottom + g * 0.08), secondary)
		c.disc(cx - w * 1.12, cy, g * 0.085, body)
		c.disc(cx + w * 1.12, cy, g * 0.085, body)
		c.disc(cx - w * 1.12, cy, g * 0.085 * 0.38, hi)
		c.disc(cx + w * 1.12, cy, g * 0.085 * 0.38, hi)
		var count := rng.randi_range(4, 6)
		for i in range(count):
			var x := cx - w * 0.42 + float(i) * (w * 0.84 / float(maxi(count - 1, 1)))
			c.line(x, top + g * 0.07, x + g * 0.015, bottom - g * 0.03, hi if i % 2 == 0 else accent)
		var bar_y := cy + rng.randf_range(-g * 0.07, g * 0.06)
		c.fill_rect(int(cx - w * 0.60), int(bar_y - g * 0.045), int(cx + w * 0.60), int(bar_y + g * 0.045), dark)
		c.disc(cx, bar_y, g * 0.045, hi)
	else:
		# Open A-frame loom with broad legs and a hanging warp.
		var w := g * rng.randf_range(0.29, 0.34)
		var top := cy - g * rng.randf_range(0.27, 0.32)
		var base := cy + g * 0.27
		var left := PackedVector2Array([
			Vector2(cx - w, base), Vector2(cx - w * 0.83, base),
			Vector2(cx - g * 0.055, top + g * 0.07), Vector2(cx - g * 0.12, top)])
		var right := PackedVector2Array([
			Vector2(cx + w, base), Vector2(cx + w * 0.83, base),
			Vector2(cx + g * 0.055, top + g * 0.07), Vector2(cx + g * 0.12, top)])
		c.fill_polygon(left, dark)
		c.fill_polygon(right, dark)
		c.fill_rect(int(cx - w), int(top), int(cx + w), int(top + g * 0.065), body)
		c.fill_rect(int(cx - w), int(base), int(cx + w), int(base + g * 0.06), secondary)
		for i in range(5):
			var x := cx - w * 0.52 + float(i) * w * 0.26
			c.line(x, top + g * 0.08, x, base - g * 0.02, hi if i % 2 == 0 else accent)
		c.fill_rect(int(cx - g * 0.15), int(cy - g * 0.025), int(cx + g * 0.15), int(cy + g * 0.045), body)


func _draw_winch(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var w := g * rng.randf_range(0.23, 0.28)
	var base := cy + g * 0.25
	c.fill_rect(int(cx - w), int(base), int(cx + w), int(base + g * 0.075), dark)
	var left := cx - w * 0.72
	var right := cx + w * 0.72
	var top := cy - g * 0.16
	var low := cy + g * 0.15
	c.fill_rect(int(left - g * 0.045), int(top), int(left + g * 0.045), int(base), secondary)
	c.fill_rect(int(right - g * 0.045), int(top), int(right + g * 0.045), int(base), secondary)
	c.fill_rect(int(left - g * 0.085), int(top - g * 0.04), int(left + g * 0.085), int(top + g * 0.04), hi)
	c.fill_rect(int(right - g * 0.085), int(top - g * 0.04), int(right + g * 0.085), int(top + g * 0.04), hi)
	c.fill_rect(int(cx - g * 0.18), int(low - g * 0.09), int(cx + g * 0.18), int(low + g * 0.09), body)
	for i in range(4):
		var xx := cx - g * 0.14 + float(i) * g * 0.09
		c.line(xx, low - g * 0.075, xx, low + g * 0.075, dark if i % 2 == 0 else hi)
	c.line(left - g * 0.045, top, cx + g * 0.19, top, hi)
	var side := 1.0 if rng.chance(0.5) else -1.0
	var ax := cx + side * w * 0.82
	c.line(ax, top, ax + side * g * 0.13, top - g * 0.12, dark)
	c.line(ax + side * g * 0.13, top - g * 0.12, ax + side * g * 0.22, top - g * 0.04, accent)
	c.disc(ax + side * g * 0.22, top - g * 0.04, g * 0.04, hi)


# ─────────────────────── BLUEPRINT-LED MINERAL FORMS ───────────────────────

func _draw_crystal_cluster(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var rx := g * rng.randf_range(0.24, 0.30)
	var ry := g * rng.randf_range(0.12, 0.17)
	var base := _jagged_poly(Vector2(cx, cy + g * 0.18), rx, ry,
		rng.randi_range(6, 8), g, rng, 0.20, -PI * 0.5)
	c.fill_polygon(base, body)
	var count := rng.randi_range(3, 5)
	for i in range(count):
		var t := 0.0 if count == 1 else float(i) / float(count - 1)
		var x := cx - rx * 0.70 + t * rx * 1.40 + rng.randf_range(-g * 0.025, g * 0.025)
		var y := cy + g * 0.13 + rng.randf_range(-g * 0.025, g * 0.035)
		var height := rng.randf_range(g * 0.18, g * 0.36) * (1.0 - absf(t - 0.50) * 0.40)
		var half := rng.randf_range(g * 0.045, g * 0.085)
		var crystal := PackedVector2Array([
			Vector2(x - half, y), Vector2(x - half * 0.38, y - height * 0.74),
			Vector2(x, y - height), Vector2(x + half * 0.72, y - height * 0.57),
			Vector2(x + half, y)])
		c.fill_polygon(crystal, accent if i % 2 == 0 else secondary)
		c.line(x - half * 0.35, y - height * 0.66, x, y - height * 0.92, hi)
	c.line(cx - rx * 0.60, cy + g * 0.22, cx + rx * 0.60, cy + g * 0.22, dark)


func _draw_vein_nodule(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var rx := g * rng.randf_range(0.25, 0.30)
	var ry := g * rng.randf_range(0.22, 0.28)
	var pts := _jagged_poly(m, rx, ry, rng.randi_range(7, 10), g, rng, 0.25, -PI * 0.5)
	c.fill_polygon(pts, body)
	var side := -1.0 if rng.chance(0.5) else 1.0
	var root := Vector2(cx - side * rx * 0.62, cy + ry * 0.40)
	var fork := Vector2(cx + side * rx * 0.02, cy - ry * 0.04)
	var end := Vector2(cx + side * rx * 0.65, cy - ry * 0.46)
	c.line(root.x, root.y + 1.0, fork.x, fork.y + 1.0, dark)
	c.line(fork.x, fork.y + 1.0, end.x, end.y + 1.0, dark)
	c.line(root.x, root.y, fork.x, fork.y, accent)
	c.line(fork.x, fork.y, end.x, end.y, hi)
	var branch_y := cy + ry * 0.45
	c.line(fork.x, fork.y, cx + side * rx * 0.40, branch_y, secondary)
	c.disc(fork.x, fork.y, g * 0.045, hi)
	c.disc(end.x, end.y, g * 0.035, accent)


func _draw_stalactite(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var rx := g * rng.randf_range(0.24, 0.29)
	var cap_y := cy - g * 0.16
	var cap := _jagged_poly(Vector2(cx, cap_y), rx, g * 0.11,
		rng.randi_range(6, 8), g, rng, 0.18, -PI * 0.5)
	c.fill_polygon(cap, body)
	var count := rng.randi_range(3, 5)
	for i in range(count):
		var t := 0.0 if count == 1 else float(i) / float(count - 1)
		var x := cx - rx * 0.67 + t * rx * 1.34 + rng.randf_range(-g * 0.025, g * 0.025)
		var start_y := cap_y + g * 0.035
		var depth := rng.randf_range(g * 0.16, g * 0.34) * (1.0 - absf(t - 0.50) * 0.30)
		var half := rng.randf_range(g * 0.035, g * 0.065)
		var crystal := PackedVector2Array([
			Vector2(x - half, start_y), Vector2(x - half * 0.82, start_y + depth * 0.46),
			Vector2(x, start_y + depth), Vector2(x + half * 0.88, start_y + depth * 0.50),
			Vector2(x + half, start_y)])
		c.fill_polygon(crystal, secondary if i % 2 == 0 else body)
		c.line(x - half * 0.40, start_y + depth * 0.20, x, start_y + depth * 0.78, hi)
	c.line(cx - rx * 0.68, cap_y + g * 0.035, cx + rx * 0.68, cap_y + g * 0.035, dark)


# ───────────────────── ADDITIONAL MACHINE SUBTYPES ─────────────────────────

func _draw_gear_press(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var style := rng.randi_range(0, 2)
	var w := g * rng.randf_range(0.22, 0.27)
	if style == 0:
		# Rigid H-frame carrying a screw, press plate and workpiece.
		var top := cy - g * 0.31
		var base := cy + g * 0.29
		c.fill_rect(int(cx - w), int(top), int(cx - w * 0.70), int(base), dark)
		c.fill_rect(int(cx + w * 0.70), int(top), int(cx + w), int(base), dark)
		c.fill_rect(int(cx - w), int(top), int(cx + w), int(top + g * 0.07), body)
		c.fill_rect(int(cx - w * 1.12), int(base), int(cx + w * 1.12), int(base + g * 0.07), body)
		c.fill_rect(int(cx - g * 0.035), int(top + g * 0.07), int(cx + g * 0.035), int(cy + g * 0.01), secondary)
		c.fill_rect(int(cx - w * 0.54), int(cy + g * 0.01), int(cx + w * 0.54), int(cy + g * 0.075), hi)
		c.fill_rect(int(cx - w * 0.46), int(cy + g * 0.18), int(cx + w * 0.46), int(cy + g * 0.22), dark)
		c.fill_polygon(PackedVector2Array([
			Vector2(cx - g * 0.10, cy + g * 0.17), Vector2(cx + g * 0.11, cy + g * 0.17),
			Vector2(cx + g * 0.08, cy + g * 0.25), Vector2(cx - g * 0.08, cy + g * 0.25)]), accent)
		var side := -1.0 if rng.chance(0.5) else 1.0
		c.line(cx + side * g * 0.04, top + g * 0.09, cx + side * g * 0.17, top + g * 0.02, dark)
		c.disc(cx + side * g * 0.19, top + g * 0.01, g * 0.035, hi)
	elif style == 1:
		# Cantilever screw press: one post, a long arm, and an offset anvil.
		var side := -1.0 if rng.chance(0.5) else 1.0
		var post_x := cx - side * g * 0.11
		var top := cy - g * 0.31
		var base := cy + g * 0.28
		var arm_x := post_x + side * g * 0.36
		c.fill_rect(int(post_x - g * 0.06), int(top), int(post_x + g * 0.06), int(base), dark)
		c.fill_rect(int(minf(post_x, arm_x)), int(top), int(maxf(post_x, arm_x)), int(top + g * 0.075), body)
		c.fill_rect(int(cx - g * 0.29), int(base), int(cx + g * 0.29), int(base + g * 0.08), secondary)
		var shelf_a := cx - side * g * 0.18
		var shelf_b := cx + side * g * 0.06
		c.fill_rect(int(minf(shelf_a, shelf_b)), int(cy + g * 0.03), int(maxf(shelf_a, shelf_b)), int(cy + g * 0.10), hi)
		c.fill_rect(int(cx - g * 0.12), int(cy + g * 0.18), int(cx + g * 0.12), int(cy + g * 0.23), accent)
		var foot_a := cx - side * g * 0.32
		var foot_b := cx - side * g * 0.08
		c.fill_rect(int(minf(foot_a, foot_b)), int(base - g * 0.04), int(maxf(foot_a, foot_b)), int(base), dark)
		c.line(post_x + side * g * 0.12, top + g * 0.07, post_x + side * g * 0.25, top - g * 0.07, dark)
		c.line(post_x + side * g * 0.25, top - g * 0.07, post_x + side * g * 0.34, top - g * 0.02, hi)
		c.disc(post_x + side * g * 0.35, top - g * 0.01, g * 0.04, hi)
	else:
		# A-frame press with splayed legs, a short ram and a wide die.
		var top := cy - g * 0.27
		var base := cy + g * 0.27
		var left := PackedVector2Array([
			Vector2(cx - w, base), Vector2(cx - w * 0.62, base),
			Vector2(cx - g * 0.045, top + g * 0.08), Vector2(cx - g * 0.13, top)])
		var right := PackedVector2Array([
			Vector2(cx + w, base), Vector2(cx + w * 0.62, base),
			Vector2(cx + g * 0.045, top + g * 0.08), Vector2(cx + g * 0.13, top)])
		c.fill_polygon(left, dark)
		c.fill_polygon(right, dark)
		c.fill_rect(int(cx - w), int(top), int(cx + w), int(top + g * 0.07), body)
		c.fill_rect(int(cx - w * 1.10), int(base), int(cx + w * 1.10), int(base + g * 0.07), secondary)
		c.fill_rect(int(cx - g * 0.035), int(top + g * 0.07), int(cx + g * 0.035), int(cy + g * 0.04), hi)
		c.fill_rect(int(cx - w * 0.58), int(cy + g * 0.04), int(cx + w * 0.58), int(cy + g * 0.11), accent)
		c.fill_rect(int(cx - w * 0.48), int(cy + g * 0.21), int(cx + w * 0.48), int(cy + g * 0.25), dark)
		c.line(cx - w * 0.60, cy - g * 0.04, cx + w * 0.60, cy - g * 0.04, secondary)


func _draw_crane(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var layout := rng.randi_range(0, 2)
	var base := cy + g * 0.29
	var side := 1.0
	if layout == 0:
		side = -1.0 if rng.chance(0.5) else 1.0
		var mast_x := cx - side * g * 0.08
		c.fill_rect(int(cx - g * 0.24), int(base), int(cx + g * 0.24), int(base + g * 0.06), dark)
		c.fill_rect(int(mast_x - g * 0.045), int(cy - g * 0.27), int(mast_x + g * 0.045), int(base), body)
		c.line(mast_x, cy + g * 0.18, mast_x + side * g * 0.28, cy - g * 0.12, dark)
		c.line(mast_x, cy - g * 0.26, mast_x + side * g * 0.32, cy - g * 0.26, body)
		c.line(mast_x + side * g * 0.30, cy - g * 0.26, mast_x + side * g * 0.30, cy - g * 0.20, hi)
		c.line(mast_x + side * g * 0.30, cy - g * 0.20, mast_x + side * g * 0.30, cy + g * 0.04, secondary)
		c.line(mast_x + side * g * 0.30, cy + g * 0.04, mast_x + side * g * 0.24, cy + g * 0.08, accent)
		c.line(mast_x + side * g * 0.24, cy + g * 0.08, mast_x + side * g * 0.30, cy + g * 0.14, accent)
		c.line(mast_x + side * g * 0.30, cy + g * 0.14, mast_x + side * g * 0.36, cy + g * 0.08, accent)
		c.fill_rect(int(cx - g * 0.18), int(base - g * 0.03), int(cx + g * 0.18), int(base), secondary)
	elif layout == 1:
		side = -1.0 if rng.chance(0.5) else 1.0
		var joint := Vector2(cx, cy - g * 0.08)
		var tip := Vector2(cx + side * g * 0.32, cy - g * 0.30)
		c.fill_rect(int(cx - g * 0.12), int(base), int(cx + g * 0.12), int(base + g * 0.06), dark)
		c.fill_rect(int(cx - g * 0.045), int(cy - g * 0.03), int(cx + g * 0.045), int(base), body)
		c.line(cx, cy - g * 0.03, joint.x, joint.y, body)
		c.line(joint.x, joint.y, tip.x, tip.y, hi)
		c.line(cx - g * 0.10, cy - g * 0.03, tip.x - side * g * 0.03, tip.y + g * 0.02, dark)
		c.fill_rect(int(minf(cx - side * g * 0.24, cx + side * g * 0.24)), int(cy - g * 0.08), int(maxf(cx - side * g * 0.24, cx + side * g * 0.24)), int(cy + g * 0.02), secondary)
		c.line(tip.x, tip.y, tip.x, cy + g * 0.02, secondary)
		c.line(tip.x, cy + g * 0.02, tip.x - side * g * 0.05, cy + g * 0.08, accent)
		c.line(tip.x - side * g * 0.05, cy + g * 0.08, tip.x + side * g * 0.01, cy + g * 0.13, accent)
	else:
		var apex := Vector2(cx, cy - g * 0.31)
		c.fill_rect(int(cx - g * 0.25), int(base), int(cx + g * 0.25), int(base + g * 0.06), dark)
		c.line(cx - g * 0.24, base, apex.x, apex.y, body)
		c.line(cx + g * 0.24, base, apex.x, apex.y, body)
		c.line(cx - g * 0.13, cy + g * 0.04, cx + g * 0.13, cy + g * 0.04, secondary)
		c.disc(apex.x, apex.y + g * 0.035, g * 0.055, dark)
		c.line(cx, apex.y + g * 0.08, cx, cy + g * 0.15, hi)
		c.line(cx, cy + g * 0.15, cx - g * 0.05, cy + g * 0.20, accent)
		c.line(cx - g * 0.05, cy + g * 0.20, cx + g * 0.01, cy + g * 0.26, accent)


func _draw_mill(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var style := rng.randi_range(0, 2)
	if style == 0:
		# Vertical mill wheel mounted on a stand with a hopper.
		var radius := g * rng.randf_range(0.18, 0.22)
		var wheel_x := cx + g * 0.08
		var wheel_y := cy - g * 0.04
		c.fill_rect(int(cx - g * 0.07), int(cy + g * 0.08), int(cx + g * 0.07), int(cy + g * 0.29), dark)
		c.fill_rect(int(cx - g * 0.22), int(cy + g * 0.27), int(cx + g * 0.24), int(cy + g * 0.32), body)
		var count := rng.randi_range(4, 6)
		for i in range(count):
			var a := TAU * float(i) / float(count)
			var dx := cos(a)
			var dy := sin(a)
			c.line(wheel_x + dx * radius * 0.24, wheel_y + dy * radius * 0.24,
				wheel_x + dx * radius, wheel_y + dy * radius, body if i % 2 == 0 else secondary)
		c.disc(wheel_x, wheel_y, radius * 0.30, dark, true)
		c.disc(wheel_x, wheel_y, radius * 0.12, hi)
		var hopper := PackedVector2Array([
			Vector2(cx - g * 0.27, cy - g * 0.28), Vector2(cx - g * 0.04, cy - g * 0.28),
			Vector2(cx - g * 0.10, cy - g * 0.12), Vector2(cx - g * 0.21, cy - g * 0.12)])
		c.fill_polygon(hopper, secondary)
		c.line(cx - g * 0.15, cy - g * 0.12, cx - g * 0.15, cy + g * 0.08, hi)
		c.fill_rect(int(cx - g * 0.27), int(cy + g * 0.10), int(cx - g * 0.12), int(cy + g * 0.21), accent)
	elif style == 1:
		# Tall grain mill: peaked hopper, broad grinding body, and split feet.
		var w := g * rng.randf_range(0.20, 0.24)
		var h := g * rng.randf_range(0.24, 0.29)
		var hopper := PackedVector2Array([
			Vector2(cx - w * 1.28, cy - h * 0.92), Vector2(cx - w * 0.82, cy - h * 1.42),
			Vector2(cx + w * 0.72, cy - h * 1.42), Vector2(cx + w * 1.25, cy - h * 0.92),
			Vector2(cx + w * 0.45, cy - h * 0.43), Vector2(cx - w * 0.48, cy - h * 0.43)])
		c.fill_polygon(hopper, secondary)
		c.fill_rect(int(cx - w), int(cy - h * 0.46), int(cx + w), int(cy + g * 0.18), body)
		c.fill_rect(int(cx - w * 0.78), int(cy + g * 0.16), int(cx - w * 0.42), int(cy + g * 0.38), dark)
		c.fill_rect(int(cx + w * 0.42), int(cy + g * 0.16), int(cx + w * 0.78), int(cy + g * 0.38), dark)
		c.fill_rect(int(cx - w * 1.28), int(cy + g * 0.36), int(cx + w * 1.28), int(cy + g * 0.42), dark)
		var wheel_x := cx + w * 0.88
		var wheel_y := cy - g * 0.02
		var radius := g * rng.randf_range(0.13, 0.17)
		c.disc(wheel_x, wheel_y, radius, body, true)
		c.disc(wheel_x, wheel_y, radius * 0.25, dark)
		c.line(wheel_x - radius * 0.72, wheel_y, wheel_x + radius * 0.72, wheel_y, hi)
		c.line(wheel_x, wheel_y - radius * 0.72, wheel_x, wheel_y + radius * 0.72, secondary)
		c.line(cx - w * 0.72, cy - g * 0.30, cx + w * 0.72, cy - g * 0.30, hi)
	else:
		# Low hand-mill table with a thick stone and a long crank arm.
		var side := -1.0 if rng.chance(0.5) else 1.0
		var body_w := g * rng.randf_range(0.27, 0.32)
		c.fill_rect(int(cx - body_w), int(cy + g * 0.10), int(cx + body_w), int(cy + g * 0.22), dark)
		c.fill_rect(int(cx - body_w * 0.78), int(cy + g * 0.22), int(cx - body_w * 0.56), int(cy + g * 0.36), body)
		c.fill_rect(int(cx + body_w * 0.56), int(cy + g * 0.22), int(cx + body_w * 0.78), int(cy + g * 0.36), body)
		c.fill_rect(int(cx - body_w * 1.12), int(cy + g * 0.34), int(cx + body_w * 1.12), int(cy + g * 0.40), secondary)
		var radius := g * rng.randf_range(0.18, 0.22)
		var wheel_x := cx - side * g * 0.04
		var wheel_y := cy - g * 0.04
		c.ellipse(wheel_x, wheel_y, radius * 1.10, radius * 0.74, body)
		c.line(wheel_x - radius * 0.75, wheel_y, wheel_x + radius * 0.75, wheel_y, hi)
		c.disc(wheel_x, wheel_y, radius * 0.20, dark)
		c.fill_polygon(PackedVector2Array([
			Vector2(cx - side * g * 0.31, cy - g * 0.29), Vector2(cx - side * g * 0.06, cy - g * 0.29),
			Vector2(cx - side * g * 0.12, cy - g * 0.12), Vector2(cx - side * g * 0.25, cy - g * 0.12)]), accent)
		var ax := cx + side * body_w * 0.88
		c.line(ax, cy + g * 0.02, ax + side * g * 0.20, cy - g * 0.18, dark)
		c.line(ax + side * g * 0.20, cy - g * 0.18, ax + side * g * 0.29, cy - g * 0.08, hi)


func _draw_bellows(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var side := -1.0 if rng.chance(0.5) else 1.0
	var left := cx - side * g * 0.25
	var right := cx + side * g * 0.12
	c.fill_rect(int(minf(left - g * 0.05, right + g * 0.05)), int(cy - g * 0.17),
		int(maxf(left - g * 0.05, right + g * 0.05)), int(cy + g * 0.17), body)
	var folds := rng.randi_range(3, 5)
	for i in range(folds):
		var t := float(i + 1) / float(folds + 1)
		var x := left + (right - left) * t
		c.line(x, cy - g * 0.16, x + side * g * 0.035, cy, dark)
		c.line(x + side * g * 0.035, cy, x, cy + g * 0.16, hi if i % 2 == 0 else secondary)
	c.fill_rect(int(left - g * 0.07), int(cy - g * 0.23), int(left + g * 0.07), int(cy + g * 0.23), dark)
	c.fill_rect(int(right - g * 0.07), int(cy - g * 0.23), int(right + g * 0.07), int(cy + g * 0.23), dark)
	var nozzle_x := right + side * g * 0.30
	c.line(right, cy - g * 0.06, nozzle_x, cy - g * 0.06, secondary)
	c.line(right, cy + g * 0.06, nozzle_x, cy + g * 0.06, secondary)
	c.line(nozzle_x, cy - g * 0.06, nozzle_x, cy + g * 0.06, hi)
	c.fill_rect(int(cx - g * 0.12), int(cy + g * 0.17), int(cx + g * 0.12), int(cy + g * 0.27), dark)


func _draw_crystal_regulator(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var style := rng.randi_range(0, 2)
	if style == 0:
		# Tripod cage with converging struts around the contained core.
		var w := g * rng.randf_range(0.24, 0.28)
		var h := g * rng.randf_range(0.22, 0.27)
		var left_leg := PackedVector2Array([
			Vector2(cx - w, cy + h * 0.70), Vector2(cx - w * 0.74, cy + h * 0.70),
			Vector2(cx - g * 0.025, cy - h * 0.72), Vector2(cx - g * 0.11, cy - h * 0.54)])
		var right_leg := PackedVector2Array([
			Vector2(cx + w, cy + h * 0.70), Vector2(cx + w * 0.74, cy + h * 0.70),
			Vector2(cx + g * 0.025, cy - h * 0.72), Vector2(cx + g * 0.11, cy - h * 0.54)])
		c.fill_polygon(left_leg, dark)
		c.fill_polygon(right_leg, dark)
		c.fill_rect(int(cx - w), int(cy + h * 0.64), int(cx + w), int(cy + h * 0.78), body)
		var crystal := PackedVector2Array([
			Vector2(cx, cy - h * 0.48), Vector2(cx + w * 0.24, cy - g * 0.025),
			Vector2(cx + w * 0.12, cy + h * 0.37), Vector2(cx - w * 0.14, cy + h * 0.40),
			Vector2(cx - w * 0.25, cy - g * 0.02)])
		c.fill_polygon(crystal, accent)
		c.line(cx, cy - h * 0.36, cx, cy + h * 0.25, hi)
		c.line(cx - w * 0.28, cy + g * 0.05, cx + w * 0.28, cy + g * 0.05, secondary)
		c.fill_rect(int(cx - g * 0.12), int(cy + h * 0.78), int(cx + g * 0.12), int(cy + h * 0.91), dark)
	elif style == 1:
		# A vertical tuning-fork cage instead of a triangular profile.
		var w := g * rng.randf_range(0.21, 0.25)
		var top := cy - g * 0.32
		var base := cy + g * 0.30
		var left := PackedVector2Array([
			Vector2(cx - w, base), Vector2(cx - w * 0.72, base),
			Vector2(cx - w * 0.58, top + g * 0.12), Vector2(cx - w * 0.94, top)])
		var right := PackedVector2Array([
			Vector2(cx + w * 0.72, base), Vector2(cx + w, base),
			Vector2(cx + w * 0.94, top), Vector2(cx + w * 0.58, top + g * 0.12)])
		c.fill_polygon(left, dark)
		c.fill_polygon(right, dark)
		c.fill_rect(int(cx - w * 1.06), int(top), int(cx - w * 0.45), int(top + g * 0.06), hi)
		c.fill_rect(int(cx + w * 0.45), int(top), int(cx + w * 1.06), int(top + g * 0.06), hi)
		c.fill_polygon(PackedVector2Array([
			Vector2(cx, cy - g * 0.18), Vector2(cx + g * 0.12, cy),
			Vector2(cx + g * 0.07, cy + g * 0.17), Vector2(cx - g * 0.07, cy + g * 0.17),
			Vector2(cx - g * 0.12, cy)]), accent)
		c.fill_rect(int(cx - g * 0.20), int(cy + g * 0.25), int(cx + g * 0.20), int(cy + g * 0.32), secondary)
		c.line(cx, cy - g * 0.12, cx, cy + g * 0.12, hi)
	else:
		# Crowned crystal on a wide four-point yoke and pedestal.
		var w := g * rng.randf_range(0.25, 0.30)
		var h := g * rng.randf_range(0.22, 0.27)
		c.fill_polygon(PackedVector2Array([
			Vector2(cx - g * 0.07, cy - h), Vector2(cx + g * 0.07, cy - h),
			Vector2(cx + w * 0.42, cy - h * 0.26), Vector2(cx + w, cy - g * 0.02),
			Vector2(cx + w * 0.48, cy + g * 0.04), Vector2(cx + w * 0.24, cy + h * 0.44),
			Vector2(cx - w * 0.24, cy + h * 0.44), Vector2(cx - w * 0.48, cy + g * 0.04),
			Vector2(cx - w, cy - g * 0.02), Vector2(cx - w * 0.42, cy - h * 0.26)]), body)
		c.fill_polygon(PackedVector2Array([
			Vector2(cx, cy - h * 0.48), Vector2(cx + g * 0.09, cy - g * 0.02),
			Vector2(cx + g * 0.04, cy + h * 0.20), Vector2(cx - g * 0.04, cy + h * 0.20),
			Vector2(cx - g * 0.09, cy - g * 0.02)]), accent)
		c.fill_rect(int(cx - w * 0.56), int(cy + h * 0.37), int(cx + w * 0.56), int(cy + h * 0.47), dark)
		c.fill_rect(int(cx - g * 0.10), int(cy + h * 0.47), int(cx + g * 0.10), int(cy + h * 0.63), dark)
		c.line(cx, cy - h * 0.40, cx, cy + h * 0.13, hi)


func _clay_point(center: Vector2, dx: float, dy: float, turns: int) -> Vector2:
	var offset := Vector2(dx, dy)
	for i in range(turns % 4):
		offset = Vector2(-offset.y, offset.x)
	return center + offset


func _draw_clay(c: SigilPixelCanvas, form: String, m: Vector2, g: float,
		rng: SigilRng, body: Color, dark: Color, hi: Color, accent: Color,
		secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	match form:
		"clay_lump":
			# Seed selects a boulder profile, a tall knuckle, or two fused masses.
			var style := rng.randi_range(0, 2)
			if style == 0:
				var rx := g * rng.randf_range(0.31, 0.36)
				var ry := g * rng.randf_range(0.24, 0.29)
				var pts := _jagged_poly(m + Vector2(-g * 0.02, g * 0.02), rx, ry,
					rng.randi_range(7, 10), g, rng, 0.38, -PI * 0.5)
				c.fill_polygon(pts, body)
				c.fill_polygon(PackedVector2Array([pts[0], pts[1],
					Vector2(cx + rx * 0.18, cy - ry * 0.10), pts[pts.size() - 1]]), secondary)
				c.line(cx - rx * 0.54, cy - ry * 0.05, cx - rx * 0.21, cy - ry * 0.39, dark)
				c.line(cx + rx * 0.15, cy + ry * 0.05, cx + rx * 0.50, cy - ry * 0.19, hi)
			elif style == 1:
				var rx := g * rng.randf_range(0.23, 0.28)
				var ry := g * rng.randf_range(0.32, 0.36)
				var pts := _jagged_poly(m + Vector2(g * 0.025, 0.0), rx, ry,
					rng.randi_range(7, 9), g, rng, 0.34, -PI * 0.5)
				c.fill_polygon(pts, body)
				c.fill_polygon(PackedVector2Array([pts[0], pts[1], Vector2(cx + g * 0.02, cy - g * 0.02), pts[pts.size() - 1]]), secondary)
				c.line(cx - rx * 0.45, cy + ry * 0.20, cx - rx * 0.14, cy - ry * 0.27, dark)
				c.line(cx + rx * 0.05, cy - ry * 0.04, cx + rx * 0.36, cy - ry * 0.42, hi)
			else:
				var rx := g * rng.randf_range(0.19, 0.23)
				var ry := g * rng.randf_range(0.19, 0.24)
				c.ellipse(cx - rx * 0.63, cy + ry * 0.12, rx, ry, body)
				c.ellipse(cx + rx * 0.52, cy - ry * 0.12, rx * 0.96, ry * 0.86, secondary)
				c.fill_polygon(PackedVector2Array([
					Vector2(cx - rx * 0.75, cy + ry * 0.05), Vector2(cx - rx * 0.30, cy - ry * 0.62),
					Vector2(cx + rx * 0.28, cy - ry * 0.56), Vector2(cx + rx * 0.10, cy - ry * 0.05)]), hi)
				c.line(cx - rx * 0.58, cy + ry * 0.25, cx + rx * 0.30, cy + ry * 0.28, dark)

		"clay_fold":
			# Seed selects a peaked flap, broad double fold, or upright pleat.
			var style := rng.randi_range(0, 2)
			if style == 0:
				var w := g * rng.randf_range(0.30, 0.35)
				var h := g * rng.randf_range(0.25, 0.30)
				var base := PackedVector2Array([
					Vector2(cx - w, cy + h * 0.28), Vector2(cx - w * 0.83, cy - h * 0.02),
					Vector2(cx - w * 0.42, cy - h * 0.13), Vector2(cx + w * 0.20, cy - h * 0.02),
					Vector2(cx + w, cy + h * 0.34), Vector2(cx + w * 0.65, cy + h * 0.72),
					Vector2(cx - w * 0.55, cy + h * 0.74)])
				var flap := PackedVector2Array([
					Vector2(cx - w * 0.58, cy + h * 0.30), Vector2(cx - w * 0.46, cy - h * 0.28),
					Vector2(cx - w * 0.10, cy - h * 0.82), Vector2(cx + w * 0.15, cy - h * 0.68),
					Vector2(cx + w * 0.34, cy - h * 0.12), Vector2(cx + w * 0.12, cy + h * 0.12)])
				c.fill_polygon(base, body)
				c.fill_polygon(flap, secondary)
				c.line(cx - w * 0.51, cy + h * 0.27, cx - w * 0.10, cy - h * 0.33, dark)
				c.line(cx - w * 0.10, cy - h * 0.33, cx + w * 0.24, cy - h * 0.08, hi)
				c.line(cx - w * 0.62, cy + h * 0.50, cx + w * 0.58, cy + h * 0.49, dark)
			elif style == 1:
				var w := g * rng.randf_range(0.34, 0.39)
				var h := g * rng.randf_range(0.15, 0.19)
				var base := PackedVector2Array([
					Vector2(cx - w, cy + h * 0.10), Vector2(cx - w * 0.75, cy - h * 0.78),
					Vector2(cx - w * 0.25, cy - h), Vector2(cx + w * 0.74, cy - h * 0.72),
					Vector2(cx + w, cy + h * 0.14), Vector2(cx + w * 0.57, cy + h),
					Vector2(cx - w * 0.62, cy + h * 0.86)])
				c.fill_polygon(base, body)
				c.fill_polygon(PackedVector2Array([
					Vector2(cx - w * 0.73, cy - h * 0.48), Vector2(cx - w * 0.25, cy - h),
					Vector2(cx + w * 0.04, cy - h * 0.10), Vector2(cx - w * 0.46, cy + h * 0.10)]), secondary)
				c.fill_polygon(PackedVector2Array([
					Vector2(cx - w * 0.20, cy + h * 0.08), Vector2(cx + w * 0.24, cy - h * 0.48),
					Vector2(cx + w * 0.76, cy - h * 0.42), Vector2(cx + w * 0.54, cy + h * 0.26)]), accent)
				c.line(cx - w * 0.72, cy + h * 0.48, cx + w * 0.59, cy + h * 0.42, dark)
			else:
				var w := g * rng.randf_range(0.22, 0.27)
				var h := g * rng.randf_range(0.31, 0.36)
				var pleat := PackedVector2Array([
					Vector2(cx - w, cy + h * 0.76), Vector2(cx - w * 0.72, cy + h * 0.24),
					Vector2(cx - w * 0.88, cy - h * 0.14), Vector2(cx - w * 0.35, cy - h * 0.03),
					Vector2(cx + w * 0.02, cy - h * 0.60), Vector2(cx + w * 0.30, cy - h * 0.22),
					Vector2(cx + w, cy - h * 0.13), Vector2(cx + w * 0.76, cy + h * 0.43),
					Vector2(cx + w * 0.42, cy + h * 0.82)])
				c.fill_polygon(pleat, body)
				c.fill_polygon(PackedVector2Array([
					Vector2(cx - w * 0.78, cy + h * 0.35), Vector2(cx - w * 0.34, cy - h * 0.04),
					Vector2(cx + w * 0.04, cy - h * 0.56), Vector2(cx + w * 0.24, cy - h * 0.18)]), secondary)
				c.line(cx - w * 0.42, cy + h * 0.55, cx + w * 0.45, cy + h * 0.52, dark)
				c.line(cx - w * 0.13, cy - h * 0.37, cx + w * 0.25, cy - h * 0.04, hi)

		"clay_coil":
			# Three joined bands leave a real open C; seed rotates the opening around the mass.
			var rx := g * rng.randf_range(0.31, 0.35)
			var ry := g * rng.randf_range(0.30, 0.34)
			var side := -1.0 if rng.chance(0.5) else 1.0
			var turns := rng.randi_range(0, 3)
			var top := PackedVector2Array([
				_clay_point(m, side * rx * -0.83, ry * -1.0, turns),
				_clay_point(m, side * rx * 0.43, ry * -1.0, turns),
				_clay_point(m, side * rx * 0.29, ry * -0.52, turns),
				_clay_point(m, side * rx * -0.60, ry * -0.50, turns)])
			var spine := PackedVector2Array([
				_clay_point(m, side * rx * -1.00, ry * -0.65, turns),
				_clay_point(m, side * rx * -0.56, ry * -0.58, turns),
				_clay_point(m, side * rx * -0.56, ry * 0.62, turns),
				_clay_point(m, side * rx * -0.96, ry * 0.84, turns)])
			var bottom := PackedVector2Array([
				_clay_point(m, side * rx * -0.88, ry * 0.48, turns),
				_clay_point(m, side * rx * 0.40, ry * 0.46, turns),
				_clay_point(m, side * rx * 0.62, ry * 1.0, turns),
				_clay_point(m, side * rx * -0.78, ry * 1.0, turns)])
			c.fill_polygon(top, body)
			c.fill_polygon(spine, body)
			c.fill_polygon(bottom, body)
			var coil_a := _clay_point(m, side * rx * -0.66, ry * -0.82, turns)
			var coil_b := _clay_point(m, side * rx * 0.26, ry * -0.78, turns)
			c.line(coil_a.x, coil_a.y, coil_b.x, coil_b.y, hi)
			coil_a = _clay_point(m, side * rx * -0.72, ry * -0.33, turns)
			coil_b = _clay_point(m, side * rx * -0.15, ry * -0.25, turns)
			c.line(coil_a.x, coil_a.y, coil_b.x, coil_b.y, dark)
			coil_a = _clay_point(m, side * rx * -0.70, ry * 0.30, turns)
			coil_b = _clay_point(m, side * rx * -0.10, ry * 0.37, turns)
			c.line(coil_a.x, coil_a.y, coil_b.x, coil_b.y, secondary)

		"clay_slab":
			# A cut plate can be wide, upright, or diagonally laid across the icon.
			var style := rng.randi_range(0, 2)
			var w: float
			var h: float
			var turns := 0
			if style == 0:
				w = g * rng.randf_range(0.36, 0.40)
				h = g * rng.randf_range(0.13, 0.17)
			elif style == 1:
				w = g * rng.randf_range(0.25, 0.29)
				h = g * rng.randf_range(0.31, 0.35)
			else:
				w = g * rng.randf_range(0.35, 0.39)
				h = g * rng.randf_range(0.14, 0.18)
				turns = 1 if rng.chance(0.5) else 3
			var slab := PackedVector2Array([
				_clay_point(m, -w, -h * 0.42, turns), _clay_point(m, -w * 0.73, -h, turns),
				_clay_point(m, w * 0.53, -h * 0.91, turns), _clay_point(m, w, -h * 0.22, turns),
				_clay_point(m, w * 0.84, h * 0.73, turns), _clay_point(m, -w * 0.66, h, turns)])
			c.fill_polygon(slab, body)
			c.fill_polygon(PackedVector2Array([
				slab[0], slab[1], _clay_point(m, -w * 0.02, -h * 0.10, turns),
				_clay_point(m, -w * 0.24, h * 0.15, turns)]), secondary)
			var line_a := _clay_point(m, -w * 0.57, h * 0.29, turns)
			var line_b := _clay_point(m, w * 0.58, h * 0.23, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, dark)
			line_a = _clay_point(m, -w * 0.38, -h * 0.40, turns)
			line_b = _clay_point(m, w * 0.34, -h * 0.34, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, hi)

		"clay_wedge":
			# Blade, roof, or side-leaning cut mass selected by seed.
			var style := rng.randi_range(0, 2)
			var w := g * rng.randf_range(0.25, 0.31)
			var h := g * rng.randf_range(0.30, 0.36)
			var turns := 0
			if style == 1:
				turns = 1
			elif style == 2:
				turns = 3
			var outline: Array[Vector2] = []
			if style == 0:
				outline = [Vector2(-w, h * 0.72), Vector2(-w * 0.90, h * 0.14),
					Vector2(-w * 0.55, -h * 0.51), Vector2(-w * 0.13, -h),
					Vector2(w * 0.16, -h * 0.88), Vector2(w * 0.62, -h * 0.27),
					Vector2(w, h * 0.55), Vector2(w * 0.45, h * 0.82)]
			elif style == 1:
				outline = [Vector2(-w, -h * 0.38), Vector2(-w * 0.30, -h * 0.72),
					Vector2(w * 0.20, -h), Vector2(w * 0.46, -h * 0.44),
					Vector2(w, h * 0.50), Vector2(w * 0.38, h * 0.77), Vector2(-w * 0.84, h * 0.54)]
			else:
				outline = [Vector2(-w, h * 0.72), Vector2(-w * 0.80, h * 0.15),
					Vector2(-w * 0.50, -h * 0.20), Vector2(-w * 0.05, -h * 0.30),
					Vector2(w * 0.28, -h * 0.78), Vector2(w * 0.52, -h * 0.22),
					Vector2(w, h * 0.56), Vector2(w * 0.43, h * 0.82)]
			var wedge := PackedVector2Array()
			for point in outline:
				wedge.append(_clay_point(m, point.x, point.y, turns))
			c.fill_polygon(wedge, body)
			var facet := PackedVector2Array([wedge[1], wedge[2], wedge[3], _clay_point(m, w * 0.12, 0.0, turns)])
			c.fill_polygon(facet, secondary)
			var line_a := _clay_point(m, -w * 0.64, h * 0.48, turns)
			var line_b := _clay_point(m, w * 0.60, h * 0.49, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, dark)
			line_a = _clay_point(m, -w * 0.15, -h * 0.78, turns)
			line_b = _clay_point(m, w * 0.03, -h * 0.16, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, hi)

		"clay_cracked":
			# Spalled mass: seed changes aspect and fracture rhythm, not merely the cracks.
			var style := rng.randi_range(0, 2)
			var rx: float
			var ry: float
			if style == 0:
				rx = g * rng.randf_range(0.32, 0.36)
				ry = g * rng.randf_range(0.25, 0.29)
			elif style == 1:
				rx = g * rng.randf_range(0.24, 0.28)
				ry = g * rng.randf_range(0.32, 0.36)
			else:
				rx = g * rng.randf_range(0.30, 0.35)
				ry = g * rng.randf_range(0.29, 0.34)
			var pts := _jagged_poly(m, rx, ry, rng.randi_range(8, 12), g, rng, 0.46, -PI * 0.5)
			c.fill_polygon(pts, body)
			var fork := Vector2(cx + rng.randf_range(-rx * 0.18, rx * 0.18), cy + rng.randf_range(-ry * 0.14, ry * 0.14))
			c.line(cx - rx * 0.78, cy - ry * 0.08, fork.x, fork.y, dark)
			c.line(fork.x, fork.y, cx + rx * 0.74, cy - ry * 0.60, dark)
			c.line(fork.x, fork.y, cx + rx * 0.55, cy + ry * 0.68, dark)
			c.line(cx - rx * 0.20, cy + ry * 0.75, cx - rx * 0.03, cy + ry * 0.18, secondary)
			c.fill_polygon(PackedVector2Array([pts[0], pts[1], Vector2(cx - rx * 0.08, cy - ry * 0.08)]), hi)

		"clay_pinched":
			# Wide bowl, narrow blank, or tall pinch-pot; each leaves an open mouth.
			var style := rng.randi_range(0, 2)
			var topw: float
			var inner: float
			var basew: float
			var h: float
			if style == 0:
				topw = g * rng.randf_range(0.31, 0.34)
				inner = g * rng.randf_range(0.19, 0.22)
				basew = g * rng.randf_range(0.17, 0.21)
				h = g * rng.randf_range(0.32, 0.36)
			elif style == 1:
				topw = g * rng.randf_range(0.35, 0.39)
				inner = g * rng.randf_range(0.25, 0.28)
				basew = g * rng.randf_range(0.24, 0.28)
				h = g * rng.randf_range(0.22, 0.26)
			else:
				topw = g * rng.randf_range(0.25, 0.28)
				inner = g * rng.randf_range(0.14, 0.17)
				basew = g * rng.randf_range(0.18, 0.22)
				h = g * rng.randf_range(0.35, 0.39)
			var shift := rng.randf_range(-g * 0.025, g * 0.025)
			var left := PackedVector2Array([
				Vector2(cx - topw, cy - h * 0.88), Vector2(cx - inner + shift, cy - h * 0.82),
				Vector2(cx - basew * 0.52 + shift, cy + h * 0.60), Vector2(cx - basew * 0.72, cy + h * 0.72)])
			var right := PackedVector2Array([
				Vector2(cx + inner + shift, cy - h * 0.82), Vector2(cx + topw, cy - h * 0.88),
				Vector2(cx + basew * 0.72, cy + h * 0.72), Vector2(cx + basew * 0.52 + shift, cy + h * 0.60)])
			var foot := PackedVector2Array([
				Vector2(cx - basew * 0.72, cy + h * 0.49), Vector2(cx + basew * 0.72, cy + h * 0.49),
				Vector2(cx + basew * 0.56, cy + h), Vector2(cx - basew * 0.56, cy + h)])
			c.fill_polygon(left, body)
			c.fill_polygon(right, body)
			c.fill_polygon(foot, body)
			c.fill_polygon(PackedVector2Array([
				Vector2(cx - topw, cy - h * 0.88), Vector2(cx - inner + shift, cy - h * 0.82),
				Vector2(cx - inner + shift * 0.5, cy - h * 0.68), Vector2(cx - topw * 1.08, cy - h * 0.70)]), secondary)
			c.fill_polygon(PackedVector2Array([
				Vector2(cx + inner + shift, cy - h * 0.82), Vector2(cx + topw, cy - h * 0.88),
				Vector2(cx + topw * 1.08, cy - h * 0.70), Vector2(cx + inner + shift * 0.5, cy - h * 0.68)]), hi)
			c.line(cx - basew * 0.62, cy + h * 0.55, cx + basew * 0.62, cy + h * 0.55, dark)

		"clay_kneaded":
			# The number and arrangement of fused thumb-pressed lobes come from the seed.
			var style := rng.randi_range(0, 2)
			var scale := rng.randf_range(0.96, 1.05)
			var turns := rng.randi_range(0, 3)
			var lobes: Array[Vector4] = []
			if style == 0:
				lobes = [Vector4(-0.19, 0.08, 0.17, 0.17), Vector4(0.0, -0.11, 0.18, 0.19), Vector4(0.19, 0.07, 0.16, 0.17)]
			elif style == 1:
				lobes = [Vector4(-0.08, 0.20, 0.17, 0.16), Vector4(0.10, 0.01, 0.16, 0.18), Vector4(-0.06, -0.18, 0.17, 0.18)]
			else:
				lobes = [Vector4(-0.15, 0.04, 0.14, 0.14), Vector4(0.0, -0.16, 0.15, 0.15), Vector4(0.17, 0.03, 0.15, 0.14), Vector4(0.01, 0.19, 0.16, 0.13)]
			for i in range(lobes.size()):
				var lobe: Vector4 = lobes[i]
				var p := _clay_point(m, lobe.x * g * scale, lobe.y * g * scale, turns)
				c.ellipse(p.x, p.y, g * lobe.z * scale, g * lobe.w * scale, body if i % 2 == 0 else secondary)
			c.line(cx - g * 0.24, cy + g * 0.02, cx - g * 0.10, cy - g * 0.12, dark)
			c.line(cx + g * 0.04, cy - g * 0.15, cx + g * 0.13, cy + g * 0.01, dark)
			c.line(cx + g * 0.21, cy + g * 0.15, cx + g * 0.34, cy + g * 0.01, hi)

		"clay_roll":
			# Rope can snake, zigzag, or climb vertically; each variant changes its outline.
			var style := rng.randi_range(0, 2)
			var turns := rng.randi_range(0, 3)
			var side := -1.0 if rng.chance(0.5) else 1.0
			var points: Array[Vector2] = []
			if style == 0:
				points = [Vector2(-0.35, 0.15), Vector2(-0.30, -0.03), Vector2(-0.16, -0.18), Vector2(0.02, -0.20), Vector2(0.18, -0.09), Vector2(0.29, 0.07), Vector2(0.34, 0.23)]
			elif style == 1:
				points = [Vector2(-0.35, -0.18), Vector2(-0.22, -0.02), Vector2(-0.08, 0.16), Vector2(0.04, 0.18), Vector2(0.16, 0.02), Vector2(0.29, -0.13), Vector2(0.35, 0.10)]
			else:
				points = [Vector2(-0.34, 0.0), Vector2(-0.22, -0.17), Vector2(-0.06, -0.18), Vector2(0.08, -0.02), Vector2(0.22, 0.15), Vector2(0.34, 0.15)]
			var radius := g * rng.randf_range(0.095, 0.115)
			for i in range(points.size()):
				var point: Vector2 = points[i]
				var p := _clay_point(m, side * point.x * g, point.y * g, turns)
				c.disc(p.x, p.y, radius, body)
				if i > 0:
					var prior: Vector2 = points[i - 1]
					var a := _clay_point(m, side * prior.x * g, prior.y * g, turns)
					c.line(a.x, a.y, p.x, p.y, secondary if i % 2 == 1 else dark)
			var first: Vector2 = points[0]
			var last: Vector2 = points[points.size() - 1]
			var p_first := _clay_point(m, side * first.x * g, first.y * g, turns)
			var p_last := _clay_point(m, side * last.x * g, last.y * g, turns)
			c.disc(p_first.x, p_first.y, radius * 0.55, hi)
			c.disc(p_last.x, p_last.y, radius * 0.55, accent)

		"clay_puck":
			# Compact puck, thick hand-pressed disk, or standing round blank.
			var style := rng.randi_range(0, 2)
			var rx: float
			var ry: float
			if style == 0:
				rx = g * rng.randf_range(0.24, 0.28)
				ry = g * rng.randf_range(0.13, 0.16)
			elif style == 1:
				rx = g * rng.randf_range(0.21, 0.24)
				ry = g * rng.randf_range(0.20, 0.23)
			else:
				rx = g * rng.randf_range(0.16, 0.19)
				ry = g * rng.randf_range(0.25, 0.29)
			var turns := rng.randi_range(0, 3)
			var outline: Array[Vector2] = [
				Vector2(-rx * 0.94, ry * 0.20), Vector2(-rx * 0.87, -ry * 0.43),
				Vector2(-rx * 0.50, -ry * 0.91), Vector2(rx * 0.45, -ry * 0.96),
				Vector2(rx * 0.88, -ry * 0.43), Vector2(rx, ry * 0.16),
				Vector2(rx * 0.74, ry * 0.72), Vector2(-rx * 0.70, ry * 0.76)]
			var puck := PackedVector2Array()
			for point in outline:
				puck.append(_clay_point(m, point.x, point.y, turns))
			c.fill_polygon(puck, body)
			var facet := PackedVector2Array([
				_clay_point(m, -rx * 0.78, -ry * 0.18, turns), _clay_point(m, -rx * 0.49, -ry * 0.78, turns),
				_clay_point(m, rx * 0.28, -ry * 0.78, turns), _clay_point(m, rx * 0.70, -ry * 0.16, turns)])
			c.fill_polygon(facet, secondary)
			var line_a := _clay_point(m, -rx * 0.66, ry * 0.39, turns)
			var line_b := _clay_point(m, rx * 0.61, ry * 0.37, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, dark)
			line_a = _clay_point(m, -rx * 0.38, -ry * 0.20, turns)
			line_b = _clay_point(m, rx * 0.38, -ry * 0.20, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, hi)

		"clay_block":
			# Deliberately different aspect ratios stop every formed block reading as a square.
			var style := rng.randi_range(0, 2)
			var w: float
			var h: float
			if style == 0:
				w = g * rng.randf_range(0.25, 0.29)
				h = g * rng.randf_range(0.32, 0.36)
			elif style == 1:
				w = g * rng.randf_range(0.34, 0.38)
				h = g * rng.randf_range(0.22, 0.26)
			else:
				w = g * rng.randf_range(0.29, 0.33)
				h = g * rng.randf_range(0.29, 0.33)
			var turns := rng.randi_range(0, 3)
			var outline: Array[Vector2] = [
				Vector2(-w * 0.78, -h), Vector2(w * 0.78, -h), Vector2(w, -h * 0.72),
				Vector2(w * 0.91, h * 0.72), Vector2(w * 0.66, h), Vector2(-w * 0.72, h),
				Vector2(-w, h * 0.64), Vector2(-w, -h * 0.72)]
			var block := PackedVector2Array()
			for point in outline:
				block.append(_clay_point(m, point.x, point.y, turns))
			c.fill_polygon(block, body)
			var facet := PackedVector2Array([block[0], block[1],
				_clay_point(m, w * 0.20, -h * 0.77, turns), _clay_point(m, -w * 0.15, -h * 0.73, turns)])
			c.fill_polygon(facet, secondary)
			var line_a := _clay_point(m, -w * 0.72, h * 0.40, turns)
			var line_b := _clay_point(m, w * 0.69, h * 0.39, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, dark)
			line_a = _clay_point(m, -w * 0.54, -h * 0.43, turns)
			line_b = _clay_point(m, w * 0.50, -h * 0.43, turns)
			c.line(line_a.x, line_a.y, line_b.x, line_b.y, hi)

		"clay_gathered":
			# Broad mound, finger-ridged sheet, or leaning heap selected by the seed.
			var style := rng.randi_range(0, 2)
			if style == 0:
				var w := g * rng.randf_range(0.30, 0.34)
				var h := g * rng.randf_range(0.29, 0.33)
				var foot := PackedVector2Array([
					Vector2(cx - w, cy + h * 0.47), Vector2(cx - w * 0.82, cy + h * 0.05),
					Vector2(cx - w * 0.34, cy + h * 0.14), Vector2(cx + w * 0.28, cy + h * 0.10),
					Vector2(cx + w * 0.90, cy + h * 0.34), Vector2(cx + w * 0.70, cy + h),
					Vector2(cx - w * 0.66, cy + h)])
				c.fill_polygon(foot, body)
				c.ellipse(cx - g * 0.02, cy - h * 0.10, g * 0.20, g * 0.28, body)
				c.ellipse(cx - g * 0.18, cy - h * 0.30, g * 0.115, g * 0.16, secondary)
				c.ellipse(cx + g * 0.04, cy - h * 0.39, g * 0.12, g * 0.18, body)
				c.ellipse(cx + g * 0.22, cy - h * 0.24, g * 0.105, g * 0.15, accent)
			elif style == 1:
				c.ellipse(cx, cy + g * 0.16, g * 0.34, g * 0.16, body)
				for i in range(4):
					# Смещения из литерала: инференс float невозможен без явного типа,
					# поэтому раскрываем массив в float-выражение.
					var xx := ([-0.27, -0.10, 0.10, 0.27] as Array)[i] as float
					var x := cx + xx * g
					var height := 0.23 if i % 2 == 0 else 0.18
					c.ellipse(x, cy - g * (0.12 if i % 2 == 0 else 0.04), g * 0.095, g * height, body if i % 2 == 0 else secondary)
					c.line(x - g * 0.025, cy - g * 0.13, x + g * 0.02, cy + g * 0.13, dark)
			else:
				c.fill_polygon(PackedVector2Array([
					Vector2(cx - g * 0.32, cy + g * 0.28), Vector2(cx - g * 0.36, cy + g * 0.10),
					Vector2(cx - g * 0.22, cy + g * 0.02), Vector2(cx - g * 0.03, cy + g * 0.13),
					Vector2(cx + g * 0.06, cy - g * 0.26), Vector2(cx + g * 0.24, cy - g * 0.14),
					Vector2(cx + g * 0.34, cy + g * 0.10), Vector2(cx + g * 0.26, cy + g * 0.30)]), body)
				c.ellipse(cx - g * 0.16, cy + g * 0.03, g * 0.19, g * 0.20, secondary)
				c.ellipse(cx + g * 0.16, cy - g * 0.12, g * 0.17, g * 0.22, body)
			c.line(cx - g * 0.18, cy - g * 0.07, cx - g * 0.08, cy + g * 0.23, dark)
			c.line(cx + g * 0.04, cy - g * 0.25, cx + g * 0.16, cy + g * 0.14, dark)
			c.line(cx - g * 0.55, cy + g * 0.63, cx + g * 0.56, cy + g * 0.62, hi)
		_:
			# Unknown clay subtypes remain clay, never fall through to a crystal.
			_draw_clay(c, "clay_lump", m, g, rng, body, dark, hi, accent, secondary)


func _draw_walker_blueprint(c: SigilPixelCanvas, m: Vector2, g: float, rng: SigilRng,
		body: Color, dark: Color, hi: Color, accent: Color, secondary: Color) -> void:
	var cx := m.x
	var cy := m.y
	var variant := rng.randi_range(0, 1)
	if variant == 1:
		# Low quadruped chassis, forward sensor, four articulated legs, one tool arm.
		var chassis := PackedVector2Array([
			Vector2(cx - g * 0.25, cy - g * 0.12), Vector2(cx - g * 0.20, cy - g * 0.22),
			Vector2(cx + g * 0.13, cy - g * 0.20), Vector2(cx + g * 0.24, cy - g * 0.06),
			Vector2(cx + g * 0.19, cy + g * 0.12), Vector2(cx - g * 0.18, cy + g * 0.13)])
		c.fill_polygon(chassis, body)
		var quad_head := PackedVector2Array([
			Vector2(cx + g * 0.12, cy - g * 0.18), Vector2(cx + g * 0.28, cy - g * 0.22),
			Vector2(cx + g * 0.34, cy - g * 0.08), Vector2(cx + g * 0.24, cy + g * 0.02)])
		c.fill_polygon(quad_head, secondary)
		c.disc(cx + g * 0.27, cy - g * 0.12, g * 0.035, hi)
		var leg_roots := [cx - g * 0.17, cx - g * 0.03, cx + g * 0.10, cx + g * 0.20]
		for i in range(4):
			var x: float = leg_roots[i]
			var sign := -1.0 if i % 2 == 0 else 1.0
			var knee_x := x + sign * g * 0.045
			c.line(x, cy + g * 0.08, knee_x, cy + g * 0.26, dark)
			c.line(knee_x, cy + g * 0.26, knee_x - sign * g * 0.025, cy + g * 0.38, dark)
			c.fill_rect(int(knee_x - g * 0.04), int(cy + g * 0.37), int(knee_x + g * 0.04), int(cy + g * 0.41), secondary)
		c.line(cx - g * 0.10, cy - g * 0.10, cx - g * 0.22, cy - g * 0.28, dark)
		c.line(cx - g * 0.22, cy - g * 0.28, cx - g * 0.30, cy - g * 0.32, hi)
		return
	var head_y := cy - g * rng.randf_range(0.21, 0.27)
	var body_y := cy + g * rng.randf_range(-0.02, 0.06)
	var head := PackedVector2Array([
		Vector2(cx - g * 0.14, head_y + g * 0.05), Vector2(cx - g * 0.10, head_y - g * 0.09),
		Vector2(cx + g * 0.07, head_y - g * 0.12), Vector2(cx + g * 0.15, head_y - g * 0.01),
		Vector2(cx + g * 0.12, head_y + g * 0.10), Vector2(cx - g * 0.05, head_y + g * 0.13)])
	c.fill_polygon(head, secondary)
	var torso := PackedVector2Array([
		Vector2(cx - g * 0.18, body_y - g * 0.08), Vector2(cx - g * 0.11, body_y - g * 0.18),
		Vector2(cx + g * 0.12, body_y - g * 0.16), Vector2(cx + g * 0.20, body_y + g * 0.16),
		Vector2(cx + g * 0.08, body_y + g * 0.26), Vector2(cx - g * 0.16, body_y + g * 0.19)])
	c.fill_polygon(torso, body)
	c.line(cx, head_y + g * 0.12, cx, body_y - g * 0.13, hi)
	var limb_side := -1.0 if rng.chance(0.5) else 1.0
	var arm_len := rng.randf_range(g * 0.20, g * 0.33)
	c.line(cx - g * 0.12, body_y - g * 0.02, cx - g * 0.12 - arm_len, body_y + g * 0.10, dark)
	c.line(cx + g * 0.12, body_y - g * 0.02, cx + g * 0.12 + arm_len * (1.0 if limb_side < 0.0 else 0.72), body_y + g * 0.12, dark)
	c.line(cx - g * 0.08, body_y + g * 0.18, cx - g * rng.randf_range(0.10, 0.20), cy + g * 0.39, dark)
	c.line(cx + g * 0.08, body_y + g * 0.18, cx + g * rng.randf_range(0.10, 0.20), cy + g * 0.39, dark)
	c.disc(cx - g * 0.12 - arm_len, body_y + g * 0.10, g * 0.045, accent)
	c.disc(cx, head_y + g * 0.01, g * 0.035, hi)
	c.fill_rect(int(cx - g * 0.20), int(cy + g * 0.37), int(cx - g * 0.04), int(cy + g * 0.42), secondary)
	c.fill_rect(int(cx + g * 0.04), int(cy + g * 0.37), int(cx + g * 0.20), int(cy + g * 0.42), secondary)
