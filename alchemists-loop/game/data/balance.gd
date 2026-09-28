extends RefCounted
class_name Balance
# Баланс и тюнинг: цены, возвраты, сроки, награды, вехи (бывшие const из main.gd, оп D).

# Economy v2: эфир is a paced research resource, not an unlimited idle faucet.
const BREW_COST := 12
const FAILURE_REFUND := 2
const BASE_ETHER_REGEN := 0.35
const MAX_ETHER := 180
const START_ETHER := 100
# First-time discoveries pay a depth surcharge. Known recipes still cost BREW_COST.
const DISCOVERY_FEES := {1: 4, 2: 6, 3: 10, 4: 16, 5: 24, 6: 36}
# Rewards that would land above the active cap go to the visible surplus reserve.
# The reserve is not energy: it is only spendable by optional mastery rites.
const ETHER_MASTERY_BASE := 300
const ETHER_MASTERY_GROWTH := 1.35

# --- прокачка (покупки за эфир) и «судьбоносные» режимы-вкладки ---
# Улучшения появляются по мере открытий: поле "unlock" — вещество, которое их открывает.
const UPGRADES := [
	{"id": "ether_regen", "name": "Поток эфира", "desc": "+0.35 эфира в секунду",
		"base": 150, "growth": 1.55, "max": 4, "unlock": "steam"},
	{"id": "ether_cap", "name": "Ёмкость эфира", "desc": "+50 к максимуму эфира",
		"base": 70, "growth": 1.32, "max": 8, "unlock": "clay"},
	{"id": "brew_speed", "name": "Скороварка", "desc": "каждая варка на 10% быстрее",
		"base": 170, "growth": 1.5, "max": 4, "unlock": "glass"},
	{"id": "source_yield", "name": "Щедрые источники", "desc": "каждая 8/7/6/5-я добыча даёт +1 сверху",
		"base": 220, "growth": 1.6, "max": 3, "unlock": "mushroom"},
	{"id": "auto_gift", "name": "Дары", "desc": "случайное открытое вещество +1 каждые 2 минуты",
		"base": 450, "growth": 1.0, "max": 1, "unlock": "fish"}
]

# Светик подсказывает направление, но не раскрывает результат. Цена — существующий эфир.
# Значение вынесено в баланс, чтобы аналитика могла менять его без рерайта UI.
const HINT_COST := 10
# Анти-спам окно для кнопок траты (подсказка): повторный тап внутри него
# молча отбрасывается. Тот же интервал, что и у _collect_all_ms в core.gd.
const SPEND_GUARD_MSEC := 250

# резонанс 2.0: вечные вехи отголосков (вечный счётчик повторов твоих веществ)
const RES_MILES := [10, 50, 100]
const RES_REGEN10 := 0.03  # +регенерация/с за веху 10 повторов
const RES_CAP50 := 5       # +к максимуму эфира за веху 50 повторов
# веха 100 — золотая рамка своих веществ в сетке мира (без числового бонуса)
# «Забрать» эхо — асинхронная трата: окно «запрос в пути» держится до ответа мира
# и заведомо больше реального round-trip (очередь Net сериализуется за опросом
# событий); самоотпускается, чтобы потерянный ответ не запирал claim до конца сессии.
const RESONANCE_CLAIM_GATE_MSEC := 15000
# ночная реторта: долгий сосуд 8–24 ч, эссенции с вечным бонусом к капу
const RETORT_BASE_HOURS := 8.0   # срок = 8 ч × (1 + тир × 0.5): 8/12/16/20/24 ч
const RETORT_CAP_EACH := 1       # +к капу за каждую уникальную эссенцию…
const RETORT_CAP_FIRST := 8      # …первые 8 уникальных; дальше — разовый эфир
const RETORT_REPEAT_ETHER := 25  # эфир за повторную/позднюю эссенцию
# письма Светика: ежедневная загадка-пары, матчинг на сервере (клиент ответа не видит)
const LETTER_MILE_EVERY := 5   # каждые N разгаданных — веха
const LETTER_CAP_EACH := 3     # +к капу навсегда за каждую веху
const LETTER_PENDING_MAX := 20 # потолок очереди офлайн-попыток (пары «a|b»)
# страница Атласа: общемировая загадка дня, альбом прошлого, веха каждые 10
const ATLAS_MILE_EVERY := 10
const ATLAS_CAP_EACH := 3
const ATLAS_PENDING_MAX := 20
# дневной круг (v29): контейнер суточного слоя + мягкий стрик-очаг + вечные вехи
const CIRCLE_DISC_GOAL := 5    # новых открытий за день для закрытия круга
const CIRCLE_REWARD := 75      # эфир за закрытый круг (раз в день)
const CIRCLE_LOCAL_POINTS := 1  # очко вех за локальную цель дня (A3); сервер, когда есть, перебивает
const HEARTH_BASE := 10        # база награды «полешка» (× множитель серии, кап ×2)
const CIRCLE_DAY_MILES := [7, 30, 100, 365]      # вехи суммарных дней визитов
const CIRCLE_DAY_CAP := {7: 5, 100: 10}          # +к капу за вехи дней
const CIRCLE_DAY_REGEN := {30: 0.05}              # +к регену за вехи дней (365 — аура «Очаг»)
const CIRCLE_PTS_MILES := [50, 150, 500]         # вехи вечных очков цели дня
const CIRCLE_PTS_CAP := {50: 3, 500: 5}          # +к капу за вехи очков
const CIRCLE_PTS_REGEN := {150: 0.03}            # +к регену за вехи очков
# план 2 (жила): cap прожилки за цикл, награда за cap, очки world-first (отображение)
const VEIN_STREAK_CAP := 5
const VEIN_STREAK_REWARD := 25
const VEIN_POINTS_WORLD := 2
# план 2 §2.1: цели варки — фильтр пула известных пар по слою выхода
const CIRCLE_GOALS := [
	{"key": "fast",   "title": "Быстрая проба", "layers": [1, 2],  "pts": 1,
		"desc": "Лёгкая варка, быстрый прогресс"},
	{"key": "middle", "title": "Средний путь",  "layers": [3, 4],  "pts": 2,
		"desc": "Баланс скорости и ценности"},
	{"key": "deep",   "title": "Глубокий синтез", "layers": [5, 99], "pts": 3,
		"desc": "Медленно, но высоко ценится"},
]
# недельный слой (v30): жила даёт очки + прожилки (+1 кап, кап 5/нед. на сервере)
const FAIR_REGEN_EACH := 0.05  # сильная недельная награда: +0.05 регена/с за закрытый котёл (вклад ≥3)
const FAIR_REGEN_CAP := 0.5    # потолок суммарного регена ярмарок
const FAIR_OFFLINE_GOAL := 3     # A3: варок разных веществ за неделю — локальный котёл
const FAIR_OFFLINE_FACTOR := 0.5 # без мира реген ярмарки — вполовину, ключ недели тот же
# сводка возврата: единый экран «пока тебя не было» после долгого отсутствия
const RETURN_GAP := 1800.0       # 30 минут — порог показа сводки
const SPRING_OFFLINE_MAX := 50   # потолок офлайн-накопления Родника (шт.)
const SPRING_INTERVAL := 6.0
# Производство remains useful, but it is a paced helper rather than a free second cauldron.
const BENCH_INTERVAL := 10.0
const BENCH_LIMIT := 3
const GIFT_INTERVAL := 120.0
const EVENT_INTERVAL := 150.0
const EVENT_WINDOW := 8.0

# Crafting rework v1: two-input Эксперимент now; hash/API are versioned
# so 3–4 reagents can be added later without changing saved pair identity.
const EXPERIMENT_ARITY_MIN := 2
const EXPERIMENT_ARITY_MAX := 2
const EXPERIMENT_COOLDOWN_SEC := 5.0
const EXPERIMENT_DAILY_LIMIT := 200
const EXPERIMENT_COST := BREW_COST
const EXPERIMENT_FAILURE_REFUND := FAILURE_REFUND
const CRAFT_STAGE_OPERATIONS := 3
# A2 «Печать мастерства»: продаём время и параллелизм, не эфир.
const MASTERY_STAGE_RANKS := [3, 7]     # +1 операция этапа за каждый достигнутый ранг
const MASTERY_RETORT_SPEED := 0.06      # −6 % срока реторты за каждый ранг ≥ 2 (задача 2)
const MASTERY_RETORT_MIN_HOURS := 6.0   # пол срока реторты, ч (задача 2)
const MASTERY_RETORT_SLOT_RANK := 5     # ранг, открывающий 4-й сосуд (задача 3)
const RETORT_SLOT_MAX := 4              # физических сосудов в массиве (задача 3)
const CRAFT_PLAN_WARNING_OPERATIONS := 20
const CRAFT_PLAN_HARD_LIMIT_OPERATIONS := 200
# The existing save migration already clamps stacks to this value. Производство
# treats reaching it as an explicit, resumable inventory pause instead of
# silently overflowing the target stack.
const CRAFT_INVENTORY_STACK_CAP := 1000000
const BLUEPRINT_DISCOUNT := 0.90
const GUILD_ALL_BONUS := 100  # эфир за выполнение всех заказов гильдии подряд

const CANDIDATE_CHANCE := 0.05    # 5%: «туман» без запроса к серверу
const CANDIDATE_COOLDOWN := 60.0  # сек между проверками одной пары
const NET_NICK := "Алхимик"
const CHALLENGE_REWARD := 50   # эфир за победу в ежедневной цели

const WORLD_PAGE_SIZE := 25  # строк на странице сетки «Все вещества» (п.8)

const PRESTIGE_MIN := 30           # веществ для разблокировки «Перегонки»
const OFFLINE_MIN_SEC := 60.0       # меньше минуты — не считаем отсутствием
const OFFLINE_CAP_SEC := 8 * 3600.0 # максимум 8 часов офлайн-накопления
const MILESTONES := [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 57]
const MILESTONE_REWARDS := {5: 20, 10: 25, 15: 30, 20: 40, 25: 50, 30: 60,
	35: 70, 40: 80, 45: 90, 50: 100, 55: 120, 57: 160}
