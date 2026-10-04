extends RefCounted
class_name SuiteSigilLore
# Аркан Сигилов: детерминированный lore-генератор (движок game/sigil/lore.gd).


## Каталог-карта с фиксированным сидом (как в sb6).
static func _card_steam() -> Dictionary:
	return {
		"id": "steam", "set": "fire", "rarity": "common", "ether_cost": 50,
		"recipe": [{"item_id": "water", "qty": 10}, {"item_id": "fire", "qty": 10}],
		"process": "sublimatio", "stage": "albedo", "fallback_name": "Пар",
		"object_type": "object", "seed": 123456789,
	}


## Подсчёт предложений в тексте (split по .!?).
static func _sentences(text: String) -> int:
	var n := 0
	for i in text.length():
		var ch := text[i]
		if ch == "." or ch == "!" or ch == "?":
			n += 1
	return n



## 11 пар (process, stage) реального каталога — фикстуры карт.
static func _catalog_pairs() -> Array:
	return [
		["sublimatio", "albedo"],
		["calcinatio", "nigredo"],
		["distillatio", "citrinitas"],
		["distillatio", "nigredo"],
		["sublimatio", "rubedo"],
		["coniunctio", "citrinitas"],
		["coniunctio", "rubedo"],
		["coniunctio", "albedo"],
		["putrefactio", "nigredo"],
		["distillatio", "albedo"],
		["sublimatio", "citrinitas"],
	]


static func _card_for(process: String, stage: String, seed: int) -> Dictionary:
	return {
		"id": "steam", "set": "fire", "rarity": "common", "ether_cost": 50,
		"recipe": [{"item_id": "water", "qty": 10}, {"item_id": "fire", "qty": 10}],
		"process": process, "stage": stage, "fallback_name": "Пар",
		"object_type": "object", "seed": seed,
	}


static func run(g: Game) -> void:
	# ---- Task 3: движок lore.gd ----
	var card := _card_steam()
	var res := SigilLore.generate(card)
	Selftest.check("sb_lore generates for catalog card",
		(not str(res.get("title", "")).is_empty()
		and not str(res.get("description", "")).is_empty()
		and _sentences(str(res.get("description", ""))) >= 3
		and _sentences(str(res.get("description", ""))) <= 6))

	var res2 := SigilLore.generate(card)
	var same: bool = (res.get("title", "") == res2.get("title", "")
		and res.get("description", "") == res2.get("description", "")
		and res.get("effect_hint", "") == res2.get("effect_hint", "")
		and res.get("warning", "") == res2.get("warning", ""))
	Selftest.check("sb_lore deterministic same seed", same)

	# другой seed -> (с вероятностью >=0.9) отличается description
	var card2 := _card_steam()
	card2["seed"] = 987654321
	var res3 := SigilLore.generate(card2)
	Selftest.check("sb_lore different seed differs", res3.get("description", "") != res.get("description", ""))

	# падежи
	Selftest.check("sb_lore declines element",
		SigilLore._decline("steam", "gen") == "пара"
		and SigilLore._decline("mercury", "acc") == "ртуть")

	# нет неподставленных плейсхолдеров
	var all_text := str(res.get("title", "")) + str(res.get("description", "")) + str(res.get("effect_hint", "")) + str(res.get("warning", ""))
	Selftest.check("sb_lore no unresolved placeholders", not all_text.contains("{"))

	# неизвестный process -> {}
	var bad := _card_steam()
	bad["process"] = "осадок и прессовка"
	var res_bad := SigilLore.generate(bad)
	Selftest.check("sb_lore unknown process returns empty", res_bad.is_empty())

	# история повторов: 20 генераций на разных seed-семействах (одна карта,
	# seed меняется) — текст соседних генераций не должен повторяться
	SigilLore.reset_history()
	var prev_desc := ""
	var no_repeat := true
	for i in 20:
		var c := _card_steam()
		c["seed"] = 1000000 + i
		var r := SigilLore.generate(c)
		if r.is_empty():
			no_repeat = false
			break
		var d := str(r.get("description", ""))
		if d == prev_desc:
			no_repeat = false
			break
		prev_desc = d
	Selftest.check("sb_lore slot history no immediate repeats", no_repeat)

	# ---- Task 4: нагрузочный сьют ----
	# 1) все 11 пар каталога дают непустой текст
	var all_pairs_ok := true
	var _pairs_index := 0
	for pair in _catalog_pairs():
		_pairs_index += 1
		var c := _card_for(str(pair[0]), str(pair[1]), 555000 + _pairs_index)
		var rr := SigilLore.generate(c)
		if str(rr.get("description", "")).is_empty():
			all_pairs_ok = false
	Selftest.check("sb_lore all catalog pairs generate", all_pairs_ok)

	# 2) 1000 генераций: ни одного неподставленного плейсхолдера
	var no_ph := true
	for i in 1000:
		var c := _card_for("sublimatio", "albedo", 700000 + i)
		var rr := SigilLore.generate(c)
		if rr.is_empty():
			no_ph = false
			break
		var txt := str(rr.get("title", "")) + str(rr.get("description", "")) + str(rr.get("effect_hint", "")) + str(rr.get("warning", ""))
		if txt.contains("{"):
			# Диагностика: печать проблемного фрагмента (seed + контекст) прямо
			# в вывод раннера — локализует неподставленный плейсхолдер за прогон.
			var k: int = txt.find("{")
			print("[FAIL-DIAG] lore ph seed=%d :: %s" % [700000 + i, txt.substr(maxi(0, k - 60), 120)])
			no_ph = false
			break
	Selftest.check("sb_lore 1000 generations no placeholders", no_ph)

	# 3) длина description в [150, 600]: ритм «brief» (3 слота без conditions)
	# даёт до ~179 символов — порог 200 писался под данные v1 (до лексикона).
	var len_ok := true
	for i in 1000:
		var c := _card_for("coniunctio", "rubedo", 800000 + i)
		var rr := SigilLore.generate(c)
		if rr.is_empty():
			len_ok = false
			break
		var dlen := str(rr.get("description", "")).length()
		if dlen < 150 or dlen > 600:
			len_ok = false
			break
	Selftest.check("sb_lore 1000 length in range", len_ok)

	# 4) mercury: если в тексте «ртут» — warning про летучесть/яд
	var mercury_ok := true
	for i in 200:
		var c := _card_for("coniunctio", "albedo", 900000 + i)
		var rr := SigilLore.generate(c)
		if rr.is_empty():
			continue
		var body := str(rr.get("description", "")) + str(rr.get("title", ""))
		if body.contains("ртут"):
			var warn := str(rr.get("warning", ""))
			# Семантика v2 (Ruling C2): ртуть летуча — «пары» и «дым» тоже говорят
			# про опасность испарений; тест сверяется с движком (_warning_candidates).
			if not (warn.contains("летуч") or warn.contains("яд") or warn.contains("отрав")
					or warn.contains("пары") or warn.contains("дым")):
				mercury_ok = false
				break
	Selftest.check("sb_lore mercury warning", mercury_ok)

	# 5) тигель+алембик не вместе ни в одной из 1000 генераций
	var no_ca := true
	for i in 1000:
		var c := _card_for("distillatio", "nigredo", 1000000 + i)
		var rr := SigilLore.generate(c)
		if rr.is_empty():
			continue
		var txt := str(rr.get("title", "")) + str(rr.get("description", "")) + str(rr.get("warning", ""))
		if txt.contains("тигел") and txt.contains("алембик"):
			no_ca = false
			break
	Selftest.check("sb_lore no crucible+alembic", no_ca)

	# 6) детерминизм: тот же seed (после reset) даёт тот же текст
	var c1 := _card_for("sublimatio", "albedo", 123456789)
	SigilLore.reset_history()
	var r_a: Dictionary = SigilLore.generate(c1)
	SigilLore.reset_history()
	var r_b: Dictionary = SigilLore.generate(c1)
	Selftest.check("sb_lore determinism repeat seed",
		str(r_a.get("description", "")) == str(r_b.get("description", ""))
		and str(r_a.get("title", "")) == str(r_b.get("title", "")))