extends RefCounted

static func run(g: Game) -> void:
	Selftest.check("startup enters loading screen before gameplay", ProjectSettings.get_setting("application/run/main_scene") == "res://boot.tscn")
	var settings: Control = g._hub._settings_popup
	settings.show()
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var settings_panel := settings.get_child(0) as PanelContainer
	var settings_body := settings_panel.get_child(0) as Control
	var crest := settings_panel.get_node("FrameCrest").get_child(0) as Control
	Selftest.check("settings title clears crest with breathing room",
		settings_body.global_position.y >= crest.get_global_rect().end.y + 12.0)
	Selftest.check("modal content clears engraved corners",
		settings_body.position.x >= 28.0 and settings_body.position.y >= 32.0)
	Selftest.check("settings frame stays inside portrait viewport",
		g.get_viewport_rect().encloses(settings_panel.get_global_rect()))
	settings.hide()
	Selftest.check("compact HUD has no permanent game title", g.find_child("TitlePlaque", true, false) == null)
	Selftest.check("room has no permanent explanatory text", g.find_child("WorkshopIntro", true, false) == null)
	for key in ["EtherChip", "ElementsChip", "RecipesChip"]:
		var chip := g.find_child(key, true, false) as Button
		Selftest.check("compact resource is tappable " + key, chip != null)
		if chip != null:
			Selftest.check("resource chip stays inside portrait screen " + key,
				g.get_viewport_rect().encloses(chip.get_global_rect()) and chip.size.y >= 44)
			var value := chip.find_child("Value", true, false) as Label
			var glyph := chip.find_children("Icon_*", "TextureRect", true, false)[0] as TextureRect
			var plaque := chip.get_node("Artwork") as TextureRect
			var s := g.size.x / 360.0
			Selftest.check("HUD plaque matches approved sample " + key, is_equal_approx(plaque.size.y, 26 * s))
			Selftest.check("HUD icon is taller than plaque " + key, glyph.size.y > plaque.size.y)
			Selftest.check("HUD icon protrudes as approved sample " + key, absf(plaque.global_position.x - glyph.global_position.x - 12 * s) < 1.0)
			Selftest.check("HUD icon stays inside screen " + key, g.get_viewport_rect().encloses(glyph.get_global_rect()))
			Selftest.check("HUD digits centered on plaque " + key, value.get_global_rect().get_center().distance_to(plaque.get_global_rect().get_center()) < 1.0)
			Selftest.check("HUD filled icon keeps original colors " + key, glyph.modulate == Color.WHITE)
			if key == "EtherChip":
				Selftest.check("HUD ether uses approved sphere", glyph.texture.resource_path.ends_with("hud_ether_orb.svg"))
				var meter := chip.get_node_or_null("EtherMeter") as TextureProgressBar
				Selftest.check("HUD meter sits below plaque", meter != null and meter.global_position.y >= plaque.get_global_rect().end.y + s)
			Selftest.check("HUD digits stay inside plaque " + key, plaque.get_global_rect().encloses(value.get_global_rect()))
			Selftest.check("HUD digits use semibold " + key, value.get_theme_font("font").resource_path.ends_with("Manrope-SemiBold.ttf"))
			Selftest.check("HUD digits have contrast shadow " + key, value.get_theme_color("font_shadow_color").a > 0.5)
			Selftest.check("HUD icon raster has headroom " + key, glyph.texture.get_width() >= 96)
			chip.pressed.emit()
			await g.get_tree().process_frame
			var detail := g.find_child("HUDDetails", true, false) as Control
			Selftest.check("resource tap reveals details " + key, detail != null and detail.visible)
			Selftest.check("resource detail fits portrait viewport " + key, detail != null and g.get_viewport_rect().encloses(detail.get_global_rect()))
			chip.pressed.emit()
			Selftest.check("resource tap dismisses details " + key, detail != null and not detail.visible)
	for item in g._bottom_nav._items:
		var btn := item["btn"] as Button
		var nav_icon := item["icon"] as TextureRect
		Selftest.check("navigation SVG has raster headroom " + str(item["key"]), nav_icon.texture.get_width() >= 144 and nav_icon.texture.get_height() >= 144)
		Selftest.check("bottom navigation is icon-only " + str(item["key"]),
			btn.find_children("*", "Label", true, false).all(func(n): return n.name == "Badge"))
	var boot_logo := load("res://assets/ui/icons/frame_crest.svg") as Texture2D
	Selftest.check("loading emblem raster covers 280x80 at high density", boot_logo.get_width() >= 560 and boot_logo.get_height() >= 160)
	var top_beam := g.find_child("TopBeam", true, false) as TextureRect
	Selftest.check("reference top beam uses supplied artwork", top_beam != null and top_beam.texture.resource_path.ends_with("01_top_beam_panel.png"))
	var social_panel := g._social_ui._screen.find_child("SocialPanel", true, false) as PanelContainer
	Selftest.check("friends uses lightweight kit modal", social_panel.get_theme_stylebox("panel") is StyleBoxFlat)
	var original_scale_size := g.get_window().content_scale_size
	var original_window_size := g.get_window().size
	for dimensions in [Vector2i(540, 960), Vector2i(420, 840), Vector2i(360, 800), Vector2i(540, 960)]:
		g.get_window().content_scale_size = dimensions
		g.get_window().size = dimensions
		for tab in [0, 1]:
			g._social_ui.open(tab)
			for frame in 4:
				await g.get_tree().process_frame
			_check_modal_corners(social_panel, "%s tab%d" % [dimensions, tab])
	g.get_window().content_scale_size = Vector2i(360, 800)
	g.get_window().size = Vector2i(360, 800)
	g._social._seed_demo()
	for tab in [0, 1]:
		g._social_ui.open(tab)
		for frame in 4:
			await g.get_tree().process_frame
		Selftest.check("friends panel fits viewport tab %d" % tab, g.get_viewport_rect().encloses(social_panel.get_global_rect()))
		var panel_style := social_panel.get_theme_stylebox("panel") as StyleBoxFlat
		Selftest.check("friends shadow fits viewport tab %d" % tab, g.get_viewport_rect().encloses(social_panel.get_global_rect().grow(panel_style.shadow_size)))
		var rows := g._social_ui._body.find_child("SocialRows", true, false) as Control
		Selftest.check("friends rows fit list width tab %d" % tab, rows.size.x <= g._social_ui._list_scroll.size.x)
		for row in rows.get_children():
			for label in row.find_children("*", "Label", true, false):
				if label.get_theme_font_size("font_size") == 14:
					Selftest.check("friend name has readable width tab %d" % tab, label.size.x >= 80)
			for button in row.find_children("*", "Button", true, false):
				Selftest.check("friend action stays inside panel tab %d" % tab, social_panel.get_global_rect().encloses(button.get_global_rect()))
	g._social_ui._show_card({"nick": "ОченьДлинноеИмяАлхимика", "last_seen": "2026-11-09"})
	for frame in 4:
		await g.get_tree().process_frame
	Selftest.check("friend search result fits viewport", g.get_viewport_rect().encloses(social_panel.get_global_rect()))
	g._social.cache["friends"][1]["nick"] = "ОченьДлинноеИмяАлхимика"
	g._social.threads["dev-b"] = [{"id": 1, "from_me": false, "body": "Длинное сообщение без потери читаемости. ".repeat(40), "sent_at": "2026-11-10T10:00:00"}]
	g._social_ui._open_thread("dev-b")
	for frame in 6:
		await g.get_tree().process_frame
	Selftest.check("friend thread fits viewport", g.get_viewport_rect().encloses(social_panel.get_global_rect()))
	g._social_ui.show_send_error("pending_limit")
	for frame in 4:
		await g.get_tree().process_frame
	Selftest.check("friend error fits viewport", g.get_viewport_rect().encloses(social_panel.get_global_rect()))
	g._social_ui.close()
	ContractBoard.open(g)
	var board := g.get_node("ContractBoard") as ContractBoard
	for card_index in range(board._cards.size()):
		var paper_card := board._cards[card_index] as ContractCard
		paper_card.scale = Vector2.ONE * ContractCard.HOVER_SCALE
		var bounds := _drawn_bounds(paper_card._paper).merge(_drawn_bounds(paper_card._seal))
		for other_index in range(card_index):
			var other := board._cards[other_index] as ContractCard
			var other_bounds := _drawn_bounds(other._paper).merge(_drawn_bounds(other._seal))
			Selftest.check("rotated papers do not overlap %d/%d" % [card_index, other_index], not bounds.intersects(other_bounds))
		paper_card.scale = Vector2.ONE
	Selftest.check("scrolling paper is visually clipped", (board._daily_row.get_parent() as Control).clip_contents)
	var heading_position := board._sign.global_position
	board._scroll_to(board._scroll_max)
	Selftest.check("board heading remains clear while scrolling", board._sign.global_position == heading_position)
	board._scroll_to(0)
	Selftest.check("rank title has readable width", board._rank_title.size.x >= 80.0)
	Selftest.check("rank title clears milestones", not board._rank_title.get_global_rect().intersects(board._mile_days.get_global_rect()))
	for tier in ["bronze", "silver", "gold"]:
		var seal_card := board._cards[0] as ContractCard
		var data := seal_card._c.duplicate(true)
		data["tier"] = tier
		seal_card.setup(data)
		Selftest.check("wax seal retains sun emblem " + tier, seal_card._seal.texture == ContractCard.tex("seal_" + tier + ".png"))
	Selftest.check("contracts use apothecary board artwork", board._bg.texture.resource_path.ends_with("17_contract_board_frame.png"))
	Selftest.check("contract paper uses supplied fine border", (board._cards[0] as ContractCard)._paper.texture.resource_path.ends_with("18a_contract_parchment_daily.png"))
	board._on_close()
	g.get_window().content_scale_size = original_scale_size
	g.get_window().size = original_window_size
	for frame in 4:
		await g.get_tree().process_frame
	var cauldron: Dictionary = g._bottom_nav._items[0]
	var shield := (cauldron["artwork"] as Control).get_parent() as Control
	var cauldron_icon := cauldron["icon"] as Control
	Selftest.check("cauldron icon is centered inside shield", cauldron_icon.get_global_rect().get_center().distance_to(shield.get_global_rect().get_center()) < 2.0)
	Selftest.check("dock renders above friends section", g._bottom_nav.bar.z_index > g._social_ui._screen.z_index)
	Selftest.check("shield touch area covers its raised artwork", (cauldron["btn"] as Control).get_global_rect().encloses(shield.get_global_rect()))
	var previous_tab := g._tabs_ref.current_tab
	g._bottom_nav._on_pressed("rating")
	for item in g._bottom_nav._items:
		var skin := (item["btn"] as Button).find_child("TabArtwork", true, false) as TextureRect
		var material := skin.material as ShaderMaterial if skin != null else null
		Selftest.check("selected tab alone has glow " + str(item["key"]), material != null and is_equal_approx(float(material.get_shader_parameter("active_amount")), 1.0 if item["key"] == "rating" else 0.0))
	g._bottom_nav._on_pressed("friends")
	for item in g._bottom_nav._items:
		var material := (item["artwork"] as TextureRect).material as ShaderMaterial
		Selftest.check("friends overlay owns exclusive active glow " + str(item["key"]), is_equal_approx(float(material.get_shader_parameter("active_amount")), 1.0 if item["key"] == "friends" else 0.0))
	g._bottom_nav._on_pressed("lab")
	g._tabs_ref.current_tab = previous_tab
	var card := SigilCard.new()
	g.add_child(card)
	var options := SigilOptions.make({"fluid_enabled": false, "aura_enabled": false, "save_png": false})
	card.setup(SuiteSigilCards._recipe(987654321, "steam"), options)
	var safe := Rect2(Vector2.ZERO, card.size).grow(-(options.frame_margin + 24.0))
	Selftest.check("sigil title stays inside corner ornament clearance", safe.encloses(card.title.get_rect()))
	card.queue_free()
	Selftest.check("engraved screen has fixed-size crest", g._screens.panel.get_node_or_null("FrameCrest") != null)
	for kind in [0, 1, 2]:
		var button := Button.new()
		UIStyle.style_button(button, kind)
		var normal := button.get_theme_stylebox("normal") as StyleBoxTexture
		var focus := button.get_theme_stylebox("focus")
		Selftest.check("engraved keyboard focus remains visible %d" % kind, not focus is StyleBoxEmpty)
		Selftest.check("engraved hover retains matte surface %d" % kind,
			(button.get_theme_stylebox("hover") as StyleBoxTexture).modulate_color.r <= 1.10)
		Selftest.check("engraved disabled state preserves button dimensions %d" % kind,
			button.get_theme_stylebox("disabled").get_minimum_size() == normal.get_minimum_size())
		button.free()
	var row := Button.new()
	UIStyle.style_row(row)
	Selftest.check("engraved disabled row has explicit state", row.has_theme_stylebox_override("disabled"))
	row.free()
	var icon_button := Button.new()
	UIIcon.into_button(icon_button, "gi_arcana")
	UIIcon._hover(icon_button, true)
	Selftest.check("engraved icon hover keeps geometry stable", icon_button.get_node("IconCenter").scale == Vector2.ONE)
	icon_button.free()
	var theme := Theme.new()
	UIStyle.apply_theme(theme)
	for control in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		Selftest.check("engraved global control themed " + control,
			theme.has_stylebox("normal", control) and theme.has_stylebox("focus", control))
	for icon in ["gi_cauldron", "gi_world", "gi_friends", "gi_rating", "gi_more", "gi_arcana", "x", "settings"]:
		Selftest.check("engraved icon loads " + icon, UIIcon.texture(icon) != null)

static func _check_modal_corners(panel: Control, state: String) -> void:
	var overlay := panel.get_node("MicroCorners")
	Selftest.check("four modal corners " + state, overlay.get_child_count() == 4)
	var expected := [Vector2.ZERO, Vector2(panel.size.x - 18, 0), Vector2(0, panel.size.y - 18), panel.size - Vector2(18, 18)]
	for i in 4:
		var corner := overlay.get_child(i) as Control
		var transform := panel.get_global_transform().affine_inverse() * corner.get_global_transform()
		var actual := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
		for point in [Vector2(corner.size.x, 0), corner.size, Vector2(0, corner.size.y)]:
			actual = actual.expand(transform * point)
		var want := Rect2(expected[i], Vector2(18, 18))
		print("CORNER ", state, " #", i, " panel=", panel.get_global_rect(), " local=", actual, " expected=", want, " global=", _drawn_bounds(corner))
		Selftest.check("modal corner aligned %d %s" % [i, state], actual.is_equal_approx(want))
		Selftest.check("modal corner inside panel %d %s" % [i, state], Rect2(Vector2.ZERO, panel.size).encloses(actual))
		Selftest.check("modal corner inside screen %d %s" % [i, state], panel.get_viewport_rect().encloses(_drawn_bounds(corner)))

static func _drawn_bounds(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	var bounds := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]:
		bounds = bounds.expand(transform * corner)
	return bounds
