extends RefCounted
class_name RetortBalance
# Compatibility facade: single source of balance tables is BalanceConfig.

const MATERIALS: Array = BalanceConfig.BASELINE_DATA["retort"]["materials"]
const ELEMENT_BY_CATEGORY: Dictionary = BalanceConfig.BASELINE_DATA["retort"]["element_by_category"]
const ELEMENT_BY_SUB: Dictionary = BalanceConfig.BASELINE_DATA["retort"]["element_by_sub"]
const QUEUE_DEPTH: Array = BalanceConfig.BASELINE_DATA["retort"]["queue_depth"]
const OFFLINE_WINDOW_SEC: Array = BalanceConfig.BASELINE_DATA["retort"]["offline_window_sec"]
const SPEED_FACTOR: Array = BalanceConfig.BASELINE_DATA["retort"]["speed_factor"]
const COMPLEXITY_MAX_TIER: Array = BalanceConfig.BASELINE_DATA["retort"]["complexity_max_tier"]
const QUEUE: Array = BalanceConfig.BASELINE_DATA["retort"]["queue"]
const OFFLINE: Array = BalanceConfig.BASELINE_DATA["retort"]["offline"]
const SLOTS: Array = BalanceConfig.BASELINE_DATA["retort"]["slots"]
const SPEED: Array = BalanceConfig.BASELINE_DATA["retort"]["speed"]
const COMPLEXITY: Array = BalanceConfig.BASELINE_DATA["retort"]["complexity"]
const BLEND: Array = BalanceConfig.BASELINE_DATA["essences"]["blend"]
const CAP: Array = BalanceConfig.BASELINE_DATA["essences"]["cap"]
const EQUIP: Array = BalanceConfig.BASELINE_DATA["essences"]["equip"]
const BLEND_RECIPES: Dictionary = BalanceConfig.BASELINE_DATA["essences"]["blend_recipes"]


static func axis_table(profile: BalanceProfile, axis: String) -> Array:
	var p: BalanceProfile = profile if profile != null else BalanceConfig.baseline()
	match axis:
		"queue": return p.get_value("retort.queue", []) as Array
		"offline": return p.get_value("retort.offline", []) as Array
		"slots": return p.get_value("retort.slots", []) as Array
		"speed": return p.get_value("retort.speed", []) as Array
		"complexity": return p.get_value("retort.complexity", []) as Array
		"blend": return p.get_value("essences.blend", []) as Array
		"cap": return p.get_value("essences.cap", []) as Array
		"equip": return p.get_value("essences.equip", []) as Array
		_: return []


static func element_of(sub: String) -> String:
	if ELEMENT_BY_SUB.has(sub):
		return String(ELEMENT_BY_SUB[sub])
	var cat := String(Modes.CATEGORY_OF.get(sub, ""))
	return String(ELEMENT_BY_CATEGORY.get(cat, "earth"))


static func is_material(sub: String) -> bool:
	return MATERIALS.has(sub)
