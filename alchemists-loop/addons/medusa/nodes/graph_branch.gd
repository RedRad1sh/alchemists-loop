@tool
@icon("uid://bg0v7skhu261s")
## A specialized container for [Atom] nodes that acts as a local gravity hub.
##
## Manages a group of atoms, allowing them to be collapsed into a single point
## or dragged as a collective unit. Automatically handles the physics state of its children.
class_name GraphBranch extends Control


#region Settings
@export var physics_enabled: bool = true: ## If false, all child atoms will be set to static mode.
	set(value):
		if physics_enabled == value: return
		physics_enabled = value
		_update_atoms_physics_state()
var _atoms_static_memory: Dictionary = {} ## Memory to restore previous static states: [Atom : bool]

@export var drag_input: bool = true         ## Whether individual atoms inside can be dragged.
@export var drag_branch_input: bool = false ## Whether the branch background itself can be dragged.

#@export var gravity_strength: float = 0.01  ## How strongly this branch pulls its child atoms.
@export var collapse_speed: float = 0.4     ## Duration of the collapse/expand tween in seconds.
#endregion

#region Internal
var _is_collapsed: bool = false         ## Current state of collapse
var _pre_collapse_data: Dictionary = {} ## Stores pre-collapse local positions and states: [Atom : Dictionary]
var _collapse_tween: Tween
var _branch_drag_offset: Vector2 = Vector2.ZERO
var _is_dragging_branch: bool = false

# Boundary Cash
var _content_min_offset: Vector2 = Vector2.ZERO
var _content_max_offset: Vector2 = Vector2.ZERO
#endregion


#region Public API
## Use this function if you need to enable physics for a previously static atom or make a dynamic atom rigidly static.
## The function updates the branch memory about static atoms.
func set_atom_static_manual(atom: Atom, is_static: bool) -> void:
	if atom in get_local_atoms():
		atom.is_static = is_static
		_atoms_static_memory[atom] = is_static

## Returns the global center of the branch used as the gravity pivot.
func get_gravity_center() -> Vector2:
	var global_scale = get_global_transform().get_scale()
	return global_position + (size / 2.0 * global_scale)

## Returns all direct children that are of type [Atom].
func get_local_atoms() -> Array[Atom]:
	var result: Array[Atom] = []
	for child in get_children():
		if child is Atom: result.append(child)
	return result

## Collapses all atoms into the center of the branch.
func collapse(atom_bool_param: StringName = &"is_hidden", value: bool = true):
	if _is_collapsed: return
	_is_collapsed = true

	if _collapse_tween: _collapse_tween.kill()
	_collapse_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	# Центр ветки в локальных координатах
	var local_center = size / 2.0

	for atom in get_local_atoms():
		# Сохраняем ЛОКАЛЬНУЮ позицию.
		# Если ветка передвинется, atom.position + branch.global_position все равно даст верный результат.
		_pre_collapse_data[atom] = {
			"local_pos": atom.position,
			"original_value": atom.get(atom_bool_param)
		}

		atom.set(atom_bool_param, value)
		atom.is_static = true
		atom.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Анимируем локальную позицию к центру
		# Вычитаем pivot, чтобы именно центр атома совпал с центром ветки
		var target_local_pos = local_center - atom.pivot_offset
		_collapse_tween.tween_property(atom, "position", target_local_pos, collapse_speed)

## Expands the branch, returning all atoms to their pre-collapse positions.
func expand(atom_bool_param: StringName = &"is_hidden") -> void:
	if not _is_collapsed: return
	_is_collapsed = false

	if _collapse_tween: _collapse_tween.kill()
	_collapse_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for atom in get_local_atoms():
		var target_local_pos = atom.position

		if _pre_collapse_data.has(atom):
			var cache = _pre_collapse_data[atom]
			target_local_pos = cache["local_pos"]
			atom.set(atom_bool_param, cache["original_value"])

		atom.mouse_filter = Control.MOUSE_FILTER_STOP
		# Анимируем возврат в локальную позицию, которая была до сворачивания
		_collapse_tween.tween_property(atom, "position", target_local_pos, collapse_speed)

	_collapse_tween.chain().tween_callback(_update_atoms_physics_state)
#endregion


#region Lifecycle
func _ready() -> void:
	child_exiting_tree.connect(_on_child_exiting_tree)
	if Engine.is_editor_hint():
		set_anchors_preset(Control.PRESET_CENTER)
		custom_minimum_size = Vector2(50, 50)

func _draw() -> void:
	if Engine.is_editor_hint():
		var border_color = Color(0.2, 0.9, 0.4, 0.8)
		draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 1.5)

		var center = size / 2.0
		var center_color = Color(0.8, 1.0, 0.4)
		var size_px = 8.0

		draw_line(center - Vector2(size_px, 0), center + Vector2(size_px, 0), center_color, 2.0)
		draw_line(center - Vector2(0, size_px), center + Vector2(0, size_px), center_color, 2.0)
		draw_circle(center, 2.0, center_color)

func _notification(what: int) -> void:
	# При изменении состава - синхронизируем их физические параметры
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_sync_static_memory()
		_update_atoms_physics_state()

func _on_child_exiting_tree(node: Node) -> void:
	# Очищаем память от удаленных атомов
	if node is Atom:
		_atoms_static_memory.erase(node)
		_pre_collapse_data.erase(node)
#endregion


#region Input & Dragging
func _gui_input(event: InputEvent) -> void:
	if not drag_branch_input or Engine.is_editor_hint(): return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging_branch = true
				_branch_drag_offset = global_position - get_global_mouse_position()
				move_to_front()
				_calculate_content_bounds()
				accept_event()
			else:
				_is_dragging_branch = false
				accept_event()
	elif event is InputEventMouseMotion and _is_dragging_branch:
		var target_global_pos = get_global_mouse_position() + _branch_drag_offset

		var graph = _find_parent_graph()
		if graph:
			# Привязка к сетке
			target_global_pos = graph.snap_node_to_grid(self, target_global_pos)

			# Ограничение по границам графа
			var graph_rect = graph.get_global_rect()
			var graph_scale = graph.get_global_transform().get_scale().x

			# Масштабируем марджин
			# Если зум 2.0, то марджин в 10 пикселей превращается в 20 экранных пикселей.
			var effective_margin = 0.0
			if "boundary_margin" in graph:
				effective_margin = graph.boundary_margin * graph_scale

			# Вычисляем границы дозволенного для ТОЧКИ ВХОДА (branch global_position)
			# Мы берем край экрана, добавляем марджин и ВЫЧИТАЕМ оффсет самого крайнего атома
			var min_limit = graph_rect.position + Vector2(effective_margin, effective_margin) - _content_min_offset
			var max_limit = graph_rect.end - Vector2(effective_margin, effective_margin) - _content_max_offset

			# Защита от "схлопывания" границ на маленьких экранах
			if max_limit.x < min_limit.x: target_global_pos.x = (min_limit.x + max_limit.x) / 2.0
			else: target_global_pos.x = clamp(target_global_pos.x, min_limit.x, max_limit.x)

			if max_limit.y < min_limit.y: target_global_pos.y = (min_limit.y + max_limit.y) / 2.0
			else: target_global_pos.y = clamp(target_global_pos.y, min_limit.y, max_limit.y)

		global_position = target_global_pos
		accept_event()

## Calculates the combined bounding box of the branch and its atoms.
func _calculate_content_bounds() -> void:
	var origin = global_position

	# Начальные границы (сама ветка)
	var min_pos = Vector2.ZERO
	var max_pos = size * get_global_transform().get_scale()

	for atom in get_local_atoms():
		if not is_instance_valid(atom): continue

		var atom_scale = atom.get_global_transform().get_scale()
		var atom_radius = atom.get_effective_radius() * atom_scale.x
		var atom_center = atom.global_position + (atom.pivot_offset * atom_scale)

		# Относительное смещение центра атома от верхнего левого угла ветки
		var relative_center = atom_center - origin

		var atom_min = relative_center - Vector2(atom_radius, atom_radius)
		var atom_max = relative_center + Vector2(atom_radius, atom_radius)

		if atom_min.x < min_pos.x: min_pos.x = atom_min.x
		if atom_min.y < min_pos.y: min_pos.y = atom_min.y
		if atom_max.x > max_pos.x: max_pos.x = atom_max.x
		if atom_max.y > max_pos.y: max_pos.y = atom_max.y

	_content_min_offset = min_pos
	_content_max_offset = max_pos
#endregion


#region Helpers
func _sync_static_memory() -> void:
	var current_atoms = get_local_atoms()

	## Очищаем память
	for mem_atom in _atoms_static_memory.keys():
		if not is_instance_valid(mem_atom) or not mem_atom in current_atoms: _atoms_static_memory.erase(mem_atom)

	## Регистрируем новичков
	for atom in current_atoms:
		if not _atoms_static_memory.has(atom): _atoms_static_memory[atom] = atom.is_static

func _update_atoms_physics_state() -> void:
	if not is_inside_tree(): return
	for atom in get_local_atoms():
		# Если атом был вручную сделан статичным, не трогаем его
		if _atoms_static_memory.get(atom, false) == true:
			atom.is_static = true
			continue
		# Иначе подчиняем его общей настройке ветки
		atom.is_static = not physics_enabled

func _find_parent_graph() -> Control:
	var parent = get_parent()
	while parent:
		if parent is Graph: return parent
		parent = parent.get_parent()
	return null
#endregion
