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

	# Откат: не оставляем флаги и серверную коллекцию живому менеджеру.
	sm._milestones_claimed = {}
	sm._server_collection = {}
	sm._server_extras = []

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
