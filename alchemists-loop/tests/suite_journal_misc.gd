extends RefCounted
class_name SuiteJournalMisc
# сброс/повтор/журнал/звук/что-вапить/добыть-всё (оп B1).

const NetBase := preload("res://autoload/net.gd")

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

	# T2: магазин декора (z=100) закрывается раньше нижнего попапа настроек хаба —
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
	# СОХРАНИЛ legacy-ключ. R-5: там же утверждаем, что перенос в RAM состоялся,
	# иначе кейс остался бы зелёным и на «миграция вообще не выполнилась».
	var _m2_tmp0 := UserData.PURCHASES_TEMP_PATH
	var _m2_key := UserData._token_key("google_play", "m2_token_value", "sku_m2")
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
		and not (_t22_json(UserData.PURCHASES_PATH).get("processed", {}) as Dictionary).has(_m2_key)
		and UserData._processed.has(_m2_key))

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

	# ---------- T23: согласие / «закрыто ≠ заработано» / стаб только в debug ----------
	# Блок живёт именно здесь: только этот monetization-блок переводит пути UserData
	# на ST-файлы (consent и pending пишутся на диск) и только тут уже есть
	# коллектор платёжных сигналов. Всё, что блок подкручивает, снимается в конце —
	# и перекрывается общим восстановлением путей/`_data` ниже.
	var _t23_env0 := OS.get_environment("ALCHEMY_ADS_STUB")
	var _t23_consent0 := UserData.get_consent("ads_personalized")
	var _t23_store0 := Monetization.store_id
	var _t23_ads_real: RefCounted = Monetization._ads
	var _t23_avail0 := Monetization.ads_available
	var _t23_game0: Node = Monetization._game
	var _t23_pending_placement0 := Monetization._pending_placement
	var _t23_pending_product0 := Monetization._pending_product
	var _t23_queue0: Array = Monetization._verify_requests.duplicate(true)
	var _t23_owned0 := UserData.is_product_owned("remove_ads")
	var _t23_ads_state0: Dictionary = UserData.get_ads_state()
	var _t23_app0: Dictionary = (UserData._data.get("app", {}) as Dictionary).duplicate(true)
	var _t23_eth_base := g._engine.ether + g._engine.ether_overflow
	var _t23_status0 := g._engine.status_text
	var _t23_auto0 := g._engine._auto

	# --- T23.1/T23.3: чистые предикаты (наблюдаемы без GUI и без плагина) ---
	Selftest.check("t23 consent predicate allows only granted",
		AdsAdapter.consent_allows_ads("granted")
		and not AdsAdapter.consent_allows_ads("denied")
		and not AdsAdapter.consent_allows_ads("unknown")
		and not AdsAdapter.consent_allows_ads(""))
	# Буквальный кейс «стуб недоступен в release»: те же аргументы, is_debug == false.
	Selftest.check("t23 ads stub is requested only in a debug build",
		not AdsAdapter.stub_requested(["--ads-stub"], "1", false)
		and not AdsAdapter.stub_requested(["--ads-stub"], "", false)
		and not AdsAdapter.stub_requested([], "", false)
		and AdsAdapter.stub_requested(["--ads-stub"], "", true)
		and AdsAdapter.stub_requested([], "1", true))

	# --- T23.1: initialize() и доступность адаптера по согласию ---
	var _t23_ad := AdsAdapter.new()
	var _t23_probe := T23AdsProbe.new()
	_t23_ad.initialized.connect(_t23_probe._on_initialized)
	_t23_ad.rewarded_completed.connect(_t23_probe._on_rewarded)
	_t23_ad.ad_failed.connect(_t23_probe._on_failed)
	Monetization.rewarded_available.connect(_t23_probe._on_rewarded_available)
	Monetization.rewarded_started.connect(_t23_probe._on_rewarded_started)
	Monetization.rewarded_finished.connect(_t23_probe._on_rewarded_finished)
	# Стаб поднимается тем же путём, что и на реальной отладочной сборке: без него
	# «granted → доступен» в headless проверить нечем (плагина нет).
	OS.set_environment("ALCHEMY_ADS_STUB", "1")
	Selftest.check("t23 debug fixture really raises the ads stub",
		AdsAdapter.stub_requested(OS.get_cmdline_user_args(), OS.get_environment("ALCHEMY_ADS_STUB"), OS.is_debug_build()))
	_t23_ad.initialize("standalone", "denied")
	# Счёт по метке, а не по индексу: любое лишнее событие (в том числе из фасада)
	# красит кейс, а не сдвигает окна молча.
	Selftest.check("t23 denied consent initializes the adapter as unavailable",
		_t23_probe.count_since(0, "init:false") == 1
		and _t23_probe.count_since(0, "init:true") == 0
		and not _t23_ad.is_available())
	Selftest.check("t23 adapter refuses both formats without consent",
		not _t23_ad.show_rewarded("extra_brew") and not _t23_ad.show_interstitial()
		and _t23_probe.count_since(0, "failed:consent_required") == 2
		and _t23_probe.count_since(0, "rewarded:") == 0)
	_t23_probe.events.clear()
	_t23_ad.initialize("standalone", "granted")
	Selftest.check("t23 granted consent brings the adapter up",
		_t23_probe.count_since(0, "init:true") == 1
		and _t23_probe.count_since(0, "init:false") == 0
		and _t23_ad.is_available())

	# Смена согласия в Лавке обязана применяться без перезапуска: тот же экземпляр
	# адаптера, что висит на фасаде, и реальный путь через Monetization.
	Monetization._ads = _t23_ad
	_t23_ad.rewarded_completed.connect(Monetization._on_rewarded_completed)
	_t23_ad.ad_failed.connect(Monetization._on_ad_failed)
	UserData.set_consent("ads_personalized", "granted")
	Monetization.configure_consent()
	Selftest.check("t23 configure_consent keeps ads available on granted",
		_t23_ad.is_available() and Monetization.ads_available)
	UserData.set_consent("ads_personalized", "denied")
	Monetization.configure_consent()
	# Ловушка T23: _stub выставлялся ДО гейта согласия, а is_available() возвращает
	# true по одному лишь _stub. Здесь consent == denied и стаб был поднят ранее —
	# без правки адаптера кейс остался бы зелёным только «по памяти о стабе».
	Selftest.check("t23 configure_consent tears the stub down on denied",
		not _t23_ad.is_available() and not Monetization.ads_available)

	# --- T23.1: гейт согласия в фасаде (не только в адаптере) ---
	# Фиксатура: адаптер СИЛАМИ возвращён в доступное состояние при denied consent
	# (так выглядит отзыв согласия, когда адаптер уже поднят). Тогда единственная
	# причина отказа — собственный гейт Monetization; без него сюда долетел бы
	# failed:consent_required от адаптера и started-событие, и кейс покраснел бы.
	_t23_ad._stub = true
	_t23_clear_ad_limits()
	var _t23_ev0 := _t23_probe.events.size()
	var _t23_shown_denied := Monetization.show_rewarded("extra_brew")
	Selftest.check("t23 facade refuses rewarded before touching the adapter",
		not _t23_shown_denied
		and _t23_probe.count_since(_t23_ev0, "available:extra_brew:false") == 1
		and _t23_probe.count_since(_t23_ev0, "started:") == 0
		and _t23_probe.count_since(_t23_ev0, "failed:") == 0
		and not Monetization.can_show_interstitial())
	# Фиксатуру снимаем: дальше адаптер живёт только своими собственными решениями.
	_t23_ad._stub = false

	# --- T23.2: «закрыто» ≠ «заработано» сквозь реальную проводку сигналов ---
	# Фейковый клиент — копия наблюдаемого контракта рекламного плагина (те же имена
	# сигналов, что перечисляет _connect_signals), поэтому проверяется и ПЕРЕПОДКЛЮЧЕНИЕ
	# rewarded_closed, а не только тело обработчика. Порядок важен: согласие
	# выставляется ДО подключения клиента — initialize() пересобирает _client через
	# _find_client() и обнулил бы фиксатуру.
	UserData.set_consent("ads_personalized", "granted")
	Monetization.configure_consent()
	var _t23_client := T23FakeAdsClient.new()
	_t23_ad._client = _t23_client
	_t23_ad._connect_signals()
	_t23_clear_ad_limits()
	var _t23_ev1 := _t23_probe.events.size()
	# Показ «в полёте» с обеих сторон контракта: адаптер держит placement ради
	# эмита награды, фасад — свой _pending_placement, которым он размечает отказ.
	_t23_ad._placement_pending = "extra_brew"
	_t23_ad._reward_earned = false
	Monetization._pending_placement = "extra_brew"
	_t23_client.rewarded.emit(null)
	_t23_client.rewarded_closed.emit(null)
	Selftest.check("t23 rewarded then closed pays exactly once",
		_t23_probe.count_since(_t23_ev1, "rewarded:extra_brew") == 1
		and _t23_probe.count_since(_t23_ev1, "finished:extra_brew") == 1
		and _t23_probe.count_since(_t23_ev1, "failed:") == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth_base + 12
		and UserData.rewarded_count_for_today() == 1)
	# Пропуск видео: плагин шлёт только закрытие.
	_t23_clear_ad_limits()
	var _t23_ev2 := _t23_probe.events.size()
	var _t23_eth2 := g._engine.ether + g._engine.ether_overflow
	_t23_ad._placement_pending = "source_boost_60"
	Monetization._pending_placement = "source_boost_60"
	_t23_client.rewarded_closed.emit(null)
	Selftest.check("t23 closed without a reward emits one not_earned and pays nothing",
		_t23_probe.count_since(_t23_ev2, "failed:not_earned") == 1
		and _t23_probe.count_since(_t23_ev2, "available:source_boost_60:false") == 1
		and _t23_probe.count_since(_t23_ev2, "rewarded:") == 0
		and _t23_probe.count_since(_t23_ev2, "finished:") == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth2
		and UserData.rewarded_count_for_today() == 0)
	# Явный отказ в payload — тоже не награда; payload без earned читается по имени
	# сигнала (размер награды берётся из каталога, а не из SDK).
	var _t23_ev3 := _t23_probe.events.size()
	_t23_ad._placement_pending = "extra_brew"
	Monetization._pending_placement = "extra_brew"
	_t23_client.rewarded.emit({"earned": false, "amount": 12})
	Selftest.check("t23 reward payload with earned false does not pay",
		_t23_probe.count_since(_t23_ev3, "failed:not_earned") == 1
		and _t23_probe.count_since(_t23_ev3, "rewarded:") == 0
		and _t23_probe.count_since(_t23_ev3, "finished:") == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth2
		and UserData.rewarded_count_for_today() == 0)
	var _t23_ev4 := _t23_probe.events.size()
	# not_earned снял _placement_pending, поэтому второй награде нужен новый показ:
	# адаптер платит только непустому pending (гейт issue #10).
	_t23_ad._placement_pending = "extra_brew"
	_t23_client.rewarded.emit({"amount": 12, "type": "item"})
	Selftest.check("t23 reward payload without earned pays by signal name",
		_t23_probe.count_since(_t23_ev4, "rewarded:extra_brew") == 1
		and _t23_probe.count_since(_t23_ev4, "finished:extra_brew") == 1
		and _t23_probe.count_since(_t23_ev4, "failed:") == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth2 + 12)
	_t23_ad._client = null

	# Отзыв согласия при НЕзакрытом показе. Подключение живёт на стороне клиента,
	# поэтому поздний rewarded от плагина доходит до обработчика адаптера и после
	# отказа. Право на выдачу даёт непустой _placement_pending — ветка отказа
	# обязана снять его вместе с клиентом, иначе награда пришла бы задним числом.
	_t23_clear_ad_limits()
	_t23_ad._placement_pending = "extra_brew"
	_t23_ad._reward_earned = false
	Monetization._pending_placement = "extra_brew"
	UserData.set_consent("ads_personalized", "denied")
	Monetization.configure_consent()
	# F4 (раунд правки): отзыв согласия обязан снять и фасадный _pending_placement,
	# а не только адаптерный _placement_pending — иначе следующий ad_failed выстрелит
	# rewarded_available("extra_brew", false) за уже отменённый показ. Проверяется
	# ДО поздних эмитов ниже: именно состояние сразу после configure_consent.
	Selftest.check("t23 withdrawn consent clears the facade pending placement",
		Monetization._pending_placement == "")
	var _t23_ev5 := _t23_probe.events.size()
	var _t23_eth5 := g._engine.ether + g._engine.ether_overflow
	_t23_client.rewarded.emit(null)
	_t23_client.rewarded_closed.emit(null)
	Selftest.check("t23 withdrawn consent drops the in-flight show",
		not _t23_ad.is_available()
		and _t23_probe.count_since(_t23_ev5, "rewarded:") == 0
		and _t23_probe.count_since(_t23_ev5, "rewarded:extra_brew") == 0
		and _t23_probe.count_since(_t23_ev5, "finished:extra_brew") == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth5
		and UserData.rewarded_count_for_today() == 0)
	# Возврат к «granted» поднимает адаптер заново (тот же экземпляр, без
	# перезапуска) — дальше идёт сюжет стаба через фасад.
	UserData.set_consent("ads_personalized", "granted")
	Monetization.configure_consent()

	# Показ через фасад: награда приходит НЕ из show_rewarded, а из сигнала.
	_t23_clear_ad_limits()
	var _t23_ev6 := _t23_probe.events.size()
	var _t23_shown_ok := Monetization.show_rewarded("extra_brew")
	Selftest.check("t23 stub rewarded does not pay before the reward signal",
		_t23_shown_ok and _t23_probe.count_since(_t23_ev6, "started:extra_brew") == 1
		and _t23_probe.count_since(_t23_ev6, "rewarded:") == 0
		and _t23_probe.count_since(_t23_ev6, "finished:") == 0
		and UserData.rewarded_count_for_today() == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth2 + 12)
	Monetization._pending_placement = ""

	# --- F3 (раунд правки): два полных цикла награды без ручного форса флага ---
	# Прежний кейс «repeated show» выставлял _reward_earned руками, поэтому строка
	# сброса в AdsAdapter.show_rewarded (:121) оставалась непроверяемой. Здесь флаг
	# пишет только код адаптера: show -> rewarded БЕЗ rewarded_closed (остаточный
	# true) -> сброс лимитов/кулдауна -> show -> rewarded. Без сброса в show
	# второй награды бы не было: её проглотил дубликат-гейт _on_rewarded_signal
	# (:190-192). Проводка — фейковый клиент (стаб намеренно опущен, чтобы
	# call_deferred-награда не прилетела в обход сюжета).
	# Дневной счётчик здесь не доказательство: сброс лимитов между циклами обнуляет
	# rewarded_count, поэтому после второго показа он всегда 1. Пару выплат меряют
	# счётчик событий награды и дельта эфира (12 x 2).
	_t23_ad._stub = false
	_t23_ad._client = _t23_client
	_t23_ad._connect_signals()
	_t23_clear_ad_limits()
	var _t23_ev7 := _t23_probe.events.size()
	var _t23_eth7 := g._engine.ether + g._engine.ether_overflow
	var _t23_cycle1 := Monetization.show_rewarded("extra_brew")
	_t23_client.rewarded.emit(null)
	_t23_clear_ad_limits()
	var _t23_cycle2 := Monetization.show_rewarded("extra_brew")
	_t23_client.rewarded.emit(null)
	Selftest.check("t23 two consecutive rewarded cycles pay exactly twice",
		_t23_cycle1 and _t23_cycle2
		and _t23_probe.count_since(_t23_ev7, "started:extra_brew") == 2
		and _t23_probe.count_since(_t23_ev7, "rewarded:extra_brew") == 2
		and _t23_probe.count_since(_t23_ev7, "finished:extra_brew") == 2
		and _t23_probe.count_since(_t23_ev7, "failed:") == 0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth7 + 24)

	# --- T23.1/T23.4: interstitial — consent-гейт, ход по границе навигации ---
	# Guardrails частоты не ослабляются, поэтому фиксатура доводит состояние
	# установки до «проходящего»: install_at/session_count пишутся прямо в _data,
	# remove_ads снимается явным set_owned_product(…, false). Единственный guardrail,
	# который фиксатура НЕ затрагивает, — session_started_at: он выставлен так, что
	# ветка `session_count <= 1 and session_seconds < 600` заведомо не участвует в
	# решении (сессий 9). Таким образом после «granted → можно» отказ при denied
	# объясняется ровно одним конъюнктом — consent-гейтом.
	Monetization.store_id = "google_play"
	UserData.set_owned_product("remove_ads", false)
	var _t23_app: Dictionary = (UserData._data.get("app", {}) as Dictionary).duplicate(true)
	_t23_app["install_at"] = Time.get_unix_time_from_system() - 3.0 * 86400.0
	_t23_app["session_count"] = 9
	_t23_app["session_started_at"] = Time.get_unix_time_from_system() - 700.0
	UserData._data["app"] = _t23_app
	_t23_clear_ad_limits()
	Selftest.check("t23 interstitial guardrails pass with granted consent",
		_t23_ad.is_available() and Monetization.can_show_interstitial())
	UserData.set_consent("ads_personalized", "denied")
	Monetization.configure_consent()
	# Единственная причина отказа здесь — согласие: guardrails выше уже доказаны
	# пройденными, remove_ads не в праве.
	Selftest.check("t23 denied consent blocks the interstitial",
		not Monetization.can_show_interstitial() and not Monetization.show_interstitial("navigation"))
	UserData.set_consent("ads_personalized", "granted")
	Monetization.configure_consent()
	_t23_clear_ad_limits()
	var _t23_ts0 := UserData.last_interstitial_at()
	var _t23_inter := Monetization.show_interstitial("navigation")
	Selftest.check("t23 stubbed interstitial records the show time",
		_t23_inter and UserData.last_interstitial_at() > _t23_ts0)
	Selftest.check("t23 second interstitial waits out the cooldown",
		not Monetization.can_show_interstitial() and not Monetization.show_interstitial("navigation"))
	# Граница навигации: вызов ровно в _on_tab_changed и ровно при закрытых модалах.
	# 0-я вкладка берётся намеренно — world/rating-ветки (2/4/5) трогали бы Net.
	g._engine._auto = false
	_t23_clear_ad_limits()
	Selftest.check("t23 navigation fixture is modal-free with a clear cooldown",
		not g._modal_open_for_ads() and Monetization.can_show_interstitial())
	var _t23_ts1 := UserData.last_interstitial_at()
	g._on_tab_changed(0)
	Selftest.check("t23 tab change shows the interstitial on a clean stack",
		UserData.last_interstitial_at() > _t23_ts1)
	_t23_clear_ad_limits()
	g._hub._settings_popup.visible = true
	var _t23_settings := g._modal_open_for_ads()
	var _t23_ts2 := UserData.last_interstitial_at()
	g._on_tab_changed(0)
	Selftest.check("t23 tab change does not interrupt an open modal",
		_t23_settings and UserData.last_interstitial_at() == _t23_ts2)
	g._hub._settings_popup.visible = false
	g._home._decor_popup.visible = true
	var _t23_decor := g._modal_open_for_ads()
	g._home._decor_popup.visible = false
	g._shop._popup.visible = true
	var _t23_shop := g._modal_open_for_ads()
	g._shop._popup.visible = false
	g._popup.visible = true
	var _t23_main_popup := g._modal_open_for_ads()
	g._popup.visible = false
	g._engine._auto = true
	var _t23_auto := g._modal_open_for_ads()
	g._engine._auto = false
	# Предикат перечисляет поверхности сам: без любой из строк свой модальный слой
	# пропускает рекламу поверх себя, и проверяется это именно этой парой имён.
	Selftest.check("t23 modal predicate covers every closable surface",
		_t23_settings and _t23_decor and _t23_shop and _t23_main_popup and _t23_auto)
	g._engine._auto = _t23_auto0

	# --- F2 (раунд правки): ручная варка и занятый верстак блокируют показ ---
	# _engine._auto покрывает только автоварку; ручная — _engine.brewing
	# (core.gd:14, true в :695, false в :711/:765), занятость верстака —
	# _pages._bench_busy (pages.gd:23; core.gd трактует её занятой вместе с
	# варкой: :407, :666, :1208, :1371). Ни то ни другое модалом не является,
	# а текст обещает «Реклама не показывается во время варки» (shop.gd) —
	# значит предикат обязан отказывать по ним, и tab_changed не должен показывать.
	_t23_clear_ad_limits()
	var _t23_can_f2 := Monetization.can_show_interstitial()
	var _t23_brew0 := g._engine.brewing
	var _t23_busy0 := g._pages._bench_busy
	g._engine.brewing = true
	var _t23_brew_block := g._modal_open_for_ads()
	var _t23_ts_f2 := UserData.last_interstitial_at()
	g._on_tab_changed(0)
	var _t23_brew_shown := UserData.last_interstitial_at() > _t23_ts_f2
	g._engine.brewing = _t23_brew0
	g._pages._bench_busy = true
	var _t23_busy_block := g._modal_open_for_ads()
	g._pages._bench_busy = _t23_busy0
	Selftest.check("t23 manual brew and busy bench block the interstitial",
		_t23_can_f2 and _t23_brew_block and not _t23_brew_shown and _t23_busy_block)

	# --- F1 (раунд правки): гейт достроенного UI на границе навигации ---
	# Первый tab_changed эмитится синхронно во время построения вкладок
	# (_make_page -> add_child), когда попапов ещё нет. До правки до
	# Monetization.show_interstitial его спасало только то, что _ads ещё не
	# поднят (_boot не отработал) — побочный эффект, а не guard.
	var _t23_ui0 := g._ui_ready
	_t23_clear_ad_limits()
	var _t23_can_f1 := Monetization.can_show_interstitial()
	g._ui_ready = false
	var _t23_ts_ui := UserData.last_interstitial_at()
	g._on_tab_changed(0)
	var _t23_ui_shown := UserData.last_interstitial_at() > _t23_ts_ui
	g._ui_ready = _t23_ui0
	Selftest.check("t23 tab change waits for the fully built UI",
		_t23_ui0 and _t23_can_f1 and not _t23_ui_shown)
	# Каждая поверхность предиката защищена null-проверкой: на boot-пути
	# незащищённый .visible падал с «Invalid access ... on a base object of type
	# 'null'». Проверяется прямым обнулением всех незащищённых прежде полей — их
	# одиннадцать, и ниже они обнулены одновременно.
	var _t23_p_popup := g._popup
	var _t23_p_confirm := g._confirm
	var _t23_p_return := g._saves._return_popup
	var _t23_p_settings := g._hub._settings_popup
	var _t23_p_craftable := g._hub._craftable_popup
	var _t23_p_retort := g._retort._retort_popup
	var _t23_p_journal := g._hub._journal_popup
	var _t23_p_prestige := g._hub._prestige_popup
	var _t23_p_prog := g._progress_ui._prog_popup
	var _t23_p_profile := g._hub._profile_popup
	var _t23_p_up := g._hub._up_popup
	g._popup = null
	g._confirm = null
	g._saves._return_popup = null
	g._hub._settings_popup = null
	g._hub._craftable_popup = null
	g._retort._retort_popup = null
	g._hub._journal_popup = null
	g._hub._prestige_popup = null
	g._progress_ui._prog_popup = null
	g._hub._profile_popup = null
	g._hub._up_popup = null
	var _t23_nulls_closed := not g._modal_open_for_ads()
	# Положительная половина — вот что делает проверку не пустой: нижняя по порядку
	# ветка предиката (_home._house_popup) открыта, и «истина» достижима только если
	# все обнулённые поверхности выше прошли молча. Убираем любой из null-guard'ов —
	# вызов прерывается на этой ветке, Godot отдаёт null, и предикат уже не «true».
	# Первая половина при этом не случайна: без неё любая случайно открытая ветка
	# выше вернула бы true до обнулённых строк, и кейс стал бы зелёным впустую.
	var _t23_house_vis0 := g._home._house_popup.visible
	g._home._house_popup.visible = true
	var _t23_nulls_open := g._modal_open_for_ads()
	g._home._house_popup.visible = _t23_house_vis0
	g._popup = _t23_p_popup
	g._confirm = _t23_p_confirm
	g._saves._return_popup = _t23_p_return
	g._hub._settings_popup = _t23_p_settings
	g._hub._craftable_popup = _t23_p_craftable
	g._retort._retort_popup = _t23_p_retort
	g._hub._journal_popup = _t23_p_journal
	g._hub._prestige_popup = _t23_p_prestige
	g._progress_ui._prog_popup = _t23_p_prog
	g._hub._profile_popup = _t23_p_profile
	g._hub._up_popup = _t23_p_up
	Selftest.check("t23 modal predicate null-guards every unbuilt surface",
		_t23_nulls_closed and _t23_nulls_open
		and _t23_house_vis0 == false and not g._modal_open_for_ads())

	# --- T23.4: снятие pending на каждом отказе ---
	var _t23_pid := "starter_bundle"
	var _t23_sku := "al_loop_starter_2026"
	var _t23_provider := "google_play"
	var _t23_pay := T22SignalProbe.new()
	Monetization.purchase_succeeded.connect(_t23_pay._on_purchase_succeeded)
	Monetization.purchase_failed.connect(_t23_pay._on_purchase_failed)
	# store_id = "google_play" (выведен выше в interstitial-секции) — иначе SKU
	# al_loop_starter_2026 не резолвится и ветки отказа вышли бы через unknown_sku,
	# а не через покрываемый код. Очередь очищается, чтобы «is_empty» ниже значил
	# «запрос не ушёл», а не «очередь была пуста случайно».
	Monetization._verify_requests.clear()
	# (a) _on_billing_failed: product_id известен из _pending_product.
	var _t23_fix_a := _t23_open_pending(_t23_pid, _t23_provider, _t23_sku)
	Monetization._pending_product = _t23_pid
	var _t23_n0 := _t23_pay.events.size()
	Monetization._on_billing_failed("user_cancelled", "Покупка отменена")
	Selftest.check("t23 billing failure clears pending",
		_t23_fix_a and Monetization._pending_product == ""
		and UserData.get_pending_purchase(_t23_pid).is_empty()
		and _t23_pay.events.size() == _t23_n0 + 1
		and String(_t23_pay.events[_t23_n0]) == "failed:user_cancelled:starter_bundle")
	# (b) missing_token.
	var _t23_fix_b := _t23_open_pending(_t23_pid, _t23_provider, _t23_sku)
	var _t23_n1 := _t23_pay.events.size()
	Monetization._on_purchase_received({"provider": _t23_provider, "sku": _t23_sku, "token": "", "state": "purchased"})
	Selftest.check("t23 missing token clears pending",
		_t23_fix_b and UserData.get_pending_purchase(_t23_pid).is_empty()
		and String(_t23_pay.events[_t23_n1]) == "failed:missing_token:starter_bundle"
		and Monetization._verify_requests.is_empty())
	# (c) receipt_queue_full: очередь забивается до потолка, чек не уходит на сервер.
	Monetization._verify_requests.clear()
	for _t23_i in range(Monetization.MAX_QUEUED_RECEIPT_CHECKS):
		Monetization._verify_requests.append({"provider": _t23_provider, "sku": "t23_filler",
			"token": "t23_filler_%d" % _t23_i, "product_id": "t23_filler"})
	var _t23_fix_c := _t23_open_pending(_t23_pid, _t23_provider, _t23_sku)
	var _t23_n2 := _t23_pay.events.size()
	Monetization._on_purchase_received({"provider": _t23_provider, "sku": _t23_sku, "token": "t23_queue_full_token", "state": "purchased"})
	Selftest.check("t23 full verify queue clears pending",
		_t23_fix_c and UserData.get_pending_purchase(_t23_pid).is_empty()
		and String(_t23_pay.events[_t23_n2]) == "failed:receipt_queue_full:starter_bundle"
		and Monetization._verify_requests.size() == Monetization.MAX_QUEUED_RECEIPT_CHECKS)
	# (d) receipt_not_verified: вердикт сервера по уже опознанному товару.
	Monetization._verify_requests.clear()
	Monetization._verify_requests.append({"provider": _t23_provider, "sku": _t23_sku,
		"token": "t23_notverified_token", "product_id": _t23_pid})
	var _t23_fix_d := _t23_open_pending(_t23_pid, _t23_provider, _t23_sku)
	var _t23_n3 := _t23_pay.events.size()
	Monetization._on_receipt_verify_result({"ok": false, "verified": false, "reason": "purchase_not_found"})
	Selftest.check("t23 unverified receipt clears pending",
		_t23_fix_d and Monetization._pending_product == ""
		and UserData.get_pending_purchase(_t23_pid).is_empty()
		and String(_t23_pay.events[_t23_n3]) == "failed:receipt_not_verified:starter_bundle"
		and Monetization._verify_requests.is_empty())
	# (e) grant_failed: начисления не было (game не пристегнут) — pending не мусор.
	Monetization._game = null
	var _t23_tok_e := "t23_grant_fail_token"
	var _t23_key_e := UserData._token_key(_t23_provider, _t23_tok_e, _t23_sku)
	var _t23_fix_e := _t23_open_pending(_t23_pid, _t23_provider, _t23_sku)
	var _t23_n4 := _t23_pay.events.size()
	Monetization._finish_purchase({"provider": _t23_provider, "sku": _t23_sku,
		"token": _t23_tok_e, "product_id": _t23_pid}, false)
	Selftest.check("t23 grant failure clears pending and leaves nothing granted",
		_t23_fix_e and UserData.get_pending_purchase(_t23_pid).is_empty()
		and String(_t23_pay.events[_t23_n4]) == "failed:grant_failed:starter_bundle"
		and not Monetization._purchase_already_granted(_t23_provider, _t23_sku, _t23_tok_e, _t23_pid)
		and not UserData._processed.has(_t23_key_e))
	Monetization._game = _t23_game0

	# --- восстановление ---
	OS.set_environment("ALCHEMY_ADS_STUB", _t23_env0)
	UserData.set_consent("ads_personalized", _t23_consent0)
	UserData._data["app"] = _t23_app0
	_t23_restore_ads_state(_t23_ads_state0)
	UserData.set_owned_product("remove_ads", _t23_owned0)
	_t23_ad.rewarded_completed.disconnect(Monetization._on_rewarded_completed)
	_t23_ad.ad_failed.disconnect(Monetization._on_ad_failed)
	Monetization._ads = _t23_ads_real
	Monetization.store_id = _t23_store0
	Monetization._pending_product = _t23_pending_product0
	Monetization._pending_placement = _t23_pending_placement0
	Monetization._verify_requests = _t23_queue0
	Monetization.purchase_succeeded.disconnect(_t23_pay._on_purchase_succeeded)
	Monetization.purchase_failed.disconnect(_t23_pay._on_purchase_failed)
	Monetization.rewarded_available.disconnect(_t23_probe._on_rewarded_available)
	Monetization.rewarded_started.disconnect(_t23_probe._on_rewarded_started)
	Monetization.rewarded_finished.disconnect(_t23_probe._on_rewarded_finished)
	Monetization.configure_consent()
	g._engine.ether = _eth0
	g._engine.ether_overflow = _ovf0
	g._engine.status_text = _t23_status0
	Selftest.check("t23 ads fixture, facade and engine state restored",
		Monetization._ads == _t23_ads_real and Monetization.store_id == _t23_store0
		and Monetization._game == _t23_game0 and Monetization._pending_product == _t23_pending_product0
		and Monetization._pending_placement == _t23_pending_placement0
		# Очередь проверок сравнивается размером и конкретными ключами: `==` над
		# массивом Dictionary в Godot 4 — ГЛУБОКОЕ сравнение, оно бы прошло и на
		# «restore не выполнен, просто совпало содержимое».
		and Monetization._verify_requests.size() == _t23_queue0.size()
		and not _t23_has_leftover_request()
		and Monetization.ads_available == _t23_avail0
		and Monetization._ads.is_available() == _t23_avail0
		and OS.get_environment("ALCHEMY_ADS_STUB") == _t23_env0
		and UserData.get_consent("ads_personalized") == _t23_consent0
		and UserData.is_product_owned("remove_ads") == _t23_owned0
		and g._engine.ether + g._engine.ether_overflow == _t23_eth_base
		and g._engine._auto == _t23_auto0)

	# ---------- #8: удаление аккаунта внутри живой сессии ----------
	# Дефект был: «Удалить локальные данные» не переживало живую сессию — автосейв
	# и пауза пересоздавали стёртый файл из памяти, а device_id продолжал ходить
	# на сервер. Механизм: заморозка записи в единственной точке (_save_game),
	# маркер-файл, переживающий вайп, и сброс сетевой идентичности (все DELETE в
	# shop.gd гейтятся _net_enabled). Живого HTTP здесь нет: в селфтесте net
	# выключен, а маршрут/точный id DELETE проверяются на экземплярах — чистый
	# Net._build_request и seam I8FailSendNet (тот же приём, что FailSendNet в
	# suite_resonance_net: старт запроса всегда падает, HTTP не делается).
	var _i8_data0 := UserData._data.duplicate(true)
	var _i8_dev0 := g._online._device_id
	var _i8_en0 := g._online._net_enabled
	var _i8_nick0 := g._online._net_nick
	var _i8_frozen0 := g._saves._save_frozen
	var _i8_armed0 := g._shop._delete_armed
	var _i8_marker0 := UserData.get_account_delete_pending()
	# Маркер обязан быть чистым, иначе первый нажим уйдёт в pending-ветку и весь
	# блок проверит не то.
	Selftest.check("i8 no stale marker before test", _i8_marker0 == "")
	UserData._data["device_id"] = "i8-dev/1"
	g._online._device_id = "i8-dev/1"
	g._online._net_nick = "И8"
	# _net_enabled НЕ включаем: в селфтесте это означало бы живой HTTP-DELETE на
	# dev-сервер. Веткой «net выключен» проверяется, что вайп доводится до конца
	# независимо от доступности сети.
	g._online._net_enabled = false
	# Сейв на диске обязателен для предусловия: на первом прогоне автосейв мог
	# ещё не создать ST-файл.
	g._saves._save_game()
	var _i8_boot := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("i8 preconditions: real device id and save on disk",
		UserData.get_or_create_device_id() == "i8-dev/1" and not _i8_boot.is_empty())
	# Маршрут DELETE: /api/account + METHOD_DELETE (контракт server.py delete_account).
	var _i8_route := Net._build_request({"kind": "account_delete",
		"path": "/account?device_id=" + "i8-dev/1".uri_encode(),
		"method": HTTPClient.METHOD_DELETE})
	Selftest.check("i8 delete route is DELETE /api/account with encoded id",
		String(_i8_route["url"]).ends_with("/api/account?device_id=i8-dev%2F1")
		and int(_i8_route["method"]) == HTTPClient.METHOD_DELETE)
	# Первый нажим: только arm (исходная подпись кнопки — из константы shop.gd).
	var _i8_label0 := String(g._shop._delete_button.text)
	g._shop._delete_data()
	Selftest.check("i8 first press only arms", g._shop._delete_armed
		and String(g._shop._delete_button.text) != _i8_label0
		and _i8_label0 == "Удалить данные: журнал покупок останется"
		and UserData.get_account_delete_pending() == ""
		and g._online._device_id == "i8-dev/1")
	# Второй нажим без сети: вайп всё равно завершён (сервер — не условие
	# локального удаления), маркер остался, старая идентичность сброшена.
	var _i8_status_before := String(g._shop._status.text)
	g._shop._delete_data()
	Selftest.check("i8 offline wipe completes: save gone, marker kept, identity cleared",
		not FileAccess.file_exists(g.SAVE_PATH)
		and UserData.get_account_delete_pending() == "i8-dev/1"
		and g._saves._save_frozen and g._online._device_id == ""
		and not g._online._net_enabled and g._online._net_nick == ""
		and _i8_status_before != String(g._shop._status.text))
	# Заморозка: прямой вызов единственной точки записи не пересоздаёт файл.
	g._saves._save_game()
	Selftest.check("i8 direct save after wipe does not recreate files",
		not FileAccess.file_exists(g.SAVE_PATH)
		and not FileAccess.file_exists(g.TEMP_PATH)
		and not FileAccess.file_exists(g.BACKUP_PATH))
	# Пауза приложения — путь, который до правки и resurrect'ил файл.
	g.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	Selftest.check("i8 pause does not resurrect the deleted save",
		not FileAccess.file_exists(g.SAVE_PATH))
	# Вайп пользовательского файла маркер не стирает (он для того и отдельный).
	UserData.delete_all_local_data()
	Selftest.check("i8 marker survives delete_all_local_data",
		UserData.get_account_delete_pending() == "i8-dev/1")
	# Ответ без ok маркер НЕ снимает: хендлеры вызываются напрямую (в
	# селфтесте коннект main.gd не поставлен). Статус перед вызовом перетирается,
	# чтобы «contains(повтори)» доказывал именно этот вызов, а не offline-слив
	# предыдущей проверки.
	g._shop._status.text = "i8-маркер-до-отказа"
	g._shop._on_account_delete_result({"ok": false, "offline": true})
	g._online._on_account_delete_result({"ok": false, "offline": true})
	Selftest.check("i8 failed result keeps the marker",
		UserData.get_account_delete_pending() == "i8-dev/1"
		and String(g._shop._status.text).contains("повтори удаление"))
	# Ретрай в той же сессии: повторный нажим берёт device_id из маркера (не из
	# уже стёртой локальной идентичности), ничего не перетирает второй раз и не
	# дёргает сеть при выключенном net.
	var _i8_status_p := String(g._shop._status.text)
	g._shop._delete_data()
	Selftest.check("i8 re-press retries by saved id without wiping again",
		String(g._shop._status.text) != _i8_status_p
		and g._online._device_id == "" and Net._queue.is_empty()
		and UserData.get_account_delete_pending() == "i8-dev/1"
		and not g._shop._delete_armed and not FileAccess.file_exists(g.SAVE_PATH))
	# Startup-ретрай (main.gd зовёт его в net-блоке) обязан послать DELETE ровно
	# по id из маркера. Seam I8FailSendNet считает попытки и маршрут: с живым
	# HTTP селфтест никогда не трогает dev-сервер.
	var _i8_net := I8FailSendNet.new()
	g._online._retry_pending_account_delete(_i8_net)
	Selftest.check("i8 startup retry sends DELETE /api/account for saved id",
		_i8_net.attempts == 1 and _i8_net.urls.size() == 1
		and String(_i8_net.urls[0]).ends_with("/api/account?device_id=i8-dev%2F1"))
	# Пустой маркер — ретрай молчит: сначала снимаем маркер, иначе кейс был бы
	# недостижим (после первого ретрая он ещё стоит).
	UserData.clear_account_delete_pending()
	var _i8_net2 := I8FailSendNet.new()
	g._online._retry_pending_account_delete(_i8_net2)
	Selftest.check("i8 retry with empty marker sends nothing", _i8_net2.attempts == 0)
	UserData.mark_account_delete_pending("i8-dev/1")
	# ok-ответ: online-хендлер снимает маркер (путь коннекта main.gd),
	# shop-хендлер обновляет статус.
	g._online._on_account_delete_result({"ok": true, "deleted": true})
	var _i8_status_ok := String(g._shop._status.text)
	g._shop._on_account_delete_result({"ok": true, "deleted": true})
	Selftest.check("i8 ok result clears the marker and reports",
		UserData.get_account_delete_pending() == ""
		and String(g._shop._status.text).contains("Серверные данные удалены")
		and _i8_status_ok != String(g._shop._status.text))
	# Размороженный сейв пишет снова: путь _save_game жив после отпуска.
	g._saves._save_frozen = false
	g._saves._save_game()
	var _i8_rewritten := g._saves._read_save(g.SAVE_PATH)
	Selftest.check("i8 unfrozen save writes again", not _i8_rewritten.is_empty())
	# восстановление состояния сюиты
	UserData.clear_account_delete_pending()
	UserData._data = _i8_data0
	UserData._save()
	g._online._device_id = _i8_dev0
	g._online._net_enabled = _i8_en0
	g._online._net_nick = _i8_nick0
	g._saves._save_frozen = _i8_frozen0
	g._shop._delete_armed = _i8_armed0
	Selftest.check("i8 marker, online identity and UserData restored",
		UserData.get_account_delete_pending() == "" and _i8_marker0 == ""
		and UserData.get_or_create_device_id() == String(_i8_data0.get("device_id", ""))
		and g._online._device_id == _i8_dev0 and g._online._net_enabled == _i8_en0
		and g._online._net_nick == _i8_nick0 and not g._saves._save_frozen)

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


class T23FakeAdsClient extends RefCounted:
	# Копия наблюдаемого контракта рекламного плагина: ровно те имена сигналов,
	# которые перечисляет AdsAdapter._connect_signals, и с той арностью, какую
	# читают его обработчики (ad_failed_to_show — code + message). Нужен, чтобы
	# проверить ПЕРЕПОДКЛЮЧЕНИЕ rewarded_closed на свой обработчик, а не только
	# тело обработчика: эмит по имени сигнала идёт тем же путём, что и в сборке.
	signal rewarded(value)
	signal rewarded_closed(value)
	signal ad_failed_to_show(code, message)
	signal interstitial_closed
	# F3 (раунд правки): нуль-аргументный show-метод реального плагина — адаптер
	# зовёт _call_first(["show_rewarded", ...], []) с пустыми аргументами. С ним
	# полный цикл награды идёт через не-stub ветку адаптера без method_missing.
	func show_rewarded() -> bool:
		return true


class T23AdsProbe extends RefCounted:
	# Коллектор рекламных и фасадных сигналов в один поток: «ни одного
	# rewarded_completed» и «ровно один not_earned» наблюдаемы так же хорошо, как
	# наличие. Метки считаются по префиксу (count_since), чтобы лишнее событие
	# красило кейс, а не сдвигало окна индексов.
	var events: Array = []
	func _on_initialized(available: bool, _message: String) -> void:
		events.append("init:" + str(available))
	func _on_rewarded(placement_id: String) -> void:
		events.append("rewarded:" + placement_id)
	func _on_failed(code: String, _message: String) -> void:
		events.append("failed:" + code)
	func _on_rewarded_available(placement_id: String, available: bool) -> void:
		events.append("available:%s:%s" % [placement_id, str(available)])
	func _on_rewarded_started(placement_id: String) -> void:
		events.append("started:" + placement_id)
	func _on_rewarded_finished(placement_id: String, _reward: Dictionary) -> void:
		events.append("finished:" + placement_id)
	func count_since(start_index: int, prefix: String) -> int:
		var hits := 0
		for i in range(start_index, events.size()):
			if String(events[i]).begins_with(prefix):
				hits += 1
		return hits


static func _t23_clear_ad_limits() -> void:
	# Фиксатура дневного капа и обоих cooldown-времени: «отказ по согласию» нельзя
	# объяснить отказом по частоте. day="" — чтобы rewarded_count_for_today()
	# вернул 0 независимо от того, сколько просмотров записали ранние сюиты.
	UserData.set_ads_state({"day": "", "rewarded_count": 0, "last_rewarded_at": 0.0, "last_interstitial_at": 0.0})


static func _t23_restore_ads_state(state: Dictionary) -> void:
	UserData.set_ads_state(state)


static func _t23_open_pending(product_id: String, provider: String, sku: String) -> bool:
	# Возвращает НАБЛЮДАЕМОСТЬ фиксатуры: запись действительно легла в pending —
	# иначе кейс «отказ снял запись» прошёл бы зелёным на пустом месте.
	UserData.set_pending_purchase(product_id, {"provider": provider, "sku": sku, "started_at": 1.0})
	return not UserData.get_pending_purchase(product_id).is_empty()


static func _t23_has_leftover_request() -> bool:
	# Признак того, что очередь проверок чеков не вернулась к исходному виду
	# (все t23-маркеры обязаны быть сняты самим блоком).
	for item in Monetization._verify_requests:
		if item is Dictionary and String((item as Dictionary).get("product_id", "")).begins_with("t23_"):
			return true
	return false


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


class I8FailSendNet extends NetBase:
	# Seam для #8 (тот же приём, что FailSendNet в suite_resonance_net): эмулирует
	# штатный для Android случай «HTTPRequest.request() не стартовал» без живого
	# HTTP, записывая url/method каждого DELETE — так селфтест доказывает, что
	# стартовый ретрай шлёт сохранённый device_id, не трогая dev-сервер.
	var attempts := 0
	var urls: Array = []
	var methods: Array = []
	func _try_send(url: String, _headers: PackedStringArray, method: int, _body: String) -> int:
		attempts += 1
		urls.append(url)
		methods.append(method)
		return ERR_CANT_CONNECT
