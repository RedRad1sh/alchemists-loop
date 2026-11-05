extends RefCounted
class_name SuiteUiScene
# Перенос иммерсивного интерактивного экрана (каркас PR #65 поверх тёплой темы):
# сцена = навигация. Верхний TabBar спрятан, разделы переключает нижний бар,
# предмет комнаты открывает ПОЛНОЭКРАННЫЙ экран механики (ScreenRouter), а не
# модалку и не bottom-sheet; стол и Мастерская — две комнаты карусели.
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
# - routing «spring» в экран роутера красит «spring opens full immersive screen»;
# - возврат `_pages._apply_tools_selection()` без учёта открытого экрана красит
#   «device screen survives core refresh» — проверено на НЕ выбранной в
#   «Инструментах» странице (выбранную видимость сохраняет сам выбор, и пин
#   не гаснет);
# - VBox ячейки навигации без якорей красит «nav item content centered»;
# - кнопка «← В комнату», ведущая не в close(), красит «screen back closes»;
# - тап по навигации, не закрывающий экран, красит «nav press closes screen»
#   (модалка, пережившая смену раздела);
# - лист, оставленный в дереве вместо роутера, красит «no bottom sheet» и
#   «device screen is not a modal» (экран не должен висеть окном поверх
#   комнаты: комната при нём гаснет целиком);
# - drawer с picker_style() (дырявые границы «обломанной» рамки) или вовсе без
#   панели красит «cauldron tray sits on a complete panel»: текст лотка не
#   должен лежать на краске плиты, как в кадре room_reagents;
# - узкая боковая колонка лотка вместо широкой нижней полосы (кадр
#   room_reagents: «зачем всё в одну строку») красит «cauldron tray is a wide
#   sheet» и «cauldron reagent grid keeps its columns»;
# - возврат drawer-поведения (поле остаётся в комнате, пикер окном) красит
#   «cauldron tap opens the screen», «cauldron screen owns the field»,
#   «cauldron screen dims the room» и «toggle closes back to the room»;
# - лист, лёгший на устье котла (варево не видно), красит «cauldron mouth
#   stays above the tray», а проекция комнаты вместо проекции экрана —
#   «cauldron screen never shrinks the pot»;
# - офсет комнаты 1 меньше половины экрана красит «experiment fills the room»
#   (тот самый «пол экрана ничем не занято»);
# - индексы 4/5 вместо TAB_RATING/TAB_TOOLS в `_on_tab_changed()` красят
#   «rating tab refetches rating» и «tools tab rebuilds tool selection»;
# - плита как ребёнок страницы/хоста и frame_panel панели вкладок красят
#   «room is the whole start screen backdrop» (плита — фон всего экрана);
# - ореол-пятно вместо обводки по контуру (radial-текстура, modulate 0.1)
#   красит «prop outline is visible at rest» и «prop outline hugs the sprite»;
# - заголовок экрана через g._label() с autowrap без границы ширины красит
#   «screen header stays one row» (в HBox минимум Label считается по одной
#   букве и растягивает кнопку «В комнату» в вертикальный пергамент);
# - лоток уже своего содержимого (пересчёт только на открытии, длинный
#   placeholder поиска) красит «brew tray fits the field»;
# - кламп смещения фона в `_apply_focus()` (без него фокус у левого края
#   сдвигает плиту) красит «focused backdrop covers the screen» — по краям
#   видна шапка игры.
# - rect фона по размеру root вместо cover-размера (KEEP_ASPECT_COVERED режет
#   верх и низ плиты) красит «screen backdrop shows the whole plate» и
#   «cauldron art lies inside the plate»: нижняя половина котла исчезала там,
#   где её рисует плита;
# - лоток, который не вмещает своё содержимое по высоте (фиктивная 18-px полоса
#   под котлом), красит «brew tray fits the field» — проверяются обе оси.
# - котёл без приближения (низ прижат к полу плиты, устье уходит под лист)
#   красит «cauldron mouth stays above the tray»;
# - ряд «ВАРИТЬ/↻/✕» шире листа красит «brew controls fit the sheet»: минимум
#   body должен влезать в фактическую ширину лотка;
# - панель и поля в цепочке роутера (PanelContainer с текстурой + отступ
#   MarginContainer) красит «device screen sits on a textured panel»: с
#   удалением bottom-sheet пропали и панель, и отступы, и текст пошёл по
#   краске плиты;
# - любой EXPAND_FILL в цепи ScrollContainer → контент красит
#   «screen width chain expands»: без него контейнер даёт ребёнку его минимум,
#   а минимум autowrap-лейбла — одна буква (кадр windows-hd2: «Верстак»
#   сложился в колонку по 3 знака);
# - autowrap у таблички «УЛУЧШЕНИЯ» красит «upgrades title stays one row»
#   (тот же механизм: сжатый по центру plaque + минимум метки по одной букве).
# - тап-зона с рамкой вместо вырезки (не видно альфы — нечего обводить) красит
#   «prop outline hugs the sprite» и «room prop outline is pale warm gold» в
#   suite_ui_theme: у обводки пропадает texture спрайта и ShaderMaterial;
# - лист с доски без печати-бейджа красит «board keeps its pinned sheet and
#   badge»: узел Overlay_prop_seal_gold перестаёт находиться.

static func run(g: Game) -> void:
	var st_tab := g._tabs_ref.current_tab

	# ---------- навигация: экран вместо вкладок ----------
	Selftest.check("top tab bar hidden", not g._tabs_ref.get_tab_bar().visible)
	Selftest.check("nav five items", g._bottom_nav != null
			and g._bottom_nav._items.size() == 5)
	g._bottom_nav._on_pressed("rating")
	Selftest.check("nav press switches tab",
			g._tabs_ref.current_tab == Game.TAB_RATING)
	var active_mark: ColorRect = g._bottom_nav._items[3]["mark"]
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
	# Доска уже висит в комнате, Аркан ушёл в шапку (полноэкранный), снизу —
	# только то, что открывается в общей панели над баром.
	var nav_keys: Array = []
	for it in g._bottom_nav._items:
		nav_keys.append(it["key"])
	Selftest.check("nav holds friends, no board or arcana",
			nav_keys == ["lab", "world", "friends", "rating", "tools"])
	var filled := true
	for it in g._bottom_nav._items:
		var tex: Texture2D = (it["icon"] as TextureRect).texture
		filled = filled and tex != null and tex.resource_path.contains("/gi_")
	Selftest.check("nav uses filled game-icons", filled)
	# Друзья снизу — общая панель между шапкой и баром, не на весь экран;
	# пункт горит, пока панель открыта, соседний пункт её закрывает.
	g._bottom_nav._on_pressed("rating")
	g._bottom_nav._on_pressed("friends")
	var sp: Control = g._social_ui._screen if g._social_ui != null else null
	var friends_mark: Color = (g._bottom_nav._items[2]["mark"] as ColorRect).color
	Selftest.check("nav friends opens shared panel above the bar", sp != null
			and g._social_ui.is_open() and friends_mark == UIStyle.BRASS
			and sp.offset_top > 0.0 and sp.offset_bottom <= -BottomNav.NAV_H + 0.5)
	var spanel := g.find_child("SocialPanel", true, false) as Control
	await g.get_tree().process_frame
	Selftest.check("friends panel is modal-sized, not the whole area", spanel != null
			and spanel.size.x <= SocialUI.PANEL_MAX.x + 1.0
			and spanel.size.y <= SocialUI.PANEL_MAX.y + 1.0)
	# Иконка бара не прилипает к латунной рейке сверху.
	var nav_icon := g._bottom_nav._items[0]["icon"] as Control
	Selftest.check("nav icons sit below the rail with a gap",
			nav_icon.global_position.y - g._bottom_nav.bar.global_position.y >= 14.0)
	g._bottom_nav._on_pressed("rating")
	Selftest.check("nav sibling closes friends panel",
			not g._social_ui.is_open() and g._tabs_ref.current_tab == Game.TAB_RATING
			and (g._bottom_nav._items[2]["mark"] as ColorRect).color.a == 0.0)
	var arcana_btn := g.find_child("ArcanaBtn", true, false) as Button
	if arcana_btn != null:
		arcana_btn.pressed.emit()
	Selftest.check("header arcana opens sigil arcana", arcana_btn != null
			and g._sigil_ui._sigil_coll != null)
	g._close_sigil_collection()
	await g.get_tree().process_frame
	# Плоская кнопка бара без hover не отвечает на наведение — владелец: «нет
	# адекватных hover интеракций».
	var idle_it: Dictionary = g._bottom_nav._items[1]
	var idle_icon := idle_it["icon"] as TextureRect
	var idle_col := idle_icon.modulate
	(idle_it["btn"] as Button).mouse_entered.emit()
	var hot_col := idle_icon.modulate
	var hot_mark: Color = (idle_it["mark"] as ColorRect).color
	(idle_it["btn"] as Button).mouse_exited.emit()
	Selftest.check("nav hover lights an idle item and restores",
			hot_col != idle_col and hot_mark.a > 0.0
			and idle_icon.modulate == idle_col
			and (idle_it["mark"] as ColorRect).color.a == 0.0)
	# Шапка: иконки вместо слов, без дублей нижнего бара.
	var ether_row := g.find_child("EtherRow", true, false) as Control
	var worded := false
	var row_icons := 0
	if ether_row != null:
		for c in ether_row.get_children():
			if c is Button:
				worded = worded or not String((c as Button).text).strip_edges().is_empty()
				if (c as Button).get_node_or_null("IconCenter") != null:
					row_icons += 1
	Selftest.check("header row uses icons instead of words", ether_row != null
			and not worded and row_icons == 3)
	Selftest.check("header no longer duplicates board and arcana",
			g.find_child("ContractsBtn", true, false) == null
			and g.find_children("Tarot", "", true, false).is_empty())
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
	# Претензия владельца: «так и не появилось бледной обводки вокруг контуров
	# предметов, я не понимаю, как игрок куда может кликнуть». Обводка — кольцо
	# снаружи силуэта, в покое бледное, на наведении разгорается; табличек нет.
	var deck_outline := deck.get_meta("glow", null) as Control
	var rest_alpha := deck_outline.modulate.a if deck_outline != null else -1.0
	Selftest.check("prop outline is visible at rest", deck_outline != null
			and rest_alpha >= SceneProps.OUTLINE_REST - 0.01
			and rest_alpha < SceneProps.OUTLINE_HOVER
			and deck.find_child("PlaqueText", true, false) == null)
	var hot_alpha := rest_alpha
	if deck_outline != null:
		deck.mouse_entered.emit()
		hot_alpha = deck_outline.modulate.a
		deck.mouse_exited.emit()
	Selftest.check("prop outline brightens on hover", deck_outline != null
			and hot_alpha > rest_alpha + 0.2
			and is_equal_approx(deck_outline.modulate.a, rest_alpha))
	# Клик открывает экран поверх предмета: mouse_exited не приходит, и без
	# сброса обводка залипала яркой (претензия владельца).
	if deck_outline != null:
		deck.mouse_entered.emit()
		(deck as Button).pressed.emit()
		g._close_sigil_collection()
		await g.get_tree().process_frame
	Selftest.check("prop outline resets after click without mouse exit",
			deck_outline != null and is_equal_approx(deck_outline.modulate.a, rest_alpha)
			and not bool(deck.get_meta("hot", false)))
	# Запертое устройство Мастерской отвечает тостом: строки статуса на
	# стартовом экране нет, и тап выглядел мёртвым («не работают кнопки»).
	var locked_key := ""
	for k in ["bench", "retort", "spring"]:
		if not g._engine._mode_unlocked(k):
			locked_key = k
			break
	if locked_key != "":
		var toasts_before: int = g._online._toast_stack.get_child_count() if g._online._toast_stack != null else 0
		g._rooms._open_tool(locked_key)
		var toasts_after: int = g._online._toast_stack.get_child_count() if g._online._toast_stack != null else 0
		Selftest.check("locked workshop device answers with a toast", toasts_after > toasts_before)
	# Каждый предмет обведён СВОИМ контуром: тот же силуэт, раздутый по альфе.
	# Претензия владельца: «ореолы квадратные, а не идут по контуру предмета» —
	# квадрат давала тап-зона с рамкой Panel, поэтому пин проверяет, что у
	# обводки есть спрайт-текстура и шейдер, а не стиль-бокс по границе зоны.
	var contour := true
	for prop in [deck, board, scroll_prop]:
		var outline := (prop as Control).get_meta("glow", null) as Control
		var spr := (prop as Control).find_child("Sprite", true, false) as TextureRect
		var mat: ShaderMaterial = null
		if outline != null:
			mat = outline.material as ShaderMaterial
		var hugs := outline != null and spr != null and mat != null
		hugs = hugs and mat.shader != null and outline.texture == spr.texture
		# Кольцо вплотную к силуэту: слой обводки совпадает с rect спрайта.
		# Раздутый rect растягивал текстуру, и обводка отходила от предмета.
		hugs = hugs and outline.offset_left == spr.offset_left
		hugs = hugs and outline.offset_right == spr.offset_right
		hugs = hugs and outline.offset_top == spr.offset_top
		contour = contour and hugs
	Selftest.check("prop outline hugs the sprite", contour)
	# Лист с доски возвращён: владелец просил снять только маленькие бейджи, а
	# вместе с ними ушёл последний лист с печатью-бейджем.
	var board_spr := board.find_child("Sprite", true, false) as TextureRect
	var board_seal := board.find_child("Overlay_prop_seal_gold", true, false) as TextureRect
	Selftest.check("board keeps its pinned sheet and badge", board_spr != null
			and board_spr.texture != null
			and board_spr.texture.resource_path.ends_with("prop_contract.png")
			and board_seal != null and board_seal.texture != null
			and board_seal.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# Обводка только на предметах: ни одна панель/кнопка её не получает.
	Selftest.check("outline lives only on props",
			g.find_children("Glow", "Control", true, false).size()
			== g._rooms._scene_props.size() + g._rooms._props.size())

	# геометрия: поле заполняет комнату, а не висит в её углу
	# (претензия владельца — «пол экрана ничем не занято»)
	var field: Control = g._pages._experiment_field
	var host_h := g._rooms._host.size.y
	Selftest.check("experiment fills the room", host_h > 0.0 and field != null
			and field.get_global_rect().size.y >= host_h * 0.5)

	# ---------- комната из нарисованного фона и предметов ----------
	# Претензия владельца: «это комната, а не прямоугольник в интерфейсе».
	# Плита комнаты — фон под обеими комнатами; предметы стоят на нарисованной
	# мебели (стол слева, доска справа, пол внизу), а не в углах окна.
	g._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	var host_rect := g._rooms._host.get_global_rect()
	# Владелец: плита — ФОН ВСЕГО стартового экрана, а не картинка в рамке
	# вкладки. Она лежит на корне под шапкой и нижним баром, а рамка панели
	# вкладок снята — иначе комната снова становится «прямоугольником в UI».
	Selftest.check("room plate behind the scene", g._rooms._plate != null
			and g._rooms._plate.texture != null
			and g._rooms._plate.get_parent() == g
			and g._rooms._plate.get_index() == 1
			and g._rooms._plate.size.x >= g.size.x - 1.0
			and g._rooms._plate.size.y >= g.size.y - 1.0)
	Selftest.check("room is the whole start screen backdrop",
			g._rooms._plate.visible
			and g._rooms._plate.get_global_rect() == Rect2(Vector2.ZERO, g.size)
			and g._tabs_ref.get_theme_stylebox("panel") is StyleBoxEmpty)
	var deck_uv := (deck.get_global_rect().get_center() - host_rect.position) / host_rect.size
	Selftest.check("deck rests on the table", host_rect.size.x > 0.0
			and deck_uv.x < 0.55 and deck_uv.y > 0.25 and deck_uv.y < 0.55)
	var board_uv := (board.get_global_rect().get_center() - host_rect.position) / host_rect.size
	Selftest.check("contract pinned on the board", host_rect.size.x > 0.0
			and board_uv.x > 0.6 and board_uv.y < 0.5)
	var scroll_uv := (scroll_prop.get_global_rect().get_center() - host_rect.position) / host_rect.size
	# Претензия владельца: «пергамент прямо на котле лежит, а не отдельно». Свиток
	# — на полу у левой стены, и его зона не пересекается с котлом.
	var pot_rect_room := g._pages._experiment_cauldron_art.get_global_rect()
	Selftest.check("scroll lies on the floor", host_rect.size.x > 0.0
			and scroll_uv.y > 0.7 and scroll_uv.x < 0.3
			and not scroll_prop.get_global_rect().grow(-6.0).intersects(pot_rect_room))
	# Котёл — картина в комнате, а живая жидкость рисуется в его устье.
	var cauldron_art: TextureRect = g._pages._experiment_cauldron_art
	var cauldron_uv := Vector2(-1.0, -1.0)
	if cauldron_art != null:
		cauldron_uv = (cauldron_art.get_global_rect().get_center() - host_rect.position) / host_rect.size
	Selftest.check("cauldron stands in the lower half", cauldron_art != null
			and cauldron_art.texture != null
			and cauldron_uv.x > 0.3 and cauldron_uv.x < 0.7 and cauldron_uv.y > 0.5)
	# Предметы комнаты заданы в пикселях опорного разрешения плиты; апскейл
	# текстуры (PLATE_REF_PX) не должен ужимать их вместе с текстурой.
	Selftest.check("cauldron keeps its drawn size after plate upscale",
			cauldron_art != null and cauldron_art.size.x > g.size.x * 0.45
			and cauldron_art.size.y > g.size.y * 0.35)
	Selftest.check("live brew sits in the painted mouth",
			g._pages._experiment_cauldron != null and g._pages._experiment_cauldron.overlay_only
			and cauldron_art != null
			and is_equal_approx(g._pages._experiment_cauldron.size.x, cauldron_art.size.x)
			and is_equal_approx(g._pages._experiment_cauldron.size.y, cauldron_art.size.y)
			and g._pages._experiment_cauldron.get_global_rect().get_center()
					.distance_to(cauldron_art.get_global_rect().get_center()) < 1.0)
	# Поле эксперимента — сама комната: рамки-панели под ним больше нет.
	Selftest.check("experiment field is the room, not a panel",
			field.get_parent() != null and not (field.get_parent() is PanelContainer))
	# Тап по котлу открывает ЭКРАН котла: поле переезжает в хост роутера, комната
	# гаснет целиком, лист реагентов — полоса под котлом без рамки. Модалки нет.
	Selftest.check("cauldron tap target exists", g._pages._experiment_cauldron_btn != null
			and not g._pages._experiment_drawer.visible
			and not g._screens.is_open())
	# Котёл без обводки не читался как кликабельный: тот же контур, что у
	# предметов, — бледный в покое, ярче на наведении и ещё ярче на нажатии.
	var cg: TextureRect = g._pages._experiment_cauldron_glow
	var cb: Button = g._pages._experiment_cauldron_btn
	var c_rest := cg.modulate.a if cg != null else -1.0
	var c_hot := c_rest
	var c_down := c_rest
	if cg != null and cb != null:
		cb.mouse_entered.emit()
		c_hot = cg.modulate.a
		cb.button_down.emit()
		c_down = cg.modulate.a
		cb.button_up.emit()
		cb.mouse_exited.emit()
	Selftest.check("cauldron outline pale at rest, brighter on hover and press",
			cg != null and cg.visible and cg.material is ShaderMaterial
			and cg.texture == g._pages._experiment_cauldron_art.texture
			and c_rest < c_hot and c_hot <= c_down
			and is_equal_approx(cg.modulate.a, c_rest))
	var field_parent := field.get_parent()
	if g._pages._experiment_cauldron_btn != null:
		g._pages._experiment_cauldron_btn.pressed.emit()
	Selftest.check("experiment opens on an unobstructed field",
			g._screens.is_open() and not g._pages._experiment_drawer.visible
			and not g._pages._experiment_cauldron.overlay_only
			and not g._pages._experiment_cauldron_art.visible)
	g._pages._show_experiment_drawer()
	var picker_bounds := g._pages._experiment_drawer.get_global_rect()
	Selftest.check("reagent selection uses the full screen body",
			picker_bounds.size.y >= field.size.y * 0.9)
	g._pages._toggle_experiment_drawer()
	Selftest.check("closing selection returns to the field not the room",
			g._screens.is_open() and field.is_visible_in_tree()
			and not g._pages._experiment_drawer.visible)
	g._pages._set_cauldron_mode("brew", false)
	Selftest.check("brew screen exposes the original animated cauldron and slots",
			g._engine._cauldron.is_visible_in_tree()
			and g._engine._slot_a.is_visible_in_tree()
			and g._engine._slot_b.is_visible_in_tree()
			and g._screens.root.is_ancestor_of(g._engine._cauldron)
			and g._brew_bar.is_visible_in_tree())
	g._pages._set_cauldron_mode("experiment", false)
	var mouth_probe := CauldronView.new()
	g.add_child(mouth_probe)
	mouth_probe.size = Vector2(300, 300)
	Selftest.check("ingredient flight targets the centered painted mouth",
			mouth_probe._mouth_global().distance_to(
					mouth_probe.global_position + Vector2(150, 90)) < 0.1)
	mouth_probe.queue_free()
	Selftest.check("cauldron screen owns the field",
			field.get_parent() == g._screens.host and field.visible)
	Selftest.check("screen header stays one row",
			g._screens.title_label.get_combined_minimum_size().y <= ScreenRouter.HEADER_H)
	Selftest.check("cauldron screen dims the room",
			not g._rooms._plate.is_visible_in_tree()
			and not g._rooms._host.is_visible_in_tree() and not deck.is_visible_in_tree())
	var drawer_sb := g._pages._experiment_drawer.get_theme_stylebox("panel") as StyleBoxTexture
	Selftest.check("reagent selection sits on a complete panel",
			drawer_sb != null and drawer_sb.texture != null)
	var saved_stock := int(g._engine.inventory.get("fire", 0))
	g._engine.inventory["fire"] = saved_stock + 20
	var saved_token_count := g._pages._experiment_tokens.size()
	var saved_filter := g._pages._experiment_filter
	var saved_rng := g._pages._experiment_position_rng.state
	var saved_recent := g._pages._experiment_recent_ids.duplicate()
	g._pages._set_experiment_filter("all")
	g._pages._experiment_position_rng.seed = 8124
	for i in 12:
		g._pages._show_experiment_drawer()
		var cell := g._pages._experiment_reagent_grid.get_node_or_null("ReagentCell_fire") as Button
		if cell != null:
			cell.pressed.emit()
	Selftest.check("selecting reagents returns visible tokens to the field",
			g._pages._experiment_tokens.size() == saved_token_count + 12
			and not g._pages._experiment_drawer.visible
			and g._pages._experiment_cauldron.is_visible_in_tree())
	var field_bounds := Rect2(Vector2.ZERO, field.size)
	var pot_bounds := Rect2(g._pages._experiment_cauldron.position,
			g._pages._experiment_cauldron.size)
	Selftest.check("whole animated pot fits inside the experiment field",
			field_bounds.encloses(pot_bounds) and pot_bounds.size.y >= 170.0)
	var usable_positions := true
	var lowest_token_y := 0.0
	for i in range(saved_token_count, g._pages._experiment_tokens.size()):
		var token: ElementOrb = g._pages._experiment_tokens[i]
		var rect := Rect2(token.position, Vector2(50, 50))
		usable_positions = usable_positions and token.is_visible_in_tree() \
				and field_bounds.encloses(rect) and not rect.intersects(pot_bounds)
		lowest_token_y = maxf(lowest_token_y, rect.end.y)
		for j in range(saved_token_count, i):
			var other: ElementOrb = g._pages._experiment_tokens[j]
			usable_positions = usable_positions and not rect.intersects(
					Rect2(other.position, Vector2(50, 50)))
	Selftest.check("a dozen field reagents do not overlap or collapse to a top strip",
			usable_positions and lowest_token_y > field.size.y * 0.5)
	var original_field_size := field.size
	var original_positions: Array[Vector2] = []
	for token in g._pages._experiment_tokens:
		original_positions.append((token as Control).position)
	var edge_token: ElementOrb = g._pages._experiment_tokens.back()
	field.size = Vector2(720, 1110)
	g._pages._fit_experiment_overlay()
	edge_token.position = Vector2(650, 1000)
	field.size = Vector2(540, 790)
	g._pages._fit_experiment_overlay()
	Selftest.check("shrinking the field keeps an edge reagent reachable",
			Rect2(0, 0, 540, 790).encloses(Rect2(edge_token.position, edge_token.size)))
	field.size = original_field_size
	g._pages._fit_experiment_overlay()
	for i in g._pages._experiment_tokens.size():
		(g._pages._experiment_tokens[i] as Control).position = original_positions[i]
	var dragged: ElementOrb = g._pages._experiment_tokens.back()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(25, 25)
	dragged._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(55, 25)
	dragged._gui_input(motion)
	Selftest.check("field token starts a real drag", dragged._dragging
			and g._pages._experiment_drag_token == dragged)
	var staged_before := g._pages._experiment_cauldron_items.duplicate()
	var token_count_before := g._pages._experiment_tokens.size()
	g._screens.close()
	var restored_position := dragged.position
	g._pages._experiment_tick()
	Selftest.check("closing experiment stops moving the preserved token",
			dragged.position == restored_position)
	Selftest.check("closing experiment cancels orb input state",
			not dragged._dragging and not dragged._pressed
			and g._pages._experiment_drag_token == null)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	g.get_viewport().warp_mouse(g._pages._experiment_cauldron_rect().get_center())
	dragged._input(release)
	Selftest.check("release after closing cannot feed the room cauldron",
			g._pages._experiment_cauldron_items == staged_before
			and g._pages._experiment_tokens.size() == token_count_before)
	g._pages._open_cauldron_screen()
	g.get_viewport().warp_mouse(g._pages._experiment_cauldron_rect().get_center())
	dragged._gui_input(release)
	Selftest.check("release after reopening cannot feed the preserved token",
			g._pages._experiment_cauldron_items == staged_before
			and g._pages._experiment_tokens.size() == token_count_before)
	while g._pages._experiment_tokens.size() > saved_token_count:
		var token: ElementOrb = g._pages._experiment_tokens.pop_back()
		token.free()
	g._pages._experiment_cauldron_items = staged_before
	g._engine.inventory["fire"] = saved_stock
	g._pages._experiment_recent_ids = saved_recent
	g._pages._experiment_position_rng.state = saved_rng
	g._pages._set_experiment_filter(saved_filter)
	var mode_buttons: Dictionary = g._pages._cauldron_mode_buttons
	var lab_parent := g._pages._lab_page.get_parent()
	(mode_buttons["brew"] as Button).pressed.emit()
	g._engine._refresh()
	Selftest.check("brew survives refresh with original controls and recipe book",
			g._screens.key() == "brew" and g._engine._cauldron.is_visible_in_tree()
			and g._engine._book_list.is_visible_in_tree() and g._brew_bar.is_visible_in_tree()
			and g._screens.root.is_ancestor_of(g._engine._brew_btn)
			and (mode_buttons["brew"] as Button).button_pressed)
	g._online._floater_at(g._engine._cauldron._mouth_global(), "+Пар", Color.WHITE)
	var result_floater: Label = g.floaters.back()["l"]
	Selftest.check("result feedback renders above the fullscreen backdrop",
			result_floater.is_visible_in_tree()
			and result_floater.z_index > g._screens.root.z_index
			and result_floater.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	g.floaters.pop_back()
	result_floater.free()
	var lab_scroll := g._pages._lab_page.get_node("LabScroll") as ScrollContainer
	var lab_surface := lab_scroll.get_theme_stylebox("panel") as StyleBoxTexture
	Selftest.check("recipe book and inventory have a textured reading surface",
			lab_surface != null and lab_surface.texture != null
			and lab_surface.get_content_margin(SIDE_LEFT) >= 12.0)
	(mode_buttons["experiment"] as Button).pressed.emit()
	Selftest.check("mode switch returns laboratory and brew bar to their parents",
			g._pages._lab_page.get_parent() == lab_parent
			and g._brew_bar.get_parent() == g and not g._brew_bar.visible
			and field.is_visible_in_tree())
	g._screens.back_btn.pressed.emit()
	Selftest.check("screen back returns field and room",
			not g._screens.is_open() and field.get_parent() == field_parent
			and g._rooms._plate.visible and deck.visible
			and not g._pages._experiment_drawer.visible)

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

	# ---------- экраны механик вместо модалок ----------
	var keys: Array = g._pages._mode_pages.keys()
	Selftest.check("tool pages exist", not keys.is_empty())
	if keys.is_empty():
		g._tabs_ref.current_tab = st_tab
		return
	# Лист (BottomSheet) удалён целиком: он был второй конкурирующей модалкой.
	Selftest.check("no bottom sheet", g.find_child("BottomSheet", true, false) == null
			and g._screens != null and g._screens.root != null)
	# Пробуем экран НЕ выбранной в «Инструментах» страницей: выбранную
	# _apply_tools_selection() оставляет видимой сама, и пин не мог бы погаснуть.
	var probe := "bench" if keys.has("bench") else String(keys[0])
	for k in keys:
		if String(k) != String(g._pages._tools_sel) and g._engine._mode_unlocked(String(k)):
			probe = String(k)
			break
	var box: Control = g._pages._mode_pages[probe]
	var orig_parent := box.get_parent()
	g._pages._open_device_screen(probe, "Проверка")
	Selftest.check("device transition releases the cauldron mode header space",
			is_equal_approx(g._screens.host.position.y, 52.0)
			and is_equal_approx(g._screens.host.size.y,
					g._screens.root.size.y - 52.0 - BottomNav.NAV_H - 6.0))
	# Экран забирает себе фон комнаты, а не висит окном поверх неё.
	Selftest.check("device screen is not a modal", g._screens.is_open()
			and g._screens.node == box and box.get_parent() == g._screens.host_box
			and not g._rooms._plate.visible and not g._rooms._host.visible)
	Selftest.check("device screen has a title bar", g._screens.title_label.text == "Проверка"
			and g._screens.back_btn != null
			and g._screens.root.size.x >= g.size.x - 1.0)
	# Контент экрана обязан лежать на текстурной панели с полями, а не на краске
	# плиты: с удалением bottom-sheet пропали и панель, и отступы, и текст «Верстака»
	# пошёл от края до края поверх доски контрактов и карт (претензия владельца:
	# «вся вёрстка в окнах полетела»). Пин идёт по цепочке родителей, а не по
	# имени узла — иначе он гаснет от переименования, а не от потери панели.
	var anc: Control = box.get_parent() as Control
	var framed: PanelContainer = null
	var padded: MarginContainer = null
	while anc != null and anc != g._screens.root:
		if anc is PanelContainer:
			framed = anc as PanelContainer
		if anc is MarginContainer:
			padded = anc as MarginContainer
		anc = anc.get_parent() as Control
	var framed_sb: StyleBoxTexture = null
	if framed != null:
		framed_sb = framed.get_theme_stylebox("panel") as StyleBoxTexture
	Selftest.check("device screen sits on a textured panel", framed != null
			and framed_sb != null and framed_sb.texture != null
			and framed.visible
			and framed.offset_left > 0.0 and framed.offset_right < 0.0
			and padded != null and padded.get_theme_constant("margin_left") > 0)
	# Структура панели ничего не гарантирует: с ней, но без EXPAND_FILL у ребёнка
	# ScrollContainer текст «Верстака» сложился в колонку по 3 знака (кадр
	# windows-hd2) — минимум autowrap-лейбла равен одной букве. Фактическую
	# ширину в этом прогоне не измерить: Godot пересобирает контейнеры следующим
	# кадром (в кадре приёмки всё сходится, в тесте box.size ещё старое), поэтому
	# пин проверяет само правило распределения ширины — горизонтальный EXPAND_FILL
	# на всех звеньях цепи ScrollContainer → контент.
	var chain: Array = [g._screens.scroll.get_child(0) as Control,
			g._screens.host_box, box]
	var expands := true
	for c in chain:
		if c == null or (int(c.size_flags_horizontal) & Control.SIZE_EXPAND_FILL) == 0:
			expands = false
	Selftest.check("screen width chain expands", expands)
	# Та же механика в окне «Улучшений»: plaque-заголовок центрирован и сжат по
	# содержимому, а autowrap-лейблу минимум считается по одной букве — «УЛУЧШЕНИЯ»
	# стояли вертикальной колонкой (кадр p0-hd/modal_upgrades, дефект из базы).
	var plate := g.find_child("UpgradeTitle", true, false) as Control
	var plate_title: Label = null
	if plate != null and plate.get_child_count() > 0:
		plate_title = plate.get_child(0) as Label
	Selftest.check("upgrades title stays one row", plate_title != null
			and plate_title.get_combined_minimum_size().y <= 36.0)
	# любой _refresh() (через _apply_tools_selection) не должен гасить открытый экран
	g._engine._refresh()
	Selftest.check("device screen survives core refresh", g._screens.is_open() and box.visible)
	# тап по навигации закрывает экран: модалка не переживает смену раздела
	g._bottom_nav._on_pressed("lab")
	Selftest.check("nav press closes screen", not g._screens.is_open())
	g._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	g._pages._open_device_screen(probe, "Проверка")
	var back_btn: Button = g.find_child("ScreenBack", true, false)
	if back_btn != null:
		back_btn.pressed.emit()
	Selftest.check("screen back closes", back_btn != null and not g._screens.is_open()
			and box.get_parent() == orig_parent and g._rooms._plate.visible)

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
	Selftest.check("locked tool explains gate", not g._screens.is_open()
			and not is_instance_valid(g._spring_screen)
			and g._engine.status_text == g._pages._mode_hint("spring"))
	g._engine.inventory["plant"] = 1
	g._rooms.refresh_unlocks()
	Selftest.check("unlocked prop glows again", fountain_btn.modulate == Color.WHITE)
	# Родник — полноэкранный иммерсивный экран, роутер его не заменяет
	g._engine.status_text = ""
	g._rooms._open_tool("spring")
	Selftest.check("spring opens full immersive screen",
			is_instance_valid(g._spring_screen) and not g._screens.is_open())
	if is_instance_valid(g._spring_screen):
		g._spring_screen._close()
	var bench_unlocked := g._engine._mode_unlocked("bench")
	g._rooms._open_tool("bench")
	Selftest.check("workshop prop opens device screen",
			g._screens.is_open() == bench_unlocked)
	if bench_unlocked:
		Selftest.check("workshop room hides behind the screen",
				not g._rooms._host.visible)
	g._screens.close()
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
