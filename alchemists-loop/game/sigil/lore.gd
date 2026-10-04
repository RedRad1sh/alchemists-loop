class_name SigilLore
extends RefCounted
# Детерминированный lore-генератор описаний карт (подпроект C).
#
# Вход: карта каталога {id, process, stage, seed, recipe:[{item_id,...}], ...}.
# Выход: {title, description, effect_hint, warning}.
#
# Детерминизм: каждый слот выбирается через SigilRng, засеянный от (seed, slot).
# Никакого глобального RNG-состояния — один и тот же seed всегда даёт один
# и тот же текст у всех игроков (важно для витрины и обмена).
# Результат для пары (card_id, seed) кэшируется, поэтому повторный вызов
# возвращает ровно тот же текст независимо от истории соседних вызовов.
#
# Данные: game/sigil/data/lore/*.json + data/lore/lexicon.json (грузится по
# требованию через SigilAssets.json_file со static-кэшем).
#
# Правки относительно первой версии:
#   1) описание собирается из готовых предложений: нормализуются пробелы,
#      заглавная буква, терминальная точка; фрагменты больше не склеиваются
#      в «слово слово» и не дают «. в топоре зарождается…»;
#   2) {process}, {stage}, {symbol}, {stone}, {mixture} берутся из
#      lexicon.json в нужном падеже (раньше {process}/{stage} печатали сырые
#      id, а {symbol} — заглушку «знак», отсюда «знак в этом скрыт знак»);
#   3) подстановка — один проход регексом по контексту карты (роли
#      source/target, элементы, лексикон), а не цепочка replace по уже
#      частично подставленному тексту;
#   4) фильтр истории и фильтр сосудов применяются ДО выбора из кандидатов
#      (детерминированно), а не перебором других сидов после выбора; фильтр
#      истории работает по tags.variant/tags.motif (id хвостовой фразы и лида),
#      поэтому в витрине не повторяются одинаковые предложения, а не только
#      одинаковые фрагменты целиком; у ключей разные окна (variant 100,
#      motif 12, id 20), а при переполнении пула фильтр ослабляется по шагам
#      (вплоть до LRU-выбора самых давно использованных кандидатов);
#   5) правило mercury и конфликт «тигель/алембик» работают по тегам
#      (safety, vessel) и по подставленному тексту; при невозможности
#   6) порядок предложений в описании не фиксирован: один из семи ритмов
#      (work/oracle/rite/sign/cue/brief/pulse) выбирается хэшем (card_id, seed),
#      поэтому у карт разная структура текста, но детерминизм сохранён;
#      исправить — деградация до исходного фрагмента с push_warning,
#      карта не теряет описание (раньше возвращалось {}).

const SLOT_FILES := {
	"actions": "data/lore/actions.json",
	"conditions": "data/lore/conditions.json",
	"results": "data/lore/results.json",
	"symbols": "data/lore/symbols.json",
	"warnings": "data/lore/warnings.json",
	"titles": "data/lore/titles.json",
	"effects": "data/lore/effects.json",
}
const ELEMENTS_FILE := "data/lore/elements.json"
const LEXICON_FILE := "data/lore/lexicon.json"
## Слоты описания (набор), порядок задаёт ритм — см. RHYTHMS.
const DESCRIPTION_SLOTS := ["actions", "conditions", "results", "symbols"]
## Ритмы описания: порядок тех же слотов. Выбираются хэшем (card_id, seed),
## то есть описание остаётся чистой функцией карты и не зависит от порядка
## вызовов. «symbols_head»/«symbols_tail» — две фразы слота symbols
## (наблюдение и афоризм) по отдельности; если фраза не делится — вставляется
## целиком на месте head, а tail пропускается.
const RHYTHMS := [
	{"id": "work", "order": ["actions", "conditions", "results", "symbols"], "weight": 8},
	{"id": "oracle", "order": ["results", "actions", "conditions", "symbols"], "weight": 5},
	{"id": "rite", "order": ["conditions", "actions", "results", "symbols"], "weight": 4},
	{"id": "sign", "order": ["symbols", "actions", "conditions", "results"], "weight": 4},
	{"id": "cue", "order": ["actions", "symbols_head", "conditions", "results", "symbols_tail"], "weight": 4},
	{"id": "brief", "order": ["actions", "results", "symbols_tail"], "weight": 3},
	{"id": "pulse", "order": ["actions", "symbols", "conditions", "results"], "weight": 2},
]
## Все слоты, участвующие в выборе (порядок фиксирован → порядок истории).
const ALL_SLOTS := ["actions", "conditions", "results", "symbols", "titles", "effects", "warnings"]
## Глубина истории выборов на слот (храним последние HISTORY записей).
## Окна для ключей разные, потому что один и тот же ключ покрывает разное
## число фрагментов: options.variant — id хвостовой фразы (1-4 фрагмента),
## motif — id лида (6 фрагментов), id — конкретный фрагмент.
## variant-окно 100: конкретная фраза не возвращается в пределах набора игрока
## (100 карт) — при пулах 90…149 хвостов это даёт 3 повтора на набор в худшем
## замере вместо 23 при окне 60. motif-окно 12 и id-окно 20: лид и целый фрагмент
## не возвращаются в ближайших картах.
## Общее окно не делаем: reject-набор растёт как окно x (variant+motif+id) и
## выедает пул кандидатов (на слоте ~72 кандидата), после чего фильтр
## отключается совсем — именно так и появлялись повторы «через 4 карты».
## Минимум кандидатов, при котором согласование по треку включается: если
## подходящих по режиму фрагментов меньше, берём весь пул (иначе логика
## начинает сужать разнообразие сильнее, чем помогает).
const TRACK_MIN := 6
## Слоты, которые подчиняются режиму действия: условия и результат должны
## работать с тем же, с чем работает действие (огонь/вода/воздух/земля/тьма).
const TRACK_SLOTS := ["conditions", "results", "effects"]
## Пары, из которых собирается противоречие: действие без огня (тьма, тишина,
## звёзды), а результат/подсказка говорят про огонь под сосудом.
const TRACK_CONFLICT_FROM := "void"
const TRACK_CONFLICT_WITH := "fire"
const HISTORY := 100
const HISTORY_MOTIF := 12
const HISTORY_ID := 20
## Пары сосудов, которые не должны встречаться в одном описании.
const VESSEL_CONFLICTS := [["тигель", "алембик"]]
## Стеммы сосудов для поиска по подставленному тексту: тег -> корни слов.
const VESSEL_STEMS := {
	"тигель": ["тигел"],
	"алембик": ["алембик"],
	"реторта": ["реторт"],
	"горшок": ["горшок", "горшк"],
	"колба": ["колб"],
}
## Заглушка, если lexicon.json недоступен: {symbol} не должен ломать текст.
const FALLBACK_SYMBOL := "знак"

static var _data: Dictionary = {}
## История последних выборов слота:
## slot -> Array[{id: String, seed: int, variant: String, motif: String}].
## Пропуск действует только для ДРУГОГО seed: повторный вызов того же seed
## обязан вернуть тот же фрагмент (детерминизм), а разные seed не должны
## давать один и тот же фрагмент — и тем более одну и ту же фразу — подряд.
static var _history: Dictionary = {}
## Кэш готовых ответов: "card_id#seed" -> {title, description, ...}.
## Снимает зависимость результата от порядка вызовов (витрина и обмен).
static var _cache: Dictionary = {}
## Счётчики для отчёта о логике (сбрасываются reset_history()).
static var _stat_cards: int = 0
static var _stat_mode_match: int = 0
static var _stat_mode_cond: int = 0
static var _stat_track_conflict: int = 0
static var _stat_frame_cards: int = 0
static var _re_placeholder: RegEx
static var _re_ws: RegEx
static var _re_space_dash: RegEx
static var _re_euphonic_s: RegEx


static func reset_history() -> void:
	## Полный сброс состояния: история слотов и кэш ответов.
	_history = {}
	_cache = {}
	_stat_cards = 0
	_stat_track_conflict = 0
	_stat_frame_cards = 0
	_stat_mode_match = 0
	_stat_mode_cond = 0


static func stats() -> Dictionary:
	## Отчёт о логике: сколько карт посчитано, у скольких режим действия
	## противоречит результату, у скольких есть зачин ритма.
	return {
		"cards": _stat_cards,
		"track_conflicts": _stat_track_conflict,
		"mode_match": (float(_stat_mode_match) / float(_stat_cards)) if _stat_cards > 0 else 0.0,
		"mode_match_cond": (float(_stat_mode_cond) / float(_stat_cards)) if _stat_cards > 0 else 0.0,
		"frame_share": (float(_stat_frame_cards) / float(_stat_cards)) if _stat_cards > 0 else 0.0,
	}


static func clear_cache() -> void:
	## Только кэш ответов (историю слотов не трогаем).
	_cache = {}


static func _re(pattern: String, which: int) -> RegEx:
	## which: 0 — плейсхолдер, 1 — пробелы, 2 — тире с пробелами,
	## 3 — эвфония предлога «с» (с -> со).
	match which:
		0:
			if _re_placeholder == null:
				_re_placeholder = RegEx.new()
				_re_placeholder.compile("\\{([a-z_]+)(?::(gen|dat|acc|ins|prep))?\\}")
			return _re_placeholder
		1:
			if _re_ws == null:
				_re_ws = RegEx.new()
				_re_ws.compile("\\s+")
			return _re_ws
		2:
			if _re_space_dash == null:
				_re_space_dash = RegEx.new()
				_re_space_dash.compile("\\s*—\\s*")
			return _re_space_dash
		_:
			# «с свинцом» -> «со свинцом»: предлог «с» перед «с/з + согласная».
			if _re_euphonic_s == null:
				_re_euphonic_s = RegEx.new()
				# \b в PCRE2 без UCP не работает перед кириллицей — берём lookbehind.
				_re_euphonic_s.compile("(?<![А-Яа-яЁё])с (?=[сз][бвгджклмнпрстфхцчшщ])")
			return _re_euphonic_s


static func _load_elements() -> Dictionary:
	if not _data.has("elements"):
		var parsed: Variant = SigilAssets.json_file(ELEMENTS_FILE)
		var elems: Dictionary = {}
		if parsed is Dictionary:
			var e: Variant = (parsed as Dictionary).get("elements", {})
			if e is Dictionary:
				elems = e as Dictionary
		_data["elements"] = elems
	return _data["elements"] as Dictionary


static func _load_slot(slot: String) -> Array:
	if not _data.has(slot):
		var parsed = SigilAssets.json_file(SLOT_FILES[slot])
		var fragments := []
		if parsed is Dictionary:
			var raw = (parsed as Dictionary).get("fragments", [])
			if raw is Array:
				fragments = raw as Array
		_data[slot] = fragments
	return _data[slot] as Array


static func _load_lexicon() -> Dictionary:
	if not _data.has("lexicon"):
		var parsed: Variant = SigilAssets.json_file(LEXICON_FILE)
		var lex: Dictionary = {}
		if parsed is Dictionary:
			lex = parsed as Dictionary
		_data["lexicon"] = lex
	return _data["lexicon"] as Dictionary


## Падежная форма записи {name, gen, dat, acc, ins, prep}; ключ "name" —
## именительный. Пустые/отсутствующие формы падают на именительный.
static func _form(entry: Variant, case_name: String) -> String:
	if not (entry is Dictionary):
		return ""
	var e := entry as Dictionary
	var v: Variant = e.get(case_name, "")
	if v is String and not (v as String).is_empty():
		return v as String
	v = e.get("name", "")
	if v is String:
		return v as String
	return ""


static func _decline(element_id: String, case_name: String) -> String:
	## Падежная форма элемента из elements.json или сущности из lexicon.json.
	if element_id.is_empty():
		return ""
	var form := _form(_load_elements().get(element_id, null), case_name)
	if form.is_empty():
		form = _form(_load_lexicon().get("entities", {}).get(element_id, null), case_name)
	if form.is_empty():
		return element_id
	return form


static func _lexicon_case(kind: String, id: String, case_name: String) -> String:
	## Падежная форма лексемы лексикона (process/stage/symbol) по её id.
	if id.is_empty():
		return ""
	var group: Variant = _load_lexicon().get(kind, null)
	if not (group is Dictionary):
		return id
	var form := _form((group as Dictionary).get(id, null), case_name)
	if form.is_empty():
		return id
	return form


## Значение плейсхолдера по контексту карты.
static func _resolve(name: String, case_name: String, ctx: Dictionary) -> String:
	match name:
		"source":
			return _decline(str(ctx.get("source_id", "")), case_name)
		"target":
			return _decline(str(ctx.get("target_id", "")), case_name)
		"process":
			return _lexicon_case("process", str(ctx.get("process", "")), case_name)
		"stage":
			return _lexicon_case("stage", str(ctx.get("stage", "")), case_name)
		"symbol":
			var sym: String = _form(ctx.get("symbol", null), case_name)
			return sym if not sym.is_empty() else FALLBACK_SYMBOL
	# {mercury:gen}, {mixture:acc}, {stone} и прочие элементы/сущности
	return _decline(name, case_name)


## Подстановка плейсхолдеров одним проходом (см. README слота).
## Роли: {source}, {target}; лексикон: {process}, {stage}, {symbol}, {stone},
## {mixture}; элементы: {<element_id>}; падеж — суффикс «:gen|dat|acc|ins|prep».
static func _substitute(text: String, ctx: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var re := _re("", 0)
	var out := ""
	var pos := 0
	for m in re.search_all(text):
		out += text.substr(pos, m.get_start(0) - pos)
		var case_name := m.get_string(2)
		if case_name.is_empty():
			case_name = "name"
		out += _resolve(m.get_string(1), case_name, ctx)
		pos = m.get_end(0)
	out += text.substr(pos)
	return out


## Совместимость стадия <-> процесс (Ruling C1, спека §6).
## ВНИМАНИЕ: для rubedo здесь разрешён sublimatio — так было в исходном коде,
## но README (Ruling C1) описывает только coniunctio/calcinatio. Таблицу нужно
## свести со спекой; я поведение не менял, чтобы не разъехаться с каталогом.
static func _compatible(process: String, stage: String) -> bool:
	match stage:
		"nigredo":
			return process in ["calcinatio", "putrefactio", "distillatio"]
		"albedo":
			return process in ["sublimatio", "distillatio", "coniunctio"]
		"rubedo":
			return process in ["coniunctio", "calcinatio", "sublimatio"]
		"citrinitas":
			return process in ["sublimatio", "coniunctio", "distillatio"]
	return false


static func _candidates(slot: String, process: String, stage: String) -> Array:
	## Фрагменты слота, совместимые с (process, stage).
	var out: Array = []
	for f in _load_slot(slot):
		if not (f is Dictionary):
			continue
		var tags = (f as Dictionary).get("tags", {})
		if not (tags is Dictionary):
			continue
		var procs: Array = (tags as Dictionary).get("process", [])
		var stages: Array = (tags as Dictionary).get("stage", [])
		if not (procs is Array) or not (stages is Array):
			continue
		if not (procs as Array).has(process):
			continue
		if not (stages as Array).has(stage):
			continue
		out.append(f)
	return out


static func _pick_weighted(cands: Array, rng: SigilRng) -> Dictionary:
	## Взвешенный детерминированный выбор из кандидатов.
	if cands.is_empty():
		return {}
	var weights := PackedFloat32Array()
	for c in cands:
		var w := int((c as Dictionary).get("weight", 1))
		weights.append(float(maxi(w, 1)))
	var idx := rng.weighted_pick(weights)
	if idx < 0 or idx >= cands.size():
		return {}
	return cands[idx] as Dictionary


## Ключи из истории (выбранные с ДРУГИМ seed), которые надо отсеять.
## У каждого ключа своё окно: variant — длинное, motif/id — короткое.
static func _reject_keys(hist: Array, seed: int, keys: Array = ["variant", "motif", "id"]) -> Dictionary:
	var out: Dictionary = {}
	var n := hist.size()
	for idx in n:
		var entry: Variant = hist[idx]
		if not (entry is Dictionary):
			continue
		var e := entry as Dictionary
		if int(e.get("seed", -1)) == seed:
			continue
		var age := n - idx  # 1 — последний выбор слота
		for key in keys:
			var limit := HISTORY
			if key == "motif":
				limit = HISTORY_MOTIF
			elif key == "id":
				limit = HISTORY_ID
			if age > limit:
				continue
			var v := str(e.get(key, ""))
			if not v.is_empty():
				out[v] = true
	return out


static func _rejected(fragment: Dictionary, reject: Dictionary) -> bool:
	if reject.is_empty():
		return false
	if reject.has(str(fragment.get("id", ""))):
		return true
	var tags: Variant = fragment.get("tags", {})
	if not (tags is Dictionary):
		return false
	for key in ["variant", "motif"]:
		var v: Variant = (tags as Dictionary).get(key, "")
		if v is String and not (v as String).is_empty() and reject.has(v as String):
			return true
	return false


static func _slot_rng(card_id: String, seed: int, slot: String, salt: String = "") -> SigilRng:
	return SigilRng.new(SigilRng.seed_from_string(
		"%s#%d#%s%s" % [card_id, seed, slot, salt]))


static func _tracks(fragment: Dictionary) -> Array:
	## Смысловые треки фрагмента (tags.track). Пусто — фраза нейтральна.
	var out: Array = []
	for t in _tags_array(fragment, "track"):
		out.append(str(t))
	return out


static func _track_ok(fragment: Dictionary, want: Array) -> bool:
	## Фраза подходит режиму: либо пересекается по трекам, либо нейтральна.
	if want.is_empty():
		return true
	var have := _tracks(fragment)
	if have.is_empty():
		return true
	for t in have:
		if want.has(t):
			return true
	return false


static func _frame_spec(rhythm_id: String) -> Dictionary:
	var frames: Variant = _load_lexicon().get("rhythm_frames", {})
	if not (frames is Dictionary):
		return {}
	var spec: Variant = (frames as Dictionary).get(rhythm_id, null)
	return spec as Dictionary if spec is Dictionary else {}


static func _pick_frame(rhythm_id: String, card_id: String, seed: int) -> Dictionary:
	## Зачин под ритм: своя история анти-повтора (окно HISTORY, LRU-деградация).
	var spec := _frame_spec(rhythm_id)
	var texts: Variant = spec.get("texts", [])
	if not (texts is Array) or (texts as Array).is_empty():
		return {}
	var roll := _slot_rng(card_id, seed, "frame_roll", rhythm_id)
	if roll.randf() > float(spec.get("prob", 0.0)):
		return {}
	var cands: Array = []
	for i in (texts as Array).size():
		cands.append({"id": "frame_%s_%02d" % [rhythm_id, i], "text": str((texts as Array)[i])})
	var hist: Array = _history.get("frames", [])
	var reject := _reject_keys(hist, seed, ["variant"])
	var pool: Array = []
	for f in cands:
		if not _rejected(f as Dictionary, reject):
			pool.append(f)
	if pool.is_empty():
		pool = _stale_pool(cands, hist, seed)
	if pool.is_empty():
		pool = cands
	return _pick_weighted(pool, _slot_rng(card_id, seed, "frame", rhythm_id))


static func frame_for(card_id: String, seed: int) -> String:
	## Зачин для карты (для тестов и метрик). Пусто, если зачина нет.
	var rhythm_id := str(_pick_rhythm(card_id, seed).get("id", ""))
	var f := _pick_frame(rhythm_id, card_id, seed)
	return str(f.get("text", ""))


static func _pick_rhythm(card_id: String, seed: int) -> Dictionary:
	## Ритм описания для карты: взвешенный выбор, детерминирован по (card_id, seed).
	var weights := PackedFloat32Array()
	for r in RHYTHMS:
		weights.append(float((r as Dictionary).get("weight", 1)))
	var idx := _slot_rng(card_id, seed, "rhythm").weighted_pick(weights)
	if idx < 0 or idx >= RHYTHMS.size():
		return RHYTHMS[0] as Dictionary
	return RHYTHMS[idx] as Dictionary


static func rhythm_for(card_id: String, seed: int) -> String:
	## id ритма описания для (card_id, seed) — для тестов, метрик и отладки.
	return str(_pick_rhythm(card_id, seed).get("id", ""))


static func _split_symbols(text: String) -> Array:
	## Две фразы слота symbols: наблюдение и афоризм. Пусто, если фраза одна.
	var idx := text.find(". ")
	if idx < 0:
		return []
	var head := text.substr(0, idx + 1).strip_edges()
	var tail := text.substr(idx + 2).strip_edges()
	if head.is_empty() or tail.is_empty():
		return []
	return [head, tail]


static func _tags_array(fragment: Dictionary, key: String) -> Array:
	var tags: Variant = fragment.get("tags", {})
	if not (tags is Dictionary):
		return []
	var v: Variant = (tags as Dictionary).get(key, [])
	if v is String:
		return [v] if not (v as String).is_empty() else []
	if v is Array:
		return v as Array
	return []


## Нормализованные имена сосудов фрагмента: теги vessel + поиск по тексту.
static func _vessels(fragment: Dictionary, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for v in _tags_array(fragment, "vessel"):
		out[str(v)] = true
	var txt := _substitute(str(fragment.get("text", "")), ctx)
	for name in VESSEL_STEMS.keys():
		for stem in VESSEL_STEMS[name]:
			if txt.contains(stem):
				out[name] = true
	return out


static func _conflicts(vessels: Dictionary, used: Dictionary) -> bool:
	for pair in VESSEL_CONFLICTS:
		var a := str(pair[0])
		var b := str(pair[1])
		if (vessels.has(a) and used.has(b)) or (vessels.has(b) and used.has(a)):
			return true
	return false


## Самые «давно использованные» кандидаты: малое число — использован недавно,
## большое — не использовался вовсе (или очень давно). Нужен, когда пул слота
## меньше окна анти-повтора (например titles: 50 шаблонов при окне 100): жёсткий
## фильтр там обнулил бы выбор, а полное снятие фильтра вернуло бы повторы.
static func _stale_pool(cands: Array, hist: Array, seed: int) -> Array:
	var age: Dictionary = {}
	var n := hist.size()
	for idx in n:
		var entry: Variant = hist[idx]
		if not (entry is Dictionary):
			continue
		var e := entry as Dictionary
		if int(e.get("seed", -1)) == seed:
			continue
		var a := n - idx
		for key in ["variant", "id", "motif"]:
			var v := str(e.get(key, ""))
			if v.is_empty():
				continue
			if not age.has(v) or int(age[v]) > a:
				age[v] = a
	var best := -1
	var out: Array = []
	for f in cands:
		if not (f is Dictionary):
			continue
		var fr := f as Dictionary
		var tags: Variant = fr.get("tags", {})
		var vals: Array = [str(fr.get("id", ""))]
		if tags is Dictionary:
			vals.append(str((tags as Dictionary).get("variant", "")))
			vals.append(str((tags as Dictionary).get("motif", "")))
		var a := 0
		for v in vals:
			var key := str(v)
			if key.is_empty():
				continue
			a = 1073741824 if not age.has(key) else maxi(a, int(age[key]))
		if a > best:
			best = a
			out = [fr]
		elif a == best:
			out.append(fr)
	return out


## Фильтры (история слотов и сосуды) применяются ДО взвешенного выбора, чтобы
## результат не зависел от порядка вызовов внутри одной генерации.
static func _pick_slot(slot: String, card_id: String, seed: int, cands: Array,
		used_vessels: Dictionary, ctx: Dictionary, want_tracks: Array = [],
		ban_tracks: Array = []) -> Dictionary:
	# Мягкая деградация: сначала пробуем учесть все ключи, затем отпускаем
	# motif, потом id и лишь в последнюю очередь — variant.
	# Запрет треков (логика, а не вкус) применяется к исходному списку: если
	# фильтровать уже сужённый историей пул, он может стать меньше порога и
	# запрет молча отключится — именно так противоречия и просачивались.
	if not ban_tracks.is_empty():
		var clean: Array = []
		for f in cands:
			var bad := false
			for t in _tracks(f as Dictionary):
				if ban_tracks.has(t):
					bad = true
					break
			if not bad:
				clean.append(f)
		if clean.size() >= TRACK_MIN:
			cands = clean
	var hist_slot: Array = _history.get(slot, [])
	var pool: Array = []
	for keys in [["variant", "motif", "id"], ["variant", "motif"], ["variant"]]:
		var reject := _reject_keys(hist_slot, seed, keys)
		pool = []
		for f in cands:
			if _rejected(f as Dictionary, reject):
				continue
			pool.append(f)
		if not pool.is_empty():
			break
	if pool.is_empty():
		pool = _stale_pool(cands, hist_slot, seed)  # пул меньше окна
	if pool.is_empty():
		pool = cands
	if not want_tracks.is_empty():
		var by_mode: Array = []
		for f in pool:
			if _track_ok(f as Dictionary, want_tracks):
				by_mode.append(f)
		if by_mode.size() >= TRACK_MIN:
			pool = by_mode
	var prefer: Array = []
	for f in pool:
		if not _conflicts(_vessels(f as Dictionary, ctx), used_vessels):
			prefer.append(f)
	if not prefer.is_empty():
		pool = prefer
	return _pick_weighted(pool, _slot_rng(card_id, seed, slot))


## Фрагменты, пригодные под правило mercury (Ruling C2): по тегу safety
## и/или по подставленному тексту.
static func _warning_candidates(ctx: Dictionary, strict: bool) -> Array:
	var out: Array = []
	for f in _load_slot("warnings"):
		if not (f is Dictionary):
			continue
		var frag := f as Dictionary
		var safety := ""
		for s in _tags_array(frag, "safety"):
			safety = str(s)
		var by_tag := safety in ["volatile", "poison"]
		var txt := _substitute(str(frag.get("text", "")), ctx)
		var by_text := (txt.contains("летуч") or txt.contains("яд")
				or txt.contains("отрав") or txt.contains("пары") or txt.contains("дым"))
		if strict:
			if by_tag and by_text:
				out.append(frag)
		elif by_tag or by_text:
			out.append(frag)
	return out


static func _normalize(text: String, ensure_period: bool = true, capitalize: bool = true) -> String:
	## Приведение фрагмента к виду «отдельное предложение»: схлопнутые пробелы,
	## каноническое тире, заглавная буква, терминальная точка.
	var out := _re("", 1).sub(text, " ", true).strip_edges()
	out = _re("", 2).sub(out, " — ", true)
	out = out.replace(" .", ".").replace(" ,", ",").replace(" :", ":")
	out = out.replace(" ;", ";").replace(" !", "!").replace(" ?", "?")
	out = _re("", 3).sub(out, "со ", true)
	out = _re("", 1).sub(out, " ", true).strip_edges()
	if out.is_empty():
		return out
	if capitalize:
		out = out.substr(0, 1).to_upper() + out.substr(1)
	if not ensure_period:
		return out
	for ch in [" ", ",", ";", ":", "—", "–", "-"]:
		if out.ends_with(ch):
			out = out.substr(0, out.length() - ch.length())
	if not (out.ends_with(".") or out.ends_with("!") or out.ends_with("?")):
		out += "."
	return out


## Детерминированный символ карты (уроборос, зеркало, …) из lexicon.json.
static func _symbol_for(card_id: String, seed: int) -> Dictionary:
	var syms: Variant = _load_lexicon().get("symbols", [])
	if not (syms is Array) or (syms as Array).is_empty():
		return {}
	var list := syms as Array
	var weights := PackedFloat32Array()
	for i in list.size():
		weights.append(1.0)
	var idx := _slot_rng(card_id, seed, "symbol").weighted_pick(weights)
	if idx < 0 or idx >= list.size():
		return {}
	var entry: Variant = list[idx]
	if entry is Dictionary:
		return entry as Dictionary
	return {}


static func generate(card: Dictionary) -> Dictionary:
	## Генерирует {title, description, effect_hint, warning} для карты каталога.
	## При некорректном process/stage или пустых данных — {}.
	var card_id := str(card.get("id", ""))
	var process := str(card.get("process", ""))
	var stage := str(card.get("stage", ""))
	if card_id.is_empty() or process.is_empty() or stage.is_empty():
		return {}
	if not _compatible(process, stage):
		return {}
	var seed := int(card.get("seed", 0))
	var cached: Variant = _cache.get("%s#%d" % [card_id, seed], null)
	if cached is Dictionary:
		return (cached as Dictionary).duplicate(true)

	var recipe: Array = card.get("recipe", [])
	if not (recipe is Array) or (recipe as Array).is_empty():
		return {}
	var source_id := ""
	for entry in recipe:
		if entry is Dictionary:
			var item_id := str((entry as Dictionary).get("item_id", ""))
			if not item_id.is_empty():
				source_id = item_id
				break
	if source_id.is_empty():
		return {}
	var target_id := card_id
	var elems := _load_elements()
	if not elems.has(source_id) or not elems.has(target_id):
		return {}

	var ctx := {
		"source_id": source_id,
		"target_id": target_id,
		"process": process,
		"stage": stage,
		"symbol": _symbol_for(card_id, seed),
	}

	var picked: Dictionary = {}  # slot -> fragment
	var used_vessels: Dictionary = {}
	var mode_tracks: Array = []   # режим действия: огонь / вода / воздух / земля / тьма
	for slot in ALL_SLOTS:
		var cands := _candidates(slot, process, stage)
		if cands.is_empty():
			return {}
		var want: Array = mode_tracks if TRACK_SLOTS.has(slot) else []
		var ban: Array = []
		if slot in TRACK_SLOTS and not mode_tracks.is_empty() \
				and mode_tracks.has(TRACK_CONFLICT_FROM) and not mode_tracks.has(TRACK_CONFLICT_WITH):
			ban = [TRACK_CONFLICT_WITH]  # работа идёт без огня — огонь в результате исключён
		var cand := _pick_slot(slot, card_id, seed, cands, used_vessels, ctx, want, ban)
		if cand.is_empty():
			return {}
		picked[slot] = cand
		for v in _vessels(cand, ctx):
			used_vessels[v] = true
		if slot == "actions":
			mode_tracks = _tracks(cand)

	# Правило mercury (Ruling C2): если в тексте есть ртуть — warning обязан
	# говорить про летучесть/яд. Сначала ищем фрагменты, подходящие и по тегу
	# safety, и по тексту; затем только по тегу; затем только по тексту;
	# если ничего нет — оставляем исходный выбор и пишем предупреждение в лог.
	var mercury := false
	for slot in ALL_SLOTS:
		var frag := picked[slot] as Dictionary
		var raw := str(frag.get("text", ""))
		if raw.contains("{mercury") or _substitute(raw, ctx).contains("ртут"):
			mercury = true
			break
	var mercury_fixed := false
	if mercury:
		for strict in [true, false]:
			var safe := _warning_candidates(ctx, strict)
			if safe.is_empty():
				continue
			var reject_w := _reject_keys(_history.get("warnings", []), seed)
			var pool: Array = []
			for f in safe:
				if _rejected(f as Dictionary, reject_w):
					continue
				if not _conflicts(_vessels(f as Dictionary, ctx), used_vessels):
					pool.append(f)
			if pool.is_empty():
				for f in safe:
					if not _conflicts(_vessels(f as Dictionary, ctx), used_vessels):
						pool.append(f)
			if pool.is_empty():
				pool = safe
			var cand_w := _pick_weighted(pool, _slot_rng(card_id, seed, "warnings", "#mercury"))
			if not cand_w.is_empty():
				if strict:
					mercury_fixed = true
				picked["warnings"] = cand_w
				break
		if not mercury_fixed:
			push_warning("SigilLore: %s#%d — не нашёлся warning под ртуть, оставлен исходный" % [card_id, seed])

	# Конфликт сосудов («тигель» и «алембик» не в одном описании): сначала
	# пытаемся заменить слот, который внёс конфликт, свободным кандидатом.
	for pair in VESSEL_CONFLICTS:
		var a := str(pair[0])
		var b := str(pair[1])
		if not (used_vessels.has(a) and used_vessels.has(b)):
			continue
		var fixed := false
		for slot in [ "warnings", "titles", "effects", "symbols", "results", "conditions", "actions" ]:
			var cur := picked[slot] as Dictionary
			var cur_v := _vessels(cur, ctx)
			if not (cur_v.has(a) or cur_v.has(b)):
				continue
			var other: Dictionary = {}
			other[b if cur_v.has(a) else a] = true
			var pool_strict: Array = []  # без обоих сосудов пары
			var pool_ok: Array = []      # без конфликтующего сосуда
			var reject_v := _reject_keys(_history.get(slot, []), seed)
			for f in _candidates(slot, process, stage):
				if _rejected(f as Dictionary, reject_v):
					continue
				var fv := _vessels(f as Dictionary, ctx)
				if _conflicts(fv, other):
					continue
				pool_ok.append(f)
				if not (fv.has(a) or fv.has(b)):
					pool_strict.append(f)
			var pool: Array = pool_strict if not pool_strict.is_empty() else pool_ok
			if slot == "warnings" and mercury:
				var safe := _warning_candidates(ctx, mercury_fixed)
				if not safe.is_empty():
					pool = safe
			var cand := _pick_weighted(pool, _slot_rng(card_id, seed, slot, "#vessel"))
			if not cand.is_empty():
				picked[slot] = cand
				fixed = true
				break
		if not fixed:
			push_warning("SigilLore: %s#%d — конфликт сосудов %s/%s не разрешён" % [card_id, seed, a, b])

	# Финальная проверка логики: переподбор сосудов мог заменить действие целиком,
	# поэтому согласование «режим → результат» проверяем ещё раз по факту.
	var final_tracks := _tracks(picked["actions"] as Dictionary)
	if final_tracks.has(TRACK_CONFLICT_FROM) and not final_tracks.has(TRACK_CONFLICT_WITH):
		for slot in ["results", "effects"]:
			if not _tracks(picked[slot] as Dictionary).has(TRACK_CONFLICT_WITH):
				continue
			# Через штатный селектор: он сам разводит историю по окнам и уходит
			# в LRU, если пул меньше окна (иначе фильтр «без огня» вычистит всё).
			var repicked := _pick_slot(slot, card_id, seed, _candidates(slot, process, stage),
				used_vessels, ctx, final_tracks, [TRACK_CONFLICT_WITH])
			if not repicked.is_empty():
				picked[slot] = repicked

	# Собираем выход: каждый фрагмент — отдельное предложение (4-6 предложений).
	# Порядок задаёт ритм карты (см. RHYTHMS).
	var title := _normalize(_substitute(str(picked["titles"].get("text", "")), ctx), false)
	var rhythm := _pick_rhythm(card_id, seed)
	var item_text: Dictionary = {}
	for slot in DESCRIPTION_SLOTS:
		item_text[slot] = _normalize(_substitute(str(picked[slot].get("text", "")), ctx), true)
	var halves := _split_symbols(str(item_text["symbols"]))
	item_text["symbols_head"] = str(halves[0]) if halves.size() == 2 else str(item_text["symbols"])
	item_text["symbols_tail"] = str(halves[1]) if halves.size() == 2 else ""
	var desc_parts: Array = []
	for part in rhythm.get("order", DESCRIPTION_SLOTS) as Array:
		var chunk := str(item_text.get(str(part), ""))
		if not chunk.is_empty():
			desc_parts.append(chunk)
	# Зачин ритма: отдельная фраза, своя история анти-повтора.
	var rhythm_id := str(rhythm.get("id", ""))
	var frame := _pick_frame(rhythm_id, card_id, seed)
	if not frame.is_empty():
		var frame_text := _normalize(_substitute(str(frame.get("text", "")), ctx), true)
		var at := clampi(int(_frame_spec(rhythm_id).get("at", 0)), 0, desc_parts.size())
		if not frame_text.is_empty() and not desc_parts.has(frame_text):
			desc_parts.insert(at, frame_text)
			_stat_frame_cards += 1
		var fh: Array = _history.get("frames", [])
		fh.append({"id": str(frame.get("id", "")), "seed": seed,
			"variant": str(frame.get("id", "")), "motif": rhythm_id})
		if (fh as Array).size() > HISTORY:
			(fh as Array).pop_front()
		_history["frames"] = fh
	var description := " ".join(desc_parts)
	var effect_hint := _normalize(_substitute(str(picked["effects"].get("text", "")), ctx), true)
	var warning := _normalize(_substitute(str(picked["warnings"].get("text", "")), ctx), true)

	# История: записываем {id, seed, variant, motif} слота (для теста повторов)
	for slot in ALL_SLOTS:
		var h: Array = _history.get(slot, [])
		var frag := picked[slot] as Dictionary
		var tags: Variant = frag.get("tags", {})
		h.append({
			"id": str(frag.get("id", "")),
			"seed": seed,
			"variant": str((tags as Dictionary).get("variant", "")) if tags is Dictionary else "",
			"motif": str((tags as Dictionary).get("motif", "")) if tags is Dictionary else "",
		})
		if (h as Array).size() > HISTORY:
			(h as Array).pop_front()
		_history[slot] = h

	# Логика: если действие идёт без огня (тьма, тишина, звёзды), результат и
	# подсказка не должны говорить про огонь под сосудом.
	var from_tracks := _tracks(picked["actions"] as Dictionary)
	var quiet_work := from_tracks.has(TRACK_CONFLICT_FROM) and not from_tracks.has(TRACK_CONFLICT_WITH)
	var conflict := false
	if quiet_work:
		for slot in ["results", "effects"]:
			if _tracks(picked[slot] as Dictionary).has(TRACK_CONFLICT_WITH):
				conflict = true
				break
	_stat_cards += 1
	if conflict:
		_stat_track_conflict += 1
	var res_tracks := _tracks(picked["results"] as Dictionary)
	if from_tracks.is_empty() or res_tracks.is_empty() or _track_ok(picked["results"] as Dictionary, from_tracks):
		_stat_mode_match += 1
	if from_tracks.is_empty() or _track_ok(picked["conditions"] as Dictionary, from_tracks):
		_stat_mode_cond += 1

	var result := {
		"title": title,
		"description": description,
		"effect_hint": effect_hint,
		"warning": warning,
	}
	_cache["%s#%d" % [card_id, seed]] = result.duplicate(true)
	return result
