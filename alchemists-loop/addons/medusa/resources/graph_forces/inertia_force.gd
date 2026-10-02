## A physical property that mimics mass and resistance to movement.
##
## Heavier atoms (those with more bonds) require more effort to move.
## This prevents large nodes from moving too quickly and provides
## a sense of stability and physical weight to the entire graph.
##
## Calculated BEFORE force is applied to correctly scale the resulting velocity.
class_name InertiaForce extends GraphForce

@export var base_mass:           float = 1.0  ## Weight of an atom without bonds.
@export var mass_per_connection: float = 0.5  ## How much heavier an atom becomes with each new bond.
@export var max_mass:            float = 10.0 ## Maximum permissible weight, even for very large hubs.

func calculate_mass(registry: Array, masses: Array, _context: Dictionary) -> void:
	for item_context in registry:
		# Пропускаем, если объект невалиден или находится в "холодном" состоянии
		if not is_instance_valid(item_context.atom) or item_context.is_cold: continue

		var index = item_context.index

		# Рассчитываем массу: базовая масса + бонус за каждое соединение (чем больше связей, тем тяжелее узел)
		var calculated_mass = base_mass + item_context.atom.connected_atoms.size() * mass_per_connection

		# Обновляем массу в общем массиве:
		# Выбираем максимальное значение между текущей и расчетной массой,
		# а затем ограничиваем её сверху через max_mass.
		masses[index] = clamp(max(masses[index], calculated_mass), 0.0, max_mass)
