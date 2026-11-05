extends RefCounted
class_name TouchDrag

# Один владелец переноса; остальные пальцы не могут отпустить его призрак.
enum State { IDLE, DRAG_FROM_TRAY, SELECTED, DRAG_MOVE, CAMERA }
const TAP_SLOP := 8.0
const NO_POINTER := -1
const MOUSE_POINTER := -2

var state := State.IDLE
var selected := -1
var last_placed_id := ""
var _view
var _ghost: Dictionary = {}
var _valid := false
var _press := Vector2.ZERO
var _drag_index := -1
var _primary := NO_POINTER
var _fingers := {}
var _ignored := {}
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _panning := false
var _left_tray := false

func _init(view) -> void:
	_view = view

func ghost_exists() -> bool:
	return not _ghost.is_empty()

func ghost_valid() -> bool:
	return _valid

func capturing() -> bool:
	return ghost_exists() or _primary != NO_POINTER or not _fingers.is_empty() or _panning

func begin_from_tray(id: String, at: Vector2, pointer := NO_POINTER) -> void:
	cancel()
	if _view.read_only or not _view.built or not HouseItems.exists(id):
		return
	_ghost = {"id": id, "x": 0.0, "z": 0.0, "y": 0.0, "flip": false,
		"wall": int(HouseItems.get_item(id).get("wall_view", -1))}
	state = State.DRAG_FROM_TRAY
	_primary = pointer
	if pointer >= 0:
		_fingers[pointer] = at
	_left_tray = at.y < _view.tray_return_y
	_place_ghost(at)

func _clear_pointers() -> void:
	_primary = NO_POINTER
	_fingers.clear()
	_ignored.clear()
	_panning = false
	_pinch_dist = 0.0
	_pinch_mid = Vector2.ZERO
	_press = Vector2.ZERO

func cancel() -> void:
	cancel_ghost()
	selected = -1
	_drag_index = -1
	last_placed_id = ""
	state = State.IDLE
	_view.highlight(-1)

func cancel_ghost() -> void:
	# Отменённый перенос: узел уже сдвинут «на живую», запись в модели — нет.
	if state == State.DRAG_MOVE and _drag_index >= 0:
		_view.restore_preview(_drag_index)
	_ghost = {}
	_valid = false
	_drag_index = -1
	last_placed_id = ""
	_left_tray = false
	_clear_pointers()
	state = State.SELECTED if selected >= 0 else State.IDLE
	_view.clear_ghost()

func release() -> void:
	var mode := state
	var index := _drag_index
	var p := Placement.snap_record(_ghost) if ghost_exists() else {}
	var allowed: bool = _valid and not p.is_empty() and not _view.read_only and _view.built
	if allowed:
		if mode == State.DRAG_MOVE:
			allowed = index >= 0 and index < _view.placements.size() and Placement.move_allowed(_view.placements[index], p, _view.placements, index)
		else:
			allowed = Placement.valid(p, _view.placements)
	# Убираем состояние до синхронного сигнала Home/set_layout.
	_ghost = {}
	_valid = false
	_clear_pointers()
	_view.clear_ghost()
	last_placed_id = ""
	state = State.SELECTED if selected >= 0 else State.IDLE
	if allowed and mode == State.DRAG_FROM_TRAY:
		if _view.commit_placement(p):
			last_placed_id = String(p["id"])
	elif allowed and mode == State.DRAG_MOVE:
		_view.commit_move(index, p)
		_view.highlight(index)
		state = State.SELECTED
	elif mode in [State.DRAG_FROM_TRAY, State.DRAG_MOVE]:
		if mode == State.DRAG_MOVE:
			_view.restore_preview(index)
		_view.hint.emit("Здесь не помещается.")
		_view.placement_reaction.emit(false)
	_drag_index = -1

func select_at(at: Vector2) -> void:
	if _view.read_only or not _view.built:
		return
	_drag_index = _view.pick_item(at)
	_view.highlight(_drag_index)
	state = State.SELECTED if selected >= 0 else State.IDLE

func _place_ghost(at: Vector2) -> void:
	if not ghost_exists():
		return
	if state == State.DRAG_FROM_TRAY:
		if at.y < _view.tray_return_y:
			_left_tray = true
		elif _left_tray:
			cancel_ghost()
			_view.placement_returned.emit()
			return
	var item := HouseItems.get_item(String(_ghost["id"]))
	# Стена захватывается с текущей: `raycast_wall` перецепляет только после
	# запаса за угол, как `_wall_axis_for_cursor` в доноре.
	var hit: Dictionary = _view.raycast_wall(at, int(_ghost["wall"])) \
		if bool(item.get("wall", false)) else _view.raycast_floor(at)
	if hit.is_empty():
		_valid = false
		_show_position(_ghost)
		return
	var p := _ghost.duplicate(true)
	for key in hit:
		p[key] = hit[key]
	p = Placement.clamp_record(p)
	if state == State.DRAG_MOVE and _drag_index >= 0:
		var from: Dictionary = _view.placements[_drag_index]
		# Разрешаем уменьшение старого пересечения; иначе выталкиваем по осям.
		if not Placement.move_allowed(from, p, _view.placements, _drag_index):
			p = Placement.push_out(p, _view.placements, _drag_index)
		_valid = Placement.move_allowed(from, p, _view.placements, _drag_index)
	else:
		# Новую вещь не выталкиваем: занятое место должно оставаться красным.
		_valid = Placement.valid(p, _view.placements)
	_ghost = p
	_show_position(p)


## Призрак рисуется только для новой вещи из лотка. Переносимый предмет двигает
## собственный узел (модель донора), иначе под пальцем живёт копия, а настоящий
## предмет остаётся на месте — «мерцание при передвижении».
func _show_position(p: Dictionary) -> void:
	if state == State.DRAG_MOVE and _drag_index >= 0:
		if _valid:
			_view.preview_move(_drag_index, p)
	else:
		_view.show_ghost(p, _valid)

func _move(at: Vector2) -> void:
	if state == State.SELECTED and _drag_index >= 0 and at.distance_to(_press) > TAP_SLOP:
		_ghost = (_view.placements[_drag_index] as Dictionary).duplicate(true)
		state = State.DRAG_MOVE
	if state in [State.DRAG_FROM_TRAY, State.DRAG_MOVE]:
		_place_ghost(at)

func gui_input(event: InputEvent) -> void:
	if _view.read_only or not _view.built:
		cancel()
		return
	if event is InputEventMouseButton:
		# Godot эмулирует мышь после touch: обрабатываем только исходный путь.
		if event.device == InputEvent.DEVICE_ID_EMULATION or _primary >= 0 or not _fingers.is_empty():
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and not ghost_exists():
			_view.zoom_at(1.12, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and not ghost_exists():
			_view.zoom_at(1.0 / 1.12, event.position)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE] and not ghost_exists():
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_primary = MOUSE_POINTER
				_press = event.position
				if state == State.DRAG_FROM_TRAY:
					_place_ghost(event.position)
				else:
					select_at(event.position)
			elif _primary == MOUSE_POINTER:
				if ghost_exists():
					_place_ghost(event.position)
					if ghost_exists():
						release()
				else:
					_clear_pointers()
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION or _primary >= 0 or not _fingers.is_empty():
			return
		if _panning:
			_view.pan_screen(event.relative)
		elif state == State.DRAG_FROM_TRAY or _primary == MOUSE_POINTER:
			_move(event.position)
	elif event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)

func _touch(ev: InputEventScreenTouch) -> void:
	if ev.canceled:
		if ev.index == _primary:
			cancel_ghost()
		else:
			_fingers.erase(ev.index)
			_ignored.erase(ev.index)
		return
	if not ev.pressed:
		if _ignored.has(ev.index):
			_ignored.erase(ev.index)
			return
		if not _fingers.has(ev.index):
			return
		_fingers.erase(ev.index)
		if ev.index == _primary and ghost_exists():
			_place_ghost(ev.position)
			if ghost_exists():
				release()
			return
		if state == State.CAMERA:
			# Не превращаем оставшийся после pinch палец в случайный drag.
			for index in _fingers:
				_ignored[index] = true
			_fingers.clear()
			_primary = NO_POINTER
			state = State.SELECTED if selected >= 0 else State.IDLE
			_pinch_dist = 0.0
		elif ev.index == _primary:
			_primary = NO_POINTER
		return
	if _primary == MOUSE_POINTER or (ghost_exists() and _primary != NO_POINTER and _primary != ev.index):
		_ignored[ev.index] = true
		return
	_fingers[ev.index] = ev.position
	if ghost_exists():
		_primary = ev.index
		_place_ghost(ev.position)
		return
	if _fingers.size() == 2:
		state = State.CAMERA
		_pinch_dist = _finger_dist()
		_pinch_mid = _finger_mid()
	elif _fingers.size() > 2:
		_fingers.erase(ev.index)
		_ignored[ev.index] = true
	else:
		_primary = ev.index
		_press = ev.position
		select_at(ev.position)

func _drag(ev: InputEventScreenDrag) -> void:
	if not _fingers.has(ev.index) or _ignored.has(ev.index):
		return
	_fingers[ev.index] = ev.position
	if state == State.CAMERA:
		if _fingers.size() == 2:
			var d := _finger_dist()
			var mid := _finger_mid()
			if _pinch_dist > 0.0:
				_view.zoom_at(d / _pinch_dist, mid)
			_view.pan_screen(mid - _pinch_mid)
			_pinch_dist = d
			_pinch_mid = mid
		else:
			_view.pan_screen(ev.relative)
	elif ev.index == _primary:
		_move(ev.position)
		if ev.index == _primary and not ghost_exists() and selected < 0 and ev.position.distance_to(_press) > TAP_SLOP:
			state = State.CAMERA
			_view.pan_screen(ev.relative)

func _finger_dist() -> float:
	var pts := _fingers.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() == 2 else 0.0

func _finger_mid() -> Vector2:
	var pts := _fingers.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5 if pts.size() == 2 else Vector2.ZERO
