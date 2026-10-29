extends RefCounted
class_name Placement

const ROOM_HALF := 3.431
const WALL_H := 2.4
const FLOOR_INSET := 0.02
const SNAP := 0.1
const EPS := 1e-3


static func footprint(p: Dictionary) -> Rect2:
	var item := HouseItems.get_item(String(p.get("id", "")))
	if item.is_empty():
		return Rect2()
	var box: Vector3 = item["box"]
	var wall := int(p.get("wall", -1))
	if wall == 0:
		return Rect2(-ROOM_HALF, float(p.get("z", 0.0)) - box.x * 0.5, box.z, box.x)
	if wall == 1:
		return Rect2(float(p.get("x", 0.0)) - box.x * 0.5, -ROOM_HALF, box.x, box.z)
	return Rect2(float(p.get("x", 0.0)) - box.x * 0.5,
		float(p.get("z", 0.0)) - box.z * 0.5, box.x, box.z)


static func clamp_record(p: Dictionary) -> Dictionary:
	var item := HouseItems.get_item(String(p.get("id", "")))
	if item.is_empty():
		return {}
	var box: Vector3 = item["box"]
	var q := p.duplicate(true)
	if bool(item.get("wall", false)):
		var wall := int(q.get("wall", -1))
		if wall != 0 and wall != 1:
			return {}
		var half := box.x * 0.5
		var lo := -ROOM_HALF + FLOOR_INSET + half
		var hi := ROOM_HALF - FLOOR_INSET - half
		if wall == 0:
			q["x"] = -ROOM_HALF + box.z * 0.5
			q["z"] = clampf(float(q.get("z", 0.0)), lo, hi)
		else:
			q["z"] = -ROOM_HALF + box.z * 0.5
			q["x"] = clampf(float(q.get("x", 0.0)), lo, hi)
		q["y"] = clampf(float(q.get("y", box.y * 0.5)), box.y * 0.5, WALL_H - box.y * 0.5)
	else:
		q["wall"] = -1
		q["y"] = 0.0
		q["x"] = clampf(float(q.get("x", 0.0)),
			-ROOM_HALF + FLOOR_INSET + box.x * 0.5,
			ROOM_HALF - FLOOR_INSET - box.x * 0.5)
		q["z"] = clampf(float(q.get("z", 0.0)),
			-ROOM_HALF + FLOOR_INSET + box.z * 0.5,
			ROOM_HALF - FLOOR_INSET - box.z * 0.5)
	q["flip"] = bool(q.get("flip", false)) and bool(item.get("flip_ok", false))
	return q


static func snap_record(p: Dictionary) -> Dictionary:
	var q := clamp_record(p)
	if q.is_empty():
		return q
	q["x"] = snappedf(float(q["x"]), SNAP)
	q["z"] = snappedf(float(q["z"]), SNAP)
	if int(q["wall"]) >= 0:
		q["y"] = snappedf(float(q["y"]), SNAP)
	return clamp_record(q)


static func gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dz := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return maxf(dx, dz)


static func valid(p: Dictionary, others: Array, ignore_index := -1) -> bool:
	var item := HouseItems.get_item(String(p.get("id", "")))
	if item.is_empty():
		return false
	var fp := footprint(p)
	if fp.size.x <= 0.0 or fp.size.y <= 0.0:
		return false
	# Стенные предметы стоят вплотную к стене: ось прижима выходит за inset
	# по построению, поэтому проверяем только ось вдоль стены.
	var wall := int(p.get("wall", -1))
	if wall == 0:
		if fp.position.y < -ROOM_HALF + FLOOR_INSET - EPS \
				or fp.end.y > ROOM_HALF - FLOOR_INSET + EPS:
			return false
	elif wall == 1:
		if fp.position.x < -ROOM_HALF + FLOOR_INSET - EPS \
				or fp.end.x > ROOM_HALF - FLOOR_INSET + EPS:
			return false
	elif fp.position.x < -ROOM_HALF + FLOOR_INSET - EPS \
			or fp.position.y < -ROOM_HALF + FLOOR_INSET - EPS \
			or fp.end.x > ROOM_HALF - FLOOR_INSET + EPS \
			or fp.end.y > ROOM_HALF - FLOOR_INSET + EPS:
		return false
	if String(item.get("cat", "")) == "rug":
		return true
	for i in others.size():
		if i == ignore_index:
			continue
		var other: Dictionary = others[i]
		var oi := HouseItems.get_item(String(other.get("id", "")))
		if oi.is_empty() or String(oi.get("cat", "")) == "rug":
			continue
		if bool(oi.get("wall", false)) != bool(item.get("wall", false)):
			continue
		var overlap := fp.intersection(footprint(other))
		if overlap.size.x > EPS and overlap.size.y > EPS:
			return false
	return true


static func move_allowed(from: Dictionary, to: Dictionary, others: Array, index: int) -> bool:
	if valid(to, others, index):
		return true
	return _overlap_area(to, others, index) < _overlap_area(from, others, index) - EPS


static func push_out(to: Dictionary, others: Array, index: int) -> Dictionary:
	var current := to.duplicate(true)
	for _step in 4:
		if valid(current, others, index):
			return clamp_record(current)
		var fp := footprint(current)
		var moved := false
		for i in others.size():
			if i == index:
				continue
			var other: Dictionary = others[i]
			var oi := HouseItems.get_item(String(other.get("id", "")))
			if oi.is_empty() or String(oi.get("cat", "")) == "rug":
				continue
			if bool(oi.get("wall", false)) != bool(HouseItems.get_item(String(current["id"])).get("wall", false)):
				continue
			var op := footprint(other)
			var overlap := fp.intersection(op)
			if overlap.size.x <= EPS or overlap.size.y <= EPS:
				continue
			# Прижим к стене отменяет сдвиг по нормали: выталкиваем вдоль стены.
			var wall := int(current.get("wall", -1))
			if wall == 1 or (wall < 0 and overlap.size.x < overlap.size.y):
				var dir := 1.0 if fp.get_center().x >= op.get_center().x else -1.0
				current["x"] = float(current["x"]) + dir * (overlap.size.x + EPS)
			else:
				var dir_z := 1.0 if fp.get_center().y >= op.get_center().y else -1.0
				current["z"] = float(current["z"]) + dir_z * (overlap.size.y + EPS)
			current = clamp_record(current)
			moved = true
			break
		if not moved:
			break
	return clamp_record(current)


static func _overlap_area(p: Dictionary, others: Array, ignore_index: int) -> float:
	var fp := footprint(p)
	var total := 0.0
	for i in others.size():
		if i == ignore_index:
			continue
		var other: Dictionary = others[i]
		var oi := HouseItems.get_item(String(other.get("id", "")))
		if oi.is_empty() or String(oi.get("cat", "")) == "rug":
			continue
		if bool(oi.get("wall", false)) != bool(HouseItems.get_item(String(p.get("id", ""))).get("wall", false)):
			continue
		var overlap := fp.intersection(footprint(other))
		if overlap.size.x > 0.0 and overlap.size.y > 0.0:
			total += overlap.size.x * overlap.size.y
	return total
