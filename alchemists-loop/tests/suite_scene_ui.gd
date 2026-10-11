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

	g._tabs_ref.current_tab = st_tab
