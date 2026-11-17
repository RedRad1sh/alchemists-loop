extends RefCounted
class_name RetortSprite

const STAGE_TOTAL := 4.0
const TIER_ASSET := ["steel", "obsidian", "crystal", "gold"]

static func _total(levels: Dictionary) -> int:
	var t := 0
	for k in levels:
		t += int(levels[k])
	return t

static func form_stage(levels: Dictionary) -> int:
	return clampi(floori(_total(levels) / STAGE_TOTAL), 0, 5)

static func material_tier(levels: Dictionary) -> int:
	var deep := int(levels.get("complexity", 0)) + int(levels.get("blend", 0))
	return clampi(floori(deep / 2.0), 0, TIER_ASSET.size() - 1)

static func texture_stem(levels: Dictionary) -> String:
	return "res://assets/retort/retort_l%d_%s" % [form_stage(levels) + 1, TIER_ASSET[material_tier(levels)]]
