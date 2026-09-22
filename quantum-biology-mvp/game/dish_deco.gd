class_name DishDeco
extends Node2D
# Стеклянный декор «чашки» и блики, рисуется ПОВЕРХ шейдерного фона.

const W := 720.0
const H := 1280.0
const C_DISH := Vector2(360, 700)

var _rng := RandomNumberGenerator.new()
var _bokeh: Array = []
var _time := 0.0

func _ready() -> void:
	_rng.randomize()
	# мягкие «боке»-блики в толще воды (декор, некликабельные)
	for i in 22:
		_bokeh.append({
			"x": _rng.randf_range(0.0, W),
			"y": _rng.randf_range(0.0, H),
			"r": _rng.randf_range(2.0, 6.5),
			"spd": _rng.randf_range(4.0, 13.0),
			"ph": _rng.randf_range(0.0, TAU),
			"a": _rng.randf_range(0.05, 0.16)
		})

func _process(delta: float) -> void:
	_time += delta
	for b in _bokeh:
		b["y"] -= b["spd"] * delta
		if b["y"] < -8.0:
			b["y"] = H + 8.0
			b["x"] = _rng.randf_range(0.0, W)
	queue_redraw()

func _draw() -> void:
	# контур «блюда» чашки — едва заметные стеклянные дуги
	var col_glass := Color(0.65, 0.95, 0.9, 0.10)
	var col_glass2 := Color(0.4, 0.8, 0.8, 0.06)
	draw_arc(C_DISH, 320.0, -0.6, 0.6, 72, col_glass, 2.0)
	draw_arc(C_DISH, 320.0, PI - 0.6, PI + 0.6, 72, col_glass, 2.0)
	draw_arc(C_DISH, 306.0, -2.2, -1.2, 48, col_glass2, 1.5)
	# большая «стеклянная» дуга-блик сверху слева
	draw_arc(C_DISH + Vector2(-34, -10), 250.0, -2.35, -1.75, 40,
		Color(0.8, 1.0, 0.98, 0.085), 7.0)
	# рассеянный светлый ореол над существом
	var soft := Art.soft()
	_soft_draw(soft, Vector2(360, 480), 260.0, Color(0.55, 0.95, 0.9, 0.10))
	# боке
	for b in _bokeh:
		var x: float = b["x"] + sin(_time * 0.7 + b["ph"]) * 10.0
		var wob: float = 1.0 + 0.25 * sin(_time * 1.6 + b["ph"] * 2.0)
		var rr: float = b["r"] * wob
		_soft_draw(soft, Vector2(x, b["y"]), rr * 2.6, Color(0.6, 0.95, 0.9, b["a"]))

func _soft_draw(tex: GradientTexture2D, pos: Vector2, radius: float, color: Color) -> void:
	var s := radius
	draw_texture_rect(tex, Rect2(pos - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), false, color)
