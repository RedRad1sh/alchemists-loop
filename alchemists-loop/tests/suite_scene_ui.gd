extends RefCounted
class_name SuiteSceneUi
# R15: каркас «сцена как меню» — HUD-капсула, нижний таб-бар, карусель комнат.
# Headless-проверки без интерактива: узлы построены _build_ui в selftest-среде.
#
# Мутационные красные зоны:
# - снятие build HUD красит «hud built» и «ether compact + rate chip»;
# - удаление BottomNav красит «nav six», «nav press switches tab»;
# - показ верхнего TabBar красит «top tab bar hidden»;
# - удаление RoomCarousel красит «rooms two», «room switch», «props three»;
# - возврат старых офсетов brew-бара красит «brew bar above nav».
# - офсет колоды под панелью варки красит «deck clear of brew bar»;
# - мыши-only свайп красит «touch swipe advances room», отсутствие guard-а
#   на релизе без нажатия — «stray release ignored»;
# - кнопка «Закрыть», проводившая не в close(), красит «daily/sheet close button
#   closes»; затенение `var close` в той же lambda проверкой НЕ краснеет: в
#   GDScript 4 вызов `close()` резолвится на метод (замер isolated-скриптом),
#   поэтому переименование — читаемость, а не починка;
# - `_apply_tools_selection()` без учёта листа красит «sheet survives core refresh»;
# - тап по карте круга без гейта красит «locked circle explains gate»;
# - UTC-база вчерашнего дня красит «yesterday follows local today»;
# - no-op `_companion_gain()` до разблокировки красит «friendship banks …» и
#   «companion unlock flushes banked friendship»;
# - индексы 4/5 вместо TAB_RATING/TAB_TOOLS в `_on_tab_changed()` красят
#   «rating tab refetches rating» и «tools tab rebuilds tool selection».

static func run(g: Game) -> void:
	var st_tab := g._tabs_ref.current_tab

	# HUD
	Selftest.check("hud built", g._hud != null
			and is_instance_valid(g._hud.cap_bar)
			and is_instance_valid(g._hud.rate_chip))
	Selftest.check("hud reuses contract nodes", g._me_avatar != null
			and g._social_btn != null and g._hub._up_btn != null
			and g._sound_btn != null and g._engine._ether_label != null)
	g._engine._refresh_header()
	Selftest.check("ether compact + rate chip",
			g._engine._ether_label.text.begins_with("⚡ ")
			and g._hud.rate_chip.text.contains("/с"))

	# Нижний таб-бар и спрятанный верхний
	Selftest.check("nav six", g._bottom_nav != null
			and g._bottom_nav._items.size() == 6)
	Selftest.check("top tab bar hidden",
			not g._tabs_ref.get_tab_bar().visible)
	g._bottom_nav._on_pressed("rating")
	Selftest.check("nav press switches tab",
			g._tabs_ref.current_tab == Game.TAB_RATING)
	g._bottom_nav.refresh(st_tab)

	# Карусель комнат
	Selftest.check("rooms two", g._rooms != null and g._rooms._rooms.size() == 2)
	Selftest.check("props three", g._rooms._props.has("spring")
			and g._rooms._props.has("bench") and g._rooms._props.has("retort"))
	g._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	g._rooms.set_room(1)
	Selftest.check("room switch", g._rooms._room_idx == 1
			and g._rooms._rooms[1].visible and not g._rooms._rooms[0].visible
			and g._rooms._left_btn.visible and not g._rooms._right_btn.visible)
	g._rooms.set_room(0)
	Selftest.check("room back", g._rooms._room_idx == 0
			and g._rooms._rooms[0].visible)

	# Brew-бар стоит над нижним навом
	Selftest.check("brew bar above nav",
			g._brew_bar.offset_bottom == -76 and g._brew_bar.offset_top == -196)

	# R16: bottom-sheet — reparent бокса туда и обратно
	Selftest.check("sheet closed initially", not g._sheet.is_open())
	var res_box: Control = g._pages._mode_pages.get("resonance")
	Selftest.check("resonance box built", res_box != null)
	if res_box != null:
		var orig_parent := res_box.get_parent()
		g._sheet.open("resonance", "Отголоски")
		Selftest.check("sheet opens resonance", g._sheet.is_open()
				and res_box.get_parent() == g._sheet._host_box)
		g._sheet.close()
		Selftest.check("sheet restores parent", not g._sheet.is_open()
				and res_box.get_parent() == orig_parent)

	# R16: карточка круга на сцене
	Selftest.check("circle card present", g._rooms._circle_card != null
			and g._rooms._circle_slots.size() == 3)
	var brew_bar: Control = g.find_child("BrewBar", true, false)
	Selftest.check("circle card above brew bar", brew_bar != null
			and not g._rooms._circle_card.get_global_rect().intersects(brew_bar.get_global_rect()))

	# R16: дейли-сетка — один claim в день, стрик и награда
	var s0 := g._engine.ether + g._engine.ether_overflow
	g._daily.open()
	Selftest.check("daily opens", g._daily.is_open())
	g._daily._on_claim()
	var s1 := g._engine.ether + g._engine.ether_overflow
	Selftest.check("daily claim grants", g._daily.streak == 1
			and g._daily.claim_day == g._daily._today() and s1 >= s0 + 30)
	g._daily._on_claim()
	Selftest.check("daily no double claim", g._daily.streak == 1
			and g._engine.ether + g._engine.ether_overflow == s1)
	g._daily.close()
	Selftest.check("daily closes", not g._daily.is_open())

	# R17: оптовая покупка улучшений (×1/×10/×100)
	var eng := g._engine
	var prev_lvl := eng._up_lvl("ether_cap")
	var prev_ether := eng.ether
	eng.upgrades["ether_cap"] = 0
	eng.ether = 100000000
	var want := 0
	for k in 8:
		want += eng._up_cost_at("ether_cap", k)
	Selftest.check("bulk buy stops at max", eng._buy_upgrade("ether_cap", 10)
			and eng._up_lvl("ether_cap") == 8 and eng.ether == 100000000 - want)
	Selftest.check("bulk buy at max refused", not eng._buy_upgrade("ether_cap", 10)
			and eng._up_lvl("ether_cap") == 8)
	# частичная покупка: эфира хватает только на 2 уровня из 10
	eng.upgrades["ether_cap"] = 0
	eng.ether = eng._up_cost_at("ether_cap", 0) + eng._up_cost_at("ether_cap", 1) + 5
	Selftest.check("bulk buy limited by ether", eng._buy_upgrade("ether_cap", 10)
			and eng._up_lvl("ether_cap") == 2 and eng.ether == 5)
	# qty=1 (вызов без аргумента) — точная цена одного уровня
	eng.ether = eng._up_cost_at("ether_cap", 2) + 7
	Selftest.check("single buy exact cost", eng._buy_upgrade("ether_cap")
			and eng._up_lvl("ether_cap") == 3 and eng.ether == 7)
	# UI: чипы множителя переключаются
	g._hub._pick_up_qty(10)
	Selftest.check("qty chip 10", g._hub._up_qty == 10)
	g._hub._pick_up_qty(1)
	Selftest.check("qty chip back to 1", g._hub._up_qty == 1)
	eng.upgrades["ether_cap"] = prev_lvl
	eng.ether = prev_ether
	eng._refresh()

	# R17c: замечания ревью по сцене (геометрия пропов, свайп, лист, гейт круга,
	# локальный календарь дейли-стрика, ненаказуемая дружба).
	# 1) Колода не должна лежать под варочной панелью и под картой круга.
	var deck: Control = g._rooms._deck_btn
	Selftest.check("deck clear of brew bar", deck != null and brew_bar != null
			and deck.visible and deck.get_global_rect().size.x > 0.0
			and not deck.get_global_rect().intersects(brew_bar.get_global_rect()))
	Selftest.check("deck clear of circle card", deck != null
			and not deck.get_global_rect().intersects(g._rooms._circle_card.get_global_rect()))

	# 2) Свайп пальцем: карусель принимала только мышь.
	var tp := InputEventScreenTouch.new()
	tp.pressed = true
	tp.position = Vector2(300, 200)
	g._rooms._on_gui_input(tp)
	var tr := InputEventScreenTouch.new()
	tr.pressed = false
	tr.position = Vector2(120, 200)
	g._rooms._on_gui_input(tr)
	Selftest.check("touch swipe advances room", g._rooms._room_idx == 1)
	tp.pressed = true
	tp.position = Vector2(120, 200)
	g._rooms._on_gui_input(tp)
	tr.pressed = false
	tr.position = Vector2(300, 200)
	g._rooms._on_gui_input(tr)
	Selftest.check("touch swipe returns", g._rooms._room_idx == 0)
	# Тач эмулирует мышь: релиз без нажатия не должен листать страницу.
	var stray := InputEventScreenTouch.new()
	stray.pressed = false
	stray.position = Vector2(300, 200)
	g._rooms._on_gui_input(stray)
	Selftest.check("stray release ignored", g._rooms._room_idx == 0)

	# 3) Кнопка «Закрыть» обязана вызывать метод листа/сетки, а не одноимённую
	# локальную переменную-кнопку.
	g._daily.open()
	var daily_close: Button = g.find_child("DailyClose", true, false)
	if daily_close != null:
		daily_close.pressed.emit()
	Selftest.check("daily close button closes", daily_close != null and not g._daily.is_open())
	g._sheet.open("resonance", "Отголоски")
	var sheet_close: Button = g.find_child("SheetClose", true, false)
	if sheet_close != null:
		sheet_close.pressed.emit()
	Selftest.check("sheet close button closes", sheet_close != null and not g._sheet.is_open())

	# 4) Обновление ядра при открытом листе не должно гасить его содержимое.
	g._sheet.open("resonance", "Отголоски")
	var sheet_box: Control = g._pages._mode_pages.get("resonance")
	g._engine._refresh()
	Selftest.check("sheet survives core refresh", g._sheet.is_open()
			and sheet_box != null and sheet_box.visible)
	g._sheet.close()

	# 5) Карта круга видна всегда (peek), но до 20 веществ она обязана
	# объяснять условие, а не молча не открывать ничего.
	var inv_backup := g._engine.inventory.duplicate()
	g._engine.inventory.clear()
	for old_key in inv_backup.keys():
		if g._engine.inventory.size() >= 3:
			break
		g._engine.inventory[old_key] = 1
	g._engine.status_text = ""
	g._rooms._open_circle()
	Selftest.check("locked circle explains gate", not g._sheet.is_open()
			and g._engine.status_text == g._pages._mode_hint("circle"))
	g._engine.inventory = inv_backup
	g._engine.status_text = ""
	g._engine._refresh()
	g._rooms._open_circle()
	Selftest.check("unlocked circle opens sheet", g._sheet.is_open())
	g._sheet.close()

	# 6) Стрик по локальному календарю: UTC-база ронила стрик на границе дня.
	var today_dict := Time.get_date_dict_from_system(false)
	Selftest.check("yesterday follows local today", g._daily._yesterday()
			== DailyGrid._prev_day(int(today_dict["year"]), int(today_dict["month"]),
					int(today_dict["day"])))
	Selftest.check("prev day crosses month", DailyGrid._prev_day(2026, 3, 1) == "2026-02-28")
	Selftest.check("prev day crosses leap february", DailyGrid._prev_day(2028, 3, 1) == "2028-02-29")
	Selftest.check("prev day crosses year", DailyGrid._prev_day(2026, 1, 1) == "2025-12-31")
	Selftest.check("prev day skips century leap", DailyGrid._prev_day(2100, 3, 1) == "2100-02-28")

	# 7) Дружба до пробуждения Светика копится и применяется целиком, а не сгорает.
	var sp := g._spirit
	var sp_unlocked := sp._companion_unlocked
	var sp_met := sp._companion_met
	var sp_aff := sp._companion_affinity
	var sp_pend := sp._companion_pending_aff
	var sp_lvl := sp._companion_level
	var sp_ether := g._engine.ether
	sp._companion_unlocked = false
	sp._companion_pending_aff = 0
	sp._companion_affinity = 0
	sp._companion_gain(3)
	Selftest.check("friendship banks while companion locked", sp._companion_affinity == 0
			and sp._companion_pending_aff == 3)
	sp._companion_unlock()
	Selftest.check("companion unlock flushes banked friendship",
			sp._companion_pending_aff == 0 and sp._companion_affinity == 3)
	sp._companion_unlocked = sp_unlocked
	sp._companion_met = sp_met
	sp._companion_affinity = sp_aff
	sp._companion_pending_aff = sp_pend
	sp._companion_level = sp_lvl
	g._engine.ether = sp_ether
	g._engine._refresh()
	# раз _companion_unlock() успел записать тестовые значения — перепишем сейв
	g._saves._save_game()

	# 8) `_on_tab_changed` должен висеть на индексах навигации: рейтинг — 3,
	# «Ещё» — 4 (сравнение с 4 и 5 не давало рейтингу обновиться никогда).
	# Подписчики Net в selftest не коннектятся (net выключен на старте), поэтому
	# счётчик вешаем сами; base_url = "" — запрос не стартует, очередь сливается
	# synchronous offline-итогом и emit'ом rating_result.
	var base_url_was := Net.base_url
	Net.base_url = ""
	var net_en := g._online._net_enabled
	g._online._net_enabled = true
	var spy := RatingHit.new()
	Net.rating_result.connect(spy.catch)
	g._tabs_ref.current_tab = Game.TAB_RATING
	Selftest.check("rating tab refetches rating", spy.hits == 1)
	var sel0 := String(g._pages._tools_sel)
	g._pages._tools_sel = "zzz-not-a-mode"
	g._tabs_ref.current_tab = Game.TAB_TOOLS
	Selftest.check("tools tab rebuilds tool selection",
			String(g._pages._tools_sel) != "zzz-not-a-mode")
	Selftest.check("tools tab does not refetch rating", spy.hits == 1)
	Net.rating_result.disconnect(spy.catch)
	g._pages._tools_sel = sel0
	g._pages._apply_tools_selection()
	g._online._net_enabled = net_en
	Net.base_url = base_url_was

	g._tabs_ref.current_tab = st_tab


class RatingHit:
	var hits := 0

	func catch(_result: Dictionary) -> void:
		hits += 1
