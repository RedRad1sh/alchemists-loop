extends Node2D
# Чашка Петри: пузырьки питательной среды (тап-цели) + существо.
# Фон (каустики/стекло/боке) рисует отдельный слой dish_bg ПОД этим нодом.
# Ввод — InputEventScreenTouch (мультитач) и мышь (десктоп-тест).

const W := 720.0
const H := 1280.0
const DROP_MAX := 5
const CREATURE_POS := Vector2(360, 610)

var creature: CreatureVisual
var drops: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var _spawn_timer := 0.5
var _time := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	creature = CreatureVisual.new()
	creature.position = CREATURE_POS
	add_child(creature)
	for i in 3:
		spawn_drop()

func _process(delta: float) -> void:
	_time += delta
	if drops.size() < DROP_MAX:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			spawn_drop()
			_spawn_timer = _rng.randf_range(0.7, 1.8)
	for i in range(floaters.size() - 1, -1, -1):
		var f: Dictionary = floaters[i]
		f["t"] += delta
		var lb: Label = f["l"]
		lb.position.y -= 88.0 * delta
		var life: float = f["life"]
		lb.modulate.a = clampf((life - f["t"]) / 0.35, 0.0, 1.0)
		if f["t"] >= life:
			lb.queue_free()
			floaters.remove_at(i)
	queue_redraw()

func apply_genome(ids: Array) -> void:
	creature.set_genome_ids(ids)

func spawn_drop(forced_pos: Vector2 = Vector2.INF) -> void:
	if forced_pos != Vector2.INF:
		# детерминированный спавн (для автотестов)
		drops.append({
			"pos": forced_pos,
			"r": 22.0,
			"val": 10,
			"ph": _rng.randf_range(0.0, TAU)
		})
		return
	var pos := Vector2.ZERO
	var ok := false
	for attempt in 10:
		pos = Vector2(_rng.randf_range(64.0, W - 64.0), _rng.randf_range(150.0, 1050.0))
		if pos.distance_to(CREATURE_POS) < 250.0:
			continue
		ok = true
		for d in drops:
			if d["pos"].distance_to(pos) < 84.0:
				ok = false
				break
		if ok:
			break
	if not ok:
		return
	drops.append({
		"pos": pos,
		"r": _rng.randf_range(17.0, 27.0),
		"val": 8 + _rng.randi_range(0, 7),
		"ph": _rng.randf_range(0.0, TAU)
	})

func _unhandled_input(event: InputEvent) -> void:
	# Принимаем И тач, И мышь: на десктопе клики приходят как
	# InputEventMouseButton, на Android — InputEventScreenTouch.
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(event.position)

func _handle_tap(pos: Vector2) -> void:
	# 1) пузырёк?
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		var dpos: Vector2 = d["pos"]
		if dpos.distance_to(pos) <= float(d["r"]) + 30.0:
			var val: int = d["val"]
			GameState.add_energy(float(val))
			_add_floater(dpos + Vector2(0, -8), "+" + str(val) + " ⚡")
			Sfx.bubble()
			Input.vibrate_handheld(8)
			drops.remove_at(i)
			return
	# 2) погладить существо?
	if pos.distance_to(CREATURE_POS) <= 220.0:
		creature.bounce()
		Sfx.pet()
		Input.vibrate_handheld(18)
		EventBus.creature_pet.emit()

func _add_floater(pos: Vector2, text: String) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos + Vector2(-34, -18)
	lb.add_theme_color_override("font_color", Color8(190, 255, 230))
	lb.add_theme_font_size_override("font_size", 27)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lb.add_theme_constant_override("outline_size", 8)
	add_child(lb)
	floaters.append({"l": lb, "t": 0.0, "life": 0.95})

# ---------- отрисовка: только пузырьки (фоном занимается dish_bg) ----------

func _draw() -> void:
	var soft := Art.soft()
	# пузырьки: мягкий ореол + ядро + «влажный» блик
	for d in drops:
		var pos: Vector2 = d["pos"]
		var r: float = d["r"]
		var bob := sin(_time * 2.2 + d["ph"]) * 3.0
		pos.y += bob
		var breathe := 1.0 + 0.05 * sin(_time * 3.0 + d["ph"] * 2.0)
		# ореол
		draw_texture_rect(soft, Rect2(pos - Vector2(r * 2.4, r * 2.4) * breathe,
			Vector2(r * 4.8, r * 4.8) * breathe), false,
			Color(0.35, 0.95, 0.8, 0.16))
		# тело капли
		var c := Color8(88, 220, 186, 255)
		draw_circle(pos, r, c.darkened(0.25))
		draw_texture_rect(soft, Rect2(pos - Vector2(r * 1.0, r * 1.0),
			Vector2(r * 2.0, r * 2.0)), false, Color(c.r, c.g, c.b, 0.9))
		# ядро темнее снизу-внутри
		draw_texture_rect(soft, Rect2(pos + Vector2(r * 0.1, r * 0.25) - Vector2(r * 0.62, r * 0.62),
			Vector2(r * 1.24, r * 1.24)), false,
			Color(0.10, 0.38, 0.34, 0.85))
		# блик сверху-слева
		draw_texture_rect(soft, Rect2(pos + Vector2(-r * 0.32, -r * 0.36) - Vector2(r * 0.26, r * 0.26),
			Vector2(r * 0.52, r * 0.52)), false,
			Color(1, 1, 1, 0.5))
