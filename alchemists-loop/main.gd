extends Control
class_name Game
# Alchemist's Loop — MVP v3 (визуальная лаборатория).
# Элементы = цветные орбы с глифами. Drag&drop орба в лунки котла (мышь/тач),
# тап по источнику = добыча, тап по «?» = намёк. Новая находка — карточка-открытие.

# ---------- пути сейва (переопределяемы для тестов) ----------
var SAVE_PATH := "user://alchemy_save.json"
var TEMP_PATH := "user://alchemy_save.tmp"
var BACKUP_PATH := "user://alchemy_save.bak"
const SAVE_VERSION := 3

var BREW_SECONDS := 1.2
const HouseViewScript := preload("res://game/house_view.gd")

# --- данные живут в game/data/* (оп D); алиасы — ноль правок вызовов ---
# Balance
const BREW_COST := Balance.BREW_COST
const FAILURE_REFUND := Balance.FAILURE_REFUND
const BASE_ETHER_REGEN := Balance.BASE_ETHER_REGEN
const DISCOVERY_FEES := Balance.DISCOVERY_FEES
const ETHER_MASTERY_BASE := Balance.ETHER_MASTERY_BASE
const ETHER_MASTERY_GROWTH := Balance.ETHER_MASTERY_GROWTH
const MILESTONE_REWARDS := Balance.MILESTONE_REWARDS
const MAX_ETHER := Balance.MAX_ETHER
const START_ETHER := Balance.START_ETHER
const UPGRADES := Balance.UPGRADES
const HINT_COST := Balance.HINT_COST
const SPEND_GUARD_MSEC := Balance.SPEND_GUARD_MSEC
const RES_MILES := Balance.RES_MILES
const RES_REGEN10 := Balance.RES_REGEN10
const RES_CAP50 := Balance.RES_CAP50
const RESONANCE_CLAIM_GATE_MSEC := Balance.RESONANCE_CLAIM_GATE_MSEC
const RETORT_BASE_HOURS := Balance.RETORT_BASE_HOURS
const RETORT_CAP_EACH := Balance.RETORT_CAP_EACH
const RETORT_CAP_FIRST := Balance.RETORT_CAP_FIRST
const RETORT_REPEAT_ETHER := Balance.RETORT_REPEAT_ETHER
const LETTER_MILE_EVERY := Balance.LETTER_MILE_EVERY
const LETTER_CAP_EACH := Balance.LETTER_CAP_EACH
const LETTER_PENDING_MAX := Balance.LETTER_PENDING_MAX
const ATLAS_MILE_EVERY := Balance.ATLAS_MILE_EVERY
const ATLAS_CAP_EACH := Balance.ATLAS_CAP_EACH
const ATLAS_PENDING_MAX := Balance.ATLAS_PENDING_MAX
const CIRCLE_DISC_GOAL := Balance.CIRCLE_DISC_GOAL
const CIRCLE_REWARD := Balance.CIRCLE_REWARD
const HEARTH_BASE := Balance.HEARTH_BASE
const CIRCLE_DAY_MILES := Balance.CIRCLE_DAY_MILES
const CIRCLE_DAY_CAP := Balance.CIRCLE_DAY_CAP
const CIRCLE_DAY_REGEN := Balance.CIRCLE_DAY_REGEN
const CIRCLE_PTS_MILES := Balance.CIRCLE_PTS_MILES
const CIRCLE_PTS_CAP := Balance.CIRCLE_PTS_CAP
const CIRCLE_PTS_REGEN := Balance.CIRCLE_PTS_REGEN
const FAIR_REGEN_EACH := Balance.FAIR_REGEN_EACH
const FAIR_REGEN_CAP := Balance.FAIR_REGEN_CAP
const FAIR_OFFLINE_GOAL := Balance.FAIR_OFFLINE_GOAL
const FAIR_OFFLINE_FACTOR := Balance.FAIR_OFFLINE_FACTOR
const RETURN_GAP := Balance.RETURN_GAP
const SPRING_OFFLINE_MAX := Balance.SPRING_OFFLINE_MAX
const SPRING_INTERVAL := Balance.SPRING_INTERVAL
const BENCH_INTERVAL := Balance.BENCH_INTERVAL
const BENCH_OFFLINE_FACTOR := Balance.BENCH_OFFLINE_FACTOR
const BENCH_OFFLINE_MAX_TICKS := Balance.BENCH_OFFLINE_MAX_TICKS
const GIFT_INTERVAL := Balance.GIFT_INTERVAL
const EVENT_INTERVAL := Balance.EVENT_INTERVAL
const EVENT_WINDOW := Balance.EVENT_WINDOW
const EXPERIMENT_ARITY_MIN := Balance.EXPERIMENT_ARITY_MIN
const EXPERIMENT_ARITY_MAX := Balance.EXPERIMENT_ARITY_MAX
const EXPERIMENT_COOLDOWN_SEC := Balance.EXPERIMENT_COOLDOWN_SEC
const EXPERIMENT_DAILY_LIMIT := Balance.EXPERIMENT_DAILY_LIMIT
const EXPERIMENT_COST := Balance.EXPERIMENT_COST
const EXPERIMENT_FAILURE_REFUND := Balance.EXPERIMENT_FAILURE_REFUND
const CRAFT_STAGE_OPERATIONS := Balance.CRAFT_STAGE_OPERATIONS
const MASTERY_STAGE_RANKS := Balance.MASTERY_STAGE_RANKS
const MASTERY_RETORT_SPEED := Balance.MASTERY_RETORT_SPEED
const MASTERY_RETORT_MIN_HOURS := Balance.MASTERY_RETORT_MIN_HOURS
const MASTERY_RETORT_SLOT_RANK := Balance.MASTERY_RETORT_SLOT_RANK
const RETORT_SLOT_MAX := Balance.RETORT_SLOT_MAX
const CRAFT_PLAN_WARNING_OPERATIONS := Balance.CRAFT_PLAN_WARNING_OPERATIONS
const CRAFT_PLAN_HARD_LIMIT_OPERATIONS := Balance.CRAFT_PLAN_HARD_LIMIT_OPERATIONS
const CRAFT_INVENTORY_STACK_CAP := Balance.CRAFT_INVENTORY_STACK_CAP
const BLUEPRINT_DISCOUNT := Balance.BLUEPRINT_DISCOUNT
const GUILD_ALL_BONUS := Balance.GUILD_ALL_BONUS
const CANDIDATE_CHANCE := Balance.CANDIDATE_CHANCE
const CANDIDATE_COOLDOWN := Balance.CANDIDATE_COOLDOWN
const NET_NICK := Balance.NET_NICK
const CHALLENGE_REWARD := Balance.CHALLENGE_REWARD
const CIRCLE_LOCAL_POINTS := Balance.CIRCLE_LOCAL_POINTS
const VEIN_STREAK_CAP := Balance.VEIN_STREAK_CAP
const VEIN_STREAK_REWARD := Balance.VEIN_STREAK_REWARD
const VEIN_POINTS_WORLD := Balance.VEIN_POINTS_WORLD
const CIRCLE_GOALS := Balance.CIRCLE_GOALS
const CIRCLE_RANKS := Balance.CIRCLE_RANKS
const CIRCLE_DECOR_REWARDS := Balance.CIRCLE_DECOR_REWARDS
const WORLD_PAGE_SIZE := Balance.WORLD_PAGE_SIZE
const PRESTIGE_MIN := Balance.PRESTIGE_MIN
const OFFLINE_MIN_SEC := Balance.OFFLINE_MIN_SEC
const OFFLINE_CAP_SEC := Balance.OFFLINE_CAP_SEC
const MILESTONES := Balance.MILESTONES
# Modes
const BASE_IDS := Modes.BASE_IDS
const MODES := Modes.MODES
const EVENT_TYPES := Modes.EVENT_TYPES
const CATEGORY_SETS := Modes.CATEGORY_SETS
const CATEGORY_OF := Modes.CATEGORY_OF
# DecorData
const WORKSHOP_THEMES := DecorData.WORKSHOP_THEMES
const WORKSHOP_AURAS := DecorData.WORKSHOP_AURAS
const HOUSE_COST := DecorData.HOUSE_COST
const CUSTOM_COSTS := DecorData.CUSTOM_COSTS
const DECOR := DecorData.DECOR
const COLOR_SWATCHES := DecorData.COLOR_SWATCHES
# HouseTasksData (β)
const HOUSE_TASKS := HouseTasksData.TASKS
# QuestData
const QUEST_CAP := QuestData.QUEST_CAP
const QUEST_REGEN := QuestData.QUEST_REGEN
const ACH_CAP := QuestData.ACH_CAP
const ACH_REGEN := QuestData.ACH_REGEN
const SPIRIT_QUESTS := QuestData.SPIRIT_QUESTS
const ACHIEVEMENTS := QuestData.ACHIEVEMENTS


var ITEMS := {
	"fire": {"name": "Огонь", "color": "#ff936b", "d": "Жар и пламя — первостихия."},
	"water": {"name": "Вода", "color": "#71bfff", "d": "Текучая влага — первостихия."},
	"earth": {"name": "Земля", "color": "#c4a47c", "d": "Почва и камень — первостихия."},
	"air": {"name": "Воздух", "color": "#cee8ef", "d": "Ветер и небо — первостихия."},
	"steam": {"name": "Пар", "color": "#c4cfe5", "d": "Вода, обращённая огнём в пар."},
	"stone": {"name": "Камень", "color": "#a6a6bb", "d": "Земля, обожжённая огнём в породу."},
	"clay": {"name": "Глина", "color": "#d2785f", "d": "Мокрая земля, годная для лепки."},
	"dust": {"name": "Пыль", "color": "#ddd0a2", "d": "Земля, растёртая ветром в порошок."},
	"spark": {"name": "Искра", "color": "#ffe08a", "d": "Маленький огонёк, готовый разгореться."},
	"mist": {"name": "Туман", "color": "#acc8e4", "d": "Дымка из воды и воздуха."},
	"brick": {"name": "Кирпич", "color": "#a05242", "d": "Обожжённая глина — стройматериал."},
	"sand": {"name": "Песок", "color": "#f0d499", "d": "Камень, истёртый ветром в крупинки."},
	"plant": {"name": "Росток", "color": "#96d691", "d": "Первая жизнь, пробившаяся из глины."},
	"cloud": {"name": "Облако", "color": "#8cb0d0", "d": "Пар, собравшийся в небе тучей."},
	"ice": {"name": "Лёд", "color": "#a8e8ff", "d": "Вода, замёрзшая на вершине горы."},
	"mountain": {"name": "Гора", "color": "#877864", "d": "Каменная громада."},
	"mud": {"name": "Грязь", "color": "#6e4628", "d": "Земля, размокшая в воде."},
	"metal": {"name": "Металл", "color": "#7896be", "d": "Руда, выбитая из камня искрой."},
	"life": {"name": "Жизнь", "color": "#4fd06f", "d": "Искра, ожившая в воде."},
	"smoke": {"name": "Дым", "color": "#a0a3aa", "d": "Пыль, поднятая огнём в воздух."},
	"lava": {"name": "Лава", "color": "#f0561e", "d": "Расплавленный огнём камень."},
	"glass": {"name": "Стекло", "color": "#93e2d3", "d": "Песок, сплавленный огнём в прозрачность."},
	"sky": {"name": "Небо", "color": "#64a8e8", "d": "Высь над облаками."},
	"rain": {"name": "Дождь", "color": "#3f74c6", "d": "Вода, пролившаяся из тучи."},
	"storm": {"name": "Гроза", "color": "#47536b", "d": "Туча, полная молний и грома."},
	"hail": {"name": "Град", "color": "#b9dcef", "d": "Ледяные зёрна, падающие из тучи."},
	"snow": {"name": "Снег", "color": "#f4fafd", "d": "Лёд, унесённый ветром в небо."},
	"volcano": {"name": "Вулкан", "color": "#8c422e", "d": "Гора, извергающая лаву."},
	"obsidian": {"name": "Обсидиан", "color": "#383248", "d": "Лава, застывшая в воде в стекло."},
	"magma": {"name": "Магма", "color": "#b23b2e", "d": "Лава, копившаяся в толще земли."},
	"ash": {"name": "Пепел", "color": "#b4b8c0", "d": "Пепел — всё, что осталось от огня."},
	"gold": {"name": "Золото", "color": "#c69624", "d": "Металл, закалённый огнём — мечта алхимика."},
	"swamp": {"name": "Болото", "color": "#548036", "d": "Грязь, заросшая растениями."},
	"fish": {"name": "Рыба", "color": "#40aac8", "d": "Жизнь, обжившая воду."},
	"bird": {"name": "Птица", "color": "#5d97d8", "d": "Жизнь, поднявшаяся в воздух."},
	"beast": {"name": "Зверь", "color": "#a06a3c", "d": "Жизнь, ступившая на землю."},
	"person": {"name": "Человек", "color": "#eeaa8c", "d": "Жизнь, слепленная из глины."},
	"seed": {"name": "Семя", "color": "#aa8246", "d": "Семя, уроненное ростком в пыль."},
	"grass": {"name": "Трава", "color": "#96d646", "d": "Росток, покрывший землю."},
	"mushroom": {"name": "Гриб", "color": "#b26d5f", "d": "Гриб, выросший на болоте."},
	"lightning": {"name": "Молния", "color": "#f5e13b", "d": "Разряд, бьющий из грозовой тучи."},
	"tornado": {"name": "Смерч", "color": "#8d939e", "d": "Вихрь из пыли и ветра."},
	"tool": {"name": "Инструмент", "color": "#77828c", "d": "Камень, приспособленный человеком."},
	"tree": {"name": "Дерево", "color": "#4e9150", "d": "Семя, проросшее в земле."},
	"sun": {"name": "Солнце", "color": "#ffd21f", "d": "Огонь, зажжённый в небе."},
	"crystal": {"name": "Кристалл", "color": "#cbbdff", "d": "Стекло, сложившееся в самоцвет."},
	"sandstorm": {"name": "Песчаная буря", "color": "#d4783c", "d": "Буря, несущая песок."},
	"forest": {"name": "Лес", "color": "#106e2d", "d": "Множество деревьев, ставшее лесом."},
	"wood": {"name": "Древесина", "color": "#d0a454", "d": "Древесина — материал из дерева."},
	"flower": {"name": "Цветок", "color": "#ef7fb4", "d": "Растение, расцветшее под солнцем."},
	"rainbow": {"name": "Радуга", "color": "#b96ad4", "d": "Свет, преломлённый в дожде."},
	"desert": {"name": "Пустыня", "color": "#e2b666", "d": "Песок, иссушённый солнцем."},
	"boat": {"name": "Лодка", "color": "#965434", "d": "Древесина, поплывшая по воде."},
	"coal": {"name": "Уголь", "color": "#555860", "d": "Древесина, обожжённая без пламени."},
	"wall": {"name": "Стена", "color": "#b0664a", "d": "Кирпичи, сложенные в преграду."},
	"house": {"name": "Дом", "color": "#8a5a3a", "d": "Стены под крышей — жилище."},
	"child": {"name": "Ребёнок", "color": "#f2c19a", "d": "Новая жизнь, рождённая людьми."},
	# Расширенные элементы (55-100)
	"rust": {"g": "metal", "name": "Ржавчина", "color": "#8b4513", "d": "Металл, разъеденный водой."},
	"blade": {"g": "tool", "name": "Лезвие", "color": "#c0c0c0", "d": "Металл, заточенный воздухом."},
	"coin": {"g": "gold", "name": "Монета", "color": "#daa520", "d": "Золото, принятое огнём форму круга."},
	"statue": {"g": "person", "name": "Статуя", "color": "#a9a9a9", "d": "Камень, принявший облик под рукой золотых дел мастера."},
	"light": {"g": "sun", "name": "Свет", "color": "#fffacd", "d": "Солнце, преломлённое в воде."},
	"plank": {"g": "wood", "name": "Доска", "color": "#deb887", "d": "Древесина, обработанная инструментом."},
	"barrel": {"g": "wood", "name": "Бочка", "color": "#8b4513", "d": "Доски, собранные в ёмкость."},
	"food": {"g": "fish", "name": "Еда", "color": "#cd853f", "d": "Рыба, приготовленная на огне."},
	"leather": {"g": "beast", "name": "Кожа", "color": "#8b4513", "d": "Шкура зверя, обработанная инструментом."},
	"smith": {"g": "fire", "name": "Кузнец", "color": "#b8860b", "d": "Человек, обуздавший огонь."},
	"swimmer": {"g": "water", "name": "Пловец", "color": "#4682b4", "d": "Человек, покоривший воду."},
	"thinker": {"g": "sky", "name": "Мыслитель", "color": "#9370db", "d": "Человек, поднявший взор к небу."},
	"farmer": {"g": "earth", "name": "Фермер", "color": "#6b8e23", "d": "Человек, обрабатывающий землю."},
	"egg": {"g": "bird", "name": "Яйцо", "color": "#f5f5dc", "d": "Птица, отложенная на камне."},
	"fruit": {"g": "flower", "name": "Фрукт", "color": "#ff6347", "d": "Цветок, напоённый водой до зрелости."},
	"wine": {"g": "rain", "name": "Вино", "color": "#722f37", "d": "Фрукт, перебродивший на огне."},
	"ceramic": {"g": "brick", "name": "Керамика", "color": "#d2691e", "d": "Грязь, обожжённая до твёрдости."},
	"chain": {"g": "metal", "name": "Цепь", "color": "#696969", "d": "Металл, скованный в звенья."},
	"boulder": {"g": "stone", "name": "Валун", "color": "#808080", "d": "Два камня, ставшие одним."},
	"fog": {"g": "mist", "name": "Туман густой", "color": "#778899", "d": "Облака, опустившиеся на землю."},
	"marsh": {"g": "swamp", "name": "Топь", "color": "#556b2f", "d": "Дождь, впитанный землёй без ухода."},
	"stream": {"g": "water", "name": "Ручей", "color": "#87ceeb", "d": "Снег, оживший от огня."},
	"island": {"g": "mountain", "name": "Остров", "color": "#2e8b57", "d": "Вулкан, поднявшийся из воды."},
	"flood": {"g": "rain", "name": "Потоп", "color": "#4169e1", "d": "Гроза, обрушившая все воды на землю."},
	"fulgurite": {"g": "lightning", "name": "Фульгурит", "color": "#daa520", "d": "Молния, попавшая в песок."},
	"hunt": {"g": "beast", "name": "Охота", "color": "#8b0000", "d": "Лес, ставший домом для зверя и человека."},
	"village": {"g": "house", "name": "Деревня", "color": "#bc8f8f", "d": "Лес, расчищенный человеком."},
	"town": {"g": "house", "name": "Город", "color": "#cd853f", "d": "Деревни, сложившиеся вместе."},
	"toy": {"g": "child", "name": "Игрушка", "color": "#ff69b4", "d": "Ребёнок, играющий инструментом."},
	"dragon": {"g": "beast", "name": "Дракон", "color": "#8b0000", "d": "Птица и зверь, ставшие легендой."},
	"axe": {"g": "tool", "name": "Топор", "color": "#a0522d", "d": "Металл, насаженный на древесину."},
	"hammer": {"g": "tool", "name": "Молот", "color": "#696969", "d": "Камень, привязанный к древесине."},
	"machine": {"g": "metal", "name": "Машина", "color": "#708090", "d": "Инструменты, собранные в механизм."},
	"soul": {"g": "life", "name": "Душа", "color": "#e6e6fa", "d": "Жизнь, очищенная от тела."},
	"golem": {"g": "stone", "name": "Голем", "color": "#2f4f4f", "d": "Камень, оживлённый душой."},
	"smog": {"g": "smoke", "name": "Смог", "color": "#556b2f", "d": "Дым, ставший удушьем."},
	"lye": {"g": "ash", "name": "Щелок", "color": "#dcdcdc", "d": "Пепел, растворённый в воде."},
	"soap": {"g": "cloud", "name": "Мыло", "color": "#fff8dc", "d": "Щелок, выпаренный огнём."},
	"adobe": {"g": "brick", "name": "Саман", "color": "#cd853f", "d": "Грязь, высушенная солнцем в кирпич."},
	"cabin": {"g": "house", "name": "Хижина", "color": "#8b4513", "d": "Дом, построенный из кирпича."},
	"fortress": {"g": "wall", "name": "Крепость", "color": "#708090", "d": "Стены, ставшие неприступными."},
	"lens": {"g": "glass", "name": "Линза", "color": "#e0ffff", "d": "Стекло, отшлифованное огнём."},
	"telescope": {"g": "sky", "name": "Телескоп", "color": "#483d8b", "d": "Линза, направленная на солнце."},
	"jewelry": {"g": "crystal", "name": "Украшение", "color": "#ffd700", "d": "Кристалл, оправленный в металл."},
	"king": {"g": "person", "name": "Король", "color": "#daa520", "d": "Человек, облечённый золотом."},
	"treasure": {"g": "gold", "name": "Сокровище", "color": "#ffd700", "d": "Монеты, сложенные в сундук."},
	"dye": {"g": "rainbow", "name": "Краска", "color": "#ff1493", "d": "Радуга, пойманная в воде."},
	"herd": {"g": "beast", "name": "Стадо", "color": "#8b4513", "d": "Звери, идущие вместе."},
	"school": {"g": "fish", "name": "Косяк", "color": "#4682b4", "d": "Рыбы, плывущие вместе."},
	"grove": {"g": "tree", "name": "Роща", "color": "#228b22", "d": "Деревья, вставшие вместе."},
	"garden": {"g": "flower", "name": "Сад", "color": "#ff69b4", "d": "Цветы, посаженные рядом."},
	"sprout": {"g": "seed", "name": "Росток молодой", "color": "#90ee90", "d": "Семя, накормленное водой."},
}

var RECIPES := [
	{"a": "fire", "b": "water", "out": "steam"},
	{"a": "earth", "b": "fire", "out": "stone"},
	{"a": "earth", "b": "water", "out": "clay"},
	{"a": "air", "b": "earth", "out": "dust"},
	{"a": "air", "b": "fire", "out": "spark"},
	{"a": "air", "b": "water", "out": "mist"},
	{"a": "clay", "b": "fire", "out": "brick"},
	{"a": "clay", "b": "water", "out": "plant"},
	{"a": "steam", "b": "air", "out": "cloud"},
	{"a": "air", "b": "stone", "out": "sand"},
	{"a": "mountain", "b": "water", "out": "ice"},
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
	{"a": "fire", "b": "plant", "out": "ash"},
	{"a": "metal", "b": "fire", "out": "gold"},
	{"a": "mud", "b": "plant", "out": "swamp"},
	{"a": "life", "b": "water", "out": "fish"},
	{"a": "life", "b": "air", "out": "bird"},
	{"a": "life", "b": "earth", "out": "beast"},
	{"a": "life", "b": "clay", "out": "person"},
	{"a": "plant", "b": "dust", "out": "seed"},
	{"a": "earth", "b": "plant", "out": "grass"},
	{"a": "storm", "b": "spark", "out": "lightning"},
	{"a": "storm", "b": "dust", "out": "tornado"},
	{"a": "person", "b": "stone", "out": "tool"},
	{"a": "seed", "b": "earth", "out": "tree"},
	{"a": "sky", "b": "fire", "out": "sun"},
	{"a": "glass", "b": "glass", "out": "crystal"},
	{"a": "sand", "b": "storm", "out": "sandstorm"},
	{"a": "swamp", "b": "plant", "out": "mushroom"},
	{"a": "tree", "b": "plant", "out": "forest"},
	{"a": "tree", "b": "stone", "out": "wood"},
	{"a": "sun", "b": "plant", "out": "flower"},
	{"a": "rain", "b": "sun", "out": "rainbow"},
	{"a": "sand", "b": "sun", "out": "desert"},
	{"a": "wood", "b": "water", "out": "boat"},
	{"a": "wood", "b": "fire", "out": "coal"},
	{"a": "brick", "b": "brick", "out": "wall"},
	{"a": "wall", "b": "wood", "out": "house"},
	{"a": "person", "b": "person", "out": "child"},
	# Расширенные рецепты (55-100)
	{"a": "metal", "b": "water", "out": "rust"},
	{"a": "metal", "b": "air", "out": "blade"},
	{"a": "gold", "b": "fire", "out": "coin"},
	{"a": "gold", "b": "stone", "out": "statue"},
	{"a": "sun", "b": "water", "out": "light"},
	{"a": "wood", "b": "tool", "out": "plank"},
	{"a": "plank", "b": "plank", "out": "barrel"},
	{"a": "fish", "b": "fire", "out": "food"},
	{"a": "beast", "b": "tool", "out": "leather"},
	{"a": "person", "b": "fire", "out": "smith"},
	{"a": "person", "b": "water", "out": "swimmer"},
	{"a": "person", "b": "air", "out": "thinker"},
	{"a": "person", "b": "earth", "out": "farmer"},
	{"a": "bird", "b": "stone", "out": "egg"},
	{"a": "flower", "b": "water", "out": "fruit"},
	{"a": "fruit", "b": "fire", "out": "wine"},
	{"a": "mud", "b": "fire", "out": "ceramic"},
	{"a": "metal", "b": "metal", "out": "chain"},
	{"a": "stone", "b": "stone", "out": "boulder"},
	{"a": "cloud", "b": "cloud", "out": "fog"},
	{"a": "rain", "b": "earth", "out": "marsh"},
	{"a": "snow", "b": "fire", "out": "stream"},
	{"a": "volcano", "b": "water", "out": "island"},
	{"a": "storm", "b": "water", "out": "flood"},
	{"a": "lightning", "b": "sand", "out": "fulgurite"},
	{"a": "forest", "b": "beast", "out": "hunt"},
	{"a": "forest", "b": "person", "out": "village"},
	{"a": "village", "b": "village", "out": "town"},
	{"a": "child", "b": "tool", "out": "toy"},
	{"a": "bird", "b": "beast", "out": "dragon"},
	{"a": "metal", "b": "wood", "out": "axe"},
	{"a": "wood", "b": "stone", "out": "hammer"},
	{"a": "tool", "b": "tool", "out": "machine"},
	{"a": "life", "b": "life", "out": "soul"},
	{"a": "soul", "b": "stone", "out": "golem"},
	{"a": "smoke", "b": "smoke", "out": "smog"},
	{"a": "ash", "b": "water", "out": "lye"},
	{"a": "lye", "b": "fire", "out": "soap"},
	{"a": "mud", "b": "sun", "out": "adobe"},
	{"a": "brick", "b": "house", "out": "cabin"},
	{"a": "wall", "b": "wall", "out": "fortress"},
	{"a": "glass", "b": "fire", "out": "lens"},
	{"a": "lens", "b": "sun", "out": "telescope"},
	{"a": "crystal", "b": "metal", "out": "jewelry"},
	{"a": "gold", "b": "person", "out": "king"},
	{"a": "coin", "b": "coin", "out": "treasure"},
	{"a": "rainbow", "b": "water", "out": "dye"},
	{"a": "beast", "b": "beast", "out": "herd"},
	{"a": "fish", "b": "fish", "out": "school"},
	{"a": "tree", "b": "tree", "out": "grove"},
	{"a": "flower", "b": "flower", "out": "garden"},
	{"a": "seed", "b": "water", "out": "sprout"},
]

# ---------- состояние ----------
var _engine: Core  # движок: варка/dnd/refresh/автоварка (R13)

# ---------- UI ----------
var _sound_btn: Button

# --- оформление: Manrope + Kenney UI (9-slice) ---
var _font_reg: Font = null
var _font_semi: Font = null
var _font_bold: Font = null
var _font_xbold: Font = null
var _ui_tex: Dictionary = {}   # path -> Texture2D (кэш)
var _tabs_ref: TabContainer
# F1 (раунд правки U18): признак достроенного UI. tabs.tab_changed срабатывает
# синхронно ещё во время _make_page(...), когда попапы не построены, — ветка
# interstitial в _on_tab_changed допускается только после достройки (true
# выставляется в конце _build_ui).
var _ui_ready := false
var _source_col: HBoxContainer
var _popup: Control
var _popup_dim: ColorRect = null
var _popup_orb: ElementOrb
var _popup_title: Label
var _popup_sub: Label
var floaters: Array = []
var _pulse_t := 0.0
var _time := 0.0
var _pulse_scale := 1.0

# автоварка (цепочка из книги рецептов)
var _confirm_dim: ColorRect
var _confirm: Control
var _confirm_orb: ElementOrb
var _confirm_l1: Label
var _confirm_l2: Label
var _confirm_l3: Label

# прокачка и режимы
var _pages: Pages  # вкладки: лаб/мир/инструменты + режимы (R11)
var _hub: Hub  # попапы: профиль/крафт/настройки/журнал/улучшения/престиж (R12)
var _item_colors: Dictionary = {}  # кэш цветов веществ (ядро)
var _online: Online  # рейтинг + сервер + мир (R8)
var _brew_bar: PanelContainer
# резонанс 2.0: отголоски (баланс/вечный счётчик с сервера + вехи в сейве)
var _resonance: Resonance  # отголоски + родословная (R5)
# ночная реторта: 3 слота {sub, name, started, dur} + коллекция эссенций {slug: имя}
var _retort: Retort  # ночная реторта (R6)
var _riddles: Riddles  # письма Светика + Атлас (оп B2)
var _retention: Retention  # дневной круг + недельный слой (R2)
var _demo_harness: Demo  # флаги --action/--shot/--geom + тик съёмки (R14)
var _demo_flip_timer: Dictionary = {}  # {card, at} — авто-флип для GIF
# сводка возврата: что случилось, пока игрока не было
var _saves: Saves  # сейвы + возвращение (R10)
var _last_rank := 0

# dev
var _selftest := false
# U22 (T26): снимки ТЕКСТА настоящих файлов (очередь аналитики и user.json), снятые
# в самом верху _ready. U23 (T27): читаются КОНСТАНТНЫМИ настоящими именами
# (Analytics.REAL_QUEUE_PATH / UserData.REAL_SAVE_PATH), а не живыми
# QUEUE_PATH/SAVE_PATH: автозагрузки переводят живые пути на ST-двойники в своих
# _ready — съём по живому пути сравнивал бы ST-двойник сам с собой, и кейс u22
# стал бы вакуумно-зелёным. Читает снимки Selftest.run в конце прогона
# (см. tests/selftest.gd).
var _analytics_text_at_boot := ""
var _user_data_text_at_boot := ""
var _me_avatar: Avatar = null
var _guild: Guild  # задания Светика + заказы + планировщик (R3)
var _progress_ui: Progress  # попап прогресса + ачивки + комплекты (R4)
var _last_ts := 0.0
var _bg_rect: ColorRect = null
var _home: Home  # дом, декор, палитра (R7)
var _shop: Shop  # магазин, rewarded и приватность
# произвольные цвета (палитра + RGB)
# магазин декора и палитра
# пары, отвергнутые сервером (фильтр намёков)
# рейтинг и чужие домики
var _set_rows: VBoxContainer = null
var _feed_list: VBoxContainer = null

var _spirit: Spirit  # Светик (R9)
var _admin: AdminConsole  # админ-консоль (~)
# Размер комплекта фиксирован генератором каталога (SET_SIZE = 25).
const SIGIL_SET_SIZE := 25
var _sigil: SigilManager  # Аркан Сигилов: карточки рецептов
var _sigil_coll: ColorRect = null  # модалка коллекции сигилов; != null ⇒ открыта
var _sigil_tab_content: Control = null  # контейнер активной вкладки модалки
var _sigil_tab: String = "crafts"  # активная вкладка: crafts | collection | sets
var _sigil_tab_btns: Array = []  # кнопки вкладок; подсветка активной в _sigil_show_tab
var _sigil_tab_seq := 0  # поколение вкладки: гасит корутины билдеров при переключении
var _sigil_fullscreen: Control = null  # полноэкранный просмотр карты; != null ⇒ открыт
## Живая карточка фуллскрина — для подачи tilt из _process. Обнуляется
## при закрытии, чтобы _process не дёргал удалённую ноду.
var _live_card_node: SigilCard = null
var _sigil_claim_layer: Control = null  # попап награды клейма майлстоуна; != null ⇒ открыт
var _sigil_set_screen: Control = null  # экран комплекта (Task 7b); != null ⇒ открыт
var _sigil_render_busy := false  # превью-рендер в полёте: у сервиса один SubViewport, фуллскрин ждёт (T5-M2)
var _sigil_header_btn: Button  ## кнопка Аркана Сигилов в шапке (иконка-таро)
var _inv_grid: GridContainer = null

func _boot_snapshot_text(path: String) -> String:
	# Только для U22/U23: снимок текста НАСТОЯЩЕГО файла — вызывается константными
	# реальными именами, а не живыми QUEUE_PATH/SAVE_PATH (те к этому моменту уже
	# переведены на ST-двойники в _ready автозагрузок). Отсутствующий файл даёт
	# пустую строку — так же, как и пустой файл, поэтому «нет файла» и «файл пуст»
	# сравниваются корректно (см. tests/selftest.gd).
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _ready() -> void:
	# U22 (T26) / U23 (T27): разбор аргументов и снимки настоящих файлов — в самом
	# верху _ready. С U23 пути переведены на ST-двойники ещё в _ready автозагрузок
	# (он раньше этого вызова), поэтому настоящие файлы в самопрогоне только
	# читаются: first-run fingerprint (UserData._ready -> _load/_save, App._ready ->
	# ensure_install_metadata) больше в них не пишется, и снимок здесь — честная
	# точка отсчёта для сверки в конце прогона. Снимок читается константными
	# настоящими именами: живые QUEUE_PATH/SAVE_PATH к этому моменту уже ST-двойники.
	# Оговорка U22 про гибрид `--selftest --demo --action=hint` без `--shot=`
	# снята: вызываемый демо-обходом Analytics.track пишет в ST-двойник очереди.
	var args := OS.get_cmdline_user_args()
	_selftest = SelftestMode.enabled()
	_analytics_text_at_boot = _boot_snapshot_text(Analytics.REAL_QUEUE_PATH)
	_user_data_text_at_boot = _boot_snapshot_text(UserData.REAL_SAVE_PATH)
	_riddles = Riddles.new(self)
	_retention = Retention.new(self)
	_guild = Guild.new(self)
	_progress_ui = Progress.new(self)
	_resonance = Resonance.new(self)
	_retort = Retort.new(self)
	_home = Home.new(self)
	_shop = Shop.new(self)
	_online = Online.new(self)
	_spirit = Spirit.new(self)
	if OS.has_feature("editor"):
		_admin = AdminConsole.new(self)
	_saves = Saves.new(self)
	_sigil = SigilManager.new()
	_sigil.name = "SigilManager"
	add_child(_sigil)
	_sigil.set_player_salt(OS.get_unique_id())
	Monetization.bind_game(self)
	# Прогон selftest не эмитит онбординг-аналитику: это не сессия реального
	# пользователя. С U23 (T27) пути уже переведены в _ready автозагрузок, и эти
	# вызовы писали бы в ST-двойники, но гейт остаётся: session_start безусловно
	# поднимает session_count в контейнере прогона (а при выданном согласии — ещё
	# и события в память), а стартовое состояние кейсов должно быть чистым.
	# Снятие гейта красит кейс u23 в начале Selftest.run (session_count == 0).
	if not _selftest:
		Analytics.session_start("icon")
		Analytics.track("app_open", {"store": App.store_id, "consent": App.analytics_consent()})
	_pages = Pages.new(self)
	_hub = Hub.new(self)
	_engine = Core.new(self)
	_demo_harness = Demo.new(self)
	_demo_harness._demo = args.has("--demo")
	_demo_harness._geom = args.has("--geom")
	_demo_harness._probe = args.has("--probe")
	for a in args:
		if a.begins_with("--demo-confirm="):
			_demo_harness._demo_confirm = a.substr("--demo-confirm=".length())
	for a in args:
		if a == "--action=upgrades":
			_demo_harness._action_upgrades = true
		elif a == "--action=hint":
			_demo_harness._action_hint = true
		elif a == "--action=event":
			_demo_harness._action_event = true
		elif a == "--action=companion":
			_demo_harness._action_companion = true
		elif a == "--action=profile":
			_demo_harness._action_profile = true
		elif a == "--action=rarity":
			_demo_harness._action_rarity = true
		elif a == "--action=quests":
			_demo_harness._action_quests = true
		elif a == "--action=prestige":
			_demo_harness._action_prestige = true
		elif a == "--action=journal":
			_demo_harness._action_journal = true
		elif a == "--action=settings":
			_demo_harness._action_settings = true
		elif a == "--action=craftable":
			_demo_harness._action_craftable = true
		elif a == "--action=workshop":
			_demo_harness._action_workshop = true
		elif a == "--action=rating":
			_demo_harness._action_rating = true
		elif a == "--action=decor":
			_demo_harness._action_decor = true
		elif a == "--action=guesthouse":
			_demo_harness._action_guesthouse = true
		elif a == "--action=palette":
			_demo_harness._action_palette = true
		elif a == "--action=glyphs":
			_demo_harness._action_glyphs = true
		elif a == "--action=resonance":
			_demo_harness._action_resonance = true
		elif a == "--action=retort":
			_demo_harness._action_retort = true
		elif a == "--action=retortpick":
			_demo_harness._action_retortpick = true
		elif a == "--action=return":
			_demo_harness._action_return = true
		elif a == "--action=letter":
			_demo_harness._action_letter = true
		elif a == "--action=atlas":
			_demo_harness._action_atlas = true
		elif a == "--action=experiment":
			_demo_harness._action_experiment = true
		elif a == "--action=brewprofile":
			_demo_harness._action_brewprofile = true
		elif a == "--action=circle":
			_demo_harness._action_circle = true
		elif a == "--action=sigilcoll":
			_demo_harness._action_sigilcoll = true
		elif a == "--action=week":
			_demo_harness._action_week = true
		elif a == "--action=goal":
			_demo_harness._action_goal = true
		elif a == "--action=goals":
			_demo_harness._action_goals = true
	for a in args:
		if a.begins_with("--gif="):
			_demo_harness._gif_dir = a.substr("--gif=".length())
		elif a.begins_with("--shot="):
			_demo_harness._shot_path = a.substr("--shot=".length())
		elif a.begins_with("--tab="):
			_demo_harness._shot_tab = a.substr("--tab=".length()).to_int()
		elif a.begins_with("--scroll="):
			_demo_harness._shot_scroll = a.substr("--scroll=".length()).to_int()
		elif a.begins_with("--netbrew="):
			_online._netbrew_pair = a.substr("--netbrew=".length())
		elif a.begins_with("--netexperiment="):
			_online._netexperiment_pair = a.substr("--netexperiment=".length())
		elif a.begins_with("--decor="):
			_demo_harness._decor_demo_cat = a.substr("--decor=".length())
		elif a.begins_with("--sigiltab="):
			_demo_harness._sigil_tab = a.substr("--sigiltab=".length())
	_online._net_enabled = not _selftest
	if _online._net_enabled:
		_online._device_id = _online._load_device_id()
		Net.pair_result.connect(_online._on_net_pair_result)
		Net.discover_result.connect(_online._on_net_discover_result)
		Net.world_result.connect(_online._on_net_world_result)
		Net.hall_result.connect(_online._on_net_hall_result)
		Net.events_result.connect(_online._on_net_events_result)
		Net.challenge_result.connect(_online._on_net_challenge_result)
		Net.me_result.connect(_hub._on_net_me_result)
		Net.rejected_result.connect(_online._on_net_rejected_result)
		Net.house_result.connect(_online._on_net_house_result)
		Net.house_visit_result.connect(_online._on_net_house_visit_result)
		Net.rating_result.connect(_online._on_net_rating_result)
		Net.echoes_result.connect(_resonance._on_net_echoes_result)
		Net.echoes_claim_result.connect(_resonance._on_net_echoes_claim_result)
		Net.letter_result.connect(_riddles._on_net_letter_result)
		Net.letter_solve_result.connect(_riddles._on_net_letter_solve_result)
		# письма нужны сразу (матчинг каждой варки); ping уже в очереди первым
		Net.letter_today(_online._device_id)
		Net.atlas_result.connect(_riddles._on_net_atlas_result)
		Net.atlas_solve_result.connect(_riddles._on_net_atlas_solve_result)
		Net.atlas_today(_online._device_id)
		Net.week_result.connect(_retention._on_net_week_result)
		Net.fair_brew_result.connect(_retention._on_net_fair_brew_result)
		Net.fair_claim_result.connect(_retention._on_net_fair_claim_result)
		Net.week_status(_online._device_id)
		Net.cycle_status(_online._device_id)
		# #8: доводка удаления аккаунта. Хендлер чистит маркер при ok; ретрай
		# поднимает незавершённое удаление прошлой сессии (маркер переживает
		# вайп). В селфтесте блок не выполняется: _net_enabled = not _selftest.
		Net.account_delete_result.connect(_online._on_account_delete_result)
		_online._retry_pending_account_delete()
	# План 2 (жила/круг): connects вне _net_enabled-блока — хендлеры сами
	# гейтят offline/ok, а ST эмитит сигналы напрямую (suite_vein_circle).
	Net.cycle_result.connect(_retention._on_net_cycle_result)
	Net.vein_find_result.connect(_retention._on_net_vein_find_result)
	Net.vein_pour_result.connect(_retention._on_net_vein_pour_result)
	# Аркан Сигилов
	Net.sigil_daily_result.connect(_sigil._on_daily_result)
	Net.sigil_craft_result.connect(_sigil._on_craft_result)
	Net.sigil_catalog_result.connect(_sigil._on_catalog_result)
	Net.sigil_collection_result.connect(_sigil._on_collection_result)
	Net.sigil_milestone_result.connect(_sigil._on_milestone_result)
	Net.sigil_milestone_result.connect(_on_sigil_milestone_result)
	_sigil.craft_completed.connect(_on_sigil_craft_completed)
	_sigil.craft_failed.connect(_on_sigil_craft_failed)
	# Task 8: достижения карточек обновляются при любой смене коллекции. В selftest
	# _ach_update no-op (g._selftest), поэтому коннект безопасен и в прогоне сьютов.
	_sigil.collection_changed.connect(_progress_ui._ach_update)
	_init_new_game()
	_saves._load_game()
	_build_ui()
	_shop.build()
	if not _selftest and not App.consent_is_decided():
		_shop._open_consent.call_deferred()
	if _demo_harness._demo:
		_demo_harness._apply_demo_state()
	_engine._refresh()
	if not _selftest and _engine._experiment_pending_pair.size() == 2:
		_online._resume_pending_experiment.call_deferred()
	if not _selftest and not _demo_harness._demo:
		_retention._circle_track_visit()
	if not _selftest and _online._net_enabled:
		Net.me(_online._net_nick, _online._device_id)
	if not _selftest:
		_spirit._companion_hello.call_deferred()
	if _demo_harness._shot_tab >= 0:
		var tc: TabContainer = get_node_or_null("Margin/Root/Tabs")
		if tc != null:
			tc.current_tab = _demo_harness._shot_tab
	if _demo_harness._demo and _demo_harness._action_upgrades:
		_hub._open_upgrades()
	if _demo_harness._demo and _demo_harness._action_hint:
		# для кадра подсказку жмём ближе к моменту съёмки, чтобы кольцо было видно
		if _demo_harness._shot_path != "":
			_demo_harness._pending_hint_shot = true
		else:
			_pages._hint()
			_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_event:
		_online._spawn_event()
	if _demo_harness._demo and _demo_harness._action_prestige:
		for i in 33:
			_engine.inventory["st_demo_%d" % i] = 1
		_hub._open_upgrades()
		_hub._open_prestige_confirm.call_deferred()
	if _demo_harness._demo and _demo_harness._action_quests:
		_progress_ui._open_progress_popup()
	if _demo_harness._demo and _demo_harness._action_craftable:
		_engine.inventory["fire"] = 2
		_engine.inventory["water"] = 2
		_engine.inventory["earth"] = 2
		_hub._open_craftable()
	if _demo_harness._demo and _demo_harness._action_workshop:
		_home._cosmetic_house = true
		_home.house_furniture = {"window": "window", "rug": "rug_1", "lamp": "lamp", "plant": "plant",
			"table": "table", "chair": "chair", "shelf": "shelf", "bed": "bed_3"}
		_home.house_owned = {"rug": ["rug_1", "rug_4"], "bed": ["bed_3"]}
		_home._apply_cosmetic()
		_home._open_workshop()
	if _demo_harness._demo and _demo_harness._action_rating:
		if _tabs_ref != null:
			_tabs_ref.current_tab = 4
	if _demo_harness._demo and _demo_harness._action_decor:
		_home._cosmetic_house = true
		_home.house_owned = {"rug": ["rug_1"]}
		_home._apply_cosmetic()
		if _tabs_ref != null:
			_tabs_ref.current_tab = 3
		_home._refresh_house_page()
		_home._open_decor_shop(_demo_harness._decor_demo_cat)
	if _demo_harness._demo and _demo_harness._action_guesthouse:
		_home._apply_player_house("Люмина", {"built": true, "theme": "ember", "aura": "rose",
			"wall": "#3f6d5a", "floor": "#4a3a28",
			"furniture": {"window": "window_2", "rug": "rug_2", "bed": "bed_3", "lamp": "lamp_1", "plant": "plant_4"}})
		_home._house_popup.visible = true
	if _demo_harness._demo and _demo_harness._action_palette:
		_home._cosmetic_house = true
		_home._apply_cosmetic()
		if _tabs_ref != null:
			_tabs_ref.current_tab = 3
		_home._open_color_picker("wall")
	if _demo_harness._demo and _demo_harness._action_glyphs:
		# витрина параметрических глифов (диагностика рендера)
		for spec in ["poly3", "star6", "burst8", "ring3", "cluster5", "crystal4", "blossom6", "sigil4", "spiral3", "rays7"]:
			var sid := "g_%s" % spec
			ITEMS[sid] = {"name": spec, "g": spec, "layer": 3}
			_item_colors[sid] = Color.from_hsv(float(hash(spec) % 360) / 360.0, 0.5, 0.85)
			_engine.inventory[sid] = 1
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_resonance:
		_progress_ui._ach_world_first = 1
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("resonance")
		# витрина без сервера: состояние подставляем напрямую
		_resonance._res_balance = 7
		_resonance._res_total = 12
		_resonance._res_echo_ether = 5
		_resonance._res_cap = 20
		_resonance._res_done = {10: true}
		_resonance._res_top = [{"name": "Лунная роса", "slug": "moon_dew", "count": 9}]
		_resonance._res_desc_total = 3
		_resonance._res_desc = [
			{"name": "Туманный янтарь", "slug": "x1", "by": "Люмина", "at": ""},
			{"name": "Тихая искра", "slug": "x2", "by": "Бор", "at": ""},
		]
		_resonance._res_apprentice = {"name": "Лунная роса", "slug": "moon_dew"}
		_resonance._refresh_resonance_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_retort:
		var now := Time.get_unix_time_from_system()
		_retort._essences = {"fire": "Огонь", "water": "Вода", "clay": "Глина"}
		_retort._retort_slots = [
			{"sub": "steam", "name": "Пар", "started": now - 4.0 * 3600.0, "dur": 8.0 * 3600.0},
			{"sub": "glass", "name": "Стекло", "started": now - 13.0 * 3600.0, "dur": 12.0 * 3600.0},
			{"sub": "", "name": "", "started": 0.0, "dur": 0.0},
		]
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("retort")
		_retort._refresh_retort_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_retortpick:
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("retort")
		_engine._refresh()
		_retort._open_retort_picker(0)
	if _demo_harness._demo and _demo_harness._action_letter:
		_riddles._inject_letter_demo()
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("letters")
		_riddles._refresh_letters_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_atlas:
		_riddles._inject_atlas_demo()
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("atlas")
		_riddles._refresh_atlas_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_circle:
		_retention._inject_circle_demo()
		# страница «Круг» открывается с 20 веществ — демо-доливка до гейта
		for cid in ITEMS.keys():
			if _engine.inventory.size() >= 22:
				break
			if not _engine.inventory.has(String(cid)):
				_engine.inventory[String(cid)] = 1
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("circle")
		_retention._refresh_circle_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_sigilcoll:
		_demo_seed_sigil_coll()
	if _demo_harness._demo and _demo_harness._action_week:
		_retention._inject_week_demo()
		# страница «Неделя» открывается с 30 веществ — демо-доливка до гейта
		for wid in ITEMS.keys():
			if _engine.inventory.size() >= 32:
				break
			if not _engine.inventory.has(String(wid)):
				_engine.inventory[String(wid)] = 1
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("week")
		_retention._refresh_week_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_goal:
		# кадр модалки выбора цели: собираем пару и открываем режимный экран
		if _tabs_ref != null:
			_tabs_ref.current_tab = 0
		_engine.ether = 100
		_engine.selected.clear()
		_engine._place_into_slot("fire", "A")
		_engine._place_into_slot("water", "B")
		_on_brew_btn_pressed()
	if _demo_harness._demo and _demo_harness._action_goals:
		if _tabs_ref != null:
			_tabs_ref.current_tab = 0
		_engine.ether = 100
		_engine.selected.clear()
		_engine._place_into_slot("fire", "A")
		_engine._place_into_slot("water", "B")
		_on_brew_btn_pressed()
	if _demo_harness._demo and _demo_harness._action_settings:
		_hub._open_settings()
	if _demo_harness._demo and _demo_harness._action_journal:
		_hub._log_event("Открыто вещество «Стекло»")
		_hub._log_event("Достижение: Первооткрыватель")
		_hub._log_event("Задание Светика: Первая пара")
		_hub._log_event("Комплект стихии: Огонь")
		_hub._log_event("Перегонка: +2 Золота мудрецов")
		_hub._open_journal()
	if _demo_harness._demo and _demo_harness._action_rarity:
		_engine.known_recipes[_pair_key("glass", "glass")] = true
		_engine._layer_cache.clear()
		_show_discovery_popup("crystal", "glass", "glass")
	if _demo_harness._demo and _demo_harness._action_profile:
		_hub._open_profile()
	if _demo_harness._demo and _demo_harness._action_companion:
		_spirit._companion_unlocked = true
		_spirit._companion_met = true
		_spirit._player_name = "Алхимик"
		_spirit._companion.say("Ты вернулся! Котёл уже булькает.", "happy")
		_spirit._companion_open_dialog("Ты вернулся! Котёл уже булькает. Как продвигается алхимия?", false)
	if _demo_harness._shot_scroll >= 0:
		_demo_harness._set_page_scroll.call_deferred(_demo_harness._shot_scroll)
	if _demo_harness._demo_confirm != "" and not _selftest:
		_engine._auto_craft.call_deferred(_demo_harness._demo_confirm)
		_demo_harness._auto_confirm_demo.call_deferred()
	if _online._netbrew_pair != "" and not _selftest:
		var parts := _online._netbrew_pair.split(",")
		if parts.size() == 2:
			_online._run_netbrew.call_deferred(parts[0], parts[1])
	var want_return := (_saves._return_due() and not _demo_harness._demo) or (_demo_harness._demo and _demo_harness._action_return)
	if not _selftest and not _saves._return_shown and want_return:
		if _demo_harness._demo and _demo_harness._action_return:
			_saves._inject_return_demo()
		_saves._open_return_popup()
		if _online._net_enabled and Net.is_available():
			Net.echoes(_online._device_id)
			Net.rating(_online._device_id)
			Net.world(1)
			Net.letter_today(_online._device_id)
			Net.atlas_today(_online._device_id)
			Net.week_status(_online._device_id)
	if _selftest:
		_run_selftest()
	else:
		# Вход в игру: приветственный звук (не в selftest-прогоне).
		Sfx.game_start()

# ---------- R14: см. game/demo.gd (616-620) ----------


func _process(delta: float) -> void:
	# get_tree().quit() разбирает дерево, а движок ещё несколько кадров зовёт
	# _process: все модули-члены уже обнулены, и каждый такой кадр печатает
	# «Invalid call ... in base 'Nil'» в user://logs (7 застрявших прогонов
	# накатали 6,7 ГБ за ночь). _demo_harness назначается последним из модулей
	# в _parse_args, поэтому null = «кадр после разбора», а не «до старта игры».
	if _demo_harness == null:
		return
	_time += delta
	# GIF-демо: авто-переворот карточки по таймеру.
	if not _demo_flip_timer.is_empty() and Time.get_ticks_msec() >= int(_demo_flip_timer.get("at", 0)):
		var card_flip: Control = _demo_flip_timer.get("card", null)
		_demo_flip_timer = {}
		if card_flip != null and is_instance_valid(card_flip):
			_sigil_flip_card(_tap_event(), card_flip)
	if not _selftest:
		_online._tick_netexperiment()
		_online._tick_pending_experiment()
	if _tabs_ref != null and not _selftest and _online._net_enabled:
		if _tabs_ref.current_tab == 2:
			_online._world_poll += delta
			if _online._world_poll > 25.0:
				_online._world_poll = 0.0
				Net.events()
				Net.challenge(_online._device_id)
		elif _tabs_ref.current_tab == 4:
			_online._rating_poll += delta
			if _online._rating_poll > 25.0:
				_online._rating_poll = 0.0
				Net.rating(_online._device_id)
	if _spirit._companion != null and _spirit._companion.visible and not _selftest:
		_spirit._companion_idle_clock += delta
		if _spirit._companion_idle_clock > 38.0:
			_spirit._companion_idle_clock = 0.0
			_spirit._companion_react("idle", "")
	if _demo_harness._tick_demo():
		return
	_engine.autosave_clock += delta
	_engine.regen_clock += delta * _engine._ether_rate()
	if _engine.regen_clock >= 1.0:
		var ticks := int(_engine.regen_clock)
		_engine.regen_clock -= float(ticks)
		_engine.ether = mini(_engine._max_ether(), _engine.ether + ticks)
		_engine._refresh_header()
	_engine._spring_tick(delta)
	_engine._gift_tick(delta)
	_pages._experiment_tick()
	_pages._bench_tick(delta)
	_online._event_tick(delta)
	if _engine.brewing and _engine._progress != null:
		_engine.brew_elapsed += delta
		_engine._progress.value = minf(100.0, _engine.brew_elapsed / _engine._brew_time() * 100.0)
	if _engine.autosave_clock >= 10.0:
		_engine.autosave_clock = 0.0
		_saves._save_game()
	# пульсация кнопки «Варить», когда можно
	if _engine._brew_btn != null:
		var can := _engine._can_brew() and not _engine._auto
		_engine._brew_btn.disabled = not can
		if can:
			_pulse_t += delta
			var k := 1.0 + 0.05 * (0.5 + 0.5 * sin(_pulse_t * 4.0))
			_engine._brew_btn.scale = Vector2(k, k)
		else:
			_engine._brew_btn.scale = Vector2.ONE
	if _engine._cauldron != null:
		_engine._cauldron.set_flame(1.0 if _engine.brewing else 0.0)
	if _engine._ghost != null:
		var gp := get_global_mouse_position()
		_engine._ghost.position = gp - _engine._ghost.size * 0.5
		# Параллакс открытой карточки: тянем tilt за курсором. Только когда
	# фуллскрин реально открыт и нода жива; иначе не трогаем.
	if _sigil_fullscreen != null and _live_card_node != null \
			and is_instance_valid(_live_card_node):
		var m := get_viewport().get_mouse_position()
		var vp_sz := get_viewport_rect().size
		var tilt_n := Vector2(
			(m.x / maxf(vp_sz.x, 1.0) - 0.5) * 2.0,
			(m.y / maxf(vp_sz.y, 1.0) - 0.5) * 2.0)
		_live_card_node.set_tilt(tilt_n)
	for i in range(floaters.size() - 1, -1, -1):
		var f: Dictionary = floaters[i]
		f["t"] += delta
		var lb: Label = f["l"]
		lb.position.y -= 52.0 * delta
		var life: float = f["life"]
		lb.modulate.a = clampf((life - f["t"]) / 0.3, 0.0, 1.0)
		if f["t"] >= life:
			lb.queue_free()
			floaters.remove_at(i)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_saves._save_game()

# ---------- R14: см. game/demo.gd (716-805) ----------


# ================= состояние =================

func _init_new_game() -> bool:
	# U9 (T12): новый старт во время активной потребляющей трассы/эксперимента
	# бросает сонные корутины на свежий подарочный запас — отказываемся с хинтом.
	if _engine.brewing or _engine._auto or _engine._experiment_pending_pair.size() == 2:
		_engine.status_text = "Начать заново нельзя: идёт варка, производство или ждёт ответа эксперимент. Дождись завершения."
		Sfx.error()
		return false
	# U9 (T12): смена поколения — любая проснувшаяся корутина старого мира выходит молча.
	_engine.brew_epoch += 1
	_engine.inventory.clear()
	_engine.known_recipes.clear()
	_engine.selected.clear()
	_engine.upgrades.clear()
	_engine.spring_on = false
	_pages._spring_clock = 0.0
	_pages._bench_target = ""
	_pages._bench_on = false
	_pages._bench_clock = 0.0
	_engine._gift_clock = 0.0
	_engine._source_taps = 0
	for item_id in BASE_IDS:
		_engine.inventory[item_id] = 5
	_engine.known_recipes[_pair_key("fire", "water")] = true
	_engine.known_recipes[_pair_key("earth", "fire")] = true
	_engine.ether = START_ETHER
	_engine.ether_overflow = 0
	_engine.mastery_rank = 0
	_engine._experiment_day = Time.get_date_string_from_system()
	_engine._experiment_count = 0
	_engine._experiment_last_at = 0.0
	_engine._experiment_pending_pair.clear()
	# U11 (T14): сброс мира аннулирует и мир-запросы в полёте — их ответы
	# больше не должны применяться к новому миру (иначе записи ждали бы TTL).
	_online._pending_requests.clear()
	_engine._craft_job.clear()
	_engine._blueprints.clear()
	_engine.attempts = 0
	_engine.successes = 0
	return true

# ---------- R14: см. game/demo.gd (829-852) ----------


# ================= UI: сборка =================

func _build_ui() -> void:
	_online._init_colors()
	_font_reg = _load_font("res://assets/fonts/Manrope-Regular.ttf")
	_font_semi = _load_font("res://assets/fonts/Manrope-SemiBold.ttf")
	_font_bold = _load_font("res://assets/fonts/Manrope-Bold.ttf")
	_font_xbold = _load_font("res://assets/fonts/Manrope-ExtraBold.ttf")
	var th := Theme.new()
	# Базовый размер рассчитан под Android portrait: иерархия строится
	# размерами конкретных заголовков, а не крупным шрифтом по умолчанию.
	th.default_font_size = 16
	if _font_reg != null:
		th.default_font = _font_reg
	theme = th

	var bg := ColorRect.new()
	bg.color = _home._theme_color(_home._cosmetic_theme)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg_rect = bg

	# Используем обычный Control-хост вместо MarginContainer: контейнеры не должны
	# раздувать корневой экран до высоты своего прокручиваемого содержимого.
	var margin := Control.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 12
	margin.offset_right = -12
	margin.offset_top = 12
	margin.offset_bottom = -14
	add_child(margin)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	# Явно фиксируем anchors после добавления в Control-хост: вызов preset
	# до parent мог сохранить старый offset и растянуть VBox за пределы экрана.
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 0.0
	root.offset_top = 0.0
	root.offset_right = 0.0
	root.offset_bottom = 0.0
	# На первом кадре Control-хост уже имеет размер окна, но VBoxContainer
	# может успеть посчитать собственный минимум раньше привязки anchors.
	# Фиксируем корень по хосту и поддерживаем это при повороте/resize.
	margin.resized.connect(func() -> void:
		root.set_size(margin.size)
	)
	root.set_size(margin.size)
	call_deferred("_fit_ui_root_after_layout", margin, root)

	# шапка
	var head := HBoxContainer.new()
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(head)
	var title := _label("ПЕТЛЯ АЛХИМИКА", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _font_xbold != null:
		title.add_theme_font_override("font", _font_xbold)
	title.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	head.add_child(title)
	var quests_btn := _small_button("✦", Vector2(46, 36), 2)
	quests_btn.tooltip_text = "Задания Светика, достижения, комплекты, заказы"
	quests_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quests_btn.pressed.connect(_progress_ui._open_progress_popup)
	head.add_child(quests_btn)
	var sigil_btn := _tarot_button()
	_sigil_header_btn = sigil_btn
	sigil_btn.tooltip_text = "Аркан Сигилов: ежедневные крафты"
	sigil_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sigil_btn.pressed.connect(_open_sigil_modal)
	head.add_child(sigil_btn)
	_hub._up_btn = _small_button("▲", Vector2(46, 36))
	_hub._up_btn.tooltip_text = "Улучшения"
	_hub._up_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hub._up_btn.pressed.connect(_hub._open_upgrades)
	head.add_child(_hub._up_btn)
	_sound_btn = _small_button("♪", Vector2(46, 36))
	_sound_btn.tooltip_text = "Настройки звука"
	_sound_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sound_btn.pressed.connect(_hub._open_settings)
	head.add_child(_sound_btn)
	var log_btn := _small_button("Ж", Vector2(46, 36))
	log_btn.tooltip_text = "Журнал событий"
	log_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	log_btn.pressed.connect(_hub._open_journal)
	head.add_child(log_btn)
	var me_btn := Button.new()
	me_btn.custom_minimum_size = Vector2(46, 36)
	me_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	me_btn.tooltip_text = "Профиль: твоё имя и аватар"
	me_btn.pressed.connect(_hub._open_profile)
	var mb := _stylebox_9("res://assets/ui/btn_secondary.png", Vector4(14, 12, 14, 12))
	if mb != null:
		me_btn.add_theme_stylebox_override("normal", mb)
		var mbh := _stylebox_9("res://assets/ui/btn_secondary.png", Vector4(14, 12, 14, 12), Color(1.2, 1.22, 1.18, 1))
		me_btn.add_theme_stylebox_override("hover", mbh)
	me_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me_btn.add_child(cc)
	_me_avatar = _make_avatar(_online._net_nick, 24)
	cc.add_child(_me_avatar)
	head.add_child(me_btn)

	var ether_row := HBoxContainer.new()
	ether_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ether_row.add_theme_constant_override("separation", 8)
	root.add_child(ether_row)
	_engine._ether_label = _label("", 14)
	_engine._ether_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_engine._ether_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_engine._ether_label.clip_text = true
	ether_row.add_child(_engine._ether_label)
	var home_btn := _small_button("Дом", Vector2(82, 34), 2)
	home_btn.tooltip_text = "Дом Светика: построй домик, обставь его, смени тему и ауру"
	home_btn.pressed.connect(_home._open_workshop)
	ether_row.add_child(home_btn)
	var market_btn := _small_button("Лавка", Vector2(82, 34), 1)
	market_btn.tooltip_text = "Покупки, награды за просмотр и приватность"
	market_btn.pressed.connect(_shop.open)
	ether_row.add_child(market_btn)
	_engine._collection_label = _label("", 14)
	_engine._collection_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(_engine._collection_label)
	_guild._quest_label = Button.new()
	_guild._quest_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_guild._quest_label.flat = true
	_guild._quest_label.add_theme_font_size_override("font_size", 13)
	_guild._quest_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_guild._quest_label.tooltip_text = "Нажми, чтобы открыть задания и достижения"
	_guild._quest_label.pressed.connect(_progress_ui._open_progress_popup)
	root.add_child(_guild._quest_label)

	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	# TabContainer не должен рисоваться поверх фиксированной нижней панели.
	# BrewBar добавлен после Margin/Root и при одинаковом z-уровне остаётся
	# выше прокручиваемого содержимого лаборатории, но ниже modal popup.
	tabs.z_index = 0
	_tabs_ref = tabs
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Нижняя навигация: QTE-событие не должно появляться поверх вкладок (док §7).
	tabs.add_to_group("qte_exclusion")
	tabs.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.13, 0.18, 0.35), 14))
	# Вкладки должны помещаться на portrait-экране целиком: «Эксперимент»
	# нельзя терять из видимой навигации при переходе в Лабораторию.
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.add_theme_constant_override("tab_hseparation", 6)
	tabs.add_theme_constant_override("tab_vseparation", 4)
	tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(tabs)

	var experiment := _make_page(tabs, "Эксперимент")
	_pages._build_experiment_location(experiment)
	var lab := _make_page(tabs, "Лаборатория")
	_pages._build_lab(lab)
	var world := _make_page(tabs, "Мир")
	_pages._build_world(world)
	var house := _make_page(tabs, "Дом")
	_home._build_house_page(house)
	var rating := _make_page(tabs, "Рейтинг")
	_online._build_rating_page(rating)
	var tools := _make_page(tabs, "Инструменты")
	_pages._build_tools_page(tools)

	_build_brew_bar()
	_spirit._build_companion()
	_build_popup()
	_build_confirm()
	_spirit._build_companion_dialog()
	_hub._build_upgrade_popup()
	_hub._build_profile_popup()
	_progress_ui._build_progress_popup()
	_hub._build_journal_popup()
	_hub._build_settings_popup()
	_hub._build_craftable_popup()
	_retort._build_retort_picker()
	_saves._build_return_popup()
	_hub._build_prestige_popup()
	_home._build_decor_popup()
	_home._build_color_picker()
	_home._build_house_popup()
	# Событие мира — глобальный QTE поверх текущей вкладки, не кнопка в «Мире».
	_online._build_event_qte()
	# UX-слой онлайн-части (тосты + индикатор сети) — поверх страниц,
	# ниже модалок (док «refactor online.gd.md» §16).
	# UX-слой онлайн-части (тосты + индикатор сети) — поверх страниц, ниже модалок
	# (док «refactor online.gd.md» §16). В selftest не строится: сюита UX строит
	# и сносит слой сама, а «фоновый» CanvasLayer менял замер троттла redraw (u14).
	if not _selftest:
		_online._build_online_ux()
	_home._apply_cosmetic()
	_update_brew_bar_visibility()
	_spirit._refresh_companion_visible()
	# Все поверхности построены — граница навигации имеет право показывать
	# interstitial (см. _ui_ready в _on_tab_changed).
	_ui_ready = true

func _fit_ui_root_after_layout(host: Control, root: Control) -> void:
	# Два кадра дают всем динамическим страницам посчитать minimum size;
	# после этого корень должен занять именно доступное окно, а не сумму страниц.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(host) and is_instance_valid(root):
		root.set_size(host.size)

func _build_brew_bar() -> void:
	# панель «ВАРИТЬ» всегда на экране — независимо от прокрутки страницы
	var bar := PanelContainer.new()
	bar.name = "BrewBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_top = -132
	bar.offset_bottom = -12
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _panel_style(Color(0.07, 0.10, 0.15, 0.96), 18)
	bar.add_theme_stylebox_override("panel", sb)
	# QTE-событие не должно появляться поверх панели варки (док §7).
	bar.add_to_group("qte_exclusion")
	add_child(bar)
	_brew_bar = bar

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(col)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	var collect_all_btn := _small_button("Все", Vector2(48, 42))
	collect_all_btn.tooltip_text = "Добыть со всех источников сразу"
	collect_all_btn.pressed.connect(_engine._collect_all)
	row.add_child(collect_all_btn)
	# источники живут в панели: добыча доступна с любого места страницы
	_source_col = HBoxContainer.new()
	_source_col.add_theme_constant_override("separation", 6)
	row.add_child(_source_col)
	for item_id in BASE_IDS:
		var orb := _make_orb(item_id, 44)
		orb.tooltip_text = "%s — тапнуть, чтобы добыть" % _online._item_name(item_id)
		orb.tapped.connect(_engine._on_source_tapped.bind(item_id))
		orb.drag_started.connect(_engine._on_orb_drag_started.bind(item_id))
		orb.drag_ended.connect(_engine._on_orb_drag_ended.bind(item_id))
		_source_col.add_child(orb)
		_engine._source_orbs[item_id] = orb

	_engine._brew_btn = _round_brew_button("ВАРИТЬ")
	_engine._brew_btn.custom_minimum_size = Vector2(140, 52)  # увеличен hitbox
	_engine._brew_btn.mouse_filter = Control.MOUSE_FILTER_STOP  # явный приём кликов
	_engine._brew_btn.pressed.connect(_on_brew_btn_pressed)
	row.add_child(_engine._brew_btn)
	_engine._repeat_btn = _small_button("↻", Vector2(44, 42), 1)
	_engine._repeat_btn.tooltip_text = "Повторить последнюю пару"
	_engine._repeat_btn.pressed.connect(_engine._repeat_last)
	row.add_child(_engine._repeat_btn)
	_engine._reset_btn = _small_button("✕", Vector2(44, 42))
	_engine._reset_btn.tooltip_text = "Сбросить ингредиенты из лунок"
	_engine._reset_btn.pressed.connect(_engine._reset_slots)
	row.add_child(_engine._reset_btn)

	_engine._progress = ProgressBar.new()
	_engine._progress.custom_minimum_size = Vector2(0, 12)
	_engine._progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_engine._progress.show_percentage = false
	_engine._progress.max_value = 100
	_engine._progress.value = 0
	_engine._progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.16, 0.20, 0.25, 0.9)
	psb.set_corner_radius_all(6)
	var pfg := StyleBoxFlat.new()
	pfg.bg_color = Color(0.30, 0.85, 0.90, 0.95)
	pfg.set_corner_radius_all(6)
	_engine._progress.add_theme_stylebox_override("background", psb)
	_engine._progress.add_theme_stylebox_override("fill", pfg)
	col.add_child(_engine._progress)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	col.add_child(srow)
	_engine._status_label = _label("", 13)
	_engine._status_label.custom_minimum_size.y = 28
	_engine._status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_engine._status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_engine._status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_engine._status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_engine._status_label)
	_engine._auto_stop_btn = _small_button("Стоп", Vector2(76, 40), 1)
	_engine._auto_stop_btn.tooltip_text = "Остановить этап; промежуточные предметы и задание производства сохранятся"
	_engine._auto_stop_btn.visible = false
	_engine._auto_stop_btn.pressed.connect(_engine._stop_auto)
	srow.add_child(_engine._auto_stop_btn)

func _on_tab_changed(index: int) -> void:
	_update_brew_bar_visibility()
	_spirit._refresh_companion_visible()
	if index == 2:
		_refetch_world()
		_resonance._fetch_echoes()
	elif index == 4:
		_online._refresh_rating()
	elif index == 5:
		_pages._ensure_modes()
	# Единственная граница, где interstitial показывается: смена вкладки при
	# полностью закрытых модалах, достроенном UI и незанятой варке/верстаке.
	# Варка и церемонии открытия под запретом
	# (docs/android/PLUGIN_SETUP.md §4, пункт про interstitial), как и показ
	# поверх открытого окна; частотные guardrails — в Monetization.can_show_interstitial().
	# _ui_ready — собственный объяснимый гейт против первого синхронного tab_changed
	# во время построения вкладок: без него от показа спасал бы только побочный
	# Monetization._ads == null (Monetization._boot ещё не отработал).
	if not _ui_ready or _modal_open_for_ads():
		return
	Monetization.show_interstitial("navigation")

func _refetch_world() -> void:
	var now := Time.get_ticks_msec()
	# первый вызов (_world_last_fetch_ms == 0) всегда проходит
	if _online._world_last_fetch_ms != 0 and now - _online._world_last_fetch_ms < 3000:
		return
	_online._world_last_fetch_ms = now
	_online._world_loaded = false
	Net.world(1)
	Net.hall()
	Net.events()
	Net.challenge(_online._device_id)
	Net.rejected()

func _update_brew_bar_visibility() -> void:
	if _brew_bar == null:
		return
	var on_lab := _tabs_ref == null or _tabs_ref.current_tab == 1
	_brew_bar.visible = on_lab
	if _engine._repeat_btn != null:
		_engine._repeat_btn.disabled = _engine.brewing or _engine._last_pair.size() != 2

func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	return null

func _ui_texture(path: String) -> Texture2D:
	if not _ui_tex.has(path):
		_ui_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _ui_tex[path] as Texture2D

# 9-slice-стайлбокс из Kenney-текстуры (перекрашенной под палитру игры).
func _stylebox_9(path: String, m: Vector4, mod: Color = Color(1, 1, 1, 1)) -> StyleBox:
	var sb := StyleBoxTexture.new()
	var tex := _ui_texture(path)
	if tex == null:
		return null
	sb.texture = tex
	sb.texture_margin_left = m.x
	sb.texture_margin_top = m.y
	sb.texture_margin_right = m.z
	sb.texture_margin_bottom = m.w
	sb.modulate_color = mod
	return sb

func _panel_style(bg_col: Color, radius: int) -> StyleBox:
	var sb := _stylebox_9("res://assets/ui/panel.png",
		Vector4(16, 14, 16, 14), Color(1, 1, 1, bg_col.a))
	if sb == null:
		var fb := StyleBoxFlat.new()
		fb.bg_color = bg_col
		fb.set_corner_radius_all(radius)
		fb.content_margin_left = 10
		fb.content_margin_right = 10
		fb.content_margin_top = 8
		fb.content_margin_bottom = 8
		return fb
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _make_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_left", 2)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	return content

# ---------- лаборатория ----------

# ---------- R11: см. game/pages.gd (1271-1359) ----------


func _make_orb(item_id: String, size_px: int) -> ElementOrb:
	var orb := ElementOrb.new()
	orb.custom_minimum_size = Vector2(size_px, size_px)
	orb.setup(item_id, _item_colors.get(item_id, Color(0.5, 0.6, 0.7)), true, _online._item_glyph(item_id))
	return orb

func _make_avatar(seed: String, size_px: float) -> Avatar:
	var av := Avatar.new()
	av.setup(seed, size_px)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return av

func _make_slot(letter: String) -> SlotWell:
	var well := SlotWell.new()
	well.set_meta("slot_letter", letter)
	well.tapped_clear.connect(_engine._on_slot_cleared)
	return well

func _round_brew_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	# Большая кнопка остаётся только для главного действия, но больше не
	# занимает пол-экрана: touch-зона сохраняется через сам Control.
	b.custom_minimum_size = Vector2(140, 52)  # увеличен hitbox для надёжного клика
	b.pivot_offset = Vector2(70, 26)
	b.add_theme_font_size_override("font_size", 16)
	if _font_semi != null:
		b.add_theme_font_override("font", _font_semi)
	var brew_margins := Vector4(14, 10, 14, 10)
	var sb := _stylebox_9("res://assets/ui/btn_primary.png", brew_margins)
	var sb_h := _stylebox_9("res://assets/ui/btn_primary.png", brew_margins, Color(1.18, 1.18, 1.16, 1))
	var sb_p := _stylebox_9("res://assets/ui/btn_primary.png", brew_margins, Color(0.72, 0.82, 0.8, 1))
	var sb_dis := _stylebox_9("res://assets/ui/btn_secondary.png", brew_margins, Color(1, 1, 1, 0.72))
	if sb == null:  # фоллбэк на плоский стиль
		sb = StyleBoxFlat.new()
		(sb as StyleBoxFlat).bg_color = Color(0.10, 0.35, 0.38, 0.95)
		(sb as StyleBoxFlat).border_color = Color(0.35, 0.95, 0.9, 0.85)
		(sb as StyleBoxFlat).set_border_width_all(3)
		(sb as StyleBoxFlat).set_corner_radius_all(18)
		sb_h = (sb as StyleBoxFlat).duplicate()
		(sb_h as StyleBoxFlat).bg_color = Color(0.14, 0.45, 0.47, 1)
		sb_p = (sb as StyleBoxFlat).duplicate()
		(sb_p as StyleBoxFlat).bg_color = Color(0.05, 0.15, 0.17, 0.9)
		sb_dis = (sb as StyleBoxFlat).duplicate()
		(sb_dis as StyleBoxFlat).bg_color = Color(0.09, 0.12, 0.15, 0.8)
		(sb_dis as StyleBoxFlat).border_color = Color(0.3, 0.4, 0.45, 0.3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("disabled", sb_dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.95, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.62))
	return b

# kind: 0 — вторичная (тёмно-синяя), 1 — основная (бирюзовая), 2 — золотая
func _small_button(text: String, min_size: Vector2, kind: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	# Один helper больше не превращает любую служебную кнопку в 46–54 px.
	# Многострочные подтверждения сохраняют высоту, остальные получают
	# компактную, но не микроскопическую Android-friendly высоту.
	var requested_h := min_size.y
	var compact_h := 38.0 if requested_h <= 0.0 else clampf(requested_h, 38.0, 42.0)
	if text.contains("\n"):
		compact_h = maxf(requested_h, 46.0)
	b.custom_minimum_size = Vector2(min_size.x, compact_h)
	b.add_theme_font_size_override("font_size", 14)
	if _font_semi != null:
		b.add_theme_font_override("font", _font_semi)
	var tex := "res://assets/ui/btn_secondary.png"
	if kind == 1:
		tex = "res://assets/ui/btn_primary.png"
	elif kind == 2:
		tex = "res://assets/ui/btn_gold.png"
	var small_margins := Vector4(10, 7, 10, 7)
	var sb := _stylebox_9(tex, small_margins)
	var sb_h := _stylebox_9(tex, small_margins, Color(1.2, 1.22, 1.18, 1))
	if sb == null:  # фоллбэк
		sb = StyleBoxFlat.new()
		(sb as StyleBoxFlat).bg_color = Color(0.13, 0.17, 0.23, 0.9)
		(sb as StyleBoxFlat).set_corner_radius_all(8)
		sb_h = (sb as StyleBoxFlat).duplicate()
		(sb_h as StyleBoxFlat).bg_color = Color(0.2, 0.26, 0.33, 1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := Color(0.88, 0.94, 0.96)
	if kind == 2:
		fg = Color(0.16, 0.12, 0.03)   # тёмный текст на золоте
	elif kind == 1:
		fg = Color(0.95, 1.0, 1.0)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	return b

## Квадратная кнопка для иконок (таро, квесты и т.д.). Фиксированный размер 46x46.
func _square_button(text: String, kind: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(46, 46)
	b.add_theme_font_size_override("font_size", 18)
	if _font_semi != null:
		b.add_theme_font_override("font", _font_semi)
	var tex := "res://assets/ui/btn_secondary.png"
	if kind == 1:
		tex = "res://assets/ui/btn_primary.png"
	elif kind == 2:
		tex = "res://assets/ui/btn_gold.png"
	var margins := Vector4(10, 7, 10, 7)
	var sb := _stylebox_9(tex, margins)
	var sb_h := _stylebox_9(tex, margins, Color(1.2, 1.22, 1.18, 1))
	if sb == null:
		sb = StyleBoxFlat.new()
		(sb as StyleBoxFlat).bg_color = Color(0.13, 0.17, 0.23, 0.9)
		(sb as StyleBoxFlat).set_corner_radius_all(8)
		sb_h = (sb as StyleBoxFlat).duplicate()
		(sb_h as StyleBoxFlat).bg_color = Color(0.2, 0.26, 0.33, 1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := Color(0.88, 0.94, 0.96)
	if kind == 2:
		fg = Color(0.16, 0.12, 0.03)
	elif kind == 1:
		fg = Color(0.95, 1.0, 1.0)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	return b

## Кнопка Аркана Сигилов: та же квадратная основа, но вместо глифа — рисованная
## иконка-таро. Button не Container, поэтому якорь ставится до офсетов.
func _tarot_button() -> Button:
	var b := _square_button("", 1)
	var icon := TarotIcon.new()
	icon.name = "Tarot"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8.0
	icon.offset_top = 6.0
	icon.offset_right = -8.0
	icon.offset_bottom = -6.0
	return b

func _label(text: String, font_size: int = 16) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

# ---------- книга ----------

# ---------- R11: см. game/pages.gd (1460-1541) ----------

# ---------- поп-ап открытия ----------

func _build_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "PopupDim"
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 20
	dim.visible = false
	dim.add_to_group("modal_ui")
	add_child(dim)
	_popup_dim = dim
	var center := CenterContainer.new()
	center.name = "PopupCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.z_index = 21
	center.visible = false
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		_panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(280, 0)
	card.add_child(col)

	_popup_title = _label("НОВЫЙ РЕЦЕПТ!", 24)
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_bold != null:
		_popup_title.add_theme_font_override("font", _font_bold)
	_popup_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(_popup_title)

	_popup_orb = ElementOrb.new()
	_popup_orb.interactive = false
	_popup_orb.custom_minimum_size = Vector2(130, 130)
	_popup_orb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_popup_orb)

	_popup_sub = _label("", 16)
	_popup_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_popup_sub)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	var ok := _small_button("Забрать", Vector2(132, 44), 2)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_hide_popup)
	actions.add_child(ok)
	var close := _small_button("Закрыть", Vector2(104, 44), 0)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(_hide_popup)
	actions.add_child(close)
	card.gui_input.connect(_on_popup_card_input)
	_popup = center
	# Модальное окно блокирует спавн и активацию QTE (док §8).
	center.add_to_group("modal_ui")

func _show_challenge_win_popup(item_id: String, target_name: String, a: String, b: String, first: bool = false) -> void:
	_popup_title.text = "ЕЖЕДНЕВНАЯ ЦЕЛЬ!"
	_popup_orb.setup(item_id, _item_colors.get(item_id, Color(0.7, 0.8, 0.9)), true, _online._item_glyph(item_id))
	var head := "Ты первым в мире получил вещество из «%s»!" if first else "Цель дня выполнена: вещество из «%s»!"
	_popup_sub.text = head + "\n%s + %s → %s\n+%d эфира" % [
		target_name, _online._item_name(a), _online._item_name(b), _online._item_name(item_id), CHALLENGE_REWARD]
	_popup_dim.visible = true
	_popup.visible = true
	_popup.scale = Vector2(0.7, 0.7)
	var tw := create_tween()
	tw.tween_property(_popup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	Sfx.legendary()

func _show_discovery_popup(item_id: String, a: String, b: String, milestones: Array = []) -> void:
	var author := String(_online._server_authors.get(item_id, ""))
	var r := _engine._rarity_of(item_id)
	var sub := "%s + %s → %s" % [_online._item_name(a), _online._item_name(b), _online._item_name(item_id)]
	if author != "":
		sub += "\nавтор: %s" % author
	var dsc := _online._item_desc(item_id)
	if dsc != "":
		sub += "\n«%s»" % dsc
	sub += "\n%s · награда +%d ⚡" % [r["name"], r["bounty"]]
	for m in milestones:
		sub += "\n%s" % _engine._milestone_text(int(m))
	_present_popup(item_id, sub, "НОВЫЙ РЕЦЕПТ!", r["color"])
	# Аркан Сигилов: для редких+ предметов генерируем карточку
	if int(r.get("tier", 0)) >= 2 and _sigil != null:
		var sigil_rarity := _tier_to_sigil_rarity(int(r.get("tier", 0)))
		var ingredients := PackedStringArray([a, b])
		_sigil.show_card_popup(item_id, ingredients, sigil_rarity, &"object", _online._item_name(item_id))

func _tier_to_sigil_rarity(tier: int) -> StringName:
	match tier:
		0, 1: return &"common"
		2: return &"rare"
		3: return &"epic"
		4: return &"legendary"
		_: return &"common"

func _present_popup(item_id: String, subtext: String, title: String = "", title_color: Color = Color(1.0, 0.9, 0.4)) -> void:
	if title != "":
		_popup_title.text = title
	_popup_title.add_theme_color_override("font_color", title_color)
	_popup_orb.setup(item_id, _item_colors.get(item_id, Color(0.7, 0.8, 0.9)), true, _online._item_glyph(item_id))
	_popup_sub.text = subtext
	_popup_dim.visible = true
	_popup.visible = true
	_popup.scale = Vector2(0.7, 0.7)
	var tw := create_tween()
	tw.tween_property(_popup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	Sfx.brew_discover()

func _hide_popup() -> void:
	_popup_dim.visible = false
	_popup.visible = false
	Sfx.click()

func _show_sigil_card(tex: ImageTexture, item_id: String, display_name: String, rarity: String) -> void:
	var accent := _rarity_color(rarity)
	var is_special := rarity in ["legendary", "mythic", "chromatic"]

	# ── Затемнение ──
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 62
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── Декоративный слой ──
	var decor := SigilCardRevealDecor.new()
	decor.rarity_color = accent
	decor.z_index = 63
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decor)
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.start(is_special, Vector2(320.0, 427.0))

	# ── Центр экрана ──
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.z_index = 64
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── Панель карточки ──
	var card_panel := PanelContainer.new()
	card_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.05, 0.05, 0.08, 0.98), 12))
	center.add_child(card_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	card_panel.add_child(vbox)

	var title_lbl := _label(display_name, 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(title_lbl)

	var img_rect := TextureRect.new()
	img_rect.texture = tex
	img_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_rect.custom_minimum_size = Vector2(320, 427)
	img_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(img_rect)

	var rar_lbl := _label(rarity.to_upper(), 14)
	rar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rar_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(rar_lbl)

	var close_btn := _small_button("Забрать", Vector2(140, 44), 2)
	vbox.add_child(close_btn)

	if is_special:
		var chrome_shader := load("res://game/sigil/shaders/sigil_chrome.gdshader")
		if chrome_shader != null:
			var chrome := ColorRect.new()
			chrome.color = Color(1, 1, 1, 0.15)
			chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chrome.material = ShaderMaterial.new()
			chrome.material.shader = chrome_shader
			center.add_child(chrome)
			chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var pulse_tw := create_tween().set_loops()
			pulse_tw.tween_property(chrome, "modulate:a", 0.30, 1.5)
			pulse_tw.tween_property(chrome, "modulate:a", 0.10, 1.5)

	# ── Стартовое состояние ДО раскладки: размер 1.0, но невидимо ──
	# Никаких pivot_offset/scale до layout: size center сейчас 0x0, и любая
	# установка пивота отправит карточку в правый нижний угол.
	center.modulate.a = 0.0

	# Запускаем анимации на следующем кадре — когда layout уже разложил size.
	# Без этого pivot_offset = viewport*0.5 попадает в точку вне карточки.
	_start_sigil_card_reveal.call_deferred(center, dim, decor, is_special)

	# Закрытие — сразу, твины внутри закроются по meta.
	var close_fn := func():
		var idle: Tween = center.get_meta("idle_tw", null)
		if idle != null and idle.is_valid():
			idle.kill()
		var tw_close := create_tween().set_parallel()
		tw_close.tween_property(center, "scale", Vector2(0.40, 0.40), 0.24)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw_close.tween_property(center, "rotation", deg_to_rad(4.0), 0.24)
		tw_close.tween_property(center, "modulate:a", 0.0, 0.20)
		tw_close.tween_property(dim, "color:a", 0.0, 0.28)
		tw_close.tween_property(decor, "modulate:a", 0.0, 0.25)
		tw_close.tween_callback(func():
			dim.queue_free()
			center.queue_free()
			decor.queue_free())
		Sfx.click()

	close_btn.pressed.connect(close_fn)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and not ev.pressed:
			close_fn.call()
	)

	if is_special:
		Sfx.legendary()
	else:
		Sfx.discovery()


## Запуск reveal-анимаций на кадре после раскладки. К этому моменту center
## уже имеет настоящий size (растянут на весь экран), и pivot = его центр
## совпадает с центром карточки. Без этой отсрочки scale-in идёт из точки
## правее-ниже карточки — «выезжает из правого нижнего угла».
func _start_sigil_card_reveal(center: Control, dim: ColorRect,
		decor: Control, is_special: bool) -> void:
	if not is_instance_valid(center):
		return
	# Пивот — от РЕАЛЬНОГО размера center, а не от размера вьюпорта.
	var pivot := center.size * 0.5
	center.pivot_offset = pivot
	center.scale = Vector2(0.28, 0.28)
	center.rotation = deg_to_rad(-6.0)

	var tw_bg := create_tween()
	tw_bg.tween_property(dim, "color:a", 0.78, 0.35)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var tw_card := create_tween().set_parallel()
	tw_card.tween_property(center, "scale", Vector2.ONE, 0.60)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_card.tween_property(center, "rotation", 0.0, 0.65)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw_card.tween_property(center, "modulate:a", 1.0, 0.22)

	# Idle-дыхание после приземления. Храним в meta, чтобы close_fn его убил.
	var tw_idle := create_tween().set_loops()
	tw_idle.tween_interval(0.9)
	tw_idle.tween_property(center, "scale", Vector2(1.015, 1.015), 1.7)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_idle.tween_property(center, "scale", Vector2.ONE, 1.7)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	center.set_meta("idle_tw", tw_idle)

	# Фон анимации декора (oreол/искры) уже стартовал в start(); здесь только
	# лёгкий fade-in при появлении.
	decor.modulate.a = 0.0
	var tw_decor := create_tween()
	tw_decor.tween_property(decor, "modulate:a", 1.0, 0.30)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.3, 0.8, 0.4)
		"rare": return Color(0.3, 0.6, 1.0)
		"epic": return Color(0.7, 0.3, 1.0)
		"legendary": return Color(1.0, 0.8, 0.2)
		"chromatic": return Color(1.0, 0.55, 0.12)
		"mythic": return Color(1.0, 0.2, 0.3)
		_: return Color(0.7, 0.7, 0.7)

## Демо-харнес (--action=sigilcoll): меню крафтов дня на локальных данных,
## без сервера. Превью кругов — настоящий рендер SigilRenderService.
func _demo_seed_sigil_coll() -> void:
	var day := Time.get_date_string_from_system()
	# Демо-каталог: земля доведена до восьми карт, как в брифе Task 7 (к 
	# clay/metal/mountain добавлены stone/sand/brick/glass/gold: 3–4 ингредиента,
	# qty 8–60, ether по редкости, stage — строка по спарке process/stage).
	# Сервера в харнесе нет, каталог задаётся прямо здесь — иначе card_recipe_for
	# ушёл бы в посоленный fallback и скриншот врал бы про боевой рендер.
	_sigil.set_catalog([
		{"id": "clay", "set": "earth", "rarity": "common", "ether_cost": 50,
			"recipe": [{"item_id": "clay", "qty": 12}, {"item_id": "water", "qty": 20},
				{"item_id": "sand", "qty": 8}],
			"process": "осадок и прессовка", "stage": "nigredo", "fallback_name": "Глина",
			"object_type": "object", "seed": 90210},
		{"id": "metal", "set": "earth", "rarity": "epic", "ether_cost": 400,
			"recipe": [{"item_id": "metal", "qty": 30}, {"item_id": "fire", "qty": 45},
				{"item_id": "ice", "qty": 25}, {"item_id": "spark", "qty": 18}],
			"process": "плавка и закалка", "stage": "albedo", "fallback_name": "Металл",
			"object_type": "relic", "seed": 90211},
		{"id": "mountain", "set": "earth", "rarity": "legendary", "ether_cost": 800,
			"recipe": [{"item_id": "mountain", "qty": 60}, {"item_id": "cloud", "qty": 80},
				{"item_id": "life", "qty": 40}],
			"process": "горный венец", "stage": "rubedo", "fallback_name": "Гора",
			"object_type": "planet", "seed": 90212},
		{"id": "stone", "set": "earth", "rarity": "common", "ether_cost": 50,
			"recipe": [{"item_id": "stone", "qty": 20}, {"item_id": "water", "qty": 25},
				{"item_id": "fire", "qty": 15}],
			"process": "calcinatio", "stage": "nigredo", "fallback_name": "Камень",
			"object_type": "object", "seed": 90213},
		{"id": "sand", "set": "earth", "rarity": "common", "ether_cost": 50,
			"recipe": [{"item_id": "sand", "qty": 15}, {"item_id": "water", "qty": 30},
				{"item_id": "air", "qty": 12}],
			"process": "distillatio", "stage": "albedo", "fallback_name": "Песок",
			"object_type": "object", "seed": 90214},
		{"id": "brick", "set": "earth", "rarity": "rare", "ether_cost": 150,
			"recipe": [{"item_id": "clay", "qty": 25}, {"item_id": "fire", "qty": 35},
				{"item_id": "water", "qty": 20}],
			"process": "sublimatio", "stage": "nigredo", "fallback_name": "Кирпич",
			"object_type": "object", "seed": 90215},
		{"id": "glass", "set": "earth", "rarity": "rare", "ether_cost": 150,
			"recipe": [{"item_id": "sand", "qty": 30}, {"item_id": "fire", "qty": 40},
				{"item_id": "air", "qty": 25}, {"item_id": "water", "qty": 15}],
			"process": "distillatio", "stage": "albedo", "fallback_name": "Стекло",
			"object_type": "object", "seed": 90216},
		{"id": "gold", "set": "earth", "rarity": "epic", "ether_cost": 400,
			"recipe": [{"item_id": "gold", "qty": 22}, {"item_id": "fire", "qty": 50},
				{"item_id": "water", "qty": 30}, {"item_id": "stone", "qty": 18}],
			"process": "coniunctio", "stage": "rubedo", "fallback_name": "Золото",
			"object_type": "relic", "seed": 90217},
	], _demo_sigil_sets(), "demo")
	_sigil._daily_day = day
	_sigil._daily_crafts = [
		{"id": day + "_demo_0", "rarity": "common", "ether_cost": 50, "llm_name": "",
			"is_chromatic": false, "card_id": "clay", "ingredients": [
				{"item_id": "clay", "qty": 12}, {"item_id": "water", "qty": 20},
				{"item_id": "sand", "qty": 8}]},
		{"id": day + "_demo_1", "rarity": "epic", "ether_cost": 400, "llm_name": "",
			"is_chromatic": false, "card_id": "metal", "ingredients": [
				{"item_id": "metal", "qty": 30}, {"item_id": "fire", "qty": 45},
				{"item_id": "ice", "qty": 25}, {"item_id": "spark", "qty": 18}]},
		{"id": day + "_demo_2", "rarity": "legendary", "ether_cost": 800,
			"llm_name": "Сигил «Горний Зов»", "is_chromatic": false, "card_id": "mountain", "ingredients": [
				{"item_id": "mountain", "qty": 60}, {"item_id": "cloud", "qty": 80},
				{"item_id": "life", "qty": 40}]},
	]
	# Первая карточка доступна, вторая — не хватает металла, третья — далеко
	_engine.ether = 950
	for pair in [["clay", 30], ["water", 25], ["sand", 40], ["metal", 10], ["fire", 50],
			["ice", 30], ["spark", 20], ["mountain", 5], ["cloud", 12], ["life", 0]]:
		_engine.inventory[str(pair[0])] = int(pair[1])
	_engine._refresh()
	# Демо-коллекция — как в sb6/sb7: через _on_collection_result (только память,
	# без записи на диск), чтобы сетка, хроматика и комплекты имели содержимое.
	# Сид Task 7: 7 собранных earth + milestone {earth: [3]} → прогресс 7/25,
	# точка 3 claimed, 6 claimable, 13/25 тусклые.
	_sigil._on_collection_result({"ok": true, "cards": {"clay": {"copies": 2,
		"first_at": "2026-09-28T10:00:00"},
		"metal": {"copies": 1, "first_at": "2026-09-30T18:30:00"},
		"mountain": {"copies": 1, "first_at": "2026-10-01T09:15:00"},
		"stone": {"copies": 1, "first_at": "2026-10-01T10:00:00"},
		"sand": {"copies": 1, "first_at": "2026-10-01T11:00:00"},
		"brick": {"copies": 1, "first_at": "2026-10-01T12:00:00"},
		"glass": {"copies": 1, "first_at": "2026-10-01T13:00:00"}},
		"extras": [{"craft_id": "demo_chroma", "rarity": "chromatic",
			"llm_name": "Хроматический сигил", "crafted_at": "2026-10-01T09:00:00"}],
		"milestones": {"earth": [3]}})
	# Демо проверки фуллскрина: открыть карточку clay (common) сразу,
	# чтобы --shot/--gif показали живую карточку (анимации, лор на обороте).
	if _demo_harness._shot_path != "" or _demo_harness._gif_dir != "":
		var demo_entry := _sigil_catalog_entry("clay", {"copies": 2, "first_at": "2026-09-28T10:00:00"})
		_open_sigil_fullscreen(demo_entry)
	_open_sigil_modal()
	# --sigiltab=collection|fullscreen|sets|set_grid: один show_tab на ветку,
	# чтобы вкладку не ребилдить дважды (set_grid поверх «sets» открывает
	# экран комплекта — Task 7b).
	match _demo_harness._sigil_tab:
		"collection", "fullscreen":
			_sigil_show_tab("collection")
			if _demo_harness._sigil_tab == "fullscreen":
				# Task 5C: для lore-скриншота открываем stone (валидный
				# process/stage/seed), иначе первую собранную карту.
				var target := "stone" if _sigil._server_collection.has("stone") else ""
				if target == "":
					for k in _sigil._server_collection:
						target = str(k)
						break
				if target != "":
					_open_sigil_fullscreen(_sigil_catalog_entry(target,
						_sigil._server_collection[target]))

		"sets":
			_sigil_show_tab("sets")
		"set_grid":
			_sigil_show_tab("sets")
			_open_sigil_set_screen("earth")
		_:
			pass


## Наборы демо-каталога: четыре стихии по 25 карт — свои предметы категории
## первыми, добивка остальными предметами каталога (CATEGORY_OF) до 25.
func _demo_sigil_sets() -> Array:
	var all_ids: Array = []
	for k in CATEGORY_OF:
		all_ids.append(String(k))
	var out: Array = []
	for def in [["fire", "огонь", "Стихия Огня"], ["water", "вода", "Стихия Воды"],
			["air", "воздух", "Стихия Воздуха"], ["earth", "земля", "Стихия Земли"]]:
		var ids: Array = []
		for k in all_ids:
			if str(CATEGORY_OF[k]) == String(def[1]):
				ids.append(k)
		for k in all_ids:
			if ids.size() >= SIGIL_SET_SIZE:
				break
			if not ids.has(k):
				ids.append(k)
		out.append({"id": String(def[0]), "title": String(def[2]), "card_ids": ids})
	return out

## Модалка Аркана Сигилов: три вкладки — крафты дня, коллекция, комплекты.
## Превью — настоящий рендер круга (SigilRenderService), а не декоративная
## рисовка: игрок видит ровно ту картину, которая будет на карточке.
func _open_sigil_modal(start_tab: String = "crafts") -> void:
	if _sigil_coll != null or _sigil == null:
		return
	Sfx.click()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 20
	_sigil_coll = dim
	add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_sigil_collection()
	)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(margin)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.065, 0.10, 0.99), 18))
	margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	var title := _label("АРКАН СИГИЛОВ", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.56))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := _small_button("✕", Vector2(46, 40))
	close_btn.tooltip_text = "Закрыть"
	close_btn.pressed.connect(_close_sigil_collection)
	head.add_child(close_btn)

	var tabbar := HBoxContainer.new()
	tabbar.name = "SigilTabBar"
	tabbar.add_theme_constant_override("separation", 8)
	vbox.add_child(tabbar)
	_sigil_tab_btns = []
	for tab_def in [["crafts", "КРАФТЫ ДНЯ"], ["collection", "КОЛЛЕКЦИЯ"], ["sets", "КОМПЛЕКТЫ"]]:
		var tb := _small_button(str(tab_def[1]), Vector2(0, 38))
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.set_meta("tab", str(tab_def[0]))
		tb.set_meta("sb_idle", tb.get_theme_stylebox("normal"))
		var sb_act: StyleBox = _stylebox_9("res://assets/ui/btn_gold.png", Vector4(10, 7, 10, 7))
		if sb_act == null:
			var fb := StyleBoxFlat.new()
			fb.bg_color = Color(0.85, 0.72, 0.35, 1.0)
			fb.set_corner_radius_all(8)
			sb_act = fb
		tb.set_meta("sb_active", sb_act)
		tb.pressed.connect(_sigil_show_tab.bind(str(tab_def[0])))
		tabbar.add_child(tb)
		_sigil_tab_btns.append(tb)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)
	_sigil_tab_content = content
	_sigil_show_tab(start_tab)


## Показать вкладку модалки: старое содержимое сносится целиком, билдер
## строит заново. Поколение _sigil_tab_seq гасит корутины билдеров, чтобы
## предыдущая вкладка не достраивалась поверх новой после своего await.
func _sigil_show_tab(tab: String) -> void:
	if _sigil_coll == null or _sigil_tab_content == null:
		return
	if tab != "crafts" and tab != "collection" and tab != "sets":
		tab = "crafts"
	_sigil_tab = tab
	_sigil_tab_seq += 1
	for c in _sigil_tab_content.get_children():
		(c as Node).queue_free()
	for b in _sigil_tab_btns:
		if b is Button and is_instance_valid(b):
			var btn := b as Button
			var active := str(btn.get_meta("tab", "")) == tab
			var sb: StyleBox = btn.get_meta("sb_active") if active else btn.get_meta("sb_idle")
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
			btn.add_theme_stylebox_override("disabled", sb)
			var fg := Color(0.16, 0.12, 0.03) if active else Color(0.88, 0.94, 0.96)
			btn.add_theme_color_override("font_color", fg)
			btn.add_theme_color_override("font_hover_color", fg)
	match tab:
		"collection":
			_sigil_build_collection_tab(_sigil_tab_content)
		"sets":
			_sigil_build_sets_tab(_sigil_tab_content)
		_:
			_sigil_build_crafts_tab(_sigil_tab_content)


## Вкладка «Крафты дня»: бывшее тело _open_sigil_modal — загрузка и строки.
func _sigil_build_crafts_tab(container: Control) -> void:
	var seq := _sigil_tab_seq
	var dim := _sigil_coll
	var status := _label("Загружаю крафты…", 15)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	container.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_sigil.request_catalog()
	await _await_catalog(10.0)
	_sigil.request_collection(_online._device_id)
	_sigil.request_daily(_online._device_id)
	var loaded := await _await_daily_crafts(10.0)
	if seq != _sigil_tab_seq or _sigil_coll != dim or not is_instance_valid(container):
		return
	var crafts: Array = _sigil._daily_crafts
	if not loaded or crafts.is_empty():
		status.text = "Сервер не ответил.\nКрафты появятся, когда вернётся связь."
		status.add_theme_color_override("font_color", Color(0.78, 0.58, 0.46))
		var retry := _small_button("Повторить", Vector2(180, 46), 2)
		retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		retry.pressed.connect(func():
			_close_sigil_collection()
			_open_sigil_modal.call_deferred()
		)
		container.add_child(retry)
		return
	status.queue_free()
	scroll.visible = true
	var rows: Array = []
	for craft in crafts:
		var row := _sigil_craft_row(craft)
		list.add_child(row)
		rows.append(row)
	# Список показываем сразу, картинки дорисовываем по одной: рендер круга
	# требует кадров, а ждать все три до первого пикселя — значит держать
	# игрока на пустом экране.
	for i in rows.size():
		_sigil_render_busy = true
		var tex := await _sigil.preview_texture(crafts[i])
		_sigil_render_busy = false
		if seq != _sigil_tab_seq or _sigil_coll != dim or tex == null:
			continue
		_sigil_fill_preview((rows[i] as Control).get_meta("preview"), tex)


## Вкладка «Коллекция»: сетка 4 колонки собранных карт, ниже — отдельная
## секция хроматики. Порядок ячеек — по каталогу: сеты в порядке catalog_sets,
## внутри сета — порядок card_ids; карты без сета — в конце.
func _sigil_build_collection_tab(container: Control) -> void:
	var seq := _sigil_tab_seq
	var dim := _sigil_coll
	var coll: Dictionary = _sigil._server_collection
	var extras: Array = _sigil.server_extras()
	if coll.is_empty() and extras.is_empty():
		var empty := _label("Пока пусто — крафты дня ждут", 16)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
		container.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var grid := GridContainer.new()
	grid.name = "SigilCollGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)

	var ordered: Array = []
	var seen := {}
	for s in _sigil.catalog_sets():
		for cid in (s as Dictionary).get("card_ids", []):
			var cs := str(cid)
			if seen.has(cs):
				continue
			seen[cs] = true
			if coll.has(cs) and not _sigil.card(cs).is_empty():
				ordered.append(cs)
	for cid in coll:
		var cs := str(cid)
		if not seen.has(cs) and not _sigil.card(cs).is_empty():
			ordered.append(cs)
	var pending: Array = []
	for cs in ordered:
		var cell := _sigil_collection_cell(_sigil_catalog_entry(cs, coll[cs]))
		grid.add_child(cell)
		pending.append([cell, {"card_id": cs}])

	if not extras.is_empty():
		var section := VBoxContainer.new()
		section.name = "SigilChromaSection"
		section.add_theme_constant_override("separation", 8)
		list.add_child(section)
		var st := _label("ХРОМАТИКА", 14)
		st.autowrap_mode = TextServer.AUTOWRAP_OFF
		st.add_theme_color_override("font_color", Color(1.0, 0.55, 0.12))
		section.add_child(st)
		var cgrid := GridContainer.new()
		cgrid.columns = 4
		cgrid.add_theme_constant_override("h_separation", 10)
		cgrid.add_theme_constant_override("v_separation", 10)
		section.add_child(cgrid)
		for x in extras:
			var xe := x as Dictionary
			var entry := {
				"card_id": "", "craft_id": str(xe.get("craft_id", "")),
				"rarity": str(xe.get("rarity", "chromatic")),
				"name": str(xe.get("llm_name", "")), "set": "",
				"set_title": "Вне комплектов",
				"first_at": str(xe.get("crafted_at", "")), "copies": 1,
				"seed": int(xe.get("seed", 0)),
				"lore": str(xe.get("lore", "")),
				# Ингредиенты хроматика (сервер хранит их при крафте) — тот же
				# SigilLore.generate, что у комплектных карт, работает от recipe.
				"recipe": xe.get("ingredients", []),
			}
			var ccell := _sigil_collection_cell(entry)
			cgrid.add_child(ccell)
			# Экстрас (хроматик): уникальная картинка по seed. Ключ дискового кэша
			# зависит от _cache_extra — ставим его по seed, чтобы разные хроматики
			# не коллизировали в один PNG (глобальный _cache_extra это ломал).
			var xseed := int(xe.get("seed", 0))
			if xseed != 0:
				_sigil._cache_extra = "chromatic|object|%d" % xseed
			var cimg := _sigil._load_cached_image(str(xe.get("craft_id", "")))
			if cimg == null:
				cimg = await _sigil.generate_card(
					str(xe.get("craft_id", "")), PackedStringArray(),
					&"chromatic", &"object", str(xe.get("llm_name", "")))
				if cimg != null:
					_sigil._save_cached_image(str(xe.get("craft_id", "")), cimg)
					_sigil._cache_extra = ""
			if cimg != null:
				_sigil_fill_preview(ccell.get_meta("preview"),
					ImageTexture.create_from_image(cimg))

	# Мини-арты дорисовываем по одному, как в списке крафтов: клетки и бейджи
	# видны сразу, картинки приходят кадром позже.
	for p in pending:
		_sigil_render_busy = true
		var tex := await _sigil.preview_texture(p[1])
		_sigil_render_busy = false
		if seq != _sigil_tab_seq or _sigil_coll != dim or tex == null:
			continue
		_sigil_fill_preview((p[0] as Control).get_meta("preview"), tex)


## Вкладка «Комплекты»: панель на каждый комплект каталога — титул из
## каталога, прогресс «N/25», ProgressBar и ряд точек-майлстоунов 3/6/13/25.
## Экран комплекта с сеткой карт и силуэтами — Task 7b.
func _sigil_build_sets_tab(container: Control) -> void:
	var sets := _sigil.catalog_sets()
	if sets.is_empty():
		var empty := _label("Комплекты появятся после загрузки каталога", 16)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
		container.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for s in sets:
		list.add_child(_sigil_set_panel(s as Dictionary))


## Панель комплекта: титул стихии, прогресс «N/25», ProgressBar и ряд из четырёх
## точек-майлстоунов. Титул и порядок — из catalog_sets(); собранные карты —
## пересечение _server_collection с card_ids сета (has_collected).
func _sigil_set_panel(set_def: Dictionary) -> Control:
	var set_id := str(set_def.get("id", ""))
	var accent := _sigil_set_accent(set_id)
	var panel := PanelContainer.new()
	# Имя уникально по сету: find_children ищет по wildcard, add_child
	# переименовывает одинаковые имена соседей.
	panel.name = "SigilSetPanel_" + set_id
	panel.set_meta("set_id", set_id)
	panel.add_theme_stylebox_override("panel", _sigil_row_style(accent, 0.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := _label(str(set_def.get("title", "")), 17)
	title.name = "SigilSetTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)

	var collected := 0
	var ids = set_def.get("card_ids", [])
	if ids is Array:
		for cid in (ids as Array):
			if _sigil.has_collected(str(cid)):
				collected += 1
	var count := _label("%d/%d" % [collected, SIGIL_SET_SIZE], 14)
	count.name = "SigilSetCount"
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_color_override("font_color", Color(0.72, 0.74, 0.80))
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)

	var bar := ProgressBar.new()
	bar.name = "SigilSetProgress"
	bar.max_value = float(SIGIL_SET_SIZE)
	bar.value = float(clampi(collected, 0, SIGIL_SET_SIZE))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.045, 0.07, 1.0)
	bar_bg.set_corner_radius_all(5)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(accent.r, accent.g, accent.b, 0.3)
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(accent.r, accent.g, accent.b, 0.85)
	bar_fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(bar)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 10)
	box.add_child(dots)
	var claimed := _sigil.claimed_tiers(set_id)
	for tier in [3, 6, 13, 25]:
		dots.add_child(_sigil_milestone_dot(set_id, tier, collected, claimed))
	# Тап по панели (вне точек-майлстоунов) открывает экран комплекта — точки
	# живут по своим координатам, чтобы клейм не спотыкался о навигацию.
	var dot_boxes: Array = []
	for c in dots.get_children():
		dot_boxes.append(c as Control)
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			var pos := (ev as InputEventMouseButton).global_position
			for db in dot_boxes:
				if db.get_global_rect().has_point(pos):
					return
			_open_sigil_set_screen(set_id)
	)
	return panel


## Экран комплекта (Task 7b): фуллскрин-слой над модалкой (z=30) с сеткой 25
## карт сета. Собранные карты каталога — мини-арт из превью-кэша и тап на
## фуллскрин карты; несобранные и неизвестные каталогу — СИЛУЭТ: тёмный
## контур круга + «???», без имени и без арта (спека: без спойлера).
## ✕ закрывает слой — вкладка «Комплекты» под ним остаётся как есть.
func _open_sigil_set_screen(set_id: String) -> void:
	if _sigil_set_screen != null or _sigil == null or _sigil_coll == null:
		return
	var set_def: Dictionary = {}
	for s in _sigil.catalog_sets():
		if str((s as Dictionary).get("id", "")) == set_id:
			set_def = s as Dictionary
			break
	if set_def.is_empty():
		return
	Sfx.click()
	var root := Control.new()
	root.name = "SigilSetScreen"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 30
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil_set_screen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_sigil_set_screen()
	)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.055, 0.065, 0.10, 0.99), 18))
	margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var accent := _sigil_set_accent(set_id)
	var collected := 0
	var ids: Array = set_def.get("card_ids", [])
	for cid in ids:
		if _sigil.has_collected(str(cid)):
			collected += 1

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	var title := _label("%s · %d/%d" % [str(set_def.get("title", "")),
		collected, SIGIL_SET_SIZE], 20)
	title.name = "SigilSetScreenTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var close_btn := _small_button("✕", Vector2(46, 40))
	close_btn.name = "SigilSetClose"
	close_btn.tooltip_text = "Закрыть"
	close_btn.pressed.connect(_close_sigil_set_screen)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "SigilSetGrid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var pending: Array = []
	for cid in ids:
		var cs := str(cid)
		var coll_entry: Dictionary = {}
		if _sigil._server_collection.has(cs):
			coll_entry = _sigil._server_collection[cs]
		var cell := _sigil_set_cell(cs, coll_entry)
		grid.add_child(cell)
		if not _sigil.card(cs).is_empty() and _sigil.has_collected(cs):
			pending.append([cell, {"card_id": cs}])
	# Мини-арты — из превью-кэша по одному, как в коллекции: сетка с силуэтами
	# видна сразу, картинки приходят кадром позже (рендер — только на промах).
	var scr := root
	for p in pending:
		_sigil_render_busy = true
		var tex := await _sigil.preview_texture(p[1])
		_sigil_render_busy = false
		if _sigil_set_screen != scr or not is_instance_valid(p[0]):
			continue
		if tex != null:
			_sigil_fill_preview((p[0] as Control).get_meta("preview"), tex)


## Закрыть экран комплекта: слой уходит, вкладка «Комплекты» под ним остаётся
## как есть (без перестройки — спека Task 7b: «возврат к вкладке»).
func _close_sigil_set_screen() -> void:
	if _sigil_set_screen == null:
		return
	var s := _sigil_set_screen
	_sigil_set_screen = null
	s.queue_free()
	Sfx.click()


## Ячейка сетки комплекта: собранная карта каталога — кнопка с мини-артом и
## тапом на фуллскрин карты; несобранная или неизвестная каталогу — силуэт:
## тёмный контур круга + «???», без имени и без арта (спека: без спойлера).
func _sigil_set_cell(card_id: String, coll_entry: Dictionary) -> Control:
	var card := _sigil.card(card_id)
	if not card.is_empty() and _sigil.has_collected(card_id):
		var entry := _sigil_catalog_entry(card_id, coll_entry)
		var accent := _rarity_color(str(entry.get("rarity", "common")))
		var btn := Button.new()
		btn.name = "SigilSetCell_" + card_id
		btn.custom_minimum_size = Vector2(0, 110)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_contents = true
		btn.add_theme_stylebox_override("normal", _sigil_row_style(accent, 0.0))
		btn.add_theme_stylebox_override("hover", _sigil_row_style(accent, 0.05))
		btn.add_theme_stylebox_override("pressed", _sigil_row_style(accent, 0.09))
		btn.add_theme_stylebox_override("disabled", _sigil_row_style(accent, 0.0))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_open_sigil_fullscreen.bind(entry))
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(holder)
		# Button не контейнер: якоря — до ручных офсетов.
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.offset_left = 6
		holder.offset_top = 6
		holder.offset_right = -6
		holder.offset_bottom = -6
		var shot := _sigil_preview_slot(accent, 0)
		shot.custom_minimum_size = Vector2(0, 0)
		holder.add_child(shot)
		shot.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.set_meta("preview", shot)
		btn.set_meta("card_id", card_id)
		return btn
	var box := PanelContainer.new()
	box.name = "SigilSetCell_" + card_id
	box.custom_minimum_size = Vector2(0, 110)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.07, 1.0)
	sb.border_color = Color(0.42, 0.45, 0.52, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	var ring := SigilSilhouette.new()
	ring.name = "SigilSilhouetteRing"
	ring.custom_minimum_size = Vector2(64, 64)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ring)
	var q := _label("???", 16)
	q.autowrap_mode = TextServer.AUTOWRAP_OFF
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_color_override("font_color", Color(0.45, 0.49, 0.58))
	vb.add_child(q)
	box.set_meta("card_id", card_id)
	return box


## Точка-майлстоун комплекта: claimed — приглушённая с отметкой; claimable
## (N >= порог и не claimed) — золотая, тап шлёт клейм; locked — тусклая.
func _sigil_milestone_dot(set_id: String, tier: int, collected: int,
		claimed: Array) -> Button:
	var is_claimed := claimed.has(tier)
	var is_claimable := not is_claimed and collected >= tier
	var state := "claimed" if is_claimed else ("claimable" if is_claimable else "locked")
	var dot := Button.new()
	dot.name = "SigilDot" + str(tier)
	dot.custom_minimum_size = Vector2(34, 34)
	dot.focus_mode = Control.FOCUS_NONE
	dot.set_meta("tier", tier)
	dot.set_meta("set_id", set_id)
	dot.set_meta("state", state)
	dot.disabled = not is_claimable
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.065, 0.10, 1.0)
	if is_claimable:
		sb.border_color = Color(0.90, 0.82, 0.56, 0.95)
		sb.set_border_width_all(2)
	else:
		sb.border_color = Color(0.42, 0.45, 0.52, 0.55 if is_claimed else 0.3)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(17)
	dot.add_theme_stylebox_override("normal", sb)
	dot.add_theme_stylebox_override("hover", sb)
	dot.add_theme_stylebox_override("pressed", sb)
	dot.add_theme_stylebox_override("disabled", sb)
	dot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var num := Label.new()
	num.text = str(tier)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_size_override("font_size", 12)
	num.autowrap_mode = TextServer.AUTOWRAP_OFF
	var fg := Color(0.90, 0.85, 0.62) if is_claimable else Color(0.55, 0.58, 0.66)
	num.add_theme_color_override("font_color", fg)
	dot.add_child(num)
	# Button не контейнер: якорь до ручных офсетов.
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	if is_claimable:
		dot.pressed.connect(_sigil_claim_milestone.bind(set_id, tier))
	if is_claimed:
		# Глиф «✓» вне шрифта Manrope: отметка рисуется, а не печатается.
		var mark := SigilMilestoneMark.new()
		mark.name = "SigilDotMark"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_child(mark)
		mark.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		mark.offset_left = -16.0
		mark.offset_top = 2.0
		mark.offset_right = -2.0
		mark.offset_bottom = 14.0
	return dot


## Тап по claimable-точке: клейм уходит на сервер, офлайн — в очередь Net.
func _sigil_claim_milestone(set_id: String, tier: int) -> void:
	Sfx.click()
	_sigil.request_milestone_claim(_online._device_id, set_id, tier)


## Тексты наград майлстоунов — дословно из брифа Task 7 (минус — U+2212).
func _sigil_milestone_reward_text(tier: int) -> String:
	match tier:
		3: return "+40 к капу эфира"
		6: return "−10% эфира крафтов комплекта"
		13: return "Верстак ×2 для стихии"
		25: return "Четвёртый слот дневного крафта"
		_: return ""


## Акцент стихии для панелей комплектов.
func _sigil_set_accent(set_id: String) -> Color:
	match set_id:
		"fire": return Color(0.98, 0.55, 0.32)
		"water": return Color(0.33, 0.68, 1.0)
		"air": return Color(0.55, 0.85, 0.92)
		"earth": return Color(0.82, 0.66, 0.42)
		_: return Color(0.62, 0.66, 0.72)


## Main-обработчик клейма майлстоуна (вторая подписка на sigil_milestone_result):
## ok && claimed — попап награды и refresh коллекции, чтобы флаги перерисовались.
## Офлайн-форма и ошибки ничего не делают — эффекты строго по серверу.
func _on_sigil_milestone_result(result: Dictionary) -> void:
	if not result.get("ok", false) or not result.get("claimed", false):
		return
	var tier := int(result.get("tier", 0))
	Sfx.achievement()
	_sigil_claim_popup(tier)
	_sigil.request_collection(_online._device_id)


## Попап «Награда получена»: слой поверх модалки (z=20) и фуллскрина (z=30),
## закрытие по OK или тапу по фону. Неизвестный тир награды попап не строит.
func _sigil_claim_popup(tier: int) -> void:
	var reward := _sigil_milestone_reward_text(tier)
	if reward == "" or _sigil_claim_layer != null:
		return
	Sfx.click()
	var root := Control.new()
	root.name = "SigilSetScreen"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 30
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil_claim_layer = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_sigil_claim_popup()
	)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.05, 0.08, 0.98), 12))
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := _label("Награда получена", 20)
	title.name = "SigilClaimTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.56))
	vbox.add_child(title)

	var body := _label(reward, 15)
	body.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	vbox.add_child(body)

	var ok_btn := _small_button("OK", Vector2(120, 40))
	ok_btn.name = "SigilClaimOk"
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_btn.pressed.connect(_close_sigil_claim_popup)
	vbox.add_child(ok_btn)


func _close_sigil_claim_popup() -> void:
	if _sigil_claim_layer == null:
		return
	var d := _sigil_claim_layer
	_sigil_claim_layer = null
	d.queue_free()
	Sfx.click()


## Ячейка коллекции: кнопка с плейсхолдером превью, бейдж «×N» в углу при
## копиях больше одной; тап открывает полноэкранный просмотр.
func _sigil_collection_cell(entry: Dictionary) -> Control:
	var rarity := str(entry.get("rarity", "common"))
	var accent := _rarity_color(rarity)
	var copies := int(entry.get("copies", 1))
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(0, 200)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.clip_contents = true
	cell.add_theme_stylebox_override("normal", _sigil_row_style(accent, 0.0))
	cell.add_theme_stylebox_override("hover", _sigil_row_style(accent, 0.05))
	cell.add_theme_stylebox_override("pressed", _sigil_row_style(accent, 0.09))
	cell.add_theme_stylebox_override("disabled", _sigil_row_style(accent, 0.0))
	cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cell.pressed.connect(_open_sigil_fullscreen.bind(entry))

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	# Button не контейнер: якоря — до ручных офсетов.
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.offset_left = 8
	holder.offset_top = 8
	holder.offset_right = -8
	holder.offset_bottom = -8

	var shot := _sigil_preview_slot(accent, 150)
	holder.add_child(shot)
	shot.set_anchors_preset(Control.PRESET_FULL_RECT)
	cell.set_meta("preview", shot)

	if copies > 1:
		var badge := _sigil_badge("×%d" % copies, accent)
		holder.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		var bs: Vector2 = badge.get_combined_minimum_size()
		badge.offset_left = -(bs.x + 4)
		badge.offset_top = 4
		badge.offset_right = -2
		badge.offset_bottom = 4 + bs.y
	return cell


## Entry полноэкранного просмотра карты каталога: имя/редкость/сет берутся
## из каталога, дата и копии — из серверной записи коллекции.
func _sigil_catalog_entry(card_id: String, coll_entry: Dictionary) -> Dictionary:
	var card := _sigil.card(card_id)
	if card.is_empty():
		return {}
	var set_title := ""
	for s in _sigil.catalog_sets():
		if str((s as Dictionary).get("id", "")) == str(card.get("set", "")):
			set_title = str((s as Dictionary).get("title", ""))
			break
	return {
		"card_id": card_id,
		"craft_id": "",
		"rarity": str(card.get("rarity", "common")),
		"name": str(card.get("fallback_name", "")),
		"set": str(card.get("set", "")),
		"set_title": set_title,
		"first_at": str(coll_entry.get("first_at", "")),
		"copies": int(coll_entry.get("copies", 1)),
		# Task 5C: поля для lore-генератора и будущего подпроекта D.
		"process": str(card.get("process", "")),
		"stage": str(card.get("stage", "")),
		"seed": int(card.get("seed", 0)),
		"recipe": card.get("recipe", []),
	}


## ISO-дата получения → «ДД.ММ.ГГГГ»: первые 10 символов до «T»,
## компоненты в обратном порядке.
func _sigil_date_ru(iso: String) -> String:
	var day := iso.substr(0, 10).split("T")[0]
	var p := day.split("-")
	if p.size() == 3:
		return "%s.%s.%s" % [p[2], p[1], p[0]]
	return day


## Полноэкранный просмотр карты коллекции — паттерн _show_sigil_card:
## затемнение + центральная панель. Закрытие: кнопка, тап по фону, свайп
## длиннее 80 px в любую сторону. Под артом — пустой якорь для lore-блока
## подпроекта C.
func _open_sigil_fullscreen(entry: Dictionary) -> void:
	if entry.is_empty() or _sigil_fullscreen != null or _sigil == null:
		return
	Sfx.click()
	var rarity := str(entry.get("rarity", "common"))
	var accent := _rarity_color(rarity)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 30
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil_fullscreen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.05, 0.08, 0.98), 12))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	# Отступы объектов внутри попапа от краёв панели.
	vbox.add_theme_constant_override("margin_left", 14)
	vbox.add_theme_constant_override("margin_right", 14)
	vbox.add_theme_constant_override("margin_top", 14)
	vbox.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(vbox)

	var title_lbl := _label(str(entry.get("name", "")), 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(title_lbl)

	# Живая карточка: SubViewportContainer + SigilCard (анимированная аура,
	# искры/фольга — как в sigil_module_v2). _svc.preview_into подключает
	# вьюпорт сервиса; UPDATE_ALWAYS заставляет его жить (иначе статика).
	# Переворачиваемая карточка: лицо = живой рендер, оборот = лор.
	var card_flip := Control.new()
	card_flip.name = "SigilCardFlip"
	card_flip.custom_minimum_size = Vector2(405, 540)
	card_flip.size = Vector2(405, 540)
	card_flip.mouse_filter = Control.MOUSE_FILTER_STOP
	card_flip.pivot_offset = Vector2(202, 270)
	card_flip.set_meta("flipped", false)
	card_flip.set_meta("busy", false)
	vbox.add_child(card_flip)

	# Лицо: живой рендер карточки (аура/фольга/искры по редкости).
	# Лицо: живой рендер карточки (аура/фольга/искры по редкости).
	var face := _sigil_live_card(entry)
	face.name = "SigilFace"
	# Каскад появления: слои собираются из центра по одному. deferred —
	# чтобы вьюпорт успел разложить размеры до первого тика твина.
	if _live_card_node != null and is_instance_valid(_live_card_node):
		_live_card_node.play_reveal.call_deferred()
	# SubViewportContainer нельзя растягивать preset-ом: он сам задаёт размер
	# вьюпорту. Фикс. размер 300x540, центрирование — через size_flags.
	face.size = Vector2(405, 540)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_flip.add_child(face)

	# Оборот: лор (скролл).
	var lore := ScrollContainer.new()
	lore.name = "SigilBack"
	lore.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lore.visible = false
	# Фон оборотной стороны, чтобы текст читался (не «прозрачная» карта).
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.07, 0.07, 0.11, 1.0)
	lsb.border_color = Color(accent.r, accent.g, accent.b, 0.5)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(12)
	lore.add_theme_stylebox_override("panel", lsb)
	card_flip.add_child(lore)
	var lore_v := VBoxContainer.new()
	lore_v.add_theme_constant_override("separation", 12)
	lore_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Отступы текста от краёв оборотной стороны.
	lore_v.add_theme_constant_override("margin_left", 12)
	lore_v.add_theme_constant_override("margin_right", 12)
	lore_v.add_theme_constant_override("margin_top", 12)
	lore_v.add_theme_constant_override("margin_bottom", 12)
	lore.add_child(lore_v)
	# Лор: тот же детерминированный генератор, что у комплектных карт
	# (SigilLore.generate от (id, seed)). Хроматики получают seed и ингредиенты
	# с сервера — SigilLore даёт такой же структурированный текст {title,
	# description, effect_hint, warning}, как у комплектов, а не плоский
	# LLM-абзац. Серверный lore больше не используется как source — только
	# как fallback при пустом seed.
	var srv_lore := str(entry.get("lore", ""))
	# Процесс/стадия у внекомплектных — детерминированные от seed, иначе
	# SigilLore (тот же генератор, что у комплектных) не найдёт совместимых
	# слотов и вернёт пустоту.
	var ps_pairs := [
		["calcinatio", "nigredo"], ["putrefactio", "nigredo"],
		["sublimatio", "albedo"], ["coniunctio", "albedo"],
		["coniunctio", "rubedo"], ["calcinatio", "rubedo"],
		["sublimatio", "citrinitas"], ["coniunctio", "citrinitas"],
	]
	var _entry_seed := int(entry.get("seed", 0))
	var _ps: Array = ps_pairs[abs(_entry_seed) % ps_pairs.size()]
	# id для лора: у каталожных карт — card_id (craft_id пуст), у хроматиков —
	# craft_id (card_id пуст). Пустой craft_id НЕ должен маскировать card_id.
	var _lore_id := str(entry.get("craft_id", ""))
	if _lore_id == "":
		_lore_id = str(entry.get("card_id", ""))
	var card_lore := SigilLore.generate({
		"id": _lore_id,
		"process": str(entry.get("process", _ps[0])),
		"stage": str(entry.get("stage", _ps[1])),
		"seed": _entry_seed,
		"recipe": entry.get("recipe", []),
	})
	if card_lore.is_empty() and rarity == "chromatic":
		if srv_lore != "":
			card_lore = {
				"title": str(entry.get("name", "Внекомплектный сигил")),
				"description": srv_lore,
				"effect_hint": "Не влияет на комплекты; коллекционная ценность.",
				"warning": "",
			}
		else:
			card_lore = {
				"title": "Внекомплектный сигил",
				"description": "Эта карта не входит ни в один комплект стихий. "
					+ "Её создали из случайного сочетания ингредиентов — "
					+ "призма редкости, светящаяся вне обычных графов трансмутации.",
				"effect_hint": "Не влияет на комплекты; коллекционная ценность.",
				"warning": "",
			}
	if not card_lore.is_empty():
		var lt := _label(str(card_lore.get("title", "")), 16)
		lt.name = "SigilLoreTitle"
		lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lt.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
		lore_v.add_child(lt)
		var ld := _label(str(card_lore.get("description", "")), 13)
		ld.name = "SigilLoreDesc"
		ld.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ld.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ld.add_theme_color_override("font_color", Color(0.70, 0.72, 0.78))
		lore_v.add_child(ld)
		var le := _label(str(card_lore.get("effect_hint", "")), 12)
		le.name = "SigilLoreEffect"
		le.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		le.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		le.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
		lore_v.add_child(le)
		var lw := _label(str(card_lore.get("warning", "")), 12)
		lw.name = "SigilLoreWarn"
		lw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lw.add_theme_color_override("font_color", Color(0.8, 0.45, 0.4))
		lore_v.add_child(lw)

	card_flip.gui_input.connect(_sigil_flip_card.bind(card_flip))
	# GIF-демо: авто-переворот через 2 с (после ритуала).
	if _demo_harness != null and _demo_harness._gif_dir != "":
		_demo_flip_timer = {"card": card_flip, "at": Time.get_ticks_msec() + 2000}

	# Ритуал-оверлей ОТКЛЮЧЁН: его круг перекрывал живую SigilCard
	# (pivot в 0,0 → свечение уезжало в правый нижний угол). Живая карточка
	# в SubViewport уже анимируется (аура/фольга/искры) — ритуал не нужен.

	var rar_lbl := _label(_sigil_rarity_title(rarity), 14)
	rar_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rar_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(rar_lbl)

	var set_lbl := _label("Комплект: %s" % str(entry.get("set_title", "")), 13)
	set_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_lbl.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
	vbox.add_child(set_lbl)

	var got_lbl := _label("Получена: %s" % _sigil_date_ru(str(entry.get("first_at", ""))), 13)
	got_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	got_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	got_lbl.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
	vbox.add_child(got_lbl)

	var copies_lbl := _label("копии: ×%d" % int(entry.get("copies", 1)), 13)
	copies_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	copies_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copies_lbl.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	vbox.add_child(copies_lbl)

	var close_btn := _small_button("Закрыть", Vector2(88, 36))
	close_btn.name = "SigilFsClose"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_close_sigil_fullscreen)
	vbox.add_child(close_btn)

	# Тап по фону и свайп в любую сторону закрывают; состояние перетаскивания
	# живёт в meta у center, чтобы оба обработчика видели одно и то же.
	center.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				center.set_meta("drag", ev.position)
			elif center.has_meta("drag"):
				var from: Vector2 = center.get_meta("drag")
				center.remove_meta("drag")
				if (ev.position - from).length() <= 80.0:
					_close_sigil_fullscreen()
		elif ev is InputEventMouseMotion and center.has_meta("drag"):
			var from: Vector2 = center.get_meta("drag")
			if (ev.position - from).length() > 80.0:
				center.remove_meta("drag")
				_close_sigil_fullscreen()
	)
	panel.gui_input.connect(func(ev):
		# Свайп, начавшийся на самой карте, тоже закрывает: панель перехватывает
		# press (STOP) и держит mouse focus, поэтому drag-meta кормим и отсюда —
		# тем же значением, что и фон. Релиз без драга снимает meta: тап по карте
		# не закрывает и не оставляет «висячего» жеста для hover-движений.
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				center.set_meta("drag", ev.position)
			elif center.has_meta("drag"):
				center.remove_meta("drag")
		elif ev is InputEventMouseMotion and center.has_meta("drag"):
			var from: Vector2 = center.get_meta("drag")
			if (ev.position - from).length() > 80.0:
				center.remove_meta("drag")
				_close_sigil_fullscreen()
	)



## Полный арт фуллскрина: для карты каталога — дисковый кэш по card_id, промах
## рендерится по карточному рецепту с полными опциями (как в get_card) и
## ложится в кэш; для extras — только дисковый кэш по craft_id, промах
## остаётся плейсхолдером. Рендер ждёт фоновые превью: у сервиса один
## SubViewport, параллельные рендеры портят картинки друг друга (хазард T5-M2).
func _sigil_fill_fullscreen_art(slot: Control, entry: Dictionary) -> void:
	var fs := _sigil_fullscreen
	var card_id := str(entry.get("card_id", ""))
	if card_id == "":
		var img0 := _sigil._load_cached_image(str(entry.get("craft_id", "")))
		if img0 != null and _sigil_fullscreen == fs:
			_sigil_fill_preview(slot, ImageTexture.create_from_image(img0))
		return
	var img := _sigil._load_cached_image(card_id)
	if img == null:
		var waited := 0.0
		while _sigil_render_busy and waited < 1.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		if _sigil_fullscreen != fs or not is_instance_valid(slot):
			return
		var recipe := _sigil.card_recipe_for({"card_id": card_id})
		img = await _sigil._svc.render(recipe, _sigil._options)
		if img != null and _sigil_fullscreen == fs:
			_sigil._save_cached_image(card_id, img)
	if img == null or _sigil_fullscreen != fs or not is_instance_valid(slot):
		return
	_sigil_fill_preview(slot, ImageTexture.create_from_image(img))


func _close_sigil_fullscreen() -> void:
	if _sigil_fullscreen == null:
		return
	var fs := _sigil_fullscreen
	_sigil_fullscreen = null
	_live_card_node = null
	fs.queue_free()
	Sfx.click()


## Ждать ежедневные крафты, но не вечно: офлайн не должен вешать меню.
## Settled-флаг гасит ожидание сразу после офлайн-ответа, не по полному таймауту.
func _await_daily_crafts(timeout: float) -> bool:
	var waited := 0.0
	while _sigil._daily_crafts.is_empty() and not _sigil.daily_settled() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return not _sigil._daily_crafts.is_empty()


## Ждать каталог карт: без него превью меню рисовало бы посоленный fallback
## вместо общей карты каталога. Тот же приём, что у _await_daily_crafts:
## settled-флаг выходит из ожидания сразу после офлайн-ответа.
func _await_catalog(timeout: float) -> bool:
	var waited := 0.0
	while _sigil.catalog_size() == 0 and not _sigil.catalog_settled() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return _sigil.catalog_size() > 0


## Строка крафта: слева круг, справа всё, что нужно для решения.
func _sigil_craft_row(craft: Dictionary) -> Control:
	var rarity := str(craft.get("rarity", "common"))
	var is_chromatic := bool(craft.get("is_chromatic", false))
	var ether_cost := _sigil.craft_ether_cost(craft)
	var rc := _rarity_color(rarity)
	var accent := Color(1.0, 0.55, 0.12) if is_chromatic else rc
	var shortages := _sigil_shortages(craft)
	var can_afford := shortages.is_empty() and _engine.ether >= ether_cost
	var n_ing := int((craft.get("ingredients", []) as Array).size())
	var title := _sigil_craft_title(craft)
	# Высота по содержимому: Button не контейнер и сам её не посчитает.
	var row_h := 107 + 21 * n_ing
	if not shortages.is_empty():
		row_h += 24
		if _sigil_shortage_text(shortages).length() > 48:
			row_h += 18
	if title.length() > 24:
		row_h += 24

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, maxi(176, row_h))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_contents = true
	btn.add_theme_stylebox_override("normal", _sigil_row_style(accent, 0.0, is_chromatic))
	btn.add_theme_stylebox_override("hover", _sigil_row_style(accent, 0.05, is_chromatic))
	btn.add_theme_stylebox_override("pressed", _sigil_row_style(accent, 0.09, is_chromatic))
	btn.add_theme_stylebox_override("disabled", _sigil_row_style(accent, 0.0, is_chromatic))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if can_afford:
		btn.pressed.connect(_open_sigil_craft.bind(craft))
	else:
		btn.disabled = true
		btn.modulate = Color(0.68, 0.68, 0.74, 0.92)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	# Button не контейнер: без якорей HBox остался бы нулевого размера.
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_top = 10
	row.offset_right = -14
	row.offset_bottom = -10

	var shot := _sigil_preview_slot(accent, 148)
	row.add_child(shot)
	btn.set_meta("preview", shot)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name_lbl := _label(title, 18)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(name_lbl)

	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 8)
	info.add_child(badge_row)
	badge_row.add_child(_sigil_badge(_sigil_rarity_title(rarity), rc))
	if is_chromatic and rarity != "chromatic":
		badge_row.add_child(_sigil_badge("ХРОМА", Color(1.0, 0.55, 0.12)))

	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		info.add_child(_sigil_need_row(str(d.get("item_id", "")), int(d.get("qty", 0))))

	var price := _label("%d эфира" % ether_cost, 15)
	price.autowrap_mode = TextServer.AUTOWRAP_OFF
	price.add_theme_color_override("font_color",
		Color(0.62, 0.85, 0.66) if _engine.ether >= ether_cost else Color(0.92, 0.48, 0.42))
	info.add_child(price)

	if not shortages.is_empty():
		var miss := _label(_sigil_shortage_text(shortages), 12)
		miss.add_theme_color_override("font_color", Color(0.92, 0.56, 0.46))
		miss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(miss)
	return btn


## Плейсхолдер превью: рамка в цвет редкости, картинка встанет сюда позже.
## Переворот карточки: лицо <-> оборот (лор) через scale.x-схлоп.
## Эмуляция тапа (для демо/GIF): один левый клик.
func _tap_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev



func _sigil_flip_card(ev: InputEvent, card_flip: Control) -> void:
	if not is_instance_valid(card_flip):
		return
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if card_flip.get_meta("busy", false):
		return
	card_flip.set_meta("busy", true)
	var flipped: bool = card_flip.get_meta("flipped", false)
	var face := card_flip.get_node_or_null("SigilFace")
	var back := card_flip.get_node_or_null("SigilBack")
	# Настоящий переворот: двухстадийный scale.x-схлоп (без ломки layout,
	# pivot по центру; старый твин убиваем, чтобы не конкурировали).
	var tw := create_tween()
	card_flip.pivot_offset = card_flip.size / 2.0
	tw.tween_property(card_flip, "scale:x", 0.0, 0.18) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if face != null:
			face.visible = flipped
		if back != null:
			back.visible = not flipped
		card_flip.set_meta("flipped", not flipped)
		Sfx.click())
	tw.tween_property(card_flip, "scale:x", 1.0, 0.18) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		card_flip.set_meta("busy", false))




## Живая карточка для фуллскрина: SubViewportContainer поверх вьюпорта
## SigilRenderService, UPDATE_ALWAYS — чтобы аура/фольга/искры жили.
## Редкость/seed берутся из entry, поэтому свечения совпадают с редкостью.
func _sigil_live_card(entry: Dictionary) -> Control:
	# Свой SubViewport, а не общий вьюпорт SigilRenderService: общий занят
	# статичными рендерами (UPDATE_DISABLED) и не может быть переподключён.
	var recipe := _sigil.card_recipe_for(entry)
	var rarity := str(entry.get("rarity", recipe.rarity))
	var prism_eff := ""
	# Хроматики — космос/призма поверх (Prism-эффекты card_beatify).
	if rarity == "chromatic":
		var effs := ["galaxy", "oil_slick", "textured_foil",
			"shattered_glass", "laser_refraction", "glitch"]
		prism_eff = effs[recipe.compute_seed() % effs.size()]
	var opts := SigilOptions.make({
		"card_size": Vector2i(405, 540),
		"show_name": true,
		"show_frame": true,
		"show_icon": true,
		"render_scale": 1,
		"prism_effect": prism_eff,
		"prism_phase": -1.0,
	})
	var box := SubViewportContainer.new()
	box.custom_minimum_size = Vector2(405, 540)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	box.stretch = true
	var vp := SubViewport.new()
	vp.name = "LiveCardViewport"
	vp.size = Vector2i(405, 540)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	# UPDATE_ALWAYS — чтобы аура/фольга/искры анимировались каждый кадр.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(vp)
	var card := SigilCard.new()
	card.name = "LiveCard"
	vp.add_child(card)
	card.setup(recipe, opts)
	card.set_live(true)
	# Живой режим: параллакс/дыхание иконки/каскад. Только для игровой
	# карточки в SubViewport, статичный рендер не трогаем.
	card.live_mode = true
	_live_card_node = card
	return box


## Превью круга БЕЗ рамки (для крафт-экрана): просто текстурный холст.
func _sigil_preview_slot(accent: Color, side: int, border: bool = true) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(side, side)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.07, 1.0) if border else Color(0, 0, 0, 0)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55) if border else Color(0, 0, 0, 0)
	sb.set_border_width_all(1) if border else sb.set_border_width_all(0)
	sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rect)
	box.set_meta("rect", rect)
	var ph := _label("…", 28)
	ph.name = "Ph"
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ph)
	return box


func _sigil_fill_preview(box: Control, tex: ImageTexture) -> void:
	if box == null or not is_instance_valid(box):
		return
	var rect: TextureRect = box.get_meta("rect")
	rect.texture = tex
	var ph := box.get_node_or_null("Ph")
	if ph != null:
		ph.visible = false


func _sigil_row_style(accent: Color, lift: float, is_chromatic: bool = false) -> StyleBox:
	var sb := StyleBoxFlat.new()
	if is_chromatic:
		# Хроматик выделяется: тёплый фон и золотая рамка потолще.
		sb.bg_color = Color(0.16 + lift, 0.11 + lift, 0.06 + lift, 1.0)
		sb.border_color = Color(1.0, 0.72, 0.25, 0.95)
		sb.set_border_width_all(2)
		sb.border_width_left = 5
		# Лёгкое свечение: внешний контур рамки (имитация ореола).
		sb.shadow_color = Color(1.0, 0.6, 0.15, 0.35)
		sb.shadow_size = 6
	else:
		sb.bg_color = Color(0.075 + accent.r * 0.10 + lift, 0.085 + accent.g * 0.10 + lift,
			0.12 + accent.b * 0.10 + lift, 1.0)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.45 + lift)
		sb.set_border_width_all(1)
		sb.border_width_left = 4
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _sigil_badge(text: String, col: Color) -> Control:
	var b := PanelContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = Color(col.r, col.g, col.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	b.add_theme_stylebox_override("panel", sb)
	var l := _label(text, 11)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_color", col)
	b.add_child(l)
	return b


## Строка ингредиента: сколько есть и сколько нужно.
func _sigil_need_row(elem_id: String, needed: int) -> Control:
	var have := int(_engine.inventory.get(elem_id, 0))
	var enough := have >= needed
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = _element_color(elem_id)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var nm := _label(_online._item_name(elem_id), 13)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	row.add_child(nm)
	var qty := _label("%d / %d" % [have, needed], 13)
	qty.autowrap_mode = TextServer.AUTOWRAP_OFF
	qty.add_theme_color_override("font_color",
		Color(0.55, 0.86, 0.58) if enough else Color(0.93, 0.50, 0.44))
	row.add_child(qty)
	return row


func _sigil_shortage_text(shortages: Array) -> String:
	return "Не хватает: " + ", ".join(shortages)


func _sigil_shortages(craft: Dictionary) -> Array:
	var out: Array = []
	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		var elem_id := str(d.get("item_id", ""))
		var needed := int(d.get("qty", 0))
		var have := int(_engine.inventory.get(elem_id, 0))
		if have < needed:
			out.append("%s (%d/%d)" % [_online._item_name(elem_id), have, needed])
	return out


## Название крафта: LLM-имя, если сервер его прислал, иначе нейтральное.
func _sigil_craft_title(craft: Dictionary) -> String:
	var llm_name := str(craft.get("llm_name", ""))
	if llm_name != "":
		return llm_name
	var fb := str(craft.get("fallback_name", ""))
	if fb != "":
		return fb
	return "Сигил «%s»" % _sigil_rarity_title(str(craft.get("rarity", "common"))).capitalize()


func _sigil_rarity_title(rarity: String) -> String:
	match rarity:
		"common": return "ОБЫЧНЫЙ"
		"uncommon": return "НЕОБЫЧНЫЙ"
		"rare": return "РЕДКИЙ"
		"epic": return "ЭПИЧЕСКИЙ"
		"legendary": return "ЛЕГЕНДАРНЫЙ"
		"chromatic": return "ХРОМАТИЧЕСКИЙ"
		"mythic": return "МИФИЧЕСКИЙ"
		_: return rarity.to_upper()

var _sigil_craft_screen: Control = null
var _sigil_craft_data: Dictionary = {}
var _sigil_placed: Dictionary = {}  ## element_id -> placed_count
## Списанные ресурсы до ответа сервера: нужны, чтобы вернуть их при отказе.
var _sigil_pending_craft: Dictionary = {}

func _open_sigil_craft(craft: Dictionary) -> void:
	# Экран крафта — весь в SigilCraftBoard (game/sigil/sigil_craft_board.gd):
	# вёрстка, ячейки-фантомы, drag&drop, кнопка. Здесь только подключение.
	if _sigil_craft_screen != null:
		_close_sigil_craft_screen()
	Sfx.click()
	_sigil_craft_data = craft
	_sigil_placed = {}
	var board := SigilCraftBoard.new()
	board.name = "SigilCraftBoard"
	_sigil_craft_screen = board
	add_child(board)
	board.show_craft(craft, self)
	board.confirmed.connect(_on_sigil_board_confirmed)
	board.closed.connect(_close_sigil_craft_screen)


## Board подтвердил: все элементы на круге — запускаем крафт (списание+сервер).
var _sigil_craft_ritual: SigilCraftRitual = null
var _pending_craft_result: Dictionary = {}

func _show_sigil_craft_ritual(rarity: String) -> void:
	print("RITUAL: show, rarity=", rarity)
	if _sigil_craft_ritual != null and is_instance_valid(_sigil_craft_ritual):
		_sigil_craft_ritual.queue_free()
		
	var strength := 0.7
	match rarity:
		"epic": strength = 0.85
		"legendary": strength = 1.0
		"mythic", "chromatic": strength = 1.2
		
	var r := SigilCraftRitual.new()
	r.accent = _rarity_color(rarity)
	r.strength = strength
	
	# КЛЮЧЕВОЕ: Подключаем сигнал показа карты и автозакрытие
	r.on_card_reveal.connect(_on_ritual_card_reveal)
	r.on_complete.connect(_close_sigil_craft_ritual)
	
	_sigil_craft_ritual = r
	add_child(r)
	
func _on_ritual_card_reveal(rect: Rect2, payload: Variant) -> void:
	print("RITUAL: card reveal signal received")
	if payload != null:
		var p := payload as Dictionary
		_show_pending_craft_card(p.get("craft_id", ""), p.get("rarity", "common"), p.get("llm_name", ""))
	elif not _pending_craft_result.is_empty():
		# Фоллбэк, если сервер не успел
		_show_pending_craft_card(_pending_craft_result.get("craft_id", ""), _pending_craft_result.get("rarity", "common"), _pending_craft_result.get("llm_name", ""))


func _close_sigil_craft_ritual() -> void:
	print("RITUAL: close (карточка пришла или таймаут)")
	if _sigil_craft_ritual != null and is_instance_valid(_sigil_craft_ritual):
		_sigil_craft_ritual.queue_free()
	_sigil_craft_ritual = null


func _on_sigil_board_confirmed(craft: Dictionary) -> void:
	# Атомарный крафт: ресурсы списываются сразу (спека: карточка уже у игрока)
	var ether_cost := _sigil.craft_ether_cost(craft)
	_engine.ether = max(0, _engine.ether - ether_cost)
	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		var elem_id := str(d.get("item_id", ""))
		var needed := int(d.get("qty", 0))
		var have := int(_engine.inventory.get(elem_id, 0))
		_engine.inventory[elem_id] = max(0, have - needed)
	_saves._save_game()
	Sfx.craft_start()
	var craft_id := str(craft.get("id", ""))
	_sigil_pending_craft = craft.duplicate(true)
	_sigil.craft_card(_online._device_id, craft_id)
	# Торжественный ритуал трансмутации (окно крафта закрывается, ритуал поверх).
	_close_sigil_craft_screen()
	_show_sigil_craft_ritual(str(craft.get("rarity", "common")))


## Сервер подтвердил крафт: показываем готовую карточку.
func _on_sigil_craft_completed(craft_id: String, rarity: String, llm_name: String) -> void:
	# Сохраняем результат
	_pending_craft_result = {"craft_id": craft_id, "rarity": rarity, "llm_name": llm_name}
	
	if _sigil_craft_ritual != null and is_instance_valid(_sigil_craft_ritual):
		# Отдаём данные ритуалу. 
		# Если он ещё не дошёл до фазы удержания (4.85с), он подождёт.
		# Если уже ждёт — немедленно начнёт вспышку и эмитнет on_card_reveal.
		_sigil_craft_ritual.deliver_result(_pending_craft_result)
	else:
		# Ритуала нет (или уже закрылся), показываем сразу
		_show_pending_craft_card(craft_id, rarity, llm_name)
		_pending_craft_result = {}


## Рендер и показ карточки (после ритуала или сразу, если ритуала нет).
func _show_pending_craft_card(craft_id: String, rarity: String, llm_name: String) -> void:
	var craft: Dictionary = {"id": craft_id, "rarity": rarity, "llm_name": llm_name,
		"ingredients": []}
	for c in _sigil._daily_crafts:
		if str((c as Dictionary).get("id", "")) == craft_id:
			craft = c
			break
	# Хроматик: показываем ТУ ЖЕ живую карточку, что и в коллекции
	# (с Prism-эффектом, анимированная) — не статичный PNG.
	if rarity == "chromatic":
		var entry := {
			"card_id": "", "craft_id": craft_id,
			"rarity": "chromatic",
			"name": llm_name if llm_name != "" else str(craft.get("fallback_name", "")),
			"set": "", "set_title": "Вне комплектов",
			"first_at": "", "copies": 1,
			# Seed и лор — из ответа крафта (сервер — источник правды), а не из
			# _daily_crafts: клиентский daily мог устареть (кэш/старый оффер),
			# тогда seed=0 -> все хроматики рендерились бы одной картинкой.
			"seed": _sigil._last_craft_seed if _sigil._last_craft_seed != 0 \
				else int(craft.get("seed", 0)),
			"lore": _sigil._last_craft_lore if _sigil._last_craft_lore != "" \
				else str(craft.get("lore", "")),
		}
		_open_sigil_fullscreen(entry)
		return
	var img := await _sigil.get_card(craft_id, SigilManager.craft_ingredients(craft),
		StringName(rarity), &"object", _sigil_craft_title(craft))
	if img == null:
		return
	_show_sigil_card(ImageTexture.create_from_image(img), craft_id,
		_sigil_craft_title(craft), rarity)


## Сервер отказал: возвращаем списанное, иначе ресурсы сгорают молча.
func _on_sigil_craft_failed(err: String) -> void:
	_close_sigil_craft_ritual()
	var craft := _sigil_pending_craft
	_sigil_pending_craft = {}
	if craft.is_empty():
		return
	# Возврат — по той же скидочной цене, что и списание (ruling T4-fix):
	# «−10% стоимости эфира крафтов этого комплекта» покрывает весь ether-учёт.
	_engine.ether += _sigil.craft_ether_cost(craft)
	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		var elem_id := str(d.get("item_id", ""))
		_engine.inventory[elem_id] = int(_engine.inventory.get(elem_id, 0)) + int(d.get("qty", 0))
	_saves._save_game()
	_engine._refresh()
	_engine.status_text = "Крафт не прошёл (%s) — ресурсы возвращены." % err
	Sfx.error()

func _close_sigil_craft_screen() -> void:
	if _sigil_craft_screen == null:
		return
	var d := _sigil_craft_screen
	_sigil_craft_screen = null
	_sigil_craft_data = {}
	_sigil_placed = {}
	d.queue_free()
	Sfx.click()

func _btn_style(col: Color) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _element_color(elem_id: String) -> Color:
	return _item_colors.get(elem_id, Color(0.62, 0.66, 0.72))

func _close_sigil_collection() -> void:
	if _sigil_coll == null:
		return
	var d := _sigil_coll
	_sigil_coll = null
	d.queue_free()
	_sigil_tab_content = null
	_sigil_tab_btns = []
	Sfx.click()

func _sigil_thumb(item: Dictionary) -> Control:
	var id := str(item["id"])
	var rar := str(item["rarity"])
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.custom_minimum_size = Vector2(100, 133)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 1)
	sb.border_color = _rarity_color(rar)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var rect := TextureRect.new()
	rect.texture = item["texture"]
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(rect)
	b.pressed.connect(func():
		_show_sigil_card(item["texture"], id, _online._item_name(id), rar)
	)
	cell.add_child(b)
	var name_lbl := _label(_online._item_name(id), 10)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", _rarity_color(rar))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	cell.add_child(name_lbl)
	return cell

var _popup_swipe_start := Vector2.ZERO

func _on_popup_card_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_popup_swipe_start = mb.position
			elif UiGestures.swipe_closes(mb.position - _popup_swipe_start):
				_hide_popup()
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_popup_swipe_start = st.position
		elif UiGestures.swipe_closes(st.position - _popup_swipe_start):
			_hide_popup()
	# touch-ветка — guarded-untested: headless-прогон не эмулирует ScreenTouch;
	# предикат общий и покрыт кейсом swipe-предиката.

func _on_brew_btn_pressed() -> void:
	_engine._brew()

func _unhandled_input(event: InputEvent) -> void:
	# ~ (тильда) — toggle админ-консоли
	if _handle_tilde(event):
		get_viewport().set_input_as_handled()
		return
	# Esc закрывает верхний попап
	if _handle_esc(event):
		get_viewport().set_input_as_handled()

func _handle_tilde(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var ke := event as InputEventKey
	if not ke.pressed or ke.keycode != KEY_QUOTELEFT:
		return false
	if _admin != null:
		_admin.toggle()
		Sfx.click()
	return true

# Предикат ESC и сам уход собраны в одну булеву функцию: «потреблять или нет»
# наблюдаемо из selftest (наблюдаемость самого set_input_as_handled в headless
# проверить нечем — это оставленный, осознанный зазор в одну строку).
func _handle_esc(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var ke := event as InputEventKey
	if not ke.pressed or ke.keycode != KEY_ESCAPE:
		return false
	return _close_top_modal()

# Порядок elif-веток = порядок наложения (z): сначала модальные окна поверх
# всего (autovark/consent, магазин декора z=100), затем попапы по убыванию z.
# Возвращает true, если что-то закрыто/потреблено — только тогда Esc считается
# обработанным; иначе событие уходит дальше (обычный выход из игры).
func _close_top_modal() -> bool:
	if _sigil_fullscreen != null:
		_close_sigil_fullscreen()
		return true
	if _sigil_set_screen != null:
		_close_sigil_set_screen()
		return true
	if _sigil_craft_screen != null:
		_close_sigil_craft_screen()
		return true
	if _sigil_coll != null:
		_close_sigil_collection()
		return true
	if _admin != null and _admin.is_visible():
		_admin.close()
		Sfx.click()
		return true
	if _engine._auto:
		_engine._auto_cancel = true
		_engine.status_text = "Автоварка: остановлю после текущего шага…"
		return true
	if _shop != null and _shop._consent_popup != null and _shop._consent_popup.visible:
		# Не даём обойти первый consent через Esc: один из двух режимов
		# должен быть выбран явно.
		return true
	elif _home != null and _home._decor_popup != null and _home._decor_popup.visible:
		# Магазин декора — modal surface с z=100 (home.gd), выше shop/hub/discovery.
		_home._close_decor_popup()
		return true
	elif _shop != null and _shop._popup != null and _shop._popup.visible:
		_shop.close()
		return true
	elif _popup.visible:
		_hide_popup()
		return true
	elif _confirm.visible:
		_hide_confirm()
		return true
	elif _saves._return_popup.visible:
		_saves._close_return_popup()
		return true
	elif _hub._settings_popup.visible:
		_hub._settings_dim.visible = false
		_hub._settings_popup.visible = false
		Sfx.click()
		return true
	elif _hub._craftable_popup.visible:
		_hub._craftable_dim.visible = false
		_hub._craftable_popup.visible = false
		Sfx.click()
		return true
	elif _retort._retort_popup.visible:
		_retort._retort_dim.visible = false
		_retort._retort_popup.visible = false
		Sfx.click()
		return true
	elif _hub._journal_popup.visible:
		_hub._journal_dim.visible = false
		_hub._journal_popup.visible = false
		Sfx.click()
		return true
	elif _hub._prestige_popup.visible:
		_hub._prestige_dim.visible = false
		_hub._prestige_popup.visible = false
		Sfx.click()
		return true
	elif _progress_ui._prog_popup.visible:
		_progress_ui._prog_dim.visible = false
		_progress_ui._prog_popup.visible = false
		Sfx.click()
		return true
	elif _hub._profile_popup.visible:
		_hub._profile_dim.visible = false
		_hub._profile_popup.visible = false
		Sfx.click()
		return true
	elif _hub._up_popup.visible:
		_hub._up_dim.visible = false
		_hub._up_popup.visible = false
		Sfx.click()
		return true
	elif _spirit._companion_dlg != null and _spirit._companion_dlg.visible:
		_spirit._companion_close_dialog()
		return true
	elif _home != null and _home._color_picker != null and _home._color_picker.visible:
		# Отмена палитры с откатом живого предпросмотра (кнопки Cancel у пикера нет).
		_home._cancel_color_picker()
		return true
	elif _home != null and _home._house_popup != null and _home._house_popup.visible:
		# Палитра и гостевой домик — самые нижние по z и одновременно видны
		# быть не могут, порядок этих двух веток не важен.
		_home._close_house_popup()
		return true
	return false

# Read-only перечисление ровно тех поверхностей, что закрывает
# _close_top_modal(): interstitial не должен появляться поверх открытого модала,
# во время автоварки (_engine._auto — верхняя ветка того же порядка), ручной
# варки (_engine.brewing: core.gd:14, true в :695, false в :711/:765) и
# ручного крафта на верстаке (_pages._bench_busy — core.gd трактует её занятой
# вместе с варкой: :407, :666, :1208, :1371). Церемония открытия идёт внутри
# _popup и покрыта модальной веткой ниже. Каждая поверхность защищена
# проверкой на
# null по образцу уже существующих строк предиката: tab_changed эмитится
# синхронно во время построения вкладок, когда часть попапов ещё null
# (сам показ при этом гейтится _ui_ready в _on_tab_changed).
# Предикат из tests/suite_journal_misc.gd переиспользовать нельзя (он тестовый),
# поэтому у продакшена свой, проверяемый из selftest напрямую.
func _modal_open_for_ads() -> bool:
	if _admin != null and _admin.is_visible():
		return true
	if _engine._auto:
		return true
	if _engine.brewing:
		return true
	if _pages != null and _pages._bench_busy:
		return true
	if _shop != null and _shop._consent_popup != null and _shop._consent_popup.visible:
		return true
	if _home != null and _home._decor_popup != null and _home._decor_popup.visible:
		return true
	if _shop != null and _shop._popup != null and _shop._popup.visible:
		return true
	if _popup != null and _popup.visible:
		return true
	if _confirm != null and _confirm.visible:
		return true
	if _saves._return_popup != null and _saves._return_popup.visible:
		return true
	if _hub._settings_popup != null and _hub._settings_popup.visible:
		return true
	if _hub._craftable_popup != null and _hub._craftable_popup.visible:
		return true
	if _retort._retort_popup != null and _retort._retort_popup.visible:
		return true
	if _hub._journal_popup != null and _hub._journal_popup.visible:
		return true
	if _hub._prestige_popup != null and _hub._prestige_popup.visible:
		return true
	if _progress_ui._prog_popup != null and _progress_ui._prog_popup.visible:
		return true
	if _hub._profile_popup != null and _hub._profile_popup.visible:
		return true
	if _hub._up_popup != null and _hub._up_popup.visible:
		return true
	if _spirit._companion_dlg != null and _spirit._companion_dlg.visible:
		return true
	if _home != null and _home._color_picker != null and _home._color_picker.visible:
		return true
	if _home != null and _home._house_popup != null and _home._house_popup.visible:
		return true
	return false

# ---------- подтверждение автоварки ----------

func _build_confirm() -> void:
	var dim := ColorRect.new()
	dim.name = "ConfirmDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	dim.add_to_group("modal_ui")
	add_child(dim)
	_confirm_dim = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	center.add_to_group("modal_ui")
	add_child(center)
	_confirm = center

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		_panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(300, 0)
	card.add_child(col)

	var t := _label("АВТОВАРКА", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9))
	col.add_child(t)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_confirm_orb = ElementOrb.new()
	_confirm_orb.interactive = false
	_confirm_orb.custom_minimum_size = Vector2(56, 56)
	row.add_child(_confirm_orb)
	_confirm_l1 = _label("", 18)
	_confirm_l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_confirm_l1)

	_confirm_l2 = _label("", 14)
	_confirm_l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_confirm_l2)
	_confirm_l3 = _label("", 13)
	_confirm_l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_l3.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	col.add_child(_confirm_l3)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)
	var ok := _small_button("Варить", Vector2(128, 46), 1)
	ok.pressed.connect(_engine._on_confirm_brew)
	btns.add_child(ok)
	var cancel := _small_button("Отмена", Vector2(120, 46))
	cancel.pressed.connect(_hide_confirm)
	btns.add_child(cancel)

func _hide_confirm() -> void:
	_confirm_dim.visible = false
	_confirm.visible = false
	_engine._pending_item = ""
	_engine._pending_plan = {}
	Sfx.click()


# ---------- R12: см. game/hub.gd (1569-2173) ----------


# ---------- R11: см. game/pages.gd (2366-2918) ----------


# ---------- R5: см. game/resonance.gd (3031-3211) ----------

# ---------- R6: см. game/retort.gd (3022-3399) ----------


# ---------- R13: см. game/core.gd (1556-1715) ----------


# ---------- R13: см. game/core.gd (1717-1742) ----------


# ---------- R4: см. game/progress.gd (4066-4077) ----------

# ---------- R13: см. game/core.gd (1746-1837) ----------


# ---------- R13: см. game/core.gd (1839-2013) ----------



# ---------- R7: см. game/home.gd (3477-4369) ----------



# ---------- R8: см. game/online.gd (3444-3574) ----------


func _pair_key(a: String, b: String) -> String:
	var pair := PackedStringArray([a, b])
	pair.sort()
	return "|".join(pair)

# ---------- сервер первооткрытий ----------

func _clean_str(v) -> String:
	if v == null:
		return ""
	return String(v)

# ---------- R8: см. game/online.gd (3588-4042) ----------

# ---------- R13: см. game/core.gd (2037-2212) ----------


# ---------- R13: см. game/core.gd (2214-2353) ----------


# ---------- гильдия (квесты+заказы+планировщик) — в game/guild.gd (R3) ----------

# ---------- R13: см. game/core.gd (2357-2535) ----------


# ---------- письма Светика + Атлас — в game/riddles.gd (оп B2) ----------

# ---------- дневной круг + недельный слой — в game/retention.gd (R2) ----------

# ---------- R8: см. game/online.gd (4547-4794) ----------


# ---------- R10: см. game/saves.gd (3922-4479) ----------


# ---------- R9: см. game/spirit.gd (4494-4930) ----------


# ================= selftest (тело — в tests/, оп B1) =================

func _run_selftest() -> void:
	await Selftest.run(self)


## Рисованная галочка для claimed-точек майлстоунов: глиф «✓» вне шрифта
## Manrope, поэтому отметка рисуется двумя линиями в _draw.
class SigilMilestoneMark:
	extends Control

	func _draw() -> void:
		var c := Color(0.90, 0.82, 0.56)
		var w := 2.0
		draw_line(Vector2(size.x * 0.16, size.y * 0.52),
			Vector2(size.x * 0.42, size.y * 0.78), c, w)
		draw_line(Vector2(size.x * 0.42, size.y * 0.78),
			Vector2(size.x * 0.86, size.y * 0.22), c, w)


## Силуэт несобранной карты комплекта (Task 7b): тёмный контур круга без
## заливки — игрок не получает ни имени, ни арта, ни намёка на сид карты.
class SigilSilhouette:
	extends Control

	func _draw() -> void:
		var c := Color(0.28, 0.32, 0.40)
		var w := 2.0
		var r := (minf(size.x, size.y) - 8.0) * 0.5
		if r <= 0.0:
			return
		draw_arc(size * 0.5, r, 0.0, TAU, 48, c, w, true)


## Декоративный слой появления карточки.
## Слои (снизу вверх): ореол → god-rays → shockwave-каскад → столб света →
## орбитальные мотивы → искры с трейлами → звёздный блик.
## Рисуется ПОД карточкой (z=31 < z=32 у center), поэтому лучи не пересекают арт.
## Ввод не перехватывает, сам себя queue_free не вызывает.
class SigilCardRevealDecor:
	extends Control

	# ── Настройки каскада ударных волн: (задержка, длительность, толщина) ──
	const SHOCKWAVES := [
		{"delay": 0.00, "dur": 1.10, "width": 6.0,  "scale": 1.90},
		{"delay": 0.11, "dur": 0.85, "width": 3.0,  "scale": 1.45},
		{"delay": 0.26, "dur": 0.70, "width": 1.6,  "scale": 1.15},
	]
	const TRAIL_LEN := 7

	var rarity_color: Color = Color(1.0, 0.8, 0.3)
	var _t := 0.0
	var _special := false
	var _rays: Array = []
	var _sparks: Array = []
	var _motes: Array = []
	var _rng := RandomNumberGenerator.new()
	var _shockwave_t := -1.0
	var _card_half := Vector2(150.0, 280.0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Аддитивное смешивание: пересечения лучей и искр дают вспышки,
		# а не грязные тёмные стыки.
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	## card_size — полный размер карточки в пикселях; лучи стартуют от её края.
	func start(is_special: bool, card_size: Vector2) -> void:
		_special = is_special
		_card_half = card_size * 0.5
		_rng.randomize()
		_shockwave_t = 0.0
		_t = 0.0
		_rays.clear()
		_sparks.clear()
		_motes.clear()
		set_process(true)

		# ── God-rays: часть «длинные-редкие», часть «короткие-частые» ──
		var ray_count := 10 if is_special else 6
		for i in ray_count:
			var long_ray := i % 3 == 0
			_rays.append({
				"ang": (float(i) / ray_count) * TAU + _rng.randf_range(-0.12, 0.12),
				"w": _rng.randf_range(0.035, 0.085) * (1.6 if long_ray else 1.0),
				"len": _rng.randf_range(0.55, 1.0) * (1.9 if long_ray else 1.0),
				"spin": _rng.randf_range(0.06, 0.22) * (-1.0 if i % 2 else 1.0),
				"phase": _rng.randf() * TAU,
				"flick": _rng.randf_range(1.3, 3.1),
			})

		# ── Искры ──
		var count := 45 if is_special else 22
		for _i in count:
			_sparks.append(_make_spark(_rng.randf_range(0.0, 0.25)))

		# ── Орбитальные мотыльки (медленно кружат вокруг карты) ──
		var mote_count := 12 if is_special else 6
		for _i in mote_count:
			_motes.append({
				"ang": _rng.randf() * TAU,
				"rad": _rng.randf_range(1.05, 1.75),
				"spd": _rng.randf_range(0.18, 0.55) * (-1.0 if _rng.randf() < 0.4 else 1.0),
				"bob": _rng.randf() * TAU,
				"size": _rng.randf_range(1.2, 2.6),
			})

	func _make_spark(delay: float) -> Dictionary:
		var ang := _rng.randf() * TAU
		var spd := _rng.randf_range(80.0, 420.0)
		return {
			"pos": Vector2.ZERO,
			"vel": Vector2.from_angle(ang) * spd,
			"life": -delay,
			"max_life": _rng.randf_range(0.9, 2.1),
			"size": _rng.randf_range(1.4, 3.2),
			"grav": _rng.randf_range(30.0, 110.0),
			"trail": PackedVector2Array(),
			"hot": _rng.randf() < 0.3,  # «белые» быстрые искры
		}

	func _process(delta: float) -> void:
		_t += delta

		if _shockwave_t >= 0.0:
			_shockwave_t += delta
			if _shockwave_t >= 1.5:
				_shockwave_t = -1.0

		for s in _sparks:
			s["life"] = float(s["life"]) + delta
			if float(s["life"]) < 0.0:
				continue
			var v: Vector2 = s["vel"]
			v.y += float(s["grav"]) * delta          # лёгкое падение
			v *= pow(0.22, delta)                     # воздушное торможение
			s["vel"] = v
			s["pos"] = Vector2(s["pos"]) + v * delta
			var tr: PackedVector2Array = s["trail"]
			tr.append(s["pos"])
			if tr.size() > TRAIL_LEN:
				tr.remove_at(0)
			s["trail"] = tr
			# Респаун для «особых» — непрерывный фонтан искр.
			if _special and float(s["life"]) >= float(s["max_life"]):
				var fresh := _make_spark(0.0)
				for k in fresh:
					s[k] = fresh[k]

		for m in _motes:
			m["ang"] = float(m["ang"]) + float(m["spd"]) * delta

		queue_redraw()

	## Расстояние от центра прямоугольника (half-размеров) до его края вдоль dir.
	## Для луча это точка «отрыва» от силуэта карточки.
	func _rect_edge_distance(dir: Vector2, half: Vector2) -> float:
		var dx := maxf(absf(dir.x), 0.0001)
		var dy := maxf(absf(dir.y), 0.0001)
		return minf(half.x / dx, half.y / dy)

	func _draw() -> void:
		var center := size * 0.5
		# Полу-диагональ карточки — радиус описанной окружности.
		var diag := _card_half.length()
		var pulse := 0.65 + 0.35 * sin(_t * 2.2)
		var fade_in := clampf(_t * 1.8, 0.0, 1.0)
		var burst := clampf(1.0 - _t / 0.45, 0.0, 1.0)   # яркость первых мгновений
		var rc := rarity_color

		# ── Мягкий пульсирующий ореол цвета редкости (за карточкой) ──
		for i in range(7, 0, -1):
			var f := float(i) / 7.0
			draw_circle(center, diag * 1.6 * f,
				Color(rc.r, rc.g, rc.b,
					0.038 * pulse * fade_in * (1.0 - f * 0.70) + 0.05 * burst * (1.0 - f)))

		# ── Вертикальный столб света (только для особых) ──
		if _special:
			var pw := _card_half.x * (0.85 + 0.1 * sin(_t * 1.7))
			for i in 4:
				var g := 1.0 - float(i) / 4.0
				var a_p := 0.028 * fade_in * g * pulse
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(-pw * g, -size.y),
					center + Vector2(pw * g, -size.y),
					center + Vector2(pw * g * 1.9, size.y),
					center + Vector2(-pw * g * 1.9, size.y),
				]), Color(rc.r, rc.g, rc.b, a_p))

		# ── God-rays: объёмные конусы от края карточки ──
		_draw_rays(center, diag, fade_in, pulse, burst)

		# ── Каскад shockwave-колец с «зубчатым» фронтом ──
		if _shockwave_t >= 0.0:
			for sw in SHOCKWAVES:
				var lt := _shockwave_t - float(sw["delay"])
				if lt < 0.0 or lt > float(sw["dur"]):
					continue
				var k := lt / float(sw["dur"])
				var r := lerpf(diag * 0.45, diag * float(sw["scale"]), ease(k, 0.30))
				var a_sw := pow(1.0 - k, 1.6) * 0.95
				_draw_wobble_ring(center, r, 96, 0.035 * (1.0 - k),
					Color(rc.r, rc.g, rc.b, a_sw * 0.8), float(sw["width"]) * (1.0 - k * 0.4))
				_draw_wobble_ring(center, r * 0.945, 72, 0.02,
					Color(1.0, 1.0, 1.0, a_sw * 0.40), float(sw["width"]) * 2.4 * (1.0 - k))

		# ── Орбитальные мотыльки ──
		for m in _motes:
			var a_m := float(m["ang"])
			var rr := diag * float(m["rad"]) * (0.95 + 0.06 * sin(_t * 1.4 + float(m["bob"])))
			var p := center + Vector2.from_angle(a_m) * Vector2(1.0, 0.62).length() * 0.0
			p = center + Vector2(cos(a_m) * rr * 0.62, sin(a_m) * rr)  # эллиптическая орбита
			var tw := 0.45 + 0.55 * sin(_t * 3.0 + float(m["bob"]) * 2.0)
			var sz := float(m["size"])
			draw_circle(p, sz * 2.8, Color(rc.r, rc.g, rc.b, 0.16 * tw * fade_in))
			draw_circle(p, sz, Color(1.0, 0.97, 0.90, 0.85 * tw * fade_in))

		# ── Искры с трейлами ──
		_draw_sparks(center, fade_in)

		# ── Звёздный блик-крест в момент появления ──
		if burst > 0.0:
			_draw_star_flare(center, diag, burst)

	# ──────────────────────────────────────────────────────────────────────

	func _draw_rays(center: Vector2, diag: float, fade_in: float, pulse: float, burst: float) -> void:
		var reach := maxf(size.x, size.y) * 0.85
		for ray in _rays:
			var a := float(ray["ang"]) + _t * float(ray["spin"])
			var hw := float(ray["w"])
			var flick := 0.55 + 0.45 * sin(_t * float(ray["flick"]) + float(ray["phase"]))
			var length := reach * float(ray["len"]) * (0.5 + 0.5 * fade_in) * (0.9 + 0.35 * burst)
			var d0 := Vector2.from_angle(a - hw)
			var d1 := Vector2.from_angle(a + hw)
			var e0 := _rect_edge_distance(d0, _card_half) * 0.98
			var e1 := _rect_edge_distance(d1, _card_half) * 0.98
			# Три сегмента с затуханием — имитация объёмного света.
			var segs := 3
			for i in segs:
				var t0 := float(i) / segs
				var t1 := float(i + 1) / segs
				var a_near := (1.0 - t0) * (1.0 - t0)
				var a_far := (1.0 - t1) * (1.0 - t1)
				var col := Color(rc_mix(0.35).r, rc_mix(0.35).g, rc_mix(0.35).b, 1.0)
				var alpha := 0.065 * flick * fade_in * (0.6 + 0.9 * burst)
				var w0 := 1.0 + t0 * 1.8   # конус расширяется
				var w1 := 1.0 + t1 * 1.8
				draw_colored_polygon(PackedVector2Array([
					center + d0 * (e0 + length * t0) + _perp(d0, hw * e0 * (w0 - 1.0)),
					center + d1 * (e1 + length * t0) - _perp(d1, hw * e1 * (w0 - 1.0)),
					center + d1 * (e1 + length * t1) - _perp(d1, hw * e1 * (w1 - 1.0)),
					center + d0 * (e0 + length * t1) + _perp(d0, hw * e0 * (w1 - 1.0)),
				]), Color(col.r, col.g, col.b, alpha * lerpf(a_near, a_far, 0.5)))

	func _perp(d: Vector2, amount: float) -> Vector2:
		return Vector2(-d.y, d.x) * amount

	func rc_mix(white: float) -> Color:
		return rarity_color.lerp(Color(1, 1, 1), white)

	## Кольцо с лёгкой синусоидальной деформацией радиуса — живее ровной дуги.
	func _draw_wobble_ring(center: Vector2, radius: float, segments: int,
			wobble: float, col: Color, width: float) -> void:
		var pts := PackedVector2Array()
		for i in segments + 1:
			var a := TAU * float(i) / segments
			var r := radius * (1.0 + wobble * sin(a * 6.0 + _t * 4.0))
			pts.append(center + Vector2.from_angle(a) * r)
		draw_polyline(pts, col, maxf(width, 0.5), true)

	func _draw_sparks(center: Vector2, fade_in: float) -> void:
		for s in _sparks:
			var life := float(s["life"])
			if life < 0.0:
				continue
			var lt := life / float(s["max_life"])
			if lt >= 1.0:
				continue
			var pos: Vector2 = s["pos"]
			var dir_s := pos.normalized() if pos.length() > 0.01 else Vector2.RIGHT
			var edge := _rect_edge_distance(dir_s, _card_half)
			var draw_pos := center + pos
			if pos.length() < edge:
				# Искра ещё «под» карточкой — сдвигаем на её край, чтобы
				# рождалась из-за силуэта, а не в центре.
				draw_pos = center + dir_s * edge
			var a_sp := pow(1.0 - lt, 1.5) * 0.55 * fade_in
			var core := Color(1.0, 0.96, 0.88) if bool(s["hot"]) else rc_mix(0.55)

			# Трейл: ломаная из истории позиций, сужающаяся к хвосту.
			var tr: PackedVector2Array = s["trail"]
			if tr.size() >= 2:
				for i in range(1, tr.size()):
					var seg_a := float(i) / tr.size()
					var p0 := _push_out(center, tr[i - 1], edge)
					var p1 := _push_out(center, tr[i], edge)
					draw_line(p0, p1,
						Color(core.r, core.g, core.b, a_sp * seg_a * 0.55),
						float(s["size"]) * seg_a * 0.9, true)

			draw_circle(draw_pos, float(s["size"]) * 3.4 * (1.0 - lt),
				Color(rarity_color.r, rarity_color.g, rarity_color.b, a_sp * 0.16))
			draw_circle(draw_pos, float(s["size"]) * (1.0 - lt * 0.4),
				Color(core.r, core.g, core.b, a_sp))

	func _push_out(center: Vector2, local: Vector2, edge: float) -> Vector2:
		if local.length() < edge and local.length() > 0.01:
			return center + local.normalized() * edge
		return center + local

	## Анаморфный блик: яркий крест + диагонали, схлопывающиеся за ~0.45 с.
	func _draw_star_flare(center: Vector2, diag: float, burst: float) -> void:
		var k := pow(burst, 0.7)
		var arms := [
			{"dir": Vector2.RIGHT, "len": 3.1, "w": 1.0},
			{"dir": Vector2.UP,    "len": 2.0, "w": 0.8},
			{"dir": Vector2(0.707, 0.707),  "len": 1.3, "w": 0.45},
			{"dir": Vector2(-0.707, 0.707), "len": 1.3, "w": 0.45},
		]
		for arm in arms:
			var d: Vector2 = arm["dir"]
			var l := diag * float(arm["len"]) * k
			var w := 14.0 * float(arm["w"]) * k
			var n := _perp(d, 1.0)
			for sgn in [1.0, -1.0]:
				draw_colored_polygon(PackedVector2Array([
					center + n * w, center - n * w, center + d * l * sgn,
				]), Color(1.0, 0.98, 0.92, 0.28 * k))
				draw_colored_polygon(PackedVector2Array([
					center + n * w * 2.2, center - n * w * 2.2, center + d * l * 0.7 * sgn,
				]), Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.18 * k))
		draw_circle(center, diag * 0.55 * k, Color(1.0, 1.0, 1.0, 0.35 * k))
		draw_circle(center, diag * 0.28 * k, Color(1.0, 1.0, 1.0, 0.55 * k))
