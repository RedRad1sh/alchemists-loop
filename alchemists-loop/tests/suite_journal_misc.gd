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

	# ---------- T19: Esc/«Назад» — закрытие верхнего модала + условный handled ----------

	# снимок всего, что трогает этот блок
	var _auto0 := g._engine._auto
	var _acancel0 := g._engine._auto_cancel
	var _status0 := g._engine.status_text
	var _wall0 := g._home._cosmetic_wall
	var _floor0 := g._home._cosmetic_floor
	var _themeon0 := g._home._theme_custom_on
	var _auraon0 := g._home._aura_custom_on
	var _tgt0 := g._home._color_target
	var _old0 := g._home._cp_old
	var _oldon0 := g._home._cp_old_on
	var _r0 := g._home._cp_r.value
	var _g0 := g._home._cp_g.value
	var _b0 := g._home._cp_b.value

	# T1: ничего не открыто -> false (Esc НЕ помечен потреблённым — выход из игры достижим)
	Selftest.check("esc modals all closed precondition", _no_modal_visible(g))
	Selftest.check("esc nothing open returns false", g._close_top_modal() == false)
	Selftest.check("esc false branch hid nothing", _no_modal_visible(g)
		and g._engine._auto_cancel == _acancel0 and g._engine.status_text == _status0)

	# T2: магазин декора (z=100) закрывается раньше нижнего попапа настроек хабa
	g._home._decor_popup.visible = true
	g._hub._settings_dim.visible = true
	g._hub._settings_popup.visible = true
	var _t2a := g._close_top_modal()
	Selftest.check("esc decor closes above settings", _t2a
		and not g._home._decor_popup.visible
		and g._hub._settings_popup.visible and g._hub._settings_dim.visible)
	var _t2b := g._close_top_modal()
	Selftest.check("esc settings closes second", _t2b
		and not g._hub._settings_popup.visible and not g._hub._settings_dim.visible)

	# T3: гостевой домик — ветка только закрывает окно. Повторного Net.house_get
	# тут быть не может: _close_house_popup (home.gd) лишь скрывает окно и играет
	# звук — проверено статически, в headless-режиме вызовов Net не понаблюдать.
	g._home._house_popup.visible = true
	var _t3 := g._close_top_modal()
	Selftest.check("esc house popup close only", _t3 and not g._home._house_popup.visible)

	# T4: Esc на палитре = отмена с откатом живого предпросмотра (R3).
	# Не vacuous: cost(wall)=500 > 0, а без отката Back оставил бы применённый,
	# но не купленный кастом.
	g._home._open_color_picker("wall")
	var _wall_before := g._home._cosmetic_wall
	var _unlock_before := bool(g._home._custom_unlocked.get("wall", false))
	var _ether_before := g._engine.ether
	var _cost_positive := int(Game.CUSTOM_COSTS.get("wall", 0)) > 0
	g._home._cp_r.value = fmod(g._home._cp_r.value + 40.0, 256.0)
	g._home._on_cp_slider(g._home._cp_r.value)
	Selftest.check("esc picker preview applied", _cost_positive
		and g._home._color_picker.visible and g._home._color_target == "wall"
		and g._home._cosmetic_wall != _wall_before)
	var _t4 := g._close_top_modal()
	Selftest.check("esc picker cancel rolls back", _t4 and not g._home._color_picker.visible
		and g._home._cosmetic_wall == _wall_before)
	Selftest.check("esc picker cancel keeps unlock",
		bool(g._home._custom_unlocked.get("wall", false)) == _unlock_before)
	Selftest.check("esc picker cancel keeps ether", g._engine.ether == _ether_before)

	# восстановление: ни один модал не остаётся открытым, поля как до блока
	g._home._decor_popup.visible = false
	g._home._color_picker.visible = false
	g._home._house_popup.visible = false
	g._hub._settings_popup.visible = false
	g._hub._settings_dim.visible = false
	g._home._color_target = _tgt0
	g._home._cp_old = _old0
	g._home._cp_old_on = _oldon0
	g._home._cosmetic_wall = _wall0
	g._home._cosmetic_floor = _floor0
	g._home._theme_custom_on = _themeon0
	g._home._aura_custom_on = _auraon0
	g._home._cp_r.value = _r0
	g._home._cp_g.value = _g0
	g._home._cp_b.value = _b0
	# присваивание .value дёргает value_changed -> _on_cp_slider; цвет уже
	# восстановлен выше, переприменяем косметику в исходном виде
	g._home._cosmetic_wall = _wall0
	g._home._cosmetic_floor = _floor0
	g._home._theme_custom_on = _themeon0
	g._home._aura_custom_on = _auraon0
	g._home._apply_cosmetic()
	g._engine._auto = _auto0
	g._engine._auto_cancel = _acancel0
	g._engine.status_text = _status0
	Selftest.check("esc state restored after suite", _no_modal_visible(g)
		and g._home._cosmetic_wall == _wall0 and g._engine.ether == _ether_before)


static func _no_modal_visible(g: Game) -> bool:
	# инвентарь всех модалов, которые закрывает _close_top_modal (main.gd)
	if g._engine._auto:
		return false
	if g._shop._consent_popup != null and g._shop._consent_popup.visible:
		return false
	if g._shop._popup != null and g._shop._popup.visible:
		return false
	if g._popup.visible or g._confirm.visible:
		return false
	if g._saves._return_popup.visible:
		return false
	if g._hub._settings_popup.visible or g._hub._craftable_popup.visible:
		return false
	if g._retort._retort_popup.visible:
		return false
	if g._hub._journal_popup.visible or g._hub._prestige_popup.visible:
		return false
	if g._progress_ui._prog_popup.visible:
		return false
	if g._hub._profile_popup.visible or g._hub._up_popup.visible:
		return false
	if g._spirit._companion_dlg != null and g._spirit._companion_dlg.visible:
		return false
	if g._home._decor_popup.visible or g._home._color_picker.visible:
		return false
	if g._home._house_popup.visible:
		return false
	return true
