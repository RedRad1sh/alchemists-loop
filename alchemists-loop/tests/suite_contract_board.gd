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
	Selftest.check("§3.1 spring speed max matches SpringBalance.SPEED size",
		SpringBalance.SPEED.size() == int(ContractsBalance.SPRING_MAX["speed"]))
	Selftest.check("§3.1 spring volume max matches SpringBalance.VOLUME size",
		SpringBalance.VOLUME.size() == int(ContractsBalance.SPRING_MAX["volume"]))
	Selftest.check("§3.1 spring sources max matches SpringBalance.SOURCES size",
		SpringBalance.SOURCES.size() == int(ContractsBalance.SPRING_MAX["sources"]))
	Selftest.check("§3.1 spring offline max matches SpringBalance.OFFLINE size",
		SpringBalance.OFFLINE.size() == int(ContractsBalance.SPRING_MAX["offline"]))

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

	# ---------------- §1.4 генерация ----------------
	# Зонд — отдельный экземпляр: живой g._contracts эти проверки не трогают.
	var probe := Contracts.new(g)
	var day_key := Contracts.day_key_from(DT_SUN)
	Selftest.check("§1.4 day key is the local YYYY-MM-DD of the given datetime",
		day_key == "2026-10-18" and Contracts.day_key_from(DT_MON) == "2026-10-19")
	# ISO-ключи сверены с эталонным расчётом на всём диапазоне 1970..2200.
	Selftest.check("§1.4 ISO week keys: Sun 2026-10-18 is 2026-W42, Mon 2026-10-19 is 2026-W43",
		Contracts.week_key_from(DT_SUN) == "2026-W42" and Contracts.week_key_from(DT_MON) == "2026-W43")
	Selftest.check("§1.4 a Sunday and the following Monday fall into different ISO weeks",
		Contracts.week_key_from(DT_SUN) != Contracts.week_key_from(DT_MON))
	Selftest.check("§1.4 Monday and Tuesday of one week share the ISO week key",
		Contracts.week_key_from(DT_MON) == Contracts.week_key_from(DT_TUE)
		and Contracts.week_key_from(DT_MON) == "2026-W43")
	Selftest.check("§1.4 a late-December Monday belongs to week 01 of the next ISO year",
		Contracts.week_key_from({"year": 2024, "month": 12, "day": 30, "hour": 12,
			"minute": 0, "second": 0, "weekday": 1}) == "2025-W01")

	# Тест №1: детерминизм.
	var gen_a := probe._generate_daily(day_key, 3)
	var gen_b := probe._generate_daily(day_key, 3)
	Selftest.check("§6.1 the same local date generates a byte-identical daily set on both calls",
		gen_a == gen_b and gen_a.size() == ContractsBalance.DAILY_SHOWN)
	var week_key := Contracts.week_key_from(DT_MON)
	Selftest.check("§6.1 the same ISO week generates a byte-identical weekly set on both calls",
		probe._generate_weekly(week_key) == probe._generate_weekly(week_key)
		and probe._generate_weekly(week_key).size() == ContractsBalance.WEEKLY_SHOWN)

	var types_seen := {}
	var type_dup := false
	for c in gen_a:
		var t := String((c as Dictionary)["type"])
		if types_seen.has(t):
			type_dup = true
		types_seen[t] = true
	var types_in_pool := true
	for t in types_seen.keys():
		if not ContractsBalance.DAILY_TYPES.has(String(t)):
			types_in_pool = false
	Selftest.check("§1.4 the 3 daily contracts have 3 distinct types from the pool",
		not type_dup and types_seen.size() == 3 and types_in_pool)

	# Разные даты дают разные наборы. Точечное сравнение двух конкретных дней
	# могло бы совпасть случайно, поэтому меряем разнообразие на 30 днях.
	var base_unix := int(Time.get_unix_time_from_datetime_dict(
		{"year": 2026, "month": 10, "day": 1, "hour": 12, "minute": 0, "second": 0}))
	var distinct := {}
	for offset in 30:
		var dt := Time.get_datetime_dict_from_unix_time(base_unix + offset * 86400)
		distinct[JSON.stringify(probe._generate_daily(Contracts.day_key_from(dt), 3))] = true
	Selftest.check("§6.1 30 consecutive days produce at least 20 distinct daily sets",
		distinct.size() >= 20)

	# Тест №25: бафф из seed у каждого контракта, декор — только у недельного gold.
	var seed_ok := true
	for c in probe._generate_weekly(week_key):
		var cc: Dictionary = c
		var tier := String(cc["tier"])
		var decor := String(cc["decor"])
		if not ContractsBalance.BUFF_IDS.has(String(cc["buff"])):
			seed_ok = false
		if tier == "gold":
			if not ContractsBalance.DECOR.has(decor):
				seed_ok = false
		elif decor != "":
			seed_ok = false
	for c in gen_a:
		var cc: Dictionary = c
		if not ContractsBalance.BUFF_IDS.has(String(cc["buff"])) or String(cc["decor"]) != "":
			seed_ok = false
	Selftest.check("§6.25 every contract carries a seed-chosen buff id and only weekly gold carries a decor id",
		seed_ok)
	# Обратная сторона детерминизма: за 60 недель встречается больше одного декора.
	var decors_seen := {}
	for offset in 60:
		var wdt := Time.get_datetime_dict_from_unix_time(base_unix + offset * 7 * 86400)
		for c in probe._generate_weekly(Contracts.week_key_from(wdt)):
			var d := String((c as Dictionary)["decor"])
			if d != "":
				decors_seen[d] = true
	Selftest.check("§3.4 60 consecutive weeks reach more than one distinct decor reward",
		decors_seen.size() >= 2)

	# Тест №23: недостижимый gold не генерируется — в обе стороны.
	var gold_with_two := false
	for c in probe._generate_daily(day_key, 2):
		if String((c as Dictionary)["type"]) == "sigil_craft" and String((c as Dictionary)["tier"]) == "gold":
			gold_with_two = true
	Selftest.check("§6.23 sigil_craft gold is never generated when the daily Arcana offer has fewer than 3 crafts",
		not gold_with_two)
	var gold_with_five := false
	for offset in 200:
		var dt := Time.get_datetime_dict_from_unix_time(base_unix + offset * 86400)
		for c in probe._generate_daily(Contracts.day_key_from(dt), 5):
			if String((c as Dictionary)["type"]) == "sigil_craft" and String((c as Dictionary)["tier"]) == "gold":
				gold_with_five = true
	Selftest.check("§6.23 sigil_craft gold does appear when the daily Arcana offer has 3 or more crafts",
		gold_with_five)

	# Тест №2: граница дня.
	var p2 := Contracts.new(g)
	p2.ensure_period(DT_SUN)
	var day1 := p2._contracts_daily.duplicate(true)
	var first_id := String((day1[0] as Dictionary)["id"])
	p2._contracts_daily_prog[first_id] = 5
	p2._contracts_daily_done[first_id] = true
	p2.ensure_period(DT_SUN_LATE)
	Selftest.check("§6.2 later the same local day keeps the daily set, progress and done flags",
		p2._contracts_daily == day1 and int(p2._contracts_daily_prog.get(first_id, 0)) == 5
		and p2._contracts_daily_done.has(first_id))
	p2.ensure_period(DT_MON)
	var new_day_key := Contracts.day_key_from(DT_MON)
	var ids_of_new_day := not p2._contracts_daily.is_empty()
	for c in p2._contracts_daily:
		if not String((c as Dictionary)["id"]).ends_with(":" + new_day_key):
			ids_of_new_day = false
	Selftest.check("§6.2 crossing local midnight regenerates dailies keyed by the new day and clears daily progress and done",
		p2._contracts_last_daily == new_day_key and ids_of_new_day
		and p2._contracts_daily_prog.is_empty() and p2._contracts_daily_done.is_empty())

	# Тест №3: граница недели.
	var p3 := Contracts.new(g)
	p3.ensure_period(DT_MON)
	var w3 := p3._contracts_weekly.duplicate(true)
	p3._contracts_weekly_prog[String((w3[0] as Dictionary)["id"])] = 2
	p3._contracts_variety["steam"] = true
	p3._contracts_set_week["set_a"] = 3
	p3.ensure_period(DT_MON_NEXT)
	var next_week_key := Contracts.week_key_from(DT_MON_NEXT)
	var ids_of_new_week := not p3._contracts_weekly.is_empty()
	for c in p3._contracts_weekly:
		if not String((c as Dictionary)["id"]).ends_with(":" + next_week_key):
			ids_of_new_week = false
	Selftest.check("§6.3 crossing Monday 00:00 regenerates weeklies and clears weekly progress, variety and set counters",
		p3._contracts_last_weekly == next_week_key and ids_of_new_week
		and p3._contracts_weekly_prog.is_empty() and p3._contracts_variety.is_empty()
		and p3._contracts_set_week.is_empty())
	# Внутри недели ничего не сбрасывается.
	var p5 := Contracts.new(g)
	p5.ensure_period(DT_MON)
	var w5id := String((p5._contracts_weekly[0] as Dictionary)["id"])
	p5._contracts_weekly_prog[w5id] = 4
	p5.ensure_period(DT_TUE)
	Selftest.check("§1.4 Tuesday of the same ISO week keeps weekly progress untouched",
		p5._contracts_weekly_prog.size() == 1 and int(p5._contracts_weekly_prog[w5id]) == 4)

	# §4.1: id контракта собирает период, поэтому списки выполненных не
	# пересекаются между периодами.
	var id_shape := true
	for c in probe.all_contracts(DT_MON):
		var cc: Dictionary = c
		var want := "%s:%s:%s:%s" % [cc["kind"], cc["type"], cc["tier"],
			Contracts.day_key_from(DT_MON) if cc["kind"] == "daily" else Contracts.week_key_from(DT_MON)]
		if String(cc["id"]) != want:
			id_shape = false
		if ContractsBalance.TIERS.find(String(cc["tier"])) < 0:
			id_shape = false
		var goals: Dictionary = ContractsBalance.DAILY_GOALS if cc["kind"] == "daily" else ContractsBalance.WEEKLY_GOALS
		if int(cc["goal"]) != int((goals[String(cc["type"])] as Array)[ContractsBalance.TIERS.find(String(cc["tier"]))]):
			id_shape = false
	Selftest.check("§4.1 every contract id is kind:type:tier:period_key and goal matches the balance table",
		id_shape)
	Selftest.check("§4.1 all_contracts returns 3 daily + 2 weekly = 5 contracts",
		probe.all_contracts(DT_MON).size() == ContractsBalance.DAILY_SHOWN + ContractsBalance.WEEKLY_SHOWN)
	Selftest.check("§4.1 contract_by_id returns an empty dictionary for an id from a burnt period",
		probe.contract_by_id("daily:brew:gold:2020-01-01", DT_MON).is_empty())

	# ---------------- проводка ----------------
	Selftest.check("g._contracts exists and points back at the game",
		g._contracts != null and g._contracts.g == g)
	Selftest.check("§4.1 CONTRACTS_SAVE_VERSION is 1", Contracts.CONTRACTS_SAVE_VERSION == 1)
	# Живой экземпляр генерирует сегодняшний набор при первом обращении.
	Selftest.check("§1.4 the live instance generates 3 daily and 2 weekly on first access",
		g._contracts.daily().size() == ContractsBalance.DAILY_SHOWN
		and g._contracts.weekly().size() == ContractsBalance.WEEKLY_SHOWN)
