extends SigilIconGenerator
class_name SigilGenRelic

## Тип «relic» — пиксельный артефакт: армиллярная сфера, астролябия, склянка.
## Сделан пиксельным намеренно: редкость должна читаться как «предмет из
## сокровищницы», а не как ещё одна схема.

const FORMS := ["armillary", "astrolabe", "phial", "censer", "codex", "idol_pix"]


func type_name() -> StringName:
	return &"relic"


func description() -> String:
	return "Пиксельный артефакт: армилла, астролябия, склянка, курильница"


func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	var g := grid_for(rect, ctx, 34)
	var c := SigilPixelCanvas.new(g)
	var f := float(g)
	var cx := f * 0.5
	var cy := f * 0.5
	var r := f * 0.38
	var metal := palette(ctx, "body", Color.from_hsv(rng.randf_range(0.05, 0.15), rng.randf_range(0.2, 0.55), rng.randf_range(0.6, 0.95)))
	var dark := metal.lerp(Color(0, 0, 0), 0.6)
	var hi := metal.lerp(Color(1, 1, 1), 0.6)
	var gem := palette(ctx, "accent", Color.from_hsv(rng.randf(), 0.85, 0.95))

	match str(ctx.get("form", FORMS[rng.randi_range(0, FORMS.size() - 1)])):
		"armillary":
			c.ellipse(cx, cy, r, r * 0.32, Color(metal.r, metal.g, metal.b, 0.85))
			c.ellipse(cx, cy, r * 0.92, r * 0.32, dark)
			c.ellipse(cx, cy, r * 0.60, r * 0.95, Color(metal.r, metal.g, metal.b, 0.7))
			c.ellipse(cx, cy, r * 0.95, r * 0.30, hi)
			c.disc(cx, cy, r * 0.16, gem, true)
			c.ring(cx, cy, r * 1.02, maxf(1.0, r * 0.07), hi)
		"astrolabe":
			c.ring(cx, cy, r, maxf(1.0, r * 0.10), metal)
			c.ring(cx, cy, r * 0.78, maxf(1.0, r * 0.06), dark)
			c.ring(cx, cy, r * 0.30, maxf(1.0, r * 0.05), metal)
			for i in 8:
				var a := TAU * float(i) / 8.0
				c.line(cx + cos(a) * r * 0.30, cy + sin(a) * r * 0.30,
					cx + cos(a) * r * 0.98, cy + sin(a) * r * 0.98, Color(dark.r, dark.g, dark.b, 0.8))
			c.line(cx - r * 0.5, cy - r * 0.5, cx + r * 0.55, cy + r * 0.45, gem)
			c.disc(cx, cy, r * 0.10, hi, true)
		"phial":
			c.fill_rect(int(cx - r * 0.22), int(cy - r), int(cx + r * 0.22), int(cy - r * 0.55), dark)
			c.ellipse(cx, cy + r * 0.30, r * 0.70, r * 0.78, Color(0.55, 0.72, 0.85, 0.85))
			c.ellipse(cx, cy + r * 0.35, r * 0.60, r * 0.62, gem)
			c.ellipse(cx - r * 0.22, cy + r * 0.15, r * 0.16, r * 0.24, Color(1, 1, 1, 0.55))
			c.fill_rect(int(cx - r * 0.28), int(cy - r * 1.05), int(cx + r * 0.28), int(cy - r * 0.92), metal)
		"censer":
			c.ellipse(cx, cy + r * 0.45, r * 0.62, r * 0.60, metal)
			c.ellipse(cx, cy + r * 0.25, r * 0.40, r * 0.30, dark)
			c.line(cx, cy - r * 0.15, cx, cy - r * 0.95, hi)
			c.ring(cx, cy - r * 0.95, r * 0.22, maxf(1.0, r * 0.06), metal)
			for i in 3:
				var fx := cx + (float(i) - 1.0) * r * 0.35
				c.disc(fx, cy - r * 0.05 - float(i % 2) * r * 0.15, r * 0.16,
					Color(gem.r, gem.g, gem.b, 0.55), true)
		"codex":
			c.fill_rect(int(cx - r * 0.85), int(cy - r * 0.62), int(cx + r * 0.85), int(cy + r * 0.68), metal)
			c.fill_rect(int(cx - r * 0.06), int(cy - r * 0.62), int(cx + r * 0.06), int(cy + r * 0.68), dark)
			c.fill_rect(int(cx - r * 0.80), int(cy - r * 0.56), int(cx + r * 0.80), int(cy + r * 0.56), hi)
			for i in 4:
				var y := cy - r * 0.38 + float(i) * r * 0.26
				c.line(cx - r * 0.68, y, cx - r * 0.16, y, Color(dark.r, dark.g, dark.b, 0.6))
				c.line(cx + r * 0.16, y, cx + r * 0.68, y, Color(dark.r, dark.g, dark.b, 0.6))
			c.disc(cx, cy, r * 0.10, gem)
		_:
			c.ellipse(cx, cy + r * 0.15, r * 0.55, r * 0.80, metal)
			c.ellipse(cx, cy - r * 0.45, r * 0.36, r * 0.34, metal)
			c.fill_rect(int(cx - r * 0.12), int(cy - r * 0.60), int(cx + r * 0.12), int(cy - r * 0.20), dark)
			for sgn in [-1.0, 1.0]:
				c.line(cx + sgn * r * 0.20, cy - r * 0.50, cx + sgn * r * 0.52, cy - r * 0.78, gem)
			c.disc(cx, cy - r * 0.45, r * 0.10, gem)
			c.line(cx - r * 0.30, cy + r * 0.55, cx + r * 0.30, cy + r * 0.55, dark)

	# Мягкий блик сверху слева — общий приём всех пиксельных объектов.
	c.shade_highlight(Vector2(cx, cy), r, hi, 0.12, 0.55)

	# Тонкая внешняя обводка — единый стиль с остальными генераторами.
	var outline_col := palette(ctx, "outline", Color(0.16, 0.09, 0.05))
	c.outline(outline_col, true)

	c.draw(ci, rect)
