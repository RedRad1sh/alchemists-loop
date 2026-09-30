extends RefCounted
class_name AdminConsole
# Админ-консоль: toggle по ~ (тильда), парсинг команд из текстового ввода.
# Команды: add <element>, unlock <mode>, set ether <N>, reset day,
# clear inventory, force circle open.

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
	help.text = "add <id> | unlock <mode> | set ether <N> | reset day | clear inventory | force circle open"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(help)

func toggle() -> void:
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
	var cmd := text.strip_edges().to_lower()
	_input.text = ""
	if cmd.is_empty():
		return
	_log_text("> " + text.strip_edges())
	var parts := cmd.split(" ", false)
	match parts[0]:
		"add":
			_cmd_add(parts)
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
		"help":
			_log_text("Commands: add <id>, unlock <mode>, set ether <N>, reset day, clear inventory, force circle open, sigil rotate|free <0|1|2>")
		_:
			_log_text("[color=red]Unknown command: %s[/color]" % parts[0])

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
	_g._retention._circle_last = ""
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
	_g._retention._circle_last = ""
	_g._engine._experiment_day = ""
	_g._saves._save_game()
	_log_text("Circle forced open (day keys cleared)")

func _cmd_sigil(parts: Array) -> void:
	if parts.size() < 2:
		_log_text("[color=red]Usage: sigil rotate|free <0|1|2>[/color]")
		return
	var sub := str(parts[1])
	if sub == "rotate":
		# Принудительная ротация ежедневных крафтов
		_g._sigil._daily_crafts.clear()
		_g._sigil._daily_day = ""
		_g._sigil.request_daily(_g._online._device_id)
		_log_text("Sigil daily crafts rotated")
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
		_g._sigil.craft_card(_g._online._device_id, craft_id)
		_log_text("Free craft: %s (%s)" % [craft_id, craft.get("rarity", "unknown")])
	else:
		_log_text("[color=red]Unknown sigil command: %s[/color]" % sub)

func _log_text(msg: String) -> void:
	_log.append_text(msg + "\n")
