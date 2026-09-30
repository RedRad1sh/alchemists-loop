class_name SigilItemAdapter
extends RefCounted

## Адаптер игровых предметов → глифы на круге.
##
## Игра знает предметы в своём формате, модуль — нет. Этот класс снимает
## вопрос: он берёт словарь предмета, находит в нём id / категорию / теги
## (по любому из типовых имён ключей) и превращает это в глиф.
##
## Три уровня приоритета:
##   1. явная привязка  — [method bind] / [member manual];
##   2. custom_resolver — твоя функция, если формат нестандартный;
##   3. категория/теги  — [member category_map] / [member tag_glyph];
##   4. хеш от id      — чтобы новый предмет никогда не ломал карточку.
##
## Быстрая связка со всей игрой:
##     SigilItemAdapter.auto_bind(get_tree().get_nodes_in_group("items"))
##     # или по массиву словарей:
##     SigilItemAdapter.bind(DATA.items)
##
## Свой формат — одна строка:
##     SigilItemAdapter.custom_resolver = func(item: Dictionary) -> String: ...

## Типовые имена ключей. Если у тебя другие — допиши сюда.
static var id_keys: PackedStringArray = PackedStringArray(
	["id", "uid", "key", "item_id", "code", "slug", "name", "title"])
static var category_keys: PackedStringArray = PackedStringArray(
	["category", "type", "kind", "group", "class", "family", "element"])
static var tag_keys: PackedStringArray = PackedStringArray(
	["tags", "traits", "elements", "properties", "attrs"])
static var name_keys: PackedStringArray = PackedStringArray(
	["name", "display_name", "title", "localization_key", "loc"])

## Категория/тип предмета → глиф. Ключи в нижнем регистре.
static var category_map: Dictionary = {
	"fire": "torch", "flame": "torch", "огонь": "torch", "пламя": "torch", "жар": "torch",
	"water": "drop", "liquid": "drop", "вода": "drop", "жидкость": "drop", "раствор": "drop",
	"ice": "leaf", "cold": "leaf", "лёд": "leaf", "холод": "leaf", "мороз": "leaf",
	"earth": "bone", "stone": "bone", "soil": "leaf", "земля": "bone", "камень": "bone",
	"air": "air", "wind": "air", "воздух": "air", "ветер": "air",
	"metal": "mercury", "ore": "lead", "металл": "mercury", "руда": "lead",
	"gold": "gold", "золото": "gold", "silver": "silver", "серебро": "silver",
	"copper": "copper", "медь": "copper", "iron": "iron", "железо": "iron",
	"lead": "lead", "свинец": "lead", "salt": "salt", "соль": "salt",
	"acid": "vitriol", "кислота": "vitriol", "vitriol": "vitriol", "vit": "vitriol",
	"blood": "serpent", "кровь": "serpent", "life": "leaf", "жизнь": "leaf",
	"soul": "spiral", "душа": "spiral", "дух": "spiral", "spirit": "spiral",
	"void": "spiral", "пустота": "spiral", "time": "hourglass", "время": "hourglass",
	"mind": "eye", "gaze": "eye", "разум": "eye", "взгляд": "eye", "мысль": "eye",
	"death": "skull", "смерть": "skull", "кость": "bone", "bone": "bone",
	"knowledge": "book", "книга": "book", "знание": "book", "гримуар": "book",
	"vessel": "phial", "сосуд": "phial", "флакон": "phial", "колба": "alembic",
	"treasure": "crown", "сокровище": "crown", "власть": "crown", "power": "crown",
	"key": "key", "ключ": "key", "nature": "leaf", "природа": "leaf",
	"bird": "raven", "птица": "raven", "зверь": "serpent", "животное": "serpent",
}

## Тег предмета → глиф (сильнее категории, если тег известен).
static var tag_glyph: Dictionary = {
	"blood": "serpent", "кровь": "serpent", "serpent": "serpent", "змея": "serpent",
	"feather": "raven", "перо": "raven", "raven": "raven", "ворон": "raven",
	"eye": "owl", "глаз": "owl", "owl": "owl", "сова": "owl",
	"bone": "bone", "кость": "bone", "scale": "balance", "чешуя": "balance",
	"star": "sphere", "звезда": "sphere", "light": "sun", "свет": "sun",
	"moon": "moon", "луна": "moon", "salt": "salt", "соль": "salt",
	"phoenix": "torch", "феникс": "torch", "dragon": "dragon", "дракон": "dragon",
	"hourglass": "hourglass", "песок": "hourglass", "water": "drop", "вода": "drop",
}

## Ручные привязки: id предмета → глиф. Перекрывают всё остальное.
static var manual: Dictionary = {}

## Твоя функция. Возвращает имя глифа или "" — тогда идёт стандартная цепочка.
static var custom_resolver: Callable = Callable()


static func _get_first(d: Dictionary, keys: PackedStringArray) -> String:
	for k in keys:
		if d.has(k):
			var v = d[k]
			if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
				var s := str(v).strip_edges()
				if s != "":
					return s
	return ""


static func id_of(item: Dictionary) -> String:
	return _get_first(item, id_keys)


## Что показывать в интерфейсе.
static func display_name(item: Dictionary) -> String:
	return _get_first(item, name_keys)


## Полное разрешение: {glyph: String, cats: PackedStringArray, id: String}
static func resolve(item: Dictionary) -> Dictionary:
	var id := id_of(item)
	if id == "":
		id = "?"
	var cats := PackedStringArray()
	var glyph := ""

	# 1. ручная привязка
	if manual.has(id):
		glyph = str(manual[id])
	# 2. пользовательский резолвер
	elif custom_resolver.is_valid():
		var g = custom_resolver.call(item)
		if typeof(g) == TYPE_STRING and str(g) != "":
			glyph = str(g)
		elif typeof(g) == TYPE_DICTIONARY and (g as Dictionary).has("glyph"):
			glyph = str((g as Dictionary)["glyph"])
	# 3. теги
	if glyph == "":
		for tk in tag_keys:
			if not item.has(tk):
				continue
			var arr = item[tk]
			if typeof(arr) == TYPE_STRING or typeof(arr) == TYPE_INT:
				arr = [arr]
			if typeof(arr) != TYPE_ARRAY:
				continue
			for t in arr:
				var key := str(t).strip_edges().to_lower()
				if tag_glyph.has(key):
					glyph = str(tag_glyph[key])
					cats.append(key)
					break
			if glyph != "":
				break
	# 4. известный ингредиент по id
	# Идёт раньше категории: если предмет — это «wolf_blood», его собственная
	# привязка важнее общей категории «life». Проверяем флаг unknown: для
	# незнакомых id таблица отдаёт хеш-фолбэк, и он не должен перехватывать
	# категорию у настоящих предметов вида {"id": "t1", "type": "fire"}.
	if glyph == "":
		var ki := SigilIngredients.info(id)
		if not bool(ki.get("unknown", false)):
			glyph = str(ki.get("glyph", ""))
			var kc := SigilIngredients.categories_for(id)
			if kc.size() > 0:
				cats.append_array(kc)
	# 5. категория
	if glyph == "":
		var cat := _get_first(item, category_keys).to_lower()
		if category_map.has(cat):
			glyph = str(category_map[cat])
		if cat != "":
			cats.append(cat)
	# 6. хеш от id — чтобы незнакомый предмет всё равно получил глиф
	if glyph == "":
		glyph = SigilIngredients._slug_to_glyph(id)

	if cats.is_empty():
		cats = SigilGlyphs.categories_of(glyph)
	return {"id": id, "glyph": glyph, "cats": cats}


## Разово привязать один предмет.
static func bind_item(item: Dictionary) -> Dictionary:
	var r := resolve(item)
	SigilIngredients.register(str(r["id"]), str(r["glyph"]), r["cats"] as PackedStringArray)
	return r


## Привязать пачку предметов (массив словарей). Основная точка входа.
static func bind(items: Array) -> int:
	var n := 0
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		bind_item(it)
		n += 1
	return n


## Привязать ноды инвентаря: у ноды читается её id и любые
## category/tag-свойства. Удобно, если предметы живут в сценах.
static func bind_nodes(nodes: Array) -> int:
	var n := 0
	for node in nodes:
		var item: Dictionary = {}
		if node is Resource or node is Object:
			for k in id_keys + category_keys:
				if k in node and node.get(k) != null:
					item[k] = node.get(k)
		if typeof(node) == TYPE_DICTIONARY:
			item = node
		if item.is_empty():
			continue
		bind_item(item)
		n += 1
	return n


static func describe() -> String:
	return "SigilItemAdapter: %d категорий, %d тегов, %d ручных привязок" % [
		category_map.size(), tag_glyph.size(), manual.size()]
