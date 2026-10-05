class_name SigilCraftRitual
extends Control
## Полноэкранный процедурный ритуал трансмутации (Godot 4, чистый _draw).
##
## СИНХРОНИЗАЦИЯ С КАРТОЧКОЙ:
##   1) add_child(ritual)
##   2) ritual.on_card_reveal.connect(_show_card)   # ТОЛЬКО тут создавать карту
##   3) когда пришёл ответ сервера -> ritual.deliver_result(payload)
##   Если сервер молчит, ритуал удерживает кульминацию до MAX_HOLD секунд.
##
## API:
##   accent          — Color акцента (по редкости)
##   strength        — 0.7..1.2 интенсивность
##   interactive     — руны кликабельны, центр удерживается
##   allow_skip      — Space ускоряет до гейта (не ломает синхронизацию)
##   mobile_fallback — без distortion/trails, вдвое меньше частиц
##
## Методы: deliver_result(payload), finish_now(), abort()

# ── События ───────────────────────────────────────────────────────────
signal on_start
signal on_circle_complete
signal on_activation
signal on_core_morph
signal on_hold_begin                       ## ждём ответ сервера
signal on_card_reveal(rect: Rect2, payload: Variant)  ## ПОКАЗАТЬ КАРТУ ЗДЕСЬ
signal on_flash
signal on_settle
signal on_complete
signal on_sigil_activated(index: int)
signal on_resonance_complete

# ── Фазы и тайминги ───────────────────────────────────────────────────
enum Phase { SUMMON, ELEMENTS, MATERIALIZE, FLASH, SETTLE }

const DISSOLVE_END    := 1.35
const SUMMON_END      := 1.80
const ELEMENTS_END    := 3.50
const MATERIALIZE_END := 5.15
const FLASH_END       := 6.10
const DURATION        := 7.00

const GATE_T          := 4.85   ## точка удержания
const MAX_HOLD        := 5.00   ## максимум ожидания СЕРВЕРА
const INTERACT_GRACE  := 8.00   ## «терпение» к игроку: ждём после последнего тапа
const RUNE_COUNT      := 8
const CARD_Z_HINT     := 61

# ── Конфиг ────────────────────────────────────────────────────────────
var accent := Color(1.0, 0.7, 0.2)
var strength := 0.7
var interactive := true
var allow_skip := true
var mobile_fallback := false

# ── Время ─────────────────────────────────────────────────────────────
var _t := 0.0          ## таймлайн фаз (замирает на гейте)
var _vt := 0.0         ## визуальное время (никогда не замирает)
var _hold := 0.0       ## сколько уже ждём сервер
var _hold_idle := 0.0  ## сколько ждём игрока без тапов
var _holding := false
var _skip_interact := false
var _force_finish := false

# ── Состояние ─────────────────────────────────────────────────────────
var _phase := -1
var _spin := 0.0
var _spin2 := 0.0
var _spin3 := 0.0
# (зацикленное верчение управляется фазами: MATERIALIZE->start, FLASH->stop)
var _flash := 0.0
var _shake := 0.0
var _gm := 1.0

# Фазовые драйверы
var _gather := 0.0
var _dissolve := 0.0
var _beams := 0.0
var _morph := 0.0
var _shockwave := 0.0
var _rune_fade := 0.0
var _decay := 0.0

# Синхронизация с карточкой
var _result_ready := false
var _payload: Variant = null
var _card_revealed := false
var _placeholder := 1.0

# Интерактив
var _rune_active: Array[bool] = []
var _activated := 0
var _resonance_done := false
var _hover := -1
var _pointer := Vector2.ZERO
var _pressed := false
var _focus := 0.0
var _tap_pulse := 0.0

# Частицы
var _dancers: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _rays: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _smoke: Array[Dictionary] = []
var _bolts: Array[Dictionary] = []

var _hint: Label
var _sub_hint: Label
var _rng := RandomNumberGenerator.new()
var _bolt_rng := RandomNumberGenerator.new()
var require_resonance := false  ## true = ждать резонанса, даже если игрок ещё не тапал


# =====================================================================
#  ЖИЗНЕННЫЙ ЦИКЛ
# =====================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 60

	strength = clampf(strength, 0.7, 1.2)
	_rng.randomize()
	_bolt_rng.randomize()

	for i in RUNE_COUNT:
		_rune_active.append(false)

	_seed_particles()
	_create_hints()
	_enter_phase(Phase.SUMMON)
	on_start.emit()


func _create_hints() -> void:
	_hint = Label.new()
	_hint.name = "RitualHint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.83
	_hint.anchor_bottom = 0.94
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	_hint.add_theme_color_override(
		"font_shadow_color", Color(accent.r, accent.g, accent.b, 0.95))
	_hint.add_theme_constant_override("shadow_offset_x", 0)
	_hint.add_theme_constant_override("shadow_offset_y", 3)
	_hint.add_theme_constant_override("shadow_outline_size", 8)
	_hint.modulate.a = 0.0
	add_child(_hint)

	_sub_hint = Label.new()
	_sub_hint.name = "RitualSubHint"
	_sub_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_hint.anchor_left = 0.0
	_sub_hint.anchor_right = 1.0
	_sub_hint.anchor_top = 0.94
	_sub_hint.anchor_bottom = 0.985
	_sub_hint.add_theme_font_size_override("font_size", 13)
	_sub_hint.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	_sub_hint.add_theme_color_override(
		"font_shadow_color", Color(accent.r, accent.g, accent.b, 0.75))
	_sub_hint.add_theme_constant_override("shadow_offset_y", 2)
	_sub_hint.add_theme_constant_override("shadow_outline_size", 5)
	_sub_hint.modulate.a = 0.0
	add_child(_sub_hint)


# =====================================================================
#  ПУБЛИЧНОЕ API ДЛЯ РОДИТЕЛЯ
# =====================================================================

## Сервер ответил. Ритуал снимает удержание и идёт к вспышке.
func deliver_result(payload: Variant = null) -> void:
	_payload = payload
	if _result_ready:
		return
	_result_ready = true
	if _holding:
		_holding = false
		_flash = maxf(_flash, 0.35)
		_shake = maxf(_shake, 0.5)


## Форсировать кульминацию немедленно (например, игрок тапнул «пропустить»).
func finish_now(payload: Variant = null) -> void:
	_force_finish = true
	deliver_result(payload)
	if _t < MATERIALIZE_END:
		_t = MATERIALIZE_END - 0.01


## Жёсткое закрытие без финала.
func abort() -> void:
	on_complete.emit()
	queue_free()


## Прямоугольник, где «материализуется» карта — родитель ставит карту сюда.
func card_rect() -> Rect2:
	var c := size * 0.5
	var r := _radius()
	var s := Vector2(r * 0.88, r * 1.24)
	return Rect2(c - s * 0.5, s)


func is_waiting_for_result() -> bool:
	return _holding


# =====================================================================
#  ФАЗОВАЯ МАШИНА
# =====================================================================

func _phase_at(time: float) -> int:
	if time < SUMMON_END:      return Phase.SUMMON
	if time < ELEMENTS_END:    return Phase.ELEMENTS
	if time < MATERIALIZE_END: return Phase.MATERIALIZE
	if time < FLASH_END:       return Phase.FLASH
	return Phase.SETTLE


func _enter_phase(next: int) -> void:
	_phase = next
	match _phase:
		Phase.SUMMON:
			Sfx.ritual_phase()  # призыв: 1 раз в начале
			_hint.text = "ПРИЗЫВ ПЕЧАТИ"
			_flash = 0.85; _shake = 0.8
		Phase.ELEMENTS:
			_hint.text = "СТИХИИ ОТКЛИКАЮТСЯ"
			_flash = 0.38; _shake = 0.55
			on_circle_complete.emit()
			on_activation.emit()
		Phase.MATERIALIZE:
			Sfx.ritual_phase()  # материализация: 1 раз в середине
			# TODO(звук): зацикленное верчение (Sfx.ritual_spin + ritual_spin_stop)
			# отключено — кусок/луп подобраны плохо, звук «сломан». Доделать:
			# подобрать start_sec/len_sec под ритм и фейд петли, затем раскомментить.
			_hint.text = "ФОРМА ОБРЕТАЕТ ПЛОТЬ"
			_flash = 0.65; _shake = 0.9
			on_core_morph.emit()
			_spawn_sparks()
		Phase.FLASH:
			# TODO(звук): Sfx.ritual_spin_stop() — см. MATERIALIZE (верчение отключено).
			_hint.text = "ТРАНСМУТАЦИЯ ЗАВЕРШЕНА"
			_flash = 1.0; _shake = 1.2
			on_flash.emit()
			_spawn_burst()
			_reveal_card()
		Phase.SETTLE:
			_hint.text = ""
			on_settle.emit()
			_spawn_smoke()


## Момент, когда родитель ОБЯЗАН показать карту — под белой вспышкой.
func _reveal_card() -> void:
	if _card_revealed:
		return
	_card_revealed = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # отдаём ввод карточке
	_hover = -1
	# Звук карты при завершении играет _show_sigil_card (discovery/legendary).
	# Отдельный ritual_reveal давал дубль.
	on_card_reveal.emit(card_rect(), _payload)


# =====================================================================
#  PROCESS
# =====================================================================

func _process(delta: float) -> void:
	_vt += delta

	# Ожидание игрока и сервера независимы.
	var waiting_server := not _result_ready

	var waiting_player := interactive \
		and not _resonance_done \
		and not _skip_interact \
		and not _force_finish \
		and (require_resonance or _activated > 0) \
		and (require_resonance or _hold_idle < INTERACT_GRACE)

	# До гейта идём по обычному таймлайну. Переход через него не проскакивает
	# даже на кадре с большим delta.
	if _t < GATE_T:
		_t = minf(_t + delta, GATE_T)
	else:
		if waiting_server or waiting_player:
			if not _holding:
				_holding = true
				on_hold_begin.emit()

			if waiting_server:
				_hold += delta

			if waiting_player:
				_hold_idle += delta
		else:
			_holding = false
			_t += delta

	if _t >= DURATION:
		Sfx.ritual_spin_stop()
		on_complete.emit()
		queue_free()
		return

	var next := _phase_at(_t)
	if next != _phase:
		_enter_phase(next)

	# --- Вращения ---
	var spd := 1.0
	if _phase == Phase.MATERIALIZE:
		spd = 1.0 + _morph * 3.0
		if _holding:
			spd = 2.0 + 0.6 * sin(_vt * 2.2)   # «дыхание» на удержании
	elif _phase == Phase.FLASH:
		spd = 0.3
	elif _phase == Phase.SETTLE:
		spd = 0.15
	_spin  += delta * (0.9 + 1.4 * strength) * spd
	_spin2 -= delta * (0.5 + 0.8 * strength) * spd
	_spin3 += delta * (0.3 + 0.55 * strength) * spd


	_flash = maxf(0.0, _flash - delta * 1.9)
	_shake = maxf(0.0, _shake - delta * 1.15)
	_tap_pulse = maxf(0.0, _tap_pulse - delta * 2.8)

	# --- Фазовые драйверы ---
	_dissolve  = smoothstep(0.0, DISSOLVE_END, _t)
	_gather    = smoothstep(0.0, SUMMON_END, _t)
	_beams     = smoothstep(SUMMON_END, ELEMENTS_END, _t)
	_morph     = smoothstep(ELEMENTS_END, MATERIALIZE_END, _t)
	_shockwave = smoothstep(MATERIALIZE_END, MATERIALIZE_END + 0.6, _t)
	_rune_fade = smoothstep(MATERIALIZE_END + 0.25, FLASH_END, _t)
	_decay     = smoothstep(FLASH_END, DURATION, _t)
	_gm        = 1.0 - smoothstep(FLASH_END + 0.35, DURATION, _t)

	if _card_revealed:
		_placeholder = move_toward(_placeholder, 0.0, delta * 5.0)

	# --- Фокус (удержание центра) ---
	var focus_target := 0.0
	if interactive and _pressed and not _card_revealed:
		if _pointer.distance_to(size * 0.5) <= _live_radius() * 0.26:
			focus_target = 1.0
	_focus = move_toward(_focus, focus_target, delta * 4.5)

	_update_particles(delta, spd)
	_update_hints()
	queue_redraw()


func _update_particles(delta: float, spd: float) -> void:
	var R := _live_radius()
	var c := size * 0.5

	for d in _dancers:
		d["ang"] = float(d["ang"]) + float(d["omega"]) * delta * spd \
			* (0.85 + 0.3 * sin(_vt + float(d["phase"])))
		if not mobile_fallback and bool(d.get("trail", false)):
			var p := c + Vector2.from_angle(float(d["ang"])) * _dancer_r(d, R)
			var tr: Array = d["trail_pts"]
			tr.insert(0, p)
			if tr.size() > 7:
				tr.resize(7)

	for em in _embers:
		em["life"] = float(em["life"]) + delta
		em["y"] = float(em["y"]) - float(em["vy"]) * delta / maxf(size.y, 1.0)
		if float(em["y"]) < -0.14:
			em["y"] = _rng.randf_range(0.3, 0.55)
			em["x"] = _rng.randf_range(-0.34, 0.34)
			em["life"] = 0.0

	for i in range(_sparks.size() - 1, -1, -1):
		var sp: Dictionary = _sparks[i]
		sp["life"] = float(sp["life"]) + delta
		if float(sp["life"]) >= float(sp["max_life"]):
			_sparks.remove_at(i)
			continue
		sp["vel_y"] = float(sp["vel_y"]) + 120.0 * delta
		sp["px"] = float(sp["px"]) + float(sp["vel_x"]) * delta
		sp["py"] = float(sp["py"]) + float(sp["vel_y"]) * delta

	for i in range(_smoke.size() - 1, -1, -1):
		var sm: Dictionary = _smoke[i]
		sm["life"] = float(sm["life"]) + delta
		if float(sm["life"]) >= float(sm["max_life"]):
			_smoke.remove_at(i)
			continue
		sm["py"] = float(sm["py"]) - float(sm["vy"]) * delta
		sm["sz"] = float(sm["sz"]) + float(sm["grow"]) * delta

	for i in range(_bolts.size() - 1, -1, -1):
		_bolts[i]["life"] = float(_bolts[i]["life"]) - delta
		if float(_bolts[i]["life"]) <= 0.0:
			_bolts.remove_at(i)

	var bolt_phase := (_phase == Phase.MATERIALIZE)
	if bolt_phase and (_t > ELEMENTS_END + 0.4 or _holding):
		var rate := 8.0 * strength
		if _holding:
			rate = 14.0 * strength
		if _rng.randf() < delta * rate:
			_spawn_bolt()


func _update_hints() -> void:
	var start := 0.0
	var finish := SUMMON_END
	match _phase:
		Phase.ELEMENTS:    start = SUMMON_END;     finish = ELEMENTS_END
		Phase.MATERIALIZE: start = ELEMENTS_END;    finish = MATERIALIZE_END
		Phase.FLASH:       start = MATERIALIZE_END; finish = FLASH_END
		Phase.SETTLE:      start = FLASH_END;       finish = DURATION

	if _holding and not _card_revealed:
		var w_res := not _result_ready
		var w_play := interactive and not _resonance_done and _activated > 0
		if w_play and w_res:
			_hint.text = "РЕЗОНАНС %d/%d • ЖДЁТ ОТКЛИКА" % [_activated, RUNE_COUNT]
		elif w_play:
			_hint.text = "АКТИВИРУЙТЕ РУНЫ • %d/%d" % [_activated, RUNE_COUNT]
		elif _hold > 0.5:
			_hint.text = "ПЕЧАТЬ ЖДЁТ ОТКЛИКА"

	var appear := smoothstep(start, start + 0.22, _t)
	var disappear := 1.0 - smoothstep(finish - 0.2, finish, _t)
	_hint.modulate.a = appear * disappear * _gm

	if not interactive or _card_revealed:
		_sub_hint.modulate.a = move_toward(_sub_hint.modulate.a, 0.0, 0.08)
		return

	if _hover >= 0:
		_sub_hint.text = "РУНА %02d • РЕЗОНАНС %d/%d" % [
			_hover + 1, _activated, RUNE_COUNT]
	elif _focus > 0.15:
		_sub_hint.text = "СТАБИЛИЗАЦИЯ ЯДРА"
	elif _resonance_done:
		_sub_hint.text = "РЕЗОНАНС ЗАВЕРШЁН"
	else:
		_sub_hint.text = "КАСАЙТЕСЬ РУН • УДЕРЖИВАЙТЕ ЦЕНТР"

	var a := smoothstep(0.4, 1.0, _t) * (1.0 - smoothstep(
		MATERIALIZE_END - 0.4, MATERIALIZE_END, _t))
	_sub_hint.modulate.a = a * _gm


# =====================================================================
#  ВВОД
# =====================================================================

func _gui_input(event: InputEvent) -> void:
	if not interactive or _card_revealed:
		return

	if event is InputEventMouseMotion:
		_pointer = event.position
		_set_hover(_hit_rune(_pointer))
		if _pressed:
			_try_activate(_pointer)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pointer = event.position
			_pressed = event.pressed
			if event.pressed:
				_try_activate(_pointer)
	elif event is InputEventScreenTouch:
		_pointer = event.position
		_pressed = event.pressed
		if event.pressed:
			_set_hover(_hit_rune(_pointer))
			_try_activate(_pointer)
		else:
			_set_hover(-1)
	elif event is InputEventScreenDrag:
		_pointer = event.position
		_set_hover(_hit_rune(_pointer))
		_try_activate(_pointer)
	else:
		return

	accept_event()


func _input(event: InputEvent) -> void:
	if not allow_skip or _card_revealed:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if _t < GATE_T:
				_t = GATE_T
				_flash = maxf(_flash, 0.5)
				_shake = maxf(_shake, 0.7)
			else:
				_skip_interact = true   # пропустить ожидание резонанса
			get_viewport().set_input_as_handled()


func _set_hover(index: int) -> void:
	if index == _hover:
		return
	_hover = index
	mouse_default_cursor_shape = (Control.CURSOR_POINTING_HAND
		if index >= 0 else Control.CURSOR_ARROW)
	queue_redraw()


func _hit_rune(p: Vector2) -> int:
	if _t < 0.35 or _phase >= Phase.FLASH:
		return -1
	var hit_r := maxf(26.0, _live_radius() * 0.13)
	for i in RUNE_COUNT:
		if p.distance_to(_rune_pos(i)) <= hit_r:
			return i
	return -1


func _try_activate(p: Vector2) -> void:
	var idx := _hit_rune(p)
	if idx >= 0:
		_activate_rune(idx)


func _activate_rune(index: int) -> void:
	_hold_idle = 0.0        # игрок активен — ритуал продолжает ждать
	_tap_pulse = 1.0
	_shake = maxf(_shake, 0.22)
	_flash = maxf(_flash, 0.16)
	if _rune_active[index]:
		return

	_rune_active[index] = true
	_activated += 1
	Sfx.ritual_rune()
	on_sigil_activated.emit(index)
	_spawn_micro_sparks(_rune_pos(index))
	_spawn_bolt_to_center(_rune_pos(index))

	if _activated >= RUNE_COUNT and not _resonance_done:
		_resonance_done = true
		_flash = maxf(_flash, 0.45)
		_shake = maxf(_shake, 0.5)
		on_resonance_complete.emit()


# =====================================================================
#  СПАВН ЧАСТИЦ
# =====================================================================

func _seed_particles() -> void:
	var k := 0.5 if mobile_fallback else 1.0
	for i in int((26 + 26 * strength) * k):
		_dancers.append(_make_dancer(0.93, 0.10, 0.65))
	for i in int((16 + 18 * strength) * k):
		_dancers.append(_make_dancer(0.56, 0.12, 0.95))
	for i in int((10 + 14 * strength) * k):
		_embers.append({
			"x": _rng.randf_range(-0.34, 0.34),
			"y": _rng.randf_range(0.2, 0.55),
			"vy": _rng.randf_range(60.0, 140.0) * strength,
			"sway": _rng.randf_range(18.0, 46.0),
			"phase": _rng.randf() * TAU,
			"size": _rng.randf_range(1.5, 3.5),
			"life": 0.0,
		})
	for i in 14:
		_rays.append({
			"ang": TAU * float(i) / 14.0 + _rng.randf_range(-0.08, 0.08),
			"len": _rng.randf_range(0.5, 0.88),
			"width": _rng.randf_range(1.0, 2.2),
			"phase": _rng.randf() * TAU,
		})
	for i in int(28 * k):
		_dust.append({
			"ang": _rng.randf() * TAU,
			"radius": _rng.randf(),
			"size": _rng.randf_range(0.9, 1.9),
			"phase": _rng.randf() * TAU,
			"dir": 1.0 if _rng.randf() > 0.4 else -1.0,
		})


func _make_dancer(rf: float, amp: float, speed: float) -> Dictionary:
	return {
		"ang": _rng.randf() * TAU,
		"omega": speed * (1.0 if _rng.randf() > 0.25 else -1.0),
		"radius_factor": rf,
		"amplitude": amp,
		"phase": _rng.randf() * TAU,
		"size": _rng.randf_range(1.4, 3.2),
		"bright": _rng.randf_range(0.45, 1.0),
		"trail": (not mobile_fallback) and _rng.randf() < 0.18,
		"trail_pts": [],
	}


func _spawn_sparks() -> void:
	var count := int((150 + 100 * strength) * (0.5 if mobile_fallback else 1.0))
	var c := size * 0.5
	for i in count:
		var a := _rng.randf() * TAU
		var s := _rng.randf_range(80.0, 260.0) * strength
		_sparks.append({
			"px": c.x, "py": c.y,
			"vel_x": cos(a) * s, "vel_y": sin(a) * s - 60.0,
			"life": 0.0, "max_life": _rng.randf_range(0.6, 1.4),
			"size": _rng.randf_range(1.0, 2.8), "hot": _rng.randf(),
		})


func _spawn_burst() -> void:
	var count := int((200 + 150 * strength) * (0.5 if mobile_fallback else 1.0))
	var c := size * 0.5
	for i in count:
		var a := _rng.randf() * TAU
		var s := _rng.randf_range(120.0, 400.0)
		_sparks.append({
			"px": c.x, "py": c.y,
			"vel_x": cos(a) * s, "vel_y": sin(a) * s,
			"life": 0.0, "max_life": _rng.randf_range(0.4, 1.0),
			"size": _rng.randf_range(1.2, 3.0), "hot": _rng.randf(),
		})


func _spawn_micro_sparks(p: Vector2) -> void:
	var c := size * 0.5
	for i in (4 if mobile_fallback else 8):
		var dir := (p - c).normalized().rotated(_rng.randf_range(-0.9, 0.9))
		var s := _rng.randf_range(35.0, 95.0)
		_sparks.append({
			"px": p.x, "py": p.y,
			"vel_x": dir.x * s, "vel_y": dir.y * s,
			"life": 0.0, "max_life": _rng.randf_range(0.22, 0.45),
			"size": _rng.randf_range(1.0, 2.2), "hot": 1.0,
		})


func _spawn_smoke() -> void:
	var c := size * 0.5
	for i in (6 if mobile_fallback else 12):
		_smoke.append({
			"px": c.x + _rng.randf_range(-45.0, 45.0),
			"py": c.y + _rng.randf_range(-25.0, 25.0),
			"vy": _rng.randf_range(18.0, 45.0),
			"sz": _rng.randf_range(6.0, 14.0),
			"grow": _rng.randf_range(8.0, 18.0),
			"life": 0.0, "max_life": _rng.randf_range(1.0, 2.0),
		})


func _spawn_bolt() -> void:
	var c := size * 0.5
	var R := _live_radius()
	var a := _rng.randf() * TAU
	_bolts.append({
		"from": c + Vector2.from_angle(a) * R * 0.9,
		"to": c + Vector2.from_angle(a + PI) * R * _rng.randf_range(0.05, 0.22),
		"life": 0.15, "max_life": 0.15, "seed": _rng.randi(),
	})


func _spawn_bolt_to_center(p: Vector2) -> void:
	_bolts.append({
		"from": p, "to": size * 0.5,
		"life": 0.18, "max_life": 0.18, "seed": _rng.randi(),
	})


# =====================================================================
#  DRAW
# =====================================================================

func _radius() -> float:
	return minf(size.x, size.y) * 0.30


func _live_radius() -> float:
	return _radius() * (0.62 + 0.38 * smoothstep(0.0, SUMMON_END, _t))


func _rune_pos(index: int) -> Vector2:
	var a := TAU * float(index) / float(RUNE_COUNT) + _spin * 0.3
	return size * 0.5 + Vector2.from_angle(a) * _live_radius()


func _draw() -> void:
	var c := size * 0.5
	if _shake > 0.01:
		var j := _shake * 3.5
		c += Vector2(_rng.randf_range(-j, j), _rng.randf_range(-j, j))

	if not mobile_fallback and _phase == Phase.MATERIALIZE and _morph > 0.1:
		c += Vector2(sin(_vt * 8.0) * 2.5, cos(_vt * 6.3) * 1.8) * _morph

	var R := _live_radius()
	var summon := smoothstep(0.0, SUMMON_END, _t)
	var bg_fade := 1.0
	if _card_revealed:
		bg_fade = 1.0 - _decay * 0.45   # фон держится, чтобы карта читалась

	draw_rect(Rect2(Vector2.ZERO, size),
		Color(0.01, 0.01, 0.02, 0.88 * summon * _gm * bg_fade), true)

	if _flash > 0.003:
		_soft_glow(c, R * (1.5 + 1.2 * _flash) + 50.0,
			Color(1.0, 0.97, 0.9, 0.5 * _flash * _gm))

	if R <= 1.0 or _gm <= 0.003:
		return

	_draw_rays(c, R, summon)
	_draw_circle_layers(c, R, summon)
	if interactive and not _card_revealed:
		_draw_interaction_fx(c, R)
	if _dissolve < 0.999:
		_draw_dissolve_edge(c, R)
	if _t >= SUMMON_END and _t < MATERIALIZE_END + 0.5:
		_draw_beams(c)
	if _t >= ELEMENTS_END:
		_draw_materialize_fx(c, R)
	if _holding:
		_draw_hold_indicator(c, R)
	if _phase >= Phase.FLASH:
		_draw_flash_fx(c, R)
	if _phase == Phase.SETTLE:
		_draw_smoke()
	_draw_orbiting_dust(c, R)
	_draw_particles(c, R)
	_draw_sparks()
	_draw_core(c)


# --- Dissolve-reveal круга --------------------------------------------

func _draw_dissolve_edge(c: Vector2, R: float) -> void:
	var segs := 84
	for i in segs:
		var f := float(i) / float(segs)
		var a := TAU * f
		var na := TAU * float(i + 1) / float(segs)
		var n := 0.5 + 0.5 * sin(f * TAU * 5.0 + 1.7 * sin(f * TAU * 3.0))
		var app := clampf((_dissolve * 1.3 - n * 0.3) / 0.25, 0.0, 1.0)
		if app <= 0.01:
			continue
		_stroke(c + Vector2.from_angle(a) * R,
			c + Vector2.from_angle(na) * R, 0.55 * app, 2.0)
		if app > 0.15 and app < 0.85:
			_glow_dot(c + Vector2.from_angle(a) * R, 2.2, 0.9)


# --- Лучи --------------------------------------------------------------

func _draw_rays(c: Vector2, R: float, amount: float) -> void:
	draw_set_transform_matrix(Transform2D(_spin3, c))
	for ray in _rays:
		var a := float(ray["ang"]) + sin(_vt * 0.8 + float(ray["phase"])) * 0.1
		var dir := Vector2.from_angle(a)
		var ray_len := R * float(ray["len"]) \
			* (0.75 + 0.25 * sin(_vt * 1.1 + float(ray["phase"])))
		draw_line(dir * R * 0.18, dir * ray_len,
			_accent_color(0.18 * amount * (1.0 - _rune_fade * 0.7)),
			float(ray["width"]), true)
	draw_set_transform_matrix(Transform2D())


# --- Кольца, руны, стихии, узлы ----------------------------------------

func _draw_circle_layers(c: Vector2, R: float, summon: float) -> void:
	var reveal := _dissolve
	var rune_a := reveal * (1.0 - _rune_fade)
	if rune_a <= 0.003:
		return

	_ring(c, R, 0.92 * summon * rune_a, 2.5 + strength, 11.0)
	_ring(c, R * 0.94, 0.42 * summon * rune_a, 1.2, 4.0)

	draw_set_transform_matrix(Transform2D(_spin3, c))
	for i in 12:
		var a := TAU * float(i) / 12.0
		_draw_rune(Vector2.from_angle(a) * R * 0.83, a, R * 0.065, i,
			0.75 * summon * rune_a)
	draw_set_transform_matrix(Transform2D())

	var elem := smoothstep(SUMMON_END, SUMMON_END + 0.65, _t)
	draw_set_transform_matrix(Transform2D(_spin2, c))
	_ring(Vector2.ZERO, R * 0.72, 0.72 * elem * rune_a, 1.7, 7.0)
	for i in 12:
		var a := TAU * float(i) / 12.0
		_stroke(Vector2.from_angle(a) * R * 0.72,
			Vector2.from_angle(a) * R * 0.62, 0.7 * elem * rune_a, 1.4)
	draw_set_transform_matrix(Transform2D())

	draw_set_transform_matrix(Transform2D(_spin, c))
	_ring(Vector2.ZERO, R * 0.49, 0.85 * summon * rune_a, 2.1, 8.0)
	for i in 6:
		var a := TAU * float(i) / 6.0
		_stroke(Vector2.from_angle(a) * R * 0.49,
			Vector2.from_angle(a + 0.48) * R * 0.36,
			0.75 * summon * rune_a, 1.8)
	draw_set_transform_matrix(Transform2D())

	if elem > 0.003:
		for i in 4:
			var a := TAU * float(i) / 4.0 - PI * 0.25 + _spin2 * 0.28
			var p := c + Vector2.from_angle(a) * R * 0.82
			_draw_element_mark(p, i, R * 0.075, elem * rune_a)
			_glow_dot(p, 2.0, 0.45 * elem * rune_a)

	# Интерактивные узлы-руны
	for i in RUNE_COUNT:
		var a := TAU * float(i) / float(RUNE_COUNT) + _spin * 0.3
		var p := c + Vector2.from_angle(a) * R
		var active: bool = _rune_active[i]
		var hovered := (_hover == i)
		var b := 0.85 * summon * rune_a
		if active:
			b *= 1.45
		if hovered:
			b *= 1.3
		_glow_dot(p, 3.2 + strength + (2.0 if hovered else 0.0), b)
		if active:
			draw_arc(p, 9.0 + sin(_vt * 5.0 + i) * 1.5, 0.0, TAU, 24,
				_accent_color(0.7 * rune_a), 1.6, true)
		if hovered:
			draw_arc(p, 15.0 + sin(_vt * 7.0) * 2.0, 0.0, TAU, 28,
				_accent_color(0.8 * rune_a), 1.5, true)


func _draw_rune(pos: Vector2, angle: float, sc: float,
		idx: int, alpha: float) -> void:
	if alpha <= 0.01:
		return
	var rad := Vector2.from_angle(angle)
	var tan := rad.orthogonal()
	var top := pos - tan * sc * 0.55
	var bot := pos + tan * sc * 0.55
	_stroke(top, bot, alpha, 1.5)
	match idx % 3:
		0:
			_stroke(top, pos + rad * sc * 0.5, alpha, 1.5)
			_stroke(pos + rad * sc * 0.5, bot, alpha, 1.5)
		1:
			_stroke(pos - tan * sc * 0.2, pos + rad * sc * 0.55, alpha, 1.5)
			_stroke(pos + rad * sc * 0.55, pos + tan * sc * 0.2, alpha, 1.5)
		2:
			_stroke(pos - rad * sc * 0.4, pos + rad * sc * 0.4, alpha, 1.5)
			_glow_dot(pos + rad * sc * 0.45, 1.2, alpha)


func _draw_element_mark(pos: Vector2, idx: int,
		sc: float, alpha: float) -> void:
	if alpha <= 0.01:
		return
	match idx:
		0:
			_stroke(pos + Vector2(0, -sc), pos + Vector2(-sc * 0.8, sc * 0.7), alpha, 1.7)
			_stroke(pos + Vector2(0, -sc), pos + Vector2(sc * 0.8, sc * 0.7), alpha, 1.7)
			_stroke(pos + Vector2(-sc * 0.8, sc * 0.7), pos + Vector2(sc * 0.8, sc * 0.7), alpha, 1.7)
		1:
			_stroke(pos + Vector2(0, sc), pos + Vector2(-sc * 0.8, -sc * 0.7), alpha, 1.7)
			_stroke(pos + Vector2(0, sc), pos + Vector2(sc * 0.8, -sc * 0.7), alpha, 1.7)
			_stroke(pos + Vector2(-sc * 0.8, -sc * 0.7), pos + Vector2(sc * 0.8, -sc * 0.7), alpha, 1.7)
		2:
			for j in 3:
				var y := (float(j) - 1.0) * sc * 0.48
				_stroke(pos + Vector2(-sc * 0.85, y),
					pos + Vector2(sc * 0.85, y - sc * 0.3), alpha, 1.5)
		3:
			var u := pos + Vector2(0, -sc)
			var r := pos + Vector2(sc * 0.8, 0)
			var d := pos + Vector2(0, sc)
			var l := pos + Vector2(-sc * 0.8, 0)
			_stroke(u, r, alpha, 1.6); _stroke(r, d, alpha, 1.6)
			_stroke(d, l, alpha, 1.6); _stroke(l, u, alpha, 1.6)
			_stroke(l, r, alpha, 1.3)


# --- Интерактив ---------------------------------------------------------

func _draw_interaction_fx(c: Vector2, R: float) -> void:
	if _hover >= 0:
		var rp := _rune_pos(_hover)
		draw_line(rp, c, _accent_color(0.16 + _tap_pulse * 0.18),
			1.0 + _tap_pulse, true)
		draw_arc(rp, 18.0 + _tap_pulse * 5.0, 0.0, TAU, 32,
			_accent_color(0.45 + _tap_pulse * 0.3), 1.2, true)

	var progress := float(_activated) / float(RUNE_COUNT)
	if progress > 0.0:
		draw_arc(c, R * 1.08, -PI * 0.5, -PI * 0.5 + TAU * progress, 64,
			_accent_color(0.12), 7.0, true)
		draw_arc(c, R * 1.08, -PI * 0.5, -PI * 0.5 + TAU * progress, 64,
			_accent_color(0.75), 2.0, true)

	if _focus > 0.01:
		_soft_glow(c, 28.0 + _focus * 20.0, _accent_color(0.16 * _focus))
		draw_arc(c, R * 0.22, -_vt * 1.5,
			-_vt * 1.5 + TAU * (0.25 + _focus * 0.75), 48,
			_accent_color(0.8 * _focus), 2.0, true)


# --- Beams --------------------------------------------------------------

func _draw_beams(c: Vector2) -> void:
	if _beams <= 0.01 or _beams >= 0.99:
		return
	var flicker := 0.5 + 0.5 * sin(_vt * TAU * 10.0)
	var ba := 0.25 * _beams * flicker
	if ba <= 0.01:
		return
	for i in 4:
		var a := TAU * float(i) / 4.0 + _spin2 * 0.15
		var edge := c + Vector2.from_angle(a) * maxf(size.x, size.y) * 0.6
		var noise := Vector2(sin(_vt * 7.3 + i * 2.1),
			cos(_vt * 5.7 + i * 3.4)) * 20.0
		var mid := (edge + c) * 0.5 + noise
		draw_line(edge, mid, _accent_color(ba * 0.5), 1.5, true)
		draw_line(mid, c, _accent_color(ba), 2.0, true)


# --- Materialize + lightning -------------------------------------------

func _draw_materialize_fx(c: Vector2, R: float) -> void:
	if _morph < 0.01:
		return
	var ramp := Color(0.45, 0.42, 0.38).lerp(accent, _morph)
	var ph := _morph * _placeholder

	if ph > 0.01:
		var w := R * 0.88 * ph
		var h := R * 1.24 * ph
		if w > 1.0 and h > 1.0:
			var rect := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
			var em := _morph * _morph * 2.0 * _placeholder
			_soft_glow(c, maxf(w, h) * 0.8 * em,
				Color(ramp.r, ramp.g, ramp.b, 0.15 * em * _gm))
			draw_rect(rect, Color(0.025, 0.02, 0.04, 0.72 * ph * _gm), true)
			draw_rect(rect.grow(5.0),
				Color(ramp.r, ramp.g, ramp.b, 0.12 * ph * _gm), false, 8.0)
			draw_rect(rect,
				Color(ramp.r, ramp.g, ramp.b, 0.9 * ph * _gm), false, 2.0)
			var inset := rect.grow(-minf(w, h) * 0.1)
			if inset.size.x > 1.0 and inset.size.y > 1.0:
				draw_rect(inset,
					Color(ramp.r, ramp.g, ramp.b, 0.38 * ph * _gm), false, 1.0)
			var scan := lerpf(rect.position.y, rect.end.y,
				fposmod(_vt * 0.8, 1.0))
			draw_line(Vector2(rect.position.x, scan),
				Vector2(rect.end.x, scan),
				Color(1.0, 0.98, 0.9, 0.7 * ph * _gm), 2.0, true)
			var gl := R * 0.14 * ph
			for i in 4:
				_stroke(c + Vector2.from_angle(TAU * float(i) / 4.0) * gl,
					c + Vector2.from_angle(TAU * float(i + 1) / 4.0) * gl,
					0.85 * ph, 2.0)

	for bolt in _bolts:
		var la := clampf(float(bolt["life"]) / float(bolt["max_life"]), 0.0, 1.0)
		_draw_bolt(bolt["from"], bolt["to"], 4, 25.0 * strength,
			la, int(bolt["seed"]))


func _draw_bolt(from: Vector2, to: Vector2, depth: int,
		disp: float, alpha: float, seed_val: int) -> void:
	if alpha <= 0.01:
		return
	if depth <= 0:
		draw_line(from, to, _accent_color(alpha * 0.25), 5.0, true)
		draw_line(from, to, Color(1.0, 0.97, 0.92, alpha * 0.85 * _gm), 1.5, true)
		return
	_bolt_rng.seed = seed_val + depth * 7919
	var mid := (from + to) * 0.5
	var perp := (to - from).orthogonal().normalized()
	mid += perp * _bolt_rng.randf_range(-disp, disp)
	_draw_bolt(from, mid, depth - 1, disp * 0.52, alpha, seed_val + 1)
	_draw_bolt(mid, to, depth - 1, disp * 0.52, alpha, seed_val + 2)
	if depth >= 2 and _bolt_rng.randf() < 0.3:
		var be := mid + perp * _bolt_rng.randf_range(-disp * 1.2, disp * 1.2) \
			+ (to - from).normalized() * disp * 0.6
		_draw_bolt(mid, be, depth - 2, disp * 0.4, alpha * 0.5, seed_val + 3)


# --- Hold indicator -----------------------------------------------------

func _draw_hold_indicator(c: Vector2, R: float) -> void:
	var a := 0.35 + 0.25 * sin(_vt * 3.0)
	for i in 8:
		var s := TAU * float(i) / 8.0 + _vt * 1.2
		draw_arc(c, R * 1.16, s, s + 0.22, 8, _accent_color(a * 0.8), 2.0, true)
	# Тонкая дуга: сколько «терпения» осталось до автопродолжения
	if interactive and not _resonance_done and _activated > 0:
		var left := clampf(1.0 - _hold_idle / INTERACT_GRACE, 0.0, 1.0)
		draw_arc(c, R * 1.10, -PI * 0.5, -PI * 0.5 + TAU * left, 48,
			_accent_color(0.30), 1.5, true)


# --- Flash / Settle -----------------------------------------------------

func _draw_flash_fx(c: Vector2, R: float) -> void:
	if _shockwave > 0.01 and _shockwave < 0.99:
		var sr := _shockwave * maxf(size.x, size.y) * 0.55
		var sa := (1.0 - _shockwave) * 0.55
		draw_arc(c, sr, 0.0, TAU, 72, _accent_color(sa * 0.3),
			12.0 * (1.0 - _shockwave) + 2.0, true)
		draw_arc(c, sr, 0.0, TAU, 72,
			Color(1.0, 0.97, 0.9, sa * _gm), 2.0, true)
	if _flash > 0.3:
		_soft_glow(c, R * 3.0 * _flash,
			Color(1.0, 0.95, 0.85, 0.2 * _flash * _gm))


func _draw_smoke() -> void:
	for sm in _smoke:
		var la := clampf(1.0 - float(sm["life"]) / float(sm["max_life"]), 0.0, 1.0)
		var sz := float(sm["sz"])
		if la <= 0.01 or sz <= 0.5:
			continue
		var p := Vector2(float(sm["px"]), float(sm["py"]))
		draw_circle(p, sz, Color(0.35, 0.3, 0.28, 0.12 * la * _gm))
		draw_circle(p, sz * 0.6, Color(0.45, 0.4, 0.35, 0.08 * la * _gm))


# --- Частицы ------------------------------------------------------------

func _draw_orbiting_dust(c: Vector2, R: float) -> void:
	var elem := smoothstep(SUMMON_END, SUMMON_END + 0.5, _t)
	for m in _dust:
		var a := float(m["ang"]) + float(m["dir"]) * _vt * 0.22
		var d := R * (0.5 + float(m["radius"]) * 0.44) \
			+ sin(_vt * 0.9 + float(m["phase"])) * R * 0.05
		_glow_dot(c + Vector2.from_angle(a) * d, float(m["size"]), 0.4 * elem)


func _draw_particles(c: Vector2, R: float) -> void:
	var elem := smoothstep(SUMMON_END * 0.5, ELEMENTS_END, _t)

	if not mobile_fallback:
		for d in _dancers:
			if not bool(d.get("trail", false)):
				continue
			var tr: Array = d["trail_pts"]
			for j in range(tr.size() - 1):
				var ta := 0.25 * (1.0 - float(j) / maxf(tr.size(), 1)) * elem
				if ta > 0.01:
					draw_line(tr[j], tr[j + 1], _accent_color(ta), 1.2, true)

	for d in _dancers:
		var p := c + Vector2.from_angle(float(d["ang"])) * _dancer_r(d, R)
		var fl := 0.8 + 0.2 * sin(_vt * 3.0 + float(d["phase"]))
		_glow_dot(p, float(d["size"]) * fl, float(d["bright"]) * elem)

	for em in _embers:
		var p := Vector2(
			size.x * (0.5 + float(em["x"]))
				+ sin(_vt * 2.0 + float(em["phase"])) * float(em["sway"]),
			size.y * (0.5 + float(em["y"])))
		var la := clampf(1.0 - float(em["life"]) / 2.2, 0.0, 1.0)
		_glow_dot(p, float(em["size"]), la * 0.85)


func _draw_sparks() -> void:
	for sp in _sparks:
		var la := clampf(1.0 - float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		if la < 0.01:
			continue
		var p := Vector2(float(sp["px"]), float(sp["py"]))
		var col := Color(1.0, 0.97, 0.9).lerp(accent, 1.0 - float(sp["hot"]) * la)
		var sz := float(sp["size"]) * la
		draw_circle(p, sz * 2.5, Color(col.r, col.g, col.b, 0.15 * la * _gm))
		draw_circle(p, sz, Color(col.r, col.g, col.b, 0.7 * la * _gm))


func _draw_core(c: Vector2) -> void:
	var pulse := 0.6 + 0.4 * sin(_vt * 3.4)
	var boost := 1.0
	if _phase == Phase.FLASH:
		boost += _flash * 2.0
	elif _phase == Phase.MATERIALIZE:
		boost += _morph * 0.8
	boost += (float(_activated) / float(RUNE_COUNT)) * 0.25 + _focus * 0.45
	if _holding:
		boost += 0.25 + 0.15 * sin(_vt * 5.0)

	_soft_glow(c, (5.0 + 10.0 * strength) * 2.4 * boost * (1.0 - _decay * 0.6),
		_accent_color(0.36 * (0.65 + 0.35 * pulse)))
	_glow_dot(c, (5.0 + 7.0 * strength * pulse) * boost * (1.0 - _decay * 0.5),
		(0.8 + 0.2 * pulse) * (1.0 - _decay * 0.7))


# =====================================================================
#  УТИЛИТЫ
# =====================================================================

func _dancer_r(d: Dictionary, R: float) -> float:
	var base := R * float(d["radius_factor"]) \
		+ sin(_vt * 1.3 + float(d["phase"])) \
		* R * float(d["amplitude"]) * 0.35
	return base + (1.0 - _gather) * R * 1.2


func _ring(center: Vector2, radius: float, alpha: float,
		width: float, glow_w: float) -> void:
	if alpha <= 0.003:
		return
	draw_arc(center, radius, 0.0, TAU, 96,
		_accent_color(alpha * 0.10), width + glow_w * 2.0, true)
	draw_arc(center, radius, 0.0, TAU, 96,
		_accent_color(alpha * 0.25), width + glow_w, true)
	draw_arc(center, radius, 0.0, TAU, 96,
		_accent_color(alpha), width, true)


func _stroke(a: Vector2, b: Vector2, alpha: float, width: float) -> void:
	if alpha <= 0.01:
		return
	draw_line(a, b, _accent_color(alpha * 0.22), width + 5.0, true)
	draw_line(a, b, _accent_color(alpha), width, true)


func _glow_dot(p: Vector2, r: float, bright: float) -> void:
	if bright <= 0.003 or r <= 0.0:
		return
	draw_circle(p, r * 3.0, _accent_color(0.15 * bright))
	draw_circle(p, r * 1.6, _accent_color(0.43 * bright))
	draw_circle(p, r, Color(1.0, 0.97, 0.88, 0.85 * bright * _gm))


func _soft_glow(p: Vector2, r: float, col: Color) -> void:
	if r <= 0.0 or col.a <= 0.003:
		return
	for i in range(5, 0, -1):
		var k := float(i) / 5.0
		draw_circle(p, r * k,
			Color(col.r, col.g, col.b, col.a * (1.0 - k * 0.75) * 0.22))


func _accent_color(alpha: float) -> Color:
	return Color(accent.r, accent.g, accent.b, clampf(alpha * _gm, 0.0, 1.0))