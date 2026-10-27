extends RefCounted
class_name SuiteUiScene
# Перенос иммерсивного интерактивного экрана (каркас PR #65 поверх тёплой темы):
# сцена = навигация. Верхний TabBar спрятан, разделы переключает нижний бар,
# устройства открываются bottom-sheet'ом, стол и Мастерская — две комнаты
# карусели, а не вкладки.
#
# Мутационные красные зоны:
# - возврат `tabs.get_tab_bar().visible = true` красит «top tab bar hidden»;
# - снятие BottomNav красит «nav six items», «nav press switches tab»,
#   «nav marks active item», «nav house entry opens workshop screen»;
# - старые офсеты brew-бара (−132/−12) красят «brew bar above nav»;
# - возврат `_pages._build_experiment_location(experiment)` вместо карусели
#   красит «rooms two», «tool props three», «scene props three»;
# - `_refresh_chrome()` без выключения объектов красит «scene props hidden in
#   workshop»; мыши-only свайп — «touch swipe advances room»; релиз без нажатия —
#   «stray release ignored»;
# - `set_locked(..., disabled = true)` красит «locked prop stays tappable»;
# - тап по замку без объяснения красит «locked tool explains gate»;
# - routing «spring» в лист красит «spring opens full immersive screen»;
# - возврат `_pages._apply_tools_selection()` без учёта листа красит
#   «sheet survives core refresh» — проверено на НЕ выбранной в «Инструментах»
#   странице (выбранную видимость сохраняет сам выбор, и пин не гаснет);
# - VBox ячейки навигации без якорей красит «nav item content centered»;
# - кнопка «Закрыть», проводившая не в close(), красит «sheet close button closes»;
# - офсет комнаты 1 меньше половины экрана красит «experiment fills the room»
#   (тот самый «пол экрана ничем не занято»);
# - индексы 4/5 вместо TAB_RATING/TAB_TOOLS в `_on_tab_changed()` красят
#   «rating tab refetches rating» и «tools tab rebuilds tool selection».

static func run(g: Game) -> void:
	var st_tab := g._tabs_ref.current_tab

	# ---------- навигация: экран вместо вкладок ----------
	Selftest.check("top tab bar hidden", not g._tabs_ref.get_tab_bar().visible)
	Selftest.check("nav six items", g._bottom_nav != null
			and g._bottom_nav._items.size() == 6)
	g._bottom_nav._on_pressed("rating")
	Selftest.check("nav press switches tab",
			g._tabs_ref.current_tab == Game.TAB_RATING)
	var active_mark: ColorRect = g._bottom_nav._items[4]["mark"]
	var idle_mark: ColorRect = g._bottom_nav._items[0]["mark"]
	Selftest.check("nav marks active item", active_mark.color == UIStyle.BRASS
			and active_mark.color != idle_mark.color and idle_mark.color.a == 0.0)
	# Button — не контейнер: без якорей VBox прижимал иконку и подпись к левому
	# краю ячейки (это и видно на первом кадре приёмки).
	var it0: Dictionary = g._bottom_nav._items[0]
	var b0: Control = it0["btn"]
	var l0: Label = it0["label"]
	Selftest.check("nav item content centered", b0.size.x > 0.0
			and absf((l0.global_position.x + l0.size.x * 0.5)
					- (b0.global_position.x + b0.size.x * 0.5)) < 2.0)
	# Дом — не вкладка TabContainer: он открывает экран дома, не двигая страницы.
	g._bottom_nav._on_pressed("rating")
	g._bottom_nav._on_pressed("house")
	Selftest.check("nav house entry opens workshop screen",
			g._home._house_screen != null and g._home._house_screen.visible
			and g._tabs_ref.current_tab == Game.TAB_RATING)
	g._home._close_house_screen()
	g._tabs_ref.current_tab = st_tab

	# ---------- карусель комнат ----------
	Selftest.check("rooms two", g._rooms != null and g._rooms._rooms.size() == 2)
	Selftest.check("tool props three", g._rooms._props.has("spring")
			and g._rooms._props.has("bench") and g._rooms._props.has("retort"))
	var deck: Control = g._rooms._host.find_child("Prop_Deck", true, false) as Control
	var board: Control = g._rooms._host.find_child("Prop_Board", true, false) as Control
	var scroll_prop: Control = g._rooms._host.find_child("Prop_Scroll", true, false) as Control
	Selftest.check("scene props three", deck != null and board != null
			and scroll_prop != null)
	# Предмет подписан табличкой и подсвечен ореолом — «что это» читается без меню.
	var plaque := deck.find_child("PlaqueText", true, false) as Label
	var halo := deck.find_child("Glow", true, false) as TextureRect
	Selftest.check("prop has plaque and glow", plaque != null
			and plaque.text == "Аркан" and halo != null
			and halo.modulate.a > 0.0)
	# Ореол только на предметах: ни одна панель/кнопка его не получает.
	Selftest.check("glow lives only on props",
			g.find_children("Glow", "TextureRect", true, false).size()
			== g._rooms._scene_props.size() + g._rooms._props.size())

	# геометрия: поле заполняет комнату, а не висит в её углу
	# (претензия владельца — «пол экрана ничем не занято»)
	var field: Control = g._pages._experiment_field
	var host_h := g._rooms._host.size.y
	Selftest.check("experiment fills the room", host_h > 0.0 and field != null
			and field.get_global_rect().size.y >= host_h * 0.5)

	g._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	g._rooms.set_room(1)
	Selftest.check("room switch", g._rooms.room_index() == 1
			and g._rooms._rooms[1].visible and not g._rooms._rooms[0].visible
			and g._rooms._left_btn.visible and not g._rooms._right_btn.visible)
	var props_hidden := true
	for p in g._rooms._scene_props:
		if (p as Control).visible:
			props_hidden = false
	Selftest.check("scene props hidden in workshop", props_hidden)
	g._rooms.set_room(0)
	Selftest.check("room back", g._rooms.room_index() == 0
			and g._rooms._rooms[0].visible and not g._rooms._rooms[1].visible)
	Selftest.check("scene props visible in lab", deck.visible)

	# свайп пальцем: тач-события, а не только мышь
	var tp := InputEventScreenTouch.new()
	tp.pressed = true
	tp.position = Vector2(300, 200)
	g._rooms._on_gui_input(tp)
	var tr := InputEventScreenTouch.new()
	tr.pressed = false
	tr.position = Vector2(120, 200)
	g._rooms._on_gui_input(tr)
	Selftest.check("touch swipe advances room", g._rooms.room_index() == 1)
	tp.pressed = true
	tp.position = Vector2(120, 200)
	g._rooms._on_gui_input(tp)
	tr.pressed = false
	tr.position = Vector2(300, 200)
	g._rooms._on_gui_input(tr)
	Selftest.check("touch swipe returns", g._rooms.room_index() == 0)
	# тач эмулирует мышь: релиз без нажатия не листает
	var stray := InputEventScreenTouch.new()
	stray.pressed = false
	stray.position = Vector2(300, 200)
	g._rooms._on_gui_input(stray)
	Selftest.check("stray release ignored", g._rooms.room_index() == 0)

	# панель варки стоит над нижним баром, а не под ним
	Selftest.check("brew bar above nav",
			g._brew_bar.offset_bottom == -12 - BottomNav.NAV_H
			and g._brew_bar.offset_top == -196)

	# ---------- bottom-sheet устройств ----------
	var keys: Array = g._pages._mode_pages.keys()
	Selftest.check("tool pages exist", not keys.is_empty())
	if keys.is_empty():
		g._tabs_ref.current_tab = st_tab
		return
	# Пробуем лист НЕ выбранной в «Инструментах» страницей: выбранную
	# _apply_tools_selection() оставляет видимой сама, и пин не мог бы погаснуть.
	var probe := "bench" if keys.has("bench") else String(keys[0])
	for k in keys:
		if String(k) != String(g._pages._tools_sel) and g._engine._mode_unlocked(String(k)):
			probe = String(k)
			break
	var box: Control = g._pages._mode_pages[probe]
	var orig_parent := box.get_parent()
	Selftest.check("sheet closed initially", not g._sheet.is_open())
	g._sheet.open(probe, "Проверка")
	Selftest.check("sheet opens with page content", g._sheet.is_open()
			and box.get_parent() == g._sheet._host_box and box.visible)
	# любой _refresh() (через _apply_tools_selection) не должен гасить открытый лист
	g._engine._refresh()
	Selftest.check("sheet survives core refresh", g._sheet.is_open() and box.visible)
	var close_btn: Button = g.find_child("SheetClose", true, false)
	if close_btn != null:
		close_btn.pressed.emit()
	Selftest.check("sheet close button closes", close_btn != null
			and not g._sheet.is_open() and box.get_parent() == orig_parent)

	# ---------- устройства в комнате Мастерской ----------
	# Замок проверяем на Роднике: его условие — вещество в инвентаре, тогда как
	# «bench» остаётся доступным через флаг Мастерской и для гейта непригоден.
	if is_instance_valid(g._spring_screen):
		g._spring_screen._close()
	var inv_backup := g._engine.inventory.duplicate()
	var fountain_btn: Button = g._rooms._props["spring"]
	g._engine.inventory.erase("plant")
	g._rooms.refresh_unlocks()
	Selftest.check("locked prop stays tappable", not fountain_btn.disabled
			and fountain_btn.modulate.a < 1.0)
	g._engine.status_text = ""
	g._rooms._open_tool("spring")
	Selftest.check("locked tool explains gate", not g._sheet.is_open()
			and not is_instance_valid(g._spring_screen)
			and g._engine.status_text == g._pages._mode_hint("spring"))
	g._engine.inventory["plant"] = 1
	g._rooms.refresh_unlocks()
	Selftest.check("unlocked prop glows again", fountain_btn.modulate == Color.WHITE)
	# Родник — полноэкранный иммерсивный экран, его лист не заменяет
	g._engine.status_text = ""
	g._rooms._open_tool("spring")
	Selftest.check("spring opens full immersive screen",
			is_instance_valid(g._spring_screen) and not g._sheet.is_open())
	if is_instance_valid(g._spring_screen):
		g._spring_screen._close()
	var bench_unlocked := g._engine._mode_unlocked("bench")
	g._rooms._open_tool("bench")
	Selftest.check("workshop prop opens sheet", g._sheet.is_open() == bench_unlocked)
	g._sheet.close()
	g._engine.inventory = inv_backup
	g._engine.status_text = ""
	g._engine._refresh()
	g._rooms.refresh_unlocks()

	# ---------- смена раздела по индексам навигации ----------
	# Было: рейтинг на 4 и «Инструменты» на 5 — при TAB_RATING=3/TAB_TOOLS=4
	# рейтинг не обновлялся никогда, а лист режимов не перестраивался вовсе.
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
