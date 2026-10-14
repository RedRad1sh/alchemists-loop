extends RefCounted
class_name SpringSprite

static func form_stage(levels: Dictionary) -> int:
	var total: int = 0
	for axis in levels:
		total += int(levels.get(axis, 0))
	return clampi(floori(total / 4.0), 0, 5)

static func material_tier(levels: Dictionary) -> int:
	var max_tier: int = 0
	for i in mini(int(levels.get("speed", 0)), SpringBalance.SPEED.size()):
		for mat in SpringBalance.SPEED[i]["materials"]:
			max_tier = maxi(max_tier, SpringBalance.MATERIAL_TIER.get(mat, 0))
	for i in mini(int(levels.get("volume", 0)), SpringBalance.VOLUME.size()):
		for mat in SpringBalance.VOLUME[i]["materials"]:
			max_tier = maxi(max_tier, SpringBalance.MATERIAL_TIER.get(mat, 0))
	for i in mini(int(levels.get("sources", 0)), SpringBalance.SOURCES.size()):
		for mat in SpringBalance.SOURCES[i]["materials"]:
			max_tier = maxi(max_tier, SpringBalance.MATERIAL_TIER.get(mat, 0))
	for i in mini(int(levels.get("offline", 0)), SpringBalance.OFFLINE.size()):
		for mat in SpringBalance.OFFLINE[i]["materials"]:
			max_tier = maxi(max_tier, SpringBalance.MATERIAL_TIER.get(mat, 0))
	return max_tier
