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
	var _oktext0 := g._home._cp_ok.text
	var _cust_theme0 := bool(g._home._custom_unlocked.get("theme", false))
	# _close_decor_popup прокручивает страницу дома наверх, если открыта вкладка «Дом»
	var _page3: ScrollContainer = null
	if g._tabs_ref != null and g._tabs_ref.get_child_count() > 3:
		_page3 = g._tabs_ref.get_child(3) as ScrollContainer
	var _scroll0 := 0
	if _page3 != null:
		_scroll0 = _page3.scroll_vertical

	# Слив возможных утечек из предыдущих сюит ДО проверок: иначе утёкшая попап
	# (а) красит T1 чужим дефектом и (б) крадёт второй вызов в T2, отчего краснеет
	# и «esc settings closes second». Входная проверка называется первой и красится
	# всегда, когда стек был не пуст (утечка, которую Esc не умеет закрывать, красит
	# и нижние кейсы — это честно, но именована она вот этой строкой).
	var _drain := 0
	while _drain < 25 and not _no_modal_visible(g):
		if g._engine._auto:
			# Esc автоварку не закрывает, слив тут бессилен: выходим и честно
			# красим входную проверку ниже, а не 25 холостых итераций
			break
		if not g._close_top_modal():
			break
		_drain += 1
	Selftest.check("esc stack was clean on entry", _drain == 0 and _no_modal_visible(g))

	# T1: пустой стек -> false. Наблюдаемо ровно решение «закрывать нечего»; что
	# именно из-за этого Esc не помечается потреблённым и выход из игры достижим —
	# следствие в main.gd:1342-1344, оно в headless не проверяется (осознанный зазор).
	var _mk := InputEventKey.new()
	_mk.pressed = true
	_mk.keycode = KEY_A
	var _unpressed := _esc_key()
	_unpressed.pressed = false
	var _not_key := InputEventMouseButton.new()
	Selftest.check("esc nothing open returns false", g._handle_esc(_esc_key()) == false)
	Selftest.check("esc false branch hid nothing", _no_modal_visible(g)
		and g._engine._auto_cancel == _acancel0 and g._engine.status_text == _status0)

	# T2: магазин декора (z=100) закрывается раньше нижнего попапа настроек хабa —
	# и закрывается именно хелпером (R4), а не «просто visible=false»: у хелпера
	# есть наблюдаемый побочный эффект, пересборка страницы дома (текст кнопки
	# палитры зависит от _custom_unlocked["theme"]).
	var _t2_btn: Button = g._home._theme_btns.get("__custom", null)
	g._home._custom_unlocked["theme"] = false
	g._home._theme_custom_on = false
	g._home._refresh_house_page()
	var _t2_stale := "кнопки нет" if _t2_btn == null else _t2_btn.text
	g._home._custom_unlocked["theme"] = true
	g._home._decor_popup.visible = true
	g._hub._settings_dim.visible = true
	g._hub._settings_popup.visible = true
	# Предикат ESC проверяется ПРИ ОТКРЫТОЙ модалке. На пустом стеке это бессмысленно:
	# там _close_top_modal() вернёт false в любом случае, поэтому и потеря `ke.pressed`,
	# и потеря проверки keycode прошли бы зелёными.
	Selftest.check("esc wiring ignores non-key events", g._handle_esc(_not_key) == false
		and g._home._decor_popup.visible and g._hub._settings_popup.visible)
	Selftest.check("esc wiring ignores other keys", g._handle_esc(_mk) == false
		and g._home._decor_popup.visible and g._hub._settings_popup.visible)
	Selftest.check("esc wiring ignores key release", g._handle_esc(_unpressed) == false
		and g._home._decor_popup.visible and g._hub._settings_popup.visible)
	var _t2a := g._handle_esc(_esc_key())
	Selftest.check("esc decor closes above settings", _t2a
		and not g._home._decor_popup.visible
		and g._hub._settings_popup.visible and g._hub._settings_dim.visible)
	Selftest.check("esc decor close goes through the helper", _t2_btn != null
		and _t2_btn.text != _t2_stale and _t2_btn.text == "Палитра")
	var _t2b := g._handle_esc(_esc_key())
	Selftest.check("esc settings closes second", _t2b
		and not g._hub._settings_popup.visible and not g._hub._settings_dim.visible)

	# T3: гостевой домик — ветка только закрывает окно. Повторного Net.house_get
	# тут быть не может: _close_house_popup (home.gd) лишь скрывает окно и играет
	# звук — проверено статически, в headless-режиме вызовов Net не понаблюдать.
	g._home._house_popup.visible = true
	var _t3 := g._handle_esc(_esc_key())
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
	# watch item для реального Godot-прогона: сравнение ниже опирается на то, что
	# цвет из шестнадцатеричной константы (alpha 1.0, квантованный 0..255) проходит
	# через слайдер без потери. Для нестандартного/полупрозрачного _cosmetic_wall
	# равенство могло бы разойтись — на устройстве проверить первым делом.
	var _t4 := g._handle_esc(_esc_key())
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
	g._home._custom_unlocked["theme"] = _cust_theme0
	# присваивание .value дёргает value_changed -> _on_cp_slider ->
	# _set_custom_color(_color_target, ...). Таргет на время слайдеров пустой:
	# если предыдущая сюита оставила "theme"/"aura", были бы перезаписаны
	# _theme_custom/_aura_custom — Color-поля вне этого снапшота.
	g._home._color_target = ""
	g._home._cp_r.value = _r0
	g._home._cp_g.value = _g0
	g._home._cp_b.value = _b0
	g._home._color_target = _tgt0
	g._home._cp_old = _old0
	g._home._cp_old_on = _oldon0
	g._home._cp_ok.text = _oktext0
	g._home._cosmetic_wall = _wall0
	g._home._cosmetic_floor = _floor0
	g._home._theme_custom_on = _themeon0
	g._home._aura_custom_on = _auraon0
	g._home._apply_cosmetic()
	g._home._refresh_house_page()
	if _page3 != null:
		_page3.scroll_vertical = _scroll0
	g._engine._auto = _auto0
	g._engine._auto_cancel = _acancel0
	g._engine.status_text = _status0
	Selftest.check("esc state restored after suite", _no_modal_visible(g)
		and g._home._cosmetic_wall == _wall0 and g._engine.ether == _ether_before)

	# ---------- T22: очередь проверок чеков и журнал покупок вне wipe ----------

	# Политика начисления по ответу валидатора — чистая функция Monetization, без
	# стора и сети. Релизная сборка выдаёт товар только при verified:true; отладка
	# выдаёт и когда валидатор НЕ СМОГ ответить (offline / гейт выключен / 5xx),
	# но никогда — когда он ответил отказом по существу.
	var _verified := {"ok": true, "verified": true, "status": "processed"}
	var _refused := {"ok": false, "verified": false, "status": "pending"}
	var _offline := {"ok": false, "offline": true, "message": "нет ответа от сервера"}
	var _gate_off := {"ok": false, "verified": false, "reason": "vendor_validation_disabled"}
	var _gate_missing := {"ok": false, "verified": false, "reason": "vendor_validation_not_implemented"}
	var _http503 := {"ok": false, "error": "HTTP 503", "message": "HTTP 503"}
	var _http409 := {"ok": false, "error": "HTTP 409", "message": "HTTP 409"}
	Selftest.check("t22 policy verified grants in both builds",
		Monetization.receipt_grant_allowed(_verified, false) and Monetization.receipt_grant_allowed(_verified, true))
	Selftest.check("t22 policy release blocks everything unverified",
		not Monetization.receipt_grant_allowed(_refused, false)
		and not Monetization.receipt_grant_allowed(_offline, false)
		and not Monetization.receipt_grant_allowed(_gate_off, false)
		and not Monetization.receipt_grant_allowed(_http503, false)
		and not Monetization.receipt_grant_allowed(_http409, false))
	Selftest.check("t22 policy debug grants when validator unreachable",
		Monetization.receipt_grant_allowed(_offline, true)
		and Monetization.receipt_grant_allowed(_gate_off, true)
		and Monetization.receipt_grant_allowed(_gate_missing, true)
		and Monetization.receipt_grant_allowed(_http503, true))
	Selftest.check("t22 policy debug respects real refusals",
		not Monetization.receipt_grant_allowed(_refused, true)
		and not Monetization.receipt_grant_allowed(_http409, true)
		and not Monetization.receipt_grant_allowed({}, true))

	# Корреляция ответов с очередью: 5xx/4xx/offline приходят без тела, то есть без
	# receipt_hash, — тогда снимается голова; ответ со своим отпечатком снимает свой
	# запрос; чужой отпечаток не снимает ничего (иначе начисление уехало бы не туда).
	var _rq0: Array = Monetization._verify_requests.duplicate(true)
	Monetization._verify_requests.clear()
	Monetization._verify_requests.append({"provider": "google_play", "sku": "sku_a", "token": "tok_a", "product_id": "a"})
	Monetization._verify_requests.append({"provider": "google_play", "sku": "sku_b", "token": "tok_b", "product_id": "b"})
	Selftest.check("t22 queue dedupes the same receipt", Monetization._verify_request_index("google_play", "sku_b", "tok_b") == 1
		and Monetization._verify_request_index("google_play", "sku_b", "tok_other") == -1)
	Selftest.check("t22 foreign hash takes nothing", Monetization._take_verify_request("tok_z".sha256_text()).is_empty()
		and Monetization._verify_requests.size() == 2)
	var _own_b: Dictionary = Monetization._take_verify_request("tok_b".sha256_text())
	Selftest.check("t22 own hash takes its own request", String(_own_b.get("product_id", "")) == "b"
		and Monetization._verify_requests.size() == 1)
	var _head_a: Dictionary = Monetization._take_verify_request("")
	Selftest.check("t22 bodyless answer takes the head", String(_head_a.get("product_id", "")) == "a"
		and Monetization._verify_requests.is_empty())
	Selftest.check("t22 extra answer on empty queue is dropped", Monetization._take_verify_request("").is_empty()
		and Monetization._take_verify_request("tok_a".sha256_text()).is_empty())
	Monetization._verify_requests = _rq0

	# Журнал покупок. Пути UserData переводятся на ST-префикс — тем же приёмом, что
	# selftest.gd делает с путями сейва: иначе кейс «переживает wipe» стирал бы
	# реальные данные установки машины, на которой он запущен.
	var _us0 := UserData.SAVE_PATH
	var _ut0 := UserData.TEMP_PATH
	var _ub0 := UserData.BACKUP_PATH
	var _up0 := UserData.PURCHASES_PATH
	var _upt0 := UserData.PURCHASES_TEMP_PATH
	var _data0: Dictionary = UserData._data.duplicate(true)
	var _processed0: Dictionary = UserData._processed.duplicate(true)
	var _granted0: Dictionary = UserData._granted.duplicate(true)
	UserData.SAVE_PATH = "user://alchemy_st_user.json"
	UserData.TEMP_PATH = "user://alchemy_st_user.tmp"
	UserData.BACKUP_PATH = "user://alchemy_st_user.bak"
	UserData.PURCHASES_PATH = "user://alchemy_st_purchases.json"
	UserData.PURCHASES_TEMP_PATH = "user://alchemy_st_purchases.tmp"
	var _st_paths := [UserData.SAVE_PATH, UserData.TEMP_PATH, UserData.BACKUP_PATH, UserData.PURCHASES_PATH, UserData.PURCHASES_TEMP_PATH]
	_t22_remove_paths(_st_paths)

	# Миграция: до T22 журнал лежал в стираемом purchases.processed основного
	# файла. Без переноса обновление «подарило» бы существующим установкам
	# повторную выдачу после удаления данных — ровно тот дефект, что T22 чинит.
	var _legacy_key := "google_play:sku_old:" + "old_token_value".sha256_text()
	var _legacy_file := FileAccess.open(UserData.SAVE_PATH, FileAccess.WRITE)
	if _legacy_file != null:
		_legacy_file.store_string(JSON.stringify({
			"version": UserData.DATA_VERSION,
			"device_id": "install_legacy_t22",
			"purchases": {"processed": {_legacy_key: {"provider": "google_play", "sku": "sku_old", "processed_at": 100.0}},
				"owned": {}, "pending": {}},
		}))
		_legacy_file.close()
	UserData._load()
	UserData._load_purchase_journal()
	Selftest.check("t22 legacy journal migrated into its own file", UserData._processed.has(_legacy_key)
		and FileAccess.file_exists(UserData.PURCHASES_PATH)
		and (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_legacy_key))
	Selftest.check("t22 legacy copy cleared from the wipeable file",
		((_t22_json(UserData.SAVE_PATH).get("purchases", {}) as Dictionary).get("processed", {}) as Dictionary).is_empty())
	# I-1: отметка «уже начислено» живёт в неуязвимом журнале (секция granted),
	# отдельной строкой от processed, а НЕ в затираемом pending: снятие pending и
	# вайп не должны её убивать.
	UserData.set_pending_purchase("starter_bundle", {"provider": "google_play", "sku": "al_loop_starter_2026"})
	Selftest.check("t22 granted mark absent before granting",
		not Monetization._purchase_already_granted("google_play", "al_loop_starter_2026", "tok_9", "starter_bundle"))
	Monetization._mark_purchase_granted("google_play", "al_loop_starter_2026", "tok_9", "starter_bundle")
	Selftest.check("t22 granted mark matches the same receipt",
		Monetization._purchase_already_granted("google_play", "al_loop_starter_2026", "tok_9", "starter_bundle"))
	Selftest.check("t22 granted mark rejects another receipt",
		not Monetization._purchase_already_granted("google_play", "al_loop_starter_2026", "tok_other", "starter_bundle"))
	# Метка НЕ живёт в pending: снятие pending её не трогает (её снимает только
	# успешно записанный processed или явный clear_purchase_granted).
	UserData.clear_pending_purchase("starter_bundle")
	Selftest.check("t22 granted mark survives clearing pending",
		Monetization._purchase_already_granted("google_play", "al_loop_starter_2026", "tok_9", "starter_bundle"))
	# Хранится в секции granted файла журнала, а не в pending стираемого сейва.
	var _gkey := UserData._token_key("google_play", "tok_9", "al_loop_starter_2026")
	Selftest.check("t22 granted mark stored in the journal file, not in pending",
		(_t22_json(UserData.PURCHASES_PATH).get("granted", {}) as Dictionary).has(_gkey)
		and ((_t22_json(UserData.SAVE_PATH).get("purchases", {}) as Dictionary).get("pending", {}) as Dictionary).is_empty())
	# Явное снятие работает и персистится (готовит чистый _granted для wipe-кейсов).
	UserData.clear_purchase_granted("google_play", "tok_9", "al_loop_starter_2026")
	Selftest.check("t22 granted mark cleared explicitly",
		not Monetization._purchase_already_granted("google_play", "al_loop_starter_2026", "tok_9", "starter_bundle")
		and not (_t22_json(UserData.PURCHASES_PATH).get("granted", {}) as Dictionary).has(_gkey))
	# Полная картина: чек закрыт, устройство «как новое», журнал на месте.
	var _dev_before := UserData.get_or_create_device_id()
	UserData.mark_processed_purchase("google_play", "secret_token_1", "sku_new")
	var _sku_new_key := "google_play:sku_new:" + "secret_token_1".sha256_text()
	# Потолок журнала: режем по processed_at (старые чеки первыми), а не «сколько
	# влезло в файл». Свежий закрытый чек обязан пережить обрезку.
	for i in range(0, UserData.PROCESSED_CAP + 5):
		UserData._processed["google_play:bulk_%d:%d" % [i, i]] = {"provider": "google_play", "sku": "bulk", "processed_at": float(i)}
	UserData._trim_processed()
	Selftest.check("t22 journal trims oldest beyond cap", UserData._processed.size() == UserData.PROCESSED_CAP
		and not UserData._processed.has("google_play:bulk_0:0")
		and UserData._processed.has("google_play:bulk_7:7")
		and UserData._processed.has(_sku_new_key))
	UserData._processed = {_sku_new_key: {"provider": "google_play", "sku": "sku_new", "processed_at": 1.0}}
	UserData._save_purchases()
	UserData.delete_all_local_data()
	var _dev_after := String(UserData._data.get("device_id", ""))
	var _journal_text := _t22_read(UserData.PURCHASES_PATH)
	Selftest.check("t22 wipe keeps the purchase journal",
		UserData.has_processed_purchase("google_play", "secret_token_1", "sku_new")
		and FileAccess.file_exists(UserData.PURCHASES_PATH))
	Selftest.check("t22 wipe really removed the wipeable files", _dev_before != "" and _dev_after == ""
		and not FileAccess.file_exists(UserData.SAVE_PATH) and not FileAccess.file_exists(UserData.BACKUP_PATH)
		and not FileAccess.file_exists(UserData.PURCHASES_TEMP_PATH)
		and ((UserData._data.get("purchases", {}) as Dictionary).get("pending", {}) as Dictionary).is_empty())
	Selftest.check("t22 journal file stores no raw receipt token", _journal_text.contains("sku_new")
		and not _journal_text.contains("secret_token_1"))
	var _export_text := JSON.stringify(UserData.export_data())
	Selftest.check("t22 export carries the journal but no raw tokens", _export_text.contains("sku_new")
		and not _export_text.contains("secret_token_1"))

	# ---------- M-2: миграция журнала не затирает legacy при неудачной записи ----
	# Если запись нового файла журнала падёт, legacy-копию в стираемом сейве
	# затирать нельзя: перенесённые записи потерялись бы и там, и тут. Пишем
	# свежий legacy-файл, ломаем запись журнала (временный путь в несуществующей
	# папке → FileAccess.open возвращает null) и наблюдаем, что стираемый файл
	# СОХРАНИЛ legacy-ключ.
	var _m2_tmp0 := UserData.PURCHASES_TEMP_PATH
	var _m2_key := "google_play:sku_m2:" + "m2_token_value".sha256_text()
	var _m2_save := FileAccess.open(UserData.SAVE_PATH, FileAccess.WRITE)
	if _m2_save != null:
		_m2_save.store_string(JSON.stringify({
			"version": UserData.DATA_VERSION,
			"device_id": "install_m2_t22",
			"purchases": {"processed": {_m2_key: {"provider": "google_play", "sku": "sku_m2", "processed_at": 50.0}},
				"owned": {}, "pending": {}},
		}))
		_m2_save.close()
	UserData._processed = {}
	UserData._granted = {}
	UserData._load()
	UserData.PURCHASES_TEMP_PATH = "user://alchemy_st_no_such_dir/m2.tmp"
	UserData._load_purchase_journal()
	UserData.PURCHASES_TEMP_PATH = _m2_tmp0
	Selftest.check("m2 migration keeps legacy when journal write fails",
		((_t22_json(UserData.SAVE_PATH).get("purchases", {}) as Dictionary).get("processed", {}) as Dictionary).has(_m2_key)
		and not (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_m2_key))

	# ---------- T22: порядок finish grant -> consume -> mark, ретрай и acknowledge ----------
	# Фейковый адаптер — копия реального контракта: T22FakeBilling как rustore_pay.gd
	# (только consume), T22FakeBillingAck как google_play_billing.gd (consume + acknowledge).
	# Вызываем _finish_purchase напрямую: в headless нет стора, а Net не трогаем (вердикт
	# валидатора покрыт выше чистой функцией). Адаптер в момент собственного вызова пишет
	# снимок наблюдаемого состояния — это и есть доказательство порядка, а не «лог со слов».
	var _store0 := Monetization.store_id
	var _ad0: RefCounted = Monetization._adapter
	var _eth0 := g._engine.ether
	var _ovf0 := g._engine.ether_overflow
	var _stat0 := g._engine.status_text
	# store_id = "google_play", чтобы SKU резолвился по store_sku, как на реальном
	# устройстве, и _on_purchase_received НЕ выходил раньше журнала-гарда по unknown_sku.
	Monetization.store_id = "google_play"
	var _probe := T22SignalProbe.new()
	Monetization.purchase_succeeded.connect(_probe._on_purchase_succeeded)
	Monetization.purchase_failed.connect(_probe._on_purchase_failed)
	var _cprov := "google_play"
	var _csku := "al_loop_ether_500"  # ether_pack_small из data/monetization.json: consumable, +500
	var _ctok := "t22_retry_token"
	var _cpid := "ether_pack_small"
	var _creq := {"provider": _cprov, "sku": _csku, "token": _ctok, "product_id": _cpid}
	var _ckey := UserData._token_key(_cprov, _ctok, _csku)
	var _jp0 := UserData._processed.size()
	# Награда consumable наблюдается суммой ether + ether_overflow: _grant_ether
	# доливает только до капа, остаток уходит в overflow — «+500» иначе зависел бы
	# от того, сколько эфира уже набрано сюитами.
	UserData.set_pending_purchase(_cpid, {"provider": _cprov, "sku": _csku, "started_at": 1.0})
	var _no := T22FakeBilling.new()
	_no.ok = false
	_no.provider = _cprov
	_no.sku = _csku
	_no.token = _ctok
	_no.product_id = _cpid
	_no.game = g
	Monetization._adapter = _no
	Monetization._finish_purchase(_creq, false)
	# Шаг 4 брифа: магазин не подтвердил — начисление уже сделано, значит игрок видит
	# результат (purchase_succeeded эмитится), но журнал «полностью завершено» не
	# тронут; pending остаётся (работа для restore), а отметка «уже начислено» —
	# в секции granted того же журнала (I-1).
	Selftest.check("t22 denied store still announces the granted purchase",
		_probe.events.size() == 1 and String(_probe.events[0]) == "ok:ether_pack_small"
		and g._engine.ether + g._engine.ether_overflow == _eth0 + 500)
	Selftest.check("t22 unconfirmed consume leaves journal untouched",
		not UserData.has_processed_purchase(_cprov, _ctok, _csku)
		and UserData._processed.size() == _jp0
		and not (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_ckey))
	# I-1: granted-отметка — в секции granted журнала (файл на диске), а не в
	# pending; pending остаётся (его снимает только подтверждённый consume).
	Selftest.check("t22 unconfirmed consume keeps pending and stores granted in the journal",
		Monetization._purchase_already_granted(_cprov, _csku, _ctok, _cpid)
		and not UserData.get_pending_purchase(_cpid).is_empty()
		and (_t22_json(UserData.PURCHASES_PATH).get("granted", {}) as Dictionary).has(_ckey)
		and not UserData.get_pending_purchase(_cpid).has("granted"))
	# Порядок наблюдаем в момент самого вызова consume: начисление уже применено
	# (сумма +500), журнал ещё закрыт — grant раньше consume, consume раньше mark.
	Selftest.check("t22 consume observed grant-before and mark-after",
		_no.calls.size() == 1 and String(_no.calls[0]) == "consume:" + _ctok + ":" + _csku
		and _no.states.size() == 1
		and int(_no.states[0]["reward"]) == _eth0 + 500
		and bool(_no.states[0]["journal_open"]) == false)
	# Ретрай того же чека: магазин теперь подтверждает. Отметка «уже начислено» обязана
	# заблокировать второе начисление, журнал — записаться ровно один раз и только
	# после подтверждения, pending — сняться.
	var _yes := T22FakeBilling.new()
	_yes.ok = true
	_yes.provider = _cprov
	_yes.sku = _csku
	_yes.token = _ctok
	_yes.product_id = _cpid
	_yes.game = g
	Monetization._adapter = _yes
	Monetization._finish_purchase(_creq, false)
	Selftest.check("t22 retry does not grant a second time",
		g._engine.ether + g._engine.ether_overflow == _eth0 + 500
		and _yes.states.size() == 1 and bool(_yes.states[0]["pending_granted"]) == true)
	Selftest.check("t22 retry writes journal exactly once after confirm",
		UserData.has_processed_purchase(_cprov, _ctok, _csku)
		and UserData._processed.size() == _jp0 + 1
		and (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_ckey)
		and bool(_yes.states[0]["journal_open"]) == false)
	Selftest.check("t22 retry clears pending only after confirm",
		UserData.get_pending_purchase(_cpid).is_empty()
		and _probe.events.size() == 2 and String(_probe.events[1]) == "ok:ether_pack_small")
	# Полностью закрытый чек: повторная доставка (restore на onResume) отсекается
	# журнальным гардом _on_purchase_received. Что это именно гард, а не более ранний
	# return, показывают контроли до вызова: SKU резолвится, очередь не полна, чека
	# в очереди нет. После вызова — ноль новых событий: ни queue, ни grant, ни сигналов.
	var _vq0 := Monetization._verify_requests.size()
	Selftest.check("t22 journal guard is the only reason left to refuse",
		Monetization._product_id_for_sku(_csku) == _cpid
		and Monetization._product_id_for_sku("t22_bogus_sku") == ""
		and _vq0 < Monetization.MAX_QUEUED_RECEIPT_CHECKS
		and Monetization._verify_request_index(_cprov, _csku, _ctok) == -1)
	Monetization._on_purchase_received({"provider": _cprov, "sku": _csku, "token": _ctok, "state": "purchased"})
	Selftest.check("t22 closed receipt refused without any new work",
		Monetization._verify_requests.size() == _vq0
		and _probe.events.size() == 2
		and g._engine.ether + g._engine.ether_overflow == _eth0 + 500
		and UserData.get_pending_purchase(_cpid).is_empty())
	# non-consumable: Google Play требует acknowledge (без него рефаунд через 3 дня),
	# у RuStore-адаптера такого метода нет — обязателен фолбэк в consume.
	var _nprov := "google_play"
	var _nsku := "al_loop_remove_ads"  # remove_ads из каталога: non_consumable
	var _ntok := "t22_ack_token"
	var _ntok2 := "t22_fallback_token"
	var _npid := "remove_ads"
	var _nreq := {"provider": _nprov, "sku": _nsku, "token": _ntok, "product_id": _npid}
	var _nreq2 := {"provider": _nprov, "sku": _nsku, "token": _ntok2, "product_id": _npid}
	var _owned0 := UserData.is_product_owned(_npid)
	UserData.set_pending_purchase(_npid, {"provider": _nprov, "sku": _nsku, "started_at": 1.0})
	var _ackad := T22FakeBillingAck.new()
	_ackad.ok = true
	_ackad.provider = _nprov
	_ackad.sku = _nsku
	_ackad.token = _ntok
	_ackad.product_id = _npid
	_ackad.game = g
	Monetization._adapter = _ackad
	Monetization._finish_purchase(_nreq, false)
	# В момент acknowledge: право уже выдано (owned flip из _owned0 == false), журнал
	# ещё закрыт. Отнеси код non-consumable в consume — calls[0] был бы "consume:…".
	Selftest.check("t22 non-consumable acknowledges when adapter can",
		_owned0 == false
		and _ackad.calls.size() == 1 and String(_ackad.calls[0]) == "acknowledge:" + _ntok
		and _ackad.states.size() == 1
		and bool(_ackad.states[0]["owned"]) == true
		and bool(_ackad.states[0]["journal_open"]) == false)
	# Другой токен — другая покупка: гарды её не отсекают, но закрывается она через
	# consume, потому что у этого адаптера нет acknowledge (has_method == false).
	UserData.set_pending_purchase(_npid, {"provider": _nprov, "sku": _nsku, "started_at": 1.0})
	var _plain := T22FakeBilling.new()
	_plain.ok = true
	_plain.provider = _nprov
	_plain.sku = _nsku
	_plain.token = _ntok2
	_plain.product_id = _npid
	_plain.game = g
	Monetization._adapter = _plain
	Monetization._finish_purchase(_nreq2, false)
	Selftest.check("t22 non-consumable falls back to consume without acknowledge",
		_plain.calls.size() == 1 and String(_plain.calls[0]) == "consume:" + _ntok2 + ":" + _nsku
		and _plain.states.size() == 1 and bool(_plain.states[0]["journal_open"]) == false
		and UserData.has_processed_purchase(_nprov, _ntok2, _nsku)
		and UserData.get_pending_purchase(_npid).is_empty())
	Monetization.purchase_succeeded.disconnect(_probe._on_purchase_succeeded)
	Monetization.purchase_failed.disconnect(_probe._on_purchase_failed)
	Monetization._adapter = _ad0
	Monetization.store_id = _store0
	g._engine.ether = _eth0
	g._engine.ether_overflow = _ovf0
	g._engine.status_text = _stat0
	# Все четыре finish эмитили успех (и только успех): две consumable-закрутки плюс
	# две non-consumable; отказанного purchase_failed за блок не было ни разу.
	Selftest.check("t22 adapter, store and engine state restored",
		Monetization._adapter == _ad0 and Monetization.store_id == _store0
		and g._engine.ether == _eth0 and g._engine.ether_overflow == _ovf0
		and _probe.events.size() == 4)

	# ---------- I-1: granted-отметка переживает wipe → нет двойной выдачи ----------
	# Цепочка дефекта: consume вернул false (начислили, processed не записан,
	# granted=true) → игрок жмёт «Удалить локальные данные» (pending и _data стёрты,
	# RAM-эфир жив, журнал с granted цел) → restore приносит тот же непотреблённый
	# чек → магазин теперь подтверждает → _finish_purchase НЕ должен лить награду
	# второй раз, потому что is_purchase_granted читает уцелевший журнал. Награда
	# наблюдается суммой ether + ether_overflow (как у соседей).
	var _i1_eth0 := g._engine.ether + g._engine.ether_overflow
	var _i1_prov := "google_play"
	var _i1_sku := "al_loop_ether_500"
	var _i1_tok := "t22_wipe_survives_token"
	var _i1_pid := "ether_pack_small"
	var _i1_req := {"provider": _i1_prov, "sku": _i1_sku, "token": _i1_tok, "product_id": _i1_pid}
	var _i1_key := UserData._token_key(_i1_prov, _i1_tok, _i1_sku)
	var _i1_probe := T22SignalProbe.new()
	Monetization.purchase_succeeded.connect(_i1_probe._on_purchase_succeeded)
	UserData.set_pending_purchase(_i1_pid, {"provider": _i1_prov, "sku": _i1_sku, "started_at": 1.0})
	var _i1_deny := T22FakeBilling.new()
	_i1_deny.ok = false
	_i1_deny.provider = _i1_prov
	_i1_deny.sku = _i1_sku
	_i1_deny.token = _i1_tok
	_i1_deny.product_id = _i1_pid
	_i1_deny.game = g
	Monetization._adapter = _i1_deny
	Monetization._finish_purchase(_i1_req, false)
	# Отметка легла в granted журнала (файл на диске), processed не тронут, pending жив.
	Selftest.check("i1 first unconfirmed delivery grants once and marks granted in the journal",
		g._engine.ether + g._engine.ether_overflow == _i1_eth0 + 500
		and (_t22_json(UserData.PURCHASES_PATH).get("granted", {}) as Dictionary).has(_i1_key)
		and not (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_i1_key)
		and not UserData.get_pending_purchase(_i1_pid).is_empty())
	UserData.delete_all_local_data()
	# Вайп стёр pending, но НЕ granted-отметку в журнале.
	Selftest.check("i1 wipe removes pending but keeps the granted mark",
		UserData.get_pending_purchase(_i1_pid).is_empty()
		and not UserData.has_processed_purchase(_i1_prov, _i1_tok, _i1_sku)
		and Monetization._purchase_already_granted(_i1_prov, _i1_sku, _i1_tok, _i1_pid))
	var _i1_ok := T22FakeBilling.new()
	_i1_ok.ok = true
	_i1_ok.provider = _i1_prov
	_i1_ok.sku = _i1_sku
	_i1_ok.token = _i1_tok
	_i1_ok.product_id = _i1_pid
	_i1_ok.game = g
	Monetization._adapter = _i1_ok
	Monetization._finish_purchase(_i1_req, false)
	# Ретрай после вайпа: награда НЕ начислена второй раз, журнал закрыт ровно раз,
	# granted-отметка снята промоушеном (processed записан → granted удалён).
	Selftest.check("i1 repeat after wipe does not grant a second time",
		g._engine.ether + g._engine.ether_overflow == _i1_eth0 + 500
		and UserData.has_processed_purchase(_i1_prov, _i1_tok, _i1_sku)
		and (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_i1_key)
		and not (_t22_json(UserData.PURCHASES_PATH).get("granted", {}) as Dictionary).has(_i1_key)
		and not Monetization._purchase_already_granted(_i1_prov, _i1_sku, _i1_tok, _i1_pid)
		and _i1_probe.events.size() == 2)
	Monetization.purchase_succeeded.disconnect(_i1_probe._on_purchase_succeeded)

	# ---------- M-1: неудачная запись журнала не закрывает покупку ----------
	# Начислили (granted в журнале), магазин подтвердил, НО запись processed упала
	# (временный путь журнала в несуществующей папке → FileAccess.open == null).
	# Покупка не считается закрытой: pending остаётся (restore повторит consume),
	# granted не снимается, строки processed на диске нет.
	var _m1_tmp0 := UserData.PURCHASES_TEMP_PATH
	var _m1_eth0 := g._engine.ether + g._engine.ether_overflow
	var _m1_prov := "google_play"
	var _m1_sku := "al_loop_ether_500"
	var _m1_tok := "t22_journal_write_fail_token"
	var _m1_pid := "ether_pack_small"
	var _m1_req := {"provider": _m1_prov, "sku": _m1_sku, "token": _m1_tok, "product_id": _m1_pid}
	var _m1_key := UserData._token_key(_m1_prov, _m1_tok, _m1_sku)
	var _m1_probe := T22SignalProbe.new()
	Monetization.purchase_succeeded.connect(_m1_probe._on_purchase_succeeded)
	UserData.set_pending_purchase(_m1_pid, {"provider": _m1_prov, "sku": _m1_sku, "started_at": 1.0})
	var _m1_deny := T22FakeBilling.new()
	_m1_deny.ok = false
	_m1_deny.provider = _m1_prov
	_m1_deny.sku = _m1_sku
	_m1_deny.token = _m1_tok
	_m1_deny.product_id = _m1_pid
	_m1_deny.game = g
	Monetization._adapter = _m1_deny
	Monetization._finish_purchase(_m1_req, false)
	# Теперь магазин подтверждает, но запись журнала падает.
	UserData.PURCHASES_TEMP_PATH = "user://alchemy_st_no_such_dir/m1.tmp"
	var _m1_ok := T22FakeBilling.new()
	_m1_ok.ok = true
	_m1_ok.provider = _m1_prov
	_m1_ok.sku = _m1_sku
	_m1_ok.token = _m1_tok
	_m1_ok.product_id = _m1_pid
	_m1_ok.game = g
	Monetization._adapter = _m1_ok
	Monetization._finish_purchase(_m1_req, false)
	# Наблюдаемый побочный эффект M-1: pending НЕ снят, processed нет на диске
	# (это же доказательство, что запись действительно упала — иначе ключ бы был),
	# granted остался (промоушен только при успешной записи), награда один раз.
	Selftest.check("m1 failed journal write keeps the purchase open",
		not UserData.get_pending_purchase(_m1_pid).is_empty()
		and not (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_m1_key)
		and Monetization._purchase_already_granted(_m1_prov, _m1_sku, _m1_tok, _m1_pid)
		and g._engine.ether + g._engine.ether_overflow == _m1_eth0 + 500
		and _m1_probe.events.size() == 2)
	UserData.PURCHASES_TEMP_PATH = _m1_tmp0
	Monetization.purchase_succeeded.disconnect(_m1_probe._on_purchase_succeeded)
	Monetization._adapter = _ad0
	g._engine.ether = _eth0
	g._engine.ether_overflow = _ovf0

	UserData.SAVE_PATH = _us0
	UserData.TEMP_PATH = _ut0
	UserData.BACKUP_PATH = _ub0
	UserData.PURCHASES_PATH = _up0
	UserData.PURCHASES_TEMP_PATH = _upt0
	UserData._data = _data0
	UserData._processed = _processed0
	UserData._granted = _granted0
	_t22_remove_paths(_st_paths)
	Selftest.check("t22 UserData paths and data restored", UserData.SAVE_PATH == _us0
		and UserData.PURCHASES_PATH == _up0 and UserData._data == _data0 and UserData._processed == _processed0
		and UserData._granted == _granted0)


static func _t22_json(path: String) -> Dictionary:
	# Чтение с диска, а не из памяти: проверка «старая копия журнала удалена из
	# стираемого файла» должна значить именно «стираемого файла так не содержит».
	var parsed: Variant = JSON.parse_string(_t22_read(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _t22_read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _t22_remove_paths(paths: Array) -> void:
	for path in paths:
		if FileAccess.file_exists(String(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(path)))


class T22FakeBilling extends RefCounted:
	# Копия контракта rustore_pay.gd: consume есть, acknowledge нет — ровно то
	# отличие, на которое опирается has_method-ветка в _confirm_purchase_with_store.
	# Каждый вызов пишет в calls строку вызова, а в states — снимок наблюдаемого
	# состояния ИМЕННО в момент вызова: порядок доказывается по нему, а не по
	# очереди строк в calls.
	var ok := false
	var calls: Array = []
	var states: Array = []
	var provider := ""
	var sku := ""
	var token := ""
	var product_id := ""
	var game: Game = null
	func consume(call_token: String, call_sku: String) -> bool:
		calls.append("consume:" + call_token + ":" + call_sku)
		states.append(_snapshot())
		return ok
	func _snapshot() -> Dictionary:
		return {
			"journal_open": UserData.has_processed_purchase(provider, token, sku),
			"pending_granted": Monetization._purchase_already_granted(provider, sku, token, product_id),
			"reward": game._engine.ether + game._engine.ether_overflow,
			"owned": UserData.is_product_owned(product_id),
		}


class T22FakeBillingAck extends T22FakeBilling:
	# Копия контракта google_play_billing.gd: consume + acknowledge.
	func acknowledge(call_token: String) -> bool:
		calls.append("acknowledge:" + call_token)
		states.append(_snapshot())
		return ok


class T22SignalProbe extends RefCounted:
	# Коллектор сигналов: отсутствие эмиссии наблюдается так же хорошо, как и
	# наличие; что коннекты живые — доказывают ok-события ранних сценариев, значит
	# последующие проверки «ни одного failed» не vacuous.
	var events: Array = []
	func _on_purchase_succeeded(product_id: String, _provider: String) -> void:
		events.append("ok:" + product_id)
	func _on_purchase_failed(product_id: String, code: String, _message: String) -> void:
		events.append("failed:" + code + ":" + product_id)


static func _esc_key() -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_ESCAPE
	return k


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
	# home-ноды построены в _ready, но цепочка main.gd guard'ит их на != null —
	# повторяем guard'ы, иначе битая сборка уронила бы весь selftest вместо одной
	# красной проверки
	if g._home._decor_popup != null and g._home._decor_popup.visible:
		return false
	if g._home._color_picker != null and g._home._color_picker.visible:
		return false
	if g._home._house_popup != null and g._home._house_popup.visible:
		return false
	return true
