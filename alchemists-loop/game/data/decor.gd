extends RefCounted
class_name DecorData
# Дом и декор: темы, ауры, цены, каталог, палитра (бывшие const из main.gd, оп D).

const WORKSHOP_THEMES := [
	{"id": "cobalt", "label": "Кобальт", "cost": 0},
	{"id": "ember", "label": "Угли", "cost": 120},
	{"id": "moss", "label": "Мох", "cost": 120},
	{"id": "violet", "label": "Аметист", "cost": 120},
]

const WORKSHOP_AURAS := [
	{"id": "amber", "label": "Янтарь", "cost": 0},
	{"id": "rose", "label": "Роза", "cost": 150},
	{"id": "aqua", "label": "Аква", "cost": 150},
	{"id": "violet", "label": "Фиалка", "cost": 150},
	{"id": "hearth", "label": "Очаг", "cost": 0},
]

const HOUSE_COST := 400  # домик для Светика
# кастомные цвета: разовая разблокировка цели (п.7). Аура Светика — дороже всех.
const CUSTOM_COSTS := {"theme": 600, "aura": 1200, "wall": 500, "floor": 500}

const ROOM_DIR := "res://assets/house/room/"
# Материалы покупаются один раз (ключ `mat_<id>` в custom_unlocked), первый — бесплатный.
const FLOOR_MATS := [
	{"id": "planks", "label": "Доски", "cost": 0, "tex": ROOM_DIR + "floor_planks.png"},
	{"id": "wood", "label": "Паркет", "cost": 300, "tex": ROOM_DIR + "floor_wood.png"},
	{"id": "stone", "label": "Камень", "cost": 300, "tex": ROOM_DIR + "floor_stone.png"},
]
const WALL_MATS := [
	{"id": "timber", "label": "Глина", "cost": 0, "left": "", "right": ""},
	{"id": "plaster", "label": "Известь", "cost": 300,
		"left": ROOM_DIR + "wall_plaster_left.jpg", "right": ROOM_DIR + "wall_plaster_right.jpg"},
]

static func floor_mat(id: String) -> Dictionary:
	for m in FLOOR_MATS:
		if String(m["id"]) == id:
			return m
	return FLOOR_MATS[0]


static func wall_mat(id: String) -> Dictionary:
	for m in WALL_MATS:
		if String(m["id"]) == id:
			return m
	return WALL_MATS[0]


const COLOR_SWATCHES := [
	"#0d1219", "#1a0e0e", "#0e1410", "#120f1a", "#3a4a6b", "#5a4636",
	"#7a4a3a", "#8a4a55", "#4d7ab7", "#5d9a6b", "#c9a24d", "#b78aff",
]
