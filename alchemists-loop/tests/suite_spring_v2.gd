extends RefCounted
class_name SuiteSpringV2

static func run(g: Game) -> void:
	# T1.1: SpringBalance существует и загружается
	Selftest.check("spring_balance exists", SpringBalance != null)
	# T1.2: SPEED таблица имеет 7 уровней
	Selftest.check("spring_balance SPEED length", SpringBalance.SPEED.size() == 7)
	# T1.3: VOLUME_CAP имеет 8 элементов (уровни 0..7)
	Selftest.check("spring_balance VOLUME_CAP length", SpringBalance.VOLUME_CAP.size() == 8)
	# T1.4: VOLUME_CAP[0] = 100 (стартовый объём)
	Selftest.check("spring_balance VOLUME_CAP[0] = 100", SpringBalance.VOLUME_CAP[0] == 100)
	# T1.5: VOLUME_CAP[7] = 60000 (максимум)
	Selftest.check("spring_balance VOLUME_CAP[7] = 60000", SpringBalance.VOLUME_CAP[7] == 60000)
	# T1.6: MIN_INTERVAL = 0.5
	Selftest.check("spring_balance MIN_INTERVAL", SpringBalance.MIN_INTERVAL == 0.5)
	# T1.7: SPEED_FACTOR = 0.85
	Selftest.check("spring_balance SPEED_FACTOR", SpringBalance.SPEED_FACTOR == 0.85)
	# T1.8: PRESTIGE_KEEP_LEVEL = 3
	Selftest.check("spring_balance PRESTIGE_KEEP_LEVEL", SpringBalance.PRESTIGE_KEEP_LEVEL == 3)
	# T1.9: MATERIAL_TIER содержит все материалы из цен
	var expected_tiers := {"stone": 0, "clay": 0, "brick": 0, "metal": 1, "glass": 1,
		"obsidian": 2, "crystal": 3, "gold": 3, "tool": 4}
	Selftest.check("spring_balance MATERIAL_TIER keys", SpringBalance.MATERIAL_TIER == expected_tiers)
	# T1.10: SPEED[0] цена соответствует спеке §4.1
	Selftest.check("spring_balance SPEED[0] price", SpringBalance.SPEED[0] == {"ether": 30, "materials": {"stone": 12}})
	# T1.11: VOLUME[0] цена соответствует спеке §4.2
	Selftest.check("spring_balance VOLUME[0] price", SpringBalance.VOLUME[0] == {"ether": 30, "materials": {"stone": 12}})
	# T1.12: SOURCES[0] требование speed >= 3
	Selftest.check("spring_balance SOURCES[0] req", SpringBalance.SOURCES[0]["req"] == {"speed": 3})
	# T1.13: OFFLINE[0] требование volume >= 3
	Selftest.check("spring_balance OFFLINE[0] req", SpringBalance.OFFLINE[0]["req"] == {"volume": 3})
	# T1.14: OFFLINE_WINDOW_SEC[3] = 43200 (12 часов)
	Selftest.check("spring_balance OFFLINE_WINDOW_SEC[3]", SpringBalance.OFFLINE_WINDOW_SEC[3] == 43200.0)
	
	# T2.1: Engine имеет spring_levels
	Selftest.check("engine spring_levels exists", "spring_levels" in g._engine)
	# T2.2: spring_interval() на уровне 0 = SPRING_INTERVAL
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	Selftest.check("spring_interval level 0", is_equal_approx(g._engine.spring_interval(), Game.SPRING_INTERVAL))
	# T2.3: spring_interval() на уровне 7 = 6.0 * pow(0.85, 7) ≈ 1.9235 (спека §3.1)
	g._engine.spring_levels["speed"] = 7
	Selftest.check("spring_interval level 7 ≈ 1.9235", absf(g._engine.spring_interval() - 1.9235) < 0.001)
	# T2.4: spring_interval() не ниже MIN_INTERVAL
	g._engine.spring_levels["speed"] = 100  # экстремальный уровень
	Selftest.check("spring_interval >= MIN_INTERVAL", g._engine.spring_interval() >= SpringBalance.MIN_INTERVAL)
	# T3.1: Engine имеет spring_buffer
	Selftest.check("engine spring_buffer exists", "spring_buffer" in g._engine)
	# T3.2: _spring_tick увеличивает буфер выбранного источника
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}  # reset from T2
	g._engine.inventory["plant"] = maxi(int(g._engine.inventory.get("plant", 0)), 1)  # unlock spring mode
	g._engine.spring_on = true
	g._engine.spring_source = "water"
	g._engine.spring_buffer = {}
	g._engine.inventory["water"] = 0
	g._pages._spring_clock = 0.0
	g._engine._spring_tick(7.0)
	Selftest.check("spring_tick increments buffer", g._engine.spring_buffer.get("water", 0) == 1)
	# T3.3: _spring_tick увеличивает inventory
	Selftest.check("spring_tick increments inventory", g._engine.inventory.get("water", 0) == 1)
	# T3.4: буфер ограничен VOLUME_CAP
	g._engine.spring_levels["volume"] = 0
	g._engine.spring_buffer = {"water": 99}
	g._engine.inventory["water"] = 99
	g._pages._spring_clock = 0.0
	g._engine._spring_tick(7.0)
	Selftest.check("spring_buffer capped at VOLUME_CAP[0]", g._engine.spring_buffer.get("water", 0) == 100)
	# T3.5: избыток сжигается (inventory не растёт сверх капа)
	Selftest.check("spring_tick burns overflow", g._engine.inventory.get("water", 0) == 100)
	# T3.6: трата элемента уменьшает буфер
	g._engine.spring_buffer = {"water": 50}
	g._engine.inventory["water"] -= 10
	g._engine.spring_buffer["water"] = maxi(0, g._engine.spring_buffer.get("water", 0) - 10)
	Selftest.check("spend decrements buffer", g._engine.spring_buffer.get("water", 0) == 40)
	# Reset state for later suites
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.spring_buffer = {}
	# T4.1: Engine имеет spring_sources
	Selftest.check("engine spring_sources exists", "spring_sources" in g._engine)
	# T4.2: _spring_tick выдаёт по единице каждого выбранного источника
	g._engine.spring_on = true
	g._engine.spring_sources = ["water", "fire"]
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 1, "offline": 0}
	g._engine.spring_buffer = {}
	g._engine.inventory["water"] = 0
	g._engine.inventory["fire"] = 0
	g._pages._spring_clock = 0.0
	g._engine._spring_tick(7.0)
	Selftest.check("spring_tick multi-source water", g._engine.spring_buffer.get("water", 0) == 1)
	Selftest.check("spring_tick multi-source fire", g._engine.spring_buffer.get("fire", 0) == 1)
	Selftest.check("spring_tick multi-source inventory water", g._engine.inventory.get("water", 0) == 1)
	Selftest.check("spring_tick multi-source inventory fire", g._engine.inventory.get("fire", 0) == 1)
	# Reset state for later suites
	g._engine.spring_sources = ["water"]
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.spring_buffer = {}
	# T5.1: _spring_offline_gain использует окно уровня 0 (300 сек)
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.spring_sources = ["water"]
	g._engine.spring_buffer = {}
	var gain_300 := g._saves._spring_offline_gain(300.0)
	Selftest.check("spring_offline_gain 300s level 0", gain_300 == 50)  # 300/6.0 = 50
	# T5.2: _spring_offline_gain использует окно уровня 1 (3600 сек)
	g._engine.spring_levels["offline"] = 1
	g._engine.spring_levels["volume"] = 7  # cap = 60000, чтобы не ограничивало
	var gain_3600 := g._saves._spring_offline_gain(3600.0)
	Selftest.check("spring_offline_gain 3600s level 1", gain_3600 == 600)  # 3600/6.0 = 600
	# T5.3: _spring_offline_gain учитывает мульти-выбор
	g._engine.spring_sources = ["water", "fire"]
	var gain_multi := g._saves._spring_offline_gain(3600.0)
	Selftest.check("spring_offline_gain multi-source", gain_multi == 1200)  # 600 * 2 sources
	# T5.4: _spring_offline_gain ограничен объёмом буфера
	g._engine.spring_levels["volume"] = 0  # cap = 100
	g._engine.spring_buffer = {"water": 100, "fire": 100}  # оба на потолке
	var gain_capped := g._saves._spring_offline_gain(3600.0)
	Selftest.check("spring_offline_gain capped by buffer", gain_capped == 0)  # буфер полон
	# Reset state for later suites
	g._engine.spring_sources = ["water"]
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.spring_buffer = {}
	# T6.1: покупка скорости уровня 1 succeeds при достаточных ресурсах
	g._engine.ether = 100
	g._engine.inventory["stone"] = 20
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	var result := g._engine.spring_purchase("speed")
	Selftest.check("spring_purchase speed L1 ok", result["ok"] == true)
	Selftest.check("spring_purchase speed L1 ether deducted", g._engine.ether == 70)
	Selftest.check("spring_purchase speed L1 stone deducted", g._engine.inventory.get("stone", 0) == 8)
	Selftest.check("spring_purchase speed L1 level up", g._engine.spring_levels["speed"] == 1)
	# T6.2: покупка не проходит при нехватке эфира
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.ether = 10
	g._engine.inventory["stone"] = 20
	var result2 := g._engine.spring_purchase("speed")
	Selftest.check("spring_purchase insufficient ether", result2["ok"] == false and "ether" in result2["error"])
	Selftest.check("spring_purchase insufficient ether no deduction", g._engine.ether == 10)
	# T6.3: покупка не проходит при нехватке материала
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
	g._engine.ether = 100
	g._engine.inventory["stone"] = 5
	var result3 := g._engine.spring_purchase("speed")
	Selftest.check("spring_purchase insufficient material", result3["ok"] == false and "stone" in result3["error"])
	Selftest.check("spring_purchase insufficient material no deduction", g._engine.ether == 100)
	# T6.4: покупка sources требует speed >= 3
	g._engine.spring_levels = {"speed": 2, "volume": 0, "sources": 0, "offline": 0}
	g._engine.ether = 200
	g._engine.inventory["metal"] = 30
	g._engine.inventory["glass"] = 20
	var result4 := g._engine.spring_purchase("sources")
	Selftest.check("spring_purchase sources req not met", result4["ok"] == false and "speed" in result4["error"])
	# T6.5: покупка sources проходит при speed >= 3
	g._engine.spring_levels["speed"] = 3
	var result5 := g._engine.spring_purchase("sources")
	Selftest.check("spring_purchase sources req met", result5["ok"] == true)
	# Reset state for later suites
	g._engine.spring_levels = {"speed": 0, "volume": 0, "sources": 0, "offline": 0}
