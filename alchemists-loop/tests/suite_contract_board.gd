extends RefCounted
class_name SuiteContractBoard
# Контрактная доска — проверки по спеке 2026-10-17. Каждое имя проверки =
# условие, которое может покраснеть: поведение или конкретное число из спеки,
# а не «поле существует».

# ---------- временные швы (§Global Constraints) ----------
const DT_SUN := {"year": 2026, "month": 10, "day": 18, "hour": 12, "minute": 0, "second": 0, "weekday": 0}
const DT_SUN_LATE := {"year": 2026, "month": 10, "day": 18, "hour": 23, "minute": 59, "second": 0, "weekday": 0}
const DT_MON := {"year": 2026, "month": 10, "day": 19, "hour": 0, "minute": 5, "second": 0, "weekday": 1}
const DT_MON_NEXT := {"year": 2026, "month": 10, "day": 26, "hour": 1, "minute": 0, "second": 0, "weekday": 1}
const DT_TUE := {"year": 2026, "month": 10, "day": 20, "hour": 9, "minute": 0, "second": 0, "weekday": 2}

# ---------- §3.2: стоимость в базовых элементах по реальному каталогу ----------
# Считается обходом g.RECIPES, а не берётся из таблицы спеки: если каталог
# изменится, покраснеют и расчёт, и коридор 200..600.
static func _base_cost(g: Game, item: String, trail: Array = []) -> int:
	if item in Game.BASE_IDS:
		return 1
	if trail.has(item):
		return 0
	for r in g.RECIPES:
		if String(r["out"]) != item:
			continue
		var next := trail.duplicate()
		next.append(item)
		return _base_cost(g, String(r["a"]), next) + _base_cost(g, String(r["b"]), next)
	return 0

static func _materials_base_cost(g: Game, mats: Dictionary) -> int:
	var total := 0
	for m in mats:
		total += int(mats[m]) * _base_cost(g, String(m))
	return total

static func _decor_item(decor_id: String) -> Dictionary:
	for cat in DecorData.DECOR:
		for item in (cat as Dictionary).get("items", []):
			if str((item as Dictionary).get("id", "")) == decor_id:
				return (item as Dictionary)
	return {}

static func run(g: Game) -> void:
	# ---------------- §2 таблицы типов и порогов ----------------
	Selftest.check("§2.1 daily pool has exactly 6 active types",
		ContractsBalance.DAILY_TYPES.size() == 6)
	Selftest.check("§2.2 weekly pool has exactly 5 active types",
		ContractsBalance.WEEKLY_TYPES.size() == 5)
	Selftest.check("§2.3 collect and masterwork are not contract types",
		not ContractsBalance.DAILY_TYPES.has("collect")
		and not ContractsBalance.WEEKLY_TYPES.has("collect")
		and not ContractsBalance.DAILY_TYPES.has("masterwork")
		and not ContractsBalance.WEEKLY_TYPES.has("masterwork"))
	var overlap := false
	for t in ContractsBalance.DAILY_TYPES:
		if ContractsBalance.WEEKLY_TYPES.has(t):
			overlap = true
	Selftest.check("daily and weekly type pools do not overlap", not overlap)
	Selftest.check("§2 tiers are bronze, silver, gold in that order",
		ContractsBalance.TIERS == ["bronze", "silver", "gold"])
	Selftest.check("§1.4 board shows 3 daily and 2 weekly",
		ContractsBalance.DAILY_SHOWN == 3 and ContractsBalance.WEEKLY_SHOWN == 2)

	var goals_ok := true
	for type in ContractsBalance.DAILY_TYPES:
		var arr = ContractsBalance.DAILY_GOALS.get(String(type), null)
		if typeof(arr) != TYPE_ARRAY or (arr as Array).size() != 3:
			goals_ok = false
			continue
		if not (int(arr[0]) <= int(arr[1]) and int(arr[1]) <= int(arr[2])):
			goals_ok = false
	for type in ContractsBalance.WEEKLY_TYPES:
		var arr = ContractsBalance.WEEKLY_GOALS.get(String(type), null)
		if typeof(arr) != TYPE_ARRAY or (arr as Array).size() != 3:
			goals_ok = false
			continue
		if not (int(arr[0]) <= int(arr[1]) and int(arr[1]) <= int(arr[2])):
			goals_ok = false
	Selftest.check("every contract type has 3 non-decreasing tier goals", goals_ok)

	# §2.1/§2.2: конкретные пороги из спеки. Мутация: поменять любое число —
	# проверка краснеет.
	Selftest.check("§2.1 brew goals are 15/40/80",
		ContractsBalance.DAILY_GOALS.get("brew", []) == [15, 40, 80])
	Selftest.check("§2.1 sigil_craft goals are 1/2/3",
		ContractsBalance.DAILY_GOALS.get("sigil_craft", []) == [1, 2, 3])
	Selftest.check("§2.2 prestige goals are 1/1/2 (bronze == silver on purpose)",
		ContractsBalance.WEEKLY_GOALS.get("prestige", []) == [1, 1, 2])
	Selftest.check("§2.2 variety goals are 8/15/25",
		ContractsBalance.WEEKLY_GOALS.get("variety", []) == [8, 15, 25])
	Selftest.check("§2.1 depth thresholds are 2 daily and 4 weekly",
		ContractsBalance.DEPTH_DAILY == 2 and ContractsBalance.DEPTH_WEEKLY == 4)

	# ---------------- §3.2 материалы ----------------
	Selftest.check("§3.2 daily gold materials are stone 55, brick 28, metal 14, glass 8",
		ContractsBalance.DAILY_MATERIALS.get("gold", {}) == {"stone": 55, "brick": 28, "metal": 14, "glass": 8})
	Selftest.check("§3.2 weekly gold materials are stone 220, brick 130, metal 70, glass 40, crystal 18",
		ContractsBalance.WEEKLY_MATERIALS.get("gold", {}) == {"stone": 220, "brick": 130, "metal": 70, "glass": 40, "crystal": 18})
	Selftest.check("§3.2 daily bronze materials are stone 20, brick 10",
		ContractsBalance.DAILY_MATERIALS.get("bronze", {}) == {"stone": 20, "brick": 10})
	var mats_ok := true
	for table in [ContractsBalance.DAILY_MATERIALS, ContractsBalance.WEEKLY_MATERIALS]:
		for tier in ContractsBalance.TIERS:
			var d = (table as Dictionary).get(String(tier), null)
			if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).is_empty():
				mats_ok = false
			else:
				for m in d:
					if int(d[m]) <= 0:
						mats_ok = false
	Selftest.check("all six tier material tables are non-empty with positive amounts", mats_ok)

	# §3.2: цепочки считаются по каталогу. Мутация: убрать рецепт sand из
	# g.RECIPES — glass подорожает и обе проверки покраснеют.
	Selftest.check("§3.2 base-element costs are stone 2, brick 3, metal 4, glass 4, crystal 8",
		_base_cost(g, "stone") == 2 and _base_cost(g, "brick") == 3
		and _base_cost(g, "metal") == 4 and _base_cost(g, "glass") == 4
		and _base_cost(g, "crystal") == 8)
	var daily_gold := _materials_base_cost(g, ContractsBalance.DAILY_MATERIALS.get("gold", {}))
	Selftest.check("§3.2 daily gold costs 282 base elements and stays inside the 200..600 corridor",
		daily_gold == 282 and daily_gold >= 200 and daily_gold <= 600)
	Selftest.check("§3.2 weekly gold costs 1414 base elements",
		_materials_base_cost(g, ContractsBalance.WEEKLY_MATERIALS.get("gold", {})) == 1414)

	# ---------------- §3.3 баффы ----------------
	Selftest.check("§3.3 there are exactly 5 buff ids",
		ContractsBalance.BUFF_IDS == ["brew_speed", "spring_yield", "craft_discount", "workshop_speed", "ether_regen"])
	var buff_ok := true
	for id in ContractsBalance.BUFF_IDS:
		var b = ContractsBalance.BUFF_BASE.get(String(id), null)
		if typeof(b) != TYPE_DICTIONARY:
			buff_ok = false
			continue
		if int((b as Dictionary).get("duration", 0)) <= 0 or float((b as Dictionary).get("power", 0.0)) <= 0.0:
			buff_ok = false
		if not ContractsBalance.BUFF_TITLE.has(String(id)) or str(ContractsBalance.BUFF_TITLE[String(id)]) == "":
			buff_ok = false
		# §5.4: записка по тапу показывает, что бафф делает. Пустой текст = «null» на бумаге.
		if not ContractsBalance.BUFF_TEXT.has(String(id)) or str(ContractsBalance.BUFF_TEXT[String(id)]) == "":
			buff_ok = false
	Selftest.check("every buff has positive base duration, positive base power, a title and an effect text", buff_ok)
	Selftest.check("§3.3 brew_speed base is 7200 s at power 0.25",
		ContractsBalance.BUFF_BASE.get("brew_speed", {}) == {"duration": 7200, "power": 0.25})
	Selftest.check("§3.3 spring_yield base is 1800 s at power 1.0",
		ContractsBalance.BUFF_BASE.get("spring_yield", {}) == {"duration": 1800, "power": 1.0})
	Selftest.check("§3.3 craft_discount base is 10800 s at power 0.20",
		ContractsBalance.BUFF_BASE.get("craft_discount", {}) == {"duration": 10800, "power": 0.2})
	Selftest.check("§3.3 workshop_speed base is 3600 s at power 0.30",
		ContractsBalance.BUFF_BASE.get("workshop_speed", {}) == {"duration": 3600, "power": 0.3})
	Selftest.check("§3.3 ether_regen base is 7200 s at power 1.0",
		ContractsBalance.BUFF_BASE.get("ether_regen", {}) == {"duration": 7200, "power": 1.0})

	# ---------------- §3.1 веса и максимумы ----------------
	Selftest.check("§3.1 workshop and spring weights sum to 1.0",
		absf(ContractsBalance.WORKSHOP_WEIGHT + ContractsBalance.SPRING_WEIGHT - 1.0) < 0.0001)
	Selftest.check("§3.1 workshop weight is greater than spring weight",
		ContractsBalance.WORKSHOP_WEIGHT > ContractsBalance.SPRING_WEIGHT)
	Selftest.check("§3.1 the only tuning knob is MULT_COEF == 1.05",
		absf(ContractsBalance.MULT_COEF - 1.05) < 0.0001)
	Selftest.check("§3.1 workshop maxima are rank 3 and autonomy 2",
		ContractsBalance.RANK_MAX == 3 and ContractsBalance.AUTONOMY_MAX == 2)
	Selftest.check("§3.1 spring maxima are speed 7, volume 7, sources 3, offline 3",
		ContractsBalance.SPRING_MAX == {"speed": 7, "volume": 7, "sources": 3, "offline": 3})
	# Максимумы взяты из кода, а не назначены: сверка с реальными таблицами.
	Selftest.check("§3.1 rank max matches WorkshopBalance.RANKS (4 entries, index 0..3)",
		WorkshopBalance.RANKS.size() == ContractsBalance.RANK_MAX + 1)
	Selftest.check("§3.1 autonomy max matches WorkshopBalance.AUTONOMY (3 entries, index 0..2)",
		WorkshopBalance.AUTONOMY.size() == ContractsBalance.AUTONOMY_MAX + 1)
	# Оси улучшения Родника (speed/volume/sources/offline) в этом дереве таблиц
	# не имеют: SpringBalance с SPEED/VOLUME/SOURCES/OFFLINE живёт в неслитой
	# ветке feature/spring-v2, а в HEAD здесь Родник — капля без прокачки.
	# Поэтому 4 сверки SPRING_MAX по размерам таблиц не написаны: обращение к
	# несуществующим константам — не красный тест, а compile-ошибка всего билда.
	# Числа SPRING_MAX выше всё равно зафиксированы spec-значениями.

	# ---------------- §3.4 косметика ----------------
	Selftest.check("§3.4 there are exactly 3 decor reward ids",
		ContractsBalance.DECOR == ["window_contract", "window_seal", "window_guild"])
	var decor_ok := true
	for id in ContractsBalance.DECOR:
		var item := _decor_item(String(id))
		# Мутация: убрать предмет из decor.gd или снять "reward": true — краснеет.
		if item.is_empty() or not bool(item.get("reward", false)) or int(item.get("cost", -1)) != 0:
			decor_ok = false
		if str(ContractsBalance.DECOR_LABEL.get(String(id), "")) == "":
			decor_ok = false
	Selftest.check("§3.4 every decor id exists in DecorData as a reward-only window (cost 0)", decor_ok)

	# ---------------- заголовки для UI ----------------
	var title_ok := true
	for type in ContractsBalance.DAILY_TYPES + ContractsBalance.WEEKLY_TYPES:
		if str(ContractsBalance.TITLE.get(String(type), "")) == "":
			title_ok = false
	for tier in ContractsBalance.TIERS:
		if str(ContractsBalance.TIER_TITLE.get(String(tier), "")) == "":
			title_ok = false
	for kind in ["daily", "weekly"]:
		if str(ContractsBalance.KIND_TITLE.get(kind, "")) == "":
			title_ok = false
	Selftest.check("every type, tier and kind has a non-empty Russian label", title_ok)
