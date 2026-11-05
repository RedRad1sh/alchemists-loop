extends RefCounted
class_name HouseTasksData
# Поручения дома (β): Светик просит не купить, а поставить. Правила считаются на
# метровой геометрии Placement (footprint/gap) — той же, что проверяет расстановку,
# поэтому «рядом» = то, что игрок видит на полу.
# a/b — категории предметов (не id вариантов: поручение не зависит от того, что
# куплено). give — наградной вариант, подобранный по смыслу пары правила.
#
# Зазоры подобраны на раскладке B: дефолтная расстановка выполняет ровно одно
# правило — rug_under_bed, — и засчитывается сразу как подарок-онбординг.
const TASKS := [
	{"id": "rug_under_bed", "a": "rug", "b": "bed", "rule": "near", "gap": 0.12,
		"text": "Заведи ковёр под кровать", "give": "bed_carved"},
	{"id": "window_over_bed", "a": "window", "b": "bed", "rule": "over", "min_y": 1.2,
		"text": "Поставь кровать под окно", "give": "window_seal"},
	{"id": "table_at_window", "a": "table", "b": "window", "rule": "near", "gap": 0.30,
		"text": "Поставь стол у окна", "give": "window_guild"},
	{"id": "door_by_rug", "a": "door", "b": "rug", "rule": "near", "gap": 0.12,
		"text": "Постели ковёр у двери", "give": "door_guild"},
	{"id": "decor_by_rug", "a": "decor", "b": "rug", "rule": "near", "gap": 0.12,
		"text": "Поставь планетарий на ковёр", "give": "planetarium_ember"},
	{"id": "decor_by_table", "a": "decor", "b": "table", "rule": "near", "gap": 0.12,
		"text": "Поставь планетарий к столу", "give": "window_contract"},
]
