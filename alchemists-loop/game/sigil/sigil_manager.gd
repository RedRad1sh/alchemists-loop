class_name SigilManager
extends Node

## Интеграционный слой модуля «Аркан Сигилов» в Alchemist's Loop.
##
## Управляет рендер-сервисом, генерацией карточек по рецептам игры,
## кэшированием и показом карточек в UI. Каждая карточка детерминирована:
## seed = hash(рецепт + player_id), поэтому один и тот же рецепт даёт
## одинаковую карточку у одного игрока, но разную — у разных.

signal card_ready(recipe_id: String, image: Image)
signal collection_changed
signal daily_crafts_ready(crafts: Array)
signal craft_completed(craft_id: String, rarity: String, llm_name: String)
signal craft_failed(error: String)

const CACHE_DIR := "user://sigil_collection"
const COLLECTION_FILE := "user://sigil_collection.json"
const DAILY_CACHE_FILE := "user://sigil_daily_cache.json"
## Сторона квадратного превью для меню крафтов. Меньше 240 — глифы сливаются,
## больше — рендер одного превью заметно дороже.
const PREVIEW_SIZE := 280

var _svc: SigilRenderService
var _options: SigilOptions
var _collection: Dictionary = {}  ## recipe_id -> {seed, rarity, discovered_at}
var _player_salt: String = ""
var _daily_crafts: Array = []  ## кэш ежедневных крафтов
var _daily_day: String = ""  ## день кэша
var _preview_cache: Dictionary = {}  ## craft_id -> ImageTexture


func _ready() -> void:
	_svc = SigilRenderService.new()
	_svc.name = "SigilRenderService"
	add_child(_svc)
	_options = SigilOptions.make({
		"card_size": Vector2i(512, 1024),
		"show_name": true,
		"show_frame": true,
		"render_scale": 1,
	})
	_load_collection()
	_load_daily_cache()


## Задать соль игрока (device_id или account_id). Вызывается один раз при старте.
func set_player_salt(salt: String) -> void:
	_player_salt = salt


## Сгенерировать карточку по рецепту игры. Возвращает Image.
## first_time=true — карточка добавляется в коллекцию.
func generate_card(item_id: String, ingredients: PackedStringArray,
		rarity: StringName = &"common", result_type: StringName = &"object",
		display_name: String = "", first_time: bool = false) -> Image:
	var recipe := _make_recipe(item_id, ingredients, rarity, result_type, display_name)
	var img := await _svc.render(recipe, _options)
	if first_time and not _collection.has(item_id):
		_collection[item_id] = {
			"seed": recipe.compute_seed(),
			"rarity": str(rarity),
			"discovered_at": Time.get_unix_time_from_system(),
		}
		_save_collection()
		collection_changed.emit()
	card_ready.emit(item_id, img)
	return img


## Получить карточку из кэша или сгенерировать.
func get_card(item_id: String, ingredients: PackedStringArray,
		rarity: StringName = &"common", result_type: StringName = &"object",
		display_name: String = "") -> Image:
	var cached := _load_cached_image(item_id)
	if cached != null:
		return cached
	var img := await generate_card(item_id, ingredients, rarity, result_type, display_name, true)
	_save_cached_image(item_id, img)
	return img


## Показать карточку в попапе (вызывается из main.gd).
func show_card_popup(item_id: String, ingredients: PackedStringArray,
		rarity: StringName = &"common", result_type: StringName = &"object",
		display_name: String = "") -> void:
	var g := get_tree().root.get_child(0) as Game
	if g == null:
		return
	var img := await get_card(item_id, ingredients, rarity, result_type, display_name)
	var tex := ImageTexture.create_from_image(img)
	g._show_sigil_card(tex, item_id, display_name, str(rarity))


## Построить SigilRecipe из данных игры.
func _make_recipe(item_id: String, ingredients: PackedStringArray,
		rarity: StringName, result_type: StringName, display_name: String) -> SigilRecipe:
	var r := SigilRecipe.new()
	r.id = StringName(item_id)
	r.ingredients = ingredients
	r.result_type = result_type
	r.result_id = StringName(item_id)
	r.rarity = rarity
	r.display_name = display_name if display_name != "" else item_id
	# Соль игрока домешивается к канонической строке рецепта, а не подменяет её:
	# иначе два рецепта с одним id давали бы одинаковый круг независимо от
	# состава и редкости.
	if _player_salt != "":
		r.seed_override = SigilRng.seed_from_string(r.canonical_string() + "#" + _player_salt)
	return r


## Рецепт ежедневного крафта из словаря ответа сервера.
func make_craft_recipe(craft: Dictionary) -> SigilRecipe:
	return _make_recipe(str(craft.get("id", "")), craft_ingredients(craft),
		StringName(str(craft.get("rarity", "common"))), &"object",
		str(craft.get("llm_name", "")))


## Список id ингредиентов крафта (без количеств).
static func craft_ingredients(craft: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for ing in craft.get("ingredients", []):
		out.append(str((ing as Dictionary).get("item_id", "")))
	return out


## Опции квадратного превью: круг целиком, без рамки и подписи.
func preview_options() -> SigilOptions:
	return SigilOptions.make({
		"card_size": Vector2i(PREVIEW_SIZE, PREVIEW_SIZE),
		"show_name": false,
		"show_frame": false,
		"render_scale": 1,
	})


## Превью круга для меню крафтов — тот же рендер, что и у карточки, только
## квадратный. Кэш в памяти на сессию + PNG на диске между запусками.
func preview_texture(craft: Dictionary) -> ImageTexture:
	var key := str(craft.get("id", ""))
	if _preview_cache.has(key):
		return _preview_cache[key]
	var recipe := make_craft_recipe(craft)
	var opts := preview_options()
	var img: Image = null
	var path := await _svc.export_cached(recipe, opts)
	if path != "" and FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null:
		img = await _svc.render(recipe, opts)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_preview_cache[key] = tex
	return tex


## Кэширование PNG на диске.
func _cached_path(item_id: String) -> String:
	return "%s/%s.png" % [CACHE_DIR, item_id]


func _load_cached_image(item_id: String) -> Image:
	var p := _cached_path(item_id)
	if not FileAccess.file_exists(p):
		return null
	return Image.load_from_file(p)


func _save_cached_image(item_id: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	img.save_png(_cached_path(item_id))


## Коллекция: сохранение/загрузка.
func _load_collection() -> void:
	if not FileAccess.file_exists(COLLECTION_FILE):
		return
	var f := FileAccess.open(COLLECTION_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_collection = parsed


func _save_collection() -> void:
	var f := FileAccess.open(COLLECTION_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_collection, "  "))
	f.close()


func collection_size() -> int:
	return _collection.size()


## Вью-модель для UI коллекции: [{id, rarity, texture}] в порядке открытия.
## Берём PNG из кэша; если файла нет — перерендериваем по seed (он детерминирован).
func build_collection_view() -> Array:
	var ids := _collection.keys()
	ids.sort_custom(func(a, b):
		return float(_collection[a].get("discovered_at", 0.0)) < float(_collection[b].get("discovered_at", 0.0)))
	var out: Array = []
	for id in ids:
		var entry: Dictionary = _collection[id]
		var img := _load_cached_image(id)
		if img == null:
			var rarity := StringName(str(entry.get("rarity", "common")))
			img = await generate_card(id, PackedStringArray(), rarity, &"object", "", false)
			if img != null:
				_save_cached_image(id, img)
		if img == null:
			continue
		out.append({
			"id": id,
			"rarity": str(entry.get("rarity", "common")),
			"texture": ImageTexture.create_from_image(img),
		})
	return out


func has_card(item_id: String) -> bool:
	return _collection.has(item_id)


func get_collection_data() -> Dictionary:
	return _collection.duplicate()


## Ежедневные крафты: запросить с сервера.
func request_daily(device_id: String) -> void:
	var today := _today_string()
	if _daily_day == today and not _daily_crafts.is_empty():
		daily_crafts_ready.emit(_daily_crafts)
		return
	Net.sigil_daily(device_id)


## Обработать ответ сервера по ежедневным крафтам.
func _on_daily_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		return
	_daily_day = str(result.get("day", ""))
	var crafts_raw: Array = result.get("crafts", [])
	_daily_crafts = []
	for c in crafts_raw:
		_daily_crafts.append({
			"id": str(c.get("id", "")),
			"ingredients": c.get("ingredients", []),
			"ether_cost": int(c.get("ether_cost", 0)),
			"rarity": str(c.get("rarity", "common")),
			"llm_name": str(c.get("llm_name", "")),
			"is_chromatic": bool(c.get("is_chromatic", false)),
		})
	_save_daily_cache()
	daily_crafts_ready.emit(_daily_crafts)


## Крафт карточки: отправить запрос на сервер.
func craft_card(device_id: String, craft_id: String) -> void:
	Net.sigil_craft(device_id, craft_id)


## Обработать ответ сервера по крафту.
func _on_craft_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		craft_failed.emit(str(result.get("error", "unknown")))
		return
	var craft_id := str(result.get("craft_id", ""))
	var rarity := str(result.get("rarity", "common"))
	var llm_name := str(result.get("llm_name", ""))
	# Добавляем в коллекцию
	if not _collection.has(craft_id):
		var craft := _daily_craft_by_id(craft_id)
		craft["rarity"] = rarity
		craft["llm_name"] = llm_name
		var recipe := make_craft_recipe(craft)
		_collection[craft_id] = {
			"seed": recipe.compute_seed(),
			"rarity": rarity,
			"discovered_at": Time.get_unix_time_from_system(),
		}
		_save_collection()
		collection_changed.emit()
	craft_completed.emit(craft_id, rarity, llm_name)


## Крафт из кэша ежедневных по id (копия); пустой каркас, если уже ротирован.
func _daily_craft_by_id(craft_id: String) -> Dictionary:
	for c in _daily_crafts:
		if str((c as Dictionary).get("id", "")) == craft_id:
			return (c as Dictionary).duplicate(true)
	return {"id": craft_id, "ingredients": [], "ether_cost": 0,
		"rarity": "common", "llm_name": "", "is_chromatic": false}


## Кэш ежедневных крафтов на диске (для офлайн-режима).
func _save_daily_cache() -> void:
	var f := FileAccess.open(DAILY_CACHE_FILE, FileAccess.WRITE)
	if f == null:
		return
	var data := {"day": _daily_day, "crafts": _daily_crafts}
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _load_daily_cache() -> void:
	if not FileAccess.file_exists(DAILY_CACHE_FILE):
		return
	var f := FileAccess.open(DAILY_CACHE_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_daily_day = str(parsed.get("day", ""))
		_daily_crafts = parsed.get("crafts", [])


func _today_string() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]
