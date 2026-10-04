Данный класс `Online` представляет собой мощный, но очень перегруженный «God Object» (Божественный объект). Он отвечает за сетевые запросы, синхронизацию состояний, построение UI, логику QTE-событий, парсинг данных и управление инвентарем. 



Код написан грамотно, с отличным документированием (видны ссылки на таски вроде U11, T14), но его можно значительно улучшить с точки зрения \*\*архитектуры, производительности и идиоматики Godot 4\*\*.



Ниже приведены конкретные рекомендации по улучшению, разбитые по категориям.



\---



\### 1. Архитектура и Разделение Ответственности (SRP)



Самая большая проблема класса — он делает слишком много. Его стоит разбить на несколько узкоспециализированных классов.



\*   \*\*Выделение UI в отдельные сцены (`.tscn`):\*\*

&#x20;   Методы вроде `\_build\_rating\_page` или `\_build\_event\_qte` создают UI кодом. Это затрудняет верстку и поддержку.

&#x20;   \*   \*Решение:\* Создайте `RatingPage.tscn`, `WorldGrid.tscn`, `EventQTE.tscn`. В коде просто делайте `var qte = preload("res://ui/event\_qte.tscn").instantiate()`. Это позволит дизайнерам (или вам) настраивать цвета, отступы и шрифты в редакторе, а не хардкодить `Color(1.0, 0.85, 0.42)`.

\*   \*\*Разделение на `OnlineNetwork` и `OnlineUI`:\*\*

&#x20;   \*   `OnlineNetwork` (текущий `Online`): управляет `\_pending\_requests`, `\_register\_pending\_pair`, `\_on\_net\_...` (обработчики ответов).

&#x20;   \*   `OnlineUI`: слушает сигналы от `OnlineNetwork` (например, `signal rating\_received(data)`) и обновляет `\_rating\_list`, `\_world\_grid`.

\*   \*\*Инкапсуляция логики Экспериментов:\*\*

&#x20;   Логика `\_start\_experiment`, `\_resume\_pending\_experiment`, `\_tick\_pending\_experiment`, `\_experiment\_outcome` очень сложна. Её стоит вынести в отдельный класс `ExperimentManager`, который будет взаимодействовать с `Online` через сигналы.



\### 2. Godot-специфичные улучшения



\*   \*\*Использование `CanvasLayer` для QTE:\*\*

&#x20;   Сейчас `\_event\_qte` — это `Control` с `z\_index = 12`. Это хрупкое решение. Если появится попап с `z\_index = 15`, QTE перекроется.

&#x20;   \*   \*Решение:\* Замените `\_event\_qte = Control.new()` на `CanvasLayer.new()`. `CanvasLayer` рисует поверх всего независимо от `z\_index` других контролов (отлично подходит для глобальных событий).

\*   \*\*Отказ от ручного тиканья в пользу `Timer`:\*\*

&#x20;   Метод `\_event\_tick(delta)` и переменные `\_event\_clock`, `\_event\_left`, `\_event\_t`, `\_resume\_experiment\_deadline` работают через ручной подсчет `delta`.

&#x20;   \*   \*Решение:\* Используйте узлы `Timer`.

&#x20;   ```gdscript

&#x20;   var \_event\_spawn\_timer := Timer.new()

&#x20;   var \_event\_active\_timer := Timer.new()



&#x20;   func \_init\_timers():

&#x20;       \_event\_spawn\_timer.wait\_time = Game.EVENT\_INTERVAL

&#x20;       \_event\_spawn\_timer.timeout.connect(\_spawn\_event)

&#x20;       add\_child(\_event\_spawn\_timer)

&#x20;       \_event\_spawn\_timer.start()

&#x20;       

&#x20;       \_event\_active\_timer.one\_shot = true

&#x20;       \_event\_active\_timer.timeout.connect(\_on\_event\_timeout)

&#x20;   ```

&#x20;   Это избавит от необходимости вызывать `\_event\_tick` из `\_process` главного узла и сэкономит ресурсы.

\*   \*\*Очистка дочерних узлов:\*\*

&#x20;   Везде используется паттерн:

&#x20;   ```gdscript

&#x20;   for child in \_rating\_list.get\_children():

&#x20;       \_rating\_list.remove\_child(child)

&#x20;       child.queue\_free()

&#x20;   ```

&#x20;   В Godot 4 можно писать короче и чище (хотя `remove\_child` перед `queue\_free` не обязателен, `queue\_free` сам безопасно удалит узел из дерева):

&#x20;   ```gdscript

&#x20;   for child in \_rating\_list.get\_children():

&#x20;       child.queue\_free()

&#x20;   ```

&#x20;   Или вынести в хелпер: `g.\_clear\_container(\_rating\_list)`.



\### 3. Производительность и Структуры Данных



\*   \*\*Оптимизация поиска рецептов ($O(N) \\to O(1)$):\*\*

&#x20;   Метод `\_find\_recipe(a, b)` ищет рецепт перебором массива `g.RECIPES`. При большом количестве рецептов это будет тормозить.

&#x20;   \*   \*Решение:\* Используйте словарь для поиска по `pair\_key`.

&#x20;   ```gdscript

&#x20;   # Инициализируется один раз при загрузке

&#x20;   var \_recipes\_by\_key: Dictionary = {} 

&#x20;   # ...

&#x20;   func \_find\_recipe(a: String, b: String) -> Dictionary:

&#x20;       return \_recipes\_by\_key.get(g.\_pair\_key(a, b), {})

&#x20;   ```

\*   \*\*Перестроение сетки мира (`\_rebuild\_world\_grid`):\*\*

&#x20;   При каждом поиске или смене страницы вы уничтожаете и создаете заново до 100 сложных UI-элементов (HBox, VBox, Labels, Avatars).

&#x20;   \*   \*Решение:\* Реализуйте \*\*Object Pooling\*\* (пул объектов). Создайте 20-30 ячеек `WorldItemCell` при старте. При смене страницы просто меняйте им `visible = true/false` и обновляйте текст. Это уберет микро-фризы при вводе текста в поиск.

\*   \*\*Безопасная итерация по словарю при удалении:\*\*

&#x20;   В `\_prune\_pending\_requests` вы удаляете элементы из `\_pending\_requests` во время итерации. В Godot 4 итерация по `.keys()` создает копию массива ключей, поэтому это безопасно, но лучше делать это явно:

&#x20;   ```gdscript

&#x20;   var keys\_to\_remove := \[]

&#x20;   for key in \_pending\_requests.keys():

&#x20;       if now - int(\_pending\_requests\[key].get("at", now)) > PENDING\_TTL\_MSEC:

&#x20;           keys\_to\_remove.append(key)

&#x20;           

&#x20;   for key in keys\_to\_remove:

&#x20;       # логика возврата реагентов...

&#x20;       \_pending\_requests.erase(key)

&#x20;   ```



\### 4. Чистота кода и Типизация



\*   \*\*Избавление от "Магических чисел" и цветов:\*\*

&#x20;   В коде десятки раз повторяются цвета вроде `Color(0.6, 0.68, 0.75)` или размеры `Vector2(80, 36)`.

&#x20;   \*   \*Решение:\* Вынесите их в `const` в начале файла или в глобальный `Theme`.

&#x20;   ```gdscript

&#x20;   const COLOR\_TEXT\_PRIMARY := Color(0.95, 0.9, 0.75)

&#x20;   const COLOR\_TEXT\_SECONDARY := Color(0.55, 0.62, 0.68)

&#x20;   const BTN\_SIZE\_SMALL := Vector2(80, 36)

&#x20;   ```

\*   \*\*Безопасное получение данных из Dictionary:\*\*

&#x20;   В обработчиках `\_on\_net\_...` много повторяющегося кода:

&#x20;   ```gdscript

&#x20;   var disc\_raw = result.get("discovery", {})

&#x20;   if typeof(disc\_raw) == TYPE\_DICTIONARY:

&#x20;       disc = disc\_raw

&#x20;   ```

&#x20;   \*   \*Решение:\* Создайте типизированные Data-классы (DTO) или используйте более строгий парсинг.

&#x20;   ```gdscript

&#x20;   var disc: Dictionary = result.get("discovery", {}) as Dictionary

&#x20;   if disc.is\_empty(): return

&#x20;   ```

\*   \*\*Обработка ошибок сети:\*\*

&#x20;   Метод `\_on\_net\_pair\_result` обрабатывает статусы `if/elif/else`. Если сервер вернет новый статус, он упадет в `else` и выдаст непонятную ошибку. Лучше использовать `match`:

&#x20;   ```gdscript

&#x20;   match String(result.get("status", "")):

&#x20;       "not\_combinable": ...

&#x20;       "candidate": ...

&#x20;       "error", "timeout": ...

&#x20;       \_: # fallback

&#x20;   ```



\### 5. Улучшение UX и Логики



\*   \*\*Позиционирование QTE:\*\*

&#x20;   В `\_place\_event\_qte` есть риск, что при очень маленьком экране (например, на старых Android) `max\_x` или `max\_y` станут меньше `left`/`top`, и `randf\_range` выдаст ошибку или неверную позицию.

&#x20;   \*   \*Решение:\* Добавьте защиту.

&#x20;   ```gdscript

&#x20;   var max\_x := maxf(left, viewport\_size.x - card\_size.x - 14.0)

&#x20;   var max\_y := maxf(top, viewport\_size.y - card\_size.y - 164.0)

&#x20;   # Если экран слишком мал, просто ставим по центру

&#x20;   if max\_x < left: max\_x = left

&#x20;   if max\_y < top: max\_y = top

&#x20;   \_event\_card.position = Vector2(randf\_range(left, max\_x), randf\_range(top, max\_y))

&#x20;   ```

\*   \*\*Дедупликация кода в `\_on\_net\_pair\_result` и `\_on\_net\_discover\_result`:\*\*

&#x20;   Эти два метода содержат почти идентичную логику обработки `not\_combinable`, `created`, `known`.

&#x20;   \*   \*Решение:\* Вынесите общую логику применения результата в приватный метод `\_apply\_pair\_result(a, b, result\_data, is\_experiment)`.

\*   \*\*Гонки состояний при быстром клике:\*\*

&#x20;   Если игрок быстро нажмет "Эксперимент" дважды до того, как `\_pending\_requests` заполнится (из-за задержки кадра), может произойти дублирование.

&#x20;   \*   \*Решение:\* Убедитесь, что кнопка эксперимента блокируется (`disabled = true`) на клиенте сразу при нажатии, до вызова `\_start\_experiment`, и разблокируется только при получении ответа или таймаута.



\### 6. Рефакторинг `\_on\_net\_discover\_result` (Пример)



Этот метод слишком длинный (более 80 строк). Вот как его можно структурировать:



```gdscript

func \_on\_net\_discover\_result(pair\_key: String, result: Dictionary) -> void:

&#x20;   var entry := \_take\_pending\_pair(pair\_key)

&#x20;   if entry.is\_empty():

&#x20;       return # Дропаем дубликат



&#x20;   var a: String = entry\["a"]

&#x20;   var b: String = entry\["b"]

&#x20;   var is\_experiment: bool = entry\["experiment"]

&#x20;   var status: String = result.get("status", "")

&#x20;   

&#x20;   # 1. Обработка ошибок

&#x20;   if status == "not\_combinable":

&#x20;       \_handle\_not\_combinable(a, b, is\_experiment)

&#x20;       return

&#x20;       

&#x20;   if status not in \["created", "known"]:

&#x20;       \_handle\_unavailable(a, b, is\_experiment, result.get("message", ""))

&#x20;       return



&#x20;   # 2. Валидация данных

&#x20;   var disc: Dictionary = result.get("discovery", {})

&#x20;   if not \_validate\_discovery\_data(pair\_key, disc, a, b, is\_experiment):

&#x20;       return



&#x20;   # 3. Применение результата

&#x20;   \_apply\_discovery\_rewards(a, b, disc, status, is\_experiment, result)

```



\### Резюме: с чего начать?



1\.  \*\*Замените ручной тайминг (`\_event\_tick`) на узлы `Timer`.\*\* Это снизит нагрузку на CPU и уберет лишний код.

2\.  \*\*Замените `Control` с `z\_index` на `CanvasLayer` для QTE.\*\* Это решит потенциальные баги с перекрытием UI.

3\.  \*\*Оптимизируйте `\_find\_recipe` через `Dictionary`.\*\*

4\.  \*\*Вынесите магические цвета и размеры в `const`.\*\*

5\.  \*\*Разбейте `\_on\_net\_discover\_result` и `\_on\_net\_pair\_result` на более мелкие функции.\*\*



Этот код явно создавался в условиях жестких дедлайнов и частых изменений требований (о чем говорят комментарии про U11, T14). Выделение UI в сцены и логики в отдельные классы сделает код гораздо более устойчивым к дальнейшему расширению.


По этому фрагменту у онлайн-части уже хороший фундамент: сервер определяет результат открытий, есть обработка повторных открытий, защита от части устаревших ответов и возврат ресурсов при сбое эксперимента. Я бы сейчас не добавлял realtime-мультиплеер: для игры про открытия лучше подойдут надёжная асинхронная кооперация и понятная работа при плохой связи.



\## 1. Сначала укрепить сетевые запросы



Сейчас `\_pending\_requests` фактически допускает только один запрос с рецептом одновременно. Это безопасно для текущей схемы, но ограничивает игру и усложняет обработку задержек.



\- \*\*Добавить уникальный `request\_id`\*\*, а не связывать ответ только с `pair\_key`. Хранить для запроса тип, пару, время отправки и поколение сессии. Идентификатор должен возвращаться в ответе сервера.

\- \*\*Сделать настоящий таймаут.\*\* `PENDING\_TTL\_MSEC` задаёт срок жизни записи, но сам по себе не срабатывает по таймеру: `\_prune\_pending\_requests()` вызывается при регистрации или получении запроса/ответа. Если ответа нет, игрок может долго не понимать, что происходит.

\- После таймаута показывать понятное состояние, разрешать повтор, а для незавершённого эксперимента возвращать ресурсы ровно один раз.

\- В дальнейшем можно заменить один слот на очередь или небольшое ограниченное число параллельных запросов, сохранив запрет на дубли одной и той же пары.



Особенно важно различать повторные запросы одной пары. Если старый запрос истёк, а игрок отправил такую же пару снова, поздний ответ старого запроса может быть принят за ответ нового — у обоих будет один `pair\_key`.



Ещё один конкретный случай: в `\_on\_net\_discover\_result()` pending-запись снимается через `\_take\_pending\_pair()`, а затем при несовпадении `discovery.a/b` обработчик делает `return`. Если это был эксперимент, он может остаться незавершённым без ответа и без возврата ресурсов. В ветке ошибочного ответа стоит вызвать общий обработчик отказа: проверить `\_experiment\_pending\_matches(a, b)`, вернуть ресурсы, сохранить игру и показать сообщение.



Также полезно привязать ответы к экрану или загрузке:



\- `house\_get`: не менять попап, если игрок уже открыл дом другого пользователя;

\- загрузка мира: игнорировать страницы от предыдущего запроса, если началась новая загрузка;

\- сброс мира, удаление личности или выход: увеличивать поколение сессии и игнорировать ответы старого поколения.



\## 2. Улучшить состояние связи и офлайн-режим



Сейчас некоторые списки очищаются до проверки `result\["ok"]`. Например, рейтинг, события и зал славы при ошибке могут потерять уже показанные данные.



Лучше хранить последний удачный результат и показывать его со статусом вроде: \*\*«Показаны данные от 14:32 · сервер недоступен»\*\*. Для каждого раздела полезно иметь состояния «загрузка», «готово», «устаревшие данные» и «ошибка», а также кнопку повтора.



Ещё одна проблема — общий `status\_text`: задержавшийся ответ сети может перезаписать сообщение о варке или другом игровом действии. Для фоновых сетевых результатов лучше использовать небольшие уведомления или статус внутри конкретного раздела.



Для пагинации стоит проверять входные данные сервера: например, `per\_page > 0` и разумный предел общего числа страниц. Иначе ответ с `per\_page = 0` при `total > 0` может запустить бесконечную цепочку `Net.world(page + 1)`.



\## 3. Сделать часть активности действительно общей



Событие в `\_event\_tick()` сейчас персональное: таймер, случайный выбор и награда происходят на клиенте. Комментарий «глобальный» здесь описывает его положение поверх экранов, а не общий для всех игроков характер.



Есть два хороших варианта:



1\. Оставить событие локальным и явно обозначить его как личное.

2\. Сделать отдельные \*\*общие события мира\*\*: сервер выдаёт `event\_id`, время начала и окончания, общий прогресс, а при нажатии подтверждает участие и выдаёт награду.



Для второго варианта награда должна быть идемпотентной: повторный запрос одного события не должен выдавать её снова. То же относится к очкам рейтинга, наградам ежедневной цели и учёту посещений домика. Локальный `\_visit\_allowed()` удобен для интерфейса, но ограничение «раз в день» нужно проверять и на сервере — локальные данные можно очистить.



Уже имеющиеся зал славы, цепочки, цель дня, лента и домики дают основу для асинхронной кооперации:



\- общая недельная цель — например, открыть заданное число веществ определённой категории;

\- кликабельные события в ленте, ведущие к веществу или рецепту;

\- сезонный рейтинг с несколькими номинациями, а не только общим счётом;

\- гостевая книга или реакция на домик с серверным ограничением частоты.



Это даст ощущение общего мира без сложного realtime-мультиплеера.



\## 4. Подготовить каталог мира к росту



`\_on\_net\_world\_result()` последовательно загружает все страницы, а `\_world\_filtered\_ids()` затем сортирует весь `g.ITEMS` при каждом поиске. Пока база небольшая — это нормально. Когда открытий станет много, лучше:



\- загружать страницы по запросу, а не скачивать весь каталог;

\- перенести поиск по названию и автору на сервер;

\- хранить серверный каталог отдельно от базовых `g.ITEMS` и локального инвентаря;

\- кэшировать каталог с датой последнего обновления.



Сейчас серверные элементы и рецепты добавляются прямо в общие `g.ITEMS` и `g.RECIPES`. Разделение на «базовый каталог», «каталог мира» и «собранное игроком» упростит обновления, восстановление данных и поведение офлайн.



\## 5. Защитить конкурентные данные на сервере



Если очки рейтинга и награды важны, клиент не должен быть единственным источником истины. `device\_id` полезен как идентификатор установки, но не является надёжной аутентификацией. На сервере стоит проверять частоту запросов, уникальность наград, ограничения посещений и допустимость никнейма. Для анонимной игры это можно сделать без обязательной регистрации — например, через выдаваемый сервером токен установки.



\## Что делать первым



Я бы шёл в таком порядке:



1\. `request\_id`, таймауты и отмена запросов при сбросе сессии.

2\. Возврат ресурсов при некорректном ответе эксперимента.

3\. Защита от устаревших ответов для домиков и страниц мира.

4\. Кэширование последнего результата и состояния «сервер недоступен».

5\. Серверные общие события и кооперативная недельная цель.



Для проверки этих сценариев уже полезны имеющиеся тестовые точки вроде `\_netexperiment\_pair` и `\_run\_netbrew`: добавьте тесты на поздний ответ той же пары, дублированный ответ, сброс мира во время запроса, неправильные данные пагинации и ответы на домики, пришедшие не по порядку.


Полностью переписывать огромный `Online` не обязательно. Ниже — **практический UX-патч**, который можно встроить в текущий класс. Он добавляет:

- тосты вместо одной перегруженной строки статуса;
- индикатор сетевого ожидания;
- предупреждение перед QTE;
- безопасное позиционирование QTE;
- запрет QTE поверх модальных окон и ввода текста;
- адаптивные награды без бесполезного «Озарения»;
- анимации и вибрацию;
- цветовой таймер QTE.

---

## 1. Новые поля

Добавьте в начало `Online.gd`:

```gdscript
# ---------- UX layer ----------

enum NoticeKind {
	INFO,
	SUCCESS,
	WARNING,
	ERROR,
}

var _ux_layer: CanvasLayer = null
var _toast_stack: VBoxContainer = null

var _network_badge: PanelContainer = null
var _network_badge_label: Label = null
var _network_badge_spinner: Label = null
var _network_badge_t := 0.0

var _event_canvas: CanvasLayer = null
var _event_telegraphing := false
var _event_spawn_token := 0

const TOAST_INFO := Color("#6f8fa8")
const TOAST_SUCCESS := Color("#73c98b")
const TOAST_WARNING := Color("#e6a84a")
const TOAST_ERROR := Color("#dc6a6a")

const QTE_MARGIN_LEFT := 16.0
const QTE_MARGIN_RIGHT := 16.0
const QTE_MARGIN_TOP := 96.0
const QTE_MARGIN_BOTTOM := 120.0
const QTE_TELEGRAPH_TIME := 1.1
const QTE_PLACEMENT_ATTEMPTS := 24
```

---

## 2. Глобальный UX-слой

Вызывайте `_build_online_ux()` один раз после создания основного интерфейса.

```gdscript
func _build_online_ux() -> void:
	if _ux_layer != null:
		return

	_ux_layer = CanvasLayer.new()
	_ux_layer.name = "OnlineUXLayer"
	# Основные модальные окна рекомендуется держать на layer >= 30.
	_ux_layer.layer = 20
	g.add_child(_ux_layer)

	_build_toast_stack()
	_build_network_badge()
	_build_event_qte()
```

### Контейнер тостов

```gdscript
func _build_toast_stack() -> void:
	_toast_stack = VBoxContainer.new()
	_toast_stack.name = "OnlineToastStack"
	_toast_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_stack.offset_left = -360.0
	_toast_stack.offset_top = 78.0
	_toast_stack.offset_right = -16.0
	_toast_stack.offset_bottom = 520.0
	_toast_stack.add_theme_constant_override("separation", 8)
	_toast_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ux_layer.add_child(_toast_stack)
```

### Вывод тоста

```gdscript
func _toast(
		text: String,
		kind: NoticeKind = NoticeKind.INFO,
		duration := 3.0
) -> void:
	if text.strip_edges() == "":
		return

	if _toast_stack == null:
		_build_online_ux()

	var accent := TOAST_INFO
	match kind:
		NoticeKind.SUCCESS:
			accent = TOAST_SUCCESS
		NoticeKind.WARNING:
			accent = TOAST_WARNING
		NoticeKind.ERROR:
			accent = TOAST_ERROR

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 52)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate = Color(1, 1, 1, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.11, 0.97)
	style.border_color = accent
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#edf3f8"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	_toast_stack.add_child(panel)

	# Не даём уведомлениям заполнить весь экран.
	while _toast_stack.get_child_count() > 4:
		var oldest := _toast_stack.get_child(0)
		oldest.queue_free()

	var tween := g.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(panel, "position:x", -10.0, 0.18).from(16.0)

	var timer := g.get_tree().create_timer(duration)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(panel):
			return

		var hide_tween := g.create_tween()
		hide_tween.set_parallel(true)
		hide_tween.tween_property(panel, "modulate:a", 0.0, 0.2)
		hide_tween.tween_property(panel, "position:x", 20.0, 0.2)
		hide_tween.chain().tween_callback(panel.queue_free)
	, CONNECT_ONE_SHOT)
```

---

## 3. Индикатор сетевого ожидания

Игрок должен видеть, что эксперимент не завис, а ожидает сервер.

```gdscript
func _build_network_badge() -> void:
	_network_badge = PanelContainer.new()
	_network_badge.name = "NetworkPendingBadge"
	_network_badge.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_network_badge.offset_left = 24.0
	_network_badge.offset_top = 18.0
	_network_badge.offset_right = -24.0
	_network_badge.offset_bottom = 66.0
	_network_badge.visible = false
	_network_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.16, 0.96)
	style.border_color = Color(0.35, 0.66, 0.95, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	_network_badge.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_network_badge.add_child(row)

	_network_badge_spinner = Label.new()
	_network_badge_spinner.text = "◐"
	_network_badge_spinner.add_theme_font_size_override("font_size", 18)
	_network_badge_spinner.add_theme_color_override(
		"font_color",
		Color("#79baff")
	)
	row.add_child(_network_badge_spinner)

	_network_badge_label = Label.new()
	_network_badge_label.text = "Мир изучает сочетание…"
	_network_badge_label.add_theme_font_size_override("font_size", 14)
	_network_badge_label.add_theme_color_override(
		"font_color",
		Color("#dcecff")
	)
	row.add_child(_network_badge_label)

	_ux_layer.add_child(_network_badge)
```

### Управление индикатором

```gdscript
func _show_network_pending(is_experiment: bool) -> void:
	if _network_badge == null:
		_build_online_ux()

	_network_badge.visible = true
	_network_badge.modulate.a = 0.0
	_network_badge_label.text = (
		"Мир проводит эксперимент…"
		if is_experiment
		else "Мир проверяет сочетание…"
	)

	var tween := g.create_tween()
	tween.tween_property(_network_badge, "modulate:a", 1.0, 0.2)


func _hide_network_pending() -> void:
	if _network_badge == null or not _network_badge.visible:
		return

	var tween := g.create_tween()
	tween.tween_property(_network_badge, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func() -> void:
		if is_instance_valid(_network_badge):
			_network_badge.visible = false
	)


func _update_network_badge(delta: float) -> void:
	if _network_badge == null or not _network_badge.visible:
		return

	_network_badge_t += delta

	var frames := ["◐", "◓", "◑", "◒"]
	var index := int(_network_badge_t * 6.0) % frames.size()
	_network_badge_spinner.text = frames[index]

	if _pending_requests.is_empty():
		_hide_network_pending()
		return

	var key = _pending_requests.keys()[0]
	var entry: Dictionary = _pending_requests[key]
	var started_at := int(entry.get("at", Time.get_ticks_msec()))
	var elapsed := maxi(
		0,
		int((Time.get_ticks_msec() - started_at) / 1000)
	)

	var base := (
		"Мир проводит эксперимент"
		if bool(entry.get("experiment", false))
		else "Мир проверяет сочетание"
	)

	_network_badge_label.text = "%s · %d с" % [base, elapsed]
```

---

## 4. Интеграция с pending-запросами

Замените `_register_pending_pair()` на:

```gdscript
func _register_pending_pair(
		a: String,
		b: String,
		is_experiment: bool
) -> bool:
	if a == "" or b == "":
		return false

	_prune_pending_requests()

	if not _pending_requests.is_empty():
		return false

	_pending_requests[g._pair_key(a, b)] = {
		"a": a,
		"b": b,
		"experiment": is_experiment,
		"at": Time.get_ticks_msec(),
	}

	_show_network_pending(is_experiment)
	return true
```

Замените `_take_pending_pair()` на:

```gdscript
func _take_pending_pair(pair_key: String) -> Dictionary:
	_prune_pending_requests()

	if not _pending_requests.has(pair_key):
		return {}

	var entry: Dictionary = _pending_requests[pair_key]
	_pending_requests.erase(pair_key)

	if _pending_requests.is_empty():
		_hide_network_pending()

	return entry
```

В конце удаления просроченной записи внутри `_prune_pending_requests()` добавьте:

```gdscript
if _pending_requests.is_empty():
	_hide_network_pending()
```

А сообщение таймаута дополните тостом:

```gdscript
_toast(
	"Мир не ответил вовремя. Реагенты и эфир возвращены.",
	NoticeKind.WARNING,
	4.0
)
```

---

## 5. Улучшенный запуск эксперимента

Замените `_start_experiment()`:

```gdscript
func _start_experiment(a: String, b: String) -> bool:
	if not _net_enabled or not Net.is_available():
		var message := (
			"Эксперимент требует связи с миром. "
			+ "Новый элемент нельзя создать офлайн."
		)
		_set_status(message)
		_toast(message, NoticeKind.ERROR, 4.0)
		_haptic_error()
		Sfx.error()
		return false

	_prune_pending_requests()

	if not _pending_requests.is_empty():
		var message := (
			"Предыдущий запрос ещё обрабатывается. "
			+ "Дождись ответа мира."
		)
		_set_status(message)
		_toast(message, NoticeKind.WARNING, 3.0)
		_haptic_error()
		Sfx.error()
		return false

	if not g._engine._begin_experiment(a, b):
		return false

	if not _register_pending_pair(a, b, true):
		g._engine._finish_experiment_inputs(a, b, true)
		_toast(
			"Не удалось отправить эксперимент. Ресурсы возвращены.",
			NoticeKind.ERROR
		)
		return false

	Net.check_pair(a, b, _net_nick, _device_id, true)

	_set_status(
		"Эксперимент начат: %s + %s."
		% [_item_name(a), _item_name(b)]
	)
	_toast(
		"Эксперимент отправлен в мир",
		NoticeKind.INFO,
		2.5
	)
	_haptic_medium()

	g._saves._save_game()
	return true
```

---

## 6. QTE через отдельный CanvasLayer

В начале существующего `_build_event_qte()` замените создание корневого слоя:

```gdscript
func _build_event_qte() -> void:
	if _event_qte != null:
		return

	if _event_canvas == null:
		_event_canvas = CanvasLayer.new()
		_event_canvas.name = "WorldEventCanvas"
		# Ниже модальных окон, но выше основных страниц.
		_event_canvas.layer = 15
		g.add_child(_event_canvas)

	_event_qte = Control.new()
	_event_qte.name = "WorldEventQTE"
	_event_qte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_event_qte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_qte.visible = false
	_event_canvas.add_child(_event_qte)

	# Далее оставьте существующее создание _event_card, кнопки,
	# лейбла и ProgressBar.
```

Удалите у `_event_qte`:

```gdscript
_event_qte.z_as_relative = false
_event_qte.z_index = 12
g.add_child(_event_qte)
```

Потому что этим теперь управляет `CanvasLayer`.

---

## 7. Безопасное позиционирование QTE

Добавляйте группу `qte_exclusion` элементам, поверх которых QTE появляться не должен:

```gdscript
brew_button.add_to_group("qte_exclusion")
bottom_navigation.add_to_group("qte_exclusion")
cauldron.add_to_group("qte_exclusion")
```

Модальным окнам добавьте группу:

```gdscript
popup.add_to_group("modal_ui")
```

Теперь замените `_place_event_qte()`:

```gdscript
func _place_event_qte() -> void:
	if _event_qte == null or _event_card == null:
		return

	var viewport_rect := g.get_viewport().get_visible_rect()
	var card_size := _event_card.size

	if card_size.x <= 0.0 or card_size.y <= 0.0:
		card_size = _event_card.custom_minimum_size

	var min_pos := Vector2(
		QTE_MARGIN_LEFT,
		QTE_MARGIN_TOP
	)
	var max_pos := Vector2(
		viewport_rect.size.x - card_size.x - QTE_MARGIN_RIGHT,
		viewport_rect.size.y - card_size.y - QTE_MARGIN_BOTTOM
	)

	max_pos.x = maxf(max_pos.x, min_pos.x)
	max_pos.y = maxf(max_pos.y, min_pos.y)

	var blocked := _qte_blocked_rects()
	var fallback := Vector2(
		(viewport_rect.size.x - card_size.x) * 0.5,
		(viewport_rect.size.y - card_size.y) * 0.5
	)

	for _attempt in range(QTE_PLACEMENT_ATTEMPTS):
		var candidate := Vector2(
			randf_range(min_pos.x, max_pos.x),
			randf_range(min_pos.y, max_pos.y)
		)
		var candidate_rect := Rect2(candidate, card_size).grow(10.0)

		if not _rect_intersects_any(candidate_rect, blocked):
			_event_card.position = candidate
			return

	_event_card.position = fallback


func _qte_blocked_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []

	for node in g.get_tree().get_nodes_in_group("qte_exclusion"):
		if node is Control:
			var control := node as Control
			if control.is_visible_in_tree():
				result.append(control.get_global_rect().grow(12.0))

	# Не спавним событие прямо поверх поля ввода.
	var focus := g.get_viewport().gui_get_focus_owner()
	if focus is Control:
		result.append((focus as Control).get_global_rect().grow(20.0))

	return result


func _rect_intersects_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other):
			return true
	return false
```

---

## 8. Не запускать QTE в неудобный момент

```gdscript
func _can_spawn_event() -> bool:
	if _event_active or _event_telegraphing:
		return false

	var focus := g.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false

	for node in g.get_tree().get_nodes_in_group("modal_ui"):
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			return false

	return true
```

---

## 9. Умный выбор события

«Озарение» не должно выпадать, если открывать уже нечего.

```gdscript
func _choose_event_type() -> String:
	var available: Array[String] = []

	available.append("comet")

	if _random_opened_item() != "":
		available.append("gift")

	var recipes := g._pages._unrevealed_recipe_candidates()
	if not recipes.is_empty():
		available.append("insight")

	if available.is_empty():
		return "comet"

	return available[randi() % available.size()]
```

Можно сделать комету чуть более частой:

```gdscript
func _choose_event_type_weighted() -> String:
	var roll := randf()

	if roll < 0.50:
		return "comet"

	if roll < 0.78 and _random_opened_item() != "":
		return "gift"

	var recipes := g._pages._unrevealed_recipe_candidates()
	if not recipes.is_empty():
		return "insight"

	return "comet"
```

---

## 10. Предупреждение перед QTE

Замените `_spawn_event()`:

```gdscript
func _spawn_event() -> void:
	if not _can_spawn_event():
		# Не сбрасываем ожидание полностью: повторим попытку через несколько секунд.
		_event_clock = maxf(0.0, Game.EVENT_INTERVAL - 5.0)
		return

	_event_type = _choose_event_type_weighted()
	_event_telegraphing = true
	_event_spawn_token += 1

	var token := _event_spawn_token

	_place_event_qte()

	_event_qte.visible = true
	_event_card.visible = true
	_event_card.modulate = Color(1, 1, 1, 0)
	_event_card.scale = Vector2(0.72, 0.72)
	_event_card.pivot_offset = _event_card.size * 0.5

	_event_btn.disabled = true
	_event_btn.text = _event_symbol()

	if _event_label != null:
		_event_label.text = "Событие близко…"

	if _event_progress != null:
		_event_progress.value = 0.0

	Sfx.mystic()
	_haptic_light()

	var tween := g.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_event_card, "modulate:a", 1.0, 0.3)
	tween.tween_property(_event_card, "scale", Vector2.ONE, 0.35)

	var pulse := g.create_tween()
	pulse.set_loops(2)
	pulse.tween_property(
		_event_card,
		"modulate",
		Color(1.15, 1.05, 0.72, 1.0),
		0.22
	)
	pulse.tween_property(
		_event_card,
		"modulate",
		Color.WHITE,
		0.22
	)

	var timer := g.get_tree().create_timer(QTE_TELEGRAPH_TIME)
	timer.timeout.connect(
		_activate_event.bind(token),
		CONNECT_ONE_SHOT
	)


func _activate_event(token: int) -> void:
	if token != _event_spawn_token:
		return

	if not _event_telegraphing:
		return

	# Если за время предупреждения открылось модальное окно,
	# событие откладывается.
	if not _can_activate_telegraphed_event():
		_cancel_event_telegraph()
		_event_clock = maxf(0.0, Game.EVENT_INTERVAL - 5.0)
		return

	_event_telegraphing = false
	_event_active = true
	_event_left = Game.EVENT_WINDOW
	_event_t = 0.0

	_event_btn.disabled = false

	g._engine.status_text = "☄ %s" % _event_name()
	_toast(
		"Мировое событие: %s" % _event_name(),
		NoticeKind.INFO,
		2.5
	)

	_haptic_medium()
	_update_event_ui()


func _can_activate_telegraphed_event() -> bool:
	var focus := g.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false

	for node in g.get_tree().get_nodes_in_group("modal_ui"):
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			return false

	return true


func _cancel_event_telegraph() -> void:
	_event_spawn_token += 1
	_event_telegraphing = false
	_event_active = false

	if _event_qte != null:
		_event_qte.visible = false
```

Обратите внимание: `_can_spawn_event()` нельзя вызывать непосредственно из `_activate_event()`, потому что во время телеграфа `_event_telegraphing == true`. Поэтому используется отдельная проверка `_can_activate_telegraphed_event()`.

---

## 11. Новый тик событий

Замените `_event_tick()`:

```gdscript
func _event_tick(delta: float) -> void:
	_update_network_badge(delta)

	if _event_telegraphing:
		return

	if _event_active:
		_event_left -= delta

		if _event_left <= 0.0:
			_event_left = 0.0
			_event_active = false
			_event_clock = 0.0

			_set_status("Событие упущено.")
			_toast(
				"Событие упущено — следующее появится позже.",
				NoticeKind.WARNING,
				2.5
			)

			_update_event_ui()
			return

		_event_t -= delta
		if _event_t <= 0.0:
			_event_t = 0.08
			_update_event_ui()

		return

	_event_clock += delta

	if _event_clock >= Game.EVENT_INTERVAL:
		_event_clock = 0.0
		_spawn_event()
```

---

## 12. Улучшенный таймер QTE

Замените `_update_event_ui()`:

```gdscript
func _update_event_ui() -> void:
	if _event_qte == null or _event_btn == null:
		return

	if _event_telegraphing:
		_event_qte.visible = true
		_event_btn.disabled = true
		return

	if not _event_active:
		_event_qte.visible = false
		_event_btn.disabled = true

		if _event_progress != null:
			_event_progress.value = 0.0
		return

	_event_qte.visible = true
	_event_btn.disabled = false
	_event_btn.text = _event_symbol()

	var ratio := clampf(
		_event_left / maxf(Game.EVENT_WINDOW, 0.001),
		0.0,
		1.0
	)

	var urgency := Color("#ff5f56").lerp(
		Color("#ffd166"),
		ratio
	)

	_event_btn.add_theme_color_override("font_color", urgency)

	if _event_label != null:
		_event_label.text = "%.1f с" % _event_left
		_event_label.add_theme_color_override("font_color", urgency)

	if _event_progress != null:
		_event_progress.value = _event_left

		var fill := StyleBoxFlat.new()
		fill.bg_color = urgency
		fill.set_corner_radius_all(2)
		_event_progress.add_theme_stylebox_override("fill", fill)

	# В последнюю секунду пузырёк слегка пульсирует.
	if _event_left <= 1.0:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.02) * 0.05
		_event_card.scale = Vector2.ONE * pulse
	else:
		_event_card.scale = Vector2.ONE
```

---

## 13. Улучшенная обработка награды QTE

Замените `_on_event_tap()`:

```gdscript
func _on_event_tap() -> void:
	if not _event_active:
		return

	var reward_pos := _event_btn.get_global_rect().get_center()

	_event_active = false
	_event_clock = 0.0
	_event_spawn_token += 1

	_haptic_success()

	match _event_type:
		"comet":
			g._engine._grant_ether(25, "comet")

			_set_status("☄ Комета! +25 эфира.")
			_toast(
				"Кометный дождь: +25 эфира",
				NoticeKind.SUCCESS
			)
			_floater_at(
				reward_pos,
				"+25 ⚡",
				Color("#ffe36e")
			)

		"gift":
			var pick := _random_opened_item()

			if pick != "":
				g._engine.inventory[pick] = (
					int(g._engine.inventory.get(pick, 0)) + 1
				)

				_set_status(
					"✦ Дар тумана: %s +1."
					% _item_name(pick)
				)
				_toast(
					"Дар тумана: %s +1" % _item_name(pick),
					NoticeKind.SUCCESS
				)
				_floater_at(
					reward_pos,
					"+%s" % _item_name(pick),
					g._item_colors.get(pick, Color.WHITE)
				)
			else:
				# Никогда не оставляем игрока без награды.
				g._engine._grant_ether(15, "gift_fallback")
				_set_status("✦ Туман превратился в +15 эфира.")
				_toast(
					"Дар тумана: +15 эфира",
					NoticeKind.SUCCESS
				)

		"insight":
			var candidates := g._pages._unrevealed_recipe_candidates()

			if not candidates.is_empty():
				var recipe: Dictionary = candidates[
					randi() % candidates.size()
				]

				var a := String(recipe["a"])
				var b := String(recipe["b"])
				var out := String(recipe["out"])

				g._engine.known_recipes[g._pair_key(a, b)] = true

				_set_status(
					"✧ Озарение: %s + %s → %s!"
					% [
						_item_name(a),
						_item_name(b),
						_item_name(out),
					]
				)

				_toast(
					"Озарение открыло новый рецепт",
					NoticeKind.SUCCESS
				)

				g._present_popup(
					out,
					"Озарение открыло рецепт:\n%s + %s → %s"
					% [
						_item_name(a),
						_item_name(b),
						_item_name(out),
					]
				)
			else:
				# Fallback вместо бесполезного сообщения.
				g._engine._grant_ether(20, "insight_fallback")
				_set_status(
					"✧ Все доступные рецепты изучены: +20 эфира."
				)
				_toast(
					"Все рецепты изучены: +20 эфира",
					NoticeKind.SUCCESS
				)

	Sfx.divide()

	_update_event_ui()
	g._engine._refresh()
	g._saves._save_game()
```

---

## 14. Вибрация

```gdscript
func _haptic_light() -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(20)


func _haptic_medium() -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(45)


func _haptic_success() -> void:
	if not OS.has_feature("mobile"):
		return

	Input.vibrate_handheld(70)

	var timer := g.get_tree().create_timer(0.10)
	timer.timeout.connect(func() -> void:
		Input.vibrate_handheld(35)
	, CONNECT_ONE_SHOT)


func _haptic_error() -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(90)
```

Желательно добавить в настройки возможность отключить вибрацию:

```gdscript
func _haptics_enabled() -> bool:
	return bool(UserData.get_value("settings", "haptics", true))
```

И проверять её в методах выше.

---

## 15. Тосты для важных сетевых результатов

В `_experiment_outcome()` при первооткрытии:

```gdscript
if created:
	_toast(
		"Первый в мире: %s!" % _item_name(slug),
		NoticeKind.SUCCESS,
		5.0
	)
	_haptic_success()
```

При обычном открытии:

```gdscript
else:
	_toast(
		"Открыто новое вещество: %s" % _item_name(slug),
		NoticeKind.SUCCESS,
		3.5
	)
```

При `not_combinable`:

```gdscript
_toast(
	"%s и %s не сочетаются."
	% [_item_name(a), _item_name(b)],
	NoticeKind.WARNING,
	3.0
)
_haptic_error()
```

При сетевой ошибке:

```gdscript
_toast(
	"Мир временно недоступен. Ресурсы не потеряны.",
	NoticeKind.ERROR,
	4.0
)
```

При посещении домика:

```gdscript
func _on_net_house_visit_result(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		_toast(
			"Не удалось засвидетельствовать визит.",
			NoticeKind.WARNING
		)
		return

	_set_status("Визит засвидетельствован.")
	_toast(
		"Визит засвидетельствован",
		NoticeKind.SUCCESS,
		2.0
	)
```

---

## 16. Инициализация

После создания основного UI:

```gdscript
g._online._build_online_ux()
```

Либо добавьте публичный метод:

```gdscript
func initialize_ui() -> void:
	_build_online_ux()
```

И продолжайте вызывать существующий тик:

```gdscript
func _process(delta: float) -> void:
	g._online._event_tick(delta)
	g._online._tick_pending_experiment()
	g._online._tick_netexperiment()
```

---

### Что изменится для игрока

1. Сетевой запрос больше не выглядит как зависание.
2. Ошибки, награды и возвраты ресурсов невозможно пропустить.
3. QTE не возникает под пальцем, поверх котла или модального окна.
4. Перед событием есть звуковое и визуальное предупреждение.
5. Бесполезные награды автоматически заменяются эфиром.
6. Последняя секунда QTE читается через цвет и пульсацию.
7. На мобильном действия ощущаются тактильно.
8. Основная строка статуса остаётся журналом состояния, а важные события показываются отдельными тостами.