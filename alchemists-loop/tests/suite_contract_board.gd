extends RefCounted
class_name SuiteContractBoard
# Контрактная доска — проверки по спеке 2026-10-17. Каждое имя проверки =
# условие, которое может покраснеть: поведение или конкретное число из спеки,
# а не «поле существует».

# ---------- §5.5: ассеты доски ----------
const CA_DIR := "res://assets/contracts/"

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

# Сюита меняет живое состояние игры, поэтому каждый блок обязан снимать снимок
# и восстанавливать его: иначе краснеют сюиты дальше по await-списку, а не та,
# что сломала (Review Focus №7).
static func _snap_progress(g: Game) -> Dictionary:
	return {
		"rank": g._workshop.rank, "autonomy": g._workshop.autonomy_level,
		"spring": g._engine.spring_levels.duplicate(true),
	}

static func _restore_progress(g: Game, s: Dictionary) -> void:
	g._workshop.rank = int(s["rank"])
	g._workshop.autonomy_level = int(s["autonomy"])
	g._engine.spring_levels = (s["spring"] as Dictionary).duplicate(true)

static func _set_progress(g: Game, rank: int, autonomy: int,
		speed: int, volume: int, sources: int, offline: int) -> void:
	g._workshop.rank = rank
	g._workshop.autonomy_level = autonomy
	g._engine.spring_levels = {"speed": speed, "volume": volume, "sources": sources, "offline": offline}

# ---------- хелперы Task 5 ----------
# Сюита подменяет списки контрактов живого объекта: набор дня детерминирован от
# даты, и ждать «сегодня выпал brew» нельзя. Прогресс лежит в тех же словарях,
# поэтому проверкам есть что краснить.
static func _force_set(c: Contracts, daily: Array, weekly: Array) -> void:
	# Ключи периода проставляем тем же «сегодня», что и id фикстур. Без этого
	# первый вызов `all_contracts()` внутри `ensure_period()` не найдёт совпадения,
	# выбросит набор фикстуры и сгенерирует настоящий — прогресс пойдёт мимо
	# проверяемого id, а проверка покраснеет не по той причине, по которой задумана.
	var dt := c._dt({})
	c._contracts_last_daily = Contracts.day_key_from(dt)
	c._contracts_last_weekly = Contracts.week_key_from(dt)
	c._contracts_daily = daily
	c._contracts_weekly = weekly

static func _mk(c: Contracts, kind: String, type: String, tier: String, goal: int) -> Dictionary:
	# Ключ берём из того же «сегодня», что и живой ensure_period(): иначе id
	# фикстуры разойдётся с ключом периода, и прогресс пишется не туда.
	var dt := c._dt({})
	var key := Contracts.day_key_from(dt) if kind == "daily" else Contracts.week_key_from(dt)
	return {
		"id": "%s:%s:%s:%s" % [kind, type, tier, key],
		"kind": kind, "type": type, "tier": tier, "goal": goal,
		"buff": "brew_speed", "decor": "",
	}

static func _clear_prog(c: Contracts) -> void:
	c._contracts_daily_prog.clear()
	c._contracts_weekly_prog.clear()
	c._contracts_daily_done.clear()
	c._contracts_weekly_done.clear()
	c._contracts_variety.clear()
	c._contracts_set_week.clear()
	c._last_output = ""

# ---------- Task 7: хелперы сейв-блока ----------
# Контракт, который генератор СЕГОДНЯ мог бы выдать, но не обязан. goal считается
# из таблицы напрямую, а не через Contracts._make_contract: иначе валидатор и
# фикстура сверяли бы друг с другом, а не с таблицей, и проверка «goal не совпал —
# контракт отвергнут» была бы зелёной всегда.
static func _mk_legal(c: Contracts, kind: String, type: String, tier: String) -> Dictionary:
	var dt := c._dt({})
	var key := Contracts.day_key_from(dt) if kind == "daily" else Contracts.week_key_from(dt)
	var goals: Dictionary = ContractsBalance.DAILY_GOALS if kind == "daily" else ContractsBalance.WEEKLY_GOALS
	return {
		"id": "%s:%s:%s:%s" % [kind, type, tier, key],
		"kind": kind, "type": type, "tier": tier,
		"goal": int((goals[type] as Array)[ContractsBalance.TIERS.find(tier)]),
		"buff": "brew_speed", "decor": "",
	}

static func _cb_snapshot(c: Contracts) -> Dictionary:
	return {
		"daily": c._contracts_daily.duplicate(true),
		"weekly": c._contracts_weekly.duplicate(true),
		"last_daily": c._contracts_last_daily,
		"last_weekly": c._contracts_last_weekly,
		"daily_done": c._contracts_daily_done.duplicate(true),
		"weekly_done": c._contracts_weekly_done.duplicate(true),
		"daily_prog": c._contracts_daily_prog.duplicate(true),
		"weekly_prog": c._contracts_weekly_prog.duplicate(true),
		"variety": c._contracts_variety.duplicate(true),
		"set_week": c._contracts_set_week.duplicate(true),
		"buffs": c._active_buffs.duplicate(true),
		"decor": c._unlocked_decor.duplicate(true),
		"last_output": c._last_output,
	}

static func _cb_restore(c: Contracts, s: Dictionary) -> void:
	c._contracts_daily = s["daily"]
	c._contracts_weekly = s["weekly"]
	c._contracts_last_daily = String(s["last_daily"])
	c._contracts_last_weekly = String(s["last_weekly"])
	c._contracts_daily_done = s["daily_done"]
	c._contracts_weekly_done = s["weekly_done"]
	c._contracts_daily_prog = s["daily_prog"]
	c._contracts_weekly_prog = s["weekly_prog"]
	c._contracts_variety = s["variety"]
	c._contracts_set_week = s["set_week"]
	c._active_buffs = s["buffs"]
	c._unlocked_decor = s["decor"]
	c._last_output = String(s["last_output"])

# Полный сброс состояния доски средствами сюиты — см. решение 5.
static func _cb_wipe(c: Contracts) -> void:
	_clear_prog(c)
	c._contracts_daily = []
	c._contracts_weekly = []
	c._contracts_last_daily = ""
	c._contracts_last_weekly = ""
	c._active_buffs = {}
	c._unlocked_decor = []

# Одно и то же богатое состояние для всех групп блока. now_u — настоящий unix,
# чтобы срок баффа после round-trip остался ровно тем же числом.
static func _cb_fill(c: Contracts, daily: Array, weekly: Array, now_u: int) -> void:
	_cb_wipe(c)
	_force_set(c, daily, weekly)
	c._contracts_daily_prog[String(daily[0]["id"])] = 4
	c._contracts_daily_prog[String(daily[2]["id"])] = 2
	c._contracts_weekly_done[String(weekly[0]["id"])] = true
	c._contracts_weekly_prog[String(weekly[1]["id"])] = 1
	c._contracts_variety = {"steam": true, "glass": true}
	c._contracts_set_week = {"fire": 4}
	c._active_buffs = {"spring_yield": {"until": now_u + 1800, "power": 2.0}}
	c._unlocked_decor = ["window_seal"]
	c._last_output = "steam"

# Переписать блок contracts в только что записанном сейве, остальной мир не трогать.
# raw == null — ключ стирается (сейв, написанный клиентом до доски).
static func _cb_put_block(g: Game, raw: Variant) -> void:
	var data := g._saves._read_save(g.SAVE_PATH)
	if data.is_empty():
		return
	if raw == null:
		data.erase("contracts")
	else:
		data["contracts"] = raw
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t", true, true))
	f.close()

# Записать сейв целиком (откат блока): остальной мир остаётся baseline-ным, а блок
# contracts стёрт, чтобы load_block при откате начал с чистого листа.
static func _cb_put_block_restore(g: Game, data: Dictionary) -> void:
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t", true, true))
	f.close()

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

	# ---------------- §3.1 единый множитель ----------------
	var snap_prog := _snap_progress(g)
	var c_daily_gold: Dictionary = {
		"id": "daily:brew:gold:2026-10-19", "kind": "daily", "type": "brew",
		"tier": "gold", "goal": 80, "buff": "brew_speed", "decor": "",
	}
	_set_progress(g, 0, 0, 0, 0, 0, 0)
	Selftest.check("§6.11 reward_mult is exactly 1.0 with an empty Spring and an empty Workshop",
		absf(g._contracts.reward_mult() - 1.0) < 0.0001)
	_set_progress(g, ContractsBalance.RANK_MAX, ContractsBalance.AUTONOMY_MAX,
		int(ContractsBalance.SPRING_MAX["speed"]), int(ContractsBalance.SPRING_MAX["volume"]),
		int(ContractsBalance.SPRING_MAX["sources"]), int(ContractsBalance.SPRING_MAX["offline"]))
	Selftest.check("§6.11 reward_mult is exactly 2.05 with a maxed Spring and a maxed Workshop",
		absf(g._contracts.reward_mult() - 2.05) < 0.0001)

	# Тест №12: вес Мастерской выше веса Родника.
	_set_progress(g, ContractsBalance.RANK_MAX, ContractsBalance.AUTONOMY_MAX, 0, 0, 0, 0)
	var from_workshop := g._contracts.reward_mult() - 1.0
	_set_progress(g, 0, 0, int(ContractsBalance.SPRING_MAX["speed"]),
		int(ContractsBalance.SPRING_MAX["volume"]), int(ContractsBalance.SPRING_MAX["sources"]),
		int(ContractsBalance.SPRING_MAX["offline"]))
	var from_spring := g._contracts.reward_mult() - 1.0
	Selftest.check("§6.12 a maxed Workshop with an empty Spring outweighs a maxed Spring with an empty Workshop",
		from_workshop > from_spring
		and absf(from_workshop - ContractsBalance.WORKSHOP_WEIGHT * ContractsBalance.MULT_COEF) < 0.0001
		and absf(from_spring - ContractsBalance.SPRING_WEIGHT * ContractsBalance.MULT_COEF) < 0.0001)

	# Половинные значения: множитель линейный и нормированный на свой максимум.
	_set_progress(g, 0, 1, 0, 0, 0, 0)
	Selftest.check("§3.1 half of the Workshop autonomy branch alone gives 1 + 1.05 * 0.65 * 0.25",
		absf(g._contracts.reward_mult() - (1.0 + ContractsBalance.MULT_COEF * ContractsBalance.WORKSHOP_WEIGHT * 0.25)) < 0.0001)
	_set_progress(g, 0, 0, 0, 0, 3, 0)
	Selftest.check("§3.1 a maxed sources axis alone contributes its own quarter of the Spring share",
		absf(g._contracts.reward_mult() - (1.0 + ContractsBalance.MULT_COEF * ContractsBalance.SPRING_WEIGHT * 0.25)) < 0.0001)

	# Тест №12b: один множитель на материалы, срок и силу. Отдельного скейла для
	# баффов нет — мутация «умножить только power» красит ровно эту проверку.
	_set_progress(g, ContractsBalance.RANK_MAX, ContractsBalance.AUTONOMY_MAX, 0, 0, 0, 0)
	var mult := g._contracts.reward_mult()
	var r := g._contracts.reward_for(c_daily_gold)
	Selftest.check("§6.12b materials, buff duration and buff power of one reward all use the same reward_mult",
		int(r["materials"]["stone"]) == int(round(55.0 * mult))
		and int(r["materials"]["brick"]) == int(round(28.0 * mult))
		and int(r["duration"]) == int(round(7200.0 * mult))
		and absf(float(r["power"]) - 0.25 * mult) < 0.0001)
	Selftest.check("§6.12b at a maxed Workshop the daily gold stone reward is exactly 93",
		int(r["materials"]["stone"]) == 93)

	# §3.1: множитель ограничен сверху — переполнение таблицы не даёт ×3.
	_set_progress(g, 99, 99, 99, 99, 99, 99)
	Selftest.check("§3.1 reward_mult is clamped to 2.05 even if levels exceed the tables",
		absf(g._contracts.reward_mult() - 2.05) < 0.0001)
	_restore_progress(g, snap_prog)

	# ---------------- §3.4 декор ----------------
	Selftest.check("§3.4 decor_exists is true for a real reward id and false for a made-up one",
		Contracts.decor_exists("window_contract") and Contracts.decor_exists("fireplace_ember")
		and not Contracts.decor_exists("window_does_not_exist"))

	# Награда недельного gold несёт декор, дневная — нет.
	var c_weekly_gold: Dictionary = {
		"id": "weekly:variety:gold:2026-W43", "kind": "weekly", "type": "variety",
		"tier": "gold", "goal": 25, "buff": "ether_regen", "decor": "window_guild",
	}
	var rw := g._contracts.reward_for(c_weekly_gold)
	Selftest.check("§3.3 weekly gold reward carries its decor id and the ether_regen base scaled by one mult",
		String(rw["decor"]) == "window_guild" and String(rw["buff"]) == "ether_regen"
		and int(rw["materials"]["crystal"]) == int(round(18.0 * g._contracts.reward_mult())))

	# ---------- Task 4: баффы (§3.3, §6.8, §6.9, §6.10) ----------
	var c4 := g._contracts
	var buffs4_snap := c4._active_buffs.duplicate(true)
	var now := int(Time.get_unix_time_from_system())

	c4.grant_buff("no_such_buff", 3600, 0.5, now)
	Selftest.check("§3.3 grant_buff ignores an id outside BUFF_IDS", c4._active_buffs.is_empty())
	c4.grant_buff("brew_speed", 0, 0.25, now)
	Selftest.check("§3.3 grant_buff ignores a non-positive duration", c4._active_buffs.is_empty())

	c4.grant_buff("brew_speed", 3600, 0.25, now)
	var first_until := int((c4._active_buffs.get("brew_speed", {}) as Dictionary).get("until", -1))
	c4.grant_buff("brew_speed", 3600, 0.9, now)
	var second := c4._active_buffs.get("brew_speed", {}) as Dictionary
	# §3.3: не стакается — сила НЕ умножается и НЕ заменяется на бо́льшую; срок
	# продлевается от текущего конца (max(until, now) + duration).
	Selftest.check("§6.10 a second grant extends the deadline from the old one and keeps the first power",
		int(second.get("until", -1)) == first_until + 3600 and absf(float(second.get("power", -1.0)) - 0.25) < 0.0001)
	c4.grant_buff("brew_speed", 3600, 0.25, now + 10_000_000)
	Selftest.check("§6.10 granting inside a live window still only extends the deadline",
		int((c4._active_buffs.get("brew_speed", {}) as Dictionary).get("until", -1)) == now + 10_000_000 + 3600)
	c4._active_buffs.clear()

	c4.grant_buff("ether_regen", 10, 1.0, 1_000_000)
	Selftest.check("§6.8 a buff whose until lies in the past gives no power",
		c4.buff_power("ether_regen", now) == 0.0)
	Selftest.check("§6.8 buff_left never returns a negative number", c4.buff_left("ether_regen", now) == 0)
	c4.grant_buff("brew_speed", 7200, 0.25, now)
	c4.prune_buffs(now)
	Selftest.check("§6.8 prune_buffs erases the expired buff and keeps the live one",
		not c4._active_buffs.has("ether_regen") and c4._active_buffs.has("brew_speed"))
	Selftest.check("§3.3 active_buffs lists live buffs in BUFF_IDS order with power, remaining seconds and title",
		c4.active_buffs(now) == [{"id": "brew_speed", "power": 0.25, "left": 7200,
			"title": String(ContractsBalance.BUFF_TITLE["brew_speed"])}])
	c4._active_buffs.clear()

	# §6.9 + §3.3: реальная формула в реальной точке потребления.
	# g.BREW_SECONDS — живая переменная: suite_bench_gifts оставляет после себя
	# 0.05, из-за чего maxf(0.35, …) в _brew_time климпит и базовое значение,
	# и значение с баффом, и проверка формулы стала бы зависеть от чужого
	# состояния. Ставим базовые 1.2 (main.gd:23) на время блока и возвращаем.
	var brew_secs_snap := g.BREW_SECONDS
	g.BREW_SECONDS = 1.2
	var brew_base := g._engine._brew_time()
	var ether_base := g._engine._ether_rate()
	c4.grant_buff("brew_speed", 7200, 0.25, -1)
	c4.grant_buff("ether_regen", 7200, 1.0, -1)
	Selftest.check("§6.9 an active brew_speed buff makes _brew_time exactly 1+power times smaller",
		absf(g._engine._brew_time() - brew_base / 1.25) < 0.000001)
	c4.grant_buff("brew_speed", 3600, 0.25, -1)
	Selftest.check("§6.10 two grants of brew_speed still divide _brew_time by exactly 1+power",
		absf(g._engine._brew_time() - brew_base / 1.25) < 0.000001)
	Selftest.check("§3.3 an active ether_regen buff multiplies _ether_rate by exactly 1+power",
		absf(g._engine._ether_rate() - ether_base * 2.0) < 0.000001)
	c4._active_buffs.clear()
	Selftest.check("§6.8 with no live buff the formulas return to their base values",
		absf(g._engine._brew_time() - brew_base) < 0.000001
		and absf(g._engine._ether_rate() - ether_base) < 0.000001)
	g.BREW_SECONDS = brew_secs_snap

	# §3.3 скорость линий Мастерской. Два места (_next_event и _elapse) вызывают
	# одну функцию, поэтому достаточно проверить её — несогласованность двух
	# строк стала бы возможной только если кто-то удалит вызов (видно в диффе).
	var sched: WorkshopScheduler = g._workshop_scheduler as WorkshopScheduler
	var offline_snap := sched._offline
	sched._offline = false
	Selftest.check("§3.3 _line_speed is 1.0 online with no buff", absf(sched._line_speed() - 1.0) < 0.000001)
	sched._offline = true
	Selftest.check("§3.3 _line_speed keeps the bench offline factor with no buff",
		absf(sched._line_speed() - Game.BENCH_OFFLINE_FACTOR) < 0.000001)
	c4.grant_buff("workshop_speed", 3600, 0.30, -1)
	Selftest.check("§3.3 an active workshop_speed buff multiplies the offline line speed by 1+power",
		absf(sched._line_speed() - Game.BENCH_OFFLINE_FACTOR * 1.3) < 0.000001)
	sched._offline = false
	Selftest.check("§3.3 the same buff multiplies the online line speed by 1+power",
		absf(sched._line_speed() - 1.3) < 0.000001)
	c4._active_buffs.clear()
	sched._offline = offline_snap

	# §3.3 скидка крафта: сначала математика SigilManager, затем реальная
	# проводка через g._sigil_ui (живой инстанс с main = g), а не текст файла.
	var sm := g._sigil
	var plain := {"set": "", "ether_cost": 400}
	var set6 := {"set": "zz_test_set", "ether_cost": 400}
	var claimed_snap := sm._milestones_claimed.duplicate(true)
	sm._milestones_claimed["zz_test_set"] = [6]
	Selftest.check("§3.3 the set-6 reward still costs 360 with no discount buff",
		sm.craft_ether_cost(set6) == 360 and sm.craft_ether_cost(plain) == 400)
	Selftest.check("§3.3 craft_discount reduces the cost by exactly its power and stacks with the set reward",
		sm.craft_ether_cost(set6, 0.2) == 288 and sm.craft_ether_cost(plain, 0.2) == 320)
	Selftest.check("§3.3 craft_discount is clamped at 90 percent", sm.craft_ether_cost(plain, 5.0) == 40)
	sm._milestones_claimed = claimed_snap
	c4.grant_buff("craft_discount", 10800, 0.20, -1)
	Selftest.check("§3.3 the Arcana UI reads the discount through the single cost helper",
		g._sigil_ui._sigil_ether_cost(plain) == 320)
	c4._active_buffs.clear()
	Selftest.check("§3.3 without the buff the Arcana UI helper returns the undiscounted cost",
		g._sigil_ui._sigil_ether_cost(plain) == 400)

	Selftest.check("§3.3 spring_yield is 1 with no live buff", c4.spring_yield(now) == 1)
	c4.grant_buff("spring_yield", 1800, 1.0, now + 999_999_999)
	Selftest.check("§3.3 an active power-1.0 spring_yield buff doubles the per-source yield",
		c4.spring_yield(1_000_000) == 2)
	c4._active_buffs.clear()
	c4.grant_buff("spring_yield", 1800, 2.05, now + 999_999_999)
	Selftest.check("§3.3 spring_yield rounds 1+2.05 to 3", c4.spring_yield(1_000_000) == 3)

	# §3.3 + Review Focus 4: реальный тик Родника и потолок буфера. Инвентарь,
	# буфер, список источников и режим живого Game трогаем только в пределах
	# этого блока и возвращаем как было (Review Focus 7).
	var e := g._engine
	var plant_had := e.inventory.has("plant")
	var water_had := e.inventory.has("water")
	var src_snap := e.spring_sources.duplicate()
	var levels_snap: Dictionary = e.spring_levels.duplicate(true)
	var on_snap := e.spring_on
	var buf_snap := e.spring_buffer.duplicate(true)
	var clock_snap := g._pages._spring_clock
	var water_snap := int(e.inventory.get("water", 0))
	e.inventory["plant"] = 1          # core.gd:650: spring разблокирован iff есть "plant"
	e.spring_sources = ["water"]
	e.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	e.spring_buffer.clear()           # кап = SpringBalance.VOLUME_CAP[0] = 100
	e.spring_on = true
	var cap := e._spring_volume_cap()
	g._pages._spring_clock = 0.0
	c4._active_buffs.clear()
	e._spring_tick(e.spring_interval() + 0.01)
	Selftest.check("§3.3 one spring tick adds spring_yield units to every active source",
		int(e.spring_buffer.get("water", 0)) == 1 and int(e.inventory.get("water", 0)) == water_snap + 1)
	c4.grant_buff("spring_yield", 1800, 1.0, -1)
	e.spring_buffer.clear()
	g._pages._spring_clock = 0.0
	var water_before := int(e.inventory.get("water", 0))
	e._spring_tick(e.spring_interval() + 0.01)
	Selftest.check("§3.3 a buffed tick adds the whole yield when the buffer has room",
		int(e.spring_buffer.get("water", 0)) == 2 and int(e.inventory.get("water", 0)) == water_before + 2)
	# Потолок: буфер никогда не превышает кап, избыток сгорает — как эфир сверх
	# капа. Без этой отсечки бафф spring_yield пробивал бы объёмное ограничение.
	e.spring_buffer["water"] = cap - 1
	g._pages._spring_clock = 0.0
	var capped_before := int(e.inventory.get("water", 0))
	e._spring_tick(e.spring_interval() + 0.01)
	Selftest.check("§3.3 a buffed tick never raises the source buffer above _spring_volume_cap",
		int(e.spring_buffer.get("water", 0)) == cap
		and int(e.inventory.get("water", 0)) == capped_before + 1)
	e.spring_buffer.clear()
	Selftest.check("§3.3 _spring_gain returns exactly what it added and 0 once the buffer is full",
		e._spring_gain("water", 3) == 3 and e._spring_gain("water", 99_999) == cap - 3
		and e._spring_gain("water", 5) == 0 and int(e.spring_buffer.get("water", 0)) == cap)
	c4._active_buffs = buffs4_snap
	e.spring_buffer = buf_snap
	e.spring_sources = src_snap
	e.spring_levels = levels_snap.duplicate(true)
	e.spring_on = on_snap
	g._pages._spring_clock = clock_snap
	# Воду возвращаем симметрично растению: если до блока ключа не было, он не
	# должен появиться — `water: 0` увеличил бы inventory.size(), а на нём
	# основан _mode_unlocked (core.gd:661) у последующих workshop-сюит.
	if water_had:
		e.inventory["water"] = water_snap
	else:
		e.inventory.erase("water")
	if not plant_had:
		e.inventory.erase("plant")

	# ---------- Task 5: хуки и правило активности ----------
	var c5 := g._contracts
	var brew_snap := {
		"inv": g._engine.inventory.duplicate(true),
		"known": g._engine.known_recipes.duplicate(true),
		"known_defs": g._engine.known_recipe_defs.duplicate(true),
		"ether": g._engine.ether,
		"attempts": g._engine.attempts,
		"successes": g._engine.successes,
	}
	var buffs5_snap := c5._active_buffs.duplicate(true)
	var rejected_snap := g._engine._rejected_pairs.duplicate(true)
	var coll_snap := g._sigil._collection.duplicate(true)
	var cat_snap := g._sigil._catalog.duplicate(true)

	var brew_daily := [_mk(c5, "daily", "brew", "bronze", 15), _mk(c5, "daily", "chain_brew", "bronze", 5),
		_mk(c5, "daily", "depth_brew", "bronze", 3)]
	var brew_weekly := [_mk(c5, "weekly", "variety", "bronze", 8), _mk(c5, "weekly", "rare_brew", "bronze", 3)]
	var exp_daily := [_mk(c5, "daily", "experiment", "bronze", 6), _mk(c5, "daily", "discover", "bronze", 1)]
	# Цели фикстур experiment/sigil_craft/upgrade намеренно выше bronze-значений
	# таблицы: эти счётчики накопительные, и часть проверок считает больше
	# событий, чем bronze-goal. Отсечку «прогресс не превышает цель» доказывает
	# отдельная фикстура brew с целью 2 в §2-блоке ниже, поэтому здесь цель не
	# должна мешать накоплению (иначе проверка покраснела бы по срабатыванию
	# капа, а не по отсутствию хука).
	_force_set(c5, brew_daily, brew_weekly)
	_clear_prog(c5)

	# §1.3: офлайн-реплей Мастерской не двигает НИЧЕГО, включая якорь цепочки.
	var off_ctx := {"source": "offline_workshop", "production": true, "discount": 0.9}
	g._engine.inventory["fire"] = 5
	g._engine.inventory["water"] = 5
	g._engine.ether = 9999
	g._engine.learn_recipe("fire", "water", "steam")
	c5._last_output = "anchor"
	var off_brew := g._engine._commit_brew("fire", "water", off_ctx)
	Selftest.check("§6.4 an offline_workshop brew moves no contract counter",
		not bool(off_brew.get("failed", false)) and c5.progress(String(brew_daily[0]["id"])) == 0
		and c5.progress(String(brew_daily[1]["id"])) == 0
		and c5.progress(String(brew_weekly[1]["id"])) == 0)
	Selftest.check("§1.3 an offline_workshop brew does not touch the chain anchor",
		c5._last_output == "anchor")
	Selftest.check("§1.3 the offline brew still produced its substance (only contracts ignore it)",
		int(g._engine.inventory.get("steam", 0)) >= 1)

	# §6.5: настоящая варка через настоящий путь.
	c5._last_output = ""
	var on_brew := g._engine._commit_brew("fire", "water",
		{"source": "production", "production": true, "discount": 1.0})
	Selftest.check("§6.5 a successful production brew moves the brew contract by exactly 1",
		not bool(on_brew.get("failed", false)) and c5.progress(String(brew_daily[0]["id"])) == 1)
	Selftest.check("§2.1 the same brew updates the chain anchor to its output", c5._last_output == "steam")

	# §6.14: цепочка — накопительная, разрыв не откатывает.
	_clear_prog(c5)
	c5.on_brew("a_out", "fire", "steam", false, "manual")   # вход == _last_output? нет
	c5._last_output = "x"
	c5.on_brew("y", "x", "fire", false, "manual")           # да: a == _last_output
	c5.on_brew("z", "air", "fire", false, "manual")         # нет: разрыв
	c5.on_brew("w", "fire", "z", false, "manual")           # да: b == _last_output
	Selftest.check("§6.14 chain_brew counts only brews whose input is the previous output",
		c5.progress(String(brew_daily[1]["id"])) == 2)
	Selftest.check("§6.14 a broken chain keeps the accumulated progress instead of rolling it back",
		c5.progress(String(brew_daily[1]["id"])) >= 2)

	# §2.1 depth: базовый элемент (0), глубина 1, глубина 2.
	_clear_prog(c5)
	c5.on_brew("fire", "earth", "air", false, "manual")     # depth 0
	c5.on_brew("stone", "earth", "fire", false, "manual")   # depth 1
	Selftest.check("§2.1 depth_brew ignores depth 0 and depth 1",
		c5.progress(String(brew_daily[2]["id"])) == 0)
	c5.on_brew("brick", "clay", "fire", false, "manual")    # clay=earth+water, brick depth 2
	Selftest.check("§2.1 a substance with content depth 2 is counted by depth_brew",
		c5.progress(String(brew_daily[2]["id"])) == 1)
	# main.gd:255 каталог: stone=earth+fire (1), brick=clay+fire (2),
	# clay=earth+water (1). Неизвестный id и циклический обход дают
	# WorkshopBalance.INVALID_DEPTH, базовые — 0; обе ветки сводятся к 0.
	Selftest.check("§1.3 _depth rejects unknown ids and clamps to the workshop's canonical range",
		c5._depth("no_such_item") == 0 and c5._depth("fire") == 0
		and c5._depth("stone") == 1 and c5._depth("brick") == 2)

	# §6.13 variety: уникальные outputs.
	_clear_prog(c5)
	c5.on_brew("q1", "fire", "air", true, "manual")
	c5.on_brew("q1", "fire", "air", true, "manual")
	c5.on_brew("q2", "fire", "water", true, "manual")
	Selftest.check("§6.13 variety counts distinct first-time outputs, not brews",
		c5.progress(String(brew_weekly[0]["id"])) == 2 and c5._contracts_variety.has("q1"))

	# §6.15 experiment: успех и отказ — оба решения; возврат входов — нет.
	_force_set(c5, exp_daily, [])
	_clear_prog(c5)
	var exp_id := String(exp_daily[0]["id"])
	g._engine._experiment_pending_pair = ["fire", "air"]
	g._engine._experiment_failed("fire", "air", "не сочетаются")
	Selftest.check("§6.26 _experiment_failed moves the experiment contract by 1 (a failure is still an experiment)",
		c5.progress(exp_id) == 1)
	g._engine._experiment_pending_pair = ["fire", "air"]
	g._engine._experiment_succeeded("steam", "fire", "air")
	Selftest.check("§6.26 _experiment_succeeded moves the experiment contract by 1",
		c5.progress(exp_id) == 2)
	g._engine._experiment_pending_pair = ["fire", "air"]
	g._engine._finish_experiment_inputs("fire", "air", true)   # только возврат входов
	Selftest.check("§6.26 returning the inputs does not move the experiment contract",
		c5.progress(exp_id) == 2)
	g._engine._experiment_pending_pair.clear()
	c5.on_experiment("fire", "air", false)
	c5.on_experiment("fire", "air", true)
	Selftest.check("§2.1 experiment counts successes and failures alike", c5.progress(exp_id) == 4)
	c5.on_brew("new_thing", "fire", "air", true, "manual")
	Selftest.check("§2.1 a first-time brew moves discover", c5.progress(String(exp_daily[1]["id"])) == 1)
	c5.on_brew("dup_thing", "fire", "air", false, "manual")
	Selftest.check("§2.1 a repeated brew does not move discover",
		c5.progress(String(exp_daily[1]["id"])) == 1)

	# §6.24 sigil_set по крафтам недели + §1.2 set_of_craft.
	var sigil_daily := [_mk(c5, "daily", "sigil_craft", "bronze", 6)]
	var sigil_weekly := [_mk(c5, "weekly", "sigil_set", "bronze", 3)]
	var sigil_craft_id := String(sigil_daily[0]["id"])
	var sigil_set_id := String(sigil_weekly[0]["id"])
	_force_set(c5, sigil_daily, sigil_weekly)
	_clear_prog(c5)
	g._sigil._catalog["card_set_x"] = {"set": "set_x", "card_id": "card_set_x"}
	g._sigil._collection["craft_x1"] = {"card_id": "card_set_x"}
	g._sigil._collection["craft_x2"] = {"card_id": "card_set_x"}
	Selftest.check("§1.2 set_of_craft resolves the set through the saved card and the catalog",
		g._sigil.set_of_craft("craft_x1") == "set_x")
	# Карта уже собрана ДО недели: самого факта в коллекции прогрессу недостаточно.
	Selftest.check("§6.24 cards already collected before the week give sigil_set no progress",
		c5.progress(sigil_set_id) == 0)
	c5.on_sigil_craft("craft_x1", "common", "Test One")
	c5.on_sigil_craft("craft_x2", "common", "Test Two")
	Selftest.check("§6.24 sigil_set counts only crafts made this week",
		c5.progress(sigil_set_id) == 2)
	Selftest.check("§2.1 the same craft also moves the daily sigil_craft counter",
		c5.progress(sigil_craft_id) == 2)
	# Лучший сет, а не сумма: крафт карты из неизвестного сета не складывается.
	c5.on_sigil_craft("craft_y1", "common", "Test Three")   # неизвестный сет → ""
	Selftest.check("§2.2 sigil_set is the best set, not the sum of sets",
		c5.progress(sigil_set_id) == 2)

	# Проводка сигнала (§1.1: доска подписывается, а не вставляется в Аркан).
	Selftest.check("§1.2 the board subscribes to SigilManager.craft_completed exactly once",
		c5._sigil_connection_count() == 1)
	_clear_prog(c5)
	g._sigil.craft_completed.emit("craft_x1", "common", "Test One")
	Selftest.check("§1.2 emitting craft_completed really reaches the board (signal wiring)",
		c5.progress(sigil_set_id) == 1)

	# §1.2 upgrade: оси Родника и покупки Мастерской.
	var up_weekly := [_mk(c5, "weekly", "upgrade", "bronze", 6)]
	var upgrade_id := String(up_weekly[0]["id"])
	_force_set(c5, [], up_weekly)
	_clear_prog(c5)
	c5.on_upgrade("spring", "speed", 1)
	c5.on_upgrade("workshop", "rank", 1)
	c5.on_upgrade("workshop", "autonomy", 1)
	Selftest.check("§1.2 a Spring axis and each Workshop purchase all move the upgrade contract",
		c5.progress(upgrade_id) == 3)
	# Проводка: реальная покупка оси Родника. SpringBalance.SPEED[0] — первый
	# уровень скорости стоит 30 эфира и 12 камня (game/data/spring_balance.gd:6),
	# поэтому камень нужно положить в инвентарь заранее: иначе покупка вернёт
	# {"ok": false, "error": "insufficient stone"} и проверка стала бы зелёной по
	# неверной причине (ok==false и ноль прогресса совпадают).
	var hook_lv_snap: Dictionary = g._engine.spring_levels.duplicate(true)
	var spring_snap := {"levels": hook_lv_snap, "ether": g._engine.ether,
		"inv": g._engine.inventory.duplicate(true),
		"buf": g._engine.spring_buffer.duplicate(true), "xp": g._workshop.xp}
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.ether = 99999
	g._engine.inventory["stone"] = 20
	var spring_buy: Dictionary = g._engine.spring_purchase("speed")
	Selftest.check("§1.2 buying a Spring axis through the real purchase path moves the upgrade contract",
		bool(spring_buy.get("ok", false)) and c5.progress(upgrade_id) == 4)
	g._engine.spring_levels = (spring_snap["levels"] as Dictionary).duplicate(true)
	g._engine.ether = int(spring_snap["ether"])
	g._engine.inventory = spring_snap["inv"]
	g._engine.spring_buffer = spring_snap["buf"]
	g._workshop.xp = int(spring_snap["xp"])

	# §2 прогресс никогда не превышает цель; §4.4 Перегонка.
	var cap_daily := [_mk(c5, "daily", "brew", "bronze", 2)]
	var cap_weekly := [_mk(c5, "weekly", "prestige", "bronze", 1)]
	var brew_id := String(cap_daily[0]["id"])
	var prestige_id := String(cap_weekly[0]["id"])
	_force_set(c5, cap_daily, cap_weekly)
	_clear_prog(c5)
	c5.on_brew("o", "fire", "air", false, "manual")
	c5.on_brew("o", "fire", "air", false, "manual")
	c5.on_brew("o", "fire", "air", false, "manual")
	Selftest.check("§2 contract progress never exceeds its goal",
		c5.progress(brew_id) == 2)
	c5.grant_buff("brew_speed", 7200, 0.25, -1)
	c5._unlocked_decor = ["window_contract"]
	c5._contracts_daily_prog[brew_id] = 2
	c5._contracts_daily_done[brew_id] = true
	var weekly_before := c5.progress(prestige_id)
	c5.on_prestige()
	# Очистку читаем сразу после on_prestige(): сброшенный ключ дня (см. on_prestige)
	# даёт регенерацию полного набора на первом же accessor — progress() в
	# соседней проверке ниже через ensure_period() восстановит _contracts_daily.
	# Если читать поле после неё, увидим уже восстановленный набор, а не факт
	# очистки, поэтому этой проверке быть первой. Текст проверки не меняется.
	Selftest.check("§4.4 on_prestige clears buffs, daily lists and daily progress",
		c5._active_buffs.is_empty() and c5._contracts_daily.is_empty()
		and c5._contracts_daily_prog.is_empty() and c5._contracts_daily_done.is_empty()
		and c5._last_output == "")
	Selftest.check("§4.4 on_prestige moves the prestige counter before it clears anything",
		c5.progress(prestige_id) == weekly_before + 1)
	Selftest.check("§4.4 on_prestige keeps weekly progress and unlocked decor",
		c5.progress(prestige_id) == 1 and c5._unlocked_decor == ["window_contract"])

	# §4.4 + §1.4: после Перегонки доска обязана снова отдавать полный набор —
	# 3 дневных и 2 недельных контракта на ближайшем обращении. Отдельный
	# экземпляр: живой c5 в этом блоке держит фикстуры, а здесь проверка краснеет
	# ровно одним условием — несброшенным ключом дня (_contracts_last_daily),
	# из-за которого ensure_period() считает период неизменным и возвращает
	# очищенный пустой дневной список вплоть до полуночи.
	var regen_probe := Contracts.new(g)
	regen_probe.daily()
	regen_probe.weekly()
	regen_probe.on_prestige()
	Selftest.check("§4.4 after on_prestige the daily set regenerates on next access",
		regen_probe.daily().size() == ContractsBalance.DAILY_SHOWN
		and regen_probe.weekly().size() == ContractsBalance.WEEKLY_SHOWN)

	# восстановление живого состояния (Review Focus 7). Списки оставляем пустыми,
	# а ключи периода — сброшенными: первый же ensure_period() после сюиты
	# восстановит настоящий набор дня из живого g._contracts.
	c5._active_buffs = buffs5_snap
	c5._contracts_daily = []
	c5._contracts_weekly = []
	c5._contracts_last_daily = ""
	c5._contracts_last_weekly = ""
	_clear_prog(c5)
	c5._unlocked_decor = []
	g._sigil._collection = coll_snap
	g._sigil._catalog = cat_snap
	g._engine._rejected_pairs = rejected_snap
	g._engine.inventory = brew_snap["inv"]
	g._engine.known_recipes = brew_snap["known"]
	g._engine.known_recipe_defs = brew_snap["known_defs"]
	g._engine.ether = int(brew_snap["ether"])
	g._engine.attempts = int(brew_snap["attempts"])
	g._engine.successes = int(brew_snap["successes"])
	g._engine._experiment_pending_pair.clear()
	# Инвариант known_recipes.keys() == known_recipe_defs.keys() (core.gd:11,
	# core.gd:520-527): хук _experiment_succeeded вызывает learn_recipe, который
	# пишет пару «air|fire» и в known_recipes, и в known_recipe_defs. Снимок
	# блока обязан возвращать оба словаря: иначе фантомное определение рецепта
	# выживает за пределами блока и краснит эту проверку. Снятие строки
	# восстановления known_recipe_defs ниже делает её красной ровно одним условием.
	Selftest.check("§1.2 the experiment hook leaves no recipe def behind the snapshot",
		g._engine.known_recipes.keys() == g._engine.known_recipe_defs.keys())

	# ---------------- Task 6: выдача награды ----------------
	var c6 := g._contracts
	var claim_snap := {
		"inv": g._engine.inventory.duplicate(true),
		"buffs": c6._active_buffs.duplicate(true),
		"decor": c6._unlocked_decor.duplicate(true),
		"owned": g._home.house_owned.duplicate(true),
		"prog": _snap_progress(g),
	}
	# Каталог Дома, журнал доски и активные баффы чищим НАМЕРЕННО. Если
	# «Витраж гильдии» уже принадлежит игроку, а brew_speed уже активен,
	# проверки №6/№8 были бы зелёными без всякого claim.
	c6._unlocked_decor = []
	c6._active_buffs = {}
	g._home.house_owned["window"] = []
	_set_progress(g, 0, 0, 0, 0, 0, 0)  # множитель ровно 1.0 → числа равны таблице

	# Тест №7: невыполненный контракт.
	var miss_set := [_mk(c6, "daily", "brew", "bronze", 5)]
	var miss_id := String(miss_set[0]["id"])
	_force_set(c6, miss_set, [])
	_clear_prog(c6)
	g._engine.inventory["stone"] = 0
	g._engine.inventory["brick"] = 0
	var got_missing := c6.claim(miss_id)
	Selftest.check("§6.7 an unfinished contract is refused and pays nothing",
		not bool(got_missing["ok"]) and String(got_missing["reason"]) == "incomplete"
		and int(g._engine.inventory.get("stone", 0)) == 0
		and int(g._engine.inventory.get("brick", 0)) == 0
		and c6._active_buffs.is_empty())

	# Тест №6: выполнен → выдача → повторный тап.
	var win_set := [_mk(c6, "daily", "brew", "bronze", 3)]
	var win_id := String(win_set[0]["id"])
	_force_set(c6, win_set, [])
	_clear_prog(c6)
	c6._contracts_daily_prog[win_id] = 3
	g._engine.inventory["stone"] = 0
	g._engine.inventory["brick"] = 0
	var got := c6.claim(win_id)
	Selftest.check("§6.6 a finished claim pays the bronze daily table and closes the contract",
		bool(got["ok"]) and String(got["reason"]) == ""
		and got["materials"] == {"stone": 20, "brick": 10}
		and int(g._engine.inventory["stone"]) == 20
		and int(g._engine.inventory["brick"]) == 10
		and c6.is_done(win_id) and not c6.is_ready(win_id))
	Selftest.check("§3.3 the same claim switches on the contract's buff at the scaled power",
		c6._active_buffs.has("brew_speed") and absf(c6.buff_power("brew_speed") - 0.25) < 0.0001
		and int(got["duration"]) == 7200)
	var again := c6.claim(win_id)
	Selftest.check("§6.6 a second claim of the same id reports claimed and pays nothing further",
		not bool(again["ok"]) and String(again["reason"]) == "claimed"
		and int(g._engine.inventory["stone"]) == 20 and c6._active_buffs.size() == 1)
	c6._active_buffs = {}

	# §3.2: недельная награда берёт недельную таблицу (у дневной bronze кристалла нет).
	var week_set := [_mk(c6, "weekly", "variety", "bronze", 1)]
	var week_id := String(week_set[0]["id"])
	_force_set(c6, [], week_set)
	_clear_prog(c6)
	c6._contracts_weekly_prog[week_id] = 1
	for week_item in ["stone", "brick", "metal", "glass"]:
		g._engine.inventory[week_item] = 0
	var got_week := c6.claim(week_id)
	Selftest.check("§3.2 a weekly claim pays the weekly table, not the daily one",
		bool(got_week["ok"]) and got_week["materials"] == {"stone": 80, "brick": 45, "metal": 20}
		and int(g._engine.inventory["metal"]) == 20)

	# §3.4 / тест №8-логика: недельный gold отдаёт витраж в Дом и в журнал доски.
	var decor_set := [_mk(c6, "weekly", "prestige", "gold", 1)]
	var guild_cid := String(decor_set[0]["id"])
	decor_set[0]["decor"] = "window_guild"
	decor_set[0]["buff"] = "spring_yield"
	_force_set(c6, [], decor_set)
	_clear_prog(c6)
	c6._contracts_weekly_prog[guild_cid] = 1
	var got_decor := c6.claim(guild_cid)
	Selftest.check("§3.4 a weekly gold claim hands the vitrage to the House, not only to the board log",
		bool(got_decor["ok"]) and String(got_decor["decor"]) == "window_guild"
		and not bool(got_decor["missing_decor"])
		and g._home._decor_owned("window", "window_guild")
		and c6._unlocked_decor == ["window_guild"]
		and int(got_decor["materials"]["crystal"]) == 18)
	# Тот же id из второй бумажки не должен удваивать журнал.
	var decor2_set := [_mk(c6, "weekly", "sigil_set", "gold", 1)]
	var decor2_id := String(decor2_set[0]["id"])
	decor2_set[0]["decor"] = "window_guild"
	_force_set(c6, [], [decor2_set[0]])
	_clear_prog(c6)
	c6._contracts_weekly_prog[decor2_id] = 1
	var got_decor2 := c6.claim(decor2_id)
	Selftest.check("§3.4 a repeat decor id is logged once and stays owned in the House",
		bool(got_decor2["ok"]) and c6._unlocked_decor == ["window_guild"]
		and g._home._decor_owned("window", "window_guild"))

	# Обратная сторона: у не-gold декора нет, и флаг missing не должен зажечься
	# от пустой строки (decor_exists("") по Task 3 возвращает false).
	var plain_set := [_mk(c6, "daily", "discover", "silver", 1)]
	var plain_id := String(plain_set[0]["id"])
	_force_set(c6, plain_set, [])
	_clear_prog(c6)
	c6._contracts_daily_prog[plain_id] = 1
	var got_plain := c6.claim(plain_id)
	Selftest.check("§3.4 a contract without a decor reward reports an empty decor and no missing flag",
		bool(got_plain["ok"]) and String(got_plain["decor"]) == ""
		and not bool(got_plain["missing_decor"]))

	# Тест №22: id декора отсутствует в каталоге Дома.
	var ghost_set := [_mk(c6, "weekly", "upgrade", "gold", 1)]
	var ghost_id := String(ghost_set[0]["id"])
	ghost_set[0]["decor"] = "window_does_not_exist"
	ghost_set[0]["buff"] = "brew_speed"
	_force_set(c6, [], ghost_set)
	_clear_prog(c6)
	c6._contracts_weekly_prog[ghost_id] = 1
	for week_item in ["stone", "brick", "metal", "glass", "crystal"]:
		g._engine.inventory[week_item] = 0
	c6._active_buffs = {}
	var got_ghost := c6.claim(ghost_id)
	Selftest.check("§6.22 a decor id missing from the House catalog still pays materials and the buff",
		bool(got_ghost["ok"]) and bool(got_ghost["missing_decor"]) and c6.is_done(ghost_id)
		and int(got_ghost["materials"]["crystal"]) == 18
		and int(g._engine.inventory["crystal"]) == 18
		and c6._active_buffs.has("brew_speed"))
	Selftest.check("§4.4 the missing decor id is not written into the House ownership list",
		not g._home._decor_owned("window", "window_does_not_exist")
		and not c6._unlocked_decor.has("window_does_not_exist"))

	# Тест №21: потолок стека.
	var cap_set := [_mk(c6, "daily", "brew", "bronze", 1)]
	var cap_id := String(cap_set[0]["id"])
	_force_set(c6, cap_set, [])
	_clear_prog(c6)
	c6._contracts_daily_prog[cap_id] = 1
	g._engine.inventory["stone"] = Game.CRAFT_INVENTORY_STACK_CAP
	g._engine.inventory["brick"] = Game.CRAFT_INVENTORY_STACK_CAP - 5
	var got_cap := c6.claim(cap_id)
	Selftest.check("§6.21 a reward against the stack cap is paid partially and reports the real delta",
		bool(got_cap["ok"]) and bool(got_cap["truncated"])
		and got_cap["materials"] == {"brick": 5}
		and not (got_cap["materials"] as Dictionary).has("stone")
		and int(g._engine.inventory["stone"]) == Game.CRAFT_INVENTORY_STACK_CAP
		and int(g._engine.inventory["brick"]) == Game.CRAFT_INVENTORY_STACK_CAP)

	# §3.1: выдача масштабируется множителем, а не берётся из таблицы сырой.
	_set_progress(g, ContractsBalance.RANK_MAX, ContractsBalance.AUTONOMY_MAX,
		int(ContractsBalance.SPRING_MAX["speed"]), int(ContractsBalance.SPRING_MAX["volume"]),
		int(ContractsBalance.SPRING_MAX["sources"]), int(ContractsBalance.SPRING_MAX["offline"]))
	var max_set := [_mk(c6, "daily", "brew", "bronze", 1)]
	var max_id := String(max_set[0]["id"])
	_force_set(c6, max_set, [])
	_clear_prog(c6)
	c6._contracts_daily_prog[max_id] = 1
	g._engine.inventory["stone"] = 0
	g._engine.inventory["brick"] = 0
	var got_max := c6.claim(max_id)
	Selftest.check("§3.1 the claim pays the multiplied amounts (bronze daily at x2.05 is 41 stone and 21 brick)",
		got_max["materials"] == {"stone": 41, "brick": 21}
		and int(g._engine.inventory["stone"]) == 41)

	# Тест №20: вчерашний выполненный контракт сгорает вместе со списком.
	# Отдельный экземпляр: живой g._contracts не должен терять ключи периода.
	var burn := Contracts.new(g)
	var past_dt := Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_system()) - 2 * 86400)
	var past_key := Contracts.day_key_from(past_dt)
	var burn_c := _mk(burn, "daily", "brew", "bronze", 2)
	burn_c["id"] = "daily:brew:bronze:" + past_key
	var burn_id := String(burn_c["id"])
	burn._contracts_daily = [burn_c]
	burn._contracts_last_daily = past_key
	burn._contracts_daily_prog[burn_id] = 2
	g._engine.inventory["stone"] = 0
	var stone_before := int(g._engine.inventory.get("stone", 0))
	var got_burn := burn.claim(burn_id)
	Selftest.check("§6.20 a contract finished yesterday pays nothing once the day rolled over",
		past_key != Contracts.day_key_from(burn._dt({}))
		and not bool(got_burn["ok"]) and String(got_burn["reason"]) == "unknown"
		and int(g._engine.inventory.get("stone", 0)) == stone_before)

	# Выдуманный id — тот же ответ, что у сгоревшего.
	# stone == 0: тест §6.20 выше установил inventory["stone"] = 0, и burn.claim()
	# вернул "unknown" без изменения инвентаря.
	var got_junk := c6.claim("daily:brew:bronze:2020-01-01")
	Selftest.check("§4.4 an id that was never generated reports unknown and pays nothing",
		not bool(got_junk["ok"]) and String(got_junk["reason"]) == "unknown"
		and int(g._engine.inventory.get("stone", 0)) == 0)

	# восстановление живого состояния (Review Focus 7)
	c6._active_buffs = claim_snap["buffs"]
	c6._unlocked_decor = claim_snap["decor"]
	g._home.house_owned = claim_snap["owned"]
	g._engine.inventory = claim_snap["inv"]
	_clear_prog(c6)
	c6._contracts_daily = []
	c6._contracts_weekly = []
	c6._contracts_last_daily = ""
	c6._contracts_last_weekly = ""
	_restore_progress(g, claim_snap["prog"])

	# §5.2–5.5: ассеты доски стоят до блока сейва — читают только файлы.
	_contract_asset_checks()
	# §5.3: карточка навешивает ноды в дерево и крутит улучшения игрока, всё возвращает назад.
	await _contract_card_checks(g)
	# §5.2/§5.4: доска открывается в дереве, кликает штампом и выдаёт награды; инвентарь,
	# Дом и состояние доски возвращаются в конце своего блока.
	await _contract_board_checks(g)
	# Блок сейва идёт последним и отдельной функции: он трогает пути сейва,
	# пишет файлы и перезагружает мир.
	_contracts_durability_checks(g)

static func _contract_board_checks(g: Game) -> void:
	# §5.2/§5.4: полная проверка доски — слои, карточки, записки, попап, закрытие.
	var c := g._contracts
	var saved := _cb_snapshot(c)
	var win_before: Vector2i = g.get_window().size
	g.get_window().size = Vector2i(540, 960)
	await g.get_tree().process_frame

	# --- 1. Открытие и базовая структура ---
	ContractBoard.open(g)
	await g.get_tree().process_frame
	var board: Control = g.get_node_or_null("ContractBoard")
	Selftest.check("§5.2 the board opens and appears in the tree",
		board != null and board.is_inside_tree())
	if board == null:
		g.get_window().size = win_before
		_cb_restore(c, saved)
		return

	# 2. Фон — тайл досок, не кодовый прямоугольник.
	var bg: TextureRect = board.get_node_or_null("Planks") as TextureRect
	Selftest.check("§5.2 the board background is a tiled plank texture, not a flat rect",
		bg != null and bg.texture != null
		and str(bg.texture.resource_path).contains("board_planks")
		and bg.stretch_mode == TextureRect.STRETCH_TILE)

	# 3. Четыре бруса рамы из PNG.
	var rail_t: TextureRect = board.get_node_or_null("RailTop") as TextureRect
	var rail_b: TextureRect = board.get_node_or_null("RailBottom") as TextureRect
	var rail_l: TextureRect = board.get_node_or_null("RailLeft") as TextureRect
	var rail_r: TextureRect = board.get_node_or_null("RailRight") as TextureRect
	Selftest.check("§5.2 the board has four frame rails from asset PNGs",
		rail_t != null and rail_b != null and rail_l != null and rail_r != null
		and rail_t.texture != null and str(rail_t.texture.resource_path).contains("frame_h")
		and rail_l.texture != null and str(rail_l.texture.resource_path).contains("frame_v"))

	# 4. Четыре кованых уголка из PNG.
	var c0: TextureRect = board.get_node_or_null("Corner0") as TextureRect
	var c1: TextureRect = board.get_node_or_null("Corner1") as TextureRect
	var c2: TextureRect = board.get_node_or_null("Corner2") as TextureRect
	var c3: TextureRect = board.get_node_or_null("Corner3") as TextureRect
	Selftest.check("§5.2 the board has four corner irons from asset PNGs",
		c0 != null and c1 != null and c2 != null and c3 != null
		and c0.texture != null and str(c0.texture.resource_path).contains("corner_iron"))

	# 5. Уголки зеркалятся: волокна сходятся на стыках.
	Selftest.check("§5.2 the four corners mirror to meet grain at each joint",
		c0 != null and c1 != null and c2 != null and c3 != null
		and not c0.flip_h and not c0.flip_v
		and c1.flip_h and not c1.flip_v
		and not c2.flip_h and c2.flip_v
		and c3.flip_h and c3.flip_v)

	# 6. Две полки из PNG.
	var sd: TextureRect = board.get_node_or_null("ShelfDaily") as TextureRect
	var sw: TextureRect = board.get_node_or_null("ShelfWeekly") as TextureRect
	Selftest.check("§5.2 the board has two shelf bars from asset PNGs",
		sd != null and sw != null and sd.texture != null and sw.texture != null
		and str(sd.texture.resource_path).contains("shelf_bar"))

	# 7. Вывеска на двух верёвках по центру.
	var sign: TextureRect = board.get_node_or_null("Sign") as TextureRect
	var sign_word: Label = null
	if sign != null:
		sign_word = sign.get_node_or_null("SignWord") as Label
	Selftest.check("§5.2 the sign hangs from ropes with the board title",
		sign != null and sign.texture != null
		and str(sign.texture.resource_path).contains("sign_hang")
		and sign_word != null and sign_word.text == ContractBoard.BOARD_TITLE)

	# 8. Кольцо закрытия — кованое, из PNG.
	var ring: TextureButton = board.get_node_or_null("Ring") as TextureButton
	Selftest.check("§5.2 the close ring is a forged iron texture button",
		ring != null and ring.texture_normal != null
		and str(ring.texture_normal.resource_path).contains("ring_pull"))

	# 9. Пять карточек: 3 daily + 2 weekly.
	var dr: Control = board.get_node_or_null("DailyRow") as Control
	var wr: Control = board.get_node_or_null("WeeklyRow") as Control
	var daily_card_count := dr.get_child_count() if dr != null else 0
	var weekly_card_count := wr.get_child_count() if wr != null else 0
	Selftest.check("§5.2 the board creates five cards (3 daily + 2 weekly)",
		daily_card_count == ContractsBalance.DAILY_SHOWN
		and weekly_card_count == ContractsBalance.WEEKLY_SHOWN)

	# 10. Ряды — обычные Control, не контейнеры.
	Selftest.check("§5.2 daily and weekly rows are plain Controls, not containers",
		dr != null and wr != null and dr.get_class() == "Control" and wr.get_class() == "Control")

	# 11. Полоса записок существует и пуста без баффов.
	var notes: Control = board.get_node_or_null("Notes") as Control
	var saved_buffs := c._active_buffs.duplicate(true)
	c._active_buffs.clear()
	board.refresh()
	await g.get_tree().process_frame
	Selftest.check("§5.4 the notes band exists and stays empty when no buffs are active",
		notes != null and notes.get_class() == "Control" and notes.get_child_count() == 0)

	# 12. Один бафф — одна записка.
	c.grant_buff("brew_speed", 7200, 0.25, int(Time.get_unix_time_from_system()))
	board.refresh()
	await g.get_tree().process_frame
	Selftest.check("§5.4 one active buff produces exactly one note in the band",
		notes.get_child_count() == 1)

	# 13. Записка — бумага из PNG правильного размера.
	var note := notes.get_child(0) if notes.get_child_count() > 0 else null
	var note_ok := note != null and note is TextureButton
	if note_ok:
		note_ok = (note as TextureButton).texture_normal != null and str((note as TextureButton).texture_normal.resource_path).contains("paper_note")
		note_ok = note_ok and note.size == ContractBoard.NOTE_SIZE
	Selftest.check("§5.4 a note is a paper_note texture at the declared NOTE_SIZE", note_ok)

	# 14. На записке — время Ч:ММ.
	var time_lbl: Label = null
	if note != null:
		for ch in note.get_children():
			if ch is Label:
				time_lbl = ch as Label
				break
	var time_text := time_lbl.text if time_lbl != null else ""
	Selftest.check("§5.4 the note shows remaining time in H:MM format",
		time_lbl != null and time_text.length() >= 3
		and time_text.contains(":"))

	# 15. Гвоздь поверх записки — латунный, на верхнем крае.
	var pin: TextureRect = null
	if note != null:
		pin = note.get_node_or_null("Pin") as TextureRect
	var pin_ok := pin != null and pin.texture != null
	if pin_ok:
		pin_ok = str(pin.texture.resource_path).contains("nail_brass")
	Selftest.check("§5.4 the note has a brass nail pin from an asset PNG", pin_ok)

	# 16. Клик по записке показывает текст эффекта, повторный клик — обратно время.
	if note != null:
		(note as TextureButton).pressed.emit()
	var effect_shown := false
	if time_lbl != null:
		effect_shown = time_lbl.text != time_text and time_lbl.text.length() > len(time_text)
	Selftest.check("§5.4 tapping a note reveals the buff effect text", effect_shown)
	if note != null:
		(note as TextureButton).pressed.emit()
	var time_back := false
	if time_lbl != null:
		time_back = time_lbl.text == time_text
	Selftest.check("§5.4 tapping the note again restores the time display", time_back)

	# --- Попап ---
	c._active_buffs = saved_buffs
	var pop_daily := [_mk(c, "daily", "brew", "bronze", 15)]
	_force_set(c, pop_daily, [])
	_clear_prog(c)
	var pop_id := String(pop_daily[0]["id"])
	c._set_progress(pop_id, int(pop_daily[0]["goal"]))
	c._done_dict("daily")[pop_id] = true

	# 17. Все пять карточек заполняются контрактами при refresh.
	_force_set(c, [
		_mk(c, "daily", "brew", "bronze", 15),
		_mk(c, "daily", "experiment", "silver", 2),
		_mk(c, "daily", "depth_brew", "gold", 3),
	], [
		_mk(c, "weekly", "sigil_set", "gold", 4),
		_mk(c, "weekly", "variety", "bronze", 8),
	])
	board.refresh()
	await g.get_tree().process_frame
	var all_vis := true
	var total_cards := 0
	for ch in dr.get_children():
		total_cards += 1
		if not (ch as Control).visible:
			all_vis = false
	for ch in wr.get_children():
		total_cards += 1
		if not (ch as Control).visible:
			all_vis = false
	Selftest.check("§5.2 all five cards are visible when five contracts are present",
		all_vis and total_cards == 5)

	# 18. Дневные контракты — в дневном ряду, недельные — в недельном.
	var daily_count := 0
	var weekly_count := 0
	for ch in dr.get_children():
		if (ch as Control).visible:
			daily_count += 1
	for ch in wr.get_children():
		if (ch as Control).visible:
			weekly_count += 1
	Selftest.check("§5.2 daily cards sit in the daily row and weekly cards in the weekly row",
		daily_count == ContractsBalance.DAILY_SHOWN
		and weekly_count == ContractsBalance.WEEKLY_SHOWN)

	# 19. Попап награды: проверяем, что _show_reward создаёт попап с правильными элементами.
	var fake_reward := {
		"ok": true, "reason": "",
		"materials": {"stone": 20, "brick": 10},
		"truncated": false,
		"buff": "brew_speed", "duration": 7200, "power": 0.25,
		"decor": "", "missing_decor": false,
	}
	board._show_reward(fake_reward)
	var popup: Control = board.get_node_or_null("RewardPopup")
	Selftest.check("§5.4 _show_reward creates a reward popup",
		popup != null and popup.is_inside_tree())
	if popup != null:
		var pop_title: Label = popup.get_node_or_null("Title") as Label
		var pop_ok_btn: Button = popup.get_node_or_null("Ok") as Button
		Selftest.check("§5.4 the popup has the reward title and an OK button",
			pop_title != null and pop_title.text == ContractBoard.POPUP_TITLE
			and pop_ok_btn != null)
		if pop_ok_btn != null:
			pop_ok_btn.pressed.emit()
		await g.get_tree().process_frame
		Selftest.check("§5.4 pressing OK closes the reward popup",
			board.get_node_or_null("RewardPopup") == null)

	# --- Закрытие и перекрёстное закрытие ---
	# 20 (bonus): повторный open не создаёт вторую доску.
	ContractBoard.open(g)
	await g.get_tree().process_frame
	var board2: Node = g.get_node_or_null("ContractBoard")
	Selftest.check("§5.2 opening the board twice does not create a second board",
		board2 == board)

	# close_any закрывает доску.
	ContractBoard.close_any(g)
	await g.get_tree().process_frame
	Selftest.check("§5.2 close_any finds and closes the board",
		not is_instance_valid(board) or not board.is_inside_tree())

	# --- Откат состояния ---
	g.get_window().size = win_before
	_cb_restore(c, saved)

static func _contracts_durability_checks(g: Game) -> void:
	var c := g._contracts
	var saved_paths: Array = [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]
	var saved_frozen := g._saves._save_frozen
	var saved_last_ts := g._last_ts
	var saved_state := _cb_snapshot(c)
	var saved_crafts: Array = g._sigil._daily_crafts.duplicate(true)
	var saved_spirit := g._spirit._spirit_name
	var saved_mastery := g._engine.mastery_rank
	var saved_status := g._engine.status_text
	for path in saved_paths:
		if FileAccess.file_exists(String(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(path)))
	g.SAVE_PATH = "user://alchemy_st_contracts_dur.json"
	g.TEMP_PATH = "user://alchemy_st_contracts_dur.tmp"
	g.BACKUP_PATH = "user://alchemy_st_contracts_dur.bak"
	g._saves._save_frozen = false
	# Два поля, по которым проверка №9 сверяет «остальной сейв прочитался». Оба
	# несутся в файле: spirit_name — строка, mastery_rank — число через
	# int(data.get(...)) (saves.gd:487), то есть float-безопасно.
	g._spirit._spirit_name = "Проверка"
	g._engine.mastery_rank = 2
	var baseline_written := g._saves._save_game()
	var baseline_data := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("contracts durability baseline save written",
		baseline_written and not baseline_data.is_empty())

	var now_u := int(Time.get_unix_time_from_system())
	var day_key := Contracts.day_key_from(c._dt({}))
	var week_key := Contracts.week_key_from(c._dt({}))
	var d_brew := _mk_legal(c, "daily", "brew", "bronze")
	var d_disc := _mk_legal(c, "daily", "discover", "silver")
	var d_gold := _mk_legal(c, "daily", "sigil_craft", "gold")
	var w_pre := _mk_legal(c, "weekly", "prestige", "gold")
	var w_up := _mk_legal(c, "weekly", "upgrade", "bronze")
	var daily_set: Array = [d_brew, d_disc, d_gold]
	var weekly_set: Array = [w_pre, w_up]
	var id_brew := String(d_brew["id"])
	var id_disc := String(d_disc["id"])
	var id_gold := String(d_gold["id"])
	var id_pre := String(w_pre["id"])
	var id_up := String(w_up["id"])
	var gold_goal := int((ContractsBalance.DAILY_GOALS["sigil_craft"] as Array)[2])

	# ---- 1. форма блока ----
	var shape := c.save_block()
	var names: Array = shape.keys()
	names.sort()
	var expect: Array = ["buffs", "daily", "daily_done", "daily_prog", "decor",
		"last_daily", "last_output", "last_weekly", "set_week", "variety",
		"version", "weekly", "weekly_done", "weekly_prog"]
	expect.sort()
	Selftest.check("§4.2 save_block carries exactly the fourteen §4.1 state keys",
		names == expect)

	# ---- 2. round-trip (§6.16): rich-состояние → файл → память начисто → загрузка ----
	_cb_fill(c, daily_set, weekly_set, now_u)
	g._home._own_item("window", "window_seal")
	g._sigil._daily_crafts = []
	g._saves._save_game()
	# Память вычищена НАМЕРЕННО: без этого no-op-загрузка оставила бы фикстуру
	# на месте и вся группа была бы зелёной без всякого load_block.
	_cb_wipe(c)
	g._home.house_owned["window"] = []
	g._saves._load_game()
	Selftest.check("§6.16 a restart keeps the period keys, the progress and the claim log",
		c._contracts_last_daily == day_key and c._contracts_last_weekly == week_key
		and int(c._contracts_daily_prog.get(id_brew, -1)) == 4 and c.progress(id_brew) == 4
		and bool(c._contracts_weekly_done.get(id_pre, false)) and c.is_done(id_pre)
		and int(c._contracts_weekly_prog.get(id_up, -1)) == 1)

	# Именно эта проверка краснеет, если валидаторы потребуют TYPE_INT: до и после
	# записи until — int, а после разбора файла — float того же значения.
	var buff_back := c._active_buffs.get("spring_yield", {}) as Dictionary
	Selftest.check("§6.16 a restart keeps the active buff with its exact expiry and power",
		c._active_buffs.size() == 1 and int(buff_back.get("until", 0)) == now_u + 1800
		and float(buff_back.get("power", 0.0)) == 2.0
		and c.buff_power("spring_yield", now_u + 600) == 2.0)
	Selftest.check("§6.16 a restart keeps the decor journal together with House ownership",
		c._unlocked_decor == ["window_seal"] and g._home._decor_owned("window", "window_seal"))

	# Разбор вместо == на всём массиве: goal после файла — float, и сверка
	# контейнеров здесь зависела бы от типов, которых в сейве больше нет.
	var ids: Array = []
	for item in c._contracts_daily:
		ids.append(String((item as Dictionary)["id"]))
	Selftest.check("§6.16 the saved lists survive verbatim instead of a re-roll at boot",
		ids == [id_brew, id_disc, id_gold]
		and int(c._contracts_daily[2]["goal"]) == gold_goal
		and String(c._contracts_daily[2]["buff"]) == "brew_speed"
		and c.progress(id_gold) == 2 and c._contracts_weekly.size() == 2)
	Selftest.check("§6.16 the weekly variety and set counters survive the restart",
		c._contracts_variety == {"steam": true, "glass": true}
		and c._contracts_set_week.size() == 1 and int(c._contracts_set_week.get("fire", -1)) == 4)
	Selftest.check("§6.16 the chain_brew anchor survives the restart", c._last_output == "steam")

	# ---- 3. fail-closed по версии (§4.3): очистку делает сам load_block ----
	var blk99 := c.save_block()
	blk99["version"] = 99
	_cb_put_block(g, blk99)
	g._saves._load_game()
	Selftest.check("§4.3 a contracts version above CONTRACTS_SAVE_VERSION drops only the contracts block",
		c._contracts_daily.is_empty() and c._contracts_last_daily == ""
		and c._contracts_daily_prog.is_empty() and c._contracts_weekly_done.is_empty()
		and c._contracts_variety.is_empty() and c._active_buffs.is_empty()
		and c._unlocked_decor.is_empty() and c._last_output == ""
		and g._spirit._spirit_name == "Проверка" and int(g._engine.mastery_rank) == 2)
	var blk_str := c.save_block()
	blk_str["version"] = "1"
	_cb_fill(c, daily_set, weekly_set, now_u)
	g._saves._save_game()
	_cb_put_block(g, blk_str)
	g._saves._load_game()
	Selftest.check("§4.3 a contracts version that is not a number drops the block the same way",
		c._contracts_last_daily == "" and c._contracts_daily.is_empty()
		and c._active_buffs.is_empty() and c._unlocked_decor.is_empty())
	_cb_fill(c, daily_set, weekly_set, now_u)
	g._saves._save_game()
	_cb_put_block(g, null)
	g._saves._load_game()
	Selftest.check("§4.3 a save without the contracts key boots today's fresh generation",
		c._contracts_last_daily == "" and c._contracts_daily.is_empty()
		and c._unlocked_decor.is_empty() and c._last_output == ""
		and c.daily().size() == ContractsBalance.DAILY_SHOWN
		and c.weekly().size() == ContractsBalance.WEEKLY_SHOWN
		and c._contracts_last_daily == day_key)

	# ---- 4. фильтрация по осям и по ключам (§4.4) ----
	# Битый только goal у одного дневного контракта: роняет дневную ось целиком,
	# недельная с её журналом обязана пережить загрузку.
	var d_bad := _mk_legal(c, "daily", "brew", "silver")
	d_bad["goal"] = int(d_bad["goal"]) + 1
	var bad_id := String(d_bad["id"])
	_cb_wipe(c)
	_force_set(c, [d_bad, d_disc, d_gold], weekly_set)
	c._contracts_daily_prog[bad_id] = 2
	c._contracts_weekly_done[id_pre] = true
	c._contracts_weekly_prog[id_up] = 1
	g._saves._save_game()
	_cb_wipe(c)
	g._saves._load_game()
	Selftest.check("§4.4 a structurally broken daily list resets only the daily axis",
		c._contracts_daily.is_empty() and c._contracts_last_daily == ""
		and c._contracts_daily_prog.is_empty()
		and c._contracts_weekly.size() == 2 and c._contracts_weekly_done.has(id_pre)
		and int(c._contracts_weekly_prog.get(id_up, -1)) == 1)
	Selftest.check("§4.4 after the dropped axis the board regenerates today, not an empty slate",
		c.daily().size() == ContractsBalance.DAILY_SHOWN
		and c._contracts_last_daily == day_key and c._contracts_daily_prog.is_empty())

	# Журнал и прогресс по id, которого нет в сохранённом списке: живой остаётся,
	# фантомный выбрасывается.
	var phantom := _mk_legal(c, "daily", "depth_brew", "gold")
	var phantom_id := String(phantom["id"])
	_cb_fill(c, daily_set, weekly_set, now_u)
	c._contracts_daily_done[phantom_id] = true
	c._contracts_daily_prog[phantom_id] = 8
	g._saves._save_game()
	_cb_wipe(c)
	g._saves._load_game()
	Selftest.check("§4.4 a log or progress entry for an id outside the saved lists is dropped",
		c._contracts_daily_prog.size() == 2 and int(c._contracts_daily_prog.get(id_brew, -1)) == 4
		and not c._contracts_daily_prog.has(phantom_id)
		and c._contracts_daily_done.size() == 0 and not c._contracts_daily_done.has(phantom_id))

	# Истекший в оффлайне бафф и id вне BUFF_IDS не грузятся (§4.4).
	_cb_wipe(c)
	_force_set(c, daily_set, weekly_set)
	c._active_buffs = {
		"brew_speed": {"until": now_u - 10, "power": 0.5},
		"not_a_buff": {"until": now_u + 3600, "power": 1.0},
		"spring_yield": {"until": now_u + 1800, "power": 2.0},
	}
	g._saves._save_game()
	_cb_wipe(c)
	g._saves._load_game()
	var kept := c._active_buffs.get("spring_yield", {}) as Dictionary
	Selftest.check("§4.4 an expired buff and a buff id outside BUFF_IDS are dropped at load",
		c._active_buffs.size() == 1 and not c._active_buffs.has("brew_speed")
		and not c._active_buffs.has("not_a_buff")
		and int(kept.get("until", 0)) == now_u + 1800 and float(kept.get("power", 0.0)) == 2.0)

	# Декор вне каталога и якорь, который не вещество, не доходят до состояния.
	_cb_wipe(c)
	_force_set(c, daily_set, weekly_set)
	c._unlocked_decor = ["window_seal", "window_phantom"]
	c._last_output = "not_a_substance"
	g._saves._save_game()
	_cb_wipe(c)
	g._saves._load_game()
	Selftest.check("§4.4 a decor id outside the catalog and a non-substance anchor are dropped at load",
		c._unlocked_decor == ["window_seal"] and c._last_output == "")

	# ---- 5. новая игра (§4.4, тест №19): полный сброс через настоящий вход ----
	_cb_fill(c, daily_set, weekly_set, now_u)
	var reset_ok := g._init_new_game()
	Selftest.check("§6.19 a real new game clears every contracts field, weekly and decor included",
		reset_ok and c._contracts_daily.is_empty() and c._contracts_weekly.is_empty()
		and c._contracts_last_daily == "" and c._contracts_last_weekly == ""
		and c._contracts_daily_prog.is_empty() and c._contracts_weekly_prog.is_empty()
		and c._contracts_daily_done.is_empty() and c._contracts_weekly_done.is_empty()
		and c._contracts_variety.is_empty() and c._contracts_set_week.is_empty()
		and c._active_buffs.is_empty() and c._unlocked_decor.is_empty()
		and c._last_output == "")

	# ---- откат: мир возвращается настоящим _load_game() из baseline-сейва ----
	var restore_world := baseline_data.duplicate(true)
	restore_world.erase("contracts")
	_cb_put_block_restore(g, restore_world)
	g._saves._load_game()
	_cb_restore(c, saved_state)
	for p in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(String(p)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(p)))
	for path in saved_paths:
		var leftover := String(path)
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))
	g.SAVE_PATH = String(saved_paths[0])
	g.TEMP_PATH = String(saved_paths[1])
	g.BACKUP_PATH = String(saved_paths[2])
	g._saves._save_frozen = saved_frozen
	g._last_ts = saved_last_ts
	g._sigil._daily_crafts = saved_crafts
	g._spirit._spirit_name = saved_spirit
	g._engine.mastery_rank = saved_mastery
	g._engine.status_text = saved_status
	g._engine._refresh()
	# Сверка с самим снимком сейва, а не с памятью блока.
	var base_inventory: Dictionary = baseline_data.get("inventory", {})
	var restored_inventory_ok := true
	for raw_key in base_inventory:
		if int(g._engine.inventory.get(String(raw_key), -1)) != int(base_inventory[raw_key]):
			restored_inventory_ok = false
	Selftest.check("contracts durability fixture restores world and files",
		g._spirit._spirit_name == saved_spirit and int(g._engine.mastery_rank) == saved_mastery
		and restored_inventory_ok and g.SAVE_PATH == String(saved_paths[0])
		and not FileAccess.file_exists(g.SAVE_PATH)
		and not FileAccess.file_exists("user://alchemy_st_contracts_dur.json")
		and c._unlocked_decor == (saved_state["decor"] as Array)
		and c._active_buffs == (saved_state["buffs"] as Dictionary))

# ---------- §5.2–5.5: хелперы и проверки ассетов ----------

static func _ca_img(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var t := load(path) as Texture2D
	if t == null:
		return null
	return t.get_image()


static func _ca_delta(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)


static func _ca_luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


# Внутренний «шум» тайла по оси axis: средняя дельта между соседними пикселями.
static func _ca_inner(img: Image, axis: String) -> float:
	var acc := 0.0
	var n := 0
	if axis == "x":
		for y in range(2, img.get_height() - 2, 2):
			for x in range(2, img.get_width() - 3, 3):
				acc += _ca_delta(img.get_pixel(x, y), img.get_pixel(x + 1, y))
				n += 1
	else:
		for x in range(2, img.get_width() - 2, 2):
			for y in range(2, img.get_height() - 3, 3):
				acc += _ca_delta(img.get_pixel(x, y), img.get_pixel(x, y + 1))
				n += 1
	return acc / float(maxi(n, 1))


# Дельта между последним и первым рядом по оси axis — это шов тайла.
static func _ca_seam(img: Image, axis: String) -> float:
	var acc := 0.0
	var n := 0
	if axis == "x":
		for y in range(0, img.get_height(), 2):
			acc += _ca_delta(img.get_pixel(img.get_width() - 1, y), img.get_pixel(0, y))
			n += 1
	else:
		for x in range(0, img.get_width(), 2):
			acc += _ca_delta(img.get_pixel(x, img.get_height() - 1), img.get_pixel(x, 0))
			n += 1
	return acc / float(maxi(n, 1))


# Средняя дельта двух картинок по непрозрачным пикселям.
static func _ca_mean_diff(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 0.0
	var acc := 0.0
	var n := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if pa.a < 0.05 and pb.a < 0.05:
				continue
			acc += _ca_delta(pa, pb)
			n += 1
	return acc / float(maxi(n, 1))


static func _contract_asset_checks() -> void:
	# Контракт имён и размеров, который читают экраны Task 9 и Task 10.
	var sizes := {
		"board_planks.png": Vector2i(256, 256),
		"frame_h.png": Vector2i(256, 40),
		"frame_v.png": Vector2i(40, 256),
		"corner_iron.png": Vector2i(96, 96),
		"shelf_bar.png": Vector2i(256, 28),
		"sign_hang.png": Vector2i(600, 168),
		"paper_daily.png": Vector2i(280, 392),
		"paper_weekly.png": Vector2i(368, 488),
		"paper_note.png": Vector2i(264, 176),
		"nail_brass.png": Vector2i(64, 64),
		"seal_bronze.png": Vector2i(104, 104),
		"seal_silver.png": Vector2i(104, 104),
		"seal_gold.png": Vector2i(104, 104),
		"stamp_frame.png": Vector2i(264, 112),
		"ring_pull.png": Vector2i(88, 88),
	}
	var missing := []
	var wrong := []
	var sidecars := []
	for f in sizes:
		var img := _ca_img(CA_DIR + String(f))
		if img == null:
			missing.append(String(f))
		elif img.get_size() != sizes[f]:
			wrong.append("%s=%s" % [String(f), str(img.get_size())])
		if not FileAccess.file_exists(CA_DIR + String(f) + ".import"):
			sidecars.append(String(f))
	Selftest.check("§5.5 every board asset is exported at its declared pixel size",
		missing.is_empty() and wrong.is_empty())
	# Без `.import` свежий worktree физически не видит текстуру: `--import` обязан
	# быть прогнан, а его результат — закоммичен.
	Selftest.check("§5.5 every board asset ships its .import sidecar", sidecars.is_empty())

	# §5.2.1: тайл бесшовный по обеим осям, иначе на доске видна сетка 256.
	var planks := _ca_img(CA_DIR + "board_planks.png")
	var seam_ok := planks != null
	if planks != null:
		for ax in ["x", "y"]:
			seam_ok = seam_ok and (
				_ca_seam(planks, String(ax)) <= _ca_inner(planks, String(ax)) * 1.6 + 0.02)
	Selftest.check("§5.2 the plank tile is seamless on both tiling axes", seam_ok)

	# §5.2.2: каждая рейка тайлится только по своей оси.
	var fh := _ca_img(CA_DIR + "frame_h.png")
	var fv := _ca_img(CA_DIR + "frame_v.png")
	Selftest.check("§5.2 each frame rail is seamless along its own tiling axis",
		fh != null and fv != null
		and _ca_seam(fh, "x") <= _ca_inner(fh, "x") * 1.6 + 0.02
		and _ca_seam(fv, "y") <= _ca_inner(fv, "y") * 1.6 + 0.02)

	# §5.3/§5.4: рваный край — это альфа, а не нарисованная рамка: 2 px у всех
	# четырёх углов прозрачны, тело бумаги непрозрачно.
	# stamp_frame и ring_pull — особые формы (рамка и кольцо с дыркой),
	# для них отдельные проверки ниже.
	var cutout := true
	for f in ["paper_daily.png", "paper_weekly.png", "paper_note.png", "sign_hang.png",
			"corner_iron.png"]:
		var img := _ca_img(CA_DIR + String(f))
		if img == null:
			cutout = false
			break
		var w := img.get_width()
		var h := img.get_height()
		var corners := [img.get_pixel(1, 1).a, img.get_pixel(w - 2, 1).a,
			img.get_pixel(1, h - 2).a, img.get_pixel(w - 2, h - 2).a]
		var clean := true
		for a in corners:
			clean = clean and float(a) < 0.05
		var body := true
		for k in 5:
			body = body and img.get_pixel(int(w * 0.5), int(h * (0.3 + 0.1 * k))).a > 0.9
		cutout = cutout and clean and body
	Selftest.check("§5.3 papers, sign and corner are cut-outs, not rectangles", cutout)

	# §5.3: stamp_frame — красная двойная рамка с прозрачной серединой.
	# Углы прозрачны (cut-out), непрозрачная рамка по краям.
	var sf_ok := false
	var sf_img := _ca_img(CA_DIR + "stamp_frame.png")
	if sf_img != null:
		var sf_w := sf_img.get_width()
		var sf_h := sf_img.get_height()
		var sf_corners := [sf_img.get_pixel(1, 1).a, sf_img.get_pixel(sf_w - 2, 1).a,
			sf_img.get_pixel(1, sf_h - 2).a, sf_img.get_pixel(sf_w - 2, sf_h - 2).a]
		var sf_clean := true
		for a in sf_corners:
			sf_clean = sf_clean and float(a) < 0.05
		# Проверяем непрозрачность верхней рамки в нескольких точках по X.
		var sf_border := true
		for k in 5:
			var bx := int(sf_w * (0.2 + 0.15 * k))
			sf_border = sf_border and sf_img.get_pixel(bx, 5).a > 0.5
		sf_ok = sf_clean and sf_border
	Selftest.check("§5.3 stamp_frame is a double frame with transparent interior", sf_ok)

	# §5.3: ring_pull — кованое кольцо с прозрачным центром (дырка).
	# Углы прозрачны, полоса кольца непрозрачна по горизонтали через центр.
	var rp_ok := false
	var rp_img := _ca_img(CA_DIR + "ring_pull.png")
	if rp_img != null:
		var rp_w := rp_img.get_width()
		var rp_h := rp_img.get_height()
		var rp_corners := [rp_img.get_pixel(1, 1).a, rp_img.get_pixel(rp_w - 2, 1).a,
			rp_img.get_pixel(1, rp_h - 2).a, rp_img.get_pixel(rp_w - 2, rp_h - 2).a]
		var rp_clean := true
		for a in rp_corners:
			rp_clean = rp_clean and float(a) < 0.05
		# Проверяем, что изображение имеет прозрачные области (дырку) и непрозрачные области (кольцо).
		var rp_band := false
		var rp_hole := false
		var opaque_count := 0
		var transparent_count := 0
		for y in range(rp_h):
			for x in range(rp_w):
				var a := rp_img.get_pixel(x, y).a
				if a > 0.5:
					opaque_count += 1
				elif a < 0.1:
					transparent_count += 1
		# Кольцо обязано иметь и непрозрачные пиксели, и прозрачные (дырка).
		rp_band = opaque_count > 100
		rp_hole = transparent_count > 100
		rp_ok = rp_clean and rp_band and rp_hole
	Selftest.check("§5.3 ring_pull is a ring with a through-hole, not a solid disk", rp_ok)

	# §5.3: бумага не плоская — запечённый градиент по вертикали плюс волокна.
	var paper := _ca_img(CA_DIR + "paper_daily.png")
	var varied := false
	if paper != null:
		var seen := {}
		var top := 0.0
		var bot := 0.0
		var tn := 0
		var bn := 0
		var n := 0
		var w := paper.get_width()
		var h := paper.get_height()
		for y in range(int(h * 0.2), int(h * 0.8), 3):
			for x in range(int(w * 0.2), int(w * 0.8), 3):
				var c := paper.get_pixel(x, y)
				if c.a <= 0.9:
					continue
				seen[int(_ca_luma(c) * 90.0)] = true
				n += 1
				if y < int(h * 0.4):
					top += _ca_luma(c)
					tn += 1
				else:
					bot += _ca_luma(c)
					bn += 1
		varied = (n > 400 and seen.size() >= 18 and tn > 0 and bn > 0
			and absf(top / float(tn) - bot / float(bn)) > 0.02)
	Selftest.check("§5.3 the paper carries a baked gradient and fibers, not a flat fill", varied)

	# §5.3: три печати — три разных картинки (эмблема тира не одна и та же).
	var seals := [_ca_img(CA_DIR + "seal_bronze.png"), _ca_img(CA_DIR + "seal_silver.png"),
		_ca_img(CA_DIR + "seal_gold.png")]
	var differ := seals[0] != null and seals[1] != null and seals[2] != null
	if differ:
		differ = (_ca_mean_diff(seals[0], seals[1]) > 0.05
			and _ca_mean_diff(seals[0], seals[2]) > 0.05
			and _ca_mean_diff(seals[1], seals[2]) > 0.02)
	Selftest.check("§5.3 the three tier seals are three different pictures", differ)

	# §5.3: гвоздь отбрасывает МЯГКУЮ тень — под шляпкой есть пиксели с частичной
	# альфой. Мутация: диск без градиента (тень = a 0 или 1) красит эту проверку.
	var nail := _ca_img(CA_DIR + "nail_brass.png")
	var soft := false
	if nail != null:
		var nw := nail.get_width()
		var nh := nail.get_height()
		var head := nail.get_pixel(int(nw * 0.5), int(nh * 0.4)).a > 0.9
		var pen := 0
		for y in range(int(nh * 0.55), int(nh * 0.95)):
			for x in range(2, nw - 2, 2):
				var a := nail.get_pixel(x, y).a
				if a > 0.04 and a < 0.85:
					pen += 1
		soft = head and pen > 200
	Selftest.check("§5.3 the brass nail sits on a soft cast shadow", soft)

	# §3.4: награды-витражи обязаны иметь арт и калибровку стекла:
	# house_view.gd:236-241 грузит res://assets/decor/<id>.png без guard'а.
	var vitrajes := true
	for id in ["window_contract", "window_seal", "window_guild"]:
		var img := _ca_img("res://assets/decor/%s.png" % String(id))
		var entry: Dictionary = DecorCalib.CALIB.get(String(id), {}) as Dictionary
		vitrajes = (vitrajes and img != null and img.get_size() == Vector2i(253, 256)
			and entry.has("glass") and FileAccess.file_exists(
				"res://assets/decor/%s.png.import" % String(id)))
	Selftest.check("§3.4 the three reward vitrajes ship art and a calibrated glass rect", vitrajes)

	# §3.4: витраж — перекраска СТЕКЛА донора: внутри rect стекла пиксели обязаны
	# отличаться, снаружи стекла — совпадать дословно, rect стекла — быть rect донора.
	var donor := _ca_img("res://assets/decor/window_9.png")
	var vc := _ca_img("res://assets/decor/window_contract.png")
	var recolored := false
	if donor != null and vc != null:
		var d0: Array = (DecorCalib.CALIB["window_9"] as Dictionary)["glass"]
		var d1: Array = (DecorCalib.CALIB["window_contract"] as Dictionary)["glass"]
		var w := donor.get_width()
		var h := donor.get_height()
		var gx0 := int(w * float(d0[0]))
		var gy0 := int(h * float(d0[1]))
		var gx1 := int(w * float(d0[2]))
		var gy1 := int(h * float(d0[3]))
		var inside_n := 0
		var inside_changed := 0
		var outside_changed := 0
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var pa := donor.get_pixel(x, y)
				var pb := vc.get_pixel(x, y)
				if pa.a < 0.05 and pb.a < 0.05:
					continue
				var inglass := x >= gx0 and x < gx1 and y >= gy0 and y < gy1
				var changed := _ca_delta(pa, pb) > 0.02
				if inglass:
					inside_n += 1
					if changed:
						inside_changed += 1
				elif changed:
					outside_changed += 1
		recolored = (d0 == d1 and inside_n > 200
			and float(inside_changed) / float(inside_n) > 0.5 and outside_changed == 0)
	Selftest.check("§3.4 the reward vitraj recolors only the donor's glass area", recolored)

# ---------- §5.3: хелперы карточки ----------

static func _cc_desc(node: Node, acc: Array) -> void:
	for ch in node.get_children():
		acc.append(ch)
		_cc_desc(ch, acc)


# Счёт слоёв, у которых настоящий PNG из папки доски.
static func _cc_assets(node: Node) -> int:
	var acc: Array = []
	_cc_desc(node, acc)
	var n := 0
	for d in acc:
		var t: Texture2D = null
		if d is TextureRect:
			t = (d as TextureRect).texture
		elif d is TextureButton:
			t = (d as TextureButton).texture_normal
		if t != null and str(t.resource_path).begins_with(CA_DIR):
			n += 1
	return n


# Кодовые примитивы вместо графики и слои без текстуры — обе болезни по rule 27.
static func _cc_bad(node: Node, acc: Array) -> void:
	for ch in node.get_children():
		var n := ch as Control
		if n == null:
			acc.append("not a control")
		elif n is ColorRect or n is Panel or n is PanelContainer or n is ProgressBar \
				or n is NinePatchRect or n is TextureProgressBar:
			acc.append(str(n.get_class()))
		elif n is TextureRect or n is TextureButton:
			var t: Texture2D = null
			if n is TextureRect:
				t = (n as TextureRect).texture
			else:
				t = (n as TextureButton).texture_normal
			if t == null or not str(t.resource_path).begins_with(CA_DIR):
				acc.append("layer:%s" % str(n.name))
		_cc_bad(n, acc)


static func _contract_card_checks(g: Game) -> void:
	var c := g._contracts
	var saved := _cb_snapshot(c)
	var saved_rank := g._workshop.rank
	var saved_auto := g._workshop.autonomy_level
	var e := g._engine
	var saved_spring: Dictionary = e.spring_levels.duplicate(true)
	var win_before: Vector2i = g.get_window().size
	g.get_window().size = Vector2i(540, 960)
	await g.get_tree().process_frame
	# Награда обязана быть масштабированной (§3.1). При пустых улучшениях множитель = 1.0,
	# и проверка «карточка печатает число из reward_for, а не из таблицы» была бы зелёной
	# сама по себе. Максимум по всем осям даёт 1 + 1.05 = 2.05.
	g._workshop.rank = ContractsBalance.RANK_MAX
	g._workshop.autonomy_level = ContractsBalance.AUTONOMY_MAX
	e.spring_levels = {"speed": int(ContractsBalance.SPRING_MAX["speed"]),
		"volume": int(ContractsBalance.SPRING_MAX["volume"]),
		"sources": int(ContractsBalance.SPRING_MAX["sources"]),
		"offline": int(ContractsBalance.SPRING_MAX["offline"])}

	var fixtures: Array = [
		_mk(c, "daily", "brew", "bronze", 15),
		_mk(c, "daily", "experiment", "silver", 2),
		_mk(c, "daily", "depth_brew", "gold", 3),
		_mk(c, "weekly", "sigil_set", "gold", 4),
		_mk(c, "weekly", "variety", "bronze", 8),
	]
	(fixtures[3] as Dictionary)["decor"] = "window_guild"
	(fixtures[3] as Dictionary)["buff"] = ""
	_force_set(c, [fixtures[0], fixtures[1], fixtures[2]], [fixtures[3], fixtures[4]])
	# Три состояния одной доски: не выполнено (6/15), готово к выдаче (2/2), получено (3/3).
	c._set_progress(String((fixtures[0] as Dictionary)["id"]), 6)
	c._set_progress(String((fixtures[1] as Dictionary)["id"]), 2)
	c._set_progress(String((fixtures[2] as Dictionary)["id"]), 3)
	c._done_dict("daily")[String((fixtures[2] as Dictionary)["id"])] = true

	var cards: Array = []
	var by_id := {}
	for raw in fixtures:
		var contract := raw as Dictionary
		var card := ContractCard.new(g)
		card.setup(contract)
		g.add_child(card)
		cards.append(card)
		by_id[String(contract["id"])] = card
	var unfinished: ContractCard = by_id[String((fixtures[0] as Dictionary)["id"])]
	var ready: ContractCard = by_id[String((fixtures[1] as Dictionary)["id"])]
	var claimed: ContractCard = by_id[String((fixtures[2] as Dictionary)["id"])]
	var wgold: ContractCard = by_id[String((fixtures[3] as Dictionary)["id"])]
	var states_ok := unfinished != null and ready != null and claimed != null and wgold != null

	# 1. Никаких кодовых примитивов: допустимы только слои с PNG и текст.
	var bad: Array = []
	if states_ok:
		_cc_bad(unfinished, bad)
		_cc_bad(wgold, bad)
	Selftest.check("§5.3 a note is paper, nail, seal and stamp — not one code-drawn box",
		states_ok and bad.is_empty() and _cc_assets(unfinished) >= 4 and _cc_assets(wgold) >= 4)

	# 2. Бумага рисуется в своём логическом размере: PNG @2x, rect @1x (§5.5).
	var up: TextureRect = unfinished.get("_paper") if states_ok else null
	var wp: TextureRect = wgold.get("_paper") if states_ok else null
	var paper_ok := up != null and wp != null and up.texture != null and wp.texture != null
	Selftest.check("§5.3 the weekly note hangs on bigger paper, both at the real PNG size",
		paper_ok and Vector2(up.texture.get_size()) == Vector2(280, 392)
		and Vector2(wp.texture.get_size()) == Vector2(368, 488)
		and up.size == ContractCard.DAILY_SIZE and wp.size == ContractCard.WEEKLY_SIZE)

	# 3. Наклон детерминирован по id и не больше ±4°.
	var tilt_ok := states_ok
	for i in range(cards.size()):
		var hang: Control = (cards[i] as ContractCard).get("_hang")
		if hang == null:
			tilt_ok = false
			continue
		var want := ContractCard.rot_deg(String((fixtures[i] as Dictionary)["id"]))
		if absf(want) > ContractCard.TILT_MAX + 0.001 \
				or not is_equal_approx(hang.rotation_degrees, want):
			tilt_ok = false
	Selftest.check("§5.3 every note hangs at its own deterministic tilt inside 4 degrees", tilt_ok)

	# 4. Хеш обязан рассеивать: 30 id дают минимум двенадцать углов и обе стороны.
	var tiers := ["bronze", "silver", "gold"]
	var angles := {}
	var lean_left := 0
	var lean_right := 0
	for i in range(30):
		var deg := ContractCard.rot_deg("daily:brew:%s:k%d" % [tiers[i % 3], i])
		angles[str(snappedf(deg, 0.01))] = true
		if deg < 0.0:
			lean_left += 1
		elif deg > 0.0:
			lean_right += 1
	Selftest.check("§5.3 thirty ids lean in both directions over at least twelve angles",
		angles.size() >= 12 and lean_left > 0 and lean_right > 0)

	# 5. Гвоздь — в середине верхнего края листа и торчит над ним (центр ровно на крае).
	var nail: TextureRect = unfinished.get("_nail") if states_ok else null
	var nail_ok := nail != null and nail.size == Vector2(ContractCard.NAIL_SIZE, ContractCard.NAIL_SIZE)
	if nail_ok:
		nail_ok = absf(nail.position.x + nail.size.x / 2.0 - ContractCard.DAILY_SIZE.x / 2.0) <= 0.5 \
			and absf(nail.position.y + nail.size.y / 2.0) <= 0.5
		# Гвоздь не висит на бумаге: он вбит в доску и не поворачивается вместе с листом.
		nail_ok = nail_ok and nail.get_parent() == unfinished
	Selftest.check("§5.3 the brass nail sits on the middle of the paper's top edge", nail_ok)

	# 6. Сургуч соответствует тиру контракта.
	var seal_ok := states_ok
	for i in range(cards.size()):
		var seal: TextureRect = (cards[i] as ContractCard).get("_seal")
		if seal == null or seal.texture == null:
			seal_ok = false
			continue
		var want_path := "%sseal_%s.png" % [CA_DIR, String((fixtures[i] as Dictionary)["tier"])]
		if str(seal.texture.resource_path) != want_path \
				or seal.size != Vector2(ContractCard.SEAL_SIZE, ContractCard.SEAL_SIZE):
			seal_ok = false
	Selftest.check("§5.3 the wax seal is the wax of the contract's own tier", seal_ok)

	# 7. Незакрытый контракт штампа не показывает, а счётчик цели показывает.
	var stamp_u: TextureButton = unfinished.get("_stamp") if states_ok else null
	var count_u: Label = unfinished.get("_count") if states_ok else null
	Selftest.check("§5.3 an unfinished note shows the counter, not a stamp",
		stamp_u != null and count_u != null and not stamp_u.visible and count_u.text == "6 / 15")

	# 8. Готовая к выдаче награда — штамп активен.
	var stamp_r: TextureButton = ready.get("_stamp") if states_ok else null
	var count_r: Label = ready.get("_count") if states_ok else null
	Selftest.check("§5.3 a fulfilled note shows an enabled claim stamp",
		stamp_r != null and count_r != null and stamp_r.visible and not stamp_r.disabled
		and count_r.text == "2 / 2")

	# 9. Полученный контракт: штамп виден и выключен, бумага обесцвечена; у остальных
	# параметр шейдера ровно 0.0 (материал обязан быть своим у каждой карточки).
	var stamp_c: TextureButton = claimed.get("_stamp") if states_ok else null
	var fade_c: ShaderMaterial = claimed.get("_fade") if states_ok else null
	var fade_r: ShaderMaterial = ready.get("_fade") if states_ok else null
	var fade_u: ShaderMaterial = unfinished.get("_fade") if states_ok else null
	var fade_ok := stamp_c != null and stamp_c.visible and stamp_c.disabled \
		and fade_c != null and fade_r != null and fade_u != null
	if fade_ok:
		fade_ok = is_equal_approx(float(fade_c.get_shader_parameter("amount")), 1.0) \
			and is_equal_approx(float(fade_r.get_shader_parameter("amount")), 0.0) \
			and is_equal_approx(float(fade_u.get_shader_parameter("amount")), 0.0)
	Selftest.check("§5.3 a claimed note fades and its stamp stops answering", fade_ok)

	# 10. Шейдер — обычный canvas_item без читок экрана (прецедент: suite_spring_v2 проверяет
	# исходник `spring_water.gdshader` текстом, потому что опечатка в headless молчит).
	var src := FileAccess.get_file_as_string(ContractCard.FADE_SHADER)
	Selftest.check("§5.3 the paper fade is plain canvas_item GLSL the card can drive",
		src.contains("shader_type canvas_item;") and src.contains("uniform float amount")
		and src.contains("texture(TEXTURE, UV)") and not src.contains(":=")
		and not src.contains("screen_texture"))

	# 11. Строка награды печатает число из reward_for (масштабированное), а не из таблицы,
	# и перечисляет ровно то, что платит этот контракт.
	var rew_u: Label = unfinished.get("_reward") if states_ok else null
	var rew_w: Label = wgold.get("_reward") if states_ok else null
	var paid := c.reward_for(fixtures[0] as Dictionary)
	var paid_stone := int((paid["materials"] as Dictionary)["stone"])
	var base_stone := int((ContractsBalance.DAILY_MATERIALS["bronze"] as Dictionary)["stone"])
	var want_line := "%s ×%d" % [g._online._item_name("stone"), paid_stone]
	var buff_title := String(ContractsBalance.BUFF_TITLE["brew_speed"])
	Selftest.check("§5.3 the reward line lists exactly what the note pays, at the scaled number",
		rew_u != null and rew_w != null and paid_stone != base_stone
		and rew_u.text.contains(want_line) and rew_u.text.contains(buff_title)
		and rew_w.text.contains(String(ContractsBalance.DECOR_LABEL["window_guild"]))
		and not rew_w.text.contains(buff_title))

	# 12. Ни один глиф не обязан быть в Manrope. Отрицательный контроль (✦ в шрифте нет) и
	# положительный (кириллица «А» есть) стоят в одной проверке: без них проверка была бы
	# зелёной при любой лжи has_char — в том числе при переставленных аргументах.
	var fnt: Font = g._font_semi
	var words := ""
	for card in cards:
		for key in ["_title", "_count", "_reward", "_stamp_word"]:
			var lbl := (card as ContractCard).get(key) as Label
			if lbl != null:
				words += lbl.text + " "
	var missing := ""
	if fnt != null:
		for i in range(words.length()):
			var cp := words.unicode_at(i)
			if cp > 32 and not fnt.has_char(cp):
				missing += words[i]
	Selftest.check("§5.3 every word on a note is a word the game font draws",
		fnt != null and missing == "" and fnt.has_char(0x0410)
		and not fnt.has_char(0x2726))

	# 13. Ряд Task 10 пересобирается при смене периода: второй setup() не должен навеслить
	# второй лист поверх первого.
	var reuse := ContractCard.new(g)
	reuse.setup(fixtures[0] as Dictionary)
	g.add_child(reuse)
	cards.append(reuse)
	var roots_before := reuse.get_child_count()
	var layers_before := _cc_assets(reuse)
	reuse.setup(fixtures[0] as Dictionary)
	reuse.setup(fixtures[3] as Dictionary)
	Selftest.check("§5.3 re-hanging a note on a new contract does not stack a second paper",
		roots_before >= 2 and layers_before >= 4 and reuse.get_child_count() == roots_before
		and _cc_assets(reuse) == layers_before)

	# 14. Штамп — кнопка получения: тап просит у доски ровно одну выдачу этого контракта.
	# Порядок важен: карточка ничего не выдаёт сама, она только шлёт claimed (§1).
	var ready_id := String((fixtures[1] as Dictionary)["id"])
	var asked: Array = []
	if stamp_r != null:
		ready.claimed.connect(func(id: String) -> void: asked.append(id))
		stamp_r.pressed.emit()
	Selftest.check("§5.3 pressing the stamp asks the board for exactly one claim of this note",
		asked.size() == 1 and String(asked[0]) == ready_id
		and stamp_r != null and stamp_r.pressed.is_connected(ready._on_stamp_pressed))

	# 15. Штамп приседает в момент нажатия (без кадра между emit и проверкой).
	Selftest.check("§5.3 the stamp squashes the moment it is hit",
		stamp_r != null and stamp_r.scale.x < 1.0 and stamp_r.scale.y < 1.0)

	for card in cards:
		(card as ContractCard).queue_free()
	await g.get_tree().process_frame
	g.get_window().size = win_before
	g._workshop.rank = saved_rank
	g._workshop.autonomy_level = saved_auto
	e.spring_levels = saved_spring.duplicate(true)
	_cb_restore(c, saved)
