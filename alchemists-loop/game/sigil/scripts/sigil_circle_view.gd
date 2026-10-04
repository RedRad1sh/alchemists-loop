class_name SigilCircleView
extends Control

## Слой 3–5: кольца круга, символы, слоты ингредиентов.
## Чистая отрисовка [SigilCircleLayout] — ни одного вычисления случайности.
## Ровно этот же layout можно отдать крафтовому UI как источник позиций.

var layout: SigilCircleLayout
var palette: SigilPalette
var options: SigilOptions

var _hover_slot: int = -1
var _debug_slots: bool = false


func setup(p_layout: SigilCircleLayout, p_palette: SigilPalette, p_options: SigilOptions) -> void:
	layout = p_layout
	palette = p_palette
	options = p_options
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_debug_slots(v: bool) -> void:
	_debug_slots = v
	queue_redraw()


func _draw() -> void:
	if layout == null or palette == null:
		return
	var ink := palette.ink
	var w_base := maxf(palette.ink_width, 0.5) * (float(options.card_size.x) / 512.0)
	var c := layout.center
	var r := layout.radius

	_draw_wedges(c, r, ink)
	_draw_rings(c, r, ink, w_base)
	_draw_offset_ring(ink, w_base)
	_draw_inner(c, ink, w_base)
	_draw_bridges(c, ink, w_base)
	_draw_spokes(c, ink, w_base)
	_draw_glyphs(c, r, ink, w_base)
	_draw_slots(c, r, ink, w_base)


func _draw_wedges(c: Vector2, r: float, ink: Color) -> void:
	## Полупрозрачные секторные сегменты: дают кругу плоскость.
	for entry in layout.wedges:
		var w: Dictionary = entry
		var pts := PackedVector2Array()
		pts.append_array(SigilGeometry.arc_points(c, float(w["r1"]), float(w["a0"]), float(w["a1"]), 16))
		for i in range(16, -1, -1):
			pts.append(SigilGeometry.polar(c, float(w["r0"]), lerpf(float(w["a0"]), float(w["a1"]), float(i) / 16.0)))
		draw_colored_polygon(pts, Color(ink.r, ink.g, ink.b, float(w["alpha"])))
		draw_polyline(SigilGeometry.closed(SigilGeometry.arc_points(c, float(w["r1"]),
			float(w["a0"]), float(w["a1"]), 16)), Color(ink.r, ink.g, ink.b, 0.45), 1.0, true)


func _draw_offset_ring(ink: Color, w: float) -> void:
	if layout.offset_ring.is_empty():
		return
	var oc: Vector2 = layout.offset_ring["center"]
	var orad := float(layout.offset_ring["radius"])
	var alpha := float(layout.offset_ring["alpha"])
	draw_arc(oc, orad, 0.0, TAU, 48, Color(ink.r, ink.g, ink.b, alpha), maxf(w * 0.8, 0.7), true)


func _draw_rings(c: Vector2, r: float, ink: Color, w: float) -> void:
	for ring in layout.rings:
		var d: Dictionary = ring
		var rad := r * float(d["ratio"])
		var col := Color(ink.r, ink.g, ink.b, float(d["alpha"]))
		var width := maxf(w * float(d["width"]), 0.8)
		var dashes := int(d["dash"])
		var off := float(d["offset"])
		if bool(d["dash_arc"]):
			draw_polyline(SigilGeometry.dashed_arc(c, rad, off, off + TAU,
				layout.sector_count * 4), col, width, true)
		elif dashes > 0:
			var step := TAU / float(dashes)
			for i in dashes:
				draw_arc(c, rad, float(i) * step, float(i) * step + step * 0.55,
					6, col, width, true)
		else:
			draw_arc(c, rad, 0.0, TAU, 96, col, width, true)
	# Внешняя двойная обводка — «печать».
	if bool(layout.style_flags.get("double_outer", false)):
		draw_arc(c, r * 1.035, 0.0, TAU, 96, Color(ink.r, ink.g, ink.b, 0.5), w * 0.8, true)
		draw_arc(c, r * 1.065, 0.0, TAU, 96, Color(ink.r, ink.g, ink.b, 0.25), w * 0.6, true)


func _draw_inner(c: Vector2, ink: Color, w: float) -> void:
	var col := Color(ink.r, ink.g, ink.b, 0.75)
	for shape in layout.inner_shapes:
		draw_polyline(shape, col, maxf(w * 0.9, 0.8), true)
	# Радиальные насечки.
	var ticks := int(layout.style_flags.get("ticks", 0))
	for i in ticks:
		var a := layout.rotation_offset + TAU * float(i) / float(maxi(ticks, 1))
		draw_line(SigilGeometry.polar(c, layout.radius * layout.radius_bridge, a),
			SigilGeometry.polar(c, layout.radius * layout.radius_inner, a),
			Color(ink.r, ink.g, ink.b, 0.45), maxf(w * 0.7, 0.7), true)
	# Водяной знак результата под иконкой.
	if layout.result_glyph != "" and layout.icon_radius > 0.0:
		SigilGlyphs.draw_glyph(self, layout.result_glyph, c, layout.icon_radius * 2.3, 0.0,
			Color(ink.r, ink.g, ink.b, 0.13), maxf(w * 1.6, 1.0))


func _draw_bridges(c: Vector2, ink: Color, w: float) -> void:
	var col := Color(ink.r, ink.g, ink.b, 0.55)
	for b in layout.bridges:
		draw_polyline(b, col, maxf(w * 0.8, 0.7), true)


func _draw_spokes(c: Vector2, ink: Color, w: float) -> void:
	var col := Color(ink.r, ink.g, ink.b, 0.4)
	for s in layout.spokes:
		draw_polyline(s, col, maxf(w * 0.7, 0.6), true)


func _draw_glyphs(c: Vector2, r: float, ink: Color, w: float) -> void:
	var size := r * layout.glyph_size
	for i in layout.glyph_names.size():
		var alpha := 0.92 if i % 2 == 0 else 0.7
		SigilGlyphs.draw_glyph(self, layout.glyph_names[i], layout.glyph_positions[i],
			size, layout.glyph_rotations[i], Color(ink.r, ink.g, ink.b, alpha),
			maxf(w * 0.85, 0.8))


func _draw_slots(c: Vector2, r: float, ink: Color, w: float) -> void:
	var node_r := r * 0.068
	for entry in layout.slots:
		var s: Dictionary = entry
		var pos: Vector2 = s["position"]
		var filled := bool(s["filled"])
		var hovered := int(s["index"]) == _hover_slot
		var base := palette.accent if filled else ink
		var alpha := 1.0 if filled else 0.32
		if hovered:
			alpha = 1.0

		# Узел-шестиугольник: вписан в круг, читается на любом размере.
		var hexa := PackedVector2Array()
		for i in 6:
			hexa.append(pos + Vector2(cos(float(i) * TAU / 6.0), sin(float(i) * TAU / 6.0)) * node_r)
		draw_polyline(SigilGeometry.closed(hexa), Color(base.r, base.g, base.b, alpha),
			maxf(w * 1.3, 1.1), true)
		if filled:
			# Тёмная подложка, чтобы глиф ингредиента не тонул в круге.
			draw_circle(pos, node_r * 0.88, Color(0, 0, 0, 0.42), true, -1.0, true)
			draw_circle(pos, node_r * 0.88, Color(base.r, base.g, base.b, 0.22), true, -1.0, true)
			var g: String = s["glyph"]
			if g != "":
				SigilGlyphs.draw_glyph(self, g, pos, node_r * 1.30,
					float(s["angle"]) + PI * 0.5, Color(palette.ink.r, palette.ink.g, palette.ink.b, 0.98),
					maxf(w * 0.95, 0.8))
		elif _debug_slots or options.mode == SigilOptions.Mode.DRAFT:
			draw_line(pos + Vector2(-node_r * 0.4, 0), pos + Vector2(node_r * 0.4, 0),
				Color(ink.r, ink.g, ink.b, 0.5), w, true)
			draw_line(pos + Vector2(0, -node_r * 0.4), pos + Vector2(0, node_r * 0.4),
				Color(ink.r, ink.g, ink.b, 0.5), w, true)

		# Лучи от узла к внешнему кольцу — «крючок» крепления ингредиента.
		var a: float = s["angle"]
		draw_line(SigilGeometry.polar(c, layout.radius * layout.radius_slot, a),
			SigilGeometry.polar(c, layout.radius * 0.80, a),
			Color(base.r, base.g, base.b, alpha * 0.45), maxf(w * 0.6, 0.6), true)


func slot_at(local_pos: Vector2) -> int:
	## Для крафтового UI: какой слот под курсором.
	if layout == null:
		return -1
	var node_r := layout.radius * 0.075
	for entry in layout.slots:
		var s: Dictionary = entry
		if local_pos.distance_to(s["position"]) <= node_r:
			return int(s["index"])
	return -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_slot != -1:
		_hover_slot = -1
		queue_redraw()
