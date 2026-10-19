extends RefCounted
class_name ContractsBalance
# §1: только таблицы — типы контрактов, пороги тиров, базовые награды, базовые
# силы и сроки баффов, id декора. Никакой логики и состояния: при переходе на
# сервер-авторитет (§1.5) этот файл дублируется на сервере как есть, и
# расхождение версий должно быть видно сразу.

# §2.1: порядок здесь — порядок пула для детерминированного выбора из seed.
# Доска v2 (спека слияния §2): первые PINNED_HEAD записей каждого пула —
# закреплённая голова ряда (goal_day/orders, vein/fair): их генератор кладёт
# в начало в этом же порядке, случайная выборка идёт только из остального хвоста.
const DAILY_TYPES: Array = ["goal_day", "orders", "brew", "experiment", "discover",
	"sigil_craft", "chain_brew", "depth_brew"]
# §2.2
const WEEKLY_TYPES: Array = ["vein", "fair", "sigil_set", "upgrade", "prestige", "variety", "rare_brew"]
const TIERS: Array = ["bronze", "silver", "gold"]
const PINNED_HEAD := 2
# Доска v2: ряд вырос 3/2→4/4 — дневной ряд теперь помещает и Дневной круг,
# и Недельный слой механик, поэтому закреплённая голова влезает в тот же ряд.
const DAILY_SHOWN := 4
const WEEKLY_SHOWN := 4

# §2.1/§2.2: порядок значений = порядок TIERS.
const DAILY_GOALS := {
	# Спека §1: цель pinned-контракта не зависит от тира там, где это зафиксировано
	# спекой — три одинаковых числа не опечатка, а контракт с механикой.
	"goal_day": [1, 1, 1],
	"orders": [3, 3, 3],
	"brew": [15, 40, 80],
	"experiment": [3, 6, 12],
	"discover": [1, 2, 4],
	"sigil_craft": [1, 2, 3],
	"chain_brew": [5, 10, 20],
	"depth_brew": [3, 5, 8],
}
const WEEKLY_GOALS := {
	# Спека §1: vein масштабируется тиром 1/2/3, fair — фиксированная цель.
	"vein": [1, 2, 3],
	"fair": [3, 3, 3],
	"sigil_set": [3, 5, 8],
	"upgrade": [2, 4, 6],
	# bronze == silver намеренно: Перегонка редка, и две за неделю на silver
	# принуждали бы к сбросу прогресса.
	"prestige": [1, 1, 2],
	"variety": [8, 15, 25],
	"rare_brew": [3, 6, 12],
}

# §3.2: числа зафиксированы расчётом по каталогу main.gd:255 (дневной gold =
# 282 базовых элемента, недельный gold = 1414). Не пересчитывать «на глаз»:
# сюита сверяет и сами числа, и их стоимость в базовых элементах.
const DAILY_MATERIALS := {
	"bronze": {"stone": 20, "brick": 10},
	"silver": {"stone": 35, "brick": 18, "metal": 8},
	"gold": {"stone": 55, "brick": 28, "metal": 14, "glass": 8},
}
const WEEKLY_MATERIALS := {
	"bronze": {"stone": 80, "brick": 45, "metal": 20},
	"silver": {"stone": 140, "brick": 80, "metal": 40, "glass": 22},
	"gold": {"stone": 220, "brick": 130, "metal": 70, "glass": 40, "crystal": 18},
}

# §3.3: порядок = порядок пула для выбора баффа из seed.
const BUFF_IDS: Array = ["brew_speed", "spring_yield", "craft_discount", "workshop_speed", "ether_regen"]
# power — добавка сверх нейтрального значения, поэтому одна формула работает и
# для процентных бонусов, и для мультипликаторов.
const BUFF_BASE := {
	"brew_speed": {"duration": 7200, "power": 0.25},
	"spring_yield": {"duration": 1800, "power": 1.0},
	"craft_discount": {"duration": 10800, "power": 0.2},
	"workshop_speed": {"duration": 3600, "power": 0.3},
	"ether_regen": {"duration": 7200, "power": 1.0},
}
const BUFF_TITLE := {
	"brew_speed": "Быстрая варка",
	"spring_yield": "Полноводный родник",
	"craft_discount": "Дешёвый крафт",
	"workshop_speed": "Спешка в мастерской",
	"ether_regen": "Прилив эфира",
}
# §5.4: текст эффекта на записке. Число в него не вшивается — сила масштабуется
# единым множителем §3.1, поэтому процент печатается отдельно из активного баффа.
const BUFF_TEXT := {
	"brew_speed": "варка идёт быстрее",
	"spring_yield": "родник даёт больше",
	"craft_discount": "крафт Аркана дешевле",
	"workshop_speed": "мастерская спешит",
	"ether_regen": "эфир копится быстрее",
}

# §3.4: reward-only витражи Дома по образцу наград Круга (decor.gd:131-133).
const DECOR: Array = ["window_contract", "window_seal", "window_guild"]
const DECOR_LABEL := {
	"window_contract": "Контрактный витраж",
	"window_seal": "Витраж с печатью",
	"window_guild": "Витраж гильдии",
}
const DECOR_TINT := {
	"window_contract": "#c9a24d",
	"window_seal": "#a34a3c",
	"window_guild": "#4d7ab7",
}

# §3.1: вес Мастерской выше веса Родника — прямое указание владельца.
const WORKSHOP_WEIGHT := 0.65
const SPRING_WEIGHT := 0.35
# Единственная ручка регулировки endgame-баффов. Уменьшать её, а не заводить
# вторую формулу скейла.
const MULT_COEF := 1.05
const RANK_MAX := 3
const AUTONOMY_MAX := 2
const SPRING_MAX := {"speed": 7, "volume": 7, "sources": 3, "offline": 3}

const DEPTH_DAILY := 2
const DEPTH_WEEKLY := 4

const TITLE := {
	"goal_day": "Цель дня",
	"orders": "Заказы гильдии",
	"vein": "Жила недели",
	"fair": "Ярмарка гильдии",
	"brew": "Варка",
	"experiment": "Эксперимент",
	"discover": "Открытие",
	"sigil_craft": "Крафт Аркана",
	"chain_brew": "Цепочка варок",
	"depth_brew": "Глубокая варка",
	"sigil_set": "Комплект Аркана",
	"upgrade": "Улучшение",
	"prestige": "Перегонка",
	"variety": "Разнообразие открытий",
	"rare_brew": "Редкая варка",
}
const TIER_TITLE := {"bronze": "Бронза", "silver": "Серебро", "gold": "Золото"}
const KIND_TITLE := {"daily": "Дневной контракт", "weekly": "Недельный контракт"}
