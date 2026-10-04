extends SigilIconGenerator
class_name SigilGenCreature

## Тип «creature» — пиксельное существо.
##
## Не спрайт-лист, а грамматика тела: осевой хребет задаёт позу, части тела
## расставляются по нему, левая половина зеркалится. Из ~40 существ на
## 32×32 складывается узнаваемая морда, а не пятно одноцветных пикселей.

const ARCHETYPES := ["serpent", "quadruped", "avian", "insectoid", "aquatic", "wisp"]
const HEADS := ["round", "snout", "beak", "horned", "antlered", "flat"]


func type_name() -> StringName:
	return &"creature"


func description() -> String:
	return "Грамматика тела: хребет, части, билатеральная симметрия"


func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	var g := grid_for(rect, ctx, 34)
	var c := SigilPixelCanvas.new(g)
	var f := float(g)

	var arche := str(ctx.get("creature_archetype", rng.pick(ARCHETYPES)))
	var head_kind := str(ctx.get("head", rng.pick(HEADS)))
	var body := palette(ctx, "body", Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.8), rng.randf_range(0.45, 0.85)))
	var belly := palette(ctx, "belly", body.lerp(Color(1, 1, 1), 0.45))
	var accent := palette(ctx, "accent", Color.from_hsv(fposmod(body.h + 0.45, 1.0), 0.85, 0.95))
	var outline := body.lerp(Color(0, 0, 0), 0.55)
	var eye := Color(0.98, 0.94, 0.55)

	var spine: PackedVector2Array = PackedVector2Array()
	var seg := 9
	var amp := 0.0
	var phase := rng.randf() * TAU
	match arche:
		"serpent":
			amp = f * 0.16
		"quadruped":
			amp = f * 0.07
		"insectoid":
			amp = f * 0.03
		_:
			amp = f * 0.04
	for i in seg:
		var t := float(i) / float(seg - 1)
		var x := f * (0.5 + (t - 0.5) * 0.62)
		var y := f * 0.52 + sin(phase + t * 3.4) * amp
		spine.append(Vector2(x, y))

	# Радиус тела: толстый в середине, тонкий к хвосту. Значения подобраны
	# так, чтобы на сетке 32–34 существо читалось силуэтом, а не полоской.
	var max_r := f * rng.randf_range(0.105, 0.150)
	for i in spine.size():
		var t := float(i) / float(spine.size() - 1)
		var rad := max_r * (0.45 + 0.55 * sin(PI * clampf(t, 0.0, 1.0)))
		if i > spine.size() - 4:
			rad *= 0.6
		var p: Vector2 = spine[i]
		c.ellipse(p.x, p.y, rad * 1.20, rad, body)
		c.ellipse(p.x, p.y + rad * 0.38, rad * 0.62, rad * 0.46, belly)

	# Голова.
	var head: Vector2 = spine[0]
	var head_r := max_r * rng.randf_range(1.15, 1.55)
	var dir: Vector2 = (spine[1] - spine[0]).normalized()
	var side := Vector2(-dir.y, dir.x)
	match head_kind:
		"snout":
			c.ellipse(head.x + dir.x * head_r * 0.7, head.y + dir.y * head_r * 0.7,
				head_r * 0.75, head_r * 0.55, body)
		"beak":
			c.line(head.x + dir.x * head_r * 0.6, head.y + dir.y * head_r * 0.6,
				head.x + dir.x * head_r * 1.5, head.y + dir.y * head_r * 1.5, accent)
		"horned":
			for s in [-1.0, 1.0]:
				var base: Vector2 = head + side * head_r * 0.5 * s
				c.line(base.x, base.y, base.x + dir.x * head_r * 0.6 - side.x * head_r * 0.7 * s,
					base.y + dir.y * head_r * 0.6 - side.y * head_r * 0.7 * s, accent)
		"antlered":
			for s in [-1.0, 1.0]:
				var base2: Vector2 = head + side * head_r * 0.55 * s
				c.line(base2.x, base2.y, base2.x + dir.x * head_r * 0.9 - side.x * head_r * 0.5 * s,
					base2.y + dir.y * head_r * 0.9 - side.y * head_r * 0.5 * s, accent)
				c.line(base2.x + dir.x * head_r * 0.5 * s * -1.0, base2.y + dir.y * head_r * 0.5 * s * -1.0,
					base2.x + dir.x * head_r * 1.2 - side.x * head_r * 0.9 * s,
					base2.y + dir.y * head_r * 1.2 - side.y * head_r * 0.9 * s, accent)
		_:
			pass
	c.ellipse(head.x, head.y, head_r * 1.05, head_r * 0.95, body)

	# Глаза.
	var eyes := 2 if rng.chance(0.72) else 1
	for i in eyes:
		var ex := head.x + dir.x * head_r * 0.30 - side.x * head_r * 0.42 * (1.0 if i == 0 else -1.0)
		var ey := head.y + dir.y * head_r * 0.30 - side.y * head_r * 0.42 * (1.0 if i == 0 else -1.0)
		c.set_px(int(floorf(ex)), int(floorf(ey)), eye)
		c.set_px(int(floorf(ex)), int(floorf(ey)) + 1, outline)

	# Конечности.
	match arche:
		"quadruped":
			for idx in [2, 4]:
				for s in [-1.0, 1.0]:
					var p: Vector2 = spine[idx]
					var foot: Vector2 = p + side * head_r * 0.95 * s + Vector2(0, head_r * 0.75)
					c.line(p.x, p.y, foot.x, foot.y, body)
					c.line(foot.x, foot.y, foot.x + dir.x * head_r * 0.35, foot.y, outline)
		"insectoid":
			for i in range(3):
				var t2 := float(i) / 2.0
				var p2: Vector2 = spine[mini(2 + i, spine.size() - 1)]
				for s in [-1.0, 1.0]:
					var joint: Vector2 = p2 + side * head_r * (0.7 + t2 * 0.5) * s
					c.line(p2.x, p2.y, joint.x, joint.y - head_r * 0.35, body)
					c.line(joint.x, joint.y - head_r * 0.35,
						joint.x + side.x * head_r * 0.8 * s, joint.y + head_r * 0.2, body)
		"avian":
			for s in [-1.0, 1.0]:
				var root: Vector2 = spine[0] + side * head_r * 0.3 * s
				for k in 4:
					var t3 := float(k) / 3.0
					var tip: Vector2 = root + side * head_r * (1.0 + t3 * 1.9) * s + dir * head_r * (0.6 - t3 * 0.5)
					c.line(root.x + side.x * head_r * t3 * 1.5 * s, root.y + side.y * head_r * t3 * 1.5 * s,
						tip.x, tip.y, accent if k % 2 == 0 else body)
		"aquatic":
			for i in range(3):
				var p3: Vector2 = spine[mini(3 + i, spine.size() - 1)]
				for s in [-1.0, 1.0]:
					var e: Vector2 = p3 + side * head_r * (1.1 + 0.25 * float(i)) * s
					c.set_px(int(floorf(e.x)), int(floorf(e.y)), body)
		"wisp":
			c.disc(f * 0.5, f * 0.5, f * 0.20, Color(accent.r, accent.g, accent.b, 0.22), true)
		_:
			pass

	# Гребень/шипы вдоль хребта.
	if rng.chance(0.6):
		for i in range(1, spine.size() - 1):
			var p4: Vector2 = spine[i]
			var h := max_r * (0.35 + 0.3 * sin(PI * float(i) / float(spine.size())))
			c.set_px(int(floorf(p4.x)), int(floorf(p4.y - h)), accent)

	# Контур: обводим всё, что уже нарисовано, тёмным.
	c.outline(outline, true)  # тонкая обводка (единый стиль)

	c.draw(ci, rect)


func _outline(c: SigilPixelCanvas, col: Color) -> void:
	var snapshot := {}
	for k in c._px.keys():
		snapshot[k] = true
	for y in range(c.grid + 2):
		for x in range(c.grid + 2):
			if snapshot.has(Vector2i(x - 1, y - 1)):
				continue
			for o in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
				if snapshot.has(Vector2i(x - 1, y - 1) + o):
					c.set_px(x - 1, y - 1, col)
					break
