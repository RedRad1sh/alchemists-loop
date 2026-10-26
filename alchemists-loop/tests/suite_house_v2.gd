extends RefCounted
class_name SuiteHouseV2


static func run(g: Game) -> void:
	_catalog()
	# дальше задачи добавляют свои секции


static func _catalog() -> void:
	Selftest.check("hv2 catalog has 24 items", HouseItems.ITEMS.size() == 24)
	var per_cat := {}
	var base_total := 0
	var ids_ok := true
	var fields_ok := true
	var costs_ok := true
	var walls_ok := true
	for raw_id in HouseItems.ITEMS:
		var id := String(raw_id)
		var it: Dictionary = HouseItems.ITEMS[raw_id]
		ids_ok = ids_ok and String(it.get("id", "")) == id
		var box: Vector3 = it.get("box", Vector3.ZERO)
		fields_ok = fields_ok and box.x > 0.0 and box.y > 0.0 and box.z > 0.0 \
			and float(it.get("ppm", 0.0)) > 0.0 \
			and String(it.get("sprite", "")).begins_with("res://assets/house/items/") \
			and HouseItems.CATS.has(String(it.get("cat", "")))
		var is_reward := bool(it.get("reward", false))
		costs_ok = costs_ok and (int(it.get("cost", -1)) == 0 if is_reward else int(it.get("cost", 0)) > 0)
		var cat := String(it.get("cat", ""))
		var want_wall := cat in ["window", "shelf", "fireplace"]
		walls_ok = walls_ok and bool(it.get("wall", false)) == want_wall
		if not is_reward:
			per_cat[cat] = int(per_cat.get(cat, 0)) + 1
			base_total += 1
	Selftest.check("hv2 catalog ids match keys", ids_ok)
	Selftest.check("hv2 catalog has 9 categories with 2 base variants each",
		per_cat.size() == 9 and base_total == 18 and not per_cat.values().has(1) and per_cat.values().max() == 2
		and per_cat.values().min() == 2)
	Selftest.check("hv2 every item has positive box/ppm/path and known category", fields_ok)
	Selftest.check("hv2 rewards are free, everything else costs ether", costs_ok)
	Selftest.check("hv2 wall flag matches category", walls_ok)
	var rewards := ["window_contract", "window_seal", "window_guild",
		"fireplace_ember", "fireplace_log", "fireplace_heart"]
	var rewards_ok := true
	for rid in rewards:
		var it := HouseItems.get_item(String(rid))
		rewards_ok = rewards_ok and not it.is_empty() and bool(it.get("reward", false)) \
			and String(it.get("tint", "")) != ""
	Selftest.check("hv2 six contract/circle reward ids exist and are tinted", rewards_ok)
	for rid in ContractsBalance.DECOR:
		Selftest.check("hv2 contract decor id exists: " + String(rid), HouseItems.exists(String(rid)))
	for rid in Game.CIRCLE_DECOR_REWARDS.values():
		Selftest.check("hv2 circle decor id exists: " + String(rid), HouseItems.exists(String(rid)))
