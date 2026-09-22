# Крафт и LLM-алхимия: Эксперимент + known frontier + resumable Производство

**Дата:** 16 сентября 2026
**Статус:** первая реализация включена в клиент и discovery-server; безопасная
миграция сохранений добавлена; расширенные сценарии покрыты headless selftest и
серверными тестами.

Этот документ является актуальным контрактом для переработки крафта. Старый
all-or-nothing автокрафт больше не является целевой моделью.

## 1. Решение в одном абзаце

- **Discovery** остаётся широким и дешёвым: известные локальные рецепты и
  серверный кэш не требуют LLM.
- **Эксперимент** — явный, платный и rate-limited путь для неизвестной пары
  из двух реагентов v1. Игрок подтверждает запрос; сервер является источником
  истины; при недоступном сервере неизвестный результат не выдумывается.
- **Производство** — глубокая, платная и возобновляемая задача `craft_job`.
  Известная длинная цепочка выполняется этапами и сохраняет промежуточные
  предметы, эфир и прогресс.
- **Known frontier** находит ближайший неизвестный узел вместо общей ошибки:
  игрок сразу видит пару и переходит в Эксперимент.
- После первого полного маршрута записывается **blueprint**. В текущей безопасной
  фазе он даёт детерминированный маршрут и конфигурируемую скидку 10% (`0.90`),
  но не создаёт бесплатные предметы и не увеличивает кап эфира.
- LLM не назначает статы, стоимость, кап, награды или другие экономические
  параметры. Она может вернуть семантический текст; сервер валидирует его и
  сам назначает категорию, слой, глиф-fallback и экономику.

## 2. Инварианты экономики и данных

| Инвариант | Контроль |
|---|---|
| Новая валюта для эксперимента не вводится | Experiment использует существующий эфир; в v1 цена равна `EXPERIMENT_COST = BREW_COST = 12` |
| Кап эфира не повышается | `craft_job` дробит списание по этапам, но не меняет `_max_ether()` |
| Одинаковая пара даёт одинаковый результат | канонический ключ пары + уникальная запись рецепта в SQLite |
| Кэш, известный рецепт и local/curated fallback не тратят внешнюю LLM quota | quota admission вызывается только для явного `experiment=true` и только после cache/lock проверки |
| Ошибка сети не превращается в случайный предмет | `unavailable` оставляет пару кандидатом; клиент возвращает входы и эфир либо ждёт retry |
| Промежуточный результат не теряется | инвентарь изменяется по операции, `craft_job` сохраняется после этапа, остановки и загрузки |
| Сервер не доверяет LLM в экономике | стоимость и слой вычисляются сервером/конфигурацией; LLM-выход проходит валидацию |
| Персональная аналитика только после consent | `Analytics.track` — consent-aware; device id/nick/email вычищаются из свойств |

### Активные значения

| Параметр | Значение по умолчанию | Где задаётся |
|---|---:|---|
| Операций в foreground/offline этапе | `3` | `Balance.CRAFT_STAGE_OPERATIONS` |
| Предупреждение о длинном маршруте | `20` операций | `Balance.CRAFT_PLAN_WARNING_OPERATIONS` |
| Hard cap локального плана | `200` операций | `Balance.CRAFT_PLAN_HARD_LIMIT_OPERATIONS` |
| Скидка blueprint | `0.90` | `Balance.BLUEPRINT_DISCOUNT` |
| Стоимость Experiment | `12 ⚡` | `Balance.EXPERIMENT_COST` |
| LLM cooldown на устройство | `5 секунд` | `ALCHEMY_EXPERIMENT_COOLDOWN_SEC` |
| LLM quota на устройство | `200/сутки` | `ALCHEMY_EXPERIMENT_DAILY_LIMIT` |
| LLM quota на весь сервер | `10000/сутки` | `ALCHEMY_EXPERIMENT_GLOBAL_DAILY_LIMIT` |
| Offline окно | до `8 часов` | существующий `OFFLINE_CAP_SEC` |

Значения rate limit должны меняться конфигурацией, а не перепрошивкой клиента.
Клиентские лимиты нужны для UX; окончательное решение о внешнем расходе
принимает серверная SQLite quota-таблица.

## 3. Архитектура

### 3.1. Компоненты

```text
Godot UI
  ├─ Эксперимент (pages.gd)
  ├─ Производство preview/confirm (core.gd)
  └─ save/load + return summary (saves.gd)
        │
        ├─ local known recipes / deterministic planner
        ├─ Analytics (только после consent)
        └─ Net: check_pair → discover, experiment=true
                    │
                    ▼
        discovery-server /api
          ├─ canonical pair key + recipes/rejected_pairs cache
          ├─ pending_pairs lock (идемпотентность гонок)
          ├─ experiment_limits (device/day/cooldown)
          ├─ experiment_global_limits (global/day)
          ├─ curated/local fallback
          └─ external LLM adapter (только после admission)
```

Ключевые клиентские места: `game/core.gd`, `game/guild.gd`, `game/pages.gd`,
`game/online.gd`, `game/saves.gd`. Серверная логика находится в
`discovery-server/server/server.py` и `gen_llm.py`.

### 3.2. Канонический ключ и расширение arity

В v1 поддерживаются две входные сущности. Текущий ключ сохраняет обратную
совместимость с существующей БД:

```text
pair_key = sort([slug_a, slug_b]).join("|")
```

Для следующего этапа 3–4 реагентов контракт расширяется без тупика:

```text
experiment_key = "exp:v2:" + sort(reagent_slugs).join("|")
context_key   = hash(recipe_version + sorted(tags) + locale)
```

Кэш должен индексироваться по `experiment_key`, а не по порядку кликов. Для
старых пар остаётся `pair_key`; миграция не пересчитывает старые результаты.

## 4. Эксперимент

### 4.1. Пользовательский поток

```text
Игрок открывает вкладку «Эксперимент»
        │
        ▼
Тап по веществу в выезжающей панели → временный реагент на поле
        │
        ▼
Перенос реагента с поля в котёл (или прямо из панели в котёл)
        │
        ├─ первый → остаётся в котле, UI ждёт второй
        └─ второй → собирается пара и запускается серверный эксперимент
                         │
                         ▼
                  Проверка клиента: запас / known / rejected / cooldown / daily limit
                         │
          ┌──────────────┼────────────────┐
          │ known/cache  │ candidate      │ rejected/unavailable
          ▼              ▼                ▼
       результат       /discover       возврат входов и эфира
```

Временный орб на поле не является новым предметом и не меняет инвентарь до
подтверждённого начала. При старте `Core` списывает входы и эфир, сохраняет
`pending pair`, а `Online` вызывает `brew-check?experiment=true`. Сервер
возвращает известный результат, создаёт новое открытие или сообщает об отказе;
клиент восстанавливает входы через существующий `finish_experiment_inputs`.
Любая ошибка должна оставить поле пригодным для следующей пары.

### 4.2. Детерминированность и cache

1. Клиент сортирует пару для UI/status, но сервер ещё раз канонизирует slug.
2. Сервер сначала смотрит `recipes`, затем `rejected_pairs`, затем lock.
3. Только неизвестная пара с `experiment=true` проходит device/global admission.
4. После успешной генерации сервер фиксирует element + recipe в одной БД.
5. Следующий запрос получает сохранённый `slug`, имя, автора и семантику; LLM
   повторно не вызывается.
6. Если внешняя LLM недоступна, состояние `candidate` не превращается в
   `rejected`: игрок может повторить позже.

В local/mock режиме генератор детерминированный и не считается внешней LLM.
Это позволяет работать без ключа и не обнулять дневной бюджет из-за curated
fallback.

### 4.3. Валидация результата

Минимальный технический ответ LLM:

```json
{"combinable": true, "name": "Туманное стекло"}
```

Дополнительные `description`, `tag`, `glyph` — только необязательный текстовый
слой. Сервер:

- отклоняет пустые/невалидные имена, цифры, склейки и дубликаты;
- проверяет tag по whitelist и подставляет категорию при необходимости;
- подставляет безопасный glyph fallback;
- ограничивает описание и очищает переносы;
- сам вычисляет category/layer/color/экономические значения.

### 4.4. Сохранение незавершённого запроса

`experiment_pending_pair` теперь входит в save. После перезапуска:

- при доступном сервере запрос продолжается с `experiment=true`;
- пока он ждёт ответа, второй эксперимент блокируется, чтобы не списать ещё
  один набор ресурсов;
- если связь не появилась за retry window, клиент возвращает реагенты и эфир,
  очищает pending и сообщает причину.

Это закрывает потерю реагентов при закрытии приложения между списанием и
ответом сервера.

## 5. Known-frontier planner

`Guild._plan_craft(item)` строит полный production-план только из известных
рецептов. При неизвестном узле `_plan_known_frontier(item)` рекурсивно собирает
известные входы и возвращает ближайшие неизвестные пары:

```json
{
  "ok": false,
  "ops": [{"a": "fire", "b": "water", "n": 1, "layer": 1}],
  "frontier": [{"a": "steam", "b": "earth", "out": "clay", "key": "earth|steam"}],
  "base_add": {"fire": 1},
  "missing": [],
  "total": 1
}
```

UI не говорит только «рецепт неизвестен»: он показывает следующую пару и
переводит игрока в Эксперимент. Если frontier нет, причина остаётся
ресурсной: ингредиенты, эфир или место в инвентаре.

## 6. Resumable Производство и `craft_job`

### 6.1. Поток

```text
известная цель
   │
   ▼
plan + preview полной стоимости и ближайшего этапа
   │  подтверждение
   ▼
craft_job {target, plan, completed, total_estimate, total_cost, discount}
   │
   ├─ до 3 операций → промежуточные предметы сохраняются
   │       │
   │       ├─ эфир закончился       → paused_ether
   │       ├─ вход закончился       → paused_ingredients
   │       ├─ рецепт исчез/неизвестен → paused_recipe
   │       ├─ stack заполнен        → paused_inventory
   │       ├─ лимит этапа           → paused_operation_cap
   │       └─ пользователь нажал Стоп → paused_user
   │
   └─ completed == total_estimate → output + blueprint + clear job
```

Структура job примерно такая:

```json
{
  "version": 1,
  "item": "house",
  "started_at": 0,
  "completed": 6,
  "total_estimate": 18,
  "plan": {"ops": [], "total": 18, "base_add": {}},
  "total_cost": 216,
  "discount": 1.0,
  "status": "paused_ether"
}
```

Стоимость считается по фактической последовательности: первое открытие узла
может иметь depth fee, известный повтор — базовую стоимость. Каждая операция
проверяет ингредиенты, recipe, место и эфир перед списанием. При паузе уже
созданные промежуточные предметы не откатываются.

Остановка через кнопку «Стоп» является отменой текущего этапа, а не удалением
прогресса: job остаётся в save и отправляет `craft_job_cancel` с
`kept_intermediates=true`. Повторный выбор той же цели — resume; выбор другой
цели блокируется понятным сообщением, чтобы не потерять старую job.

### 6.2. Preview длинной цели

До подтверждения игрок видит:

- полное число операций;
- базовые ингредиенты, которых не хватает;
- общую оценку эфира;
- стоимость ближайшего этапа (до 3 операций);
- наличие blueprint и скидки;
- возможность продолжить позже.

Preview не создаёт временный prototype item и не списывает эфир.

### 6.3. Offline/idle

Существующий offline return (до 8 часов) сначала начисляет обычный эфир, затем
продвигает сохранённую `craft_job` максимум на один stage. Используется та же
проверка pair/recipe/inventory и тот же `_commit_brew`, поэтому idle не создаёт
особую экономическую лазейку. В сводке возврата показываются число шагов и
причина новой паузы. Если цепочка завершена офлайн, blueprint записывается
так же, как в foreground.

## 7. Blueprints

Первое полное прохождение сохраняет:

```json
{
  "version": 1,
  "item": "brick",
  "operations": 4,
  "plan": {"ops": [], "total": 4},
  "discount": 0.9,
  "created_at": 0
}
```

Повторный маршрут:

- остаётся детерминированным и использует известную книгу рецептов;
- получает 10% скидку к операции/этапу;
- не получает бесплатный output, дополнительный cap или скрытую валюту;
- отправляет отдельное `craft_job_repeat` для оценки экономики.

Фаза v2 может оптимизировать blueprint до компактной формулы, но только после
добавления `recipe_version`, миграции старых планов и проверки, что скидка не
комбинируется с другими скидками за пределами заданного коэффициента.

## 8. Telemetry и аналитика

Все события проходят `Analytics.track` и не записываются до пользовательского
consent. События не содержат device id, nick или email в properties.

| Событие | Когда | Минимальные свойства |
|---|---|---|
| `experiment_start` | подтверждён и списан Experiment | left/right, cost |
| `experiment_result` | created/rejected/unavailable/invalid | left/right, result, output? |
| `craft_plan_preview` | показан preview | target, operations, stage_ether, available_ether, blueprint |
| `craft_job_start` | первый запуск job | target, operations, total_ether, blueprint |
| `craft_job_resume` | продолжение сохранённой job | target, completed, total, previous status |
| `craft_job_pause` | эфир/ингредиенты/recipe/inventory/cap | target, reason, completed, total |
| `craft_job_cancel` | пользователь остановил этап | target, completed, total, kept_intermediates |
| `craft_job_complete` | маршрут завершён | target, operations, blueprint, repeat, offline? |
| `craft_job_repeat` | старт маршрута с blueprint | target, discount |
| `craft_job_offline` | idle продвинул job | target, steps, status, completed, total |

Главные продуктовые метрики:

1. preview → start conversion;
2. доля jobs, дошедших до complete;
3. медиана времени и числа сессий до complete;
4. pause rate по причинам;
5. resume within 24h и cancel rate;
6. Experiment success/reject/unavailable;
7. cache hit rate и external LLM calls per DAU;
8. доля повторных крафтов через blueprint;
9. средний расход эфира до/после blueprint;
10. платная конверсия после pause, но без таргетинга по персональным данным.

Нельзя оптимизировать только `craft_job_start`: рост стартов при падении
complete/resume означает, что preview обещает больше, чем экономика позволяет.

## 9. Миграция и совместимость

### M0 — текущий save (выполнено)

1. Старый save без `experiment_day/count/last_at` получает безопасные defaults.
2. Отсутствующий `craft_job` трактуется как `{}`.
3. Отсутствующий `blueprints` трактуется как `{}`.
4. Отсутствующий `experiment_pending_pair` трактуется как пустой массив.
5. Старый `known_recipes`, server elements и server recipes не пересчитываются.
6. Никаких бесплатных items за сам факт миграции.

### M1 — rollout клиента (выполнено)

- включить Эксперимент только для пар v1;
- неизвестную production-цель отправлять в known frontier;
- включить staged job и явный preview;
- записывать job после каждой завершённой операции/этапа;
- подключить offline advancement к return summary;
- сохранять blueprint только после полного маршрута.

### M2 — rollout сервера (выполнено)

- применить SQLite DDL для `experiment_limits` и
  `experiment_global_limits` через `init_db`;
- сначала включить `local/mock` fallback;
- затем включить внешний provider с env quota;
- мониторить `rate_limited`, `unavailable`, latency и DB lock conflicts;
- при проблеме выставить `LLM_PROVIDER=local`: старые рецепты и кэш продолжают
  работать, новые внешние вызовы не происходят.

### M3 — arity 3–4 и compact blueprint (следующий этап)

1. Ввести `exp:v2` key без изменения pair v1.
2. Расширить UI preview до списка реагентов, не меняя серверную авторитетность.
3. Добавить `recipe_version` в blueprint.
4. Прогнать property/regression tests: одинаковый набор реагентов, порядок,
   повторная загрузка, quota и rollback.
5. Только после этого оптимизировать граф в компактную формулу.

## 10. Монетизация, privacy и stores

Крафт не должен скрыто превращать Experiment в платный paywall. Если в магазине
есть consumable ether pack, он должен проходить общий idempotent purchase funnel:
проверка provider/token, запись обработанного purchase и начисление через
существующий `Monetization`/`UserData`, а не через Experiment endpoint.

Для Google Play и RuStore сохраняется один игровой контракт: receipt/token
валидируется соответствующим адаптером, но баланс и job меняются только после
серверно подтверждённого результата. Product ids, цены и store-specific SDK не
зашиваются в `craft_job`.

Пользовательские данные разделены:

- локально: save, pending job, blueprint, pending experiment и consent;
- сервер: canonical recipes/elements, device quota, минимальный профиль и
  открытие мира;
- экспорт/удаление account/profile остаются через существующие privacy endpoints;
- analytics queue экспортируется/очищается через privacy UI и не активируется
  без согласия.

## 11. Файлы и проверки

Основные файлы реализации:

- `game/core.gd` — Experiment refund/state, planner handoff, staged Производство,
  pause reasons, blueprints, telemetry;
- `game/guild.gd` — known-frontier planner;
- `game/pages.gd` — Эксперимент и bench tick;
- `game/online.gd` — check/discover flow, marker propagation и pending resume;
- `game/saves.gd` — migration, job/blueprint/pending persistence, offline stage;
- `game/data/balance.gd` — configurable limits and discount;
- `discovery-server/server/server.py` — deterministic DB/cache, quota/admission;
- `discovery-server/server/tests/test_experiment_limits.py` — quota/cache/local
  fallback regression tests.

Последняя локальная проверка реализации:

```text
Godot headless parse/editor check: exit 0
Godot selftest: SELFTEST PASS (316/316)
server python3 -m py_compile: exit 0
server pytest server/tests: 123 passed
```

`git diff --check` неприменим к этой рабочей копии: каталог проекта не является
Git working tree. Для whitespace-проверки используется эквивалентный поиск
trailing whitespace по изменённым текстовым файлам.

## 12. Критерии приёмки

1. Неизвестная пара не создаёт локальный временный предмет и ведёт в Experiment
   Bench.
2. Повтор одного и того же ключа получает тот же серверный результат без LLM
   вызова.
3. Cache/local/curated не уменьшают external quota.
4. Вторая внешняя попытка в cooldown получает явную причину, а дневной лимит
   устройства — `200` по умолчанию.
5. Известная цепочка длиннее капа стартует этапом, а не падает целиком.
6. После паузы по эфир/ингредиент/recipe/inventory/cap игрок видит следующую
   причину и может продолжить.
7. Остановка и закрытие приложения сохраняют промежуточные items и job.
8. Возврат после offline продвигает job не более разрешённого этапа.
9. Полное первое прохождение записывает blueprint; повтор получает только
   безопасную конфигурируемую скидку.
10. Все требуемые переходы видны в telemetry, а consent/privacy/store paths не
    обходятся новой механикой.
