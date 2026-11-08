extends RefCounted
class_name SuiteSigilCardEffects
# Бонусы карт коллекции по редкости (roadmap §8.2), ослабленные вдвое против
# исходного черновика: скорость линий %, кап эфира, стадии автономности.


static func run(g: Game) -> void:
	var mgr = g._sigil
	if mgr == null or not mgr.has_method("card_speed_bonus") or not mgr.has_method("card_cap_bonus") \
			or not mgr.has_method("card_autonomy_bonus"):
		Selftest.check("card_effects: bonus API exists", false)
		return
	var saved_collection: Dictionary = mgr._server_collection.duplicate(true)
	var saved_extras: Array = mgr._server_extras.duplicate(true)
	var saved_catalog: Dictionary = mgr._catalog.duplicate(true)

	mgr._server_collection = {}
	mgr._server_extras = []
	Selftest.check("card_effects: empty collection gives no bonus",
		mgr.card_speed_bonus() == 0.0 and mgr.card_cap_bonus() == 0 and mgr.card_autonomy_bonus() == 0)
	var base_cap: int = g._engine._max_ether()
	var base_stages: int = g._workshop.offline_stage_limit()
	var sched := WorkshopScheduler.new(g, g._workshop)
	var base_interval: float = sched._interval({"queue": []})

	# Редкость — из каталога: серверная коллекция хранит только copies/first_at.
	mgr._catalog["fx_leg"] = {"id": "fx_leg", "rarity": "legendary"}
	mgr._server_collection = {"fx_leg": {"copies": 1, "first_at": "1"}}
	Selftest.check("card_effects: legendary from catalog → speed +2%",
		absf(mgr.card_speed_bonus() - 2.0) < 0.01)
	Selftest.check("card_effects: legendary → cap +10", mgr.card_cap_bonus() == 10)
	Selftest.check("card_effects: legendary → autonomy +4 (3.75 rounded)", mgr.card_autonomy_bonus() == 4)

	mgr._catalog["fx_c"] = {"id": "fx_c", "rarity": "common"}
	mgr._catalog["fx_r"] = {"id": "fx_r", "rarity": "rare"}
	mgr._catalog["fx_e"] = {"id": "fx_e", "rarity": "epic"}
	mgr._server_collection = {"fx_c": {"copies": 1}, "fx_r": {"copies": 1}, "fx_e": {"copies": 1}}
	Selftest.check("card_effects: common+rare+epic → speed 0.25+0.75+1.25",
		absf(mgr.card_speed_bonus() - 2.25) < 0.01)
	Selftest.check("card_effects: common+rare+epic → cap 1.25+3.75+6.25 ≈ 11",
		mgr.card_cap_bonus() == 11)
	Selftest.check("card_effects: common+rare+epic → autonomy 0.5+1.25+2.5 ≈ 4",
		mgr.card_autonomy_bonus() == 4)

	# Копии одной карты бонус не умножают: считается открытая карта.
	mgr._server_collection = {"fx_leg": {"copies": 5}}
	Selftest.check("card_effects: copies do not stack", absf(mgr.card_speed_bonus() - 2.0) < 0.01)

	# Хроматик — внекомплектный крафт в extras; множитель скорости вдвое слабее.
	mgr._server_collection = {}
	mgr._server_extras = [{"craft_id": "x1", "rarity": "chromatic", "effects": {"speed_mult": 1.2}}]
	Selftest.check("card_effects: chromatic speed_mult 1.2 → +10% speed",
		absf(mgr.card_speed_bonus() - 10.0) < 0.01)

	# Бонусы реально доходят до кап-эфира, автономности и интервала линий.
	mgr._server_extras = []
	mgr._server_collection = {"fx_leg": {"copies": 1}}
	Selftest.check("card_effects: cap bonus reaches max ether", g._engine._max_ether() == base_cap + 10)
	Selftest.check("card_effects: autonomy bonus reaches workshop stage limit",
		g._workshop.offline_stage_limit() == base_stages + 4)
	Selftest.check("card_effects: speed bonus shortens the line interval",
		is_equal_approx(sched._interval({"queue": []}), base_interval * 0.98))

	mgr._server_collection = saved_collection
	mgr._server_extras = saved_extras
	mgr._catalog = saved_catalog
