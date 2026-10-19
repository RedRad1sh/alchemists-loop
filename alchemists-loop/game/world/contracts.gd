extends RefCounted
class_name Contracts
# §1: всё состояние и вся логика контрактной доски. Единственный файл, который
# читают и пишут точки-хуки; UI берёт отсюда готовые списки и ничего не считает
# (§1.5: при переходе на сервер-авторитет набор начнёт приходить с сервера, и
# этот файл останется единственным, кто знает разницу).

const CONTRACTS_SAVE_VERSION := 1

var g: Game

# ---------- §4.1 состояние ----------
var _contracts_daily: Array = []
var _contracts_weekly: Array = []
var _contracts_last_daily := ""
var _contracts_last_weekly := ""
var _contracts_daily_done: Dictionary = {}
var _contracts_weekly_done: Dictionary = {}
var _contracts_daily_prog: Dictionary = {}
var _contracts_weekly_prog: Dictionary = {}
var _contracts_variety: Dictionary = {}
var _contracts_set_week: Dictionary = {}
var _active_buffs: Dictionary = {}
var _unlocked_decor: Array = []
var _last_output := ""
# доска v2 (§1 строки 1–2): кэш цели дня (по образцу _circle_local_goal_cache),
# гейт повторного входа синка заказов, подсказка цели (заполняет Task 4).
var _day_goal_cache := {}
var _orders_syncing := false
var _day_hint := ""

func _init(game: Game) -> void:
	g = game

# ---------- временные швы ----------
# В Godot 4 все unix-геттеры только UTC, а get_datetime_dict_from_system() —
# только локальное время: локального геттера из unix нет. Ключ периода обязан
# считаться от локальной даты (§1.4: сброс в 00:00 локального времени), срок
# баффа — от настоящего unix. Смешать их значит сдвинуть одно из двух на
# часовой пояс, поэтому шва два и они не объединяются.
func _dt(now: Dictionary) -> Dictionary:
	return now if not now.is_empty() else Time.get_datetime_dict_from_system()

func _unix(now_unix: int) -> int:
	return now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())

static func day_key_from(dt: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(dt["year"]), int(dt["month"]), int(dt["day"])]

static func _civil_days(y: int, m: int, d: int) -> int:
	# Полдень, а не полночь: перевод локальной календарной даты в номер дня
	# через UTC не должен зависеть от доли суток.
	var unix := int(Time.get_unix_time_from_datetime_dict(
		{"year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0}))
	return int(floor(float(unix) / 86400.0))

static func _days_to_dt(days: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(days * 86400 + 43200)

# ISO-8601: неделя принадлежит году своего четверга. Считаем явно — формат
# "YYYY-Www" из §1.4 менять нельзя, по нему сервер сверит период (§1.5).
# Алгоритм сверен с эталоном на каждой дате 1970..2200: расхождений 0.
static func week_key_from(dt: Dictionary) -> String:
	var monday := _civil_days(int(dt["year"]), int(dt["month"]), int(dt["day"])) \
		- (int(dt.get("weekday", 0)) + 6) % 7
	var thu := monday + 3
	var thu_year := int(_days_to_dt(thu)["year"])
	var week := int(floor(float(thu - _civil_days(thu_year, 1, 1)) / 7.0)) + 1
	return "%04d-W%02d" % [thu_year, week]

# ---------- §1.4 детерминированная генерация ----------
func _seed_for(prefix: String, period_key: String) -> String:
	return ("contracts:%s:%s" % [prefix, period_key]).sha256_text()

func _byte(h: String, cursor: int) -> int:
	return int(h.substr((cursor * 2) % h.length(), 2).hex_to_int())

# Курсор держим в словаре: Dictionary передаётся по ссылке, поэтому выборка
# типов и последующие байты контракта идут по одному непрерывному курсору.
# Доска v2: максимум на набор — daily 2+4·2=10 байт (2 выбора + 4×(тир+бафф)),
# weekly 2+4·3=14 (2 выбора + 4×(тир+бафф+декор)), то есть до 32 доступных байт
# sha256-строки дело не доходит и повторов курса нет.
func _pick_types(pool: Array, count: int, h: String, cur: Dictionary) -> Array:
	var left: Array = pool.duplicate()
	var out: Array = []
	while out.size() < count and not left.is_empty() and int(cur["i"]) < 192:
		var idx := _byte(h, int(cur["i"])) % left.size()
		cur["i"] = int(cur["i"]) + 1
		out.append(left[idx])
		left.remove_at(idx)
	return out

func _tiers_for(kind: String, type: String, daily_crafts: int) -> Array:
	var tiers: Array = ContractsBalance.TIERS.duplicate()
	# §4.1: gold у sigil_craft невыполним, если дневное предложение Аркана
	# меньше порога gold — такой тир не генерируется вовсе.
	if kind == "daily" and type == "sigil_craft":
		if daily_crafts < int((ContractsBalance.DAILY_GOALS["sigil_craft"] as Array)[2]):
			tiers.erase("gold")
	return tiers

func _make_contract(kind: String, type: String, tier: String, period_key: String,
		buff: String, decor: String) -> Dictionary:
	var goals: Dictionary = ContractsBalance.DAILY_GOALS if kind == "daily" else ContractsBalance.WEEKLY_GOALS
	return {
		"id": "%s:%s:%s:%s" % [kind, type, tier, period_key],
		"kind": kind,
		"type": type,
		"tier": tier,
		"goal": int((goals[type] as Array)[ContractsBalance.TIERS.find(tier)]),
		"buff": buff,
		"decor": decor,
	}

# daily_crafts = -1 означает «взять фактическое дневное предложение Аркана».
# Параметр нужен тестам: в headless-прогоне _daily_crafts пуст, и без него
# проверка «gold не генерируется» была бы зелёной всегда, а обратная — всегда
# красной.
# Доска v2 (спека слияния §2): первые PINNED_HEAD мест ряда — закрепление
# goal_day/orders в этом порядке (следующие таски опираются на daily()[0] ==
# goal_day), случайный остаток выбирается из пула без pinned. Полный список
# обходится одним курсором байтов tier→buff, поэтому ряд по-прежнему
# детерминирован от ключа дня.
func _generate_daily(day_key: String, daily_crafts: int = -1) -> Array:
	var crafts := daily_crafts if daily_crafts >= 0 else g._sigil._daily_crafts.size()
	var h := _seed_for("daily", day_key)
	var cur := {"i": 0}
	var picked := _pick_types(ContractsBalance.DAILY_TYPES.slice(ContractsBalance.PINNED_HEAD),
		ContractsBalance.DAILY_SHOWN - ContractsBalance.PINNED_HEAD, h, cur)
	var out: Array = []
	for t in ContractsBalance.DAILY_TYPES.slice(0, ContractsBalance.PINNED_HEAD) + picked:
		var type := String(t)
		var tiers := _tiers_for("daily", type, crafts)
		var tier := String(tiers[_byte(h, int(cur["i"])) % tiers.size()])
		cur["i"] = int(cur["i"]) + 1
		var buff := String(ContractsBalance.BUFF_IDS[
			_byte(h, int(cur["i"])) % ContractsBalance.BUFF_IDS.size()])
		cur["i"] = int(cur["i"]) + 1
		out.append(_make_contract("daily", type, tier, day_key, buff, ""))
	return out

# Симметрично _generate_daily: закреплённая голова vein/fair, байт декора
# тратится на каждую запись — правило «байт декора тратится всегда» сохраняет
# независимость потребления курса от тира, то есть детерминизм ряда.
func _generate_weekly(week_key: String) -> Array:
	var h := _seed_for("weekly", week_key)
	var cur := {"i": 0}
	var picked := _pick_types(ContractsBalance.WEEKLY_TYPES.slice(ContractsBalance.PINNED_HEAD),
		ContractsBalance.WEEKLY_SHOWN - ContractsBalance.PINNED_HEAD, h, cur)
	var out: Array = []
	for t in ContractsBalance.WEEKLY_TYPES.slice(0, ContractsBalance.PINNED_HEAD) + picked:
		var type := String(t)
		var tiers := _tiers_for("weekly", type, 0)
		var tier := String(tiers[_byte(h, int(cur["i"])) % tiers.size()])
		cur["i"] = int(cur["i"]) + 1
		var buff := String(ContractsBalance.BUFF_IDS[
			_byte(h, int(cur["i"])) % ContractsBalance.BUFF_IDS.size()])
		cur["i"] = int(cur["i"]) + 1
		# Байт декора тратится всегда — иначе потребление курса зависело бы от
		# тира, и детерминизм стал бы труднее проверить.
		var decor := String(ContractsBalance.DECOR[
			_byte(h, int(cur["i"])) % ContractsBalance.DECOR.size()])
		cur["i"] = int(cur["i"]) + 1
		# §3.4: косметика только у недельного gold, у остальных пустая строка.
		out.append(_make_contract("weekly", type, tier, week_key, buff,
			decor if tier == "gold" else ""))
	return out

# ---------- §1.4/§4.5 периоды ----------
func ensure_period(now: Dictionary = {}) -> void:
	var dt := _dt(now)
	var day_key := day_key_from(dt)
	var week_key := week_key_from(dt)
	if day_key != _contracts_last_daily:
		_contracts_last_daily = day_key
		_contracts_daily = _generate_daily(day_key)
		# §4.5: невыданные награды прошедшего дня сгорают — перенос превратил бы
		# дневной контракт в накопительный, а §8.3 это запрещает.
		_contracts_daily_prog.clear()
		_contracts_daily_done.clear()
	if week_key != _contracts_last_weekly:
		_contracts_last_weekly = week_key
		_contracts_weekly = _generate_weekly(week_key)
		_contracts_weekly_prog.clear()
		_contracts_weekly_done.clear()
		_contracts_variety.clear()
		_contracts_set_week.clear()
	# §1 (доска v2): строка orders зеркалит счётчик гильдии на любой выход из
	# точки периода, включая «ничего не сменилось».
	_sync_orders()

# ---------- §1 (доска v2): goal_day и orders ----------
# Порт дневной цели из retention.gd:117-139 и зеркало заказов гильдии.
func _local_goal_for(day: String) -> Dictionary:
	# Копия алгоритма retention.gd:117-129 без изменения: seed ("local_goal_"+day),
	# пул — рецепты из двух баз (заведомо достижимые), индекс — первые два
	# hex-символа sha256.
	var h: String = ("local_goal_" + day).sha256_text()
	var pool: Array = []
	for r in g.RECIPES:
		if Game.BASE_IDS.has(String(r["a"])) and Game.BASE_IDS.has(String(r["b"])):
			pool.append(r)
	if pool.is_empty():
		return {}
	var idx := h.substr(0, 2).hex_to_int() % pool.size()
	return pool[idx]

# Кэш по ключу дня — как _circle_local_goal в retention: пересчёт один раз за
# день, при смене дня (полночь локального времени) — новый выбор.
func _local_goal() -> Dictionary:
	var day := day_key_from(Time.get_datetime_dict_from_system())
	if String(_day_goal_cache.get("day", "")) != day:
		var pick := _local_goal_for(day)
		_day_goal_cache = {"day": day}
		_day_goal_cache.merge(pick)
	return _day_goal_cache

func day_hint() -> String:
	return _day_hint

# Абсолютное зеркало счётчика выполненных заказов гильдии (спека §1: «на момент
# ensure_period()/daily()»). Done-контракты не трогаем, отметку о выдаче здесь
# не ставим — это дело claim().
func _sync_orders() -> void:
	# Защита от повторного входа: _set_progress → contract_by_id → ensure_period →
	# _sync_orders — без флага вызов уходил бы в бесконечную рекурсию.
	if _orders_syncing:
		return
	_orders_syncing = true
	g._guild._orders_refresh()
	var n := g._guild._order_done.size()
	# Нулевое зеркало — no-op: запись нуля через _set_progress материализовала бы
	# пустые записи в прогрессе (сюита сверяет «после сброса словарь пуст») и
	# втягивала бы вложенный ensure_period по настенным часам, ломая тесты с
	# синтетическими периодами. Обнулять нечего: на полуночи дневной сброс уже
	# очистил прогресс, а гильдия на смене дня чистит свой счётчик.
	if n <= 0:
		_orders_syncing = false
		return
	for c in _contracts_daily:
		var contract := c as Dictionary
		if String(contract["type"]) != "orders":
			continue
		var id := String(contract["id"])
		if _contracts_daily_done.has(id):
			continue
		_set_progress(id, n)
	_orders_syncing = false

# ---------- чтение ----------
func daily(now: Dictionary = {}) -> Array:
	# §1 (доска v2): зеркало заказов обязано быть свежим на момент daily(),
	# поэтому sync и здесь — до ensure_period (его собственный sync сработает
	# уже по свежему ряду).
	_sync_orders()
	ensure_period(now)
	return _contracts_daily

func weekly(now: Dictionary = {}) -> Array:
	ensure_period(now)
	# §1 (доска v2): vein и fair считаются по внешнему состоянию (цикл жилы,
	# вклад котла), поэтому прогресс догоняется на каждом входе — именно здесь,
	# а не в ensure_period(): _set_progress → contract_by_id → all_contracts →
	# ensure_period дал бы рекурсивную смену периода.
	_sync_vein()
	_sync_fair()
	return _contracts_weekly

func all_contracts(now: Dictionary = {}) -> Array:
	ensure_period(now)
	return _contracts_daily + _contracts_weekly

func contract_by_id(id: String, now: Dictionary = {}) -> Dictionary:
	# Ищем только в текущем периоде: контракт вчерашнего дня не находится, и это
	# есть механизм сгорания наград (§4.5, тест №20).
	for c in all_contracts(now):
		if String((c as Dictionary)["id"]) == id:
			return (c as Dictionary)
	return {}

func _done_dict(kind: String) -> Dictionary:
	return _contracts_daily_done if kind == "daily" else _contracts_weekly_done

func _prog_dict(kind: String) -> Dictionary:
	return _contracts_daily_prog if kind == "daily" else _contracts_weekly_prog

func is_done(id: String, now: Dictionary = {}) -> bool:
	var c := contract_by_id(id, now)
	return not c.is_empty() and _done_dict(String(c["kind"])).has(id)

func progress(id: String, now: Dictionary = {}) -> int:
	var c := contract_by_id(id, now)
	if c.is_empty():
		return 0
	return int(_prog_dict(String(c["kind"])).get(id, 0))

func is_ready(id: String, now: Dictionary = {}) -> bool:
	var c := contract_by_id(id, now)
	if c.is_empty() or is_done(id, now):
		return false
	# §1 (доска v2): у ярмарки готовность — гейт закрытого котла (серверный или
	# локальный), а не «прогресс ≥ цель»: число варок на экране есть, но само
	# право забрать награду решает вклад ≥3 в ЗАКРЫТЫЙ котёл.
	if String(c["type"]) == "fair":
		return _fair_gate()
	return progress(id, now) >= int(c["goal"])

# ---------- §3.1 единый множитель прогресса ----------
# Максимумы взяты из кода, а не назначены: сюита сверяет их с размерами
# WorkshopBalance.RANKS/AUTONOMY и таблиц цен Родника.
func reward_mult() -> float:
	var workshop_progress := (float(g._workshop.rank) / float(ContractsBalance.RANK_MAX) \
		+ float(g._workshop.autonomy_level) / float(ContractsBalance.AUTONOMY_MAX)) / 2.0
	var spring_levels: Dictionary = g._engine.spring_levels
	var spring_progress := (float(spring_levels.get("speed", 0)) / float(ContractsBalance.SPRING_MAX["speed"]) \
		+ float(spring_levels.get("volume", 0)) / float(ContractsBalance.SPRING_MAX["volume"]) \
		+ float(spring_levels.get("sources", 0)) / float(ContractsBalance.SPRING_MAX["sources"]) \
		+ float(spring_levels.get("offline", 0)) / float(ContractsBalance.SPRING_MAX["offline"])) / 4.0
	var progress := ContractsBalance.WORKSHOP_WEIGHT * clampf(workshop_progress, 0.0, 1.0) \
		+ ContractsBalance.SPRING_WEIGHT * clampf(spring_progress, 0.0, 1.0)
	return 1.0 + ContractsBalance.MULT_COEF * clampf(progress, 0.0, 1.0)

# Один и тот же множитель на все три числовые величины награды (§3.1).
# Косметика им не масштабируется — это фиксированная долгосрочная цель (§3.4).
func reward_for(c: Dictionary) -> Dictionary:
	var mult := reward_mult()
	var kind := String(c.get("kind", "daily"))
	var tier := String(c.get("tier", "bronze"))
	var table: Dictionary = ContractsBalance.DAILY_MATERIALS if kind == "daily" else ContractsBalance.WEEKLY_MATERIALS
	var base: Dictionary = table.get(tier, {})
	var materials := {}
	for m in base:
		materials[String(m)] = int(round(float(int(base[m])) * mult))
	var buff_id := String(c.get("buff", ""))
	var bb: Dictionary = ContractsBalance.BUFF_BASE.get(buff_id, {})
	return {
		"materials": materials,
		"buff": buff_id,
		"duration": int(round(float(int(bb.get("duration", 0))) * mult)),
		"power": float(bb.get("power", 0.0)) * mult,
		"decor": String(c.get("decor", "")),
	}

# ---------- §3.3 баффы ----------
# Срок и сила живут на настоящем unix (§1.4: «временные» — значит сгорающие по
# часам, а не по игровым дням). now_unix = -1 ⇒ фактическое время системы.
func grant_buff(buff_id: String, duration: int, power: float, now_unix: int = -1) -> void:
	if not ContractsBalance.BUFF_IDS.has(buff_id) or duration <= 0:
		return
	prune_buffs(now_unix)
	var now := _unix(now_unix)
	var prev := _active_buffs.get(buff_id, {}) as Dictionary
	# §3.3: не стакается. Срок продлевается от конца действующего, сила
	# остаётся первой — иначе вторая выдача удваивала бы эффект.
	var from := maxi(int(prev.get("until", 0)), now)
	_active_buffs[buff_id] = {"until": from + duration, "power": float(prev.get("power", power))}

func prune_buffs(now_unix: int = -1) -> void:
	var now := _unix(now_unix)
	for id in _active_buffs.keys():
		if int((_active_buffs[id] as Dictionary)["until"]) <= now:
			_active_buffs.erase(id)

func buff_power(buff_id: String, now_unix: int = -1) -> float:
	var b := _active_buffs.get(buff_id, {}) as Dictionary
	if b.is_empty() or int(b.get("until", 0)) <= _unix(now_unix):
		return 0.0
	return float(b.get("power", 0.0))

func buff_left(buff_id: String, now_unix: int = -1) -> int:
	var b := _active_buffs.get(buff_id, {}) as Dictionary
	if b.is_empty():
		return 0
	return maxi(0, int(b.get("until", 0)) - _unix(now_unix))

func active_buffs(now_unix: int = -1) -> Array:
	prune_buffs(now_unix)
	var now := _unix(now_unix)
	var out: Array = []
	# Порядок фиксирован таблицей, а не порядком в Dictionary: UI перестраивает
	# записки на каждой пересборке доски, и без порядка они бы прыгали.
	for id in ContractsBalance.BUFF_IDS:
		var buff_id := String(id)
		if not _active_buffs.has(buff_id):
			continue
		out.append({
			"id": buff_id,
			"power": float((_active_buffs[buff_id] as Dictionary)["power"]),
			"left": maxi(0, int((_active_buffs[buff_id] as Dictionary)["until"]) - now),
			"title": String(ContractsBalance.BUFF_TITLE[buff_id]),
		})
	return out

func spring_yield(now_unix: int = -1) -> int:
	# §3.3: power — добавка к нейтральному значению, поэтому ×(1+power) и для
	# процента, и для мультипликатора. Округляем до целого выхода за один тик.
	return maxi(1, int(round(1.0 + buff_power("spring_yield", now_unix))))

# §4.4: id декора обязан существовать в каталоге до выдачи.
static func decor_exists(decor_id: String) -> bool:
	if decor_id == "":
		return false
	for cat in DecorData.DECOR:
		for item in (cat as Dictionary).get("items", []):
			if str((item as Dictionary).get("id", "")) == decor_id:
				return true
	return false

# ---------- §3.4/§4.4 выдача награды ----------
# Отметку ставим ДО выдачи. Второй тап, пришедший во время первого, обязан
# уйти в ветку "claimed", а не во вторую выдачу (тест №6).
func claim(id: String, now: Dictionary = {}, now_unix: int = -1) -> Dictionary:
	ensure_period(now)
	var c := contract_by_id(id, now)
	if c.is_empty():
		# Один и тот же ответ для выдуманного id и для сгоревшего вчерашнего:
		# контракт вне текущего списка не существует, и наград у него нет (§4.5).
		return _claim_failure("unknown")
	var kind := String(c["kind"])
	if _done_dict(kind).has(id):
		return _claim_failure("claimed")
	# §1 (доска v2, спека §4): у fair право забрать награду даёт гейт ЗАКРЫТОГО котла
	# (_fair_gate — серверный «закрыт и вклад ≥3» или локальный котёл), а не прогресс:
	# прогресс fair — это лишь число варок на экране, и по нему открытый котёл с
	# вкладом ≥3 выглядел бы готовым. Доска не должна платить за незакрытый котёл,
	# поэтому для fair проверяем именно гейт (ровно то же правило, что в is_ready()).
	if String(c["type"]) == "fair":
		if not _fair_gate():
			return _claim_failure("incomplete")
	elif progress(id, now) < int(c["goal"]):
		return _claim_failure("incomplete")
	_done_dict(kind)[id] = true
	var reward := reward_for(c)
	var grant := _grant_materials(reward["materials"] as Dictionary)
	var buff_id := String(reward["buff"])
	if buff_id != "":
		grant_buff(buff_id, int(reward["duration"]), float(reward["power"]), _unix(now_unix))
	var decor_id := String(reward["decor"])
	var missing := false
	if decor_id != "":
		if not decor_exists(decor_id):
			# §4.4: в house_owned фантом не пишем — _decor_owned_count считает
			# владение по этому же массиву и завысил бы счётчик коллекции.
			missing = true
			Analytics.track("contract_decor_missing",
				{"contract_id": id, "decor_id": decor_id})
		else:
			g._home._own_item("window", decor_id)
			if not _unlocked_decor.has(decor_id):
				_unlocked_decor.append(decor_id)
	# §1 (доска v2, строки 7–8): у pinned-строк недельного слоя у табличной
	# награды доски есть второй, «вечный» слой.
	# · fair: доска — только витрина, поэтому успешный claim обязан сверх того
	#   совершить грант регена: офлайн — тело локального котла (гейт уже
	#   выполнен в _fair_gate, повторная проверка отсекла бы законную выдачу),
	#   онлайн — запрос /fair/claim, вечный реген придёт асинхронно в
	#   _on_net_fair_claim_result.
	# · vein: меряем, что недельная строка жилы реально забирают (ключ из спеки).
	if String(c["type"]) == "fair":
		if _fair_offline_available():
			_fair_offline_grant()
		elif not g._selftest:
			# в selftest сеть недоступна, вечный грант асинхронный — проверке не нужен
			Net.fair_claim(g._online._device_id)
	elif String(c["type"]) == "vein":
		Analytics.track("vein_contract_claim", {"tier": String(c["tier"])})
	g._saves._save_game()
	return {"ok": true, "reason": "", "materials": grant["given"],
		"truncated": bool(grant["truncated"]), "buff": buff_id,
		"duration": int(reward["duration"]), "power": float(reward["power"]),
		"decor": decor_id, "missing_decor": missing}

# Возвращает ровно то, что физически легло в инвентарь: попап обязан показать
# фактическое количество (§4.4, тест №21), а не задуманное.
func _grant_materials(materials: Dictionary) -> Dictionary:
	var given := {}
	var truncated := false
	for raw_id in materials:
		var item_id := String(raw_id)
		var want := int(materials[raw_id])
		if want <= 0:
			continue
		var have := int(g._engine.inventory.get(item_id, 0))
		var put := mini(want, maxi(0, Game.CRAFT_INVENTORY_STACK_CAP - have))
		if put < want:
			truncated = true
		if put > 0:
			g._engine.inventory[item_id] = have + put
			given[item_id] = put
	return {"given": given, "truncated": truncated}

static func _claim_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "materials": {}, "truncated": false,
		"buff": "", "duration": 0, "power": 0.0, "decor": "", "missing_decor": false}

# ---------- §1.2/§1.3 точки-хуки ----------
# Абсолютная запись прогресса с отсечкой по цели контракта (§2): «N / goal» не
# должно показывать 17/15.
func _set_progress(id: String, value: int) -> void:
	var c := contract_by_id(id)
	if c.is_empty():
		return
	_prog_dict(String(c["kind"]))[id] = clampi(value, 0, int(c["goal"]))

# Прогресс накопительный и всегда capped по цели контракта (§2). Сгоревшие
# (done) контракты не двигаются.
func _bump(type: String, amount: int) -> void:
	if amount <= 0:
		return
	for c in all_contracts():
		var contract := c as Dictionary
		if String(contract["type"]) != type:
			continue
		var id := String(contract["id"])
		if _done_dict(String(contract["kind"])).has(id):
			continue
		_set_progress(id, int(_prog_dict(String(contract["kind"])).get(id, 0)) + amount)

# §1.3: глубину считаем здесь, а не в core.gd — офлайн-реплей делает тысячи
# варок подряд, и `_content_depth` (рекурсивный обход без кэша) не должен
# вызываться для тех из них, которые всё равно не засчитываются.
func _depth(item_id: String) -> int:
	var d := g._workshop._content_depth(item_id)
	# workshop.gd:33 — каноническая отсечка: неизвестные и циклические id
	# возвращают WorkshopBalance.INVALID_DEPTH, базовые — 0.
	if d <= 0 or d >= WorkshopBalance.INVALID_DEPTH:
		return 0
	return d

func on_brew(output: String, a: String, b: String, first_time: bool, source: String) -> void:
	# §1.3 ДО любого изменения состояния, включая якорь цепочки.
	if source == "offline_workshop":
		return
	ensure_period()
	# §1 (доска v2): локальная цель дня засчитывается до остальных счётчиков и
	# только за ровно тот выход, что выбран датой (офлайн-реплей уже отсечён
	# early-return выше).
	if output != "" and output == String(_local_goal().get("out", "")):
		_bump("goal_day", 1)
	if a == _last_output or b == _last_output:
		_bump("chain_brew", 1)
	_last_output = output
	if first_time and output != "":
		_bump("discover", 1)
		if not _contracts_variety.has(output):
			_contracts_variety[output] = true
			_bump("variety", 1)
	if output != "":
		_bump("brew", 1)
	var d := _depth(output)
	if d >= ContractsBalance.DEPTH_DAILY:
		_bump("depth_brew", 1)
	if d >= ContractsBalance.DEPTH_WEEKLY:
		_bump("rare_brew", 1)

# §1.2: вызывается из _experiment_succeeded и _experiment_failed, обе точки
# защищены существующим гейтом _experiment_pending_pair, поэтому срабатывает
# ровно один раз на подтверждённый эксперимент. _finish_experiment_inputs не
# трогаем: он означает «вход возвращён», включая сетевой сбой (rule 14).
func on_experiment(_a: String, _b: String, _success: bool) -> void:
	ensure_period()
	_bump("experiment", 1)

func set_count(set_id: String) -> int:
	return int(_contracts_set_week.get(set_id, 0))

func _set_best() -> int:
	var best := 0
	for set_id in _contracts_set_week:
		best = maxi(best, int(_contracts_set_week[set_id]))
	return best

# Сигнатура = SigilManager.craft_completed (sigil_manager.gd:14).
func on_sigil_craft(craft_id: String, _rarity: String, _llm_name: String) -> void:
	ensure_period()
	_bump("sigil_craft", 1)
	# §1.2: сет считается по крафтам НЕДЕЛИ, а не по коллекции. Иначе игрок, у
	# которого сет уже собран, закрывал бы недельный gold в первую секунду недели.
	var set_id := g._sigil.set_of_craft(craft_id)
	if set_id == "":
		return
	_contracts_set_week[set_id] = int(_contracts_set_week.get(set_id, 0)) + 1
	# sigil_set — максимум по сетам, поэтому абсолютная запись, а не _bump.
	for c in all_contracts():
		var contract := c as Dictionary
		if String(contract["type"]) != "sigil_set":
			continue
		var id := String(contract["id"])
		if _done_dict(String(contract["kind"])).has(id):
			continue
		_set_progress(id, _set_best())

func on_upgrade(_system: String, _axis: String, _level: int) -> void:
	ensure_period()
	_bump("upgrade", 1)

# §4.4: счётчик растёт ДО очистки, иначе недельный контракт `prestige`
# обнулялся бы собственным событием. Недельное состояние переживает Перегонку,
# дневное и баффы — нет. Полная очистка — только у reset_new_game (Task 7).
func on_prestige() -> void:
	ensure_period()
	_bump("prestige", 1)
	_active_buffs.clear()
	_contracts_daily.clear()
	_contracts_daily_prog.clear()
	_contracts_daily_done.clear()
	_last_output = ""
	# Ключ дня обязан освободиться: ensure_period() выше уже проставил его равным
	# сегодняшнему, поэтому без сброса следующее daily() увидит неизменный ключ,
	# выйдет до регенерации и вернёт очищенный пустой список — доска останется
	# пуста до полуночи. Сброс даёт детерминированный по-дате набор с нулевым
	# прогрессом (тот же день → те же контракты). Недельный ключ не трогаем:
	# недельные списки Перегонку переживают (§4.4).
	_contracts_last_daily = ""

# §1.1: единственный случай, где доска подписывается вместо прямого вызова —
# издатель (Аркан) существует независимо и ничего не должен знать о доске.
func connect_signals() -> void:
	if not g._sigil.craft_completed.is_connected(on_sigil_craft):
		g._sigil.craft_completed.connect(on_sigil_craft)

func _sigil_connection_count() -> int:
	var n := 0
	for conn in g._sigil.craft_completed.get_connections():
		if ((conn as Dictionary)["callable"] as Callable).get_method() == "on_sigil_craft":
			n += 1
	return n

# ---------- §4.1/§4.2 сейв-блок ----------
# Единственный шлюз чисел из файла. JSON в Godot 4.7 отдаёт ЛЮБОЕ число как
# TYPE_FLOAT (проверено разбором записанного файла: 5, 1000000 и 2.5 — float),
# поэтому границу «это целое число» считаем здесь и дальше работаем на float.
# Образец — Workshop._integer (workshop.gd:489).
static func _whole(raw: Variant) -> float:
	if raw is int:
		return float(raw)
	if raw is float and is_finite(raw) and raw == floor(raw):
		return float(raw)
	return -1.0

func save_block() -> Dictionary:
	return {
		"version": CONTRACTS_SAVE_VERSION,
		"daily": _contracts_daily.duplicate(true),
		"weekly": _contracts_weekly.duplicate(true),
		"last_daily": _contracts_last_daily,
		"last_weekly": _contracts_last_weekly,
		"daily_done": _contracts_daily_done.duplicate(true),
		"weekly_done": _contracts_weekly_done.duplicate(true),
		"daily_prog": _contracts_daily_prog.duplicate(true),
		"weekly_prog": _contracts_weekly_prog.duplicate(true),
		"variety": _contracts_variety.duplicate(true),
		"set_week": _contracts_set_week.duplicate(true),
		"buffs": _active_buffs.duplicate(true),
		"decor": _unlocked_decor.duplicate(true),
		"last_output": _last_output,
	}

# Defaults-first, по образцу _load_spring_state (saves.gd:615): состояние уже
# чистое, сейв только подтверждает его.
func load_block(raw: Variant) -> void:
	_clear_state()
	if not (raw is Dictionary):
		return
	var d: Dictionary = raw
	var v := _whole(d.get("version", null))
	if v < 1.0 or v > float(CONTRACTS_SAVE_VERSION):
		# §4.3: подозрительная версия всего блока = блок отбрасывается целиком,
		# остальной сейв уже загружен. Задним числом награды не начисляются.
		return
	_load_axis(d, "daily")
	_load_axis(d, "weekly")
	# Недельные счётчики без пережившей недели бессмысленны: их всё равно
	# обнулит первый же сброс периода.
	if not _contracts_weekly.is_empty():
		_contracts_variety = _clean_flags(d.get("variety", null))
		_contracts_set_week = _clean_free_counts(d.get("set_week", null))
	_active_buffs = _clean_buffs(d.get("buffs", null))
	_unlocked_decor = _clean_decor(d.get("decor", null))
	var anchor: Variant = d.get("last_output", "")
	if anchor is String and g.ITEMS.has(String(anchor)):
		_last_output = String(anchor)

func _clear_state() -> void:
	_contracts_daily = []
	_contracts_weekly = []
	_contracts_last_daily = ""
	_contracts_last_weekly = ""
	_contracts_daily_done = {}
	_contracts_weekly_done = {}
	_contracts_daily_prog = {}
	_contracts_weekly_prog = {}
	_contracts_variety = {}
	_contracts_set_week = {}
	_active_buffs = {}
	_unlocked_decor = []
	_last_output = ""

func reset_new_game() -> void:
	# §4.4: новая игра — полный сброс, недельное включительно (в отличие от
	# on_prestige, который недельное бережёт).
	_clear_state()

func _load_axis(d: Dictionary, kind: String) -> void:
	var daily := kind == "daily"
	var key_v: Variant = d.get("last_daily" if daily else "last_weekly", "")
	if not (key_v is String):
		return
	var list := _clean_list(d.get("daily" if daily else "weekly", null), kind, String(key_v))
	if list.is_empty():
		# Вместе со списком сбрасывается и ключ: иначе ensure_period() не увидит
		# расхождения и оставит пустую доску до полуночи.
		return
	var ids := {}
	for item in list:
		ids[String((item as Dictionary)["id"])] = int((item as Dictionary)["goal"])
	var done := _clean_log(d.get("daily_done" if daily else "weekly_done", null), ids)
	var prog := _clean_counts(d.get("daily_prog" if daily else "weekly_prog", null), ids)
	if daily:
		_contracts_last_daily = String(key_v)
		_contracts_daily = list
		_contracts_daily_done = done
		_contracts_daily_prog = prog
	else:
		_contracts_last_weekly = String(key_v)
		_contracts_weekly = list
		_contracts_weekly_done = done
		_contracts_weekly_prog = prog

# Структурная проверка одного контракта. Недостижимость gold-тира (тест №23) —
# правило генератора, здесь её нет: иначе сейв, переживший день, отвергался бы
# из-за порядка загрузки Аркана (решение 1).
func _clean_contract(raw: Variant, kind: String, period_key: String) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var d: Dictionary = raw
	var type := String(d.get("type", ""))
	var tier := String(d.get("tier", ""))
	if String(d.get("kind", "")) != kind:
		return {}
	var goals: Dictionary = ContractsBalance.DAILY_GOALS if kind == "daily" else ContractsBalance.WEEKLY_GOALS
	if not goals.has(type):
		return {}
	var tier_idx := ContractsBalance.TIERS.find(tier)
	if tier_idx < 0:
		return {}
	# goal сверяется с таблицей ровно: чужое число означало бы контракт,
	# написанный не этим клиентом.
	var goal := _whole(d.get("goal", null))
	if goal != float(int((goals[type] as Array)[tier_idx])):
		return {}
	var want_id := "%s:%s:%s:%s" % [kind, type, tier, period_key]
	if String(d.get("id", "")) != want_id:
		return {}
	var buff := String(d.get("buff", ""))
	if buff != "" and not ContractsBalance.BUFF_IDS.has(buff):
		return {}
	var decor := String(d.get("decor", ""))
	if decor != "" and not decor_exists(decor):
		return {}
	# Пересборка dict, а не pass-through: лишние ключи из файла не должны
	# переезжать в состояние.
	return {"id": want_id, "kind": kind, "type": type, "tier": tier,
		"goal": int(goal), "buff": buff, "decor": decor}

func _clean_list(raw: Variant, kind: String, period_key: String) -> Array:
	if not (raw is Array) or period_key == "":
		return []
	var want := ContractsBalance.DAILY_SHOWN if kind == "daily" else ContractsBalance.WEEKLY_SHOWN
	if (raw as Array).size() != want:
		return []
	var out: Array = []
	var seen := {}
	for entry in (raw as Array):
		var item := _clean_contract(entry, kind, period_key)
		if item.is_empty() or seen.has(String(item["type"])):
			# Один сомнительный элемент роняет весь список, а не выкидывается:
			# иначе доска показала бы 2 бумажки из 3 и молча потеряла одну.
			return []
		seen[String(item["type"])] = true
		out.append(item)
	return out

func _clean_log(raw: Variant, ids: Dictionary) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var src: Dictionary = raw
	for entry in src:
		var id := String(entry)
		if not ids.has(id):
			continue
		# Залипшая отметка «выдано» по id вне списка позже заблокировала бы
		# законную выдачу того же id после перегенерации — поэтому она не
		# переезжает.
		var v: Variant = src[entry]
		if v is bool and bool(v):
			out[id] = true
	return out

func _clean_counts(raw: Variant, ids: Dictionary) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var src: Dictionary = raw
	for entry in src:
		var id := String(entry)
		if not ids.has(id):
			continue
		var v := _whole(src[entry])
		if v <= 0.0:
			continue
		# Сжатие к goal, а не отказ: игрок, наваривший сверх цели, не должен
		# потерять право на выдачу из-за целого числа больше нужного.
		out[id] = clampi(int(v), 0, int(ids[id]))
	return out

func _clean_free_counts(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var src: Dictionary = raw
	for entry in src:
		if not (entry is String) or String(entry) == "":
			continue
		var v := _whole(src[entry])
		if v > 0.0:
			out[String(entry)] = int(v)
	return out

func _clean_flags(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var src: Dictionary = raw
	for entry in src:
		if not (entry is String) or String(entry) == "":
			continue
		# Ключи variety НЕ режутся по g.ITEMS: срез по каталогу повторил бы ровно
		# дефект Bug B (каталог меняется быстрее, чем неделя), а здесь это просто
		# флаг «варилось на этой неделе».
		var v: Variant = src[entry]
		if v is bool and bool(v):
			out[String(entry)] = true
	return out

func _clean_buffs(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var now := float(_unix(-1))
	var src: Dictionary = raw
	for entry in src:
		var buff_id := String(entry)
		if not ContractsBalance.BUFF_IDS.has(buff_id):
			continue
		if not (src[entry] is Dictionary):
			continue
		var b: Dictionary = src[entry]
		var until := _whole(b.get("until", null))
		if until <= now:
			# §4.4: бафф, истёкший в оффлайне, не применяется и не грузится.
			continue
		var power: Variant = b.get("power", null)
		if not (power is int or power is float) or not is_finite(float(power)) \
				or float(power) < 0.0:
			continue
		# Верхняя граница силы намеренно не придумана: сила — табличное число,
		# умноженное на reward_mult (§3.1), и любой потолок из головы молча
		# съедал бы законную награду. Подмена сверяется сервером (§1.5).
		out[buff_id] = {"until": int(until), "power": float(power)}
	return out

func _clean_decor(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		if not (entry is String):
			continue
		var id := String(entry)
		if id == "" or not decor_exists(id) or out.has(id):
			continue
		# Если каталог когда-нибудь уберёт id, журнал доски потеряет его, а Дом —
		# нет: _own_item уже сделал предмет владением навсегда, и повторная
		# выдача дедуплицируется (home.gd:173).
		out.append(id)
	return out

# ---------- доска v2 (§1 строки 7–8): недельный слой — туманная жила + ярмарка ----------
# Дословный переезд недельной половины retention.gd:523-1058. Дублирование
# здесь переходное и запланировано планом слияния: страница «Неделя» и
# демо-инъектор живут в Retention до Task 5 (файл удаляется там), но состояние и
# логика теперь здесь — второй копии полей больше нет.
# Жила: первооткрытие с тегом недели → +2 очк. дня и 10% прожилка (+1 кап,
# кап 5/нед. — на сервере). Ярмарка: варки пар с выходом-тегом недели идут
# в общий котёл (пара — раз в неделю); закрытый котёл + вклад ≥3 → +0.05/с
# регена навсегда (кап +0.5 суммарно), иначе — утешение эфиром. Теги веществ живут
# на сервере; клиент оперирует только строками недели.

# кэш статуса недели + вечные бонусы (имена сохранены из Retention: по ним
# читаются старые ключи сейва — переезд ключей это Task 6)
var _week_cache: Dictionary = {}
var _week_offline := false
var _vein_cap_total := 0
var _fair_regen_total := 0.0
var _fair_local_week := ""
var _fair_local_brews: Array = []
var _fair_off_claim_week := ""
# цикл жилы, pending finds, предыдущее состояние цикла
var _cycle_cache: Dictionary = {}
var _vein_finds: Array = []
var _cycle_prev_state := ""

func _fetch_week() -> void:
	if not g._online._net_enabled or g._online._device_id == "":
		return
	if not Net.is_available():
		_week_offline = true
		refresh_board()
		return
	Net.week_status(g._online._device_id)
	_fetch_cycle()

func _on_net_week_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		_week_offline = true
		refresh_board()
		return
	_week_offline = false
	_week_cache = result
	g._saves._save_game()
	# доска v2: вклад котла пришёл с сервера — строка fair пересчитывается сразу.
	_sync_fair()
	refresh_board()

func _week_vein() -> Dictionary:
	var v = _week_cache.get("vein", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

# ---------- план 2: цикл жилы ----------

func _fetch_cycle() -> void:
	if not g._online._net_enabled or g._online._device_id == "":
		return
	if not Net.is_available():
		return
	Net.cycle_status(g._online._device_id)

func _on_net_cycle_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		return
	var prev_id := String(_cycle_cache.get("cycle_id", ""))
	_cycle_cache = result
	if String(result.get("state", "")) == "spread" and _cycle_prev_state != "spread":
		# R5: reason — порог достигнут или max_days; duration — от started_at до сегодня
		var wf := int(result.get("world_finds", 0))
		var thr := int(result.get("spread_threshold", 0))
		var dur := 0
		var sa := String(result.get("started_at", ""))
		if sa.length() >= 10:
			dur = maxi(0, int((Time.get_unix_time_from_system() - float(
				Time.get_unix_time_from_datetime_string(sa))) / 86400.0))
		Analytics.track("vein_cycle_spread", {"reason": "threshold" if wf >= thr else "max_days",
			"world_finds": wf, "duration_days": dur})
	_cycle_prev_state = String(result.get("state", ""))
	if prev_id != "" and String(result.get("cycle_id", "")) != prev_id:
		# R1: закрытие старого цикла — невлитые капли его становятся auto_applied
		var autoed := 0
		for f in _vein_finds:
			if typeof(f) == TYPE_DICTIONARY and String(f.get("cycle_id", "")) == prev_id \
					and String(f.get("status", "")) == "registered":
				f["status"] = "auto_applied"
				autoed += 1
				Analytics.track("vein_pour", {"tag": String(f.get("tag", "")), "manual": false})
		Analytics.track("vein_cycle_closed", {"auto_applied_count": autoed,
			"total_points": int(_cycle_cache.get("my_points", 0))})
		_vein_sync_pending()
	g._saves._save_game()
	# доска v2: смена цикла меняет счётчик «только текущий цикл» — строку vein
	# пересчитываем сразу, иначе доска показала бы прогресс закрытого цикла.
	_sync_vein()
	refresh_board()

func _vein_sync_pending() -> void:
	if not Net.is_available() or g._online._device_id == "":
		return
	var cyc := String(_cycle_cache.get("cycle_id", ""))
	if cyc == "":
		return
	for f in _vein_finds:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if String(f.get("status", "")) == "pending_server" and String(f.get("cycle_id", "")) == cyc:
			Net.vein_find(g._online._device_id, String(f["pair_key"]), String(f["tag"]), cyc)

func _vein_find_exists(cycle_id: String, pair_key: String) -> bool:
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("cycle_id", "")) == cycle_id \
				and String(f.get("pair_key", "")) == pair_key:
			return true
	return false

func _vein_find_entry(pair_key: String, cycle_id: String = "") -> Dictionary:
	# Fix #6: та же пара может жить в _vein_finds дважды — заявка текущего цикла
	# и уже зарегистрированная запись прошлого цикла. Ответ сервера (цикл здесь не
	# known) относится к незакрытой заявке, поэтому pending_server приоритетен; без
	# этого цикла find из прошлого цикла перехватил бы ответ (R2-пересоздание
	# ушло бы в старый cycle_id). Если pending нет, берём первую запись той же
	# пары — иначе запоздалый повторный ответ (ok после registered, cycle_mismatch
	# после register) молча терялся и локальная запись оставалась inconsistent.
	var fallback := {}
	for f in _vein_finds:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if String(f.get("pair_key", "")) != pair_key:
			continue
		if cycle_id != "":
			if String(f.get("cycle_id", "")) == cycle_id:
				return f
			continue
		if String(f.get("status", "")) == "pending_server":
			return f
		if fallback.is_empty():
			fallback = f
	return fallback

## server-кэш цикла читается через этот геттер: /api/vein/cycle/status отдаёт
## tag2 как Optional[str] = null (цикл ещё не «расползлся»), а String(null) —
## это ошибка рантайма, которая обрывала бы _commit_brew посреди варки.
func _cache_str(key: String) -> String:
	var v: Variant = _cycle_cache.get(key, "")
	return String(v) if typeof(v) == TYPE_STRING else ""

func _vein_report_pair(a: String, b: String, out: String) -> void:
	# §3.3.1: personal find рождается только для пары из серверной книги, тег
	# которой активен в текущем цикле; anti-farm — одна пара на цикл (R2: без
	# кэша цикла find не заводится).
	if out == "" or not g._online._is_server_pair(a, b):
		return
	var cyc := _cache_str("cycle_id")
	var tag := String(g._online._server_tag.get(out, ""))
	if cyc == "" or tag == "":
		return
	if tag != _cache_str("tag1") and tag != _cache_str("tag2"):
		return
	var pk := g._pair_key(a, b)
	if _vein_find_exists(cyc, pk):
		return
	_vein_finds.append({"id": "%s-%d-%s" % [cyc, int(Time.get_unix_time_from_system()), pk],
		"tag": tag, "points": 1, "found_at": int(Time.get_unix_time_from_system()),
		"pair_key": pk, "cycle_id": cyc, "status": "pending_server", "server_response": {}})
	g._saves._save_game()
	_vein_sync_pending()
	# доска v2: заявка капли меняет набор находок текущего цикла — прогресс
	# строки vein пересчитываем сразу после записи.
	_sync_vein()
	refresh_board()

func _vein_add_from_discover(pair_key: String, out: String, vein: Dictionary) -> void:
	# world-first: сервер уже начислил очки в /discover — капля сразу registered
	if typeof(vein) != TYPE_DICTIONARY or vein.is_empty() or out == "":
		return
	var cyc := String(_cycle_cache.get("cycle_id", ""))
	var tag := String(vein.get("tag", ""))
	if tag == "":
		tag = String(g._online._server_tag.get(out, ""))
	if cyc == "" or tag == "" or _vein_find_exists(cyc, pair_key):
		return
	_vein_finds.append({"id": "wf-%d-%s" % [int(Time.get_unix_time_from_system()), pair_key],
		"tag": tag, "points": int(vein.get("points", Game.VEIN_POINTS_WORLD)),
		"found_at": int(Time.get_unix_time_from_system()), "pair_key": pair_key,
		"cycle_id": cyc, "status": "registered", "server_response": vein})
	g._saves._save_game()
	_sync_vein()
	refresh_board()

func _on_net_vein_find_result(pair_key: String, cycle_id: String, result: Dictionary) -> void:
	if result.get("offline", false) == true:
		return
	if cycle_id == "":
		return
	var f := _vein_find_entry(pair_key, cycle_id)
	if f.is_empty():
		return
	if result.get("ok", false) != true:
		var err := String(result.get("error", ""))
		if err == "cycle_mismatch":
			# R2: пересоздаём find в актуальном цикле сервера
			var new_cyc := String(result.get("cycle_id", ""))
			if new_cyc == "":
				new_cyc = String(_cycle_cache.get("cycle_id", ""))
			f["cycle_id"] = new_cyc
			f["id"] = "%s-%d-%s" % [new_cyc, int(Time.get_unix_time_from_system()), pair_key]
			f["status"] = "pending_server"
			f["points"] = 0
			_vein_sync_pending()
		else:
			_vein_finds.erase(f)  # unknown_pair / tag_mismatch — снимаем
		g._saves._save_game()
		_sync_vein()
		refresh_board()
		return
	f["status"] = "registered"
	f["server_response"] = result
	f["points"] = int(result.get("points", 1))
	Analytics.track("vein_personal_find", {"tag": String(f["tag"]),
		"points": int(result.get("points", 1)), "streak_roll": bool(result.get("streak_added", false)),
		"cycle_id": String(f["cycle_id"])})
	if bool(result.get("cap_reached", false)) and int(f.get("cap_paid", 0)) == 0:
		f["cap_paid"] = 1
		g._engine._grant_ether(Game.VEIN_STREAK_REWARD, "vein_streak_cap")
		Analytics.track("vein_streak_cap", {"cycle_id": String(f["cycle_id"]),
			"reward": Game.VEIN_STREAK_REWARD})
		g._engine.status_text = "Прожилка дошла до капа! +%d ⚡" % Game.VEIN_STREAK_REWARD
	g._saves._save_game()
	_sync_vein()
	refresh_board()

func _vein_tag_slug(tag: String) -> String:
	# тег → любое вещество с этим тегом (для цвета капли); "" если нет
	for slug in g._online._server_tag:
		if String(g._online._server_tag[slug]) == tag:
			return String(slug)
	return ""

func _vein_pour(find_id: String) -> void:
	if not Net.is_available() or g._online._device_id == "":
		g._engine.status_text = "Вливание ждёт связи с миром."
		Sfx.error()
		return
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("id", "")) == find_id:
			if String(f.get("status", "")) != "registered":
				return
			Net.vein_pour(g._online._device_id, find_id)
			return

func _on_net_vein_pour_result(find_id: String, result: Dictionary) -> void:
	if result.get("ok", false) != true:
		return
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY and String(f.get("id", "")) == find_id:
			if String(f.get("status", "")) == "registered":
				f["status"] = "poured"
				Analytics.track("vein_pour", {"tag": String(f.get("tag", "")), "manual": true})
			break
	g._saves._save_game()
	_sync_vein()
	refresh_board()

func _week_fair() -> Dictionary:
	var f = _week_cache.get("fair", {})
	return f if typeof(f) == TYPE_DICTIONARY else {}

func _week_claimable() -> bool:
	var f := _week_fair()
	if f.is_empty():
		return false
	if bool(f.get("closed", false)) and int(f.get("my_contrib", 0)) >= 3 and not bool(f.get("claimed", false)):
		return true
	return typeof(f.get("prev", null)) == TYPE_DICTIONARY

func _fair_report_brew(a: String, b: String) -> void:
	if g._selftest or a == "" or b == "":
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		return
	Net.fair_brew(g._online._device_id, a, b)

func _on_net_fair_brew_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		return
	if bool(result.get("counted", false)):
		g._engine.status_text = "Вклад в котёл ярмарки засчитан! (твоих: %d)" % int(result.get("contrib", 0))
		var f := _week_fair()
		if not f.is_empty():
			f["progress"] = int(result.get("progress", f.get("progress", 0)))
			f["my_contrib"] = int(result.get("contrib", f.get("my_contrib", 0)))
			f["closed"] = bool(result.get("closed", f.get("closed", false)))
			_week_cache["fair"] = f
			g._saves._save_game()
		_sync_fair()
		refresh_board()
		g._engine._refresh()

func _fair_claim() -> void:
	if g._selftest:
		return
	if not g._online._net_enabled or not Net.is_available() or g._online._device_id == "":
		g._engine.status_text = "Ярмарка ждёт связи с миром."
		Sfx.error()
		return
	Net.fair_claim(g._online._device_id)

func _fair_on_brew(output: String) -> void:
	# Локальный котёл (A3): считаем варки разных веществ, чтобы ярмарка жила и
	# без сети — вдвое дешевле на выходе. Чистый счётчик: без гейта selftest,
	# как _circle_on_discovery (suite_resonance_net: его мутации восстанавливаются).
	if output == "":
		return
	var w := Home._iso_week_id()
	if _fair_local_week != w:
		_fair_local_week = w
		_fair_local_brews.clear()
	if not _fair_local_brews.has(output):
		_fair_local_brews.append(output)
		# доска v2: без сети локальный котёл — единственный источник прогресса
		# строки fair, поэтому синк обязателен и здесь (сейв и перерисовка
		# остаются за гейтом selftest, как в оригинале).
		_sync_fair()
		if not g._selftest:
			g._saves._save_game()
			refresh_board()

func _fair_offline_available() -> bool:
	return not g._online._net_enabled or not Net.is_available() or g._online._device_id == ""

func _fair_offline_claimable() -> bool:
	if _fair_off_claim_week == Home._iso_week_id():
		return false
	if _fair_local_week != Home._iso_week_id():
		return false
	return _fair_local_brews.size() >= Game.FAIR_OFFLINE_GOAL \
		and _fair_regen_total < Game.FAIR_REGEN_CAP

# Вечный грант локального котла — тело _fair_offline_claim() БЕЗ проверки гейта:
# у досочного контракта fair гейт уже выполнен в _fair_gate() (иначе claim()
# вернул бы "incomplete"), и повторная проверка отсекла бы законную выдачу доски.
func _fair_offline_grant() -> void:
	_fair_off_claim_week = Home._iso_week_id()
	var before := _fair_regen_total
	_fair_regen_total = minf(Game.FAIR_REGEN_CAP, _fair_regen_total + Game.FAIR_REGEN_EACH * Game.FAIR_OFFLINE_FACTOR)
	g._hub._log_event("Ярмарка без мира: +%.2f регена навсегда (вполовину)" % (_fair_regen_total - before))
	g._engine.status_text = "Локальный котёл закрыт: +%.2f к регену навсегда. Без мира — вполовину." % (_fair_regen_total - before)
	g._spirit._companion_react("milestone", "ярмарка")
	Sfx.stage_up()
	g._saves._save_game()
	refresh_board()
	g._engine._refresh()

func _fair_offline_claim() -> void:
	if not _fair_offline_claimable():
		g._engine.status_text = "Локальный котёл: свари %d разных вещества за неделю (%d/%d)." % [
			Game.FAIR_OFFLINE_GOAL, _fair_local_brews.size(), Game.FAIR_OFFLINE_GOAL]
		Sfx.error()
		return
	_fair_offline_grant()

func _on_net_fair_claim_result(result: Dictionary) -> void:
	if result.get("offline", false) == true or result.get("ok", false) != true:
		g._engine.status_text = "Мир не ответил — награда котла подождёт."
		Sfx.error()
		return
	var grants_raw = result.get("grants")
	var grants: Array = grants_raw as Array if typeof(grants_raw) == TYPE_ARRAY else []
	if grants.is_empty():
		g._engine.status_text = "Забирать пока нечего: котёл варится или вклад уже забран."
		return
	for gr in grants:
		if typeof(gr) != TYPE_DICTIONARY:
			continue
		var gd := gr as Dictionary
		if String(gd.get("kind", "")) == "regen":
			var before := _fair_regen_total
			_fair_regen_total = minf(Game.FAIR_REGEN_CAP, _fair_regen_total + Game.FAIR_REGEN_EACH)
			g._hub._log_event("Ярмарка %s: +%.2f регена навсегда" % [String(gd.get("week", "?")), _fair_regen_total - before])
			g._engine.status_text = "Котёл ярмарки закрыт! +%.2f к регену навсегда." % (_fair_regen_total - before)
			g._spirit._companion_react("milestone", "ярмарка")
			Sfx.legendary()
		else:
			var amount := int(gd.get("amount", 0))
			g._engine._grant_ether(amount, "fair_compensation")
			g._engine.status_text = "Ярмарка %s: утешение +%d ⚡." % [String(gd.get("week", "?")), amount]
			Sfx.stage_up()
	g._saves._save_game()
	_fetch_week()
	_sync_fair()
	refresh_board()
	g._engine._refresh()

func _discover_vein_bonus(result: Dictionary) -> void:
	var v = result.get("vein", null)
	if typeof(v) != TYPE_DICTIONARY or (v as Dictionary).is_empty():
		return
	var vd := v as Dictionary
	if bool(vd.get("streak", false)):
		_vein_cap_total += 1
		g._engine.status_text = "Прожилка в жиле «%s»! +1 к капу навсегда." % g._clean_str(vd.get("tag", ""))
		g._spirit._companion_react("milestone", "жила")
		Sfx.legendary()
		g._saves._save_game()
		g._engine._refresh()
	else:
		g._engine.status_text = "Находка в жиле «%s»: +%d очк. дня!" % [g._clean_str(vd.get("tag", "")), int(vd.get("points", 0))]
		_fetch_week()

# ---------- §1 (доска v2): синки прогресса pinned-строк vein/fair ----------
# Оба пишут абсолютный прогресс и пропускают закрытые контракты — ровно как
# _sync_orders. Из ensure_period() они НЕ вызываются: _set_progress →
# contract_by_id → all_contracts → ensure_period дал бы рекурсивный цикл смены
# периода внутри смены периода.
func _sync_vein() -> void:
	var cyc := String(_cycle_cache.get("cycle_id", ""))
	var n := 0
	for f in _vein_finds:
		if typeof(f) == TYPE_DICTIONARY \
				and (cyc == "" or String(f.get("cycle_id", "")) == cyc) \
				and ["registered", "poured"].has(String(f.get("status", ""))):
			n += 1
	for c in _contracts_weekly:
		var contract := c as Dictionary
		if String(contract["type"]) != "vein":
			continue
		var id := String(contract["id"])
		if _contracts_weekly_done.has(id):
			continue
		_set_progress(id, n)

func _sync_fair() -> void:
	# Вклад котла: онлайн — серверный my_contrib, без сети — локальный счётчик
	# разных варок (A3). Готовность ярмарки на этом прогрессе не строится: она
	# в _fair_gate().
	var n := _fair_local_brews.size() if _fair_offline_available() \
		else int(_week_fair().get("my_contrib", 0))
	for c in _contracts_weekly:
		var contract := c as Dictionary
		if String(contract["type"]) != "fair":
			continue
		var id := String(contract["id"])
		if _contracts_weekly_done.has(id):
			continue
		_set_progress(id, n)

# Готовность ярмарки: закрытый серверный котёл с вкладом ≥3 (награда ещё не
# забрана) либо локальный котёл, который можно закрыть.
func _fair_gate() -> bool:
	var f := _week_fair()
	if not f.is_empty() and bool(f.get("closed", false)) \
			and int(f.get("my_contrib", 0)) >= 3 and not bool(f.get("claimed", false)):
		return true
	return _fair_offline_claimable()

# Единственная точка «перерисовать доску» для переехавшего недельного слоя:
# UI-страницы Круг/Неделя живут в Retention до Task 5, доска — self.
func refresh_board() -> void:
	var b := g.get_node_or_null("ContractBoard")
	if b != null and b.has_method("refresh"):
		b.refresh()
