extends RefCounted
class_name HouseItems

# Только те предметы, у которых в PlayerHouse есть нарисованный ассет: метрики
# box/vbox/off/alpha взяты из .asset файлов один в один. Категорий без исходного
# арта в магазине нет — заглушек в каталоге больше не держим.
const CATS: Array = ["window", "door", "table", "rug", "bed", "decor"]
## Во столько раз исходные метрики предмета крупнее в комнате.
const ITEM_SCALE := 2.0
## Настенные предметы остаются в метриках оригинала: PlayerHouse ставит окно
## 1,0×1,07 м и дверь 1,0×1,67 м в стену 2,4 м, а удвоение превращало окно
## в две трети стены и делало дверь выше клампа `Placement.clamp_record`.
const WALL_ITEM_SCALE := 1.0

static var _scaled: Dictionary = {}
const ITEMS := {
	"window": {"id": "window", "label": "Классическое окно", "cat": "window", "cost": 70, "sprite": "res://assets/house/items/common_window_sprite.png", "box": Vector3(1.000000, 1.074396, 0.146734), "vbox": Vector3(0.995000, 0.991469, 0.146000), "off": Vector3(0.014299, -0.028598, 0.014299), "alpha": Rect2(3.0, 3.0, 415.0, 656.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_window_reflection.png", "ppm": 256.0, "wall": true, "wall_view": 0, "flip_ok": true, "reward": false, "tint": ""},
	"window_alt": {"id": "window_alt", "label": "Окно с гардой", "cat": "window", "cost": 110, "sprite": "res://assets/house/items/common_window_sprite2.png", "box": Vector3(1.000000, 0.903140, 0.094394), "vbox": Vector3(0.995000, 0.886931, 0.093922), "off": Vector3(0.014299, -0.028598, 0.014299), "alpha": Rect2(3.0, 3.0, 392.0, 595.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_window_reflection2.png", "ppm": 256.0, "wall": true, "wall_view": 0, "flip_ok": true, "reward": false, "tint": ""},
	"door": {"id": "door", "label": "Дубовая дверь", "cat": "door", "cost": 150, "sprite": "res://assets/house/items/common_door_01_sprite.png", "box": Vector3(1.000000, 1.671154, 0.087241), "vbox": Vector3(0.995000, 1.653594, 0.086804), "off": Vector3(0.003380, -0.006760, 0.003380), "alpha": Rect2(3.0, 3.0, 295.0, 691.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_door_01_reflection.png", "ppm": 256.0, "wall": true, "wall_view": 1, "flip_ok": true, "reward": false, "tint": ""},
	"table": {"id": "table", "label": "Старый стол оружейника", "cat": "table", "cost": 120, "sprite": "res://assets/house/items/table_gunmaker_sprite.png", "box": Vector3(0.500000, 0.447960, 1.000000), "vbox": Vector3(0.497500, 0.362570, 0.995000), "off": Vector3(0.014857, -0.029713, 0.014857), "alpha": Rect2(3.0, 3.0, 401.0, 344.0), "refl_mode": "regular", "refl": "res://assets/house/items/table_gunmaker_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"table_herbs": {"id": "table_herbs", "label": "Стол с травами", "cat": "table", "cost": 160, "sprite": "res://assets/house/items/table_herbs_sprite.png", "box": Vector3(0.735330, 0.775413, 1.000000), "vbox": Vector3(0.731654, 0.639557, 0.995000), "off": Vector3(0.023366, -0.046732, 0.023366), "alpha": Rect2(3.0, 3.0, 396.0, 398.0), "refl_mode": "regular", "refl": "res://assets/house/items/table_herbs_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"table_merchant": {"id": "table_merchant", "label": "Прилавок торговца", "cat": "table", "cost": 210, "sprite": "res://assets/house/items/table_merchant_sprite.png", "box": Vector3(0.505882, 0.444434, 1.000000), "vbox": Vector3(0.503353, 0.401726, 0.995000), "off": Vector3(0.007745, -0.015491, 0.007745), "alpha": Rect2(3.0, 3.0, 398.0, 353.0), "refl_mode": "regular", "refl": "res://assets/house/items/table_merchant_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"table_alt": {"id": "table_alt", "label": "Рабочий стол алхимика", "cat": "table", "cost": 190, "sprite": "res://assets/house/items/alchemy_table_sprite.png", "box": Vector3(0.624204, 0.645245, 1.000000), "vbox": Vector3(0.621083, 0.511458, 0.995000), "off": Vector3(0.022975, -0.045950, 0.022975), "alpha": Rect2(3.0, 3.0, 402.0, 379.0), "refl_mode": "regular", "refl": "res://assets/house/items/alchemy_table_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug": {"id": "rug", "label": "Тканый ковёр", "cat": "rug", "cost": 80, "sprite": "res://assets/house/items/rug_01_sprite.png", "box": Vector3(0.659091, 0.059043, 1.000000), "vbox": Vector3(0.655795, 0.045142, 0.995000), "off": Vector3(0.003008, -0.006016, 0.003008), "alpha": Rect2(2.0, 2.0, 964.0, 587.0), "refl_mode": "regular", "refl": "res://assets/house/items/rug_01_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_alt": {"id": "rug_alt", "label": "Круглый ковёр", "cat": "rug", "cost": 130, "sprite": "res://assets/house/items/rug_02_sprite.png", "box": Vector3(0.724747, 0.047200, 1.000000), "vbox": Vector3(0.721124, 0.025473, 0.995000), "off": Vector3(0.004340, -0.008680, 0.004340), "alpha": Rect2(4.0, 4.0, 979.0, 582.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_step": {"id": "rug_step", "label": "Придорожный коврик", "cat": "rug", "cost": 55, "sprite": "res://assets/house/items/rug_var_sprite2.png", "box": Vector3(0.601562, 0.032313, 1.000000), "vbox": Vector3(0.598555, 0.009950, 0.995000), "off": Vector3(0.004394, -0.008789, 0.004394), "alpha": Rect2(18.0, 12.0, 376.0, 214.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_braided": {"id": "rug_braided", "label": "Плетёный ковёр", "cat": "rug", "cost": 70, "sprite": "res://assets/house/items/rug_var_sprite3.png", "box": Vector3(0.591615, 0.029337, 1.000000), "vbox": Vector3(0.588657, 0.009950, 0.995000), "off": Vector3(0.003894, -0.007789, 0.003894), "alpha": Rect2(16.0, 12.0, 381.0, 217.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_field": {"id": "rug_field", "label": "Полевой ковёр", "cat": "rug", "cost": 85, "sprite": "res://assets/house/items/rug_var_sprite4.png", "box": Vector3(0.600000, 0.031941, 1.000000), "vbox": Vector3(0.597000, 0.009950, 0.995000), "off": Vector3(0.004332, -0.008664, 0.004332), "alpha": Rect2(16.0, 12.0, 381.0, 219.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_ash": {"id": "rug_ash", "label": "Пепельный ковёр", "cat": "rug", "cost": 95, "sprite": "res://assets/house/items/rug_var_sprite5.png", "box": Vector3(0.603774, 0.033428, 1.000000), "vbox": Vector3(0.600755, 0.009950, 0.995000), "off": Vector3(0.004581, -0.009163, 0.004581), "alpha": Rect2(14.0, 12.0, 385.0, 222.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_moss": {"id": "rug_moss", "label": "Мховый ковёр", "cat": "rug", "cost": 105, "sprite": "res://assets/house/items/rug_var_sprite6.png", "box": Vector3(0.591615, 0.029709, 1.000000), "vbox": Vector3(0.588657, 0.009950, 0.995000), "off": Vector3(0.003956, -0.007913, 0.003956), "alpha": Rect2(14.0, 12.0, 384.0, 223.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_dusk": {"id": "rug_dusk", "label": "Вечерний ковёр", "cat": "rug", "cost": 115, "sprite": "res://assets/house/items/rug_var_sprite7.png", "box": Vector3(0.600000, 0.031569, 1.000000), "vbox": Vector3(0.597000, 0.009950, 0.995000), "off": Vector3(0.004270, -0.008540, 0.004270), "alpha": Rect2(15.0, 12.0, 383.0, 221.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_ember": {"id": "rug_ember", "label": "Угольный ковёр", "cat": "rug", "cost": 125, "sprite": "res://assets/house/items/rug_var_sprite8.png", "box": Vector3(0.602504, 0.035280, 1.000000), "vbox": Vector3(0.599491, 0.009950, 0.995000), "off": Vector3(0.004889, -0.009779, 0.004889), "alpha": Rect2(13.0, 12.0, 386.0, 222.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_tide": {"id": "rug_tide", "label": "Приливный ковёр", "cat": "rug", "cost": 140, "sprite": "res://assets/house/items/rug_var_sprite9.png", "box": Vector3(0.608150, 0.041205, 1.000000), "vbox": Vector3(0.605110, 0.009950, 0.995000), "off": Vector3(0.005879, -0.011759, 0.005879), "alpha": Rect2(13.0, 13.0, 386.0, 218.0), "refl_mode": "none", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"bed": {"id": "bed", "label": "Кровать", "cat": "bed", "cost": 250, "sprite": "res://assets/house/items/bed_test_fixed_sprite.png", "box": Vector3(1.000000, 0.597537, 0.780870), "vbox": Vector3(0.995000, 0.564139, 0.776965), "off": Vector3(0.006308, -0.012617, 0.006308), "alpha": Rect2(1.0, 1.0, 1381.0, 1305.0), "refl_mode": "advanced", "refl": "res://assets/house/items/bed_test_fixed_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"planetarium": {"id": "planetarium", "label": "Планетарий", "cat": "decor", "cost": 320, "sprite": "res://assets/house/items/planetarium_01_sprite.png", "box": Vector3(0.455909, 0.574459, 1.000000), "vbox": Vector3(0.453630, 0.562685, 0.995000), "off": Vector3(0.002569, -0.005138, 0.002569), "alpha": Rect2(5.0, 5.0, 812.0, 833.0), "refl_mode": "regular", "refl": "res://assets/house/items/planetarium_01_reflection.png", "ppm": 256.0, "grade": Vector4(1.0, 1.0, 1.0, 0.5), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"window_contract": {"id": "window_contract", "label": "Контрактный витраж", "cat": "window", "cost": 0, "sprite": "res://assets/house/items/common_window_sprite3.png", "box": Vector3(1.000000, 0.881154, 0.105724), "vbox": Vector3(0.995000, 0.864590, 0.105195), "off": Vector3(0.014299, -0.028598, 0.014299), "alpha": Rect2(3.0, 3.0, 394.0, 585.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_window_reflection3.png", "ppm": 256.0, "wall": true, "wall_view": 0, "flip_ok": true, "reward": true, "tint": "#c9a24d"},
	"window_seal": {"id": "window_seal", "label": "Витраж с печатью", "cat": "window", "cost": 0, "sprite": "res://assets/house/items/common_window_sprite.png", "box": Vector3(1.000000, 1.074396, 0.146734), "vbox": Vector3(0.995000, 0.991469, 0.146000), "off": Vector3(0.014299, -0.028598, 0.014299), "alpha": Rect2(3.0, 3.0, 415.0, 656.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_window_reflection.png", "ppm": 256.0, "wall": true, "wall_view": 0, "flip_ok": true, "reward": true, "tint": "#a34a3c"},
	"window_guild": {"id": "window_guild", "label": "Витраж гильдии", "cat": "window", "cost": 0, "sprite": "res://assets/house/items/common_window_sprite2.png", "box": Vector3(1.000000, 0.903140, 0.094394), "vbox": Vector3(0.995000, 0.886931, 0.093922), "off": Vector3(0.014299, -0.028598, 0.014299), "alpha": Rect2(3.0, 3.0, 392.0, 595.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_window_reflection2.png", "ppm": 256.0, "wall": true, "wall_view": 0, "flip_ok": true, "reward": true, "tint": "#4d7ab7"},
	"door_guild": {"id": "door_guild", "label": "Дверь гильдии", "cat": "door", "cost": 0, "sprite": "res://assets/house/items/common_door_01_sprite.png", "box": Vector3(1.000000, 1.671154, 0.087241), "vbox": Vector3(0.995000, 1.653594, 0.086804), "off": Vector3(0.003380, -0.006760, 0.003380), "alpha": Rect2(3.0, 3.0, 295.0, 691.0), "refl_mode": "advanced", "refl": "res://assets/house/items/common_door_01_reflection.png", "ppm": 256.0, "wall": true, "wall_view": 1, "flip_ok": true, "reward": true, "tint": "#4d7ab7"},
	"bed_carved": {"id": "bed_carved", "label": "Резная кровать", "cat": "bed", "cost": 0, "sprite": "res://assets/house/items/bed_test_fixed_sprite.png", "box": Vector3(1.000000, 0.597537, 0.780870), "vbox": Vector3(0.995000, 0.564139, 0.776965), "off": Vector3(0.006308, -0.012617, 0.006308), "alpha": Rect2(1.0, 1.0, 1381.0, 1305.0), "refl_mode": "advanced", "refl": "res://assets/house/items/bed_test_fixed_reflection.png", "ppm": 256.0, "wall": false, "wall_view": -1, "flip_ok": true, "reward": true, "tint": "#c9a24d"},
	"planetarium_ember": {"id": "planetarium_ember", "label": "Планетарий «Уголь»", "cat": "decor", "cost": 0, "sprite": "res://assets/house/items/planetarium_01_sprite.png", "box": Vector3(0.455909, 0.574459, 1.000000), "vbox": Vector3(0.453630, 0.562685, 0.995000), "off": Vector3(0.002569, -0.005138, 0.002569), "alpha": Rect2(5.0, 5.0, 812.0, 833.0), "refl_mode": "regular", "refl": "res://assets/house/items/planetarium_01_reflection.png", "ppm": 256.0, "grade": Vector4(1.0, 1.0, 1.0, 0.5), "wall": false, "wall_view": -1, "flip_ok": true, "reward": true, "tint": "#ff7a2e"},
}


static func get_item(id: String) -> Dictionary:
	if not _scaled.has(id):
		var src: Dictionary = ITEMS.get(id, {})
		if src.is_empty():
			return {}
		_scaled[id] = _apply_scale(src)
	return _scaled[id]


## Метрики в ITEMS остаются один в один из .asset, а в комнату предмет попадает
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
