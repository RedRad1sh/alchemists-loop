extends RefCounted
class_name SpringBalance
# Compatibility facade: single source of balance tables is BalanceConfig.

const VERSION: int = BalanceConfig.BASELINE_DATA["spring"]["version"]
const SPEED: Array = BalanceConfig.BASELINE_DATA["spring"]["speed"]
const VOLUME: Array = BalanceConfig.BASELINE_DATA["spring"]["volume"]
const VOLUME_CAP: Array = BalanceConfig.BASELINE_DATA["spring"]["volume_cap"]
const SOURCES: Array = BalanceConfig.BASELINE_DATA["spring"]["sources"]
const OFFLINE: Array = BalanceConfig.BASELINE_DATA["spring"]["offline"]
const OFFLINE_WINDOW_SEC: Array = BalanceConfig.BASELINE_DATA["spring"]["offline_window_sec"]
const MIN_INTERVAL: float = BalanceConfig.BASELINE_DATA["spring"]["min_interval"]
const SPEED_FACTOR: float = BalanceConfig.BASELINE_DATA["spring"]["speed_factor"]
const PRESTIGE_KEEP_LEVEL: int = BalanceConfig.BASELINE_DATA["prestige"]["spring_keep_level"]
const MATERIAL_TIER: Dictionary = BalanceConfig.BASELINE_DATA["spring"]["material_tier"]


static func axis_table(profile: BalanceProfile, axis: String) -> Array:
	var p: BalanceProfile = profile if profile != null else BalanceConfig.baseline()
	match axis:
		"speed": return p.get_value("spring.speed", []) as Array
		"volume": return p.get_value("spring.volume", []) as Array
		"sources": return p.get_value("spring.sources", []) as Array
		"offline": return p.get_value("spring.offline", []) as Array
		_: return []


static func volume_cap(profile: BalanceProfile) -> Array:
	var p: BalanceProfile = profile if profile != null else BalanceConfig.baseline()
	return p.get_value("spring.volume_cap", []) as Array


static func offline_windows(profile: BalanceProfile) -> Array:
	var p: BalanceProfile = profile if profile != null else BalanceConfig.baseline()
	return p.get_value("spring.offline_window_sec", []) as Array
