extends RefCounted
class_name QuestData
# Задания Светика и достижения: таблицы и бонусы (бывшие const из main.gd, оп D).

# постоянные бонусы прогрессии (ценнее плоского эфира — не сгорают за идл)
const QUEST_CAP := 6       # +к максимуму эфира за каждое задание
const QUEST_REGEN := 0.03  # +регенерация/с за каждое задание
const ACH_CAP := 2         # +к максимуму эфира за каждое достижение
const ACH_REGEN := 0.015   # +регенерация/с за каждое достижение

const SPIRIT_QUESTS := [
	{"id": "q1", "title": "Первая пара", "goal": "brew", "target": "steam", "count": 1, "ether": 15, "aff": 2,
	 "hint": "Свари Пар: Огонь + Вода."},
	{"id": "q2", "title": "Лепка", "goal": "brew", "target": "clay", "count": 1, "ether": 15, "aff": 1,
	 "hint": "Свари Глину: Земля + Вода."},
	{"id": "q3", "title": "Коллекционер", "goal": "items", "count": 6, "ether": 20, "aff": 1,
	 "hint": "Открой 6 веществ."},
	{"id": "q4", "title": "На облака", "goal": "brew", "target": "cloud", "count": 1, "ether": 20, "aff": 1,
	 "hint": "Свари Облако: Пар + Воздух."},
	{"id": "q5", "title": "Редкость", "goal": "tier", "tier": 2, "count": 1, "ether": 30, "aff": 2,
	 "hint": "Получи редкое или выше вещество."},
	{"id": "q6", "title": "Дыхание жизни", "goal": "brew", "target": "life", "count": 1, "ether": 30, "aff": 2,
	 "hint": "Свари Жизнь: Искра + Вода."},
	{"id": "q7", "title": "Человек", "goal": "brew", "target": "person", "count": 1, "ether": 45, "aff": 2,
	 "hint": "Свари Человека: Жизнь + Глина."},
	{"id": "q8", "title": "Эпическая глубина", "goal": "tier", "tier": 3, "count": 1, "ether": 60, "aff": 3,
	 "hint": "Получи эпическое или легендарное вещество."},
	{"id": "q9", "title": "Книжник", "goal": "recipes", "count": 10, "ether": 50, "aff": 2,
	 "hint": "Узнай 10 рецептов."},
	{"id": "q10", "title": "Друг Светика", "goal": "affinity", "level": 2, "count": 1, "ether": 50, "aff": 5,
	 "hint": "Достигни 2-го уровня дружбы со Светиком."},
	{"id": "q11", "title": "Полный круг", "goal": "items", "count": 30, "ether": 75, "aff": 3,
	 "hint": "Открой 30 веществ."},
]
const ACHIEVEMENTS := [
	{"id": "a_items6", "title": "Начинающий алхимик", "kind": "items", "param": 6, "ether": 25},
	{"id": "a_items12", "title": "Подмастерье", "kind": "items", "param": 12, "ether": 35},
	{"id": "a_items20", "title": "Мастер", "kind": "items", "param": 20, "ether": 55},
	{"id": "a_items30", "title": "Знаток", "kind": "items", "param": 30, "ether": 80},
	{"id": "a_items40", "title": "Гроссмейстер", "kind": "items", "param": 40, "ether": 120},
	{"id": "a_items57", "title": "Архимаг", "kind": "items", "param": 57, "ether": 180},
	{"id": "a_rec5", "title": "Книга открыта", "kind": "recipes", "param": 5, "ether": 25},
	{"id": "a_rec10", "title": "Пытливый ум", "kind": "recipes", "param": 10, "ether": 35},
	{"id": "a_rec20", "title": "Библиотекарь", "kind": "recipes", "param": 20, "ether": 55},
	{"id": "a_rec35", "title": "Хранитель знаний", "kind": "recipes", "param": 35, "ether": 80},
	{"id": "a_rec53", "title": "Атлас рецептов", "kind": "recipes", "param": 53, "ether": 140},
	{"id": "a_brew10", "title": "Первые пузыри", "kind": "successes", "param": 10, "ether": 25},
	{"id": "a_brew50", "title": "Котёл не спит", "kind": "successes", "param": 50, "ether": 70},
	{"id": "a_brew100", "title": "Варщик", "kind": "successes", "param": 100, "ether": 130},
	{"id": "a_fail25", "title": "Упорный", "kind": "fails", "param": 25, "ether": 35},
	{"id": "a_world1", "title": "Первооткрыватель", "kind": "world_first", "param": 1, "ether": 80},
	{"id": "a_world3", "title": "Пионер", "kind": "world_first", "param": 3, "ether": 170},
	{"id": "a_chal1", "title": "Целеустремлённый", "kind": "challenge", "param": 1, "ether": 55},
	{"id": "a_chal3", "title": "Мастер целей", "kind": "challenge", "param": 3, "ether": 150},
	{"id": "a_legend", "title": "Легенда в котле", "kind": "legend", "param": 1, "ether": 110},
	{"id": "a_aff3", "title": "Душевный друг", "kind": "affinity", "param": 3, "ether": 55},
	{"id": "a_aff4", "title": "Неразлучные", "kind": "affinity", "param": 4, "ether": 125},
	{"id": "a_up5", "title": "Вложения", "kind": "upgrades", "param": 5, "ether": 35},
	{"id": "a_up12", "title": "Инвестор", "kind": "upgrades", "param": 12, "ether": 110},
	{"id": "a_sets4", "title": "Повелитель стихий", "kind": "sets", "param": 4, "ether": 180},
]
