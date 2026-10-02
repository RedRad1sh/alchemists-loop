extends RefCounted
class_name SuiteSigilCards
# Аркан Сигилов: опции рендера, карточка «только круг», каталог и кнопка шапки.


## Мелкий рецепт с зафиксированным сидом: карточка 96×96 рисуется быстро,
## а seed_override снимает зависимость от canonical_string.
static func _recipe(seed_value: int, result_id: String) -> SigilRecipe:
	var r := SigilRecipe.new()
	r.id = StringName("st_" + result_id)
	r.ingredients = PackedStringArray(["fire", "water"])
	r.result_type = &"object"
	r.result_id = StringName(result_id)
	r.rarity = &"common"
	r.display_name = "Пар"
	r.seed_override = seed_value
	return r


static func _small_options() -> Dictionary:
	return {
		"card_size": Vector2(96, 96), "render_scale": 1,
		"show_name": false, "show_frame": false,
		"fluid_enabled": false, "aura_enabled": false, "save_png": false,
	}


static func run(g: Game) -> void:
	# ---- SigilOptions.show_icon ----
	var on := SigilOptions.make({})
	var off := SigilOptions.make({"show_icon": false})
	Selftest.check("options show icon by default", on.show_icon)
	Selftest.check("options hide icon", not off.show_icon)
	Selftest.check("icon flag roundtrips", not SigilOptions.make(off.to_dict()).show_icon)
	Selftest.check("icon flag in dict", off.to_dict().get("show_icon", true) == false)
	Selftest.check("icon flag changes cache salt", on.cache_salt() != off.cache_salt())

	# ---- Карточка «только круг» ----
	var recipe := _recipe(987654321, "steam")
	var full := SigilCard.new()
	g.add_child(full)
	full.setup(recipe, SigilOptions.make(_small_options()))

	var no_icon_opts := _small_options()
	no_icon_opts["show_icon"] = false
	var circle_only := SigilCard.new()
	g.add_child(circle_only)
	circle_only.setup(recipe, SigilOptions.make(no_icon_opts))

	Selftest.check("full card shows icon", full.icon != null and full.icon.visible)
	Selftest.check("circle-only card hides icon", not circle_only.icon.visible)
	Selftest.check("circle-only card keeps circle",
		circle_only.circle != null and circle_only.circle.visible)
	Selftest.check("circle-only card keeps frame slot", circle_only.frame != null)
	Selftest.check("circle-only card keeps same seed", circle_only.seed_value == full.seed_value)

	full.queue_free()
	circle_only.queue_free()

	# ---- Транспорт: новые сигил-запросы существуют и разводят сигналы ----
	Selftest.check("net has catalog request", Net.has_method("sigil_catalog"))
	Selftest.check("net has collection request", Net.has_method("sigil_collection"))
	Selftest.check("net has catalog signal", Net.has_signal("sigil_catalog_result"))
	Selftest.check("net has collection signal", Net.has_signal("sigil_collection_result"))

	# ---- Каталог в SigilManager ----
	var sm := g._sigil
	sm.set_catalog([
		{"id": "steam", "set": "water", "rarity": "rare", "ether_cost": 150,
			"recipe": [{"item_id": "fire", "qty": 5}, {"item_id": "water", "qty": 5}],
			"process": "sublimatio", "stage": "albedo", "fallback_name": "Пар",
			"object_type": "object", "seed": 123456789},
	], [{"id": "water", "title": "Стихия Воды", "card_ids": ["steam"]}], "unit-v1")
	Selftest.check("catalog stores card", int(sm.card("steam").get("seed", 0)) == 123456789)
	Selftest.check("catalog misses unknown", sm.card("nope").is_empty())
	Selftest.check("catalog size", sm.catalog_size() == 1)
	Selftest.check("catalog version", sm.catalog_version() == "unit-v1")
	Selftest.check("catalog sets", sm.catalog_sets().size() == 1)

	# ---- Рецепт карты каталога ----
	var card_recipe := sm.make_card_recipe(sm.card("steam"))
	Selftest.check("card recipe uses catalog seed", card_recipe.compute_seed() == 123456789)
	Selftest.check("card recipe object type", card_recipe.result_type == &"object")
	Selftest.check("card recipe ingredients",
		Array(card_recipe.ingredients) == ["fire", "water"])
	Selftest.check("card recipe display name", card_recipe.display_name == "Пар")
	Selftest.check("card recipe keeps set",
		str(card_recipe.properties.get("set", "")) == "water")
	Selftest.check("card recipe keeps stage string",
		str(card_recipe.properties.get("stage", "")) == "albedo")

	# Каталог НЕ солится: картинка карты общая для всех игроков — на этом
	# держатся коллекция и витрина.
	sm.set_player_salt("unit-test-salt")
	Selftest.check("card recipe ignores player salt",
		sm.make_card_recipe(sm.card("steam")).compute_seed() == 123456789)

	# ---- Маршрутизация крафта ----
	var craft := {"id": "d_0", "card_id": "steam", "rarity": "rare",
		"ingredients": [{"item_id": "fire", "qty": 5}], "ether_cost": 150,
		"llm_name": "", "is_chromatic": false}
	Selftest.check("craft routes to catalog card",
		sm.card_recipe_for(craft).compute_seed() == 123456789)
	Selftest.check("unknown card falls back to craft recipe",
		sm.card_recipe_for({"id": "d_9", "card_id": "ghost", "rarity": "common",
			"ingredients": [{"item_id": "fire", "qty": 1}], "llm_name": "",
			"is_chromatic": false}).id == &"d_9")

	var chroma := {"id": "d_1", "card_id": "", "rarity": "chromatic",
		"ingredients": [{"item_id": "fire", "qty": 30}], "ether_cost": 1200,
		"llm_name": "Хроматический сигил", "is_chromatic": true}
	var chroma_recipe := sm.card_recipe_for(chroma)
	Selftest.check("chromatic keeps salted path", chroma_recipe.id == &"d_1")
	Selftest.check("chromatic keeps ingredients", Array(chroma_recipe.ingredients) == ["fire"])
	Selftest.check("chromatic gets salted seed", chroma_recipe.seed_override >= 0)

	# ---- Превью: только круг ----
	var pv := sm.preview_options()
	Selftest.check("preview hides icon", not pv.show_icon)
	Selftest.check("preview hides name", not pv.show_name)
	Selftest.check("preview hides frame", not pv.show_frame)
	Selftest.check("preview is square", pv.card_size
		== Vector2i(SigilManager.PREVIEW_SIZE, SigilManager.PREVIEW_SIZE))

	# ---- Коллекция с сервера ----
	sm._on_collection_result({"ok": true,
		"cards": {"steam": {"copies": 2, "first_at": "2026-01-01T00:00:00"}},
		"extras": [{"craft_id": "x", "rarity": "chromatic", "llm_name": "",
			"crafted_at": "2026-01-02T00:00:00"}]})
	Selftest.check("collection copies", sm.copies_of("steam") == 2)
	Selftest.check("collection has card", sm.has_collected("steam"))
	Selftest.check("collection unknown is zero", sm.copies_of("nope") == 0)
	Selftest.check("collection extras kept", sm.server_extras().size() == 1)
	var snap := sm.server_collection()
	snap["steam"] = {"copies": 99, "first_at": ""}
	Selftest.check("collection snapshot is a copy", sm.copies_of("steam") == 2)

	sm._on_collection_result({"ok": false, "error": "missing_device_id"})
	Selftest.check("failed collection keeps state", sm.copies_of("steam") == 2)

	# ---- Откат: сьют не оставляет юнит-каталог в живом менеджере ----
	sm.set_player_salt(OS.get_unique_id())
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	Selftest.check("suite cleared catalog", sm.catalog_size() == 0)

	# ---- Проводка: сигналы каталога/коллекции доходят до менеджера ----
	Selftest.check("catalog result wired",
		Net.sigil_catalog_result.get_connections().size() >= 1)
	Selftest.check("collection result wired",
		Net.sigil_collection_result.get_connections().size() >= 1)
	Selftest.check("game awaits catalog", g.has_method("_await_catalog"))

	# ---- Кнопка Аркана Сигилов: иконка-таро вместо глифа ----
	var btn := g._sigil_header_btn
	Selftest.check("sigil header button exists", btn != null)
	if btn != null:
		Selftest.check("sigil header has no text glyph", btn.text == "")
		Selftest.check("sigil header is 46x46",
			btn.custom_minimum_size == Vector2(46, 46))
		var tarot := btn.get_node_or_null("Tarot")
		Selftest.check("sigil header draws tarot", tarot is TarotIcon)
		if tarot != null:
			Selftest.check("tarot ignores mouse",
				tarot.mouse_filter == Control.MOUSE_FILTER_IGNORE)
			Selftest.check("tarot fills button",
				tarot.offset_left == 8.0 and tarot.offset_top == 6.0
				and tarot.offset_right == -8.0 and tarot.offset_bottom == -6.0)
	# Иконка обязана рисоваться даже в вырожденном размере (нулевой Control).
	var tiny := TarotIcon.new()
	g.add_child(tiny)
	tiny.size = Vector2(1, 1)
	tiny.queue_redraw()
	Selftest.check("tarot survives tiny size", tiny.size == Vector2(1, 1))
	tiny.queue_free()

	# ---- Task 3: майлстоуны — серверные флаги наград и транспорт клейма ----
	# Ответ коллекции несёт milestones (set -> тиры); отсутствие ключа — не
	# ошибка, а «сервер ничего не подтвердил»: полное замещение состояния.
	# Снапшот user-кэша коллекции: клейм и roundtrip ниже пишут его на диск;
	# restore в конце блока держит прогон герметичным.
	var sb3_coll_snap := _sb5_file_text(SigilManager.COLLECTION_FILE)
	sm._on_collection_result({"ok": true, "cards": {}, "extras": [],
		"milestones": {"fire": [3, 6]}})
	var sb3_from_collection := sm.claimed_tiers("fire") == [3, 6]
	sm._on_collection_result({"ok": true, "cards": {}, "extras": []})
	Selftest.check("sb3 milestone flags from collection result",
		sb3_from_collection and sm.claimed_tiers("fire").is_empty())

	# Клейм: ok && claimed — единственная ветка, меняющая флаги.
	var sb3_changed := [0]
	var sb3_changed_cb := func() -> void: sb3_changed[0] += 1
	sm.collection_changed.connect(sb3_changed_cb)
	sm._on_milestone_result({"ok": true, "claimed": true, "set": "fire", "tier": 6})
	sm.collection_changed.disconnect(sb3_changed_cb)
	var sb3_disk := false
	var sb3_file := FileAccess.open(SigilManager.COLLECTION_FILE, FileAccess.READ)
	if sb3_file != null:
		var sb3_parsed = JSON.parse_string(sb3_file.get_as_text())
		sb3_file.close()
		if sb3_parsed is Dictionary:
			var sb3_ms = (sb3_parsed as Dictionary).get("milestones", null)
			var sb3_tiers = (sb3_ms as Dictionary).get("fire", []) if sb3_ms is Dictionary else []
			# JSON отдаёт числа float'ами, а Array.has/== в Godot 4 сравнивает
			# по хэшу: [6.0].has(6) — false. Сравниваем численно.
			if sb3_tiers is Array:
				for t in (sb3_tiers as Array):
					sb3_disk = sb3_disk or int(t) == 6
	Selftest.check("sb3 claim ok merges flag and emits",
		sm.claimed_tiers("fire").has(6) and sb3_changed[0] == 1 and sb3_disk)

	# Офлайн-форма и серверная ошибка флаги не трогают и не эмитят.
	var sb3_before: Array = sm.claimed_tiers("fire")
	sm.collection_changed.connect(sb3_changed_cb)
	sm._on_milestone_result({"ok": false, "offline": true})
	sm._on_milestone_result({"ok": false, "error": "not_enough_cards"})
	sm.collection_changed.disconnect(sb3_changed_cb)
	Selftest.check("sb3 claim offline form changes nothing",
		sb3_changed[0] == 1 and sm.claimed_tiers("fire") == sb3_before)

	# Флаги переживают roundtrip кэша коллекции.
	var sb3_snapshot := sm.claimed_tiers("fire")
	sm._save_collection()
	sm._milestones_claimed = {}
	sm._load_collection()
	Selftest.check("sb3 flags survive cache roundtrip",
		not sb3_snapshot.is_empty() and sm.claimed_tiers("fire") == sb3_snapshot)

	# Откат: не оставляем флаги и серверную коллекцию живому менеджеру и
	# возвращаем user-кэш коллекции к состоянию до блока.
	sm._milestones_claimed = {}
	sm._server_collection = {}
	sm._server_extras = []
	_sb5_restore_file(SigilManager.COLLECTION_FILE, sb3_coll_snap)

	# ---- Task 4: эффекты наград — кап эфира и скидка крафта ----
	# Кап: +40 за каждый комплект, у которого сервер подтвердил тир 3.
	sm._on_collection_result({"ok": true, "cards": {}, "extras": [],
		"milestones": {"fire": [3], "water": [3, 6]}})
	var sb4_cap := sm.milestone_cap_bonus() == 80
	sm._on_collection_result({"ok": true, "cards": {}, "extras": [],
		"milestones": {"fire": [3], "water": [3, 6], "air": [3]}})
	sb4_cap = sb4_cap and sm.milestone_cap_bonus() == 120
	Selftest.check("sb4 cap bonus 40 per claimed set", sb4_cap)

	# Скидка: −10% эфира крафтов комплекта с тиром 6; хроматика (set == "")
	# всегда платит полную цену; возврат при отказе — по той же скидочной цене.
	sm._on_collection_result({"ok": true, "cards": {}, "extras": [],
		"milestones": {"fire": [6]}})
	var sb4_craft := {"set": "fire", "ether_cost": 400}
	var sb4_cost := sm.craft_ether_cost(sb4_craft) == 360
	# Возврат при отказе крафта идёт через craft_ether_cost, не по сырой цене:
	# живой хендлер main.gd берёт крафт из _sigil_pending_craft (сейв уходит в ST).
	var sb4_ether := g._engine.ether
	g._sigil_pending_craft = {"id": "d_r", "set": "fire", "ether_cost": 400,
		"ingredients": []}
	g._on_sigil_craft_failed("offline")
	sb4_cost = sb4_cost and g._engine.ether == sb4_ether + 360 \
		and g._sigil_pending_craft.is_empty()
	g._engine.ether = sb4_ether
	# Гейт открытия модалки — по той же скидочной цене: при эфире 380 (между
	# 360 и 400) открытие должно состояться; сырая цена молча отсекла бы.
	g._engine.ether = 380
	g._open_sigil_craft({"id": "d_o", "set": "fire", "ether_cost": 400,
		"ingredients": []})
	sb4_cost = sb4_cost and g._sigil_craft_screen != null
	g._close_sigil_craft_screen()
	g._engine.ether = sb4_ether
	sm._on_collection_result({"ok": true, "cards": {}, "extras": [],
		"milestones": {"fire": [3]}})
	sb4_cost = sb4_cost and sm.craft_ether_cost(sb4_craft) == 400
	sb4_cost = sb4_cost and sm.craft_ether_cost({"set": "", "ether_cost": 1200}) == 1200
	Selftest.check("sb4 craft cost discount for claimed set", sb4_cost)

	# Откат: не оставляем флаги живому менеджеру (сидирование без записи на диск).
	sm._on_collection_result({"ok": true, "cards": {}, "extras": []})

	# ---- Task 5: гигиена каталога — settled-флаги (M1), version-гейт (M2),
	# guard кэша превью (D10) ----
	# Снапшоты user-кэшей: ok-ответы в проверках ниже пишут их на диск; restore
	# в конце блока держит прогон герметичным (новых записей не оставляем).
	var sb5_cat_snap := _sb5_file_text(SigilManager.CATALOG_FILE)
	var sb5_daily_snap := _sb5_file_text(SigilManager.DAILY_CACHE_FILE)
	var sb5_day0 := sm._daily_day
	var sb5_crafts0: Array = sm._daily_crafts.duplicate(true)
	var sb5_preview0 := sm._preview_cache.duplicate()

	# Офлайн-ответ в ST приходит синхронно внутри request_*, поэтому на время
	# «запроса в полёте» хендлер отключаем: между отправкой и офлайн-ответом
	# флаг обязан стоять false, а офлайн-ответ должен гасить его в true.
	Net.sigil_catalog_result.disconnect(sm._on_catalog_result)
	sm.request_catalog()
	var sb5_cat_pending := not sm.catalog_settled()
	var sb5_daily_pending := not sm.daily_settled()
	Net.sigil_catalog_result.connect(sm._on_catalog_result)
	sm._on_catalog_result({"ok": false, "offline": true})
	sm._on_daily_result({"ok": false, "offline": true})
	Selftest.check("sb5 catalog settled flips on offline result",
		sb5_cat_pending and sb5_daily_pending
		and sm.catalog_settled() and sm.daily_settled())

	# M2: ok-ответ помечает каталог докачанным в этой сессии; повторный
	# request_catalog — no-op и НЕ сбрасывает settled в false (отправки не было).
	var sb5_card := {"id": "sb5", "set": "fire", "rarity": "common",
		"ether_cost": 10, "recipe": [{"item_id": "fire", "qty": 5}],
		"process": "calcinatio", "stage": "nigredo", "fallback_name": "Проба",
		"object_type": "object", "seed": 42}
	sm._on_catalog_result({"ok": true, "cards": [sb5_card], "sets": [],
		"version": "st-v1"})
	var sb5_settled_after_ok := sm.catalog_settled()
	Net.sigil_catalog_result.disconnect(sm._on_catalog_result)
	sm.request_catalog()
	var sb5_skipped := sm.catalog_settled()
	Net.sigil_catalog_result.connect(sm._on_catalog_result)
	Selftest.check("sb5 request catalog skips when fetched this session",
		sb5_settled_after_ok and sb5_skipped)

	# Ежедневный ответ с другой версией каталога перевыпускает докачку (спека §1):
	# fetched_session гасится, request_catalog реально уходит, settled — false.
	sm.set_catalog([sb5_card], [], "aaaa")
	Net.sigil_catalog_result.disconnect(sm._on_catalog_result)
	sm._on_daily_result({"ok": true, "catalog_version": "bbbb", "day": "st-day",
		"crafts": []})
	var sb5_refetched := not sm.catalog_settled()
	Net.sigil_catalog_result.connect(sm._on_catalog_result)
	Selftest.check("sb5 daily version mismatch refetches", sb5_refetched)

	# D10: card_id, отсутствующий в локальном каталоге, не становится ключом
	# кэша превью — солёный fallback кэшируется под id крафта. Рендер в headless
	# не зовём: PNG в кэш рендера кладём сами, export_cached вернёт файл без
	# единого кадра.
	var sb5_craft := {"id": "x1", "card_id": "no_such_card", "rarity": "common",
		"ingredients": [{"item_id": "fire", "qty": 5}], "llm_name": "",
		"is_chromatic": false}
	var sb5_path := sm._svc.cache_path(sm.card_recipe_for(sb5_craft),
		sm.preview_options())
	var sb5_blank := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var sb5_seeded := sb5_blank.save_png(sb5_path) == OK \
		and FileAccess.file_exists(sb5_path)
	var sb5_tex: ImageTexture = null
	if sb5_seeded:
		sb5_tex = await sm.preview_texture(sb5_craft)
	Selftest.check("sb5 preview key avoids salted fallback for unknown card",
		sb5_seeded and sb5_tex != null and sm._preview_cache.has("x1")
		and not sm._preview_cache.has("no_such_card"))

	# Откат: юнит-каталог, флаги и user-кэши — в состояние до блока. Сидированный
	# PNG превью — единственная запись блока на диск вне двух JSON-кэшей.
	if sb5_seeded:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sb5_path))
	sm.set_catalog([], [], "")
	sm._catalog_settled = false
	sm._catalog_fetched_session = false
	sm._daily_settled = false
	sm._daily_day = sb5_day0
	sm._daily_crafts = sb5_crafts0
	sm._preview_cache = sb5_preview0
	_sb5_restore_file(SigilManager.CATALOG_FILE, sb5_cat_snap)
	_sb5_restore_file(SigilManager.DAILY_CACHE_FILE, sb5_daily_snap)

	# ---- Task 6: вкладки модалки, сетка коллекции, полноэкранный просмотр ----
	# Сид — как в демо-харнесе: каталог + коллекция через _on_collection_result.
	# Рендер в headless не зовём: мини-арты ячеек читаются из сеяных PNG кэша
	# рендера (приём sb5), полный арт фуллскрина — из сеяного дискового кэша карты.
	var sb6_clay := {"id": "clay", "set": "earth", "rarity": "common", "ether_cost": 50,
		"recipe": [{"item_id": "clay", "qty": 12}, {"item_id": "water", "qty": 20},
			{"item_id": "sand", "qty": 8}],
		"process": "осадок и прессовка", "stage": "nigredo", "fallback_name": "Глина",
		"object_type": "object", "seed": 90210}
	var sb6_metal := {"id": "metal", "set": "earth", "rarity": "epic", "ether_cost": 400,
		"recipe": [{"item_id": "metal", "qty": 30}, {"item_id": "fire", "qty": 45},
			{"item_id": "ice", "qty": 25}, {"item_id": "spark", "qty": 18}],
		"process": "плавка и закалка", "stage": "albedo", "fallback_name": "Металл",
		"object_type": "relic", "seed": 90211}
	sm.set_catalog([sb6_clay, sb6_metal],
		[{"id": "earth", "title": "Стихия Земли", "card_ids": ["clay", "metal"]}], "unit-t6")
	sm._on_collection_result({"ok": true,
		"cards": {"clay": {"copies": 2, "first_at": "2026-09-28T10:00:00"},
			"metal": {"copies": 1, "first_at": "2026-09-30T18:30:00"}},
		"extras": [{"craft_id": "demo_chroma", "rarity": "chromatic",
			"llm_name": "Хроматический сигил", "crafted_at": "2026-10-01T09:00:00"}],
		"milestones": {}})
	# Daily-состояние менеджера обнуляем: вкладка крафтов в сьюте обязана уйти
	# в офлайн-ветку синхронно, а не строить строки из прод-кэша ежедневки.
	var sb6_day0 := sm._daily_day
	var sb6_crafts0: Array = sm._daily_crafts.duplicate(true)
	var sb6_preview0 := sm._preview_cache.duplicate()
	var sb6_cat_settled0 := sm.catalog_settled()
	var sb6_daily_settled0 := sm.daily_settled()
	sm._daily_day = ""
	sm._daily_crafts = []
	var sb6_blank := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var sb6_render_paths: Array = []
	for sb6_cid in ["clay", "metal"]:
		var sb6_p := sm._svc.cache_path(sm.card_recipe_for({"card_id": sb6_cid}),
			sm.preview_options())
		if sb6_blank.save_png(sb6_p) == OK:
			sb6_render_paths.append(sb6_p)
	var sb6_disk_path := sm._cached_path("clay")
	var sb6_disk_snap := _sb5_file_text(sb6_disk_path)
	sm._save_cached_image("clay", sb6_blank)

	g._open_sigil_modal("crafts")
	var sb6_bar := g._sigil_coll.find_child("SigilTabBar", true, false) as HBoxContainer
	var sb6_tabs := 0
	if sb6_bar != null:
		for c in sb6_bar.get_children():
			if c is Button:
				sb6_tabs += 1
	var sb6_old := g._sigil_tab_content.get_child(0)
	g._sigil_show_tab("collection")
	var sb6_moved := sb6_old.is_queued_for_deletion() and g._sigil_tab == "collection"
	Selftest.check("sb6 modal builds three tabs",
		g._sigil_coll != null and sb6_tabs == 3 and g._sigil_tab_content != null
		and sb6_moved)

	var sb6_grid := g._sigil_tab_content.find_child("SigilCollGrid", true, false) as GridContainer
	var sb6_badge := false
	if sb6_grid != null:
		for l in sb6_grid.find_children("*", "Label", true, false):
			if (l as Label).text == "×2":
				sb6_badge = true
	Selftest.check("sb6 collection grid cells match collection",
		sb6_grid != null and sb6_grid.get_child_count() == 2 and sb6_badge)

	var sb6_chroma := g._sigil_tab_content.find_child("SigilChromaSection", true, false)
	var sb6_sep := false
	if sb6_chroma != null and sb6_grid != null:
		var sb6_ct := false
		for l in sb6_chroma.find_children("*", "Label", true, false):
			if (l as Label).text == "ХРОМАТИКА":
				sb6_ct = true
		var sb6_cgrids := sb6_chroma.find_children("*", "GridContainer", true, false)
		sb6_sep = sb6_ct and sb6_cgrids.size() == 1 \
			and (sb6_cgrids[0] as GridContainer).get_child_count() == 1 \
			and not sb6_grid.is_ancestor_of(sb6_chroma)
	Selftest.check("sb6 chromatic section separate", sb6_sep)

	var sb6_entry: Dictionary = g._sigil_catalog_entry("clay",
		{"copies": 2, "first_at": "2026-09-28T10:00:00"})
	g._open_sigil_fullscreen(sb6_entry)
	var sb6_z := 0
	var sb6_texts := ""
	if g._sigil_fullscreen != null:
		sb6_z = int(g._sigil_fullscreen.z_index)
		for l in g._sigil_fullscreen.find_children("*", "Label", true, false):
			sb6_texts += (l as Label).text + "\n"
	Selftest.check("sb6 fullscreen shows required fields",
		g._sigil_fullscreen != null and sb6_z >= 20
		and sb6_texts.contains("Глина") and sb6_texts.contains("ОБЫЧНЫЙ")
		and sb6_texts.contains("Стихия Земли") and sb6_texts.contains("28.09.2026")
		and sb6_texts.contains("×2"))

	var sb6_fs := g._sigil_fullscreen
	var sb6_closed := false
	if sb6_fs != null:
		var sb6_close := sb6_fs.find_child("SigilFsClose", true, false) as Button
		if sb6_close != null:
			sb6_close.pressed.emit()
		sb6_closed = g._sigil_fullscreen == null and sb6_fs.is_queued_for_deletion()
	Selftest.check("sb6 fullscreen closes on close button", sb6_closed)

	g._close_sigil_collection()
	# Откат: сиды, кэши и daily-состояние — в состояние до блока.
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	sm._daily_day = sb6_day0
	sm._daily_crafts = sb6_crafts0
	sm._preview_cache = sb6_preview0
	sm._catalog_settled = sb6_cat_settled0
	sm._daily_settled = sb6_daily_settled0
	for sb6_p in sb6_render_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sb6_p))
	_sb5_restore_file(sb6_disk_path, sb6_disk_snap)

	# ---- Task 7a: вкладка «Комплекты» — панели сетов, точки майлстоунов и
	# клейм; экран сета с силуэтами — Task 7b. Сид повторяет расширенный
	# демо-харнес: earth-каталог из 8 карт, наборы четырёх стихий (20+ имён
	# добивки из CATEGORY_OF), коллекция из 7 карт земля и milestone {earth: [3]}.
	# Рендер в headless не зовём: проверяется каркас вкладки и состояния точек.
	var sb7_earth_ids: Array = ["earth", "stone", "clay", "brick", "sand",
		"mountain", "mud", "metal", "glass", "obsidian", "ash", "gold",
		"beast", "person", "seed", "grass", "mushroom", "tool", "tree",
		"crystal", "forest", "wood", "flower", "desert", "boat"]
	var sb7_defs := [["clay", "common", "Глина", 50, 90210], ["stone", "common",
		"Камень", 50, 90213], ["sand", "common", "Песок", 50, 90214],
		["brick", "rare", "Кирпич", 150, 90215], ["glass", "rare", "Стекло",
		150, 90216], ["metal", "epic", "Металл", 400, 90211],
		["gold", "epic", "Золото", 400, 90217], ["mountain", "legendary",
		"Гора", 800, 90212]]
	var sb7_cards: Array = []
	for sb7_d in sb7_defs:
		sb7_cards.append({"id": sb7_d[0], "set": "earth", "rarity": sb7_d[1],
			"ether_cost": sb7_d[3],
			"recipe": [{"item_id": "fire", "qty": 10},
				{"item_id": "water", "qty": 12}, {"item_id": "earth", "qty": 14}],
			"process": "calcinatio", "stage": "nigredo",
			"fallback_name": sb7_d[2], "object_type": "object", "seed": sb7_d[4]})
	var sb7_sets := [{"id": "fire", "title": "Стихия Огня", "card_ids": []},
		{"id": "water", "title": "Стихия Воды", "card_ids": []},
		{"id": "air", "title": "Стихия Воздуха", "card_ids": []},
		{"id": "earth", "title": "Стихия Земли", "card_ids": sb7_earth_ids}]
	var sb7_coll := func(cids: Array) -> Dictionary:
		var out: Dictionary = {}
		for sb7_c in cids:
			out[str(sb7_c)] = {"copies": 1, "first_at": "2026-09-30T18:00:00"}
		return out

	# ---- sb7: четыре панели в порядке каталога, титулы и прогресс ----
	sm.set_catalog(sb7_cards, sb7_sets, "unit-t7")
	sm._on_collection_result({"ok": true, "cards": sb7_coll.call(["clay", "metal",
		"mountain", "stone", "sand", "brick", "glass"]), "extras": [],
		"milestones": {}})
	g._open_sigil_modal("sets")
	# Имена панелей/точек уникальны по сету/тиру (add_child переименовывает
	# одинаковые имена соседей), поэтому поиск — по wildcard SigilSetPanel*/SigilDot*.
	var sb7_panels := g._sigil_tab_content.find_children("SigilSetPanel*",
		"PanelContainer", true, false)
	var sb7_ids: Array = []
	for sb7_p in sb7_panels:
		sb7_ids.append(str((sb7_p as Control).get_meta("set_id", "")))
	var sb7_titles := {}
	var sb7_counts := {}
	for sb7_p in sb7_panels:
		var sb7_t := (sb7_p as Control).find_child("SigilSetTitle", true, false) as Label
		var sb7_c := (sb7_p as Control).find_child("SigilSetCount", true, false) as Label
		sb7_titles[str((sb7_p as Control).get_meta("set_id", ""))] = \
			sb7_t.text if sb7_t != null else ""
		sb7_counts[str((sb7_p as Control).get_meta("set_id", ""))] = \
			sb7_c.text if sb7_c != null else ""
	# Тип явный: выражения с Dictionary.get(...) верят Variant, инференс `:=` их не тянет.
	var sb7_panels_ok: bool = sb7_panels.size() == 4 and sb7_ids == ["fire", "water",
		"air", "earth"] and sb7_titles.get("fire", "") == "Стихия Огня" \
		and sb7_titles.get("water", "") == "Стихия Воды" \
		and sb7_titles.get("air", "") == "Стихия Воздуха" \
		and sb7_titles.get("earth", "") == "Стихия Земли" \
		and sb7_counts.get("earth", "") == "7/25" and sb7_counts.get("fire", "") == "0/25"
	Selftest.check("sb7 sets tab builds four panels in catalog order", sb7_panels_ok)
	g._close_sigil_collection()

	# ---- сид 2: 6 собранных earth + milestone {earth: [3]} --- точки ---
	sm._on_collection_result({"ok": true, "cards": sb7_coll.call(["clay", "metal",
		"mountain", "stone", "sand", "brick"]), "extras": [],
		"milestones": {"earth": [3]}})
	g._open_sigil_modal("sets")
	var sb7_dots: Dictionary = {}
	for sb7_p in g._sigil_tab_content.find_children("SigilSetPanel*",
			"PanelContainer", true, false):
		if str((sb7_p as Control).get_meta("set_id", "")) == "earth":
			for sb7_d in (sb7_p as Control).find_children("SigilDot*", "Button",
					true, false):
				sb7_dots[int((sb7_d as Button).get_meta("tier", 0))] = sb7_d
	var sb7_states := {}
	for sb7_t in [3, 6, 13, 25]:
		if sb7_dots.has(sb7_t):
			sb7_states[sb7_t] = str((sb7_dots[sb7_t] as Button).get_meta("state", ""))
	var sb7_dot6: Button = sb7_dots.get(6, null)
	var sb7_claim_list := [0]
	var sb7_claim_cb := func(_r: Dictionary) -> void: sb7_claim_list[0] += 1
	Net.sigil_milestone_result.connect(sb7_claim_cb)
	if sb7_dot6 != null and not sb7_dot6.disabled:
		sb7_dot6.pressed.emit()
	Net.sigil_milestone_result.disconnect(sb7_claim_cb)
	var sb7_dots_ok: bool = sb7_states.get(3, "") == "claimed" \
		and sb7_states.get(6, "") == "claimable" \
		and sb7_states.get(13, "") == "locked" \
		and sb7_states.get(25, "") == "locked" \
		and sb7_dot6 != null and not sb7_dot6.disabled \
		and sb7_dots.has(3) and (sb7_dots[3] as Button).disabled \
		and sb7_dots.has(13) and (sb7_dots[13] as Button).disabled \
		and sb7_dots.has(25) and (sb7_dots[25] as Button).disabled \
		and sb7_claim_list[0] == 1 \
		and sm.claimed_tiers("earth") == [3]  # офлайн-клейм флаги не трогает
	Selftest.check("sb7 milestone dot states", sb7_dots_ok)
	g._close_sigil_collection()

	# ---- main-обработчик: попап награды + refresh; офлайн — ничего -----
	var sb7_collects := [0]
	var sb7_collect_cb := func(_r: Dictionary) -> void: sb7_collects[0] += 1
	Net.sigil_collection_result.connect(sb7_collect_cb)
	if g.has_method("_on_sigil_milestone_result"):
		g._on_sigil_milestone_result({"ok": true, "claimed": true, "set": "earth",
			"tier": 6})
	Net.sigil_collection_result.disconnect(sb7_collect_cb)
	var sb7_popup := g._sigil_claim_layer
	var sb7_popup_text := ""
	var sb7_popup_z := 0
	if sb7_popup != null:
		sb7_popup_z = int(sb7_popup.z_index)
		for l in sb7_popup.find_children("*", "Label", true, false):
			sb7_popup_text += (l as Label).text + "\n"
	# Закрытие кнопкой OK и офлайн-форма (ok=false) — в той же проверке: обе
	# соседние ветки одного хендлера, отдельными чеками их не плодим.
	var sb7_ok_btn: Button = null
	if sb7_popup != null:
		sb7_ok_btn = sb7_popup.find_child("SigilClaimOk", true, false) as Button
	if sb7_ok_btn != null:
		sb7_ok_btn.pressed.emit()
	var sb7_popup_closed := g._sigil_claim_layer == null and sb7_popup != null \
		and sb7_popup.is_queued_for_deletion()
	if g.has_method("_on_sigil_milestone_result"):
		g._on_sigil_milestone_result({"ok": false, "offline": true})
	var sb7_no_offline_popup := g._sigil_claim_layer == null and sb7_popup_closed
	var sb7_popup_ok: bool = sb7_popup != null and sb7_popup_z >= 20 \
		and sb7_popup_text.contains("Награда получена") \
		and sb7_popup_text.contains("−10% эфира крафтов комплекта") \
		and sb7_collects[0] == 1 \
		and sb7_popup_closed and sb7_no_offline_popup
	Selftest.check("sb7 milestone ok popup and refresh", sb7_popup_ok)

	# Откат: сиды и флаги — в состояние до блока (дисковых записей нет: клейм в
	# офлайне ушёл в очередь Net и был синхронно слит offline-ответом).
	g._close_sigil_collection()
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	sm._milestones_claimed = {}

	# ---- Task 7b: экран комплекта — сетка 25 карт сета: собранные — мини-арт
	# из сеяного превью-кэша рендера (приём sb6: рендер в headless не зовём),
	# несобранные (и неизвестные каталогу) — силуэт: контур круга + «???» БЕЗ
	# имени и без арта; тап по собранной карте открывает фуллскрин. Сид — как
	# в sb7: 8 earth-карт в каталоге, 25 card_ids, коллекция из 7 карт земли.
	# Сид каталога/коллекции — как в sb7: 8 earth-карт, 25 card_ids, 7 собранных.
	sm.set_catalog(sb7_cards, sb7_sets, "unit-t7")
	sm._on_collection_result({"ok": true, "cards": sb7_coll.call(["clay", "metal",
		"mountain", "stone", "sand", "brick", "glass"]), "extras": [],
		"milestones": {}})
	# Сидированные PNG превью-кэша считаем по карточным рецептам — каталог уже
	# стоит, иначе paths разошлись бы с боевым card_recipe_for и рендер в
	# headless повис бы на frame_post_draw (приём sb6: рендер не зовём).
	var sb7g_blank := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var sb7g_render_paths: Array = []
	for sb7g_cid in ["clay", "metal", "mountain", "stone", "sand", "brick", "glass"]:
		var sb7g_p := sm._svc.cache_path(sm.card_recipe_for({"card_id": sb7g_cid}),
			sm.preview_options())
		if sb7g_blank.save_png(sb7g_p) == OK:
			sb7g_render_paths.append(sb7g_p)
	# Полный арт фуллскрина при тапе читается из дискового кэша карты (не рендер).
	var sb7g_disk_path := sm._cached_path("clay")
	var sb7g_disk_snap := _sb5_file_text(sb7g_disk_path)
	sm._save_cached_image("clay", sb7g_blank)
	var sb7g_preview0 := sm._preview_cache.duplicate()
	g._open_sigil_modal("sets")
	await g._open_sigil_set_screen("earth")
	await g.get_tree().process_frame
	var sb7g_screen := g._sigil_set_screen
	var sb7g_title := ""
	var sb7g_grid: GridContainer = null
	if sb7g_screen != null:
		var sb7g_t := sb7g_screen.find_child("SigilSetScreenTitle", true, false) as Label
		sb7g_title = sb7g_t.text if sb7g_t != null else ""
		sb7g_grid = sb7g_screen.find_child("SigilSetGrid", true, false) as GridContainer
	var sb7g_collected_map := {"clay": true, "metal": true, "mountain": true,
		"stone": true, "sand": true, "brick": true, "glass": true}
	var sb7g_cells_ok := true
	var sb7g_art := 0
	var sb7g_sil := 0
	if sb7g_grid != null:
		for sb7g_i in sb7g_grid.get_child_count():
			var sb7g_cell := sb7g_grid.get_child(sb7g_i) as Control
			var sb7g_cid := str(sb7g_cell.get_meta("card_id", ""))
			var sb7g_text := ""
			var sb7g_has_art := false
			for l in sb7g_cell.find_children("*", "Label", true, false):
				sb7g_text += (l as Label).text + "|"
			for t in sb7g_cell.find_children("*", "TextureRect", true, false):
				if (t as TextureRect).texture != null:
					sb7g_has_art = true
			if sb7g_collected_map.has(sb7g_cid):
				sb7g_art += 1
				sb7g_cells_ok = sb7g_cells_ok and sb7g_has_art \
					and not sb7g_text.contains("???")
			else:
				sb7g_sil += 1
				sb7g_cells_ok = sb7g_cells_ok and sb7g_text == "???|" \
					and not sb7g_has_art
	# Тап по собранной карте (clay) открывает полноэкранный просмотр карты.
	var sb7g_col_btn: Button = null
	if sb7g_grid != null and g._sigil_set_screen != null:
		sb7g_col_btn = g._sigil_set_screen.find_child("SigilSetCell_clay",
			true, false) as Button
	if sb7g_col_btn != null:
		sb7g_col_btn.pressed.emit()
	var sb7g_fs_z := 0
	if g._sigil_fullscreen != null:
		sb7g_fs_z = int(g._sigil_fullscreen.z_index)
	var sb7g_ok: bool = sb7g_screen != null \
		and sb7g_title == "Стихия Земли · 7/25" \
		and sb7g_grid != null and sb7g_grid.columns == 5 \
		and sb7g_grid.get_child_count() == 25 \
		and sb7g_art == 7 and sb7g_sil == 18 \
		and sb7g_cells_ok and g._sigil_fullscreen != null \
		and sb7g_fs_z >= 20
	Selftest.check("sb7 set screen silhouettes hide unknown", sb7g_ok)
	# Откат: слои, сиды и кэши — в состояние до блока; сидированные PNG превью —
	# единственная запись блока на диск (той же судьбой, что и в sb6).
	if g._sigil_fullscreen != null:
		g._close_sigil_fullscreen()
	if g._sigil_set_screen != null:
		g._close_sigil_set_screen()
	g._close_sigil_collection()
	sm._preview_cache = sb7g_preview0
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	sm._milestones_claimed = {}
	for sb7g_p in sb7g_render_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sb7g_p))
	_sb5_restore_file(sb7g_disk_path, sb7g_disk_snap)

	# ---- Task 8: достижения карточек. Сид — как sb7: каталог earth из 8 карт
	# с редкостями (common/rare/epic/legendary) и 25 card_ids сета; коллекция —
	# 2 карты (common + epic) + один хроматический extra. Сборка/клеймы только
	# прямым сетом стейта менеджера — дисковых записей блок не делает, поэтому
	# _ach_progress можно проверять напрямую (в selftest _ach_update — no-op, а
	# награды эфира тут не нужны).
	sm.set_catalog(sb7_cards, sb7_sets, "unit-t8")
	sm._on_collection_result({"ok": true, "cards": sb7_coll.call(["clay", "metal"]),
		"extras": [{"id": "chroma_t", "rarity": "chromatic", "llm_name": "Тест"}],
		"milestones": {}})
	var sb8_ach := func(kind: String, param: int) -> Dictionary:
		return {"id": "sb8_x", "title": "x", "kind": kind, "param": param, "ether": 0}
	var sb8_progress_ok: bool = g._progress_ui._ach_progress(sb8_ach.call("sigil_total", 1)) == 2 \
		and g._progress_ui._ach_progress(sb8_ach.call("sigil_first_rarity", 0)) == 1 \
		and g._progress_ui._ach_progress(sb8_ach.call("sigil_first_rarity", 1)) == 0 \
		and g._progress_ui._ach_progress(sb8_ach.call("sigil_first_rarity", 2)) == 1 \
		and g._progress_ui._ach_progress(sb8_ach.call("sigil_set_count", 13)) == 2 \
		and g._progress_ui._ach_progress(sb8_ach.call("sigil_sets_full", 1)) == 0 \
		and sm.has_rarity(4)
	Selftest.check("sb8 sigil achievement progress counts", sb8_progress_ok)

	# ---- сид 2: все 25 card_ids earth в _server_collection — комплект полон,
	# set_count достигает 25 (хроматика в сете не считается).
	sm._on_collection_result({"ok": true, "cards": sb7_coll.call(sb7_earth_ids),
		"extras": [], "milestones": {}})
	var sb8_full_ok: bool = g._progress_ui._ach_progress(sb8_ach.call("sigil_set_count", 13)) == 25 \
		and g._progress_ui._ach_progress(sb8_ach.call("sigil_sets_full", 1)) == 1
	Selftest.check("sb8 full set counts once", sb8_full_ok)

	# ---- проводка: collection_changed доходит до _ach_update (в selftest
	# _ach_update no-op, сигнал эмитим — наблюдаем коннект, не эффект).
	sm.collection_changed.emit()
	var sb8_target := g._progress_ui._ach_update
	var sb8_wired := false
	for sb8_c in sm.collection_changed.get_connections():
		if (sb8_c as Dictionary).get("callable", Callable()) == sb8_target:
			sb8_wired = true
	Selftest.check("sb8 collection change triggers ach update", sb8_wired)

	# ---- Task 5C: lore-блок в полноэкранном просмотре ----
	# Каталог с картой steam (валидные process/stage/seed) и chroma-extra.
	var sb9_steam := {"id": "steam", "set": "fire", "rarity": "common", "ether_cost": 50,
		"recipe": [{"item_id": "water", "qty": 10}, {"item_id": "fire", "qty": 10}],
		"process": "sublimatio", "stage": "albedo", "fallback_name": "Пар",
		"object_type": "object", "seed": 123456789}
	sm.set_catalog([sb9_steam], [{"id": "fire", "title": "Стихия Огня", "card_ids": ["steam"]}], "unit-t9")
	sm._on_collection_result({"ok": true, "cards": {"steam": {"copies": 1,
		"first_at": "2026-10-01T09:00:00"}}, "extras": [], "milestones": {}})
	var sb9_entry: Dictionary = g._sigil_catalog_entry("steam", {"copies": 1, "first_at": "2026-10-01T09:00:00"})
	g._open_sigil_fullscreen(sb9_entry)
	var sb9_lore_title := ""
	var sb9_lore_desc := ""
	var sb9_lore_warn := ""
	if g._sigil_fullscreen != null:
		for l in g._sigil_fullscreen.find_children("SigilLoreTitle", "Label", true, false):
			sb9_lore_title = str((l as Label).text)
		for l in g._sigil_fullscreen.find_children("SigilLoreDesc", "Label", true, false):
			sb9_lore_desc = str((l as Label).text)
		for l in g._sigil_fullscreen.find_children("SigilLoreWarn", "Label", true, false):
			sb9_lore_warn = str((l as Label).text)
	Selftest.check("sb_lore block renders for catalog card",
		not sb9_lore_title.is_empty() and not sb9_lore_desc.is_empty())
	g._close_sigil_fullscreen()
	# extras: карта вне каталога (card_id="") -> entry пустая; попытка открыть
	# фуллскрин не падает и не рисует lore (пустая entry -> early return).
	var sb9_chroma: Dictionary = g._sigil_catalog_entry("", {"copies": 1, "first_at": ""})
	var sb9_no_crash := sb9_chroma.is_empty() and g._sigil_fullscreen == null
	g._open_sigil_fullscreen(sb9_chroma)
	Selftest.check("sb_lore extras fullscreen no crash",
		sb9_no_crash and g._sigil_fullscreen == null)
	Selftest.check("sb_lore extras fullscreen empty block",
		g._sigil_fullscreen == null)
	# откатываем каталог
	g._close_sigil_collection()
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	sm._milestones_claimed = {}
	# Откат: сиды — в состояние до блока (дисковых записей нет).
	sm.set_catalog([], [], "")
	sm._server_collection = {}
	sm._server_extras = []
	sm._milestones_claimed = {}


## Текст user-файла для снапшота блока sb5: пустая строка = файла не было.
static func _sb5_file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


## Вернуть user-файл к снапшоту: пустой снимок означает «файла не было» — удаляем.
static func _sb5_restore_file(path: String, text: String) -> void:
	if text == "":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
