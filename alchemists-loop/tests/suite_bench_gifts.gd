extends RefCounted
class_name SuiteBenchGifts
# верстак/дары (оп B1).

static func run(g: Game) -> void:
	# верстак: варит выбранное сам
	g._pages._bench_target = "steam"
	g._pages._bench_on = true
	g._pages._bench_clock = 0.0
	g._engine.inventory["fire"] = 5
	g._engine.inventory["water"] = 5
	g._engine.inventory["steam"] = 0
	g._engine.ether = 200
	g.BREW_SECONDS = 0.05
	g._pages._bench_tick(Game.BENCH_INTERVAL + 0.01)
	Selftest.check("bench keeps kettle free", not g._engine.brewing and g._pages._bench_busy)
	await g.get_tree().create_timer(0.5).timeout
	Selftest.check("bench brews solo", int(g._engine.inventory.get("steam", 0)) >= 1
		and g._engine.ether <= 200 - Game.BREW_COST + 2)
	Selftest.check("bench released", not g._pages._bench_busy and not g._engine.brewing)
	g._pages._bench_on = false

	# лимит Production: небольшой запас, дальше не варит
	g._engine.inventory["steam"] = Game.BENCH_LIMIT
	g._pages._bench_target = "steam"
	g._pages._bench_on = true
	g._pages._bench_clock = 0.0
	g._pages._bench_tick(Game.BENCH_INTERVAL + 0.01)
	Selftest.check("bench cap stops at limit", int(g._engine.inventory.get("steam", 0)) == Game.BENCH_LIMIT and not g._pages._bench_busy)
	g._engine.inventory["steam"] = Game.BENCH_LIMIT - 1
	g._pages._bench_clock = 0.0
	g._pages._bench_tick(Game.BENCH_INTERVAL + 0.01)
	await g.get_tree().create_timer(0.5).timeout
	Selftest.check("bench cap brews to limit", int(g._engine.inventory.get("steam", 0)) == Game.BENCH_LIMIT)
	g._pages._bench_on = false

	# «Дары»: случайное уже открытое вещество каждые 2 минуты
	g._engine.ether = 1000
	Selftest.check("gift buy", g._engine._buy_upgrade("auto_gift") and g._engine._up_lvl("auto_gift") == 1)
	Selftest.check("gift single level", g._engine._buy_upgrade("auto_gift") == false and g._engine._up_lvl("auto_gift") == 1)
	var nonbase_before := 0
	for item_id in g._engine.inventory:
		if not Game.BASE_IDS.has(String(item_id)):
			nonbase_before += int(g._engine.inventory[item_id])
	g._engine._gift_clock = 0.0
	g._engine._gift_tick(Game.GIFT_INTERVAL + 0.01)
	var nonbase_after := 0
	for item_id in g._engine.inventory:
		if not Game.BASE_IDS.has(String(item_id)):
			nonbase_after += int(g._engine.inventory[item_id])
	Selftest.check("gift drops opened item", nonbase_after == nonbase_before + 1)
	g._engine._gift_clock = 0.0
	g._engine._gift_tick(Game.GIFT_INTERVAL * 0.5)
	var nonbase_half := 0
	for item_id in g._engine.inventory:
		if not Game.BASE_IDS.has(String(item_id)):
			nonbase_half += int(g._engine.inventory[item_id])
	Selftest.check("gift waits full interval", nonbase_half == nonbase_after)

	# ============ U38 (A5): афиши стоков не дрейфуют от констант ============
	var u38_desc := ""
	for u38_u in Game.UPGRADES:
		if String((u38_u as Dictionary).get("id", "")) == "auto_gift":
			u38_desc = String((u38_u as Dictionary).get("desc", ""))
	Selftest.check("u38 gift poster matches const", u38_desc.contains("%d мин" % int(Game.GIFT_INTERVAL / 60.0)))
	var u38_found := 0
	for u38_c in g._pages._bench_page_labels:
		if String(u38_c).contains("%d с" % int(Game.BENCH_INTERVAL)) and String(u38_c).contains("%d шт" % Game.BENCH_LIMIT):
			u38_found += 1
	Selftest.check("u38 bench poster matches const", u38_found >= 1)
