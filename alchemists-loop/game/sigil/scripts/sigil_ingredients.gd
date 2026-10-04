class_name SigilIngredients
extends RefCounted

## Таблица ингредиентов по умолчанию: id → глиф + категории.
## Это ЗАГЛУШКА для стенда. В игре подставь своё: игра уже знает, что такое
## «Кровь волка» — модулю нужно только знать, каким глифом её изобразить.
##
## Подключение своей БД:
##   SigilIngredients.overrides["wolf_blood"] = {"glyph": "serpent", "cats": ["life", "fire"]}
##   SigilIngredients.emit_changed()

static var overrides: Dictionary = {}
static var _table: Dictionary = {}


static func _ensure() -> void:
	if not _table.is_empty():
		return
	_table = {
		# --- стихии ---
		"sulfur":        {"glyph": "sulfur",      "cats": ["fire", "metal"]},
		"charcoal":      {"glyph": "earth",       "cats": ["fire", "earth"]},
		"salt":          {"glyph": "salt",        "cats": ["earth", "salt"]},
		"nitre":         {"glyph": "salt",        "cats": ["earth", "acid"]},
		"quicksilver":   {"glyph": "mercury",     "cats": ["metal", "spirit"]},
		"gold_leaf":     {"glyph": "gold",        "cats": ["metal", "gold"]},
		"silver_ash":    {"glyph": "silver",      "cats": ["metal", "silver"]},
		"copper":        {"glyph": "copper",      "cats": ["metal", "copper"]},
		"iron filings":  {"glyph": "iron",        "cats": ["metal", "iron"]},
		"antimony":      {"glyph": "antimony",    "cats": ["metal", "mind"]},
		"vitriol":       {"glyph": "vitriol",     "cats": ["acid"]},
		"aqua_regia":    {"glyph": "aqua_regia",  "cats": ["acid", "water"]},
		"lead":          {"glyph": "lead",        "cats": ["metal", "lead"]},
		# --- жидкости ---
		"rain_water":    {"glyph": "water",       "cats": ["water"]},
		"distilled":     {"glyph": "drop",        "cats": ["water", "vessel"]},
		"oil":           {"glyph": "drop",        "cats": ["water", "fire"]},
		"blood":         {"glyph": "drop",        "cats": ["life"]},
		# --- органика ---
		"wolf_blood":    {"glyph": "serpent",     "cats": ["life", "spirit"]},
		"raven_feather": {"glyph": "raven",      "cats": ["spirit", "air"]},
		"owl_eye":       {"glyph": "owl",         "cats": ["mind", "night"]},
		"bone_dust":     {"glyph": "bone",        "cats": ["earth", "life"]},
		"mandrake":      {"glyph": "hand",        "cats": ["life"]},
		"herbal_extract":{"glyph": "leaf",        "cats": ["life", "earth"]},
		"dragon_scale":  {"glyph": "dragon",      "cats": ["spirit", "fire"]},
		"ash":           {"glyph": "earth",       "cats": ["earth", "fire"]},
		# --- приборы ---
		"crucible":      {"glyph": "crucible",    "cats": ["vessel", "fire"]},
		"alembic":       {"glyph": "alembic",     "cats": ["vessel"]},
		"retort":        {"glyph": "retort",      "cats": ["vessel", "acid"]},
		"athanor":       {"glyph": "athanor",     "cats": ["vessel", "time"]},
		"phial":         {"glyph": "phial",       "cats": ["vessel", "life"]},
		"grimoire":      {"glyph": "book",        "cats": ["mind"]},
		"astrolabe":     {"glyph": "compass",     "cats": ["mind", "world"]},
		"scale":         {"glyph": "balance",     "cats": ["balance", "mind"]},
		"hourglass":     {"glyph": "hourglass",   "cats": ["time"]},
		# --- прочее ---
		"starlight":     {"glyph": "sphere",      "cats": ["light", "star"]},
		"void_dust":     {"glyph": "spiral",      "cats": ["void", "spirit"]},
		"echo":          {"glyph": "infinity",    "cats": ["time", "mind"]},
		"gaze":          {"glyph": "eye",         "cats": ["mind", "eye"]},
		"rebirth":       {"glyph": "philosopher_stone", "cats": ["result", "spirit"]},
		"triad":         {"glyph": "triquetra",   "cats": ["spirit", "mind"]},
		"seal":          {"glyph": "hexagram",    "cats": ["spirit"]},
		"pyre":          {"glyph": "torch",       "cats": ["fire", "light"]},
		"anchor":        {"glyph": "anchor",      "cats": ["balance", "water"]},
		"key":           {"glyph": "key",         "cats": ["object", "mind"]},
		"crown":         {"glyph": "crown",       "cats": ["power", "object"]},
		"skull":         {"glyph": "skull",       "cats": ["death", "mind"]},
		"air":           {"glyph": "air",         "cats": ["air"]},
	}


static func info(ingredient_id: String) -> Dictionary:
	_ensure()
	if overrides.has(ingredient_id):
		return (overrides[ingredient_id] as Dictionary)
	if _table.has(ingredient_id):
		return (_table[ingredient_id] as Dictionary)
	# Неизвестный ингредиент: глиф выведем из самого id — карточка не должна
	# «пропадать» из-за нового предмета в игре.
	return {"glyph": _slug_to_glyph(ingredient_id), "cats": ["object"], "unknown": true}


static func glyph_for(ingredient_id: String) -> String:
	return str(info(ingredient_id).get("glyph", "sphere"))


static func categories_for(ingredient_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for c in info(ingredient_id).get("cats", []):
		out.append(str(c))
	return out


static func register(ingredient_id: String, glyph: String, cats: PackedStringArray) -> void:
	overrides[ingredient_id] = {"glyph": glyph, "cats": Array(cats)}


static func _slug_to_glyph(ingredient_id: String) -> String:
	var lib := SigilGlyphs.names()
	if lib.is_empty():
		return ""
	var h := SigilRng.fnv1a(ingredient_id)
	return lib[h % lib.size()]
