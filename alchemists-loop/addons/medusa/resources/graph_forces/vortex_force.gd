## Physical force that creates a rotating vortex effect around a central point.
##
## Causes atoms to move in a circle around an axis (the center of the hub or global center).
## The rotational force decreases with distance to maintain orbital stability.
class_name GraphVortexForce extends GraphForce


@export var rotation_speed: float = 5.0   ## Base intensity of rotational thrust.
@export var clockwise: bool = true        ## Direction of the vortex rotation.


func apply_force(registry: Array, forces: Array, context: Dictionary) -> void:
	var global_center: Vector2 = context["global_center"]
	var centers: Array[Vector2] = context["centers"]
	var scales: Array[float] = context["scales"]

	for item_context in registry:
		var index = item_context.index
		var atom = item_context.atom

		if atom.is_dragging or atom.is_static or item_context.is_cold: continue

		var world_scale = scales[index]
		var atom_center = centers[index]

		# Выбор точки вращения: центр хаба или общий глобальный центр
		var pivot_point: Vector2
		if item_context.is_in_hub and is_instance_valid(item_context.gravity_target_node): pivot_point = item_context.gravity_target_node.get_gravity_center()
		else: pivot_point = global_center

		# Расчет вектора от центра вращения к атому
		var radial_vector = atom_center - pivot_point
		var distance = radial_vector.length()

		# Логическая дистанция (независимая от масштаба зума)
		var logical_distance = distance / world_scale

		# Защита от деления на ноль и "сингулярности" в самом центре
		if logical_distance < 20.0: continue

		# Расчет тангенциального вектора (перпендикуляра)
		# Стандартный перпендикуляр: (-y, x). Если не по часовой стрелке — инвертируем.
		var tangent_direction: Vector2
		if clockwise:  tangent_direction = Vector2(-radial_vector.y, radial_vector.x) / distance
		else: tangent_direction = Vector2(radial_vector.y, -radial_vector.x) / distance

		# Расчет силы вращения
		# Используем затухание (1 / distance), чтобы стабилизировать внешние орбиты
		# и избежать слишком высоких скоростей у центра.
		var force_magnitude = (rotation_speed * 10.0) / logical_distance

		# Применяем силу, масштабируя её обратно под мировой масштаб, и сохраняем в общий массив
		forces[index] += tangent_direction * (force_magnitude * world_scale)
