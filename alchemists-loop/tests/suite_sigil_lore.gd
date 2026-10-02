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