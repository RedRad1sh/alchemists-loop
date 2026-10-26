extends RefCounted
class_name HouseTasksData
# Поручения дома (β): Светик просит не купить, а поставить. Правила считаются на
# метровой геометрии Placement (footprint/gap) — той же, что проверяет расстановку,
# поэтому «рядом» = то, что игрок видит на полу.
# a/b — категории предметов (не id вариантов: поручение не зависит от того, что
# куплено). give — наградной вариант, его категория совпадает с парой правила.
#
# Зазоры подобраны на раскладке B: дефолтная расстановка выполняет ровно одно
# правило — hearth_on_rug, — и засчитывается сразу как подарок-онбординг.
const TASKS := [
	{"id": "hearth_on_rug", "a": "fireplace", "b": "rug", "rule": "near", "gap": 0.12,
		"text": "Поставь камин вплотную к ковру", "give": "fireplace_heart"},
	{"id": "chair_at_table", "a": "chair", "b": "table", "rule": "near", "gap": 0.12,
		"text": "Пододвинь стул к столу", "give": "window_guild"},
	{"id": "plant_by_window", "a": "plant", "b": "window", "rule": "near", "gap": 0.40,
		"text": "Посади растение у окна", "give": "window_seal"},
	{"id": "rug_tucked_bed", "a": "rug", "b": "bed", "rule": "near", "gap": 0.12,
		"text": "Заведи ковёр под кровать", "give": "fireplace_log"},
	{"id": "lamp_by_bed", "a": "lamp", "b": "bed", "rule": "near", "gap": 0.12,
		"text": "Поставь торшер рядом с кроватью", "give": "window_contract"},
	{"id": "shelf_over_bed", "a": "shelf", "b": "bed", "rule": "over", "min_y": 1.2,
		"text": "Навесить полку над кроватью", "give": "fireplace_ember"},
]
