extends RefCounted
# Английская локализация и переключение языка в настройках.

static func _strip_test_fixtures(s: String) -> String:
	for tok in ["Тестер", "ДитяЭха", "РезБ", "РезА"]:
		s = s.replace(tok, "")
	return s


static func _has_cyrillic(s: String) -> bool:
	s = _strip_test_fixtures(s)
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 0x0400 and c <= 0x04FF) or c == 0x0401 or c == 0x0451:
			return true
	return false


static func _collect_cyrillic_leaks(node: Node, out: Array, tag: String) -> void:
	if node is Control:
		var c := node as Control
		if not c.is_visible_in_tree():
			return
		if c is Label:
			var lb := c as Label
			var shown := lb.atr(lb.text)
			if _has_cyrillic(shown):
				out.append(tag + ":" + String(lb.name) + "=" + shown)
		elif c is Button:
			var bt := c as Button
			var shown := bt.atr(bt.text)
			if _has_cyrillic(shown):
				out.append(tag + ":" + String(bt.name) + "=" + shown)
		elif c is LineEdit:
			var le := c as LineEdit
			var shown := le.atr(le.placeholder_text)
			if _has_cyrillic(shown):
				out.append(tag + ":" + String(le.name) + "=" + shown)
	for ch in node.get_children():
		_collect_cyrillic_leaks(ch, out, tag)

static func run(g: Game) -> void:
	var locale_node := g.get_node_or_null("/root/Locale")
	Selftest.check("i18n Locale autoload exists and defaults to ru",
		locale_node != null and String(locale_node.get("lang")) == "ru"
		and TranslationServer.get_locale().begins_with("ru"))
	if locale_node == null:
		return

	# Кнопка переключения языка в попапе настроек и во вкладке «Ещё».
	var popup_lang_btn := g._hub._settings_popup.find_child("LangToggle", true, false) as Button if g._hub._settings_popup != null else null
	var more_settings := g.find_child("MoreSettings", true, false) as Control
	var more_lang_btn := more_settings.find_child("LangToggle", true, false) as Button if more_settings != null else null
	Selftest.check("i18n settings popup and MoreSettings both expose LangToggle",
		popup_lang_btn != null and more_lang_btn != null)
	if popup_lang_btn == null or more_lang_btn == null:
		return

	# На русском отрисовываются русские подписи.
	var title_lbl := g.find_child("TitlePlaque", true, false)
	var title_node := title_lbl.get_child(0) as Label if title_lbl != null and title_lbl.get_child_count() > 0 else null
	Selftest.check("i18n default ru keeps Russian UI captions",
		title_node != null and title_node.atr(title_node.text) == "ПЕТЛЯ АЛХИМИКА"
		and g._engine._brew_btn.atr(g._engine._brew_btn.text) == "ВАРИТЬ"
		and popup_lang_btn.atr(popup_lang_btn.text).contains("Русский"))

	# Переключение кнопкой в настройках переводит язык на английский и синхронизирует обе кнопки.
	popup_lang_btn.pressed.emit()
	await g.get_tree().process_frame
	Selftest.check("i18n pressing LangToggle switches Locale to en",
		String(locale_node.get("lang")) == "en"
		and TranslationServer.get_locale().begins_with("en")
		and popup_lang_btn.atr(popup_lang_btn.text) == "Language: English"
		and more_lang_btn.atr(more_lang_btn.text) == "Language: English")

	# Основные поверхности UI переводятся на английский без кириллицы.
	var nav_ok := true
	for item in g._bottom_nav._items:
		var lb := item["label"] as Label
		var shown := lb.atr(lb.text)
		if shown.is_empty() or _has_cyrillic(shown):
			nav_ok = false
	var screen_back := g._screens.back_btn
	var ether_lbl: Label = g._engine._ether_label
	if ether_lbl == null:
		var ep := g.find_child("EtherPill", true, false)
		if ep != null:
			for ch in ep.find_children("*", "Label", true, false):
				ether_lbl = ch as Label
				break
	Selftest.check("i18n core chrome, nav, buttons and dynamic HUD translate to English",
		title_node != null and title_node.atr(title_node.text) == "ALCHEMIST'S LOOP"
		and g._engine._brew_btn != null and g._engine._brew_btn.atr(g._engine._brew_btn.text) == "BREW"
		and screen_back != null and not _has_cyrillic(screen_back.atr(screen_back.text))
		and nav_ok
		and (ether_lbl == null or not _has_cyrillic(ether_lbl.atr(ether_lbl.text)))
		and (g._engine._collection_label == null or not _has_cyrillic(g._engine._collection_label.atr(g._engine._collection_label.text))))

	# Все 109 базовых/расширенных элементов (имя и описание) переводятся без кириллицы.
	var bad_items: Array = []
	for raw_id in g.ITEMS.keys():
		var sid := String(raw_id)
		if sid.begins_with("st_") or sid.begins_with("__st") or sid.begins_with("sv_") or sid.begins_with("u1"):
			continue
		var nm_tr := g.atr(g._online._item_name(sid))
		var ds_tr := g.atr(g._online._item_desc(sid))
		if _has_cyrillic(nm_tr) or _has_cyrillic(ds_tr):
			bad_items.append(sid)
	Selftest.check("i18n all 109 item names and descriptions translate cleanly to English",
		bad_items.is_empty())
	if not bad_items.is_empty():
		print("[FAIL-DIAG] untranslated items: ", bad_items.slice(0, 10))

	# Таблицы данных (улучшения, задания, достижения, контракты, мебель дома, декор) без кириллицы.
	var bad_data: Array = []
	for u in Game.UPGRADES:
		if _has_cyrillic(g.atr(String(u["name"]))) or _has_cyrillic(g.atr(String(u["desc"]))):
			bad_data.append("up:" + String(u["id"]))
	for q in Game.SPIRIT_QUESTS:
		if _has_cyrillic(g.atr(String(q["title"]))) or _has_cyrillic(g.atr(String(q["hint"]))):
			bad_data.append("quest:" + String(q["id"]))
	for a in Game.ACHIEVEMENTS:
		if _has_cyrillic(g.atr(String(a["title"]))):
			bad_data.append("ach:" + String(a["id"]))
	for k in ContractsBalance.TITLE.keys():
		if _has_cyrillic(g.atr(String(ContractsBalance.TITLE[k]))):
			bad_data.append("ctitle:" + String(k))
	for k in ContractsBalance.BUFF_TITLE.keys():
		if _has_cyrillic(g.atr(String(ContractsBalance.BUFF_TITLE[k]))) or _has_cyrillic(g.atr(String(ContractsBalance.BUFF_TEXT[k]))):
			bad_data.append("cbuff:" + String(k))
	for hid in HouseItems.ITEMS.keys():
		if _has_cyrillic(g.atr(String(HouseItems.ITEMS[hid]["label"]))):
			bad_data.append("house:" + String(hid))
	for t in HouseTasksData.TASKS:
		if _has_cyrillic(g.atr(String(t["text"]))):
			bad_data.append("htask:" + String(t["id"]))
	Selftest.check("i18n upgrades, quests, achievements, contracts and house items translate to English",
		bad_data.is_empty())
	if not bad_data.is_empty():
		print("[FAIL-DIAG] untranslated data: ", bad_data.slice(0, 15))

	# Поиск элементов находит вещества по английскому названию ("Steam", "Fire").
	g._engine._search_box.text = "steam"
	var search_lab_ok := g._online._matches_search("steam") and not g._online._matches_search("stone")
	g._engine._search_box.text = ""
	g._pages._experiment_reagent_search.text = "flame"
	var search_exp_ok := g._pages._experiment_search_matches("fire")
	g._pages._experiment_reagent_search.text = ""
	Selftest.check("i18n search matches English element names and descriptions",
		search_lab_ok and search_exp_ok)

	# Лор сигилов в английском режиме переводится без кириллицы, сохраняя русский контракт SigilLore.generate().
	var lore_card := {
		"id": "steam", "set": "fire", "rarity": "common", "ether_cost": 50,
		"recipe": [{"item_id": "water", "qty": 10}, {"item_id": "fire", "qty": 10}],
		"process": "sublimatio", "stage": "albedo", "fallback_name": "Пар",
		"object_type": "object", "seed": 424242,
	}
	var lore_out := SigilLore.generate(lore_card)
	Selftest.check("i18n SigilLore translates generated title, description, effect and warning in en mode",
		not lore_out.is_empty()
		and _has_cyrillic(String(lore_out.get("description", "")))
		and not _has_cyrillic(g.atr(String(lore_out.get("title", ""))))
		and not _has_cyrillic(g.atr(String(lore_out.get("description", ""))))
		and not _has_cyrillic(g.atr(String(lore_out.get("effect_hint", ""))))
		and not _has_cyrillic(g.atr(String(lore_out.get("warning", "")))))

	# Рунический шрифт имеет fallback для строчной латиницы (не рисует пустые квадраты).
	var runic_f := UIStyle.runic()
	Selftest.check("i18n runic font renders lowercase Latin via fallback",
		runic_f != null and runic_f.has_char(ord("a")) and runic_f.has_char(ord("z")))

	# Проверка живого дерева сцены на основных экранах и попапах в английском режиме: без кириллицы.
	var leaks: Array = []
	_collect_cyrillic_leaks(g, leaks, "lab")
	for tab_idx in [2, 3, 4]:
		g._tabs_ref.current_tab = tab_idx
		await g.get_tree().process_frame
		_collect_cyrillic_leaks(g, leaks, "tab_%d" % tab_idx)
	g._tabs_ref.current_tab = 0
	g._pages._open_device_screen("retort", "Реторта")
	await g.get_tree().process_frame
	_collect_cyrillic_leaks(g, leaks, "retort")
	g._screens.close()
	g._hub._open_settings()
	await g.get_tree().process_frame
	_collect_cyrillic_leaks(g, leaks, "settings")
	Juice.close(g._hub._settings_dim, g._hub._settings_popup)
	g._shop.open()
	await g.get_tree().process_frame
	_collect_cyrillic_leaks(g, leaks, "shop")
	g._shop.close()
	g._hub._open_credits()
	await g.get_tree().process_frame
	_collect_cyrillic_leaks(g, leaks, "credits")
	Juice.close(g._hub._credits_dim, g._hub._credits_popup)
	Selftest.check("i18n zero Cyrillic leaks across live tabs, device screens and popups in en mode",
		leaks.is_empty())
	if not leaks.is_empty():
		print("[FAIL-DIAG] live UI leaks: ", leaks.slice(0, 15))


	# Сохранение и загрузка игры восстанавливают выбранный язык ("en" -> save -> reset to "ru" -> load -> "en").
	g._saves._save_game()
	locale_node.call("set_lang", "ru")
	Selftest.check("i18n set_lang(ru) restores Russian immediately",
		String(locale_node.get("lang")) == "ru"
		and g._engine._brew_btn.atr(g._engine._brew_btn.text) == "ВАРИТЬ")
	g._saves._load_game()
	Selftest.check("i18n _load_game restores saved language preference",
		String(locale_node.get("lang")) == "en"
		and g._engine._brew_btn.atr(g._engine._brew_btn.text) == "BREW")


	# В английском режиме доска контрактов держит все подписи, бафф-записки и штампы внутри бумаги без обрезки.
	var saved_buffs_i18n := g._contracts._active_buffs.duplicate(true)
	g._contracts._inject_vein_ready()
	g._contracts.grant_buff("brew_speed", 7200, 0.25, -1)
	g._contracts.grant_buff("spring_yield", 1800, 1.0, -1)
	ContractBoard.open(g)
	var cb_en := g.get_node_or_null("ContractBoard") as ContractBoard
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var cb_bounds_bad: Array = []
	if cb_en == null:
		cb_bounds_bad.append("no ContractBoard")
	else:
		for rn in [cb_en._mile_days, cb_en._mile_pts]:
			var rw := rn.get_node("Word") as Label
			if rw.position.x < 10.0 or rw.position.x + rw.size.x > rn.size.x - 10.0 or rw.get_visible_line_count() < rw.get_line_count():
				cb_bounds_bad.append("rank_note:" + rn.name)
		for bnote in cb_en._notes.get_children():
			cb_en._on_note_pressed(bnote)
			await g.get_tree().process_frame
			var tl := bnote.get_node("Time") as Label
			if tl.position.x < 10.0 or tl.position.x + tl.size.x > bnote.size.x - 10.0 or tl.get_visible_line_count() < tl.get_line_count():
				cb_bounds_bad.append("buff_note:" + bnote.name)
		for idx in cb_en._cards.size():
			var card_en := cb_en._cards[idx] as ContractCard
			if not card_en.visible:
				continue
			var paper_en := card_en.get_node("Hang/Paper") as Control
			var stamp_en := card_en.get_node("Hang/Stamp") as Control
			if stamp_en.position.x < 9.0:
				cb_bounds_bad.append("stamp_x:Card%d" % idx)
			for sub_p in ["Hang/Title", "Hang/Detail", "Hang/Reward"]:
				var sub_c := card_en.get_node(sub_p) as Control
				if sub_c.position.x < 15.0 or sub_c.position.x + sub_c.size.x > paper_en.size.x - 15.0:
					cb_bounds_bad.append("pad:%s:Card%d" % [sub_p, idx])
				if sub_c is Label and (sub_c as Label).get_visible_line_count() < (sub_c as Label).get_line_count():
					cb_bounds_bad.append("clip:%s:Card%d" % [sub_p, idx])
		cb_en._on_close()
		await g.get_tree().process_frame
	g._contracts._active_buffs = saved_buffs_i18n
	Selftest.check("i18n English ContractBoard keeps all text, notes and stamps inside paper bounds",
		cb_bounds_bad.is_empty())
	if not cb_bounds_bad.is_empty():
		print("[FAIL-DIAG] ContractBoard bounds: ", cb_bounds_bad)

	# Возвращаем язык в исходный ru для чистоты окружения следующих сюит.
	locale_node.call("set_lang", "ru")
	g._saves._save_game()
	await g.get_tree().process_frame
