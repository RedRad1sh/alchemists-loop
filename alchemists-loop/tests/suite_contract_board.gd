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

# Ввод для проверки клика/скролла: события подаются прямо в _gui_input виджета,
# поэтому координаты локальные и headless-прогон не зависит от настоящего курсора.
static func _mb(btn: int, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.position = at
	ev.global_position = at
	return ev

static func _mm(at: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	return ev

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
		# Task 4: claim() теперь трогает очаг/вехи/ранг — каждый блок обязан это
		# откатывать, иначе краснеют следующие блоки по await-списку.
		"visit_days": c._visit_days.duplicate(true),
		"streak_run": c._streak_run,
		"last_visit_day": c._last_visit_day,
		"hearth_claim": c._hearth_claim,
		"pts_total": c._pts_total,
		"mdays": c._mdays,
		"mpts": c._mpts,
		"unlocked_titles": c._unlocked_titles.duplicate(true),
		"active_title": c._active_title,
		"day_hint": c._day_hint,
		# Task 7: ряды goal_day/vein/fair и строка ранга читают недельный слой —
		# блок доски обязан его откатывать целиком.
		"week_cache": c._week_cache.duplicate(true),
		"cycle_cache": c._cycle_cache.duplicate(true),
		"vein_finds": c._vein_finds.duplicate(true),
		"vein_cap_total": c._vein_cap_total,
		"fair_regen_total": c._fair_regen_total,
		"week_offline": c._week_offline,
		"fair_local_week": c._fair_local_week,
		"fair_local_brews": c._fair_local_brews.duplicate(true),
		"fair_off_claim_week": c._fair_off_claim_week,
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
	c._visit_days = s["visit_days"]
	c._streak_run = int(s["streak_run"])
	c._last_visit_day = String(s["last_visit_day"])
	c._hearth_claim = String(s["hearth_claim"])
	c._pts_total = int(s["pts_total"])
	c._mdays = int(s["mdays"])
	c._mpts = int(s["mpts"])
	c._unlocked_titles = s["unlocked_titles"]
	c._active_title = String(s["active_title"])
	c._day_hint = String(s["day_hint"])
	c._week_cache = s["week_cache"]
	c._cycle_cache = s["cycle_cache"]
	c._vein_finds = s["vein_finds"]
	c._vein_cap_total = int(s["vein_cap_total"])
	c._fair_regen_total = float(s["fair_regen_total"])
	c._week_offline = bool(s["week_offline"])
	c._fair_local_week = String(s["fair_local_week"])
	c._fair_local_brews = s["fair_local_brews"]
	c._fair_off_claim_week = String(s["fair_off_claim_week"])

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
	# доска v2: пул дневных типов вырос 6→8 (pinned head goal_day/orders сверху)
	Selftest.check("§2.1 daily pool has exactly 8 active types",
		ContractsBalance.DAILY_TYPES.size() == 8)
	# доска v2: пул недельных типов вырос 5→7 (pinned head vein/fair сверху)
	Selftest.check("§2.2 weekly pool has exactly 7 active types",
		ContractsBalance.WEEKLY_TYPES.size() == 7)
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
	# доска v2: размер ряда вырос 3/2→4/4
	Selftest.check("§1.4 board shows 4 daily and 4 weekly",
		ContractsBalance.DAILY_SHOWN == 4 and ContractsBalance.WEEKLY_SHOWN == 4)

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
	# Баг владельца 2026-10-20: «Спешка в мастерской — мастерская спешит» игрок
	# не понял. Текст эффекта обязан называть подсистему и то, что с ней
	# происходит, а не повторять заголовок другими словами.
	Selftest.check("§5.4 buff effect texts name the subsystem and the effect, not the title",
		String(ContractsBalance.BUFF_TEXT["workshop_speed"]).contains("Мастерской")
		and not String(ContractsBalance.BUFF_TEXT["workshop_speed"]).contains("спешит")
		and String(ContractsBalance.BUFF_TEXT["brew_speed"]).contains("варка")
		and String(ContractsBalance.BUFF_TEXT["spring_yield"]).contains("материала")
		and String(ContractsBalance.BUFF_TEXT["craft_discount"]).contains("эфира")
		and String(ContractsBalance.BUFF_TEXT["ether_regen"]).contains("эфир"))
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
	# доска v2: размер ряда 3→4 и 2→4 — условие называем литералом, чтобы
	# проверка краснела на старых рядах, а не следовала за константой.
	var gen_a := probe._generate_daily(day_key, 3)
	var gen_b := probe._generate_daily(day_key, 3)
	Selftest.check("§6.1 the same local date generates a byte-identical daily set on both calls",
		gen_a == gen_b and gen_a.size() == 4)
	var week_key := Contracts.week_key_from(DT_MON)
	Selftest.check("§6.1 the same ISO week generates a byte-identical weekly set on both calls",
		probe._generate_weekly(week_key) == probe._generate_weekly(week_key)
		and probe._generate_weekly(week_key).size() == 4)

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
	# доска v2: ряд 3→4, distinct типов 3→4
	Selftest.check("§1.4 the 4 daily contracts have 4 distinct types from the pool",
		not type_dup and types_seen.size() == 4 and types_in_pool)

	# доска v2 (§2 спеки слияния): pinned head — первые ряды фиксированы по
	# типу и порядку, случайный хвост выбирается из пула без pinned.
	# Живой экземпляр трогаем через ensure_period — как в существующем образце;
	# состояние возвращаем снимком, иначе следующие блоки краснеют не по своей
	# причине (Review Focus №7). Имена dt_v2/d_v2/w_v2: в функции уже есть
	# блочные var dt/var d ниже, на уровне функции GDScript не переобъявляет.
	var cb_v2_snap := _cb_snapshot(g._contracts)
	var dt_v2 := {"year": 2026, "month": 10, "day": 19, "weekday": 1, "hour": 12, "minute": 0, "second": 0}
	g._contracts.ensure_period(dt_v2)
	var d_v2 := g._contracts.daily(dt_v2)
	var w_v2 := g._contracts.weekly(dt_v2)
	Selftest.check("boardgen v2 daily shown 4 with pinned goal_day/orders",
		d_v2.size() == 4 and String((d_v2[0] as Dictionary)["type"]) == "goal_day"
		and String((d_v2[1] as Dictionary)["type"]) == "orders")
	Selftest.check("boardgen v2 weekly shown 4 with pinned vein/fair",
		w_v2.size() == 4 and String((w_v2[0] as Dictionary)["type"]) == "vein"
		and String((w_v2[1] as Dictionary)["type"]) == "fair")
	# Проверка начинается с guards d_v2.size()==4/w_v2.size()==4: на рядах старого
	# размера индексы d_v2[3]/w_v2[2] были бы выходом за границу, а сюита обязана
	# краснеть, а не ронять исполнителя (условие после guard — точное из спеки).
	Selftest.check("boardgen v2 random part excludes pinned",
		d_v2.size() == 4 and w_v2.size() == 4
		and not (["goal_day", "orders"] as Array).has(String((d_v2[2] as Dictionary)["type"]))
		and String((d_v2[2] as Dictionary)["type"]) != String((d_v2[3] as Dictionary)["type"])
		and not (["vein", "fair"] as Array).has(String((w_v2[2] as Dictionary)["type"])))
	Selftest.check("boardgen v2 pinned goals",
		int((d_v2[0] as Dictionary)["goal"]) == 1 and int((d_v2[1] as Dictionary)["goal"]) == 3
		and int((w_v2[1] as Dictionary)["goal"]) == 3)
	# Старый вид TIERS.has(d_v2[0]["tier"]) был зелёным всегда: тир по построению
	# из TIERS. Условие теперь проверяет зависимость от seed: на 30 ключах дня
	# тир d[0] обязан встретиться больше одного раза (хардкод тира краснит его).
	# probe — отдельный экземпляр, _generate_daily не меняет ни его, ни
	# g._contracts — снимок не нужен (как в соседней проверке разнообразия).
	var v2_tier_seen := {}
	var v2_tier_unix := int(Time.get_unix_time_from_datetime_dict(dt_v2))
	for v2_off in 30:
		var v2_tier_row: Dictionary = probe._generate_daily(
			Contracts.day_key_from(Time.get_datetime_dict_from_unix_time(
				v2_tier_unix + v2_off * 86400)), 3)[0]
		v2_tier_seen[String(v2_tier_row["tier"])] = true
	Selftest.check("boardgen v2 pinned tier comes from seed (30 day keys, >1 distinct tier)",
		v2_tier_seen.size() > 1)
	# Сейв v1 (ряды 3/2) обязан деградировать регенерацией, а не откатом блока:
	# фикстура — реальный save_block зонда, у которого списки обрезаны до старого
	# размера, а ключи периода совпадают с текущим (dt_v2). Только так проверка
	# чувствительна к механизму: ряд станет размера 4 исключительно по пути
	# «отвергнутый список сбрасывает ключи» (ensure_period регенерирует по пустому
	# ключу). С прошедшими ключами проверка была нечувствительна: ключи расходились
	# бы с текущими и при сломанной rejects-обработке, регенерация случилась бы сама.
	var lprobe := Contracts.new(g)
	lprobe.ensure_period(dt_v2)
	var legacy_blk: Dictionary = lprobe.save_block()
	legacy_blk["daily"] = (legacy_blk["daily"] as Array).slice(0, 3)
	legacy_blk["weekly"] = (legacy_blk["weekly"] as Array).slice(0, 2)
	legacy_blk["last_daily"] = Contracts.day_key_from(dt_v2)
	legacy_blk["last_weekly"] = Contracts.week_key_from(dt_v2)
	var legacy_probe := Contracts.new(g)
	legacy_probe.load_block(legacy_blk)
	legacy_probe.ensure_period(dt_v2)
	Selftest.check("boardgen v2 legacy-size lists regenerate",
		legacy_probe.daily(dt_v2).size() == 4)
	_cb_restore(g._contracts, cb_v2_snap)

	# доска v2 Task 2 (§1 строки 1–2): поведение goal_day и orders. Живой
	# экземпляр мутируем варками и полями гильдии, состояние возвращаем снимками
	# (доска — _cb_snapshot, гильдия — три поля заказов, как suite_riddles_retention
	# с circle-полями), иначе следующие блоки краснеют не по своей причине.
	# Варка цели под дополнительным goal_t2.has("out"): без него на незакрытом
	# поведении goal_t2["out"] дал бы рантайм-ошибку и оборвал весь прогон,
	# а сюита обязана краснеть поведением, не падением.
	var t2_snap := _cb_snapshot(g._contracts)
	var today_t2 := Contracts.day_key_from(Time.get_datetime_dict_from_system())
	var goal_t2: Dictionary = g._contracts._local_goal_for(today_t2)
	Selftest.check("goal_day local pair is two-base deterministic",
		goal_t2.has("out") and Game.BASE_IDS.has(String(goal_t2["a"]))
		and Game.BASE_IDS.has(String(goal_t2["b"]))
		and goal_t2 == g._contracts._local_goal_for(today_t2))
	var gd_t2 := (g._contracts.daily() as Array)[0] as Dictionary
	# Pre-phase (Fix round 1, Important #1): бриф-проверка «goal_day ignores other
	# outputs» не способна краснеть на удалённом guard в on_brew (contracts.gd:503):
	# цель goal_day == 1, _bump отсечён капом, и после зелёной positive-варки
	# before2 == 1 — unconditional bump оставляет 1. Здесь же прогресс
	# принудительно обнулён (done-флаг снят, чтобы _bump не пропускал строку
	# молча), варится НЕ-цель, и прогресс обязан остаться 0: на удалённом guard
	# это единственная проверка, которая краснеет. Делается ДО positive-варки,
	# positive-проверка брифа ниже остаётся дословно, как post-cap assertion.
	# Состояние доски возвращает общий t2_snap в конце блока.
	g._contracts._contracts_daily_done.erase(String(gd_t2["id"]))
	g._contracts._set_progress(String(gd_t2["id"]), 0)
	g._contracts.on_brew("zz_not_goal_output", "water", "fire", false, "manual")
	Selftest.check("goal_day pre-cap ignores other outputs",
		g._contracts.progress(String(gd_t2["id"])) == 0)
	var before_t2 := g._contracts.progress(String(gd_t2["id"]))
	if before_t2 == 0 and goal_t2.has("out"):
		g._contracts.on_brew(String(goal_t2["out"]), String(goal_t2["a"]),
			String(goal_t2["b"]), false, "manual")
	Selftest.check("goal_day advances on brewing the local goal output",
		g._contracts.progress(String(gd_t2["id"])) == 1)
	var before2_t2 := g._contracts.progress(String(gd_t2["id"]))
	g._contracts.on_brew("zz_not_goal_output", "water", "fire", false, "manual")
	Selftest.check("goal_day ignores other outputs",
		g._contracts.progress(String(gd_t2["id"])) == before2_t2)
	# orders: два выполненных заказа гильдии зеркалятся на строку orders доски,
	# третий закрывает цель (3) — ready. Проверяем внутри фикстуры, иначе
	# «mirrors … size» на пустом _order_done была бы зелёной всегда.
	var t2_ord_day: Variant = g._guild._order_day
	var t2_ord_targets: Array = g._guild._order_targets_cache.duplicate(true)
	var t2_ord_done: Dictionary = g._guild._order_done.duplicate(true)
	g._guild._order_day = Time.get_date_string_from_system()
	g._guild._order_targets_cache = ["steam", "stone", "clay"]
	g._guild._order_done = {"steam": true, "stone": true}
	var or_t2_id := String((g._contracts.daily() as Array)[1]["id"])
	Selftest.check("orders progress mirrors guild order_done size",
		g._guild._order_done.is_empty() or g._contracts.progress(String((g._contracts.daily() as Array)[1]["id"])) > 0)
	Selftest.check("orders contract mirrors two done guild orders",
		g._contracts.progress(or_t2_id) == 2)
	g._guild._order_done["clay"] = true
	g._contracts.daily()
	Selftest.check("orders contract is ready when all three guild orders are done",
		g._contracts.is_ready(or_t2_id))
	g._guild._order_day = String(t2_ord_day)
	g._guild._order_targets_cache = t2_ord_targets
	g._guild._order_done = t2_ord_done
	_cb_restore(g._contracts, t2_snap)

	# доска v2 Task 3 (§1 строки 7–8): недельный слой (жила + ярмарка) переехал в
	# Contracts, поэтому pinned weekly[0]=vein и weekly[1]=fair живут доской.
	# Снимки: доска (_cb_snapshot), поля недельного слоя, инвентарь с Домом (у
	# успешного claim fair есть выдача) и флаги сети — на время проверки офлайн-
	# котёл обязан быть недоступным, иначе гейт ярмарки краснеет не по своей
	# причине. Локалы с суффиксом/именами блока: в run() уже есть блочные dt/d,
	# переобъявление уровня функции GDScript карает Parse Error.
	var t3_snap := _cb_snapshot(g._contracts)
	# Финал-фикс M4: сетевые хендлеры (_on_net_vein_find_result, закрытие цикла)
	# мутируют находки и кеш-словари in place, поэтому снимок обязан быть deep —
	# иначе откат ниже был бы no-op и последующие блоки наследовали бы грязь.
	var t3_week := {
		"week_cache": g._contracts._week_cache.duplicate(true),
		"cycle_cache": g._contracts._cycle_cache.duplicate(true),
		"vein_finds": g._contracts._vein_finds.duplicate(true),
		"vein_cap": g._contracts._vein_cap_total,
		"regen": g._contracts._fair_regen_total, "local_week": g._contracts._fair_local_week,
		"local_brews": g._contracts._fair_local_brews.duplicate(true),
		"off_claim": g._contracts._fair_off_claim_week,
		"offline": g._contracts._week_offline, "prev_state": g._contracts._cycle_prev_state,
	}
	var t3_env := {
		"inv": g._engine.inventory.duplicate(true),
		"owned": g._home.house_owned.duplicate(true),
		"net": g._online._net_enabled, "avail": Net.is_available(),
		"dev": g._online._device_id, "status": g._engine.status_text,
	}
	# Онлайн-фикстура: _fair_offline_available() обязан стать false, иначе ярмарка
	# читает локальный котёл, а не серверный гейт (в selftest Net обрезан).
	g._online._net_enabled = true
	Net._available = true
	g._online._device_id = "t3-device"
	var wk := (g._contracts.weekly())[0] as Dictionary  # vein
	var sv_cyc: Dictionary = g._contracts._cycle_cache
	var sv_finds: Array = g._contracts._vein_finds.duplicate(true)
	g._contracts._cycle_cache = {"cycle_id": "vc:T1", "tag1": "Туман", "state": "active"}
	g._contracts._vein_finds = [
		{"id": "a", "tag": "Туман", "points": 1, "found_at": 1, "pair_key": "p1",
			"cycle_id": "vc:T1", "status": "registered", "server_response": {}},
		{"id": "b", "tag": "Туман", "points": 1, "found_at": 1, "pair_key": "p2",
			"cycle_id": "vc:T1", "status": "poured", "server_response": {}},
		{"id": "c", "tag": "Туман", "points": 1, "found_at": 1, "pair_key": "p3",
			"cycle_id": "vc:OLD", "status": "registered", "server_response": {}},
		{"id": "d", "tag": "Туман", "points": 1, "found_at": 1, "pair_key": "p4",
			"cycle_id": "vc:T1", "status": "pending_server", "server_response": {}}]
	g._contracts._sync_vein()
	# цель bronze=1..gold=3 по тиру; прогресс = только текущий цикл, registered|poured:
	Selftest.check("vein contract counts current-cycle registered+poured only",
		g._contracts.progress(String(wk["id"])) == mini(2, int(wk["goal"])))
	var wf := (g._contracts.weekly())[1] as Dictionary
	g._contracts._week_cache = {"fair": {"closed": true, "my_contrib": 3, "claimed": false,
		"progress": 9, "goal": 12, "tag": "Туман"}}
	g._contracts._sync_fair()
	Selftest.check("fair contract ready via server gate",
		g._contracts.is_ready(String(wf["id"])))
	var claim_res := g._contracts.claim(String(wf["id"]))
	Selftest.check("fair claim grants board reward once",
		bool(claim_res["ok"]) and g._contracts.claim(String(wf["id"]))["reason"] == "claimed")
	# Finding 1 (спека §4): право забрать награду fair даёт гейт ЗАКРЫТОГО котла, а
	# не прогресс. Открытый котёл с вкладом ≥3 оставляет is_ready() ложным, но
	# прогресс fair (=3) формально равен цели — доска не обязана за это платить.
	# Строку fair вернули в открытое состояние (erase done), иначе done-skip оставил
	# бы прогресс нулевым и claim отказал бы по чужой причине. Локальный котельный
	# гейт (_fair_offline_claimable) глушим обнулением варок: иначе ambient-состояние
	# сюиты делает _fair_gate() истинным и проверка краснела бы через is_ready, а не
	# через баг claim() — тогда RED был бы вакуумным.
	g._contracts._contracts_weekly_done.erase(String(wf["id"]))
	g._contracts._contracts_weekly_prog.erase(String(wf["id"]))
	g._contracts._fair_local_brews = []
	g._contracts._week_cache = {"fair": {"closed": false, "my_contrib": 3, "claimed": false,
		"progress": 3, "goal": 3, "tag": "Туман"}}
	g._contracts._sync_fair()
	var t3f1_ready := g._contracts.is_ready(String(wf["id"]))
	var t3f1_claim := g._contracts.claim(String(wf["id"]))
	Selftest.check("fair claim on an OPEN pot is refused, readiness stays by the closed-pot gate",
		not t3f1_ready and not bool(t3f1_claim["ok"]))
	g._contracts._week_cache = {}
	g._contracts._cycle_cache = sv_cyc
	g._contracts._vein_finds = sv_finds
	# Прогресс vein обязан догоняться и на самом входе weekly(): доска рисует
	# строку сразу, без отдельного вызова синка из UI.
	g._contracts._cycle_cache = {"cycle_id": "vc:T3", "tag1": "Туман", "state": "active"}
	g._contracts._vein_finds = [
		{"id": "a", "tag": "Туман", "points": 1, "found_at": 1, "pair_key": "p1",
			"cycle_id": "vc:T3", "status": "registered", "server_response": {}},
		{"id": "b", "tag": "Туман", "points": 1, "found_at": 1, "pair_key": "p2",
			"cycle_id": "vc:T3", "status": "poured", "server_response": {}}]
	# Изоляция проверки: предыдущий явный _sync_vein() уже оставил прогресс vein = 2,
	# и новая фикстура T3 тоже даёт 2 — без стирания записи проверка осталась бы
	# зелёной даже если weekly() перестать синкать жилу. Стираем запись, чтобы
	# единственным источником значения стал sync внутри weekly().
	g._contracts._contracts_weekly_prog.erase(String(wk["id"]))
	g._contracts.weekly()
	Selftest.check("weekly() syncs the pinned vein contract",
		g._contracts.progress(String(wk["id"])) == mini(2, int(wk["goal"])))
	# Done-skip: закрытый контракт синк не оживляет — то же правило, что у orders
	# (иначе недельная награда выдавалась бы повторно до конца недели).
	var wk_id := String(wk["id"])
	g._contracts._contracts_weekly_done[wk_id] = true
	g._contracts._contracts_weekly_prog.erase(wk_id)
	g._contracts._sync_vein()
	Selftest.check("vein sync leaves a done contract at zero progress",
		g._contracts.progress(wk_id) == 0)
	g._contracts._contracts_weekly_done.erase(wk_id)
	# Офлайн-гейт ярмарки: без сети readiness даёт локальный котёл
	# (_fair_offline_claimable, FAIR_OFFLINE_GOAL == 3), а прогресс пишется с
	# _fair_local_brews — так ярмарка остаётся проходимой без сервера.
	var wf_id := String(wf["id"])
	g._online._net_enabled = false
	Net._available = false
	# Строка fair была закрыта успешным claim выше (проверка «один раз»), для
	# офлайн-гейта её надо вернуть в открытое состояние — иначе done-skip в
	# _sync_fair законно оставит прогресс нулевым, и проверка покраснеет не по
	# своей причине.
	g._contracts._contracts_weekly_done.erase(wf_id)
	g._contracts._contracts_weekly_prog.erase(wf_id)
	g._contracts._fair_off_claim_week = ""
	g._contracts._fair_regen_total = 0.0
	g._contracts._fair_local_week = Home._iso_week_id()
	g._contracts._fair_local_brews = ["steam", "stone", "clay"]
	g._contracts._sync_fair()
	Selftest.check("fair contract ready via local pot gate",
		g._contracts.progress(wf_id) == int(wf["goal"]) and g._contracts.is_ready(wf_id))
	g._contracts._fair_local_brews = ["steam", "stone"]
	g._contracts._sync_fair()
	Selftest.check("fair local pot below goal is not ready",
		g._contracts.progress(wf_id) == int(wf["goal"]) - 1 and not g._contracts.is_ready(wf_id))
	# ---------- Финал-фикс I-1/I-2 (final whole-branch review) ----------
	# I-1: потерянный ответ /fair/claim. Контракт к тому моменту уже закрыт
	# (карточка проштампована, is_ready мёртв), и единственный путь повторить
	# вечный грант — молча переспросить сервер при ближайшем статусе недели.
	# Сервер держит authority claimed-флагом, повтор безопасен. Предиката
	# read-only (ищет fair по типу в _contracts_weekly, без сайд-эффектов
	# weekly()); наблюдимость проводки — счётчик _fair_regrants, тот же
	# прецедент Task 8, что _board_refreshes. В selftest _fair_claim() выходит
	# до отправки — наблюдаем счётчик, а не send.
	var fx1_done0: Variant = g._contracts._contracts_weekly_done.duplicate(true)
	var fx1_week0: Variant = g._contracts._week_cache.duplicate(true)
	var fx1_regrants0 := g._contracts._fair_regrants
	g._contracts._contracts_weekly_done[wf_id] = true
	g._contracts._week_cache = {"fair": {"closed": true, "my_contrib": 3, "claimed": false}}
	Selftest.check("I-1 predicate: done fair contract + closed pot + contrib 3 + unclaimed grant retries",
		g._contracts._fair_grant_unclaimed())
	g._contracts._week_cache = {"fair": {"closed": true, "my_contrib": 3, "claimed": true}}
	Selftest.check("I-1 predicate: claimed pot never retries",
		not g._contracts._fair_grant_unclaimed())
	g._contracts._week_cache = {"fair": {"closed": true, "my_contrib": 2, "claimed": false}}
	Selftest.check("I-1 predicate: contrib below the gate never retries",
		not g._contracts._fair_grant_unclaimed())
	g._contracts._week_cache = {"fair": {"closed": false, "my_contrib": 3, "claimed": false}}
	Selftest.check("I-1 predicate: open pot never retries",
		not g._contracts._fair_grant_unclaimed())
	g._contracts._week_cache = {"fair": {"closed": true, "my_contrib": 3, "claimed": false}}
	g._contracts._contracts_weekly_done.erase(wf_id)
	Selftest.check("I-1 predicate: fair contract not taken on the board never retries",
		not g._contracts._fair_grant_unclaimed())
	g._contracts._contracts_weekly_done[wf_id] = true
	g._contracts._on_net_week_result({"ok": true,
		"fair": {"closed": true, "my_contrib": 3, "claimed": false}})
	Selftest.check("I-1 wiring: week status with an unclaimed grant calls _fair_claim exactly once",
		g._contracts._fair_regrants - fx1_regrants0 == 1)
	g._contracts._on_net_week_result({"ok": true,
		"fair": {"closed": true, "my_contrib": 3, "claimed": true}})
	Selftest.check("I-1 wiring: claimed week status does not move the retry counter",
		g._contracts._fair_regrants - fx1_regrants0 == 1)
	# I-2: pop-посев обязан переживать недельный синк: raw-прогресс затирается
	# weekly()→_sync_vein по _vein_finds (в чистом демо-сейве они пусты — ровно
	# причина сломанного попапа). Инъектор сеёт цикл + ≥3 registered-капель:
	# цель vein ≤3 по любому тиру, поэтому готовность держится после любого sync.
	g._contracts._cycle_cache = {}
	g._contracts._vein_finds = []
	g._contracts._inject_vein_ready()
	g._contracts.weekly()
	Selftest.check("I-2 pop seed: injected vein contract stays ready through the weekly() sync",
		g._contracts.is_ready(wk_id))
	g._contracts._contracts_weekly_done = fx1_done0
	g._contracts._week_cache = fx1_week0
	g._contracts._fair_regrants = fx1_regrants0
	g._online._net_enabled = bool(t3_env["net"])
	Net._available = bool(t3_env["avail"])
	g._online._device_id = String(t3_env["dev"])
	g._engine.status_text = String(t3_env["status"])
	g._engine.inventory = (t3_env["inv"] as Dictionary).duplicate(true)
	g._home.house_owned = (t3_env["owned"] as Dictionary).duplicate(true)
	g._contracts._week_cache = t3_week["week_cache"]
	g._contracts._cycle_cache = t3_week["cycle_cache"]
	g._contracts._vein_finds = t3_week["vein_finds"]
	g._contracts._vein_cap_total = int(t3_week["vein_cap"])
	g._contracts._fair_regen_total = float(t3_week["regen"])
	g._contracts._fair_local_week = String(t3_week["local_week"])
	g._contracts._fair_local_brews = t3_week["local_brews"]
	g._contracts._fair_off_claim_week = String(t3_week["off_claim"])
	g._contracts._week_offline = bool(t3_week["offline"])
	g._contracts._cycle_prev_state = String(t3_week["prev_state"])
	_cb_restore(g._contracts, t3_snap)

	# доска v2 Task 4 (§1 строки 5–6, §3): визит-день = день, в который закрыт
	# дневной контракт; очки вех = тир закрытого контракта (bronze+1/silver+2/
	# gold+3). Лестница CIRCLE_GOALS и 75⚡ за «закрытый круг» удалены — эти
	# проверки их замещают. Фикстуры (_mk) вместо живого набора: тир bronze/
	# silver известен заранее, и «delta == 1» не должен зависеть от того, какой
	# тир сегодня выбросил генератор.
	var t4_snap := _cb_snapshot(g._contracts)
	var t4_inv := g._engine.inventory.duplicate(true)
	var t4_ether := g._engine.ether
	var t4_status := g._engine.status_text
	# Обнуляем очаг детерминированно: проверки сверяют точные числа, а не
	# ambient-значения из подгруженного сейва.
	g._contracts._visit_days = []
	g._contracts._streak_run = 0
	g._contracts._last_visit_day = ""
	g._contracts._hearth_claim = ""
	g._contracts._pts_total = 0
	var t4_d1 := _mk(g._contracts, "daily", "brew", "bronze", 1)
	var t4_d2 := _mk(g._contracts, "daily", "brew", "silver", 1)
	_force_set(g._contracts, [t4_d1, t4_d2], g._contracts._contracts_weekly)
	_clear_prog(g._contracts)
	var t4_id1 := String(t4_d1["id"])
	var t4_pts_before := g._contracts._pts_total
	g._contracts._set_progress(t4_id1, 1)
	var t4_res := g._contracts.claim(t4_id1)
	var t4_today := Contracts.day_key_from(Time.get_datetime_dict_from_system())
	var t4_delta := g._contracts._pts_total - t4_pts_before
	Selftest.check("first daily claim of the day opens a visit day and streak",
		bool(t4_res["ok"]) and g._contracts._visit_days.has(t4_today)
		and g._contracts._streak_run >= 1)
	Selftest.check("milestone points equal closed-contract tier value", t4_delta == 1)
	var t4_days_after := g._contracts._visit_days.size()
	var t4_id2 := String(t4_d2["id"])
	var t4_pts2_before := g._contracts._pts_total
	g._contracts._set_progress(t4_id2, 1)
	var t4_res2 := g._contracts.claim(t4_id2)
	Selftest.check("second claim of the day does not add a second visit day",
		g._contracts._visit_days.size() == t4_days_after)
	Selftest.check("silver claim adds exactly two milestone points",
		bool(t4_res2["ok"]) and g._contracts._pts_total - t4_pts2_before == 2)
	# mark_day_challenge(): серверное испытание теперь просто закрывает цель
	# дня без всякой выдачи (старые 75⚡ и локальные очки CIRCLE_LOCAL_POINTS
	# удалены). Инвентарь, эфир, визит-дни и очки вех меняться не обязаны.
	var t4_gd := _mk(g._contracts, "daily", "goal_day", "gold", 5)
	_force_set(g._contracts, [t4_gd], g._contracts._contracts_weekly)
	_clear_prog(g._contracts)
	var t4_gd_id := String(t4_gd["id"])
	var t4_inv_before := g._engine.inventory.duplicate(true)
	var t4_pts3 := g._contracts._pts_total
	var t4_days3 := g._contracts._visit_days.size()
	var t4_ether3 := g._engine.ether
	g._contracts.mark_day_challenge()
	Selftest.check("mark_day_challenge closes goal_day without any payout",
		g._contracts.is_done(t4_gd_id) and g._contracts._pts_total == t4_pts3
		and g._contracts._visit_days.size() == t4_days3
		and g._engine.ether == t4_ether3
		and g._engine.inventory == t4_inv_before)
	var t4_run3 := g._contracts._streak_run
	g._contracts.mark_day_challenge()
	Selftest.check("mark_day_challenge is idempotent",
		g._contracts.is_done(t4_gd_id) and g._contracts._pts_total == t4_pts3
		and g._contracts._streak_run == t4_run3)
	# Эквивалентность формул: кап/реген движка обязан оставаться суммой базы
	# и бонусов Contracts — считаем против живой формулы дифференциально
	# (обнуление → известное состояние). На заглушках движок ещё читает
	# Retention, поэтому дельта по полям Contracts нулевая и проверки красные.
	var t4_miles := {"mdays": g._contracts._mdays, "mpts": g._contracts._mpts,
		"vein": g._contracts._vein_cap_total, "fair": g._contracts._fair_regen_total}
	g._contracts._mdays = 0
	g._contracts._mpts = 0
	g._contracts._vein_cap_total = 0
	g._contracts._fair_regen_total = 0.0
	var t4_cap0 := g._engine._max_ether()
	g._contracts._vein_cap_total = 10
	var t4_cap1 := g._engine._max_ether()
	Selftest.check("engine cap sums the vein bonus living in Contracts",
		t4_cap1 - t4_cap0 == 10)
	g._contracts._mdays = 2
	g._contracts._mpts = 2
	var t4_cap2 := g._engine._max_ether()
	# _mdays=2 → вехи 7 и 30: кап 5+0; _mpts=2 → 50 и 150: кап 3+0.
	Selftest.check("engine cap counts Contracts milestone bonus by the mile tables",
		t4_cap2 - t4_cap1 == 8)
	g._contracts._mdays = 0
	g._contracts._mpts = 0
	g._contracts._fair_regen_total = 0.0
	var t4_rate0 := g._engine._ether_rate()
	g._contracts._fair_regen_total = 0.5
	var t4_rate1 := g._engine._ether_rate()
	var t4_mult := g._engine._sage_multiplier() * (1.0 + g._contracts.buff_power("ether_regen"))
	Selftest.check("engine regen sums the fair bonus living in Contracts",
		is_equal_approx(t4_rate1 - t4_rate0, 0.5 * t4_mult))
	# _mdays=2 → реген 0+0.05; _mpts=2 → 0.03+0.
	g._contracts._mdays = 2
	g._contracts._mpts = 2
	var t4_rate2 := g._engine._ether_rate()
	Selftest.check("engine regen counts Contracts milestone bonus by the mile tables",
		is_equal_approx(t4_rate2 - t4_rate1, 0.08 * t4_mult))
	g._contracts._mdays = int(t4_miles["mdays"])
	g._contracts._mpts = int(t4_miles["mpts"])
	g._contracts._vein_cap_total = int(t4_miles["vein"])
	g._contracts._fair_regen_total = float(t4_miles["fair"])
	g._engine.inventory = t4_inv
	g._engine.ether = t4_ether
	g._engine.status_text = t4_status
	_cb_restore(g._contracts, t4_snap)

	# доска v2 Task 8 (спека §8): демо-состояние boardfull — слияние удалённых
	# _inject_circle_demo/_inject_week_demo в один инъектор Contracts. Сюита не
	# строит ноду доски, поэтому «доска обновилась» меряется счётчиком
	# refresh_board: инъектор обязан двигать его сам. Снимок/откат — общий
	# (_cb_snapshot) плюс три поля заказов гильдии, как в блоке Task 2.
	var t8_snap := _cb_snapshot(g._contracts)
	var t8_ord_day: Variant = g._guild._order_day
	var t8_ord_targets: Array = g._guild._order_targets_cache.duplicate(true)
	var t8_ord_done: Dictionary = g._guild._order_done.duplicate(true)
	var t8_refresh_before := g._contracts._board_refreshes
	g._contracts._inject_board_demo()
	var t8_statuses: Array = []
	var t8_cyc := String(g._contracts._cycle_cache.get("cycle_id", ""))
	for t8_f in g._contracts._vein_finds:
		if typeof(t8_f) == TYPE_DICTIONARY \
				and String((t8_f as Dictionary).get("cycle_id", "")) == t8_cyc:
			t8_statuses.append(String((t8_f as Dictionary)["status"]))
	var t8_fair: Dictionary = g._contracts._week_fair()
	var t8_orders_id := String((g._contracts.daily() as Array)[1]["id"])
	Selftest.check("§8 boardfull demo: streak 3, rank 4, three current-cycle vein statuses, active fair pot, orders 3/3, board refreshed",
		g._contracts._streak_run == 3 and g._contracts.rank_level() == 4
		and t8_cyc != "" and t8_statuses.size() == 3
		and t8_statuses.has("registered") and t8_statuses.has("pending_server")
		and t8_statuses.has("poured")
		and not t8_fair.is_empty() and int(t8_fair.get("progress", 0)) > 0
		and not bool(t8_fair.get("closed", false))
		and g._contracts.progress(t8_orders_id) == 3
		and g._contracts._board_refreshes > t8_refresh_before)
	g._guild._order_day = String(t8_ord_day)
	g._guild._order_targets_cache = t8_ord_targets
	g._guild._order_done = t8_ord_done
	_cb_restore(g._contracts, t8_snap)

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
	# доска v2: ряд 3+2=5 → 4+4=8
	Selftest.check("§4.1 all_contracts returns 4 daily + 4 weekly = 8 contracts",
		probe.all_contracts(DT_MON).size() == 8)
	Selftest.check("§4.1 contract_by_id returns an empty dictionary for an id from a burnt period",
		probe.contract_by_id("daily:brew:gold:2020-01-01", DT_MON).is_empty())

	# ---------------- проводка ----------------
	Selftest.check("g._contracts exists and points back at the game",
		g._contracts != null and g._contracts.g == g)
	# доска v2 Task 6 (спека §6): блок переехал на v2 — чинит 17 новых ключей.
	Selftest.check("§4.1 CONTRACTS_SAVE_VERSION is 2", Contracts.CONTRACTS_SAVE_VERSION == 2)
	# доска v2 Task 6: формат сейва поднялся до 5; v4-файлы остаются читаемыми
	# (гейт _read_save принимает 1..SAVE_VERSION) и мигрируют presence-based.
	Selftest.check("§6 Game.SAVE_VERSION is 5", Game.SAVE_VERSION == 5)
	# Живой экземпляр генерирует сегодняшний набор при первом обращении.
	# доска v2: размер ряда 3/2→4/4, условие названо литералом.
	Selftest.check("§1.4 the live instance generates 4 daily and 4 weekly on first access",
		g._contracts.daily().size() == 4
		and g._contracts.weekly().size() == 4)

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
	# 4 дневных и 4 недельных контракта на ближайшем обращении (доска v2, 3/2→4/4).
	# Отдельный
	# экземпляр: живой c5 в этом блоке держит фикстуры, а здесь проверка краснеет
	# ровно одним условием — несброшенным ключом дня (_contracts_last_daily),
	# из-за которого ensure_period() считает период неизменным и возвращает
	# очищенный пустой дневной список вплоть до полуночи.
	var regen_probe := Contracts.new(g)
	regen_probe.daily()
	regen_probe.weekly()
	regen_probe.on_prestige()
	Selftest.check("§4.4 after on_prestige the daily set regenerates on next access",
		regen_probe.daily().size() == 4
		and regen_probe.weekly().size() == 4)

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
		# Task 4: успешный claim больше не нейтрален — очаг/вехи/ранг мутируются
		# каждым claim() → блок обязан вернуть и их, иначе следующие блоки
		# видят чужие визит-дни и очки.
		"visit_days": c6._visit_days.duplicate(true),
		"streak_run": c6._streak_run,
		"last_visit_day": c6._last_visit_day,
		"hearth_claim": c6._hearth_claim,
		"pts_total": c6._pts_total,
		"mdays": c6._mdays,
		"mpts": c6._mpts,
		"unlocked_titles": c6._unlocked_titles.duplicate(true),
		"active_title": c6._active_title,
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
	# доска v2 Task 4: claim() цепляет очаг/вехи — возвращаем и их, иначе
	# фантомные визит-дни утекли бы в сейв-блок и в чужие проверки.
	c6._visit_days = claim_snap["visit_days"]
	c6._streak_run = int(claim_snap["streak_run"])
	c6._last_visit_day = String(claim_snap["last_visit_day"])
	c6._hearth_claim = String(claim_snap["hearth_claim"])
	c6._pts_total = int(claim_snap["pts_total"])
	c6._mdays = int(claim_snap["mdays"])
	c6._mpts = int(claim_snap["mpts"])
	c6._unlocked_titles = claim_snap["unlocked_titles"]
	c6._active_title = String(claim_snap["active_title"])
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
	# доска v2 Task 6 (спека §6): сейв v5, блок contracts v2 и presence-миграция
	# старых retention-ключей — свой блок со своими путями сейва и откатом.
	_cb_save_v5_checks(g)

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

	# 8. Закрытие доски — подписанная кнопка, а не безымянное кольцо: владелец
	# не понял, как закрыть доску (баг 2026-10-20).
	var close_btn: Button = board.get_node_or_null("Close") as Button
	Selftest.check("§5.2 the board closes with a labeled button, not an unlabeled ring",
		close_btn != null and close_btn.text.contains("Закрыть")
		and close_btn.tooltip_text != ""
		and board.get_node_or_null("Ring") == null)

	# 8b. §C (спека 2026-10-25): кнопки доски одеты в латунную плашку. Жёлтый
	# `UIStyle.style_button(..., 2)` даёт StyleBoxFlat, поэтому «normal — это
	# StyleBoxTexture с plate_brass.png» краснеет и от возврата к теме, и от
	# плашки без текстуры. Числа в хелпере литеральные, не константы ContractBoard:
	# понижать поле в коде — это решение, а пин обязан его заметить.
	var t8b_hearth: Button = board.get("_hearth_btn") as Button
	Selftest.check("§C the board's close button is sawn in the brass plate",
		_plate_state(close_btn) == "")
	Selftest.check("§C the board's hearth button is sawn in the brass plate",
		_plate_state(t8b_hearth) == "")

	# 9. Доска v2: восемь карточек — 4 daily + 4 weekly (было 3+2).
	var dr: Control = board.get_node_or_null("DailyRow") as Control
	var wr: Control = board.get_node_or_null("WeeklyRow") as Control
	var daily_card_count := dr.get_child_count() if dr != null else 0
	var weekly_card_count := wr.get_child_count() if wr != null else 0
	Selftest.check("§5.2 the board creates eight cards (4 daily + 4 weekly)",
		daily_card_count == 4 and weekly_card_count == 4)

	# 10. Ряды — обычные Control, не контейнеры.
	Selftest.check("§5.2 daily and weekly rows are plain Controls, not containers",
		dr != null and wr != null and dr.get_class() == "Control" and wr.get_class() == "Control")

	# 10b. Доска v2 (Task 7, спека §5): состав экрана — 4 карточки на полку,
	# полка очага под дневным рядом, строка ранга внизу.
	var t7_daily_cards := dr.get_child_count() if dr != null else 0
	var t7_weekly_cards := wr.get_child_count() if wr != null else 0
	Selftest.check("board v2 renders four cards per shelf with hearth shelf and rank strip",
		t7_daily_cards == 4 and t7_weekly_cards == 4 and board != null
		and board.get_node_or_null("ShelfHearth") != null
		and board.get_node_or_null("RankStrip") != null)

	# 10c. Task 7: _place — wrapping-сетка: при ширине ровно на 4 карточки
	# пятая уходит на вторую линию, а высота ряда растёт. Проверка статической
	# функции на фикстурном ряду: явные size/position, без зависимости от
	# layout-проходов headless-прогона.
	var t7_wrap_row := Control.new()
	t7_wrap_row.size = Vector2(420, 50)
	for i in range(5):
		t7_wrap_row.add_child(Control.new())
	ContractBoard._place(t7_wrap_row, Vector2(100, 50))
	var t7_wrap_ok := absf(t7_wrap_row.size.y - 108.0) < 0.01 \
		and (t7_wrap_row.get_child(0) as Control).position == Vector2(4, 0) \
		and (t7_wrap_row.get_child(3) as Control).position == Vector2(316, 0) \
		and (t7_wrap_row.get_child(4) as Control).position == Vector2(160, 58)
	t7_wrap_row.free()
	Selftest.check("board v2 wrapping _place puts the fifth card on a centered second row",
		t7_wrap_ok)

	# 10d. Полка очага: кнопка «Полешко: +N ⚡» и пламя серии (✦✦ при 3).
	c._hearth_claim = ""
	c._streak_run = 3
	board.refresh()
	await g.get_tree().process_frame
	var t7_shelf := board.get_node_or_null("ShelfHearth")
	var t7_hearth_btn: Button = null
	var t7_flame_lbl: Label = null
	if t7_shelf != null:
		t7_hearth_btn = t7_shelf.find_child("HearthBtn", true, false) as Button
		t7_flame_lbl = t7_shelf.find_child("HearthFlame", true, false) as Label
	var t7_claimable := t7_hearth_btn != null and not t7_hearth_btn.disabled \
		and t7_hearth_btn.text == "Полешко: +%d ⚡" % c.hearth_reward() \
		and t7_flame_lbl != null and t7_flame_lbl.text == c.flame()
	Selftest.check("board v2 hearth shelf offers the daily log with the streak flame",
		t7_claimable)

	# 10e. Полка очага после дневного забора: кнопка гаснет и называется «Забрано ✓».
	# Task 9 (T7 minor 1): пин disabled==true — «Забрано ✓» без гашения кнопка
	# обещала бы второй забор; краснеет на удалении _hearth_btn.disabled в
	# contract_board.gd (_refresh_hearth), т.к. Button.disabled по умолчанию false.
	c._hearth_claim = Time.get_date_string_from_system()
	board.refresh()
	await g.get_tree().process_frame
	var t7_claimed_txt := t7_hearth_btn != null and t7_hearth_btn.text == "Забрано ✓" \
		and t7_hearth_btn.disabled
	Selftest.check("board v2 hearth shelf shows «Забрано ✓» after today's log",
		t7_claimed_txt)
	c._hearth_claim = ""
	c._streak_run = 0

	# 10f. Строка ранга: символ + титул + два бумажных свитка вех (спека §5 —
	# иммерсивныеPaper-ленты, не Label-простыня).
	c._visit_days = ["2026-09-10"]
	c._mdays = 1
	c._mpts = 1
	c._pts_total = 50
	board.refresh()
	await g.get_tree().process_frame
	var t7_strip := board.get_node_or_null("RankStrip")
	var t7_sym: Node = null
	var t7_title: Label = null
	var t7_md: Node = null
	var t7_mp: Node = null
	if t7_strip != null:
		t7_sym = t7_strip.find_child("RankSymbol", true, false)
		t7_title = t7_strip.find_child("RankTitle", true, false) as Label
		t7_md = t7_strip.find_child("MileDays", true, false)
		t7_mp = t7_strip.find_child("MilePts", true, false)
	var t7_mile_days := ""
	var t7_mile_pts := ""
	if t7_md != null:
		var l1 := (t7_md as Node).find_child("Word", true, false) as Label
		t7_mile_days = l1.text if l1 != null else ""
	if t7_mp != null:
		var l2 := (t7_mp as Node).find_child("Word", true, false) as Label
		t7_mile_pts = l2.text if l2 != null else ""
	var t7_rank_ok := t7_strip != null and t7_sym is CircleRankSymbol and t7_title != null \
		and t7_title.text == c.rank_title(c.rank_level()) \
		and t7_mile_days.contains(c.mile_strip("дней", Game.CIRCLE_DAY_MILES, 1)) \
		and t7_mile_pts.contains(c.mile_strip("очков", Game.CIRCLE_PTS_MILES, 1))
	Selftest.check("board v2 rank strip carries symbol, title and two mile scrolls",
		t7_rank_ok)

	# 10g. Тела карточек goal_day/vein/fair (спека §5): цель дня строкой
	# «свари …» + хинт мира в tooltip, ряды капель текущего цикла с кнопкой
	# «Влить», строка котла fair.
	var t7_hint_saved := c.day_hint()
	var t7_finds_saved: Array = c._vein_finds.duplicate(true)
	var t7_cycle_saved: Dictionary = c._cycle_cache.duplicate(true)
	c._day_hint = "из двух баз"
	c._cycle_cache = {"cycle_id": "t7-cyc"}
	c._vein_finds = [
		{"id": "t7-f1", "tag": "Тег", "points": 1, "pair_key": "t7a+t7b",
			"cycle_id": "t7-cyc", "status": "registered"},
		{"id": "t7-f2", "tag": "Тег", "points": 1, "pair_key": "t7c+t7d",
			"cycle_id": "t7-cyc", "status": "pending_server"},
		{"id": "t7-old", "tag": "Тег", "points": 1, "pair_key": "t7e+t7f",
			"cycle_id": "t7-other", "status": "registered"},
	]
	c._fair_local_week = Home._iso_week_id()
	c._fair_local_brews = ["steam", "glass"]
	var t7_lg := c._local_goal()
	_force_set(c, [
		_mk(c, "daily", "goal_day", "bronze", 1),
		_mk(c, "daily", "brew", "bronze", 15),
		_mk(c, "daily", "discover", "silver", 1),
		_mk(c, "daily", "chain_brew", "silver", 2),
	], [
		_mk(c, "weekly", "vein", "bronze", 1),
		_mk(c, "weekly", "fair", "bronze", 3),
		_mk(c, "weekly", "upgrade", "silver", 4),
		_mk(c, "weekly", "rare_brew", "bronze", 3),
	])
	board.refresh()
	await g.get_tree().process_frame
	var t7_goal_card: Control = dr.get_child(0) as Control
	var t7_goal_detail := t7_goal_card.get_node_or_null("Hang/Detail") as Control
	var t7_goal_line := ""
	var t7_goal_tip := ""
	if t7_goal_detail != null:
		for ch in t7_goal_detail.get_children():
			if ch is Label and String((ch as Label).text).begins_with("свари"):
				t7_goal_line = String((ch as Label).text)
				t7_goal_tip = String((ch as Label).tooltip_text)
	var t7_goal_want := "свари «%s» из %s и %s" % [
		g._online._item_name(String(t7_lg.get("out", ""))),
		g._online._item_name(String(t7_lg.get("a", ""))),
		g._online._item_name(String(t7_lg.get("b", "")))]
	Selftest.check("goal_day card body states the local goal line and the world hint tooltip",
		t7_goal_line == t7_goal_want and t7_goal_want != "свари «» из и " \
		and t7_goal_tip.contains("мир: из двух баз"))

	# Жила: ровно по ряду капель на находку ТЕКУЩЕГО цикла (старый цикл — мимо),
	# у registered — кнопка «Влить».
	var t7_vein_card: Control = wr.get_child(0) as Control
	var t7_vein_detail := t7_vein_card.get_node_or_null("Hang/Detail") as Control
	var t7_drop_rows := 0
	var t7_pour_btns := 0
	if t7_vein_detail != null:
		for ch in t7_vein_detail.get_children():
			if String((ch as Node).name).begins_with("VeinDropRow"):
				t7_drop_rows += 1
		for b in t7_vein_detail.find_children("*", "Button", true, false):
			if String((b as Button).text) == "Влить":
				t7_pour_btns += 1
	Selftest.check("vein card exposes one VeinDropRow per current-cycle find plus a pour button",
		t7_drop_rows == 2 and t7_pour_btns == 1)

	# Ярмарка: строка котла — ровно fair_pot_line(), офлайн-вариант виден текстом.
	var t7_fair_card: Control = wr.get_child(1) as Control
	var t7_fair_lbl: Label = null
	var t7_fair_detail := t7_fair_card.get_node_or_null("Hang/Detail") as Control
	if t7_fair_detail != null:
		t7_fair_lbl = t7_fair_detail.find_child("FairPot", true, false) as Label
	Selftest.check("fair card body shows the pot line from fair_pot_line()",
		t7_fair_lbl != null and t7_fair_lbl.text == c.fair_pot_line()
		and t7_fair_lbl.text == "Локальный котёл: 2/3")

	# 10i. Task 9 (T7 minor 4): онлайн-формат fair_pot_line() «Котёл: prog/goal ·
	# твоих: N» — не локальная строка. Сеть поднимается фикстурой (тот же приём,
	# что в t3_env выше), серверный котёл — _week_cache, всё откатывается.
	# Краснеет на удалении онлайн-ветки fair_pot_line (contracts.gd) или клампа
	# mini(prog, goal), и на подмене строки карточки локальным форматом.
	var t9_week_saved: Dictionary = c._week_cache.duplicate(true)
	var t9_env := {
		"net": g._online._net_enabled, "avail": Net.is_available(),
		"dev": g._online._device_id,
	}
	g._online._net_enabled = true
	Net._available = true
	g._online._device_id = "t9-dev"
	c._week_cache = {"fair": {"progress": 5, "apprentice": 2, "goal": 12, "my_contrib": 3}}
	var t9_fair_line := c.fair_pot_line()
	c._week_cache = {"fair": {"progress": 9, "apprentice": 4, "goal": 12, "my_contrib": 3}}
	var t9_fair_clamped := c.fair_pot_line()
	c._week_cache = {"fair": {"progress": 5, "apprentice": 2, "goal": 12, "my_contrib": 3}}
	board.refresh()
	await g.get_tree().process_frame
	var t9_fair_lbl2: Label = null
	var t9_fair_detail2 := (wr.get_child(1) as Control).get_node_or_null("Hang/Detail") as Control
	if t9_fair_detail2 != null:
		t9_fair_lbl2 = t9_fair_detail2.find_child("FairPot", true, false) as Label
	Selftest.check("fair_pot_line() prints the server pot «Котёл: prog/goal · твоих: N» onto the fair card",
		t9_fair_line == "Котёл: 7/12 · твоих: 3" and t9_fair_clamped == "Котёл: 12/12 · твоих: 3"
		and t9_fair_lbl2 != null and t9_fair_lbl2.text == "Котёл: 7/12 · твоих: 3")
	g._online._net_enabled = bool(t9_env["net"])
	Net._available = bool(t9_env["avail"])
	g._online._device_id = String(t9_env["dev"])
	c._week_cache = t9_week_saved

	# 10j. Task 9 (T7 minor 4): сверх трёх рядов капель текущего цикла карточка
	# жилы сворачивает остаток в «…ещё N». Краснеет на удалении ветки
	# `if rows.size() > shown` в contract_card.gd::_fill_vein.
	var t9_more: Array = []
	var t9_st: Array = ["registered", "registered", "poured", "pending_server", "auto_applied"]
	for t9_i in range(5):
		t9_more.append({"id": "t9-f%d" % t9_i, "tag": "Тег", "points": 1,
			"pair_key": "t9a+t9b", "cycle_id": "t9-cyc", "status": String(t9_st[t9_i])})
	c._cycle_cache = {"cycle_id": "t9-cyc"}
	c._vein_finds = t9_more
	board.refresh()
	await g.get_tree().process_frame
	var t9_vein_detail := (wr.get_child(0) as Control).get_node_or_null("Hang/Detail") as Control
	var t9_rows := 0
	var t9_more_lbl := ""
	if t9_vein_detail != null:
		for t9_ch in t9_vein_detail.get_children():
			if String((t9_ch as Node).name).begins_with("VeinDropRow"):
				t9_rows += 1
			elif t9_ch is Label and String((t9_ch as Label).text).begins_with("…ещё"):
				t9_more_lbl = String((t9_ch as Label).text)
	Selftest.check("vein card folds the fourth and fifth current-cycle finds into «…ещё N»",
		t9_rows == 3 and t9_more_lbl == "…ещё 2")
	c._day_hint = t7_hint_saved
	c._vein_finds = t7_finds_saved
	c._cycle_cache = t7_cycle_saved

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

	# 17. Доска v2: все восемь карточек заполняются контрактами при refresh
	# (фикстура ряда 3/2→4/4).
	_force_set(c, [
		_mk(c, "daily", "brew", "bronze", 15),
		_mk(c, "daily", "experiment", "silver", 2),
		_mk(c, "daily", "depth_brew", "gold", 3),
		_mk(c, "daily", "discover", "bronze", 1),
	], [
		_mk(c, "weekly", "sigil_set", "gold", 4),
		_mk(c, "weekly", "variety", "bronze", 8),
		_mk(c, "weekly", "upgrade", "silver", 4),
		_mk(c, "weekly", "rare_brew", "bronze", 3),
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
	Selftest.check("§5.2 all eight cards are visible when eight contracts are present",
		all_vis and total_cards == 8)

	# 18. Дневные контракты — в дневном ряду, недельные — в недельном
	# (доска v2: ряд 3/2→4/4, условие названо литералом).
	var daily_count := 0
	var weekly_count := 0
	for ch in dr.get_children():
		if (ch as Control).visible:
			daily_count += 1
	for ch in wr.get_children():
		if (ch as Control).visible:
			weekly_count += 1
	Selftest.check("§5.2 daily cards sit in the daily row and weekly cards in the weekly row",
		daily_count == 4
		and weekly_count == 4)

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
		# §C: та же латунная плашка на единственной кнопке попапа (проверяется ДО
		# onжатия: press закрывает доску награды вместе с кнопкой).
		Selftest.check("§C the reward popup's OK button is sawn in the brass plate",
			_plate_state(pop_ok_btn) == "")
		if pop_ok_btn != null:
			pop_ok_btn.pressed.emit()
		await g.get_tree().process_frame
		Selftest.check("§5.4 pressing OK closes the reward popup",
			board.get_node_or_null("RewardPopup") == null)

	# --- Точная награда по наведению (Polish 1) ---
	# 20. Строка награды и штамп показывают при наведении точную награду:
	#     бафф называется с процентом силы, а строка ловит мышь.
	var tip_card := dr.get_child(0) as ContractCard
	var tip_c: Dictionary = (c.daily() as Array)[0]
	var r_tip: Dictionary = c.reward_for(tip_c)
	var tip_pct := int(round(100.0 * float(r_tip["power"])))
	var tip_lbl: Label = tip_card.get_node("Hang/Reward") as Label
	var tip_stamp: TextureButton = tip_card.get_node("Hang/Stamp") as TextureButton
	Selftest.check("§5.3 hovering the reward line or stamp states the exact buff power",
		tip_lbl.mouse_filter == Control.MOUSE_FILTER_PASS
		and tip_lbl.tooltip_text.contains("+%d%%" % tip_pct)
		and tip_stamp.tooltip_text.contains("+%d%%" % tip_pct)
		and tip_lbl.tooltip_text.contains(String(ContractsBalance.BUFF_TITLE.get(String(r_tip["buff"]), "нетбаффа"))))

	# 20b. §D: штамп не наезжает на текст. Прямоугольники штампа, тела и награды
	# сравниваются в координатах листа (`_hang`), поэтому поворот бумаги не мешает.
	# Краснеет, если вернуть прежние _stamp.position = h-112 при _reward = h-78:
	# там рамка 132×56 ложилась и на цель, и на награду.
	var stamp_clear := true
	for row in [dr, wr]:
		for ch0 in row.get_children():
			var card0 := ch0 as ContractCard
			if card0 == null:
				continue
			var sr := (card0.get_node("Hang/Stamp") as Control).get_rect()
			for sub in ["Reward", "Detail"]:
				if sr.intersects((card0.get_node("Hang/" + String(sub)) as Control).get_rect()):
					stamp_clear = false
	Selftest.check("§D stamp band does not overlap card text", stamp_clear)

	# 21. Записка активного баффа: наведение показывает название, эффект и силу.
	c.grant_buff("craft_discount", 3600, 0.2, int(Time.get_unix_time_from_system()))
	board.refresh()
	await g.get_tree().process_frame
	var note2: TextureButton = null
	for ch in notes.get_children():
		var nb := ch as TextureButton
		if nb != null and String(nb.get_meta("id")) == "craft_discount":
			note2 = nb
	Selftest.check("§5.4 hovering a buff note states its title, effect and exact power",
		note2 != null and note2.tooltip_text.contains("Дешёвый крафт")
		and note2.tooltip_text.contains("20%"))

	# --- Аутентичные шрифты (Polish 2) ---
	# 22. Вывеска — тот же парадный шрифт, что заголовок шапки, не 15 px Manrope.
	Selftest.check("§5.2 the sign title uses the display face at 17 px or more",
		sign_word.has_theme_font_override("font")
		and int(sign_word.get_theme_font_size("font_size")) >= 17)
	# 23. Бумага: заголовок полужирным 14+, строка награды читаемые 11+.
	var t_lbl: Label = tip_card.get_node("Hang/Title") as Label
	Selftest.check("§5.3 paper titles use the semi-bold face and the reward line is readable",
		t_lbl.has_theme_font_override("font")
		and int(t_lbl.get_theme_font_size("font_size")) >= 14
		and int(tip_lbl.get_theme_font_size("font_size")) >= 11)
	# 24. Попап награды: текст 13+ — игрок читает награду, а не разгадывает.
	board._show_reward(fake_reward)
	var pop2: Control = board.get_node_or_null("RewardPopup")
	var body2: Label = pop2.get_node_or_null("Body") as Label
	Selftest.check("§5.4 the reward popup body is readable at 13 px or more",
		body2 != null and int(body2.get_theme_font_size("font_size")) >= 13)
	board._close_reward()

	# --- Кнопка входа (Polish 3) ---
	# 25. Кнопка доски понижена из ряда шапки в ряд эфира и несёт свою иконку.
	var hb: Button = g._contracts_header_btn
	Selftest.check("§7 the board button lives in the lower row with its own board icon",
		hb != null and hb.get_parent() != null and hb.get_parent().name == "EtherRow"
		and UIIcon.texture("board") != null
		and hb.get_node_or_null("IconCenter/Icon_board") != null)

	# --- Juice Task 4: hover, stamp, board/reward, hearth/rank ---
	# T4-1. Наведение считается по всей бумаге: STOP-потомок (строка награды,
	# тело, штамп) больше не крадёт hover у корня карточки — владелец видел
	# реакцию только на части листа (баг 2026-10-20).
	var t4_card := dr.get_child(0) as ContractCard
	var t4_reward: Label = t4_card.get_node("Hang/Reward") as Label
	var t4_detail: Control = t4_card.get_node("Hang/Detail") as Control
	var t4_line: Control = null
	if t4_detail.get_child_count() > 0:
		t4_line = t4_detail.get_child(0) as Control
	var t4_other: ContractCard = dr.get_child(1) as ContractCard
	Selftest.check("card hover covers every part of the paper, not only the bare root",
		t4_card != null and t4_card.mouse_filter == Control.MOUSE_FILTER_STOP
		and t4_card._covers(t4_card)
		and t4_card._covers(t4_reward)
		and t4_card._covers(t4_card.get_node("Hang/Stamp") as Control)
		and (t4_line == null or t4_card._covers(t4_line))
		and not t4_card._covers(null)
		and not t4_card._covers(t4_other)
		and t4_reward.mouse_filter == Control.MOUSE_FILTER_PASS
		and (t4_line == null or t4_line.mouse_filter == Control.MOUSE_FILTER_PASS))

	# T4-2. Claim with juice disabled shows reward synchronously.
	Juice.enabled = false
	var t4_daily := [_mk(c, "daily", "brew", "bronze", 15)]
	_force_set(c, t4_daily, [])
	_clear_prog(c)
	var t4_id := String(t4_daily[0]["id"])
	c._set_progress(t4_id, 15)
	board.refresh()
	await g.get_tree().process_frame
	var t4_ready_card: ContractCard = dr.get_child(0) as ContractCard
	if t4_ready_card != null:
		var t4_stamp := t4_ready_card.get("_stamp") as TextureButton
		if t4_stamp != null:
			t4_stamp.pressed.emit()
	Selftest.check("claim with juice disabled shows reward synchronously",
		t4_ready_card != null and board._popup != null
		and c.is_done(t4_id))
	board._close_reward()
	_force_set(c, [], [])
	_clear_prog(c)
	Juice.enabled = true

	# T4-3. Claim defers reward while seal settles.
	var t4_daily2 := [_mk(c, "daily", "brew", "bronze", 15)]
	_force_set(c, t4_daily2, [])
	_clear_prog(c)
	var t4_id2 := String(t4_daily2[0]["id"])
	c._set_progress(t4_id2, 15)
	board.refresh()
	await g.get_tree().process_frame
	var t4_ready_card2: ContractCard = dr.get_child(0) as ContractCard
	var t4_deferred := false
	if t4_ready_card2 != null:
		var t4_stamp2 := t4_ready_card2.get("_stamp") as TextureButton
		if t4_stamp2 != null:
			t4_stamp2.pressed.emit()
			t4_deferred = (board._popup == null)
	await g.get_tree().create_timer(ContractBoard.SEAL_HOLD + 0.15).timeout
	Selftest.check("claim defers reward while seal settles",
		t4_deferred and board._popup != null)
	board._close_reward()

	# T4-4. Seal settles stamp to rest pose.
	var t4_stamp_rest := false
	if t4_ready_card2 != null:
		var t4_stamp3 := t4_ready_card2.get("_stamp") as TextureButton
		if t4_stamp3 != null:
			t4_stamp_rest = (t4_stamp3.scale == Vector2.ONE
				and is_equal_approx(t4_stamp3.rotation_degrees, ContractCard.STAMP_TILT))
	Selftest.check("seal settles stamp to rest pose", t4_stamp_rest)
	_force_set(c, [], [])
	_clear_prog(c)

	# T4-5. Reward popup fades in.
	var t4_fake := {
		"ok": true, "reason": "",
		"materials": {"stone": 20, "brick": 10},
		"truncated": false,
		"buff": "brew_speed", "duration": 7200, "power": 0.25,
		"decor": "", "missing_decor": false,
	}
	board._show_reward(t4_fake)
	var t4_pop: Control = board._popup
	var t4_fade_in := false
	if t4_pop != null:
		t4_fade_in = (t4_pop.modulate.a < 1.0)
	await g.get_tree().create_timer(0.35).timeout
	var t4_fade_done := false
	if t4_pop != null:
		t4_fade_done = is_equal_approx(t4_pop.modulate.a, 1.0)
	Selftest.check("reward popup fades in", t4_fade_in and t4_fade_done)
	board._close_reward()

	# T4-6. Hearth claim pops flame.
	c._hearth_claim = ""
	c._streak_run = 3
	c._pts_total = 0
	c._mdays = 0
	c._mpts = 0
	var t4_lvl_before := c.rank_level()
	board.refresh()
	await g.get_tree().process_frame
	var t4_active_before := Juice.active_count()
	var t4_hearth_btn := board.get("_hearth_btn") as Button
	if t4_hearth_btn != null:
		t4_hearth_btn.pressed.emit()
	await g.get_tree().process_frame
	var t4_active_after := Juice.active_count()
	Selftest.check("hearth claim pops flame",
		t4_active_after > t4_active_before
		and c._hearth_claim == Time.get_date_string_from_system())
	c._hearth_claim = ""
	c._streak_run = 0
	c._pts_total = 0
	c._mdays = 0
	c._mpts = 0

	# --- Баг владельца 2026-10-20: клик по бумаге и доступ к нижним рядам ---
	# B1. Клик по любому месту листа закрывает готовый контракт: раньше работал
	# только штамп, и игрок тыкал в бумагу без ответа.
	var b1_daily := [_mk(c, "daily", "brew", "bronze", 15)]
	_force_set(c, b1_daily, [])
	_clear_prog(c)
	var b1_id := String(b1_daily[0]["id"])
	c._set_progress(b1_id, 15)
	board.refresh()
	await g.get_tree().process_frame
	var b1_card: ContractCard = dr.get_child(0) as ContractCard
	Juice.enabled = false
	b1_card._gui_input(_mb(MOUSE_BUTTON_LEFT, true, Vector2(20, 20)))
	b1_card._gui_input(_mb(MOUSE_BUTTON_LEFT, false, Vector2(20, 20)))
	Selftest.check("clicking the paper itself claims a ready contract",
		b1_card != null and c.is_done(b1_id))
	Juice.enabled = true

	# B2. Перетаскивание поверх листа (скролл доски) закрытием не считается.
	var b2_daily := [_mk(c, "daily", "brew", "bronze", 15)]
	_force_set(c, b2_daily, [])
	_clear_prog(c)
	var b2_id := String(b2_daily[0]["id"])
	c._set_progress(b2_id, 15)
	board.refresh()
	await g.get_tree().process_frame
	var b2_card: ContractCard = dr.get_child(0) as ContractCard
	b2_card._gui_input(_mb(MOUSE_BUTTON_LEFT, true, Vector2(20, 20)))
	b2_card._gui_input(_mm(Vector2(20, 64)))
	b2_card._gui_input(_mb(MOUSE_BUTTON_LEFT, false, Vector2(20, 64)))
	Selftest.check("dragging across the paper does not claim the contract",
		b2_card != null and not c.is_done(b2_id))

	# B3. Клик по неготовому контракту ничего не выдаёт. Поппап награды от B1
	# закрываем: иначе `_popup == null` мерил бы не этот клик, а хвост прошлого.
	board._close_reward()
	_clear_prog(c)
	board.refresh()
	await g.get_tree().process_frame
	var b3_card: ContractCard = dr.get_child(0) as ContractCard
	b3_card._gui_input(_mb(MOUSE_BUTTON_LEFT, true, Vector2(20, 20)))
	b3_card._gui_input(_mb(MOUSE_BUTTON_LEFT, false, Vector2(20, 20)))
	Selftest.check("clicking an unfinished contract claims nothing",
		b3_card != null and not c.is_done(b2_id) and board._popup == null)

	# B4. Восемь карточек на 540×960 не влезают в один экран: доска листается,
	# и нижний недельный ряд доезжает до видимой полосы целиком.
	var b4_daily: Array = []
	var b4_weekly: Array = []
	for i in range(4):
		var bd := _mk(c, "daily", "brew", "bronze", 15)
		bd["id"] = String(bd["id"]) + ":b%d" % i
		b4_daily.append(bd)
		var bw := _mk(c, "weekly", "fair", "silver", 3)
		bw["id"] = String(bw["id"]) + ":b%d" % i
		b4_weekly.append(bw)
	_force_set(c, b4_daily, b4_weekly)
	_clear_prog(c)
	board.refresh()
	await g.get_tree().process_frame
	var band_top := ContractBoard.RAIL
	var band_bottom := 960.0 - ContractBoard.RAIL - ContractBoard.RANK_H
	Selftest.check("a full board of eight cards is taller than the view and can be scrolled",
		board._scroll_max > 0.0)
	board._scroll_to(0.0)
	await g.get_tree().process_frame
	var b4_first: Control = dr.get_child(0) as Control
	var b4_first_rect := b4_first.get_global_rect()
	board._scroll_to(board._scroll_max)
	await g.get_tree().process_frame
	var b4_last: Control = wr.get_child(3) as Control
	var b4_last_rect := b4_last.get_global_rect()
	Selftest.check("the first card is reachable at the top and the last weekly card at the bottom",
		b4_first_rect.position.y >= band_top - 0.5
		and b4_first_rect.end.y <= band_bottom + 0.5
		and b4_last_rect.position.y >= band_top - 0.5
		and b4_last_rect.end.y <= band_bottom + 0.5)

	# B5. Колесо мыши листает доску и упирается в края.
	board._scroll_to(0.0)
	board._gui_input(_mb(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(270, 500)))
	var b5_scrolled: bool = board._scroll_y > 0.0
	board._scroll_to(board._scroll_max)
	board._gui_input(_mb(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(270, 500)))
	var b5_clamped_low: bool = is_equal_approx(board._scroll_y, board._scroll_max)
	board._gui_input(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(270, 500)))
	var b5_back: bool = board._scroll_y < board._scroll_max
	board._scroll_to(0.0)
	board._gui_input(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(270, 500)))
	Selftest.check("the mouse wheel scrolls the board and clamps at both ends",
		b5_scrolled and b5_clamped_low and b5_back and board._scroll_y == 0.0)

	# B6. Перетаскивание бумаги листает доску на дельту в координатах окна.
	# Локальная координата здесь дала бы петлю: лист сам уезжает под пальцем,
	# поэтому position и global_position в событиях намеренно разведены.
	board._scroll_to(0.0)
	var b6_card: ContractCard = dr.get_child(0) as ContractCard
	var b6_down := _mb(MOUSE_BUTTON_LEFT, true, Vector2.ZERO)
	b6_down.global_position = Vector2(270, 600)
	b6_card._gui_input(b6_down)
	var b6_move := _mm(Vector2.ZERO)
	b6_move.global_position = Vector2(270, 540)
	b6_card._gui_input(b6_move)
	var b6_want := minf(60.0, board._scroll_max)
	var b6_scrolled: bool = is_equal_approx(board._scroll_y, b6_want)
	var b6_up := _mb(MOUSE_BUTTON_LEFT, false, Vector2.ZERO)
	b6_up.global_position = Vector2(270, 540)
	b6_card._gui_input(b6_up)
	Selftest.check("dragging a paper scrolls the board by the viewport delta, not the local one",
		b6_want > 0.0 and b6_scrolled)
	board._scroll_to(0.0)

	# B7. Уехавшая за раму бумага не кликабельна: маска перехватывает ввод там,
	# где её закрывают рельс и строка ранга.
	var b7_top: Control = board.get_node_or_null("MaskTop") as Control
	var b7_bottom: Control = board.get_node_or_null("MaskBottom") as Control
	Selftest.check("paper scrolled out of view cannot be clicked behind the frame",
		b7_top != null and b7_bottom != null
		and b7_top.mouse_filter == Control.MOUSE_FILTER_STOP
		and b7_bottom.mouse_filter == Control.MOUSE_FILTER_STOP
		and b7_top.get_global_rect().end.y <= band_top + 0.5
		and absf(b7_bottom.get_global_rect().position.y - band_bottom) <= 0.5)
	board._scroll_to(0.0)
	_force_set(c, [], [])
	_clear_prog(c)

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

	# Task 9 (T8 minor A): boardfull-заморозка гейтит единственную точку записи —
	# прогон boardfull-демо не должен писать инъектированное состояние в сейв.
	# Фикстура флагов — сам demo-harness (в selftest он поднят, --demo=false);
	# путь сейва здесь уже переведён на alchemy_st_contracts_dur.json, реальный
	# пользовательский файл не трогается. Краснеет на удалении гейта
	# _boardfull_frozen() в Saves._save_game.
	var t9_h := g._demo_harness
	var t9_demo_saved: bool = t9_h._demo
	var t9_state_saved: String = t9_h._contract_state
	var t9_rev := g._engine.client_rev
	t9_h._demo = true
	t9_h._contract_state = "boardfull"
	var t9_blocked := g._saves._save_game()
	var t9_rev_blocked := g._engine.client_rev
	t9_h._contract_state = "pop"
	var t9_allowed := g._saves._save_game()
	t9_h._demo = t9_demo_saved
	t9_h._contract_state = t9_state_saved
	g._engine.client_rev = t9_rev
	Selftest.check("boardfull freeze gate blocks Saves._save_game at the single write point",
		not t9_blocked and t9_allowed and t9_rev_blocked == t9_rev)

	var now_u := int(Time.get_unix_time_from_system())
	var day_key := Contracts.day_key_from(c._dt({}))
	var week_key := Contracts.week_key_from(c._dt({}))
	# Доска v2: _clean_list требует размер ряда == SHOWN (4/4, было 3/2),
	# поэтому фикстуры рядов — по четыре легальных контракта разных типов.
	var d_brew := _mk_legal(c, "daily", "brew", "bronze")
	var d_disc := _mk_legal(c, "daily", "discover", "silver")
	var d_gold := _mk_legal(c, "daily", "sigil_craft", "gold")
	var d_chain := _mk_legal(c, "daily", "chain_brew", "silver")
	var w_pre := _mk_legal(c, "weekly", "prestige", "gold")
	var w_up := _mk_legal(c, "weekly", "upgrade", "bronze")
	var w_var := _mk_legal(c, "weekly", "variety", "bronze")
	var w_sig := _mk_legal(c, "weekly", "sigil_set", "silver")
	var daily_set: Array = [d_brew, d_disc, d_gold, d_chain]
	var weekly_set: Array = [w_pre, w_up, w_var, w_sig]
	var id_brew := String(d_brew["id"])
	var id_disc := String(d_disc["id"])
	var id_gold := String(d_gold["id"])
	var id_chain := String(d_chain["id"])
	var id_pre := String(w_pre["id"])
	var id_up := String(w_up["id"])
	var gold_goal := int((ContractsBalance.DAILY_GOALS["sigil_craft"] as Array)[2])

	# ---- 1. форма блока ----
	var shape := c.save_block()
	var names: Array = shape.keys()
	names.sort()
	# доска v2 Task 6 (спека §6): к четырёмнадцати ключам §4.1 добавлены семнадцать
	# мигрированных полей (круг/ярмарка/жила) — circle_last в блоке нет.
	var expect: Array = ["active_title", "buffs", "cycle_cache", "daily", "daily_done",
		"daily_prog", "day_hint", "decor", "fair_local_brews", "fair_local_week",
		"fair_off_claim_week", "fair_regen_total", "hearth_claim", "last_daily",
		"last_output", "last_weekly", "mdays", "mpts", "pts_total", "set_week",
		"streak_run", "unlocked_titles", "variety", "vein_cap_total", "vein_finds",
		"version", "visit_days", "week_cache", "weekly", "weekly_done", "weekly_prog"]
	expect.sort()
	Selftest.check("§4.2 save_block carries exactly the thirty-one state keys (§4.1 + §6)",
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
	# Доска v2: ряд 3/2→4/4 — список id фикстуры и размер недельного ряда
	# названы литералами.
	Selftest.check("§6.16 the saved lists survive verbatim instead of a re-roll at boot",
		ids == [id_brew, id_disc, id_gold, id_chain]
		and int(c._contracts_daily[2]["goal"]) == gold_goal
		and String(c._contracts_daily[2]["buff"]) == "brew_speed"
		and c.progress(id_gold) == 2 and c._contracts_weekly.size() == 4)
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
		# доска v2: размер regenerated-ряда 3/2→4/4, условие названо литералом.
		and c.daily().size() == 4
		and c.weekly().size() == 4
		and c._contracts_last_daily == day_key)

	# ---- 4. фильтрация по осям и по ключам (§4.4) ----
	# Битый только goal у одного дневного контракта: роняет дневную ось целиком,
	# недельная с её журналом обязана пережить загрузку.
	var d_bad := _mk_legal(c, "daily", "brew", "silver")
	d_bad["goal"] = int(d_bad["goal"]) + 1
	var bad_id := String(d_bad["id"])
	_cb_wipe(c)
	# Доска v2: дневная фикстура — те же 4 ряда (было 3), чтобы список отвергался
	# именно битым goal, а не размером; недельный ряд 2→4.
	_force_set(c, [d_bad, d_disc, d_gold, d_chain], weekly_set)
	c._contracts_daily_prog[bad_id] = 2
	c._contracts_weekly_done[id_pre] = true
	c._contracts_weekly_prog[id_up] = 1
	g._saves._save_game()
	_cb_wipe(c)
	g._saves._load_game()
	Selftest.check("§4.4 a structurally broken daily list resets only the daily axis",
		c._contracts_daily.is_empty() and c._contracts_last_daily == ""
		and c._contracts_daily_prog.is_empty()
		and c._contracts_weekly.size() == 4 and c._contracts_weekly_done.has(id_pre)
		and int(c._contracts_weekly_prog.get(id_up, -1)) == 1)
	# доска v2: regenerated-ряд 3→4, условие названо литералом.
	Selftest.check("§4.4 after the dropped axis the board regenerates today, not an empty slate",
		c.daily().size() == 4
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

# доска v2 Task 6 (спека §6): сейв v5, блок contracts v2 и однократная
# presence-миграция старых retention-ключей. Сюита красная, пока миграция —
# заглушка: поля после вызова остаются дефолтными, файл после пересохранения
# несёт старые ключи, а блок — версию 1.
static func _cb_clear_migrated(c: Contracts) -> void:
	# Принудительные дефолты переехавших полей средствами сюиты: в RED-фазе
	# _clear_state их не чистит, и проверки обязаны краснеть поведением миграции,
	# а не случайным остатком живого состояния.
	c._visit_days = []
	c._streak_run = 0
	c._last_visit_day = ""
	c._hearth_claim = ""
	c._pts_total = 0
	c._mdays = 0
	c._mpts = 0
	c._unlocked_titles = []
	c._active_title = ""
	c._day_hint = ""
	c._week_cache = {}
	c._cycle_cache = {}
	c._vein_finds = []
	c._vein_cap_total = 0
	c._fair_regen_total = 0.0
	c._fair_local_week = ""
	c._fair_local_brews = []
	c._fair_off_claim_week = ""

static func _cb_save_v5_checks(g: Game) -> void:
	var c := g._contracts
	var migrated_keys := ["streak_run", "visit_days", "hearth_claim", "pts_total",
		"mdays", "mpts", "unlocked_titles", "active_title", "day_hint", "week_cache",
		"cycle_cache", "vein_finds", "vein_cap_total", "fair_regen_total",
		"fair_local_week", "fair_local_brews", "fair_off_claim_week"]
	var legacy_keys := ["circle_days", "circle_run", "circle_last", "hearth_claim",
		"circle_pts_total", "circle_mdays", "circle_mpts", "circle_hint",
		"unlocked_titles", "active_title", "week_cache", "cycle_cache",
		"vein_cap_total", "vein_pending_finds", "fair_regen_total", "fair_local_week",
		"fair_local_brews", "fair_off_claim_week"]
	# --- снимки живого мира; откат в конце — образец _contracts_durability_checks ---
	var saved_paths: Array = [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]
	var saved_frozen := g._saves._save_frozen
	var saved_last_ts := g._last_ts
	var saved_state := _cb_snapshot(c)
	var saved_week := {
		"week_cache": c._week_cache, "cycle_cache": c._cycle_cache,
		"vein_finds": c._vein_finds, "vein_cap": c._vein_cap_total,
		"regen": c._fair_regen_total, "local_week": c._fair_local_week,
		"local_brews": c._fair_local_brews, "off_claim": c._fair_off_claim_week,
		"last_visit_day": c._last_visit_day,
	}
	var saved_crafts: Array = g._sigil._daily_crafts.duplicate(true)
	var saved_status := g._engine.status_text
	for path in saved_paths:
		if FileAccess.file_exists(String(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(path)))
	g.SAVE_PATH = "user://alchemy_st_cb_v5.json"
	g.TEMP_PATH = "user://alchemy_st_cb_v5.tmp"
	g.BACKUP_PATH = "user://alchemy_st_cb_v5.bak"
	g._saves._save_frozen = false
	var baseline_written := g._saves._save_game()
	var baseline_data := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("save v5 fixture baseline save written",
		baseline_written and not baseline_data.is_empty())

	# ---- 1. миграция прямым вызовом: фикстура = полный валидный сейв ----
	# (собирается из baseline_data, т.е. из вывода _save_game(): version 4 +
	# сохранённые inventory/ether/unknown-гейты; без этого _read_save отбрасывает
	# файл до миграции и проверка была бы зелёной на пустом месте).
	var mig := baseline_data.duplicate(true)
	mig["version"] = 4
	mig["circle_days"] = ["2026-10-18"]
	mig["circle_run"] = 3
	mig["circle_last"] = "2026-10-18"
	mig["hearth_claim"] = ""
	mig["circle_pts_total"] = 61
	mig["circle_mdays"] = 1
	mig["circle_mpts"] = 1
	mig["circle_hint"] = "Мох"
	mig["unlocked_titles"] = ["Искра"]
	mig["active_title"] = "Искра"
	mig["week_cache"] = {"week": "2026-W42"}
	mig["cycle_cache"] = {"cycle_id": "vc:m"}
	mig["vein_cap_total"] = 2
	mig["vein_pending_finds"] = []
	mig["fair_regen_total"] = 0.05
	mig["fair_local_week"] = "2026-W42"
	mig["fair_local_brews"] = ["a"]
	mig["fair_off_claim_week"] = ""
	c._clear_state()
	_cb_clear_migrated(c)
	var cap_before := g._engine._max_ether()
	g._saves._migrate_retention_into_contracts(mig)
	Selftest.check("migration v4→v5 moves retention into contracts",
		c._streak_run == 3 and c._visit_days == ["2026-10-18"]
		and c._pts_total == 61 and c._vein_cap_total == 2
		and absf(c._fair_regen_total - 0.05) < 0.0001
		and c._day_hint == "Мох")
	# Веха дней 7 даёт +5 капа, веха очков 50 — +3, vein_cap_total — +2: вместе +10.
	# Заодно доказывает, что миграция присвоила mdays/mpts из файла.
	Selftest.check("migration keeps cap/regen numbers",
		g._engine._max_ether() == cap_before + 10)
	# circle_last не персистится — миграция выводит день из visit_days;
	# _migrate_missed_milestones обязана отработать на присвоенных числах.
	Selftest.check("migration re-derives circle_last and grants missed milestones",
		c._last_visit_day == "2026-10-18" and c._mdays == 1 and c._mpts == 1
		and c._week_cache == {"week": "2026-W42"} and c._cycle_cache == {"cycle_id": "vc:m"}
		and c._fair_local_week == "2026-W42" and c._fair_local_brews == ["a"]
		and c._unlocked_titles.has("Искра") and c._unlocked_titles.has("Тлеющий"))
	# presence-гейт (не version-гейт): после миграции ключи не пишутся — повторный
	# прогон на свежем сейве обязан быть no-op.
	c._clear_state()
	_cb_clear_migrated(c)
	c._streak_run = 9
	g._saves._migrate_retention_into_contracts(baseline_data)
	Selftest.check("migration without legacy keys is a presence-gated no-op",
		c._streak_run == 9)
	c._streak_run = 0

	# ---- 2. интеграция: v4-файл целиком проходит через _load_game ----
	c._clear_state()
	_cb_clear_migrated(c)
	var mf := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	mf.store_string(JSON.stringify(mig, "\t", true, true))
	mf.close()
	g._saves._load_game()
	Selftest.check("save v4 file loads and migrates through _load_game",
		c._streak_run == 3 and c._visit_days == ["2026-10-18"] and c._day_hint == "Мох"
		and c._vein_cap_total == 2 and absf(c._fair_regen_total - 0.05) < 0.0001
		and c._last_visit_day == "2026-10-18")
	g._saves._save_game()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(g.SAVE_PATH))
	var raw: Dictionary = parsed if parsed is Dictionary else {}
	var blk: Dictionary = raw.get("contracts", {}) if raw.get("contracts", {}) is Dictionary else {}
	var legacy_gone := int(raw.get("version", 0)) == Game.SAVE_VERSION
	for k in legacy_keys:
		if raw.has(String(k)):
			legacy_gone = false
	# server_tags — ключ Online, не retention: обязан остаться на верхнем уровне.
	Selftest.check("resave after migration writes v5 without legacy keys",
		legacy_gone and raw.has("server_tags") and not raw.has("circle_last"))
	Selftest.check("resave carries block v2 with the migrated keys",
		int(blk.get("version", 0)) == 2 and int(blk.get("streak_run", -1)) == 3
		and blk.get("visit_days") == ["2026-10-18"] and String(blk.get("day_hint", "")) == "Мох"
		and int(blk.get("vein_cap_total", -1)) == 2
		and not blk.has("circle_last") and not blk.has("last_visit_day"))
	# Второй заход: ключей нет — состояние целиком из блока v2, миграция не нужна.
	c._clear_state()
	_cb_clear_migrated(c)
	g._saves._load_game()
	Selftest.check("second load restores migrated fields from block v2",
		c._streak_run == 3 and c._visit_days == ["2026-10-18"] and c._pts_total == 61
		and c._mdays == 1 and c._mpts == 1 and c._day_hint == "Мох"
		and c._vein_cap_total == 2 and absf(c._fair_regen_total - 0.05) < 0.0001
		and c._last_visit_day == "2026-10-18" and c._unlocked_titles.has("Искра"))

	# ---- 3. форма блока v2: ключи, round-trip, дефолты версии 1 ----
	var p1 := Contracts.new(g)
	p1.ensure_period()
	p1._visit_days = ["2026-10-18"]
	p1._streak_run = 3
	p1._last_visit_day = "2026-10-18"
	p1._hearth_claim = "2026-10-17"
	p1._pts_total = 61
	p1._mdays = 1
	p1._mpts = 1
	p1._unlocked_titles = ["Искра"]
	p1._active_title = "Искра"
	p1._day_hint = "Мох"
	p1._week_cache = {"week": "2026-W42"}
	p1._cycle_cache = {"cycle_id": "vc:m"}
	p1._vein_finds = [{"id": "f-1", "tag": "Мох"}]
	p1._vein_cap_total = 2
	p1._fair_regen_total = 0.05
	p1._fair_local_week = "2026-W42"
	p1._fair_local_brews = ["a"]
	p1._fair_off_claim_week = ""
	var v2blk := p1.save_block()
	var has_all := int(v2blk.get("version", 0)) == 2 and not v2blk.has("last_visit_day")
	for k in migrated_keys:
		if not v2blk.has(String(k)):
			has_all = false
	Selftest.check("contracts block v2 carries the seventeen migrated keys and no circle_last",
		has_all)
	# duplicate(true): мутация источника не должна протекать в записанный блок.
	p1._visit_days.append("2999-12-31")
	(p1._week_cache as Dictionary)["week"] = "mut"
	(p1._vein_finds[0] as Dictionary)["id"] = "mut"
	p1._unlocked_titles.append("Мусор")
	var p2 := Contracts.new(g)
	p2.load_block(v2blk)
	Selftest.check("v2 block round-trips every migrated field and re-derives last visit",
		p2._streak_run == 3 and p2._visit_days == ["2026-10-18"]
		and p2._hearth_claim == "2026-10-17" and p2._pts_total == 61
		and p2._mdays == 1 and p2._mpts == 1 and p2._unlocked_titles == ["Искра"]
		and p2._active_title == "Искра" and p2._day_hint == "Мох"
		and p2._week_cache == {"week": "2026-W42"} and p2._cycle_cache == {"cycle_id": "vc:m"}
		and p2._vein_finds.size() == 1
		and String((p2._vein_finds[0] as Dictionary)["id"]) == "f-1"
		and p2._vein_cap_total == 2 and absf(p2._fair_regen_total - 0.05) < 0.0001
		and p2._fair_local_week == "2026-W42" and p2._fair_local_brews == ["a"]
		and p2._last_visit_day == "2026-10-18")
	# Версия 1 принимается (§4.3 1..CONTRACTS_SAVE_VERSION): оси читаются, новых
	# полей в блоке нет → дефолты, а не падение и не дроп блока.
	var v1blk := v2blk.duplicate(true)
	v1blk["version"] = 1
	for k in migrated_keys:
		v1blk.erase(String(k))
	var p3 := Contracts.new(g)
	p3._streak_run = 9
	p3._day_hint = "остаток"
	p3.load_block(v1blk)
	Selftest.check("a version-1 block still loads its axes and leaves migrated fields default",
		p3._contracts_daily.size() == 4 and p3._contracts_weekly.size() == 4
		and p3._streak_run == 0 and p3._visit_days.is_empty() and p3._day_hint == ""
		and p3._week_cache.is_empty() and p3._vein_finds.is_empty()
		and p3._fair_regen_total == 0.0 and p3._last_visit_day == "")

	# ---- 4. новая игра (§6): reset_new_game чистит и переехавшие поля ----
	c._streak_run = 3
	c._day_hint = "Мох"
	c._vein_cap_total = 2
	c._week_cache = {"week": "w"}
	c._fair_regen_total = 0.05
	c._visit_days = ["2026-10-18"]
	var reset_ok := g._init_new_game()
	Selftest.check("§6.19 new game wipes every migrated retention field too",
		reset_ok and c._streak_run == 0 and c._visit_days.is_empty()
		and c._day_hint == "" and c._vein_cap_total == 0 and c._week_cache.is_empty()
		and c._cycle_cache.is_empty() and c._vein_finds.is_empty()
		and c._fair_regen_total == 0.0 and c._fair_local_week == ""
		and c._fair_local_brews.is_empty() and c._fair_off_claim_week == ""
		and c._hearth_claim == "" and c._pts_total == 0 and c._mdays == 0
		and c._mpts == 0 and c._unlocked_titles.is_empty() and c._active_title == ""
		and c._last_visit_day == "")

	# ---- откат: мир возвращается настоящим _load_game() из baseline-сейва ----
	var restore_world := baseline_data.duplicate(true)
	restore_world.erase("contracts")
	_cb_put_block_restore(g, restore_world)
	g._saves._load_game()
	_cb_restore(c, saved_state)
	c._week_cache = saved_week["week_cache"]
	c._cycle_cache = saved_week["cycle_cache"]
	c._vein_finds = saved_week["vein_finds"]
	c._vein_cap_total = int(saved_week["vein_cap"])
	c._fair_regen_total = float(saved_week["regen"])
	c._fair_local_week = String(saved_week["local_week"])
	c._fair_local_brews = saved_week["local_brews"]
	c._fair_off_claim_week = String(saved_week["off_claim"])
	c._last_visit_day = String(saved_week["last_visit_day"])
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
	g._engine.status_text = saved_status
	g._engine._refresh()
	Selftest.check("save v5 fixture restores world and files",
		g.SAVE_PATH == String(saved_paths[0]) and not FileAccess.file_exists(g.SAVE_PATH)
		and not FileAccess.file_exists("user://alchemy_st_cb_v5.json"))

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


## Число различных цветов на сетке 24×24 с квантом 5 бит на канал: без кванта
## дизеринг PNG посчитался бы разнообразием, а с квантом плоская заливка даёт
## ровно 1 цвет. Квант — 32 уровня, а не 16: тёмная древесина виньетки целиком
## не влезает в 16 коробок по каналу. Хелпер живёт здесь, а сюита обмена зовёт
## его как `SuiteContractBoard._ca_distinct` — то же направление, что у
## `_ca_img`/`_ca_inner`/`_ca_seam`.
static func _ca_distinct(img: Image) -> int:
	var seen := {}
	var w := img.get_width()
	var h := img.get_height()
	for i in range(24):
		for j in range(24):
			var c := img.get_pixel(int(w * (0.05 + 0.9 * i / 23.0)),
				int(h * (0.05 + 0.9 * j / 23.0)))
			seen["%d_%d_%d_%d" % [int(c.r * 31), int(c.g * 31), int(c.b * 31),
				int(c.a * 31)]] = true
	return seen.size()


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
		"plate_brass.png": Vector2i(224, 64),
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

	# §B/§C (спека 2026-10-25): плашка — не «PNG картинкой сверху»: орех под
	# латунью обязан держать и цветовой разброс, и высокочастотную деталь (волокно,
	# сколы, speckle) ПОДОЛЬНЕ растягиваемой оси — середина nine-slice live'ет при
	# любом размере кнопки, и плоский тон там читался бы наклейкой.
	var plate := _ca_img(CA_DIR + "plate_brass.png")
	Selftest.check("§C the brass plate is sawn walnut under metal, not a flat fill",
		plate != null and _ca_distinct(plate) >= 24
		and _ca_inner(plate, "x") > 0.02)

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


## §C (спека 2026-10-25): пустая строка, если кнопка доски реально одета в
## латунную плашку nine-slice; иначе — короткая причина. Жёлтый
## `UIStyle.style_button(..., 2)` даёт StyleBoxFlat, так что первая же проверка
## краснеет и от возврата к теме, и от плашки без текстуры. Числа литеральные
## (36/10/6), не константы ContractBoard: понизить поле в коде — решение, а пин
## обязан его заметить. Мутации: снять `style_plate`, уронить поля до 16 px,
## оставить content_margin по умолчанию, сделать hover темнее normal.
static func _plate_state(b: Button) -> String:
	if b == null:
		return "нет кнопки"
	var sb := b.get_theme_stylebox("normal") as StyleBoxTexture
	if sb == null or sb.texture == null:
		return "normal не StyleBoxTexture с PNG"
	if not String(sb.texture.resource_path).ends_with("plate_brass.png"):
		return String(sb.texture.resource_path).get_file()
	# 36 px по бокам держат гвоздик целиком: меньше — и два куска наедут в
	# растягиваемую середину.
	if sb.texture_margin_left < 36.0 or sb.texture_margin_right < 36.0 \
			or sb.texture_margin_top < 10.0 or sb.texture_margin_bottom < 10.0:
		return "поля nine-slice уже 36/10"
	for k in ["content_margin_left", "content_margin_top",
			"content_margin_right", "content_margin_bottom"]:
		if float(sb.get(k)) < 6.0:
			return "§D %s" % k
	var hov := b.get_theme_stylebox("hover") as StyleBoxTexture
	var prs := b.get_theme_stylebox("pressed") as StyleBoxTexture
	if hov == null or prs == null:
		return "нет hover/pressed"
	if hov.modulate_color.r <= 1.0 or prs.modulate_color.r >= 1.0:
		return "hover/pressed не ярче/тусклее"
	# «1 px вниз» при нажатии: texture_offset в Godot 4 нет, сдвиг — полем контента.
	if not is_equal_approx(prs.content_margin_top, sb.content_margin_top - 1.0):
		return "pressed не сдвинут на 1 px"
	var ink: Color = b.get_theme_color("font_color")
	if ink.r < 0.8 or ink.g < 0.7:
		return "чернила не светлые"
	return ""


## §D: ни одна подпись листа не ближе 6 px к кромке своего текстурированного
## блока. Карточка задаёт position/size всем полям сама (лист не в контейнере
## ряда), поэтому геометрия читается из декларации и в headless. Обходим с
## накоплением смещения; рядом с подписью, у которой есть текстурный родитель
## (слово внутри рамки штампа), эталоном становится именно его rect — иначе
## штамп краснел бы за свес рамки, а не за тесный текст. Меряем Label и
## Container; TextureRect/TextureButton не меряем — сургуч нарочно свешивается
## за край бумаги на 4 px. Поворот на ±4° (наклон листа) и −6° (штамп)
## прямоугольниками не учитываем: он меньше поля PAD.
static func _cc_margin_bad(card: Control) -> Array:
	var acc: Array = []
	var hang := card.get("_hang") as Control
	if hang == null:
		acc.append("no Hang")
		return acc
	_cc_margin_walk(hang, Vector2.ZERO, hang.size, acc)
	return acc


static func _cc_margin_walk(n: Control, off: Vector2, box: Vector2, acc: Array) -> void:
	if n == null:
		return
	var o := off + n.position
	if (n is Label or n is Container) and n.size.x > 0.0 and n.size.y > 0.0:
		var d := minf(minf(o.x, box.x - o.x - n.size.x),
			minf(o.y, box.y - o.y - n.size.y))
		if d < 6.0:
			acc.append("%s=%.1f" % [str(n.name), d])
	var own := _cc_block(n)
	for ch in n.get_children():
		if own.x > 0.0:
			_cc_margin_walk(ch as Control, Vector2.ZERO, own, acc)
		else:
			_cc_margin_walk(ch as Control, o, box, acc)


## Rect текстурированного блока, чьим детям он задаёт поля: PNG-слой или
## nine-slice кнопка. Пустой вектор — блок не текстурный, эталон не меняется.
static func _cc_block(n: Control) -> Vector2:
	if n.size.x <= 0.0 or n.size.y <= 0.0:
		return Vector2.ZERO
	if n is TextureRect:
		var tr := (n as TextureRect).texture
		return n.size if tr != null else Vector2.ZERO
	if n is TextureButton:
		var tb := (n as TextureButton).texture_normal
		return n.size if tb != null else Vector2.ZERO
	if n is Button and (n as Button).get_theme_stylebox("normal") is StyleBoxTexture:
		return n.size
	return Vector2.ZERO


static func _cc_button(n: Node, want: String) -> Button:
	for ch in n.get_children():
		var c := ch as Control
		if c == null:
			continue
		if c is Button and String(c.name) == want:
			return c as Button
		var found := _cc_button(c, want)
		if found != null:
			return found
	return null


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

	# 15. Штамп садится в позу покоя в момент нажатия (под selftest — мгновенно).
	Selftest.check("§5.3 the stamp settles to rest pose the moment it is hit",
		stamp_r != null and stamp_r.scale == Vector2.ONE
		and is_equal_approx(stamp_r.rotation_degrees, ContractCard.STAMP_TILT))

	# 16. §D (спека 2026-10-25): текст не впритык к кромке бумаги. Мутации:
	# поднять `_reward` на 8 px, ужать слово штампа до rect рамки, сдвинуть
	# `_title` влево на 6 px — каждая красит эту проверку.
	# Кадр до замера: у Label минимум считается до первого процесса по кеглю
	# темы (16 px), и `set_size()` клампится до минимума — «ИСПОЛНЕНО» 16 px
	# шириной 99 px вместо объявленных 84, тело — 157 вместо 112. Пин краснел
	# бы на артефакте headless, а не на вёрстке (мутация: убрать await).
	await g.get_tree().process_frame
	var tight: Array = []
	for card in cards:
		tight.append_array(_cc_margin_bad(card as Control))
	if not tight.is_empty():
		print("  §D tight: ", ", ".join(tight))
	Selftest.check("§D every word on a note keeps six pixels off its paper and frame",
		tight.is_empty())

	# 17. §C+§D ряда жилы: «Влить» — та же латунная плашка, что у кнопки доски, а
	# не жёлтая тема, и её подпись не касается metal-края. Ряд существует только
	# при находке статуса `registered` текущего цикла (contracts.gd:1795), поэтому
	# её и подставляем; `_cb_restore` откатывает `_vein_finds` и `_cycle_cache`.
	var vein_contract := _mk(c, "weekly", "vein", "bronze", 1)
	c._cycle_cache = {"cycle_id": "d-cyc"}
	c._vein_finds = [{"id": "d-f1", "tag": "руда", "points": 1, "pair_key": "a+b",
		"cycle_id": "d-cyc", "status": "registered"}]
	var vein_card := ContractCard.new(g)
	vein_card.setup(vein_contract)
	g.add_child(vein_card)
	cards.append(vein_card)
	var pour := _cc_button(vein_card, "Pour")
	Selftest.check("§C the vein row's pour button is sawn in the brass plate",
		_plate_state(pour) == "")

	for card in cards:
		(card as ContractCard).queue_free()
	await g.get_tree().process_frame
	g.get_window().size = win_before
	g._workshop.rank = saved_rank
	g._workshop.autonomy_level = saved_auto
	e.spring_levels = saved_spring.duplicate(true)
	_cb_restore(c, saved)
