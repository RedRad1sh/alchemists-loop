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
# Максимум на набор — 9 байт (3 выбора + 3×2), то есть до 32 доступных байт
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
func _generate_daily(day_key: String, daily_crafts: int = -1) -> Array:
	var crafts := daily_crafts if daily_crafts >= 0 else g._sigil._daily_crafts.size()
	var h := _seed_for("daily", day_key)
	var cur := {"i": 0}
	var out: Array = []
	for t in _pick_types(ContractsBalance.DAILY_TYPES, ContractsBalance.DAILY_SHOWN, h, cur):
		var type := String(t)
		var tiers := _tiers_for("daily", type, crafts)
		var tier := String(tiers[_byte(h, int(cur["i"])) % tiers.size()])
		cur["i"] = int(cur["i"]) + 1
		var buff := String(ContractsBalance.BUFF_IDS[
			_byte(h, int(cur["i"])) % ContractsBalance.BUFF_IDS.size()])
		cur["i"] = int(cur["i"]) + 1
		out.append(_make_contract("daily", type, tier, day_key, buff, ""))
	return out

func _generate_weekly(week_key: String) -> Array:
	var h := _seed_for("weekly", week_key)
	var cur := {"i": 0}
	var out: Array = []
	for t in _pick_types(ContractsBalance.WEEKLY_TYPES, ContractsBalance.WEEKLY_SHOWN, h, cur):
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

# ---------- чтение ----------
func daily(now: Dictionary = {}) -> Array:
	ensure_period(now)
	return _contracts_daily

func weekly(now: Dictionary = {}) -> Array:
	ensure_period(now)
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
	return progress(id, now) >= int(c["goal"])
