# One-shot промпт №2 — «Первооткрытия и серверный слой» (для GPT Astra)

> Этот файл **самодостаточен**: доступа к репозиторию у тебя не будет — весь нужный контекст встроен ниже.
> Отправь файл целиком как единственное вложение, ответь кодом в чат блоками.

## Роль
Ты — архитектор фичи «живого мира» для игры-алхимии «Петля алхимика» (прототип, Godot 4.7, GDScript). Игра — Little Alchemy-подобная: 4 стихии, варка пар в котле, сеть рецептов, локальный офлайн-прогресс. Сейчас **сервера нет вообще** — нужен полный проект серверного слоя «первооткрытий».

## Игровые правила (факты; используй в расчётах и текстах)
- Варка стоит 10 эфира; неудача возвращает 1 эфир; эфир +1/с, кап 200; старт 100. Кап, скорость регенерации, время варки и бонус добычи игрок улучшает за эфир (четыре апгрейда, открываются вместе с веществами), поэтому в расчётах времени не полагайся на жёсткие 1.2 с.
- Локальный словарь: `ITEMS[id] = {"name": русское_имя, "color": "#hex"}`; пара ингредиентов симметрична; рецепт уникален на пару.
- Сейчас неизвестная пара даёт «Туман рассеялся…» (неудача, возврат 1 эфира). Вкладка «Мир» в UI — заглушка-текст «ОФФЛАЙН-ПРОТОТИП… глобальные первооткрытия с авторством и «живой пул» появятся с сервером».
- Формат данных (текущий фрагмент из файла main.gd; всего 54 вещества и 50 рецептов):

```gdscript
const ITEMS := {
	"fire": {"name": "Огонь", "color": "#ff936b"},
	"water": {"name": "Вода", "color": "#71bfff"},
	"earth": {"name": "Земля", "color": "#c4a47c"},
	"air": {"name": "Воздух", "color": "#cee8ef"},
	"steam": {"name": "Пар", "color": "#c4cfe5"},
	"stone": {"name": "Камень", "color": "#a6a6bb"},
	"clay": {"name": "Глина", "color": "#d2785f"},
	"dust": {"name": "Пыль", "color": "#ddd0a2"},
	"spark": {"name": "Искра", "color": "#ffe08a"},
	"mist": {"name": "Туман", "color": "#acc8e4"},
	"brick": {"name": "Кирпич", "color": "#a05242"},
	"sand": {"name": "Песок", "color": "#f0d499"},
	"plant": {"name": "Росток", "color": "#96d691"},
	"cloud": {"name": "Облако", "color": "#8cb0d0"},
	"ice": {"name": "Лёд", "color": "#a8e8ff"},
	"mountain": {"name": "Гора", "color": "#877864"},
	"mud": {"name": "Грязь", "color": "#6e4628"},
	"metal": {"name": "Металл", "color": "#7896be"},
	"life": {"name": "Жизнь", "color": "#4fd06f"},
	"smoke": {"name": "Дым", "color": "#a0a3aa"},
	"lava": {"name": "Лава", "color": "#f0561e"},
	"glass": {"name": "Стекло", "color": "#93e2d3"},
	"sky": {"name": "Небо", "color": "#64a8e8"},
	"rain": {"name": "Дождь", "color": "#3f74c6"},
	"storm": {"name": "Гроза", "color": "#47536b"},
	"hail": {"name": "Град", "color": "#b9dcef"},
	"snow": {"name": "Снег", "color": "#f4fafd"},
	"volcano": {"name": "Вулкан", "color": "#8c422e"},
	"obsidian": {"name": "Обсидиан", "color": "#383248"},
	"magma": {"name": "Магма", "color": "#b23b2e"},
	"ash": {"name": "Пепел", "color": "#b4b8c0"},
	"gold": {"name": "Золото", "color": "#c69624"},
	"swamp": {"name": "Болото", "color": "#548036"},
	"fish": {"name": "Рыба", "color": "#40aac8"},
	"bird": {"name": "Птица", "color": "#5d97d8"},
	"beast": {"name": "Зверь", "color": "#a06a3c"},
	"person": {"name": "Человек", "color": "#eeaa8c"},
	"seed": {"name": "Семя", "color": "#aa8246"},
	"grass": {"name": "Трава", "color": "#96d646"},
	"mushroom": {"name": "Гриб", "color": "#b26d5f"},
	"lightning": {"name": "Молния", "color": "#f5e13b"},
	"tornado": {"name": "Смерч", "color": "#8d939e"},
	"tool": {"name": "Инструмент", "color": "#77828c"},
	"tree": {"name": "Дерево", "color": "#4e9150"},
	"sun": {"name": "Солнце", "color": "#ffd21f"},
	"crystal": {"name": "Кристалл", "color": "#cbbdff"},
	"sandstorm": {"name": "Песчаная буря", "color": "#d4783c"},
	"forest": {"name": "Лес", "color": "#106e2d"},
	"wood": {"name": "Древесина", "color": "#d0a454"},
	"flower": {"name": "Цветок", "color": "#ef7fb4"},
	"rainbow": {"name": "Радуга", "color": "#b96ad4"},
	"desert": {"name": "Пустыня", "color": "#e2b666"},
	"boat": {"name": "Лодка", "color": "#965434"},
	"coal": {"name": "Уголь", "color": "#555860"},
}```

```gdscript
const RECIPES := [
	{"a": "fire", "b": "water", "out": "steam"},
	{"a": "earth", "b": "fire", "out": "stone"},
	{"a": "earth", "b": "water", "out": "clay"},
	{"a": "air", "b": "earth", "out": "dust"},
	{"a": "air", "b": "fire", "out": "spark"},
	{"a": "air", "b": "water", "out": "mist"},
	{"a": "clay", "b": "fire", "out": "brick"},
	{"a": "air", "b": "stone", "out": "sand"},
	{"a": "clay", "b": "water", "out": "plant"},
	{"a": "steam", "b": "air", "out": "cloud"},
	{"a": "stone", "b": "water", "out": "ice"},
	{"a": "stone", "b": "earth", "out": "mountain"},
	{"a": "mist", "b": "earth", "out": "mud"},
	{"a": "stone", "b": "spark", "out": "metal"},
	{"a": "spark", "b": "water", "out": "life"},
	{"a": "fire", "b": "dust", "out": "smoke"},
	{"a": "stone", "b": "fire", "out": "lava"},
	{"a": "fire", "b": "sand", "out": "glass"},
	{"a": "cloud", "b": "air", "out": "sky"},
	{"a": "cloud", "b": "water", "out": "rain"},
	{"a": "cloud", "b": "spark", "out": "storm"},
	{"a": "cloud", "b": "ice", "out": "hail"},
	{"a": "ice", "b": "air", "out": "snow"},
	{"a": "mountain", "b": "fire", "out": "volcano"},
	{"a": "lava", "b": "water", "out": "obsidian"},
	{"a": "lava", "b": "earth", "out": "magma"},
	{"a": "lava", "b": "air", "out": "ash"},
	{"a": "metal", "b": "fire", "out": "gold"},
	{"a": "mud", "b": "plant", "out": "swamp"},
	{"a": "life", "b": "water", "out": "fish"},
	{"a": "life", "b": "air", "out": "bird"},
	{"a": "life", "b": "earth", "out": "beast"},
	{"a": "life", "b": "clay", "out": "person"},
	{"a": "plant", "b": "dust", "out": "seed"},
	{"a": "earth", "b": "plant", "out": "grass"},
	{"a": "storm", "b": "air", "out": "lightning"},
	{"a": "storm", "b": "dust", "out": "tornado"},
	{"a": "person", "b": "stone", "out": "tool"},
	{"a": "seed", "b": "earth", "out": "tree"},
	{"a": "sky", "b": "fire", "out": "sun"},
	{"a": "glass", "b": "stone", "out": "crystal"},
	{"a": "sand", "b": "storm", "out": "sandstorm"},
	{"a": "swamp", "b": "plant", "out": "mushroom"},
	{"a": "tree", "b": "plant", "out": "forest"},
	{"a": "tree", "b": "stone", "out": "wood"},
	{"a": "sun", "b": "plant", "out": "flower"},
	{"a": "rain", "b": "sun", "out": "rainbow"},
	{"a": "sand", "b": "sun", "out": "desert"},
	{"a": "wood", "b": "water", "out": "boat"},
	{"a": "wood", "b": "fire", "out": "coal"},
]```

## Код варки, с которым интегрируется фича (из main.gd, актуальный)

```gdscript
func _brew() -> void:
	if not _can_brew():
		if selected.size() != 2:
			status_text = "Положи в лунки два ингредиента."
		elif ether < BREW_COST:
			status_text = "Не хватает эфира. Подожди — он восстанавливается."
		return
	var a := selected[0]
	var b := selected[1]
	if not _has_ingredients(a, b):
		status_text = "Не хватает ингредиентов для этой пары."
		_refresh()
		return
	brewing = true
	brew_elapsed = 0.0
	if _progress != null:
		_progress.value = 0.0
	status_text = "Котёл светится. Туман собирается над водой…"
	Sfx.draft_open()
	_refresh()
	await get_tree().create_timer(BREW_SECONDS).timeout

	inventory[a] = int(inventory[a]) - 1
	inventory[b] = int(inventory[b]) - 1
	ether -= BREW_COST
	attempts += 1
	var recipe := _find_recipe(a, b)
	if recipe.is_empty():
		ether = mini(MAX_ETHER, ether + FAILURE_REFUND)
		status_text = "Туман рассеялся… Возвращён 1 эфир (10%)."
		Sfx.error()
		Input.vibrate_handheld(20)
		if _cauldron != null:
			_cauldron.trigger_flash(Color(0.55, 0.6, 0.68))
	else:
		var key := _pair_key(a, b)
		var output := String(recipe["out"])
		var newly_learned := not known_recipes.has(key)
		known_recipes[key] = true
		inventory[output] = int(inventory.get(output, 0)) + 1
		successes += 1
		if newly_learned:
			if _auto:
				_auto_new.append(output)
				status_text = "…открыт рецепт: %s" % _item_name(output)
			else:
				status_text = "НОВЫЙ РЕЦЕПТ: %s!" % _item_name(output)
				Input.vibrate_handheld(45)
				if _cauldron != null:
					_cauldron.trigger_flash(_item_colors.get(output, Color.WHITE))
				_show_discovery_popup(output, a, b)
		else:
			status_text = "Успех: %s +1." % _item_name(output)
			if _cauldron != null:
				_cauldron.trigger_flash(_item_colors.get(output, Color.WHITE))
			if not _auto:
				Sfx.divide()
				Input.vibrate_handheld(20)
				_floater_at(_cauldron.get_global_rect().get_center(), "+%s" % _item_name(output),
					_item_colors.get(output, Color.WHITE))
	selected.clear()
	_slot_a.set_slot("", Color.WHITE)
	_slot_b.set_slot("", Color.WHITE)
	brewing = false
	if _progress != null:
		_progress.value = 100.0
	_refresh()
	_save_game()
```

Смысл: `_brew()` вызывается после того, как игрок положил 2 вещества в лунки; при успехе — инвентарь/рецепты обновляются, при первом открытии рецепта — карточка. Плюс в проекте есть **автоварка**: игрок тапает рецепт, планировщик считает цепочку и варит подряд; в цепочке могут открываться новые рецепты.

## Задача

### Часть А — механика «пары-кандидаты» (спроектировать и описать)
1. Правило, когда локальная варка неизвестной пары становится **кандидатом на первооткрытие**: (а) оба ингредиента открыты игроком; (б) пара X+X допустима как кандидат; (в) как клиент отличает «просто неудачу» от кандидата без спама сервера (например, «шанс тумана» на клиенте или отложенный запрос).
2. Жизненный цикл: кандидат → `brew-check` → сервер: если пара уже в глобальной таблице — вернуть существующий элемент (кто открыл первым — автор); если нет — атомарно сгенерировать и **опубликовать новый элемент**, вернуть карточку первооткрытия автору.
3. Генерация вещества (детерминированная): русское имя из морфем/тематики родителей с проверкой уникальности (при коллизии — суффикс-счётчик); латинский слаг id; цвет = детерминированная смесь цветов родителей, отстоящая от обоих; слой = max(слои родителей)+1; категория = по категориям родителей.
4. Анти-коллизии: повторное «открытие» той же пары вторым игроком = не новое вещество; **race condition** (два игрока, одна пара, одновременно) — предложи решение (серверная блокировка/очередь по ключу пары/таблица pending с уникальным индексом).
5. Авторство: ник игрока с клиента; хранить author, timestamp, seq.

### Часть Б — референс-сервер
1. Стек: **Python 3 + FastAPI + uvicorn + SQLite** (без Docker, лёгкий VPS). Порт 8080.
2. Схема БД + SQL: `elements(id, slug UNIQUE, name, color, layer, category, author, created_at)`, `recipes(pair_key UNIQUE, a, b, out_id, discoverer, created_at)`, `players(nick, device_id UNIQUE)`. Индексы.
3. Эндпоинты (метод/путь/тело/ответ/ошибки + curl): `POST /api/brew-check`, `POST /api/discover` (идемпотентно по pair_key), `GET /api/world` (пагинация), `GET /api/hall-of-fame`, `GET /api/health`.
4. **Полный код**: `server.py` (один файл) + `schema.sql` + `requirements.txt` + README: генератор имён (списки морфем по категориям родителей, кириллица), генератор цвета (формула, с проверкой различимости), обработка коллизий, блокировка пары, логирование. Только FastAPI/uvicorn + стандартная библиотека.
5. **GDScript-клиент**: `net.gd` — autoload с HTTPRequest; методы `check_pair(a,b)`, `discover(a,b)`, `world()`, таймаут ~4 с; `SERVER_URL` константой; при недоступности сети — поведение ровно как сейчас (туман + возврат 1 эфира). Дай **готовый код net.gd** и точную инструкцию, какие ~15 строк в каком месте `_brew()` заменить (покажи старый фрагмент и новый фрагмент), чтобы после «тумана» клиент слал `brew-check` и, если сервер ответил новым элементом, показывал карточку «ПЕРВООТКРЫТИЕ» с ником автора и добавлял элемент в игру (в ITEMS на клиенте элемент появляется динамически — в игре есть автоварка, планировщик читает RECIPES; добавь пояснение, что серверные открытия хранятся в отдельном local JSON рядом с сейвом, а в RECIPES константу не вшиваются).
6. Демо-сценарий: два «игрока», два клиента/сейва, ожидаемый лог.

### Часть В — тесты (pytest)
`server/tests/`: известная пара; новая пара открывается 1 раз; второй игрок получает того же автора; race: два параллельных запроса на одну пару → один элемент/автор; уникальность имён; слаг-уникальность; оффлайн-клиент (мок таймаута → фолбэк «туман»); hall-of-fame порядок.

## Формат ответа (код в чат, блоками)
1. `spec.md` (текстом, ~2–3 стр.): механика А + API Б.
2. `schema.sql`, `server.py`, `requirements.txt`, `README-server.md` — полный код.
3. `net.gd` + дифф-фрагмент для `_brew()` (старое → новое).
4. `tests/` — pytest-файлы.

## Критерии приёмки
- У меня: `pip install -r requirements.txt` → `uvicorn server:app` поднимается → pytest зелёный.
- Два параллельных `brew-check` одной новой пары → один результат, один автор.
- Клиент без сети полностью повторяет текущий офлайн-геймплей (никаких зависаний UI).
- JSON-ответ `GET /api/world` ложится на сетку орбов вкладки «Мир» (поля name/color достаточно).
