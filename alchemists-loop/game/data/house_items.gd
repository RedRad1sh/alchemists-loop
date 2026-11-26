extends RefCounted
class_name HouseItems

## Каталог мебели собирается из папок, а не из кода. Чтобы добавить предмет,
## положи PNG в `assets/house/items/<категория>/<id>.png` и открой проект
## в редакторе (он создаст .import). Необязательно рядом:
##   <id>.reflection.png — отдельное запечённое отражение (режим advanced:
##     затемнено и дотянуто до линии пола). Без него отражение рисуется тем же
##     спрайтом, шейдер зеркалит меш сам — дубль PNG не нужен.
##   <id>.json — label, cost, reward, tint, order, refl_mode ("none" выключает
##     отражение), flip_ok, grade, wall_view, sprite (id-донор картинки для
##     вариантов-перекрасок) и метрики box/vbox/off/alpha.
## Без json метрики берутся из непрозрачной области PNG: ширина и глубина —
## по умолчанию категории, высота подбирается так, чтобы изометрическая
## проекция бокса совпала с пропорцией картинки.
const ROOT := "res://assets/house/items"
const CATS: Array = ["window", "door", "table", "rug", "bed", "decor"]
## Во столько раз исходные метрики предмета крупнее в комнате.
const ITEM_SCALE := 2.0
## Настенные предметы остаются в метриках оригинала: PlayerHouse ставит окно
## 1,0×1,07 м и дверь 1,0×1,67 м в стену 2,4 м, а удвоение превращало окно
## в две трети стены и делало дверь выше клампа `Placement.clamp_record`.
const WALL_ITEM_SCALE := 1.0
const PPM := 256.0
const WALL_CATS := ["window", "door"]
## Ширина (x) и глубина (z) бокса по умолчанию для PNG без json, в метрах
## исходного масштаба (до ITEM_SCALE). Высоту даёт пропорция картинки.
const CAT_FOOTPRINT := {
	"window": Vector2(1.0, 0.12), "door": Vector2(1.0, 0.09),
	"table": Vector2(0.6, 1.0), "rug": Vector2(0.6, 1.0),
	"bed": Vector2(1.0, 0.78), "decor": Vector2(0.46, 1.0),
}
const CAT_WALL_VIEW := {"window": 0, "door": 1}
const DEFAULT_COST := 100
const ISO_ROTATION_DEG := Vector3(-35.264, 45.0, 0.0)

static var _scaled: Dictionary = {}
static var _items: Dictionary = {}
static var _loaded := false
## Совместимость: потребители читают HouseItems.ITEMS как словарь каталога.
static var ITEMS: Dictionary:
	get:
		_ensure_loaded()
		return _items


static func reload() -> void:
	_loaded = false
	_items = {}
	_scaled = {}
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var found: Array = []
	for cat in CATS:
		var dir := "%s/%s" % [ROOT, cat]
		var names := ResourceLoader.list_directory(dir)
		for raw in names:
			var name := String(raw)
			if not name.ends_with(".png") or name.ends_with(".reflection.png"):
				continue
			found.append(_scan_item(String(cat), dir, name.get_basename()))
		for raw in names:
			var name := String(raw)
			if name.ends_with(".json") and not names.has(name.get_basename() + ".png"):
				# Вариант без собственной картинки (перекраска донора).
				found.append(_scan_item(String(cat), dir, name.get_basename()))
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("_order", 1000000))
		var ob := int(b.get("_order", 1000000))
		return oa < ob if oa != ob else String(a["id"]) < String(b["id"]))
	for item in found:
		if item.is_empty():
			continue
		item.erase("_order")
		_items[String(item["id"])] = item
	# Донор картинки задаётся по id: путь подставляем после полного скана.
	for id in _items:
		var it: Dictionary = _items[id]
		var donor := String(it.get("_donor", ""))
		it.erase("_donor")
		if donor == "":
			continue
		var src: Dictionary = _items.get(donor, {})
		if src.is_empty():
			push_error("HouseItems: %s ссылается на неизвестный спрайт %s" % [id, donor])
			continue
		it["sprite"] = src["sprite"]
		if not it.has("refl") and src.has("refl"):
			it["refl"] = src["refl"]
			if not it.has("_mode_set"):
				it["refl_mode"] = src["refl_mode"]
		for k in ["box", "vbox", "off", "alpha"]:
			if not it.has("_has_" + k):
				it[k] = src[k]
	for id in _items:
		var it: Dictionary = _items[id]
		for k in it.keys():
			if String(k).begins_with("_"):
				it.erase(k)


static func _scan_item(cat: String, dir: String, id: String) -> Dictionary:
	var meta := {}
	var json_path := "%s/%s.json" % [dir, id]
	if FileAccess.file_exists(json_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			meta = parsed
		else:
			push_error("HouseItems: битый json %s" % json_path)
	var item := {
		"id": id, "cat": cat,
		"label": String(meta.get("label", id.capitalize())),
		"cost": int(meta.get("cost", DEFAULT_COST)),
		"reward": bool(meta.get("reward", false)),
		"tint": String(meta.get("tint", "")),
		"ppm": PPM,
		"wall": WALL_CATS.has(cat),
		"wall_view": int(meta.get("wall_view", CAT_WALL_VIEW.get(cat, -1))),
		"flip_ok": bool(meta.get("flip_ok", true)),
		"_order": int(meta.get("order", 1000000)),
	}
	if meta.has("grade"):
		var gr: Array = meta["grade"]
		item["grade"] = Vector4(gr[0], gr[1], gr[2], gr[3])
	if meta.has("refl_mode"):
		item["_mode_set"] = true
	var png := "%s/%s.png" % [dir, id]
	if meta.has("sprite"):
		item["_donor"] = String(meta["sprite"])
	elif ResourceLoader.exists(png):
		item["sprite"] = png
	else:
		push_error("HouseItems: у %s нет ни PNG, ни донора sprite" % id)
		return {}
	var refl := "%s/%s.reflection.png" % [dir, id]
	var mode := String(meta.get("refl_mode", ""))
	if ResourceLoader.exists(refl):
		item["refl"] = refl
		item["refl_mode"] = mode if mode != "" else "advanced"
	elif not meta.has("sprite"):
		# Без запечённого отражения шейдер зеркалит сам спрайт.
		item["refl"] = png
		item["refl_mode"] = mode if mode != "" else "regular"
	elif mode != "":
		item["refl_mode"] = mode
	for k in ["box", "vbox", "off"]:
		if meta.has(k):
			var v: Array = meta[k]
			item[k] = Vector3(v[0], v[1], v[2])
			item["_has_" + k] = true
	if meta.has("alpha"):
		var a: Array = meta["alpha"]
		item["alpha"] = Rect2(a[0], a[1], a[2], a[3])
		item["_has_alpha"] = true
	if not meta.has("sprite") and not item.has("box"):
		_auto_metrics(item, cat)
	return item


## Метрики для PNG без json: alpha — непрозрачная область картинки, бокс —
## footprint категории, высота — та, при которой изопроекция бокса имеет ту же
## пропорцию, что alpha-прямоугольник.
static func _auto_metrics(item: Dictionary, cat: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(String(item["sprite"])))
	var tex: Texture2D = load(String(item["sprite"]))
	var used := Rect2(Vector2.ZERO, tex.get_size() if tex != null else Vector2.ONE)
	if img != null:
		used = Rect2(img.get_used_rect())
	elif tex != null and tex.get_image() != null:
		used = Rect2(tex.get_image().get_used_rect())
	if not item.has("alpha"):
		item["alpha"] = used
	var fp: Vector2 = CAT_FOOTPRINT.get(cat, Vector2(0.6, 1.0))
	var a: Rect2 = item["alpha"]
	var aspect := a.size.y / maxf(a.size.x, 1.0)
	var h := _height_for_aspect(fp.x, fp.y, aspect)
	item["box"] = Vector3(fp.x, h, fp.y)
	item["vbox"] = Vector3(fp.x * 0.995, h, fp.y * 0.995)
	item["off"] = Vector3.ZERO


static func _height_for_aspect(x: float, z: float, aspect: float) -> float:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(ISO_ROTATION_DEG.x), deg_to_rad(ISO_ROTATION_DEG.y), 0.0))
	var lo := 0.001
	var hi := 10.0
	for _i in 48:
		var mid := (lo + hi) * 0.5
		var r := _iso_size(Vector3(x, mid, z), basis)
		if r.y / maxf(r.x, 0.0001) < aspect:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func _iso_size(box: Vector3, basis: Basis) -> Vector2:
	var lo := Vector2(1e30, 1e30)
	var hi := Vector2(-1e30, -1e30)
	for sx in [-0.5, 0.5]:
		for sy in [0.0, 1.0]:
			for sz in [-0.5, 0.5]:
				var p := Vector3(box.x * sx, box.y * sy, box.z * sz)
				var s := Vector2(p.dot(basis.x), p.dot(basis.y))
				lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
				hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
	return hi - lo


static func get_item(id: String) -> Dictionary:
	if not _scaled.has(id):
		var src: Dictionary = ITEMS.get(id, {})
		if src.is_empty():
			return {}
		_scaled[id] = _apply_scale(src)
	return _scaled[id]


## Метрики каталога остаются в исходном масштабе .asset, а в комнату предмет попадает
## увеличенным: на 7-метровом полу оригинальные 0,5×1 м выглядят игрушечными.
## Множитель стоит на путях `get_item()`, потому что из `box` растут и спрайт
## (`_build_projected_box_mesh`), и площадь расстановки (`Placement.footprint`) —
## увеличить только картинку значит начать ставить мебель сквозь себя.
static func _apply_scale(src: Dictionary) -> Dictionary:
	var box: Vector3 = src["box"]
	var factor := ITEM_SCALE
	if bool(src.get("wall", false)):
		factor = WALL_ITEM_SCALE
	var out := src.duplicate(true)
	out["box"] = box * factor
	out["vbox"] = (src["vbox"] as Vector3) * factor
	out["off"] = (src["off"] as Vector3) * factor
	return out


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func items_in_cat(cat: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if String(ITEMS[id]["cat"]) == cat:
			out.append(ITEMS[id])
	return out


static func price(id: String) -> int:
	var item := get_item(id)
	return int(item.get("cost", 0)) if not item.is_empty() else 0


## Первый покупаемый вариант категории — именно он выдаётся бесплатно вместе с
## домиком. Раньше роль играл id, совпадающий с именем категории, но теперь
## категория «decor» такого id не имеет.
static func base_item(cat: String) -> String:
	for id in ITEMS:
		var item: Dictionary = ITEMS[id]
		if String(item["cat"]) == cat and not bool(item.get("reward", false)):
			return String(id)
	return ""
