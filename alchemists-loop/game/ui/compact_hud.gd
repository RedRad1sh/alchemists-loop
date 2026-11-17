extends RefCounted

const Kit = preload("res://game/ui/menu_kit.gd")
var g: Game
var row: Control
var sides: Control
var details: PanelContainer
var detail_label: Label
var recipe_count: Label
var ether_meter: TextureProgressBar
var chips: Dictionary = {}
var selected := ""

func build(game: Game, parent: VBoxContainer) -> void:
	g = game
	var s := g.size.x / 360.0
	row = Control.new()
	row.name = "CompactHUD"
	row.custom_minimum_size.y = 60 * s - 12
	parent.add_child(row)
	var beam := Kit.artwork(row, "01_top_beam_panel.png", "TopBeam")
	beam.offset_left = -12
	beam.offset_right = 12
	beam.offset_top = -12
	var resources := HBoxContainer.new()
	resources.position = Vector2(16 * s - 12, 8 * s - 12)
	resources.add_theme_constant_override("separation", roundi(10 * s))
	row.add_child(resources)
	g._engine._ether_label = _chip(resources, "EtherChip", "ether_orb", "ether", Vector2(108, 44) * s, "02a_resource_plaque_wide.png")
	g._engine._collection_label = _chip(resources, "ElementsChip", "flask", "elements", Vector2(76, 44) * s, "02b_resource_plaque_compact.png")
	recipe_count = _chip(resources, "RecipesChip", "book", "recipes", Vector2(76, 44) * s, "02b_resource_plaque_compact.png")
	ether_meter = TextureProgressBar.new()
	ether_meter.name = "EtherMeter"
	ether_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ether_meter.texture_under = Kit.texture("03_top_energy_bar_track.png")
	ether_meter.texture_progress = Kit.texture("04_top_energy_bar_fill.png")
	ether_meter.nine_patch_stretch = true
	ether_meter.stretch_margin_left = 3
	ether_meter.stretch_margin_right = 3
	chips["ether"].add_child(ether_meter)
	ether_meter.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ether_meter.offset_left = 18 * s
	ether_meter.offset_right = -10 * s
	ether_meter.offset_top = 37 * s
	ether_meter.offset_bottom = 42 * s
	var profile := Button.new()
	profile.custom_minimum_size = Vector2(44, 44) * s
	Kit.clear_button(profile)
	profile.name = "ProfileEntry"
	profile.tooltip_text = "Профиль: твоё имя и аватар"
	profile.pressed.connect(g._hub._open_profile)
	resources.add_child(profile)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile.add_child(center)
	g._me_avatar = g._make_avatar(g._online._net_nick, roundi(44 * s))
	center.add_child(g._me_avatar)

	sides = Control.new()
	sides.name = "HUDSideActions"
	sides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.add_child(sides)
	var left := _hanging_column("HUDLeftActions", false, s)
	g._guild._quest_label = _side_button("gi_quests", "Задания Светика, достижения, комплекты, заказы", s)
	g._guild._quest_label.pressed.connect(g._progress_ui._open_progress_popup)
	left.add_child(g._guild._quest_label)
	_chain(left, 18, s)
	g._hub._up_btn = _side_button("gi_upgrade", "Улучшения", s)
	g._hub._up_btn.add_child(Kit.wax_badge())
	g._place_badge(g._hub._up_btn)
	g._hub._up_btn.pressed.connect(g._hub._open_upgrades)
	left.add_child(g._hub._up_btn)
	var right := _hanging_column("HUDRightActions", true, s)
	var home := _side_button("gi_house", "Дом Светика", s)
	home.name = "HouseEntry"
	home.pressed.connect(g._home._open_workshop)
	right.add_child(home)
	_chain(right, 18, s)
	var shop := _side_button("gi_shop", "Лавка", s)
	shop.name = "ShopBtn"
	shop.pressed.connect(g._shop.open)
	right.add_child(shop)

	details = PanelContainer.new()
	details.name = "HUDDetails"
	details.add_theme_stylebox_override("panel", UIStyle.panel())
	details.visible = false
	details.z_index = 18
	g.add_child(details)
	details.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	details.offset_left = 12
	details.offset_right = -12
	details.offset_top = 60 * s + 8
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	details.add_child(content)
	detail_label = g._label("", 14)
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(detail_label)
	var close := g._icon_row_button("x", "Закрыть")
	close.pressed.connect(hide_details)
	content.add_child(close)

func _hanging_column(node_name: String, right: bool, s: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.add_theme_constant_override("separation", -roundi(4 * s))
	sides.add_child(column)
	if right:
		column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		column.offset_left = -52 * s
		column.offset_right = -8 * s
	else:
		column.position.x = 8 * s
	column.position.y = 53 * s
	_chain(column, 24, s)
	return column

func _chain(parent: VBoxContainer, height: float, s: float) -> void:
	var chain := TextureRect.new()
	chain.texture = Kit.texture("07_brass_chain_link.png")
	chain.custom_minimum_size = Vector2(9, height) * s
	chain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chain.stretch_mode = TextureRect.STRETCH_SCALE
	chain.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(chain)

func _side_button(icon: String, tip: String, s: float) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(44, 44) * s
	button.tooltip_text = tip
	Kit.frame_button(button, "06_side_button_frame.png")
	UIIcon.into_button(button, icon.replace("gi_", "hud_"), roundi(19 * s), Color("e2bc80"))
	return button

func _chip(parent: HBoxContainer, node_name: String, icon: String, key: String, dimensions: Vector2, file: String) -> Label:
	var s := dimensions.y / 44.0
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(dimensions.x, 44 * s)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.frame_button(button, file)
	var plaque := button.get_node("Artwork") as TextureRect
	plaque.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	plaque.offset_left = 8 * s
	plaque.offset_top = 9 * s
	plaque.offset_bottom = 35 * s
	button.pressed.connect(_toggle_details.bind(key))
	parent.add_child(button)
	chips[key] = button
	var glyph := UIIcon.make("hud_" + icon, roundi(30 * s), Color.WHITE)
	glyph.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.add_child(glyph)
	glyph.position = Vector2(-4, 5) * s
	glyph.size = Vector2(30, 30) * s
	var value := g._label("0", roundi(12 * s))
	button.add_child(value)
	value.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	value.offset_left = 8 * s
	value.offset_top = 9 * s
	value.offset_bottom = 35 * s
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_override("font", g._font_semi)
	value.add_theme_color_override("font_color", Color("ebd5ab"))
	value.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	value.add_theme_constant_override("shadow_offset_x", 0)
	value.add_theme_constant_override("shadow_offset_y", roundi(s))
	value.name = "Value"
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value

func _toggle_details(key: String) -> void:
	if selected == key and details.visible:
		hide_details()
		return
	selected = key
	detail_label.text = chips[key].tooltip_text
	details.show()
	Sfx.click()

func hide_details() -> void:
	selected = ""
	details.hide()

func refresh() -> void:
	recipe_count.text = str(g._engine.known_recipes.size())
	ether_meter.max_value = g._engine._max_ether()
	ether_meter.value = g._engine.ether
	chips["ether"].tooltip_text = "Эфир  %d / %d\nРезерв %d  ·  +%.1f/с" % [g._engine.ether, g._engine._max_ether(), g._engine.ether_overflow, g._engine._ether_rate()]
	var atlas := ""
	var next := g._engine._next_milestone(g._engine.inventory.size())
	if next > 0:
		atlas = "\nАтлас · следующая награда: %d веществ" % next
	chips["elements"].tooltip_text = "Вещества  %d / %d     Рецепты  %d / %d%s" % [g._engine.inventory.size(), g.ITEMS.size(), g._engine.known_recipes.size(), g.RECIPES.size(), atlas]
	chips["recipes"].tooltip_text = "Рецепты: %d / %d" % [g._engine.known_recipes.size(), g.RECIPES.size()]
	if details.visible:
		detail_label.text = chips[selected].tooltip_text

func tab_changed(tab: int) -> void:
	sides.visible = tab == Game.TAB_EXPERIMENT
	hide_details()
