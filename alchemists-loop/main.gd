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
const BENCH_LIMIT := Balance.BENCH_LIMIT
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
	_saves = Saves.new(self)
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
		elif a == "--action=week":
			_demo_harness._action_week = true
	for a in args:
		if a.begins_with("--shot="):
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
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("circle")
		_retention._refresh_circle_page()
		_engine._refresh()
	if _demo_harness._demo and _demo_harness._action_week:
		_retention._inject_week_demo()
		if _tabs_ref != null:
			_tabs_ref.current_tab = 5
		_pages._ensure_modes()
		_pages._select_mode("week")
		_retention._refresh_week_page()
		_engine._refresh()
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

# ---------- R14: см. game/demo.gd (616-620) ----------


func _process(delta: float) -> void:
	_time += delta
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
	quests_btn.pressed.connect(_progress_ui._open_progress_popup)
	head.add_child(quests_btn)
	_hub._up_btn = _small_button("▲", Vector2(46, 36))
	_hub._up_btn.tooltip_text = "Улучшения"
	_hub._up_btn.pressed.connect(_hub._open_upgrades)
	head.add_child(_hub._up_btn)
	_sound_btn = _small_button("♪", Vector2(46, 36))
	_sound_btn.tooltip_text = "Настройки звука"
	_sound_btn.pressed.connect(_hub._open_settings)
	head.add_child(_sound_btn)
	var log_btn := _small_button("Ж", Vector2(46, 36))
	log_btn.tooltip_text = "Журнал событий"
	log_btn.pressed.connect(_hub._open_journal)
	head.add_child(log_btn)
	var me_btn := Button.new()
	me_btn.custom_minimum_size = Vector2(46, 36)
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
	_engine._ether_label = _label("", 17)
	_engine._ether_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_engine._brew_btn.custom_minimum_size = Vector2(120, 46)
	_engine._brew_btn.pressed.connect(_engine._brew)
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
	b.custom_minimum_size = Vector2(136, 46)
	b.pivot_offset = Vector2(68, 23)
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
	_popup = center

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
	Sfx.discovery()

func _hide_popup() -> void:
	_popup_dim.visible = false
	_popup.visible = false
	Sfx.click()

func _unhandled_input(event: InputEvent) -> void:
	# Esc закрывает верхний попап
	if _handle_esc(event):
		get_viewport().set_input_as_handled()

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
	dim.visible = false
	add_child(dim)
	_confirm_dim = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
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
