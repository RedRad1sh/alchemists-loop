class_name SigilGlitchView
extends Control
## Глитч-слой редкости: «сломанная реальность» высших сигилов.
## Рисует поверх всех слоёв: RGB-расщепление (сдвиг каналов), строчные
## артефакты, дрожание. Сила — palette.glitch (0.25 legendary / 1.0 mythic).
## В статичном PNG-кадре (t=0) эффект почти невидим — живёт в _process.

var strength := 0.0
var _t := 0.0
var _rng: RandomNumberGenerator

func setup(p_strength: float, seed_value: int) -> void:
	strength = p_strength
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = strength > 0.01
	if visible:
		set_process(true)

func _process(delta: float) -> void:
	if not visible or strength <= 0.01:
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	if strength <= 0.01:
		return
	var s := size
	var c := s * 0.5
	var k := strength
	# RGB-расщепление: по горизонтали сдвигаем каналы, когда «сбой»
	var glitch_on := sin(_t * 9.0) > 0.55 or sin(_t * 23.0) > 0.85
	if glitch_on:
		var off := 4.0 * k + 3.0 * sin(_t * 13.0)
		var stripe_h := 6.0 + 14.0 * k
		var y := fposmod(_t * 90.0 * k, s.y + 40.0) - 40.0
		# Строчный артефакт: полоса с RGB-сдвигом
		draw_rect(Rect2(0, y, s.x, stripe_h), Color(1, 0, 0, 0.10 * k), true)
		draw_rect(Rect2(off, y, s.x - off, stripe_h), Color(0, 1, 1, 0.07 * k), true)
		draw_rect(Rect2(-off, y + stripe_h * 0.5, s.x, stripe_h * 0.6), Color(0, 0.6, 1, 0.06 * k), true)
	# Крупные блоки-«разрывы» (редкие, но заметные)
	if _rng.randf() < 0.02 * k:
		var bx: float = _rng.randf() * s.x
		var by: float = _rng.randf() * s.y
		var bw: float = 8.0 + _rng.randf() * 40.0 * k
		draw_rect(Rect2(bx, by, bw, 2.0 + _rng.randf() * 4.0), Color(0.3, 0.9, 1.0, 0.35 * k), true)
	# Краевые RGB-расщепления сигила (по краям кадра)
	var glow := 0.10 * k * (0.5 + 0.5 * sin(_t * 4.0))
	draw_rect(Rect2(0, 0, s.x, 1.0), Color(0.2, 0.8, 1.0, glow), true)
	draw_rect(Rect2(0, s.y - 1.0, s.x, 1.0), Color(1.0, 0.2, 0.4, glow), true)