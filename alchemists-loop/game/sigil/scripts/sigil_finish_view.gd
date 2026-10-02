class_name SigilFinishView
extends Control

## Слой «покрытия» для редких карточек: фольга, пыль и искры.
## Порты python/sigil_finish.py — GDScript и Python обязаны совпадать,
## иначе превью и игра покажут разное.
##
## Всё запекается в кадр. Времени здесь нет и не будет: карточка
## детерминирована и кэшируется одним PNG, а движение по кадру ломает
## оба свойства сразу.
##
## Слой ставится дважды, потому что части карточки должны лежать по разные
## стороны круга:
##   Part.FOIL      — под кругом: радуга и пыль;
##   Part.SPARKLES  — поверх центрального объекта: искры-блики.

enum Part { FOIL, SPARKLES }

## Порог анимации. Ровно тот же, что и у искр: legendary (0.35) и
## mythic (0.55) двигаются, epic (0.05) остаётся неподвижным.
## Отдельного числа не заводим, иначе порог пришлось бы выставлять в двух местах.
const MOTION_MIN := 0.25
## Скорости. Подобраны на глаз по гифке: при 0.035 оборот полосы шёл
## почти полминуты и анимация выглядела как статичная картинка. Сейчас
## полный оборот — около 8 с: медленно, но движение видно.
const SPEED_FOIL := 0.12
const SPEED_MOTES := 18.0
const SPEED_SPARK := 3.4

var part: int = Part.FOIL
var strength: float = 0.0
var phase: float = 0.0
var tint: Color = Color(1, 1, 1)
var art: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0
var card_size: Vector2 = Vector2(512, 1024)
var seed_value: int = 0

var animated: bool = false

var _rect: ColorRect = null
var _sh: Shader = null
var _mat: ShaderMaterial = null
var _base_phase: float = 0.0
var _t: float = 0.0
const TAU := 6.283185307179586


func setup(p_part: int, options: SigilOptions, palette: SigilPalette,
		p_seed: int, p_center: Vector2, p_radius: float) -> void:
	part = p_part
	seed_value = seed_value
	strength = clampf(palette.aura_pulse, 0.0, 1.0)
	# Свой поток на слой: добавление искр не должно сдвигать генерацию
	# круга, иначе у всех выпущенных карточек поедут глифы.
	phase = SigilRng.new(p_seed).fork("finish").randf()
	tint = palette.aura_color if part == Part.FOIL else palette.ink
	art = options.art_rect()
	center = p_center
	radius = p_radius
	card_size = Vector2(options.card_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if part == Part.FOIL and strength > 0.001:
		_sh = SigilAssets.shader_file("shaders/sigil_foil.gdshader")
		if _sh != null:
			_rect = ColorRect.new()
			_rect.name = "Foil"
			_rect.color = Color.WHITE
			var mat := ShaderMaterial.new()
			_mat = mat
			mat.shader = _sh
			mat.set_shader_parameter("strength", strength)
			mat.set_shader_parameter("phase", phase)
			mat.set_shader_parameter("card_size", card_size)
			_base_phase = phase
			_rect.material = mat
			_rect.position = art.position
			_rect.size = art.size
			_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_rect)
	animated = strength >= MOTION_MIN
	# Пока не анимируем, процессор держим выключенным: у common/uncommon/
	# rare и epic узла вообще нет в дереве сценами.
	set_process(animated)
	visible = strength > 0.001
	queue_redraw()


## Анимация живёт здесь, а не в шейдере. В шейдере намеренно нет TIME:
## он остаётся чистой функцией от uniform-ов, поэтому Python может отрисовать
## любой кадр, просто подставив нужную фазу, и превью совпадёт с игрой.
func _process(delta: float) -> void:
	if not animated or not visible:
		return
	_t += delta
	if _mat != null:
		_mat.set_shader_parameter("phase", fposmod(_base_phase + _t * SPEED_FOIL, 1.0))
	queue_redraw()


## Фаза кадра. Нужна Python-зеркалу: она полностью задаёт и положение
## полосы, и фазу мигания искр.
func motion_phase() -> float:
	return _t


func _draw() -> void:
	if strength <= 0.001:
		return
	if part == Part.FOIL:
		_draw_motes()
	else:
		_draw_sparkles()


## Пыль. Мелкая и разреженная: при больших размерах превращается в снег.
##
## Базовые позиции берутся из детерминированного потока и не меняются никогда —
## двигается только сдвиг по времени. Так кадр остаётся воспроизводимым:
## зная t, можно точно восстановить, где была каждая пылинка.
func _draw_motes() -> void:
	var rng := SigilRng.new(seed_value).fork("motes")
	var n := int(26.0 + 120.0 * strength)
	var k := float(card_size.x) / 512.0
	for i in n:
		var x0 := rng.randf()
		var y0 := rng.randf()
		var r := 0.8 + rng.randf() * (1.3 + 2.1 * strength)
		var a := 0.16 + rng.randf() * 0.40 * strength
		var vy := (0.5 + rng.randf() * 0.5) * SPEED_MOTES
		var vx := 0.0
		var wob := 0.0
		if animated:
			vy *= -1.0  # пыль поднимается, а не оседает вниз
			vx = 0.06 + rng.randf() * 0.10
			wob = rng.randf() * TAU
		# Медленный подъём со сносом: круговое движение даёт «дыхание»,
		# но пылинка не улетает за край поля.
		var ph := wob + _t * 0.9
		var x := art.position.x + fposmod(x0 + _t * vx + sin(ph) * 0.004, 1.0) * art.size.x
		var y := art.position.y + fposmod(y0 + _t * vy * 0.01, 1.0) * art.size.y
		# У краёв гасим: иначе частица выпрыгивает из-под обрезки.
		var edge := 1.0
		if animated:
			var ey: float = absf(y - art.position.y - art.size.y * 0.5) / (art.size.y * 0.5)
			edge = 1.0 - smoothstep(0.86, 1.0, ey)
		draw_circle(Vector2(x, y), r * k, Color(tint.r, tint.g, tint.b, a * edge))


## Искры-блики: подпись коллекционки. Только у верхних редкостей.
func _draw_sparkles() -> void:
	if strength < 0.25:
		return
	var rng := SigilRng.new(seed_value).fork("sparkle")
	var k := float(card_size.x) / 512.0
	var n := int(2.0 + 10.0 * strength)
	for i in n:
		var a := rng.randf() * TAU
		var d := radius * (0.20 + 0.72 * rng.randf())
		var pos := center + Vector2(cos(a), sin(a)) * d
		var tw := 1.0
		if animated:
			# Мигание с индивидуальной частотой: синхронное мигание всех
			# искр сразу выглядит как сбой, а не как блик.
			tw = 0.55 + 0.45 * sin(_t * SPEED_SPARK + a * 3.0)
		var ln := (2.0 + 5.0 * strength) * (0.6 + rng.randf() * 0.8) * k * tw
		var wd := maxf(1.0, (0.9 + 0.7 * strength) * k)
		draw_line(pos - Vector2(ln, 0), pos + Vector2(ln, 0),
			Color(1, 1, 1, (165.0 + 90.0 * strength) / 255.0), wd, true)
		draw_line(pos - Vector2(0, ln), pos + Vector2(0, ln),
			Color(1, 1, 1, (165.0 + 90.0 * strength) / 255.0), wd, true)
		# Диагонали короче — это блик, а не крестик.
		var dl := ln * 0.36
		var dcol := Color(1, 1, 1, (90.0 + 60.0 * strength) / 255.0)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				draw_line(pos, pos + Vector2(sx * dl, sy * dl), dcol, wd, true)
		draw_circle(pos, ln * 0.16, Color(1, 1, 1, 0.9))
