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
