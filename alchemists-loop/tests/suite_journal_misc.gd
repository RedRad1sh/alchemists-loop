extends RefCounted
class_name SuiteJournalMisc
# сброс/повтор/журнал/звук/что-вапить/добыть-всё (оп B1).

static func run(g: Game) -> void:
	# полный сброс — в самом конце, так как меняет состояние
	g._engine.inventory.clear()
	for i in 35:
		g._engine.inventory["st_pr_%d" % i] = 1
	var sg_before := g._engine.sage_gold
	g._hub._do_prestige()
	Selftest.check("prestige resets", g._engine.sage_gold > sg_before and g._engine.inventory.size() == 4
		and g._engine.ether == Game.START_ETHER and g._engine.upgrades.is_empty() and g._engine.known_recipes.size() == 2)

	# повтор последней пары
	g._engine.inventory["fire"] = 3
	g._engine.inventory["water"] = 3
	g._engine._last_pair = ["fire", "water"]
	g._engine.selected = []
	g._engine._repeat_last()
	Selftest.check("repeat places pair", g._engine.selected == ["fire", "water"])
	g._engine.inventory["fire"] = 0
	g._engine.selected = []
	g._engine._repeat_last()
	Selftest.check("repeat fails without stock", g._engine.selected == [])
	g._engine.inventory["fire"] = 3

	# журнал событий
	g._hub._log_events.clear()
	g._hub._log_event("Тест A")
	g._hub._log_event("Тест B")
	Selftest.check("journal order", String(g._hub._log_events[0]["text"]) == "Тест B")
	for i in 50:
		g._hub._log_event("X")
	Selftest.check("journal cap", g._hub._log_events.size() == 40)
	g._hub._log_events.clear()

	# настройки звука
	var _v0 := Sfx.sfx_volume
	Sfx.set_sfx_volume(0.4)
	Selftest.check("sfx volume set", absf(Sfx.sfx_volume - 0.4) < 0.001)
	Sfx.set_sfx_volume(2.5)
	Selftest.check("sfx volume clamp", Sfx.sfx_volume == 1.0)
	Sfx.set_sfx_volume(_v0)

	# что варить сейчас
	g._engine.known_recipes.clear()
	g._engine.inventory.clear()
	g._engine.inventory["fire"] = 2
	g._engine.inventory["water"] = 2
	var _cp1 := g._hub._craftable_pairs()
	var _has_steam := false
	for p in _cp1:
		if String(p["out"]) == "steam":
			_has_steam = true
	Selftest.check("craftable lists fire+water", _has_steam)
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	var _cp2 := g._hub._craftable_pairs()
	var _still_steam := false
	for p in _cp2:
		if String(p["out"]) == "steam":
			_still_steam = true
	Selftest.check("craftable skips known", not _still_steam)
	g._engine.known_recipes.clear()

	# round-trip сейва: журнал + настройки звука
	g._hub._log_events.clear()
	g._hub._log_event("Проверка сохранения")
	Sfx.set_sfx_volume(0.3)
	Sfx.set_music_volume(0.6)
	var _music_was := Sfx.music_on
	g._saves._save_game()
	g._hub._log_events.clear()
	Sfx.set_sfx_volume(1.0)
	Sfx.set_music_volume(1.0)
	g._saves._load_game()
	Selftest.check("journal persists", g._hub._log_events.size() == 1 and String(g._hub._log_events[0]["text"]) == "Проверка сохранения")
	Selftest.check("sfx volume persists", absf(Sfx.sfx_volume - 0.3) < 0.001)
	Selftest.check("music volume persists", absf(Sfx.music_volume - 0.6) < 0.001)
	Selftest.check("music_on persists", Sfx.music_on == _music_was)
	g._hub._log_events.clear()

	# добыть всё
	var _before := {}
	for b in Game.BASE_IDS:
		_before[String(b)] = int(g._engine.inventory.get(b, 0))
	g._engine._collect_all()
	var _all_grew := true
	for b in Game.BASE_IDS:
		if int(g._engine.inventory.get(b, 0)) <= int(_before[String(b)]):
			_all_grew = false
	Selftest.check("collect all grows every base", _all_grew)
	Selftest.check("category title helper", g._progress_ui._cat_title("огонь") == "Стихия Огня")
	Selftest.check("companion sprite map", g._spirit._companion_sprite("success_new") == "laugh"
		and g._spirit._companion_sprite("fail") == "sad" and g._spirit._companion_sprite("world_first") == "charged")
	Selftest.check("companion levels", g._spirit._companion_level_for(0) == 1 and g._spirit._companion_level_for(15) == 2
		and g._spirit._companion_level_for(35) == 3 and g._spirit._companion_level_for(70) == 4)
