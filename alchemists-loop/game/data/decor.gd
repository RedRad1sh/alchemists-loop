extends RefCounted
class_name DecorData
# Дом и декор: темы, ауры, цены, каталог, палитра (бывшие const из main.gd, оп D).

const WORKSHOP_THEMES := [
	{"id": "cobalt", "label": "Кобальт", "cost": 0},
	{"id": "ember", "label": "Угли", "cost": 120},
	{"id": "moss", "label": "Мох", "cost": 120},
	{"id": "violet", "label": "Аметист", "cost": 120},
]

const WORKSHOP_AURAS := [
	{"id": "amber", "label": "Янтарь", "cost": 0},
	{"id": "rose", "label": "Роза", "cost": 150},
	{"id": "aqua", "label": "Аква", "cost": 150},
	{"id": "violet", "label": "Фиалка", "cost": 150},
	{"id": "hearth", "label": "Очаг", "cost": 0},
]

const HOUSE_COST := 400  # домик для Светика
# кастомные цвета: разовая разблокировка цели (п.7). Аура Светика — дороже всех.
const CUSTOM_COSTS := {"theme": 600, "aura": 1200, "wall": 500, "floor": 500}

const DECOR := [
	{"id": "window", "label": "Окно", "items": [
		{"id": "window", "label": "Классическое", "tint": "#8fc6ea", "cost": 70},
		{"id": "window_1", "label": "Полукруглое", "tint": "#62b8e2", "cost": 85},
		{"id": "window_2", "label": "Панорамное", "tint": "#6fbbe4", "cost": 100},
		{"id": "window_3", "label": "Стрельчатое", "tint": "#7cbfe6", "cost": 115},
		{"id": "window_4", "label": "С цветами", "tint": "#89c4e9", "cost": 130},
		{"id": "window_5", "label": "Лунное", "tint": "#95c8eb", "cost": 145},
		{"id": "window_6", "label": "Закатное", "tint": "#a2ceee", "cost": 160},
		{"id": "window_7", "label": "Морозное", "tint": "#afd3f0", "cost": 175},
		{"id": "window_8", "label": "Эркер", "tint": "#bcd9f2", "cost": 190},
		{"id": "window_9", "label": "Витражное", "tint": "#c9e0f5", "cost": 205},
	]},
	{"id": "rug", "label": "Ковёр", "items": [
		{"id": "rug", "label": "Классический", "tint": "#b06a78", "cost": 80},
		{"id": "rug_1", "label": "Восточный", "tint": "#954f62", "cost": 95},
		{"id": "rug_2", "label": "Полосатый", "tint": "#9f5467", "cost": 110},
		{"id": "rug_3", "label": "Круглый", "tint": "#a85b6d", "cost": 125},
		{"id": "rug_4", "label": "Мохнатый", "tint": "#ad6574", "cost": 140},
		{"id": "rug_5", "label": "Зимний", "tint": "#b36f7c", "cost": 155},
		{"id": "rug_6", "label": "Луговой", "tint": "#b87984", "cost": 170},
		{"id": "rug_7", "label": "Шахматный", "tint": "#bd838c", "cost": 185},
		{"id": "rug_8", "label": "Царский", "tint": "#c38d94", "cost": 200},
		{"id": "rug_9", "label": "Звёздный", "tint": "#c8979c", "cost": 215},
	]},
	{"id": "chair", "label": "Стул", "items": [
		{"id": "chair", "label": "Классический", "tint": "#a5794a", "cost": 90},
		{"id": "chair_1", "label": "Резной", "tint": "#805939", "cost": 105},
		{"id": "chair_2", "label": "Мягкий", "tint": "#8b623e", "cost": 120},
		{"id": "chair_3", "label": "Табурет", "tint": "#956b43", "cost": 135},
		{"id": "chair_4", "label": "Трон", "tint": "#a07448", "cost": 150},
		{"id": "chair_5", "label": "Венский", "tint": "#aa7e4c", "cost": 165},
		{"id": "chair_6", "label": "Плетёный", "tint": "#b28754", "cost": 180},
		{"id": "chair_7", "label": "Высокий", "tint": "#b7915e", "cost": 195},
		{"id": "chair_8", "label": "Скамья", "tint": "#bc9969", "cost": 210},
		{"id": "chair_9", "label": "Кресло", "tint": "#c0a273", "cost": 225},
	]},
	{"id": "plant", "label": "Растение", "items": [
		{"id": "plant", "label": "В горшке", "tint": "#a3543c", "cost": 100},
		{"id": "plant_1", "label": "Папоротник", "tint": "#7c3a2e", "cost": 115},
		{"id": "plant_2", "label": "Фикус", "tint": "#874132", "cost": 130},
		{"id": "plant_3", "label": "Кактус", "tint": "#924936", "cost": 145},
		{"id": "plant_4", "label": "Розовый куст", "tint": "#9d503a", "cost": 160},
		{"id": "plant_5", "label": "Пальма", "tint": "#a9583e", "cost": 175},
		{"id": "plant_6", "label": "Бонсай", "tint": "#b46042", "cost": 190},
		{"id": "plant_7", "label": "Вьюнок", "tint": "#bc6a49", "cost": 205},
		{"id": "plant_8", "label": "Подсолнух", "tint": "#c07554", "cost": 220},
		{"id": "plant_9", "label": "Суккулент", "tint": "#c48060", "cost": 235},
	]},
	{"id": "lamp", "label": "Лампа", "items": [
		{"id": "lamp", "label": "Классическая", "tint": "#c9a24d", "cost": 110},
		{"id": "lamp_1", "label": "Настольная", "tint": "#ac7e34", "cost": 125},
		{"id": "lamp_2", "label": "Торшер", "tint": "#b88938", "cost": 140},
		{"id": "lamp_3", "label": "Свеча", "tint": "#c4953b", "cost": 155},
		{"id": "lamp_4", "label": "Фонарь", "tint": "#c79e47", "cost": 170},
		{"id": "lamp_5", "label": "Люстра", "tint": "#cba653", "cost": 185},
		{"id": "lamp_6", "label": "Ночник", "tint": "#ceaf5f", "cost": 200},
		{"id": "lamp_7", "label": "Масляная", "tint": "#d2b76a", "cost": 215},
		{"id": "lamp_8", "label": "Волшебная", "tint": "#d5be76", "cost": 230},
		{"id": "lamp_9", "label": "Хрустальная", "tint": "#d9c582", "cost": 245},
	]},
	{"id": "table", "label": "Стол", "items": [
		{"id": "table", "label": "Классический", "tint": "#9a744c", "cost": 120},
		{"id": "table_1", "label": "Дубовый", "tint": "#76553a", "cost": 135},
		{"id": "table_2", "label": "Круглый", "tint": "#805d3f", "cost": 150},
		{"id": "table_3", "label": "Письменный", "tint": "#8b6644", "cost": 165},
		{"id": "table_4", "label": "Кофейный", "tint": "#956f49", "cost": 180},
		{"id": "table_5", "label": "Резной", "tint": "#9f794f", "cost": 195},
		{"id": "table_6", "label": "Мраморный", "tint": "#a98254", "cost": 210},
		{"id": "table_7", "label": "Лёгкий", "tint": "#af8b5d", "cost": 225},
		{"id": "table_8", "label": "Длинный", "tint": "#b49467", "cost": 240},
		{"id": "table_9", "label": "Праздничный", "tint": "#b99d72", "cost": 255},
	]},
	{"id": "shelf", "label": "Полка", "items": [
		{"id": "shelf", "label": "Классическая", "tint": "#7a5a3c", "cost": 140},
		{"id": "shelf_1", "label": "Книжная", "tint": "#563c2a", "cost": 155},
		{"id": "shelf_2", "label": "Угловая", "tint": "#60452f", "cost": 170},
		{"id": "shelf_3", "label": "Плавающая", "tint": "#6b4d34", "cost": 185},
		{"id": "shelf_4", "label": "С посудой", "tint": "#755639", "cost": 200},
		{"id": "shelf_5", "label": "Со склянками", "tint": "#7f5e3f", "cost": 215},
		{"id": "shelf_6", "label": "Аптечная", "tint": "#896744", "cost": 230},
		{"id": "shelf_7", "label": "Высокая", "tint": "#947149", "cost": 245},
		{"id": "shelf_8", "label": "Двойная", "tint": "#9e7a4e", "cost": 260},
		{"id": "shelf_9", "label": "С часами", "tint": "#a88453", "cost": 275},
	]},
	{"id": "bed", "label": "Кровать", "items": [
		{"id": "bed", "label": "Классическая", "tint": "#b75d4d", "cost": 250},
		{"id": "bed_1", "label": "Перина", "tint": "#93433b", "cost": 265},
		{"id": "bed_2", "label": "Балдахин", "tint": "#9e4940", "cost": 280},
		{"id": "bed_3", "label": "Двуспальная", "tint": "#a95044", "cost": 295},
		{"id": "bed_4", "label": "Детская", "tint": "#b45849", "cost": 310},
		{"id": "bed_5", "label": "Деревянная", "tint": "#b96352", "cost": 325},
		{"id": "bed_6", "label": "С пологом", "tint": "#be6f5d", "cost": 340},
		{"id": "bed_7", "label": "Круглая", "tint": "#c27a68", "cost": 355},
		{"id": "bed_8", "label": "Тахта", "tint": "#c68673", "cost": 370},
		{"id": "bed_9", "label": "Роскошная", "tint": "#cb917e", "cost": 385},
	]},
	{"id": "fireplace", "label": "Камин", "items": [
		{"id": "fireplace", "label": "Классический", "tint": "#7a4a3a", "cost": 300},
		{"id": "fireplace_1", "label": "Каменный", "tint": "#563129", "cost": 315},
		{"id": "fireplace_2", "label": "Мраморный", "tint": "#60382e", "cost": 330},
		{"id": "fireplace_3", "label": "Угловой", "tint": "#6a3f33", "cost": 345},
		{"id": "fireplace_4", "label": "Печной", "tint": "#754638", "cost": 360},
		{"id": "fireplace_5", "label": "Кирпичный", "tint": "#7f4e3c", "cost": 375},
		{"id": "fireplace_6", "label": "Современный", "tint": "#8a5641", "cost": 390},
		{"id": "fireplace_7", "label": "Деревенский", "tint": "#945e46", "cost": 405},
		# §2.2: эксклюзивные награды Круга — не продаются (reward), выдаются β-путём
		{"id": "fireplace_ember", "label": "Уголёк очага", "tint": "#d2691e", "cost": 0, "reward": true},
		{"id": "fireplace_log", "label": "Полено очага", "tint": "#8b4513", "cost": 0, "reward": true},
		{"id": "fireplace_heart", "label": "Сердце очага", "tint": "#ffd700", "cost": 0, "reward": true},
		{"id": "fireplace_8", "label": "С порталом", "tint": "#9e664b", "cost": 420},
		{"id": "fireplace_9", "label": "Величественный", "tint": "#a96e50", "cost": 435},
	]},
]
const COLOR_SWATCHES := [
	"#0d1219", "#1a0e0e", "#0e1410", "#120f1a", "#3a4a6b", "#5a4636",
	"#7a4a3a", "#8a4a55", "#4d7ab7", "#5d9a6b", "#c9a24d", "#b78aff",
]
