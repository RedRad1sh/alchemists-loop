extends RefCounted
class_name BalanceProfile

var _data: Dictionary = {}
var _meta: Dictionary = {}


func _init(data: Dictionary = {}, meta: Dictionary = {}) -> void:
	_data = data.duplicate(true)
	_meta = meta.duplicate(true)


func get_value(path: String, fallback = null):
	if path.is_empty():
		return _dup(fallback)
	var cur: Variant = _data
	for part in path.split("."):
		if cur is Dictionary:
			var d: Dictionary = cur
			if d.has(part):
				cur = d[part]
			elif part.is_valid_int() and d.has(int(part)):
				cur = d[int(part)]
			else:
				return _dup(fallback)
		elif cur is Array:
			var a: Array = cur
			if not part.is_valid_int():
				return _dup(fallback)
			var idx: int = int(part)
			if idx < 0 or idx >= a.size():
				return _dup(fallback)
			cur = a[idx]
		else:
			return _dup(fallback)
	return _dup(cur)


func section(name: String) -> Dictionary:
	if _data.has(name) and _data[name] is Dictionary:
		return (_data[name] as Dictionary).duplicate(true)
	return {}


func metadata() -> Dictionary:
	return _meta.duplicate(true)


func raw_data() -> Dictionary:
	return _data.duplicate(true)


static func _dup(v: Variant):
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v
