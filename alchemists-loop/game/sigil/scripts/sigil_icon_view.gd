class_name SigilIconView
extends Control

## Слой 5 — центральный объект. Тонкая обёртка над [SigilIconGenerator]:
## гнездо (тёмный диск) + сам генератор. Генератор ничего не знает
## о гнезде и может рисовать в любом другом контейнере.

var generator: SigilIconGenerator
var ctx: Dictionary = {}
var rng: SigilRng
var socket: bool = true
var ink: Color = Color(0.92, 0.88, 0.78)
var accent: Color = Color(0.9, 0.75, 0.4)


func setup(p_generator: SigilIconGenerator, p_ctx: Dictionary, p_rng: SigilRng,
		p_ink: Color, p_accent: Color) -> void:
	generator = p_generator
	ctx = p_ctx
	rng = p_rng
	ink = p_ink
	accent = p_accent
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	if socket:
		# Мягкое затемнение концентрическими шагами. Раньше здесь был
		# жёсткий тёмный диск: на размере карточки он читался как
		# «пустая дырка» и съедал объект.
		const STEPS := 16
		for i in STEPS:
			var t := float(i) / float(STEPS)
			draw_circle(c, r * lerpf(1.18, 0.72, t), Color(0, 0, 0, 0.032), true, -1.0, true)
		draw_arc(c, r * 1.20, 0.0, TAU, 72, Color(ink.r, ink.g, ink.b, 0.24),
			maxf(r * 0.016, 1.0), true)
	if generator != null and rng != null:
		generator.draw_icon(self, Rect2(Vector2.ZERO, size), rng, ctx)
