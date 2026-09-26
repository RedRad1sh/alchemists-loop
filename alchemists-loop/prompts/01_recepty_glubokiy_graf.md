# One-shot промпт №1 — «Глубокий граф рецептов» (для GPT Astra)

> Этот файл **самодостаточен**: доступ к репозиторию у тебя не будет, весь нужный контекст встроен ниже.
> Отправь этот файл целиком модели как единственное вложение и попроси ответить кодом в чат.

## Роль
Ты — гейм-дизайнер и GDScript-разработчик игры «Петля алхимика» (Little Alchemy-подобный прототип, Godot 4.7, GDScript, портрет 540×960, UI строится кодом). Проект уже работает: цветные «орбы» веществ, drag&drop в котёл, варка, **автоварка по цепочке** (игрок тапает рецепт — игра сама рассчитывает, сколько базовых стихий нужно, и варит последовательность, эфир −10 за варку, регенерация +1/с, кап 200; есть покупки за эфир — поток эфира, ёмкость, скороварка, щедрые источники — и «судьбоносные» вкладки-режимы: Линза (открывает случайный известный рецепт за 20 эфира), Родник (капля выбранной стихии раз в 6 с), Верстак (подмастерье сам варит выбранное вещество каждые 8 с). Улучшения и режимы открываются вместе с новыми веществами, есть мягкая подсказка «Намёк» за 8 эфира (называет только одно вещество с неоткрытой парой). Панель с источниками и кнопкой «ВАРИТЬ» закреплена внизу экрана.

## Задача
Расширить набор с **54 веществ / 50 рецептов** до **120+ веществ / 150–200 рецептов**, не ломая код, UI и автоварку.

## Контекст (это — всё, что нужно знать о данных)

Игра хранит данные в двух константах GDScript (файл main.gd). **Текущее содержимое**:

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

Базовые стихии: `const BASE_IDS := ["fire", "water", "earth", "air"]`.

### Как данные используются (договорённости, не менять)
- `ITEMS`: словарь `id -> {"name": имя_русское_существительное_им_падеж, "color": hex}`. **Порядок ключей = порядок показа в инвентаре** (сетка 7 колонок): родители раньше детей.
- `RECIPES`: массив `{"a","b","out"}`; пара **симметрична** (игра сортирует ключом `_pair_key`, «a+b» ≡ «b+a»); пара уникальна; нет пар вида «X+X»; `out` не равен `a`/`b`.
- Каждый элемент, кроме стихий, появляется в инвентаре только после первой варки (рецепт считается «открытым игроку»). Рецепты, которые игрок ещё не открыл, в книге не показываются, но **автоварка умеет открывать их по пути** — поэтому граф должен позволять каскадные цепочки.
- Существует **планировщик автоварки**: выбирает для каждого вещества самый дешёвый (по числу базовых стихий) известный рецепт, считает дефицит баз, варит «снизу вверх» по слоям (дети раньше родителей). **Граф обязан быть ацикличным** (слой ребёнка строго больше слоя родителя), иначе планировщик зависнет (у него есть защита, но лучше без циклов).
- Селфтест в проекте проверяет: цвета парсятся; все id рецептов существуют; пары уникальны; пар «X+X» нет; достижимость всех веществ из стихий (BFS); слои монотонны. Он будет обновлён по твоим результатам — ниже есть шаблон того, как тесты выглядят сейчас (см. раздел «Тесты»).

### Как рисуются вещества (глифы)
Орб рисует тело-шарик цветом `ITEMS[id].color` и вызывает статический `ElementGlyphs.draw(canvas, glyph_id, center, radius, color)`.
В `element_glyphs.gd` **уже есть** ручные глифы для старых id и процедурный фолбэк `_proc` для остальных: форма выбирается хешем id (`id.hash()`), поэтому у одного вещества форма стабильна между запусками. Ниже — текущая точка входа и фолбэк (сокращённо, без 14 ручных форм):

```gdscript
static func draw(c: CanvasItem, glyph: String, center: Vector2, r: float, col: Color) -> void:
	match glyph:
		"fire": _flame(c, center, r, col)
		"water": _drop(c, center, r, col)
		"earth": _mountain(c, center, r, col)
		"air": _wind(c, center, r, col)
		"steam": _steam(c, center, r, col)
		"stone": _stone(c, center, r, col)
		"clay": _blob(c, center, r, col)
		"dust": _dust(c, center, r, col)
		"spark": _spark(c, center, r, col)
		"mist": _mist(c, center, r, col)
		"brick": _brick(c, center, r, col)
		"sand": _sand(c, center, r, col)
		"glass": _glass(c, center, r, col)
		"plant": _leaf(c, center, r, col)
		_: _proc(c, glyph, center, r, col)
```

```gdscript
# Простая замкнутая «линза» без дублирующихся вершин — полигон всегда триангулируется.
static func _lens_shape(o: Vector2, r: float, half_h: float, x0: float, x1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 7
	for k in n + 1:
		var t := float(k) / float(n)
		pts.append(o + Vector2(lerpf(x0, x1, t), -sin(t * PI) * r * half_h))
	for k in range(n - 1, 0, -1):
		var t := float(k) / float(n)
		pts.append(o + Vector2(lerpf(x0, x1, t), sin(t * PI) * r * half_h))
	return pts

static func _leaf(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(_lens_shape(o, r, 0.30, -r * 0.7, r * 0.8), col)
	c.draw_polyline(PackedVector2Array([o + Vector2(-r * 0.6, 0), o + Vector2(r * 0.75, 0)]),
		Color(col.r, col.g, col.b, 0.7), 1.8)

static func _dot(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o, r * 0.5, col)

# ---------- процедурные эмблемы для новых веществ (по стабильному хешу id) ----------
# Каждая из форм — простой примитив; «семейство» выбирает хеш id, поэтому у одного
# id форма всегда одинаковая между запусками.

static func _proc(c: CanvasItem, id: String, o: Vector2, r: float, col: Color) -> void:
	var h := id.hash()
	var form := posmod(h, 6)
	var rot := float(posmod(h >> 3, 360))
	var sy := 1.0 + 0.2 * (float(posmod(h >> 5, 10)) - 5.0) / 5.0  # лёгкое сплющивание
	c.draw_set_transform(o, deg_to_rad(rot), Vector2(1.0, sy))
	match form:
		0: _gem(c, Vector2.ZERO, r, col)                # кристалл/ромб
		1: _sparkle(c, Vector2.ZERO, r, col)            # звезда-искра
		2: _orb3(c, Vector2.ZERO, r, col)               # клубок/кластер
		3: _leafblade(c, Vector2.ZERO, r, col)          # лезвие/лист
		4: _polyrock(c, Vector2.ZERO, r, col)           # камень-многоугольник
		5: _wave(c, Vector2.ZERO, r, col)               # волна/струя
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

### Как выглядят тесты (сейчас в main.gd, селфтест `--selftest`)

```gdscript
const BASE_IDS := ["fire", "water", "earth", "air"]
# ...проверки: парсинг цветов; симметрия _pair_key; все рецепты валидны;
#     рецепты уникальны (RECIPES.size() == 50); поиск рецепта; стартовое состояние;
#     граф: «graph layers settle», «graph monotonic layers», «graph reachable all»;
#     варка steam (расход 10, возврат 1 при неудаче); планировщик автоварки...
#     (для новых данных они будут переписаны под «граф достижим», «слои монотонны»)
```

## Требования к контенту
1. **120+ веществ**, включая все 54 текущих (id/имена/цвета сохранить дословно из контекста выше).
2. **100% достижимость** из стихий (BFS), граф ацикличен, слои монотонны.
3. **Валидность**: id — латинские слаги; русские имена уникальны; цвета — уникальные hex; смысловая связность (результат логичен для пары); соседние по дереву и «братья» одного слоя не должны быть неразличимы по цвету.
4. **Слои и порядок**: ITEMS отсортированы по слоям (стихии → слой 1 → слой 2…); RECIPES отсортированы по слою результата (для естественного порядка книги рецептов). Возле сложных рецептов допускаются `# L3`-комментарии.
5. **5–6 семейств**: огонь/лава/энергия, вода/лёд/холод, земля/минералы/металлы, воздух/погода, жизнь/растения/животные, стекло/песок/ремесло. Кроссоверы семейств — редкие и «вау».
6. Стартовые рецепты игрока (открыты сразу): Огонь+Вода→Пар, Земля+Огонь→Камень — сохранить.

## Формат ответа (только код, в чат, без пояснений «как это работает»)
1. **Блок A**: полный `const ITEMS := {…}` для замены.
2. **Блок B**: полный `const RECIPES := […]` для замены.
3. **Блок C**: полный файл `element_glyphs.gd` (существующие 14 веток + процедурный фолбэк).
4. **Блок D**: две функции-проверки на GDScript, которые я вставлю в селфтест: `reachable_and_acyclic()` и `layer_monotonic()` (возвращают bool), плюс список `EXPECTED_COUNTS = {"items": N, "recipes": M, "layers": K}`.

## Критерии приёмки (проверю у себя после вставки)
- Игра запускается, все орбы имеют цвета и глифы (никаких серых «точек»-заглушек у новых веществ).
- BFS из 4 стихий достигает всех 120+; слой каждого ребёнка > слоя родителей.
- Автоварка строит цепочки глубиной ≥4 (например: Песок+Огонь→Стекло + ещё 2–3 шага ниже) и корректно тратит базовые.
- Рецепты уникальны, пар «X+X» нет, русские имена и цвета уникальны.
