extends RefCounted
class_name HouseLayout

const MAX_ITEMS := 40

var unlocked: Array[String] = []
var placements: Array[Dictionary] = []


func has(id: String) -> bool:
	return unlocked.has(id)


func unlock(id: String) -> bool:
	if not HouseItems.exists(id) or unlocked.has(id):
		return false
	unlocked.append(id)
	return true


func add_placement(p: Dictionary) -> bool:
	if placements.size() >= MAX_ITEMS:
		return false
	var clean := _clean(p)
	if clean.is_empty():
		return false
	placements.append(clean)
	return true


func remove_at(i: int) -> bool:
	if i < 0 or i >= placements.size():
		return false
	placements.remove_at(i)
	return true


func move_at(i: int, p: Dictionary) -> bool:
	if i < 0 or i >= placements.size():
		return false
	var clean := _clean(p)
	if clean.is_empty() or not Placement.valid(clean, placements, i):
		return false
	placements[i] = clean
	return true


func to_dict() -> Dictionary:
	return {"unlocked": unlocked.duplicate(), "placements": placements.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	unlocked.clear()
	placements.clear()
	var raw_unlocked = data.get("unlocked", [])
	if raw_unlocked is Array:
		for raw in raw_unlocked:
			unlock(str(raw))
	var raw_placements = data.get("placements", [])
	if raw_placements is Array:
		for raw in raw_placements:
			if placements.size() >= MAX_ITEMS:
				break
			if not (raw is Dictionary):
				continue
			var clean := _clean(raw)
			if not clean.is_empty():
				placements.append(clean)


func _clean(raw: Dictionary) -> Dictionary:
	# str(), а не String(): в 4.7.2 у String нет конструктора из числа, и
	# String(42) из гостевого JSON падает рантайм-ошибкой.
	var id := str(raw.get("id", ""))
	if not HouseItems.exists(id):
		return {}
	# Координаты обязаны быть числами: float("oops") молча даёт 0.0 и
	# превращает мусор из гостевого JSON в валидную расстановку.
	for key in ["x", "z", "y"]:
		var v = raw.get(key, null)
		if not (v is float or v is int):
			return {}
	var x := float(raw["x"])
	var z := float(raw["z"])
	var y := float(raw["y"])
	if not (is_finite(x) and is_finite(z) and is_finite(y)):
		return {}
	var p := {"id": id, "x": x, "z": z, "y": y,
		"flip": bool(raw.get("flip", false)), "wall": int(raw.get("wall", -1))}
	return Placement.clamp_record(p)


static func default_placements() -> Array[Dictionary]:
	# Composition из девяти предметов, закрывающих все шесть категорий каталога.
	# Напольные метрики удвоены (`HouseItems.ITEM_SCALE`): стол занимает 1,0×2,0 м,
	# кровать 2,0×1,6 м, поэтому компактная исходная раскладка начала бы
	# пересекаться. Настенные координаты только намечены — `clamp_record` прижимает
	# их к своей стене по фактической глубине предмета.
	var out: Array[Dictionary] = []
	var raw := [
		["bed", 2.2, -2.3, 0.0, -1],
		["window", -3.284, -1.4, 1.2, 0],
		["window_alt", -3.336, 0.9, 1.0, 0],
		["door", 0.0, -3.371, 1.15, 1],
		["rug", 2.2, -2.2, 0.0, -1],
		["table", -1.8, 1.8, 0.0, -1],
		["table_herbs", 1.9, 1.9, 0.0, -1],
		["rug_alt", -0.4, -0.6, 0.0, -1],
		["planetarium", -2.3, -1.9, 0.0, -1],
	]
	for r in raw:
		out.append(Placement.clamp_record({
			"id": String(r[0]), "x": float(r[1]), "z": float(r[2]),
			"y": float(r[3]), "flip": false, "wall": int(r[4]),
		}))
	return out


static func parse(data: Dictionary) -> HouseLayout:
	var model := HouseLayout.new()
	model.from_dict(data)
	return model
