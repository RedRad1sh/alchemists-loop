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
#
# Данные: game/sigil/data/lore/*.json, грузятся по требованию через
# SigilAssets.json_file с static-кэшем.

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
## Порядок сборки description: action, condition, result, symbol.
const DESCRIPTION_SLOTS := ["actions", "conditions", "results", "symbols"]
## Размер истории последних id на слот (без повторов подряд).
const HISTORY := 3

static var _data: Dictionary = {}
## История последних выборов слота: slot -> Array[{id: String, seed: int}].
## Пропуск id при выборе действует только для ДРУГОГО seed: повторный вызов
## того же seed обязан вернуть тот же фрагмент (детерминизм), а разные seed
## не должны давать один и тот же фрагмент подряд.
static var _history: Dictionary = {}


static func reset_history() -> void:
	_history = {}


static func _decline(element_id: String, case_name: String) -> String:
	## Падежная форма элемента из elements.json.
	var elems: Dictionary = _load_elements()
	var e = elems.get(element_id, {})
	if e is Dictionary:
		var v = (e as Dictionary).get(case_name, "")
		if v is String and not (v as String).is_empty():
			return v as String
	return element_id


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


## Совместимость стадия <-> процесс (Ruling C1, спека §6).
static func _compatible(process: String, stage: String) -> bool:
	match stage:
		"nigredo":
			return process in ["calcinatio", "putrefactio", "distillatio"]
		"albedo":
			return process in ["sublimatio", "distillatio", "coniunctio"]
		"rubedo":
			return process in ["coniunctio", "calcinatio"]
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


## Подстановка плейсхолдеров в текст фрагмента.
## Роли: {process}, {stage}, {symbol}, {stone} (строки-аргументы); {source}, {target}
## (элементы); {element:case} — падеж элемента; {role:case} — падеж source/target.
static func _substitute(text: String, source_id: String, target_id: String,
		process: String, stage: String) -> String:
	var out := text
	# Плейсхолдеры-строки (без падежа)
	out = out.replace("{process}", process)
	out = out.replace("{stage}", stage)
	out = out.replace("{symbol}", "знак")
	out = out.replace("{stone}", _decline("stone", "gen"))
	out = out.replace("{source}", _decline(source_id, "name"))
	out = out.replace("{target}", _decline(target_id, "name"))
	# Плейсхолдеры-падежи
	var re := RegEx.new()
	re.compile(r"\{([a-z_]+):(gen|dat|acc|ins|prep)\}")
	for m in re.search_all(out):
		var eid := m.get_string(1)
		var case_name := m.get_string(2)
		var decl := ""
		if eid == "source":
			decl = _decline(source_id, case_name)
		elif eid == "target":
			decl = _decline(target_id, case_name)
		else:
			decl = _decline(eid, case_name)
		out = out.replace(m.get_string(0), decl)
	return out



## True, если id встречается в истории с seed, отличным от данного.
static func _in_history(hist: Array, id: String, seed: int) -> bool:
	for entry in hist:
		if entry is Dictionary:
			if str((entry as Dictionary).get("id", "")) == id 					and int((entry as Dictionary).get("seed", -1)) != seed:
				return true
	return false

static func generate(card: Dictionary) -> Dictionary:
	## Генерирует {title, description, effect_hint, warning} для карты каталога.
	## При некорректном process/stage или пустых данных — {}.
	var process := str(card.get("process", ""))
	var stage := str(card.get("stage", ""))
	if process == "" or stage == "":
		return {}
	if not _compatible(process, stage):
		return {}
	var seed := int(card.get("seed", 0))
	var recipe: Array = card.get("recipe", [])
	if recipe.is_empty():
		return {}
	var source_id := str((recipe[0] as Dictionary).get("item_id", ""))
	var target_id := str(card.get("id", ""))
	var elems := _load_elements()
	if not elems.has(source_id) or not elems.has(target_id):
		return {}

	var picked: Dictionary = {}  # slot -> fragment
	for slot in DESCRIPTION_SLOTS + ["titles", "effects", "warnings"]:
		var cands := _candidates(slot, process, stage)
		if cands.is_empty():
			return {}
		var rng := SigilRng.new(SigilRng.seed_from_string(
			"%s#%d#%s" % [str(card.get("id", "")), seed, slot]))
		var cand := _pick_weighted(cands, rng)
		var attempts := 0
		var hist: Array = _history.get(slot, [])
		# Пропускаем кандидата, если его id уже в истории с ДРУГИМ seed.
		while not cand.is_empty() and attempts < 8 and _in_history(hist, str(cand.get("id", "")), seed):
			attempts += 1
			var rng2 := SigilRng.new(SigilRng.seed_from_string(
				"%s#%d#%s#%d" % [str(card.get("id", "")), seed, slot, attempts]))
			cand = _pick_weighted(cands, rng2)
		if cand.is_empty():
			return {}
		picked[slot] = cand

	# Совместимость текста: mercury -> warning с safety volatile/poison;
	# «тигель» и «алембик» не в одном описании.
	var has_mercury := false
	var full_text := ""
	for slot in DESCRIPTION_SLOTS + ["titles", "effects", "warnings"]:
		var frag := picked[slot] as Dictionary
		var txt := _substitute(str(frag.get("text", "")), source_id, target_id, process, stage)
		full_text += txt + " "
		if txt.contains("ртут") or str(frag.get("text", "")).contains("{mercury"):
			has_mercury = true

	if has_mercury:
		# перевыбираем warning из фрагментов с safety volatile/poison
		var safe := []
		for f in _load_slot("warnings"):
			var safety := str((f as Dictionary).get("tags", {}).get("safety", ""))
			if safety == "volatile" or safety == "poison":
				safe.append(f)
		if safe.is_empty():
			return {}
		var rng_w := SigilRng.new(SigilRng.seed_from_string(
			"%s#%d#warnings#mercury" % [str(card.get("id", "")), seed]))
		picked["warnings"] = _pick_weighted(safe, rng_w)

	# «тигель»+«алембик» конфликт: если оба в тексте — перегенерируем warning
	var merged := ""
	for slot in DESCRIPTION_SLOTS + ["titles", "effects", "warnings"]:
		merged += str(picked[slot].get("text", "")) + " "
	if merged.contains("тигел") and merged.contains("алембик"):
		# перевыбор warning (если он виноват) — простой цикл до совместимости
		var rng_w2 := SigilRng.new(SigilRng.seed_from_string(
			"%s#%d#warnings#conflict" % [str(card.get("id", "")), seed]))
		var attempts2 := 0
		while attempts2 < 12:
			attempts2 += 1
			var cw := _pick_weighted(_load_slot("warnings"), rng_w2)
			if cw.is_empty():
				break
			var tw := _substitute(str(cw.get("text", "")), source_id, target_id, process, stage)
			var all_but_w := ""
			for slot in DESCRIPTION_SLOTS + ["titles", "effects"]:
				all_but_w += str(picked[slot].get("text", "")) + " "
			if not (all_but_w.contains("тигел") and tw.contains("алембик")):
				picked["warnings"] = cw
				break

	# Собираем выход
	var title := _substitute(str(picked["titles"].get("text", "")), source_id, target_id, process, stage)
	var desc_parts: Array = []
	for slot in DESCRIPTION_SLOTS:
		var part := _substitute(str(picked[slot].get("text", "")), source_id, target_id, process, stage)
		# Каждый фрагмент — отдельное предложение с точкой (3-6 предложений).
		part = part.strip_edges()
		if not part.ends_with(".") and not part.ends_with("!") and not part.ends_with("?"):
			part += "."
		desc_parts.append(part)
	var description := " ".join(desc_parts)
	var effect_hint := _substitute(str(picked["effects"].get("text", "")), source_id, target_id, process, stage)
	var warning := _substitute(str(picked["warnings"].get("text", "")), source_id, target_id, process, stage)

	# История: записываем {id, seed} слота (для теста повторов)
	for slot in DESCRIPTION_SLOTS + ["titles", "effects", "warnings"]:
		var h: Array = _history.get(slot, [])
		h.append({"id": str(picked[slot].get("id", "")), "seed": seed})
		if (h as Array).size() > HISTORY:
			(h as Array).pop_front()
		_history[slot] = h

	return {
		"title": title,
		"description": description,
		"effect_hint": effect_hint,
		"warning": warning,
	}