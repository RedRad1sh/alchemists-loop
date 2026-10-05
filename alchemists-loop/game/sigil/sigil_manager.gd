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
signal sigil_admin_reset_result(result: Dictionary)
signal sigil_admin_rotate_result(result: Dictionary)
signal craft_failed(error: String)
signal catalog_ready(cards: Dictionary)
signal collection_ready(collection: Dictionary)

const CACHE_DIR := "user://sigil_collection"
const COLLECTION_FILE := "user://sigil_collection.json"
const DAILY_CACHE_FILE := "user://sigil_daily_cache.json"
const CATALOG_FILE := "user://sigil_catalog.json"
## Сторона квадратного превью для меню крафтов. Меньше 240 — глифы сливаются,
## больше — рендер одного превью заметно дороже.
const PREVIEW_SIZE := 280
## Награды комплектов: категория локального вещества -> set_id каталога.
const SET_OF_CATEGORY := {"огонь": "fire", "вода": "water", "воздух": "air", "земля": "earth"}

var _svc: SigilRenderService
var _options: SigilOptions
var _collection: Dictionary = {}  ## craft_id -> {seed, rarity, card_id, discovered_at}
var _player_salt: String = ""
var _daily_crafts: Array = []  ## кэш ежедневных крафтов
## Хэш оффера дня с сервера (по нему клиент решает, актуален ли кэш после ротации).
var _daily_offer_hash: String = ""
var _daily_day: String = ""  ## день кэша
var _preview_cache: Dictionary = {}  ## key -> ImageTexture
## Каталог карт: card_id -> словарь карты. Общий для всех игроков.
var _catalog: Dictionary = {}
var _catalog_sets: Array = []
var _catalog_version: String = ""
## Серверная коллекция: card_id -> {copies, first_at} и внекомплектные крафты.
var _server_collection: Dictionary = {}
var _server_extras: Array = []
var _last_device_id: String = ""
## Майлстоуны, подтверждённые сервером: set_id -> отсортированные тиры.
## Строго серверные: офлайн-клейм и ошибки ничего не меняют, эффекты не
## включаются без серверного подтверждения.
var _milestones_claimed: Dictionary = {}  ## set_id -> Array[int]
## M1: «на последний запрос уже пришёл ответ (любой исход)». request_* ставит
## false только при реальной отправке, хендлер гасит в true на ok/offline/error:
## офлайн-ожидание в main.gd выходит сразу, а не по полному таймауту.
var _catalog_settled := false
var _daily_settled := false
## M2: каталог уже докачан в этой сессии — повторный request_catalog no-op.
## Смена catalog_version в daily-ответе сбрасывает флаг и перевыпускает докачку.
var _catalog_fetched_session := false


func _ready() -> void:
	_svc = SigilRenderService.new()
	_svc.name = "SigilRenderService"
	add_child(_svc)
	_options = SigilOptions.make({
		"card_size": Vector2i(512, 683),
		"show_name": true,
		"show_frame": true,
		"render_scale": 1,
	})
	_load_collection()
	_load_daily_cache()
	_load_catalog_cache()


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
	var display_name := str(craft.get("llm_name", ""))
	if display_name == "":
		# Имя из каталога (fallback_name) — достойное название вместо id крафта.
		display_name = str(craft.get("fallback_name", ""))
	return _make_recipe(str(craft.get("id", "")), craft_ingredients(craft),
		StringName(str(craft.get("rarity", "common"))), &"object",
		display_name)


## Список id ингредиентов крафта (без количеств).
static func craft_ingredients(craft: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for ing in craft.get("ingredients", []):
		out.append(str((ing as Dictionary).get("item_id", "")))
	return out


## Принять каталог в память. На диск не пишем: кэш — это «последний ответ
## сервера», его сохраняет только _on_catalog_result.
func set_catalog(cards: Array, sets: Array, version: String) -> void:
	_catalog = {}
	for c in cards:
		if c is Dictionary and str((c as Dictionary).get("id", "")) != "":
			_catalog[str((c as Dictionary)["id"])] = c
	_catalog_sets = []
	for s in sets:
		if s is Dictionary:
			_catalog_sets.append(s)
	_catalog_version = version
	catalog_ready.emit(_catalog)


func card(card_id: String) -> Dictionary:
	return _catalog.get(card_id, {})


func catalog_size() -> int:
	return _catalog.size()


func catalog_version() -> String:
	return _catalog_version


func catalog_sets() -> Array:
	return _catalog_sets


## M1: ответ на последний запрос каталога уже получен (любой исход).
func catalog_settled() -> bool:
	return _catalog_settled


func request_catalog() -> void:
	# M2-гейт: каталог этой сессии уже получен — не докачиваем повторно
	# (смена версии ловится по daily-ответу в _on_daily_result).
	if _catalog_fetched_session and catalog_size() > 0:
		return
	_catalog_settled = false
	Net.sigil_catalog()


func _on_catalog_result(result: Dictionary) -> void:
	# M1: гасим settled при любом исходе — ok, offline, ошибка.
	_catalog_settled = true
	if not result.get("ok", false):
		return
	_catalog_fetched_session = true
	var cards: Array = result.get("cards", [])
	if cards.is_empty():
		return
	set_catalog(cards, result.get("sets", []), str(result.get("version", "")))
	_save_catalog_cache()


func _save_catalog_cache() -> void:
	var f := FileAccess.open(CATALOG_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": _catalog_version,
		"sets": _catalog_sets,
		"cards": _catalog.values(),
	}, "  "))
	f.close()


func _load_catalog_cache() -> void:
	if not FileAccess.file_exists(CATALOG_FILE):
		return
	var f := FileAccess.open(CATALOG_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var d := parsed as Dictionary
		set_catalog(d.get("cards", []), d.get("sets", []), str(d.get("version", "")))


## Список id ингредиентов карты каталога (без количеств).
static func card_ingredients(card: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for ing in card.get("recipe", []):
		out.append(str((ing as Dictionary).get("item_id", "")))
	return out


## Рецепт карты каталога. Seed приходит с сервера и НЕ солится: картинка карты
## общая для всех игроков — иначе коллекция и витрина показывали бы разные
## круги для одной и той же карты.
func make_card_recipe(card: Dictionary) -> SigilRecipe:
	var r := SigilRecipe.new()
	r.id = StringName(str(card.get("id", "")))
	r.ingredients = card_ingredients(card)
	r.result_type = StringName(str(card.get("object_type", "object")))
	r.result_id = StringName(str(card.get("id", "")))
	r.rarity = StringName(str(card.get("rarity", "common")))
	r.display_name = str(card.get("fallback_name", ""))
	r.properties = {
		"set": str(card.get("set", "")),
		"process": str(card.get("process", "")),
		# Спека: stage каталога — строка («nigredo»/«albedo»/…), int-каст ломал бы её.
		"stage": str(card.get("stage", "")),
	}
	var catalog_seed := int(card.get("seed", 0))
	if catalog_seed > 0:
		r.seed_override = catalog_seed
	return r


## Рецепт крафта дня: карта каталога, если card_id известен, иначе старый
## посоленный путь. Хроматическая (card_id пуст) остаётся уникальной per-player.
func card_recipe_for(craft: Dictionary) -> SigilRecipe:
	var card_id := str(craft.get("card_id", ""))
	if card_id != "" and _catalog.has(card_id):
		return make_card_recipe(_catalog[card_id])
	return make_craft_recipe(craft)


## Серверная коллекция.
func request_collection(device_id: String) -> void:
	Net.sigil_collection(device_id)


func _on_collection_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		return
	var cards: Dictionary = {}
	var raw = result.get("cards", {})
	if raw is Dictionary:
		for k in (raw as Dictionary):
			var e = (raw as Dictionary)[k]
			if e is Dictionary:
				cards[str(k)] = {
					"copies": int((e as Dictionary).get("copies", 0)),
					"first_at": str((e as Dictionary).get("first_at", "")),
				}
	_server_collection = cards
	_server_extras = []
	for x in result.get("extras", []):
		if x is Dictionary:
			_server_extras.append(x)
	# Майлстоуны едут тем же ответом. Сервер авторитетен, поэтому отсутствие
	# ключа — не ошибка, а «ничего не подтверждено»: полное замещение состояния,
	# а не накопление.
	_milestones_claimed = _normalize_milestones(result.get("milestones", {}))
	collection_changed.emit()
	collection_ready.emit(_server_collection)


func copies_of(card_id: String) -> int:
	var e = _server_collection.get(card_id, null)
	if e is Dictionary:
		return int((e as Dictionary).get("copies", 0))
	return 0


func has_collected(card_id: String) -> bool:
	return copies_of(card_id) > 0


## Есть ли собранная карта данной редкости (для достижений). Индекс редкости:
## 0=common, 1=rare, 2=epic, 3=legendary — по серверной коллекции и каталогу;
## 4=chromatic — только по хроматическим внекомплектным крафтам.
func has_rarity(idx: int) -> bool:
	if idx == 4:
		for extra in _server_extras:
			if str(extra.get("rarity", "")) == "chromatic":
				return true
		return false
	var wanted := ""
	match idx:
		0: wanted = "common"
		1: wanted = "rare"
		2: wanted = "epic"
		3: wanted = "legendary"
		_: return false
	for cid in _server_collection:
		var c := card(str(cid))
		if str(c.get("rarity", "")) == wanted:
			return true
	return false


func server_collection() -> Dictionary:
	return _server_collection.duplicate(true)


func server_extras() -> Array:
	return _server_extras.duplicate(true)


## Нормализация сырых майлстоунов (ответ сервера или кэш с диска, где числа
## приходят float): set_id -> отсортированный Array[int]. Чужие формы — пусто.
func _normalize_milestones(raw) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for k in (raw as Dictionary):
			var tiers: Array = []
			var v = (raw as Dictionary)[k]
			if v is Array:
				for t in v:
					tiers.append(int(t))
				tiers.sort()
			out[str(k)] = tiers
	return out


## Тиры набора, подтверждённые сервером. Копия, не внутренняя ссылка.
func claimed_tiers(set_id: String) -> Array:
	var tiers = _milestones_claimed.get(set_id, [])
	if tiers is Array:
		return (tiers as Array).duplicate()
	return []


## Награда «3 карты комплекта»: +40 к капу эфира за каждый комплект,
## у которого сервер подтвердил тир 3.
func milestone_cap_bonus() -> int:
	var sets := 0
	for set_id in _milestones_claimed:
		if claimed_tiers(str(set_id)).has(3):
			sets += 1
	return 40 * sets


## Награда «6 карт комплекта»: −10% эфира крафтов этого комплекта.
## Хроматика (set == "") всегда платит полную цену.
func craft_ether_cost(craft: Dictionary) -> int:
	var set_id := str(craft.get("set", ""))
	if set_id != "" and claimed_tiers(set_id).has(6):
		return int(round(int(craft.get("ether_cost", 0)) * 0.9))
	return int(craft.get("ether_cost", 0))


## Награда «13 карт комплекта»: верстак варит элементы категории комплекта
## вдвое быстрее. Неизвестные категория/сет — обычный интервал.
func bench_interval(item_id: String) -> float:
	var set_id := str(SET_OF_CATEGORY.get(str(Game.CATEGORY_OF.get(item_id, "")), ""))
	if set_id != "" and claimed_tiers(set_id).has(13):
		return Game.BENCH_INTERVAL * 0.5
	return Game.BENCH_INTERVAL


## Клейм майлстоуна набора. Ответ приходит сигналом sigil_milestone_result
## (коннект в main.gd) в _on_milestone_result.
func request_milestone_claim(device_id: String, set_id: String, tier: int) -> void:
	Net.sigil_milestone(device_id, set_id, tier)


func _on_milestone_result(result: Dictionary) -> void:
	# Флаги строго серверные: ok && claimed — единственная ветка, которая
	# меняет состояние. Офлайн-форма и ошибки (not_enough_cards и т.п.) ничего
	# не делают — эффекты не включаются без серверного подтверждения.
	if not result.get("ok", false):
		return
	if not result.get("claimed", false):
		return
	var set_id := str(result.get("set", ""))
	var tier := int(result.get("tier", 0))
	if set_id == "" or tier <= 0:
		return
	var tiers: Array = claimed_tiers(set_id)
	if not tiers.has(tier):
		tiers.append(tier)
		tiers.sort()
	_milestones_claimed[set_id] = tiers
	_save_collection()
	collection_changed.emit()


## Опции квадратного превью: круг целиком, без рамки, подписи и объекта.
## Центральный объект на 280 px превращается в шум, круг остаётся узнаваемым.
func preview_options() -> SigilOptions:
	return SigilOptions.make({
		"card_size": Vector2i(PREVIEW_SIZE, PREVIEW_SIZE),
		"show_name": false,
		"show_frame": false,
		"show_icon": false,
		"render_scale": 1,
	})


## Превью круга для меню крафтов — тот же рендер, что и у карточки, только
## квадратный. Ключ кэша — card_id, если карта известна локальному каталогу:
## превью карты каталога общее для всех игроков и переиспользуется между днями.
func preview_texture(craft: Dictionary) -> ImageTexture:
	var card_id := str(craft.get("card_id", ""))
	# D10: card_id без карты в каталоге рендерится посоленным fallback-рецептом —
	# кэшировать такое превью под card_id нельзя, ключом становится id крафта.
	var key := card_id if (card_id != "" and _catalog.has(card_id)) else str(craft.get("id", ""))
	if _preview_cache.has(key):
		return _preview_cache[key]
	var recipe := card_recipe_for(craft)
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
		# Флаги майлстоунов лежат в том же кэше (ключ "milestones"); в старых
		# файлах его нет — это пусто, а не ошибка. Сам ключ из коллекции
		# убираем: служебное поле, не карточка.
		var data := parsed as Dictionary
		_milestones_claimed = _normalize_milestones(data.get("milestones", {}))
		data.erase("milestones")
		_collection = data


func _save_collection() -> void:
	var f := FileAccess.open(COLLECTION_FILE, FileAccess.WRITE)
	if f == null:
		return
	# Флаги майлстоунов едут в том же payload (ключ "milestones"); duplicate,
	# чтобы не дописать служебный ключ в живую коллекцию.
	var payload := _collection.duplicate(true)
	payload["milestones"] = _milestones_claimed.duplicate(true)
	f.store_string(JSON.stringify(payload, "  "))
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


## M1: ответ на последний daily-запрос уже получен (любой исход).
func daily_settled() -> bool:
	return _daily_settled


## Ежедневные крафты: запросить с сервера.
## Админ: ротация крафтов дня (сервер пересобирает оффер, коллекция цела).
func request_admin_rotate(device_id: String) -> void:
	if not Net.sigil_admin_rotate_result.is_connected(_on_admin_rotate_result):
		Net.sigil_admin_rotate_result.connect(_on_admin_rotate_result, CONNECT_ONE_SHOT)
	Net.sigil_admin_rotate(device_id)


func _on_admin_rotate_result(result: Dictionary) -> void:
	# Сервер вернул новый оффер — сразу подменяем локальный кэш дневных.
	if bool(result.get("ok", false)) and result.has("crafts"):
		_daily_crafts = result.get("crafts", [])
		_daily_day = Time.get_date_string_from_system()
		_save_daily_cache()
	sigil_admin_rotate_result.emit(result)


## Админ: полный сброс Аркана на сервере (коллекция + майлстоуны).
func request_admin_reset(device_id: String) -> void:
	if not Net.sigil_admin_reset_result.is_connected(_on_admin_reset_result):
		Net.sigil_admin_reset_result.connect(_on_admin_reset_result, CONNECT_ONE_SHOT)
	Net.sigil_admin_reset(device_id)


func _on_admin_reset_result(result: Dictionary) -> void:
	sigil_admin_reset_result.emit(result)


## Удаляет PNG-кэш карточек (user://sigil_collection/*): после сброса коллекции
## старые изображения не должны воскрешаться из кэша.
func clear_image_cache() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".png"):
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()


func request_daily(device_id: String) -> void:
	# Сверка с сервером по offer_hash: клиент хранит хэш последнего оффера.
	# Сервер вернёт текущий — если совпал с нашим, кэш актуален и не
	# перезапрашиваем (нет лишнего ререндера); если ротация сменила оффер —
	# хэш другой, идём на сервер и обновляем кэш. Так устаревший оффер
	# («превью common, выпала epic») не показывается.
	_daily_settled = false
	Net.sigil_daily(device_id)


## Обработать ответ сервера по ежедневным крафтам.
func _on_daily_result(result: Dictionary) -> void:
	# M1: гасим settled при любом исходе — ok, offline, ошибка.
	_daily_settled = true
	if not result.get("ok", false):
		return
	_daily_offer_hash = str(result.get("offer_hash", _daily_offer_hash))
	# M2: daily пришёл под новой версией каталога — локальная копия устарела
	# для card_id этих крафтов, перевыпускаем докачку (спека §1).
	var srv_ver := str(result.get("catalog_version", ""))
	if srv_ver != "" and _catalog_version != "" and srv_ver != _catalog_version:
		_catalog_fetched_session = false
		request_catalog()
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
			"card_id": str(c.get("card_id", "")),
			"set": str(c.get("set", "")),
			"process": str(c.get("process", "")),
			"stage": str(c.get("stage", "")),
			"object_type": str(c.get("object_type", "object")),
			"seed": int(c.get("seed", 0)),
			"fallback_name": str(c.get("fallback_name", "")),
		})
	_save_daily_cache()
	daily_crafts_ready.emit(_daily_crafts)


## Крафт карточки: отправить запрос на сервер.
func craft_card(device_id: String, craft_id: String) -> void:
	_last_device_id = device_id
	Net.sigil_craft(device_id, craft_id)


## Обработать ответ сервера по крафту.
func _on_craft_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		craft_failed.emit(str(result.get("error", "unknown")))
		return
	var craft_id := str(result.get("craft_id", ""))
	var rarity := str(result.get("rarity", "common"))
	var llm_name := str(result.get("llm_name", ""))
	var card_id := str(result.get("card_id", ""))
	if not _collection.has(craft_id):
		var craft := _daily_craft_by_id(craft_id)
		craft["rarity"] = rarity
		craft["llm_name"] = llm_name
		if card_id != "":
			craft["card_id"] = card_id
		var recipe := card_recipe_for(craft)
		_collection[craft_id] = {
			"seed": recipe.compute_seed(),
			"rarity": rarity,
			"card_id": card_id,
			"discovered_at": Time.get_unix_time_from_system(),
		}
		_save_collection()
		collection_changed.emit()
	# Сервер — источник правды по копиям: без перечитывания счётчик в UI
	# остался бы вчерашним до следующего запуска.
	if _last_device_id != "":
		request_collection(_last_device_id)
	craft_completed.emit(craft_id, rarity, llm_name)


## Крафт из кэша ежедневных по id (копия); пустой каркас, если уже ротирован.
func _daily_craft_by_id(craft_id: String) -> Dictionary:
	for c in _daily_crafts:
		if str((c as Dictionary).get("id", "")) == craft_id:
			return (c as Dictionary).duplicate(true)
	return {"id": craft_id, "ingredients": [], "ether_cost": 0,
		"rarity": "common", "llm_name": "", "is_chromatic": false,
		"card_id": "", "set": "", "process": "", "stage": "",
		"object_type": "object", "seed": 0, "fallback_name": ""}


## Кэш ежедневных крафтов на диске (для офлайн-режима).
func _save_daily_cache() -> void:
	var f := FileAccess.open(DAILY_CACHE_FILE, FileAccess.WRITE)
	if f == null:
		return
	var data := {"day": _daily_day, "crafts": _daily_crafts, "offer_hash": _daily_offer_hash}
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
		_daily_offer_hash = str(parsed.get("offer_hash", ""))


func _today_string() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]
