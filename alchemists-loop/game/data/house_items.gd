extends RefCounted
class_name HouseItems

const CATS: Array = ["window", "rug", "chair", "table", "plant", "lamp", "shelf", "fireplace", "bed"]
const ITEMS := {
	"window": {"id": "window", "label": "Классическое окно", "cat": "window", "cost": 70, "sprite": "res://assets/house/items/window.png", "box": Vector3(1.20, 1.00, 0.10), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": false, "tint": ""},
	"window_alt": {"id": "window_alt", "label": "Круглое окно", "cat": "window", "cost": 110, "sprite": "res://assets/house/items/window_alt.png", "box": Vector3(1.20, 1.00, 0.10), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": false, "tint": ""},
	"rug": {"id": "rug", "label": "Тканый ковёр", "cat": "rug", "cost": 80, "sprite": "res://assets/house/items/rug.png", "box": Vector3(2.00, 0.02, 1.80), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"rug_alt": {"id": "rug_alt", "label": "Круглый ковёр", "cat": "rug", "cost": 130, "sprite": "res://assets/house/items/rug_alt.png", "box": Vector3(2.00, 0.02, 1.80), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"chair": {"id": "chair", "label": "Деревянный стул", "cat": "chair", "cost": 90, "sprite": "res://assets/house/items/chair.png", "box": Vector3(0.60, 0.90, 0.60), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"chair_alt": {"id": "chair_alt", "label": "Мягкое кресло", "cat": "chair", "cost": 145, "sprite": "res://assets/house/items/chair_alt.png", "box": Vector3(0.60, 0.90, 0.60), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"table": {"id": "table", "label": "Круглый стол", "cat": "table", "cost": 120, "sprite": "res://assets/house/items/table.png", "box": Vector3(1.10, 0.75, 0.80), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"table_alt": {"id": "table_alt", "label": "Письменный стол", "cat": "table", "cost": 190, "sprite": "res://assets/house/items/table_alt.png", "box": Vector3(1.10, 0.75, 0.80), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"plant": {"id": "plant", "label": "Папоротник в кадке", "cat": "plant", "cost": 100, "sprite": "res://assets/house/items/plant.png", "box": Vector3(0.55, 1.00, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"plant_alt": {"id": "plant_alt", "label": "Монстера", "cat": "plant", "cost": 160, "sprite": "res://assets/house/items/plant_alt.png", "box": Vector3(0.55, 1.00, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"lamp": {"id": "lamp", "label": "Торшер", "cat": "lamp", "cost": 110, "sprite": "res://assets/house/items/lamp.png", "box": Vector3(0.45, 1.50, 0.45), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"lamp_alt": {"id": "lamp_alt", "label": "Настольная лампа", "cat": "lamp", "cost": 175, "sprite": "res://assets/house/items/lamp_alt.png", "box": Vector3(0.45, 1.50, 0.45), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"shelf": {"id": "shelf", "label": "Полка", "cat": "shelf", "cost": 140, "sprite": "res://assets/house/items/shelf.png", "box": Vector3(1.20, 0.35, 0.25), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": false, "tint": ""},
	"shelf_alt": {"id": "shelf_alt", "label": "Навесной шкаф", "cat": "shelf", "cost": 225, "sprite": "res://assets/house/items/shelf_alt.png", "box": Vector3(1.20, 0.35, 0.25), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": false, "tint": ""},
	"fireplace": {"id": "fireplace", "label": "Каменный камин", "cat": "fireplace", "cost": 300, "sprite": "res://assets/house/items/fireplace.png", "box": Vector3(1.40, 1.10, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 1, "flip_ok": true, "reward": false, "tint": ""},
	"fireplace_alt": {"id": "fireplace_alt", "label": "Чугунная печь", "cat": "fireplace", "cost": 480, "sprite": "res://assets/house/items/fireplace_alt.png", "box": Vector3(1.40, 1.10, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 1, "flip_ok": true, "reward": false, "tint": ""},
	"bed": {"id": "bed", "label": "Кровать", "cat": "bed", "cost": 250, "sprite": "res://assets/house/items/bed.png", "box": Vector3(1.70, 0.60, 2.20), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"bed_alt": {"id": "bed_alt", "label": "Кровать с балдахином", "cat": "bed", "cost": 400, "sprite": "res://assets/house/items/bed_alt.png", "box": Vector3(1.70, 0.60, 2.20), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": false, "wall_view": -1, "flip_ok": true, "reward": false, "tint": ""},
	"window_contract": {"id": "window_contract", "label": "Контрактный витраж", "cat": "window", "cost": 0, "sprite": "res://assets/house/items/window.png", "box": Vector3(1.20, 1.00, 0.10), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": true, "tint": "#c9a24d"},
	"window_seal": {"id": "window_seal", "label": "Витраж с печатью", "cat": "window", "cost": 0, "sprite": "res://assets/house/items/window_alt.png", "box": Vector3(1.20, 1.00, 0.10), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": true, "tint": "#a34a3c"},
	"window_guild": {"id": "window_guild", "label": "Витраж гильдии", "cat": "window", "cost": 0, "sprite": "res://assets/house/items/window_alt.png", "box": Vector3(1.20, 1.00, 0.10), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 0, "flip_ok": true, "reward": true, "tint": "#4d7ab7"},
	"fireplace_ember": {"id": "fireplace_ember", "label": "Камин «Уголёк»", "cat": "fireplace", "cost": 0, "sprite": "res://assets/house/items/fireplace.png", "box": Vector3(1.40, 1.10, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 1, "flip_ok": true, "reward": true, "tint": "#ff7a2e"},
	"fireplace_log": {"id": "fireplace_log", "label": "Печь «Полено»", "cat": "fireplace", "cost": 0, "sprite": "res://assets/house/items/fireplace_alt.png", "box": Vector3(1.40, 1.10, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 1, "flip_ok": true, "reward": true, "tint": "#7a4a2a"},
	"fireplace_heart": {"id": "fireplace_heart", "label": "Камин «Сердце очага»", "cat": "fireplace", "cost": 0, "sprite": "res://assets/house/items/fireplace_alt.png", "box": Vector3(1.40, 1.10, 0.55), "ppm": 256.0, "off": Vector2.ZERO, "alpha": Rect2(0, 0, 512, 512), "wall": true, "wall_view": 1, "flip_ok": true, "reward": true, "tint": "#c94a6a"},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


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
