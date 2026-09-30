class_name SigilRecipe
extends RefCounted

## Рецепт — единственный вход генератора карточки. Один и тот же рецепт
## всегда даёт один и тот же seed, а seed — один и тот же круг.
##
## Порядок ингредиентов по умолчанию НЕ влияет на seed (список сортируется):
## перестановка ингредиентов не должна ломать уже выпущенные карточки.
## Если рецепту важна последовательность шагов (трансмутация), поставь
## [member order_sensitive] = true — это тоже часть хеша.

const ALGORITHM_VERSION := 1

var id: StringName = &""
var ingredients: PackedStringArray = PackedStringArray()
var result_type: StringName = &"object"
var result_id: StringName = &""
var rarity: StringName = &"common"
var tags: PackedStringArray = PackedStringArray()
var properties: Dictionary = {}
var order_sensitive: bool = false
var display_name: String = ""

## Ручной сид для отладки и стенда. В каноническую строку НЕ входит
## (иначе подмена меняла бы сама себя), но входит в ключ кэша.
var seed_override: int = -1


static func from_dict(d: Dictionary) -> SigilRecipe:
	var r := new()
	r.id = StringName(str(d.get("id", "")))
	r.ingredients = PackedStringArray()
	for v in d.get("ingredients", []):
		r.ingredients.append(str(v))
	r.result_type = StringName(str(d.get("result_type", "object")))
	r.result_id = StringName(str(d.get("result_id", d.get("id", ""))))
	r.rarity = StringName(str(d.get("rarity", "common")))
	for v in d.get("tags", []):
		r.tags.append(str(v))
	r.properties = (d.get("properties", {}) as Dictionary).duplicate(true)
	r.order_sensitive = bool(d.get("order_sensitive", false))
	r.display_name = str(d.get("display_name", ""))
	return r


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"ingredients": Array(ingredients),
		"result_type": String(result_type),
		"result_id": String(result_id),
		"rarity": String(rarity),
		"tags": Array(tags),
		"properties": properties.duplicate(true),
		"order_sensitive": order_sensitive,
		"display_name": display_name,
	}


func sorted_ingredients() -> PackedStringArray:
	var out := ingredients.duplicate()
	var arr := Array(out)
	arr.sort()
	return PackedStringArray(arr)


func canonical_string() -> String:
	## Стабильное представление для хеширования. Ключи properties сортируются,
	## иначе порядок в JSON-файле менял бы seed.
	var props := PackedStringArray()
	for k in properties.keys():
		props.append("%s=%s" % [str(k), JSON.stringify(properties[k])])
	props.sort()
	return "|".join(PackedStringArray([
		"v%d" % ALGORITHM_VERSION,
		"id=%s" % id,
		"ing=%s" % (",".join(ingredients if order_sensitive else sorted_ingredients())),
		"ord=%d" % (1 if order_sensitive else 0),
		"type=%s" % result_type,
		"res=%s" % result_id,
		"rar=%s" % rarity,
		"tags=%s" % (",".join(_sorted(tags))),
		"props=%s" % ";".join(props),
	]))


func _sorted(v: PackedStringArray) -> PackedStringArray:
	var a := Array(v)
	a.sort()
	return PackedStringArray(a)


func compute_seed() -> int:
	## recipe → SHA-256 → uint64. Детерминированно и без Godot-зависимостей.
	if seed_override >= 0:
		return seed_override
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical_string().to_utf8_buffer())
	return SigilRng.seed_from_bytes(ctx.finish())


func card_key(extra_salt: String = "") -> String:
	## Ключ кэша: на картинку влияет не только рецепт, но и размер/опции рендера.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((canonical_string() + "|salt=" + extra_salt
		+ "|ovr=" + str(seed_override)).to_utf8_buffer())
	return ctx.finish().hex_encode()


func duplicate_recipe() -> SigilRecipe:
	return from_dict(to_dict())
