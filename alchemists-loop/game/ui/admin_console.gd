extends RefCounted
class_name AdminConsole
# Админ-консоль: toggle по ~ (тильда), парсинг команд из текстового ввода.
# Команды: add <element>, unlock <mode>, set ether <N>, reset day,
# clear inventory, force circle open (имя команды — легаси-грамматика; по-настоящему
# она сбрасывает дневные ключи контрактной доски: визит/очаг + эксперимент).

var _g: Game
var _dim: ColorRect
var _center: CenterContainer
var _input: LineEdit
var _log: RichTextLabel
var _visible := false

func _init(g: Game) -> void:
	_g = g
	_build_ui()

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.z_index = 50
	_dim.visible = false
	_g.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 51
	center.visible = false
	_g.add_child(center)
	_center = center

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	var panel_wrap := PanelContainer.new()
	panel_wrap.add_theme_stylebox_override("panel", style)
	panel_wrap.custom_minimum_size = Vector2(400, 300)
	center.add_child(panel_wrap)
	panel_wrap.add_child(vbox)

	var title := Label.new()
	title.text = "Admin Console"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 180)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log)

	_input = LineEdit.new()
	_input.placeholder_text = "command..."
	_input.clear_button_enabled = true
	_input.text_submitted.connect(_on_command)
	vbox.add_child(_input)

	var help := Label.new()
	help.text = "give all [N] | give layer <L> [N] | give <id> [N] | house all | house <id> | sfx play|set|file|rarity|reload|save | add <id> | unlock <mode> | set ether <N> | reset day | clear inventory | force circle open"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(help)

func toggle() -> void:
	if not OS.has_feature("editor"):
		return
	_visible = !_visible
	_dim.visible = _visible
	_center.visible = _visible
	if _visible:
		_input.grab_focus()
	else:
		_input.release_focus()

func is_visible() -> bool:
	return _visible

func close() -> void:
	_visible = false
	_dim.visible = false
	_center.visible = false
	_input.release_focus()

func _on_command(text: String) -> void:
	if not OS.has_feature("editor"):
		return
	var cmd := text.strip_edges().to_lower()
	_input.text = ""
	if cmd.is_empty():
		return
	_log_text("> " + text.strip_edges())
	var parts := cmd.split(" ", false)
	match parts[0]:
		"add":
			_cmd_add(parts)
		"give":
			_cmd_give(parts)
		"house":
			_cmd_house(parts)
		"unlock":
			_cmd_unlock(parts)
		"set":
			_cmd_set(parts)
		"reset":
			_cmd_reset(parts)
		"clear":
			_cmd_clear(parts)
		"force":
			_cmd_force(parts)
		"sigil":
			_cmd_sigil(parts)
		"sfx":
			_cmd_sfx(parts)
		"help":
			_log_text("Commands: give all [N] | give layer <L> [N] | give <id> [N], add <id>, unlock <mode>, set ether <N>, reset day, clear inventory, force circle open, sigil rotate|free <0|1|2>|chroma|ritual, sfx list|play <name>")
		_:
			_log_text("[color=red]Unknown command: %s[/color]" % parts[0])

## Звуковой debug: sfx list (все события конфига) / sfx play <event>.
func _cmd_sfx(parts: Array) -> void:
	if OS.has_feature("editor") == false:
		return
	var usage := "sfx list | play <event> [N] | rarity <редкость> | set <event[.N]> <key> <value> | file <путь> [дБ] [pitch] | reload | save | stop   (ключи: file volume_db pitch delay start_sec len_sec loop)"
	if parts.size() < 2:
		_log_text("[color=red]Usage: %s[/color]" % usage)
		return
	var sub: String = str(parts[1])
	match sub:
		"list":
			# По группам (ui, craft, ritual, reward, spirit), как папки в assets/audio.
			var groups := {}
			for k in Sfx._sound_cfg.keys():
				var g := str((Sfx._sound_cfg[k] as Dictionary).get("group", "other"))
				if not groups.has(g):
					groups[g] = []
				(groups[g] as Array).append(String(k))
			for g in groups.keys():
				_log_text("[b]%s[/b]: %s" % [str(g), ", ".join(groups[g])])
		"play":
			if parts.size() < 3:
				_log_text("[color=red]sfx play <event>[/color]")
				return
			var ev: String = str(parts[2])
			var variant := int(parts[3]) - 1 if parts.size() >= 4 else -1
			Sfx.play_event(ev, variant)
			_log_text("Playing event: %s  %s" % [ev, _sfx_summary(ev)])
		"reload":
			Sfx.reload_config()
			_log_text("sounds.json перечитан, кэш звуков сброшен (%d событий)" % Sfx._sound_cfg.size())
		"set":
			if parts.size() < 5:
				_log_text("[color=red]sfx set <event> <key> <value>[/color]")
				return
			var ev := str(parts[2])
			var key := str(parts[3])
			if not (key in ["file", "volume_db", "pitch", "delay", "start_sec", "len_sec", "loop"]):
				_log_text("[color=red]Unknown key: %s[/color]" % key)
				return
			var raw := str(parts[4])
			var value: Variant = raw
			if key == "file":
				value = _sfx_path(raw)
			elif key == "loop":
				value = raw == "true" or raw == "1"
			else:
				value = float(raw)
			Sfx.debug_set(ev, key, value)
			Sfx.play_event(ev.get_slice(".", 0), ev.get_slice(".", 1).to_int() - 1 if ev.contains(".") else -1)
			_log_text("%s.%s = %s → играю  (в файл: sfx save)" % [ev, key, str(value)])
		"file":
			if parts.size() < 3:
				_log_text("[color=red]sfx file <путь> [дБ] [pitch][/color]")
				return
			var path := _sfx_path(str(parts[2]))
			var vol := float(parts[3]) if parts.size() >= 4 else 0.0
			var pitch := float(parts[4]) if parts.size() >= 5 else 1.0
			if Sfx.debug_play_file(path, vol, pitch):
				_log_text("Играет %s (%.1f дБ, pitch %.2f)" % [path, vol, pitch])
			else:
				_log_text("[color=red]Файл не найден или не импортирован: %s[/color]" % path)
		"save":
			if Sfx.debug_save():
				_log_text("[color=green]Записано в assets/audio/sounds.json[/color]")
			else:
				_log_text("[color=red]Не удалось записать sounds.json[/color]")
		"rarity":
			# Проверка звука раскрытия по редкости: sfx rarity legendary
			if parts.size() < 3:
				_log_text("[color=red]sfx rarity <common|rare|epic|legendary|mythic|chromatic>[/color]")
				return
			Sfx.card(str(parts[2]))
			_log_text("Карта %s → %s" % [str(parts[2]), Sfx.card_event_for(str(parts[2]))])
		"stop":
			Sfx.debug_stop()
			_log_text("Звук остановлен")
		_:
			_log_text("[color=red]Usage: %s[/color]" % usage)


## Короткий путь → res://: `cc0/morph.wav` = res://assets/audio/cc0/morph.wav.
func _sfx_path(raw: String) -> String:
	if raw.begins_with("res://"):
		return raw
	return "res://assets/audio/" + raw.trim_prefix("/")


func _sfx_summary(ev: String) -> String:
	var d: Dictionary = Sfx._sound_cfg.get(ev, {})
	if d.is_empty():
		return "(нет в конфиге — процедурный звук)"
	var vs: Array = d.get("variants", [])
	var tail := "  вариантов: %d (sfx play %s N — конкретный)" % [vs.size(), ev] if not vs.is_empty() else ""
	return "file=%s vol=%s pitch=%s%s" % [str(d.get("file", "")).get_file(), str(d.get("volume_db", 0.0)), str(d.get("pitch", 1.0)), tail]

## Быстрая выдача веществ для приёмки. Работает только в редакторе (гейт
## _on_command). Выданное вещество открывается вместе с рецептом, которым оно
## получается: иначе Эксперимент и Мастерская его бы не видели.
##   give all [N]        — весь локальный каталог по N штук (по умолчанию 10)
##   give layer <L> [N]  — вещества слоя сложности ≤ L
##   give <id> [N]       — одно вещество
func _cmd_give(parts: Array) -> void:
	if parts.size() < 2:
		_log_text("[color=red]Usage: give all [N] | give layer <L> [N] | give <id> [N][/color]")
		return
	var what := str(parts[1])
	var count := 10
	var ids: Array[String] = []
	if what == "all":
		if parts.size() >= 3:
			count = maxi(int(parts[2]), 1)
		for raw in _g.ITEMS.keys():
			ids.append(String(raw))
	elif what == "layer":
		if parts.size() < 3:
			_log_text("[color=red]Usage: give layer <L> [N][/color]")
			return
		var max_layer := maxi(int(parts[2]), 0)
		if parts.size() >= 4:
			count = maxi(int(parts[3]), 1)
		var depth := _catalog_depth()
		for raw in depth.keys():
			if int(depth[raw]) <= max_layer:
				ids.append(String(raw))
	else:
		if not _g.ITEMS.has(what):
			_log_text("[color=red]Unknown element: %s[/color]" % what)
			return
		if parts.size() >= 3:
			count = maxi(int(parts[2]), 1)
		ids.append(what)
	var granted := give_items(ids, count)
	_log_text("Granted %d elements x%d, recipes known: %d" % [granted, count, _g._engine.known_recipes.size()])


## Глубина вещества по всему локальному каталогу (стихии — 0), не по уже
## известным рецептам: иначе в свежей игре слои были бы пустыми.
func _catalog_depth() -> Dictionary:
	var depth := {}
	for id in Game.BASE_IDS:
		depth[String(id)] = 0
	var changed := true
	while changed:
		changed = false
		for recipe in _g.RECIPES:
			var a := String(recipe["a"])
			var b := String(recipe["b"])
			var out := String(recipe.get("out", ""))
			if out == "" or not depth.has(a) or not depth.has(b):
				continue
			var d := maxi(int(depth[a]), int(depth[b])) + 1
			if not depth.has(out) or d < int(depth[out]):
				depth[out] = d
				changed = true
	return depth

## Выдать вещества и открыть рецепты их получения; возвращает число веществ.
func give_items(ids: Array[String], count: int) -> int:
	var wanted := {}
	for id in ids:
		wanted[id] = true
	var granted := 0
	for id in ids:
		if not _g.ITEMS.has(id):
			continue
		_g._engine.inventory[id] = int(_g._engine.inventory.get(id, 0)) + count
		granted += 1
	for recipe in _g.RECIPES:
		var out := String(recipe.get("out", ""))
		if wanted.has(out) and not _g._engine.known_recipes.has(_g._pair_key(String(recipe["a"]), String(recipe["b"]))):
			_g._engine.learn_recipe(String(recipe["a"]), String(recipe["b"]), out)
	_g._engine._cost_cache.clear()
	_g._engine._layer_cache.clear()
	_g._engine._refresh()
	_g._pages._ensure_modes()
	if _g._workshop != null:
		_g._workshop.changed.emit()
	_g._saves._save_game()
	return granted


func _cmd_add(parts: Array) -> void:
	if parts.size() < 2:
		_log_text("[color=red]Usage: add <element_id>[/color]")
		return
	var eid: String = str(parts[1])
	var count := 1
	if parts.size() >= 3:
		count = maxi(int(parts[2]), 1)
	var inv: Dictionary = _g._engine.inventory
	inv[eid] = inv.get(eid, 0) + count
	_g._engine.inventory = inv
	_g._saves._save_game()
	_log_text("Added %d x %s" % [count, eid])

func _cmd_unlock(parts: Array) -> void:
	if parts.size() < 2:
		_log_text("[color=red]Usage: unlock <mode_key>[/color]")
		return
	var mode_key: String = str(parts[1])
	var found := false
	for m in _g.MODES:
		if m["key"] == mode_key:
			found = true
			break
	if not found:
		var keys := []
		for m in _g.MODES:
			keys.append(str(m["key"]))
		_log_text("[color=red]Unknown mode: %s. Available: %s[/color]" % [mode_key, ", ".join(keys)])
		return
	var inv_count := _g._engine.inventory.size()
	for m in _g.MODES:
		if m["key"] != mode_key:
			continue
		var min_items: int = m.get("min_items", 0)
		if inv_count < min_items:
			var needed := min_items - inv_count
			var base_items := ["fire", "water", "earth", "air"]
			for i in needed:
				var item_id: String = base_items[i % base_items.size()]
				_g._engine.inventory[item_id] = _g._engine.inventory.get(item_id, 0) + 1
			_log_text("Unlocked %s (added %d base items)" % [mode_key, needed])
		else:
			_log_text("Mode %s already unlocked by item count" % mode_key)
		break
	_g._saves._save_game()

func _cmd_set(parts: Array) -> void:
	if parts.size() < 3 or parts[1] != "ether":
		_log_text("[color=red]Usage: set ether <N>[/color]")
		return
	var val := int(parts[2])
	_g._engine.ether = val
	_g._saves._save_game()
	_log_text("Ether set to %d" % val)

func _cmd_reset(parts: Array) -> void:
	if parts.size() < 2 or parts[1] != "day":
		_log_text("[color=red]Usage: reset day[/color]")
		return
	_g._contracts._last_visit_day = ""
	_g._engine._experiment_day = ""
	_g._saves._save_game()
	_log_text("Day key reset")

func _cmd_clear(parts: Array) -> void:
	if parts.size() < 2 or parts[1] != "inventory":
		_log_text("[color=red]Usage: clear inventory[/color]")
		return
	_g._engine.inventory.clear()
	_g._saves._save_game()
	_log_text("Inventory cleared")

func _cmd_force(parts: Array) -> void:
	if parts.size() < 3 or parts[1] != "circle":
		_log_text("[color=red]Usage: force circle open[/color]")
		return
	if parts[2] != "open":
		_log_text("[color=red]Usage: force circle open[/color]")
		return
	_g._contracts._last_visit_day = ""
	_g._engine._experiment_day = ""
	_g._saves._save_game()
	_log_text("Daily board keys cleared (visit and experiment open again)")

func _cmd_sigil(parts: Array) -> void:
	if parts.size() < 2:
		_log_text("[color=red]Usage: sigil rotate|free <0|1|2>[/color]")
		return
	var sub := str(parts[1])
	if sub == "craft":
		# Открыть экран крафта крафта дня <N> (перенос материалов вручную).
		# НЕ автозавершаем: игрок сам расставляет ингредиенты и жмёт «Крафт».
		if parts.size() < 3:
			_log_text("[color=red]Usage: sigil craft <0|1|2>[/color]")
			return
		var idx := int(parts[2])
		if idx < 0 or idx > 2:
			_log_text("[color=red]Index must be 0, 1, or 2[/color]")
			return
		var crafts: Array = _g._sigil._daily_crafts
		if crafts.is_empty() or idx >= crafts.size():
			_log_text("[color=red]No daily crafts available[/color]")
			return
		var craft: Dictionary = crafts[idx]
		if _g.has_method("_open_sigil_craft"):
			# Админ-команда: открываем экран крафта напрямую, без гейтов ресурсов
			# (для тестирования окна; расставить ингредиенты игрок может тапом).
			_g._open_sigil_craft(craft)
			_log_text("Craft screen opened: %s (%s)" % [str(craft.get("id", "")), str(craft.get("rarity", ""))])
		else:
			_log_text("[color=red]No craft screen available[/color]")
	elif sub == "ritual":
		# Демо ритуала без крафта: смотрим визуал церемонии (rarity опционально).
		var rar := str(parts[2]) if parts.size() > 2 else "epic"
		if _g.has_method("_show_sigil_craft_ritual"):
			_g._show_sigil_craft_ritual(rar)
			_log_text("Ritual demo: %s (тап по экрану — закрыть)" % rar)
		else:
			_log_text("[color=red]No ritual method[/color]")
	elif sub in ["reset", "rotate"]:
		# РОТАЦИЯ крафтов дня: сервер пересобирает оффер, коллекция цела.
		var dev: String = _g._online._device_id
		if not _g._sigil.sigil_admin_rotate_result.is_connected(_on_sigil_rotate_done):
			_g._sigil.sigil_admin_rotate_result.connect(_on_sigil_rotate_done, CONNECT_ONE_SHOT)
		_g._sigil.request_admin_rotate(dev)
		_log_text("Sigil reset: rotating daily crafts...")
	elif sub == "chroma":
		# Подменить слот 0 оффера дня на НОВЫЙ уникальный хроматик —
		# его можно скрафтить как обычный слот.
		var dev: String = _g._online._device_id
		if not _g._sigil.sigil_admin_chromatic_result.is_connected(_on_sigil_chroma_done):
			_g._sigil.sigil_admin_chromatic_result.connect(_on_sigil_chroma_done, CONNECT_ONE_SHOT)
		_g._sigil.request_admin_chroma_slot(dev)
		_log_text("Sigil chroma: ставлю уникальный хроматик в слот 0...")
	elif sub == "free":
		if parts.size() < 3:
			_log_text("[color=red]Usage: sigil free <0|1|2>[/color]")
			return
		var idx := int(parts[2])
		if idx < 0 or idx > 2:
			_log_text("[color=red]Index must be 0, 1, or 2[/color]")
			return
		var crafts: Array = _g._sigil._daily_crafts
		if crafts.is_empty() or idx >= crafts.size():
			_log_text("[color=red]No daily crafts available[/color]")
			return
		var craft: Dictionary = crafts[idx]
		var craft_id := str(craft.get("id", ""))
		# Пишем результат ТОЛЬКО после ответа сервера (иначе «добавлено», а
		# коллекция пуста — офлайн/ошибка). Одноразовые коннекты на сигналы.
		_g._sigil.craft_card(_g._online._device_id, craft_id)
		var log := _log
		var done := func(_cid: String, _rarity: String, _name: String) -> void:
			log.append_text("Free craft done: %s (%s)\n" % [_cid, _rarity])
		var fail := func(err: String) -> void:
			log.append_text("[color=red]Free craft failed: %s[/color]\n" % err)
		_g._sigil.craft_completed.connect(done, CONNECT_ONE_SHOT)
		_g._sigil.craft_failed.connect(fail, CONNECT_ONE_SHOT)
	else:
		_log_text("[color=red]Unknown sigil command: %s[/color]" % sub)

## Ответ сервера на ротацию дневных: лог + новый оффер.
func _on_sigil_rotate_done(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		var crafts: Array = result.get("crafts", [])
		var ids := []
		for c in crafts:
			ids.append(str((c as Dictionary).get("id", "")))
		_log_text("Daily crafts rotated: %s" % ", ".join(ids))
		# Модалка коллекции открыта на «Крафтах дня» — перерисовать список
		# с новым оффером (вкладка пересобирается с нуля через _sigil_show_tab).
		if _g._sigil_coll != null and _g._sigil_tab == "crafts":
			_g._sigil_show_tab.call_deferred("crafts")
	else:
		_log_text("[color=red]Sigil rotate FAIL: %s[/color]" % str(result.get("error", "?")))


## Ответ сервера на установку хроматика в слот 0: лог + перерисовка крафтов.
func _on_sigil_chroma_done(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		var crafts: Array = result.get("crafts", [])
		if not crafts.is_empty():
			var c: Dictionary = crafts[0]
			_log_text("Хроматик в слоте 0: %s (rarity=%s)" % [
				str(c.get("llm_name", "?")), str(c.get("rarity", "?"))])
		else:
			_log_text("Хроматик поставлен (оффер обновлён)")
		# Перерисовать открытую вкладку крафтов с новым оффером.
		if _g._sigil_coll != null and _g._sigil_tab == "crafts":
			_g._sigil_show_tab.call_deferred("crafts")
	else:
		_log_text("[color=red]Sigil chroma FAIL: %s[/color]" % str(result.get("error", "?")))


func _log_text(msg: String) -> void:
	_log.append_text(msg + "\n")


## Открывает мебель дома без покупки: «house all» — весь каталог (вместе с только
## что положенными в assets/house/items PNG), «house <id>» — один предмет.
## Домик строится, если ещё не построен, чтобы предмет сразу можно было поставить.
func _cmd_house(parts: Array) -> void:
	if parts.size() < 2:
		_log_text("[color=red]Usage: house all | house <id>[/color]")
		return
	HouseItems.reload()
	var home = _g._home
	var ids: Array = []
	if str(parts[1]) == "all":
		ids = HouseItems.ITEMS.keys()
	elif HouseItems.exists(str(parts[1])):
		ids = [str(parts[1])]
	else:
		_log_text("[color=red]Unknown item: %s[/color]" % str(parts[1]))
		return
	if not home._cosmetic_house:
		home._cosmetic_house = true
		home._apply_cosmetic()
	var added := 0
	for id in ids:
		if home._unlock_item(String(id)):
			added += 1
	_g._saves._save_game()
	home._refresh_house_screen()
	_log_text("[color=green]Мебель открыта: %d (всего в каталоге %d)[/color]" % [added, HouseItems.ITEMS.size()])
