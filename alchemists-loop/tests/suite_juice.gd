extends RefCounted
class_name SuiteJuice
# juice-слой: жизненный цикл fx, cap, хостинг, синхронный путь под selftest.
# Каждая проверка привязана к съёмной строке в game/ui/juice.gd (красные пары —
# в плане 2026-10-20, Task 1 Step 7): без _unlive(self) краснеет 8, без queue_free — 9,
# без синхронного visible=false в close — 16, без фейда без размера в open — 17,
# без гейта META_POP_FRAME — 19, без FLY_DUR=0.16 — 20.


static func _mk_host(g: Game, probes: Array) -> Control:
	# Хост вне Container: ближайший не-контейнерный предок есть у самого Game.
	# probe-контейнер собираем в probes — иначе сюита оставляет висячие узлы.
	var probe := HBoxContainer.new()
	g.add_child(probe)
	probes.append(probe)
	var cell := Label.new()
	probe.add_child(cell)
	return cell


static func _drain() -> void:
	while not Juice._live.is_empty():
		var left: Control = Juice._live[0]
		if left is Juice.JuiceFx:
			(left as Juice.JuiceFx).advance(1.0)
		else:
			Juice._unlive(left)


static func run(g: Game) -> void:
	var prev_enabled := Juice.enabled
	var prev_max := Juice.max_concurrent
	var spawned: Array = []
	var probes: Array = []

	# --- под selftest (enabled=false) примитивы синхронны и не плодят узлов ---
	Juice.enabled = false
	var hit := [0]
	Juice.fly(_mk_host(g, probes), Vector2(10, 10), Vector2(200, 300), UIStyle.TEAL, 0.24,
		func() -> void: hit[0] += 1)
	Selftest.check("fly disabled calls arrive synchronously", hit[0] == 1)
	Selftest.check("fly disabled spawns no fx node", Juice.active_count() == 0)
	Juice.spark(_mk_host(g, probes), Vector2.ZERO, Vector2(50, 50), UIStyle.GOLD)
	Juice.ring(_mk_host(g, probes), Vector2(20, 20), UIStyle.GOLD)
	Selftest.check("spark and ring disabled spawn nothing", Juice.active_count() == 0)

	# --- включённый слой: узел создаётся, доживает и убивает себя ---
	Juice.enabled = true
	Juice.fly(_mk_host(g, probes), Vector2(10, 10), Vector2(120, 160), UIStyle.TEAL, 0.24,
		func() -> void: hit[0] += 1)
	Selftest.check("fly enabled spawns one fx", Juice.active_count() == 1)
	var fx: Control = Juice._live[0]
	# Не find_child("JuiceFx"): `_spawn` имени не задаёт, узел безымянный
	# (`<Control#id>`), а два одинаковых имени в одном хосте Godot всё равно переименует.
	spawned.append(fx)
	Selftest.check("fly arrive not called before duration", hit[0] == 1)
	if fx is Juice.JuiceFx:
		(fx as Juice.JuiceFx).advance(0.10)
	Selftest.check("fly mid-flight keeps arrive pending", hit[0] == 1)
	if fx is Juice.JuiceFx:
		(fx as Juice.JuiceFx).advance(0.20)
	Selftest.check("fly arrive fires after duration", hit[0] == 2)
	Selftest.check("fly unregisters from live list after duration", Juice.active_count() == 0)
	await g.get_tree().process_frame
	Selftest.check("fly frees its node after duration", not is_instance_valid(fx))

	# --- fx не хостится в Container ---
	Juice.ring(_mk_host(g, probes), Vector2(30, 30), UIStyle.GOLD)
	var last_host: Node = null
	for c in Juice._live:
		last_host = (c as Control).get_parent()
	Selftest.check("fx host is never a Container",
		last_host != null and not (last_host is Container))
	_drain()
	Selftest.check("fx cleanup leaves nothing live", Juice.active_count() == 0)

	# --- cap: вызов сверх лимита не создаёт узел, но arrive срабатывает ---
	Juice.max_concurrent = 2
	var capped := [0]
	for i in 5:
		Juice.fly(_mk_host(g, probes), Vector2.ZERO, Vector2(40, 40), UIStyle.TEAL, 0.24,
			func() -> void: capped[0] += 1)
	Selftest.check("concurrent fx respects cap", Juice.active_count() <= 2 and capped[0] >= 3)
	_drain()

	# --- open/close: контракт синхронности под selftest (enabled=false) ---
	Juice.enabled = false
	var dim := ColorRect.new()
	g.add_child(dim)
	var pop := PanelContainer.new()
	g.add_child(pop)
	Juice.open(dim, pop)
	Selftest.check("open disabled shows window synchronously",
		dim.visible and pop.visible and pop.scale == Vector2.ONE)
	Juice.close(dim, pop)
	Selftest.check("close disabled hides window synchronously",
		not dim.visible and not pop.visible)
	# open возвращает альфу в 1.0 ДО гейта enabled: убираем строки
	# `dim.modulate.a = 1.0` / `popup.modulate.a = 1.0` — краснеет здесь.
	dim.modulate.a = 0.0
	pop.modulate.a = 0.0
	Juice.open(dim, pop)
	Selftest.check("open restores alpha before animating",
		is_equal_approx(dim.modulate.a, 1.0) and is_equal_approx(pop.modulate.a, 1.0))

	# --- R1: close прячет окно в том же кадре, даже когда слой включён ---
	Juice.enabled = true
	dim.visible = true
	pop.visible = true
	Juice.open(dim, pop)
	Juice.close(dim, pop)
	Selftest.check("close hides the window in the same frame",
		not dim.visible and not pop.visible)
	_drain()

	# --- R2: фейд есть всегда: ленивое окно без размера анимируется фейдом ---
	var fade := PanelContainer.new()
	g.add_child(fade)
	Juice.open(null, fade)
	Selftest.check("open at zero size still fades", fade.modulate.a < 1.0)
	_drain()

	# --- R6: pop штамдует цель, не слой: ровно одно кольцо на узел за кадр ---
	var cell := _mk_host(g, probes)
	var before := Juice.active_count()
	Juice.pop(cell, UIStyle.GOLD)
	Selftest.check("pop stamps the node, not the whole layer",
		Juice.active_count() == before + 1
		and (cell.get_parent() as Control).scale == Vector2.ONE)
	Juice.pop(cell, UIStyle.GOLD)
	Selftest.check("pop twice in one frame stamps once",
		Juice.active_count() == before + 1)
	_drain()

	# --- дефолт fly: 0.16 (dur в вызове пропущен; arrive навешиваем на fx,
	# т.к. GDScript не умеет пропуск позиционного аргумента с дефолтом) ---
	var done := [0]
	Juice.fly(_mk_host(g, probes), Vector2.ZERO, Vector2(30, 30), UIStyle.GOLD)
	var fx_def: Juice.JuiceFx = Juice._live[0]
	fx_def.arrive = func() -> void: done[0] += 1
	fx_def.advance(0.17)
	Selftest.check("fly default duration is 0.16",
		fx_def.duration == 0.16 and done[0] == 1)
	_drain()

	for n in spawned:
		if is_instance_valid(n):
			n.queue_free()
	for p in probes:
		if is_instance_valid(p):
			p.queue_free()
	dim.free()
	pop.free()
	fade.free()
	Juice.enabled = prev_enabled
	Juice.max_concurrent = prev_max
