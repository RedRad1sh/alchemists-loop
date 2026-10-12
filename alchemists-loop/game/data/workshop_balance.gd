extends RefCounted
class_name WorkshopBalance

const VERSION := 1
const INVALID_DEPTH := 1 << 29
const MAX_XP := 2147483647
const RANKS := [
	{"name": "Подмастерье", "xp": 0, "lines": 1, "capacity": 1, "ether": 0, "materials": {}},
	{"name": "Мастер", "xp": 100, "lines": 2, "capacity": 2, "ether": 120, "materials": {"brick": 20, "metal": 10}},
	{"name": "Инженер", "xp": 400, "lines": 3, "capacity": 3, "ether": 240, "materials": {"glass": 25, "tool": 10}},
	{"name": "Архитектор", "xp": 1000, "lines": 4, "capacity": 4, "ether": 480, "materials": {"crystal": 20, "gold": 10}},
]
const AUTONOMY := [
	{"rank": 0, "stages": 60, "ether": 0, "materials": {}},
	{"rank": 1, "stages": 120, "ether": 150, "materials": {"glass": 15, "metal": 10}},
	{"rank": 2, "stages": 240, "ether": 300, "materials": {"tool": 15, "crystal": 10}},
]
const STATUSES := ["idle", "running", "paused_user", "waiting_ether", "waiting_ingredients", "waiting_recipe", "waiting_inventory"]
