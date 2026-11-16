extends RefCounted
class_name WorkshopBalance
# Compatibility facade: single source of balance tables is BalanceConfig.

const VERSION: int = BalanceConfig.BASELINE_DATA["workshop"]["version"]
const INVALID_DEPTH: int = BalanceConfig.BASELINE_DATA["workshop"]["invalid_depth"]
const MAX_XP: int = BalanceConfig.BASELINE_DATA["workshop"]["max_xp"]
const RANKS: Array = BalanceConfig.BASELINE_DATA["workshop"]["ranks"]
const AUTONOMY: Array = BalanceConfig.BASELINE_DATA["workshop"]["autonomy"]
const STATUSES: Array = BalanceConfig.BASELINE_DATA["workshop"]["statuses"]


static func ranks(profile: BalanceProfile) -> Array:
	var p: BalanceProfile = profile if profile != null else BalanceConfig.baseline()
	return p.get_value("workshop.ranks", []) as Array


static func autonomy(profile: BalanceProfile) -> Array:
	var p: BalanceProfile = profile if profile != null else BalanceConfig.baseline()
	return p.get_value("workshop.autonomy", []) as Array
