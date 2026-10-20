class_name Juice
extends RefCounted
# Векторные эффекты отклика: окно открывается, эфир тратится, реагент влетает в котёл.
# Только _draw() + Tween: без ассетов, шейдеров и нод-частиц.
# Состояние эффекта живёт в advance(delta) — синхронные тесты гоняют время без кадров.

const REDRAW_GATE := 0.05
const TRAIL := 5
const META_TWEEN := &"juice_tw"
const FLY_DUR := 0.16
const OPEN_SHRINK_PX := 56.0
const OPEN_MAX_AMP := 0.1
const META_POP_FRAME := &"juice_pop_frame"

const KIND_FLY := 0
const KIND_SPARK := 1
const KIND_RING := 2
const KIND_SWEEP := 3

static var enabled := true
static var max_concurrent := 12
static var _live: Array = []


static func active_count() -> int:
	return _live.size()


static func _unlive(fx: Control) -> void:
	_live.erase(fx)


## Родитель для fx: ближайший предок-Control, НЕ являющийся Container: контейнер
## переложил бы и растянул узел эффекта.
static func _host_for(target: Control) -> Control:
	var n: Node = target.get_parent()
	while n != null:
		if n is Control and not (n is Container):
			return n as Control
		n = n.get_parent()
	return null


static func _spawn(target: Control, fx_kind: int, arrive: Callable) -> Control:
	if target == null or not is_instance_valid(target):
		if arrive.is_valid():
			arrive.call()
		return null
	if _live.size() >= max_concurrent:
		if arrive.is_valid():
			arrive.call()
		return null
	var host := _host_for(target)
	if host == null:
		if arrive.is_valid():
			arrive.call()
		return null
	var fx := JuiceFx.new()
	fx.kind = fx_kind
	fx.arrive = arrive
	fx.z_index = target.z_index + 5
	_live.append(fx)
	host.add_child(fx)
	return fx


class JuiceFx extends Control:
	var kind := 0
	var global_from := Vector2.ZERO
	var global_to := Vector2.ZERO
	var col := Color.WHITE
	var duration := 0.24
	var count := 4
	var radius := 46.0
	var clip_rect := Rect2()
	var clip_from: Control = null
	var arrive := Callable()
	var _t := 0.0
	var _clock := 0.0
	var _dead := false
	var _jitter: PackedVector2Array = PackedVector2Array()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat
		set_process(true)

	## Шаг состояния без кадров. Тестируется напрямую из сюиты.
	func advance(delta: float) -> void:
		if _dead:
			return
		_t += delta
		if _t >= duration:
			_finish()
		else:
			queue_redraw()

	func _finish() -> void:
		_dead = true
		set_process(false)
		Juice._unlive(self)
		if arrive.is_valid():
			arrive.call()
		queue_free()

	func _process(delta: float) -> void:
		advance(delta)
		if _dead:
			return
		_clock += delta
		if _clock >= Juice.REDRAW_GATE:
			_clock = 0.0
			queue_redraw()

	## Глобальные координаты -> локальные fx: узел лежит в произвольном хосте,
	## его глобальный origin — смещение хоста.
	func _p(gpos: Vector2) -> Vector2:
		return gpos - get_global_transform().origin

	func _soft(at: Vector2, r: float, c: Color) -> void:
		draw_texture_rect(Art.soft(),
			Rect2(at - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, c)

	## Дуга: контроль-точка поднята над серединой. Прямая читается как телепорт.
	func _arc(k: float) -> Vector2:
		var dist := global_from.distance_to(global_to)
		var ctrl := ((global_from + global_to) * 0.5
			+ Vector2(0.0, -minf(34.0, dist * 0.35)))
		return global_from.lerp(ctrl, k).lerp(ctrl.lerp(global_to, k), k)

	func _draw() -> void:
		var k := clampf(_t / maxf(duration, 0.001), 0.0, 1.0)
		match kind:
			Juice.KIND_FLY:
				var r := lerpf(20.0, 9.0, k)
				for i in Juice.TRAIL:
					var tk := clampf(k - float(i + 1) * 0.055, 0.0, 1.0)
					_soft(_p(_arc(tk)), r * (1.0 - 0.1 * float(i)),
						Color(col.r, col.g, col.b,
							0.28 * (1.0 - float(i) / Juice.TRAIL) * (1.0 - k * 0.4)))
				_soft(_p(_arc(k)), r, Color(col.r, col.g, col.b, 1.0 - 0.25 * k))
			Juice.KIND_SPARK:
				for i in count:
					if i >= _jitter.size():
						break
					var lag := clampf(k - float(i) * 0.05, 0.0, 1.0)
					var pos := _p(global_from.lerp(global_to, lag)
						+ _jitter[i] * lag * (1.0 - lag) * 40.0)
					_soft(pos, lerpf(9.0, 3.0, lag),
						Color(col.r, col.g, col.b, 0.85 * (1.0 - lag)))
			Juice.KIND_RING:
				var rr := radius * (0.35 + 0.65 * k)
				draw_arc(_p(global_to), rr, 0.0, TAU, 40,
					Color(col.r, col.g, col.b, 0.75 * (1.0 - k)),
					maxf(1.0, 3.0 * (1.0 - k)))
			Juice.KIND_SWEEP:
				if clip_from != null and is_instance_valid(clip_from):
					clip_rect = clip_from.get_global_rect()
				_sweep(k)

	## Диагональный блик, ограниченный прямоугольником панели: наружу не утекает.
	func _sweep(k: float) -> void:
		if clip_rect.size.x <= 1.0 or clip_rect.size.y <= 1.0:
			return
		var o := _p(clip_rect.position)
		var band := maxf(24.0, clip_rect.size.x * 0.22)
		var span := clip_rect.size.x + band * 2.0
		var lead := o.x - band + span * k
		for i in 6:
			var t := float(i) / 5.0
			var x := lead + (t - 0.5) * band
			if x < o.x or x > o.x + clip_rect.size.x:
				continue
			var a := 0.10 * (1.0 - absf(t - 0.5) * 2.0) * (1.0 - k)
			draw_line(Vector2(x, o.y),
				Vector2(x + clip_rect.size.y * 0.35, o.y + clip_rect.size.y),
				Color(col.r, col.g, col.b, a), 6.0)


static func _kill_prev(node: Control) -> void:
	var prev: Tween = node.get_meta(META_TWEEN, null) as Tween
	if prev != null and prev.is_valid():
		prev.kill()
	if node.has_meta(META_TWEEN):
		node.remove_meta(META_TWEEN)


## Карточка, по которой режется блик: CenterContainer растянут на весь экран.
static func _card_of(popup: Control) -> Control:
	if popup is Container and popup.get_child_count() > 0:
		var first := popup.get_child(0) as Control
		if first != null:
			return first
	return popup


## Открытие модалки. dim и popup показываются СРАЗУ: анимация не должна
## оставлять окно невидимым, иначе синхронные тесты и ESC-логика врут.
## Фейд есть всегда (R2): ленивые окна без размера анимируются только фейдом.
static func open(dim: Control, popup: Control) -> void:
	if popup == null or not is_instance_valid(popup):
		return
	if dim != null and is_instance_valid(dim):
		dim.visible = true
		dim.modulate.a = 1.0
	popup.visible = true
	popup.modulate.a = 1.0
	if not enabled:
		return
	_kill_prev(popup)
	if popup.size.x > 1.0 and popup.size.y > 1.0:
		popup.pivot_offset = popup.size * 0.5
		var amp := clampf(OPEN_SHRINK_PX / popup.size.y, 0.0, OPEN_MAX_AMP)
		popup.scale = Vector2(1.0 - amp, 1.0 - amp)
	var tp := popup.create_tween()
	tp.tween_property(popup, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK)
	if dim == null or not is_instance_valid(dim):
		popup.modulate.a = 0.0
		tp.parallel().tween_property(popup, "modulate:a", 1.0, 0.13)
	else:
		dim.modulate.a = 0.0
		var td := dim.create_tween()
		td.tween_property(dim, "modulate:a", 1.0, 0.13).set_trans(Tween.TRANS_SINE)
	popup.set_meta(META_TWEEN, tp)
	var fx := _spawn(popup, KIND_SWEEP, Callable())
	if fx != null:
		fx.duration = 0.30
		var card := _card_of(popup)
		fx.clip_from = card
		fx.clip_rect = card.get_global_rect()
		fx.col = UIStyle.GOLD


## Закрытие строго синхронное (R1): фейда закрытия нет никогда. Отложенный hide
## оставлял dim живым на 0.12 с и съедал следующий тап.
static func close(dim: Control, popup: Control) -> void:
	if popup == null or not is_instance_valid(popup):
		return
	_kill_prev(popup)
	if dim != null and is_instance_valid(dim):
		dim.visible = false
		dim.modulate.a = 1.0
	popup.visible = false
	popup.scale = Vector2.ONE
	popup.modulate.a = 1.0


## Короткий «толчок» цели + кольцо. Один pop на узел за кадр (R6): иначе
## two-в-одном-кадре (трата + возврат) обрывают твин на середине и метка дёргается.
static func pop(node: Control, color: Color) -> void:
	if node == null or not is_instance_valid(node) or not enabled:
		return
	if node.has_meta(META_POP_FRAME):
		if int(node.get_meta(META_POP_FRAME)) == Engine.get_frames_drawn():
			return
	node.set_meta(META_POP_FRAME, Engine.get_frames_drawn())
	node.pivot_offset = node.size * 0.5
	_kill_prev(node)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.07, 1.07), 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_BACK)
	node.set_meta(META_TWEEN, tw)
	var rect := node.get_global_rect()
	ring(node, rect.get_center(), color, maxf(24.0, rect.size.x * 0.35))


static func fly(target: Control, from: Vector2, to: Vector2, color: Color,
		dur: float = FLY_DUR, arrive: Callable = Callable()) -> void:
	if not enabled:
		if arrive.is_valid():
			arrive.call()
		return
	var fx := _spawn(target, KIND_FLY, arrive)
	if fx == null:
		return
	fx.duration = dur
	fx.global_from = from
	fx.global_to = to
	fx.col = color


static func spark(target: Control, from: Vector2, to: Vector2, color: Color,
		count: int = 4) -> void:
	if not enabled:
		return
	var fx := _spawn(target, KIND_SPARK, Callable())
	if fx == null:
		return
	fx.duration = 0.34
	fx.global_from = from
	fx.global_to = to
	fx.col = color
	fx.count = clampi(count, 1, 6)
	for i in fx.count:
		fx._jitter.append(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)))


static func ring(target: Control, at: Vector2, color: Color,
		radius: float = 46.0) -> void:
	if not enabled:
		return
	var fx := _spawn(target, KIND_RING, Callable())
	if fx == null:
		return
	fx.duration = 0.26
	fx.global_to = at
	fx.col = color
	fx.radius = maxf(12.0, radius)
