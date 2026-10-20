extends Node
## Съёмка juice-примитивов в трёх фазах на живом UI. Сцена обязательна: нужны дерево,
## раскладка и кадры. Запуск (ОКНО, не --headless — в headless viewport не рендерится):
##   "$GODOT" --path . --scene res://tests/juice_shots.tscn
## Вывод: user://juice_shots/<примитив>_<фаза>.png (5 x 3 = 15)

const PHASES: Array = [0.0, 0.45, 0.95]

var _game: Game
var _shots: Array = []
var _idx := 0


func _ready() -> void:
	Juice.enabled = true
	_game = load("res://main.tscn").instantiate() as Game
	if _game == null:
		push_error("JUICE-SHOTS: main.tscn не инстанцируется в Game")
		get_tree().quit(1)
		return
	add_child(_game)
	# 3 кадра: Main собирает UI в _ready, реальные размеры приходят позже.
	for i in 3:
		await get_tree().process_frame
	# R7: снятие согласия, чтобы не перекрывало кадр.
	if _game._shop != null and _game._shop.has_method("_close_consent"):
		_game._shop._close_consent()
		await get_tree().create_timer(0.3).timeout
	# Котёл живёт на вкладке «Лаборатория» (index 1); TabContainer скрывает неактивные
	# страницы, а невидимый предок не рисуется → кадр был бы пустым.
	_game._tabs_ref.current_tab = 1
	for i in 2:
		await get_tree().process_frame
	var cauldron: Control = _game._engine._cauldron
	var ether: Control = _game._engine._ether_label
	var missing := cauldron == null or ether == null
	missing = missing or _game._popup == null or _game._popup_dim == null
	if missing:
		push_error("JUICE-SHOTS: UI не построен (cauldron/ether_label/_popup/_popup_dim)")
		get_tree().quit(1)
		return
	var mouth: Vector2 = cauldron._mouth_global()
	var epos: Vector2 = ether.get_global_rect().get_center()
	# target для fly/spark/ring — узел ВНУТРИ UI: _host_for() идёт вверх от
	# target.get_parent(), поэтому сам Game-корень хоста не даёт (его предок — Viewport).
	_shots = [
		["fly", cauldron, Vector2(150, 820), mouth],
		["spark", ether, Vector2(150, 820), epos],
		["ring", ether, epos, epos],
		["pop", ether, epos, epos],
		["open", _game, epos, epos],
	]
	print("JUICE-SHOTS host ok mouth=", mouth, " epos=", epos)
	await _run_next()


func _run_next() -> void:
	if _idx >= _shots.size() * PHASES.size():
		print("JUICE-SHOTS done")
		get_tree().quit(0)
		return
	var shot: Array = _shots[int(_idx / PHASES.size())]
	var phase: float = PHASES[_idx % PHASES.size()]
	var kind: String = shot[0]
	var fname := "user://juice_shots/%s_%d.png" % [kind, int(phase * 100)]
	match kind:
		"open":
			await _shot_open(fname, phase)
		"pop":
			await _shot_pop(fname, phase)
		_:
			await _shot_fx(kind, fname, phase, shot)
	_idx += 1
	await _run_next()


## fly/spark/ring — шаг-state: узел создаём через публичный API, дальше process off
## и единственный advance(phase * dur).
func _shot_fx(kind: String, fname: String, phase: float, shot: Array) -> void:
	var dur := 0.24
	match kind:
		"fly":
			dur = Juice.FLY_DUR
			Juice.fly(shot[1], shot[2], shot[3], UIStyle.TEAL, Juice.FLY_DUR)
		"spark":
			dur = 0.34
			Juice.spark(shot[1], shot[2], shot[3], UIStyle.GOLD, 5)
		"ring":
			dur = 0.26
			Juice.ring(shot[1], shot[3], UIStyle.GOLD, 60.0)
	if Juice._live.is_empty():
		push_error("JUICE-SHOTS: %s не создал fx (cap/хост/выключен?)" % kind)
		return
	var fx: Control = Juice._live[Juice._live.size() - 1]
	fx.set_process(false)
	fx.advance(phase * dur)
	await get_tree().process_frame
	await _capture(fname)
	fx.arrive = Callable()
	fx._finish()


func _shot_pop(fname: String, phase: float) -> void:
	Juice.pop(_game._engine._ether_label, UIStyle.GOLD)
	await get_tree().create_timer(phase * 0.18).timeout
	await _capture(fname)
	# Tween цели доживает до конца сам; метка эфира остаётся на месте.


func _shot_open(fname: String, phase: float) -> void:
	var dim: Control = _game._popup_dim
	var popup: Control = _game._popup
	# Боевое содержимое модалки, чтобы яркость оценивалась на настоящем окне.
	_game._popup_title.text = "НОВЫЙ РЕЦЕПТ!"
	_game._popup_sub.text = "Сера + Соль → Кварц\ncommon · награда +3 ⚡"
	dim.visible = true
	popup.visible = true
	Juice.open(dim, popup)
	await get_tree().create_timer(phase * 0.22).timeout
	await _capture(fname)
	dim.visible = false
	popup.visible = false
	popup.scale = Vector2.ONE
	popup.modulate.a = 1.0
	dim.modulate.a = 1.0


func _capture(fname: String) -> void:
	if not DirAccess.dir_exists_absolute("user://juice_shots"):
		DirAccess.make_dir_recursive_absolute("user://juice_shots")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("JUICE-SHOT ", fname, " ok=", img.save_png(fname))
