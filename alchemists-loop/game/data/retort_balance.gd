extends RefCounted
class_name RetortBalance

const MATERIALS := ["stone", "clay", "brick", "metal", "glass", "obsidian", "crystal", "gold", "tool"]
const ELEMENT_BY_CATEGORY := {"огонь": "fire", "вода": "water", "воздух": "air", "земля": "earth"}
const ELEMENT_BY_SUB := {"light": "fire", "fulgurite": "fire", "wine": "fire",
	"stream": "water", "fruit": "water", "dye": "air"}
const QUEUE_DEPTH := [1, 2, 3, 4, 6, 8]
const OFFLINE_WINDOW_SEC := [28800.0, 43200.0, 86400.0, 129600.0, 172800.0, 259200.0] # 8/12/24/36/48/72 ч
const SPEED_FACTOR := [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
const COMPLEXITY_MAX_TIER := [1, 2, 3, 4, 4] # L5 дополнительно открывает купаж
# Цены: индекс = текущий уровень (0-based), покупка ведёт на уровень+1. Модель SpringBalance.
const QUEUE := [
	{"essences": {"fire-0": 3, "water-0": 3}},
	{"essences": {"earth-1": 3, "air-1": 3}},
	{"essences": {"fire-2": 2, "water-2": 2, "earth-2": 2}},
	{"essences": {"air-3": 3, "fire-3": 3}},
	{"essences": {"blend-fire": 2, "blend-water": 2}},
]
const OFFLINE := [
	{"essences": {"water-0": 4, "earth-0": 4}},
	{"essences": {"air-1": 4, "fire-1": 4}},
	{"essences": {"water-2": 3, "earth-2": 3}},
	{"essences": {"air-3": 3, "water-3": 3}},
	{"essences": {"blend-earth": 2, "blend-air": 2}},
]
const SLOTS := [
	{"essences": {"earth-0": 5, "fire-0": 5}},
	{"essences": {"water-1": 5, "air-1": 5}},
	{"essences": {"earth-3": 4, "fire-3": 4}},
]
const SPEED := [
	{"essences": {"fire-1": 4, "air-0": 4}},
	{"essences": {"water-2": 4, "earth-1": 4}},
	{"essences": {"fire-3": 3, "air-3": 3}},
	{"essences": {"water-4": 3, "earth-4": 3}},
	{"essences": {"blend-fire": 2, "blend-air": 2}},
]
const COMPLEXITY := [
	{"essences": {"earth-1": 4, "water-1": 4}},
	{"essences": {"fire-2": 4, "air-2": 4}},
	{"essences": {"earth-3": 3, "water-3": 3}},
	{"essences": {"fire-4": 3, "air-4": 3}},
	{"essences": {"earth-4": 3, "water-4": 3}},
]
const BLEND := [
	{"essences": {"fire-4": 2, "water-4": 2, "earth-4": 2, "air-4": 2}, "req": {"complexity": 5}},
	{"essences": {"blend-fire": 1, "blend-water": 1, "blend-earth": 1, "blend-air": 1}},
]
# sink капа: +cap за уровень, цена типизированными эссенциями
const CAP := [
	{"cap": 30, "essences": {"earth-2": 3, "water-2": 3}},
	{"cap": 40, "essences": {"fire-3": 3, "air-3": 3}},
	{"cap": 50, "essences": {"earth-3": 3, "water-3": 3}},
	{"cap": 60, "essences": {"fire-4": 3, "air-4": 3}},
	{"cap": 80, "essences": {"blend-earth": 2, "blend-fire": 2}},
]
# sink мастерской: +1 линия на тирах 1 и 3, +скорость/автономность на 2
const EQUIP := [
	{"lines": 1, "essences": {"fire-3": 3, "water-3": 3, "earth-3": 3}},
	{"speed": 0.85, "essences": {"air-4": 3, "fire-4": 3, "water-4": 3}},
	{"lines": 1, "essences": {"blend-fire": 2, "blend-water": 2, "blend-earth": 2, "blend-air": 2}},
]
# купаж: одноэлементная пара (tier3 + tier4) → blend-<element>
const BLEND_RECIPES := {"fire": ["fire-3", "fire-4"], "water": ["water-3", "water-4"],
	"earth": ["earth-3", "earth-4"], "air": ["air-3", "air-4"]}

static func element_of(sub: String) -> String:
	if ELEMENT_BY_SUB.has(sub):
		return String(ELEMENT_BY_SUB[sub])
	var cat := String(Modes.CATEGORY_OF.get(sub, ""))
	return String(ELEMENT_BY_CATEGORY.get(cat, "earth"))

static func is_material(sub: String) -> bool:
	return MATERIALS.has(sub)
