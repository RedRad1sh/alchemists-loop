extends RefCounted
class_name Hub
# Хаб попапов (R12): профиль, крафт-подсказки, настройки, журнал, улучшения, престиж.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _up_btn: Button
var _up_popup: Control
var _up_dim: ColorRect
var _up_rows: VBoxContainer
var _profile_dim: Control = null
var _profile_popup: Control = null
var _profile_avatar: Avatar = null
var _profile_nick: LineEdit = null
var _prestige_btn: Button = null
var _prestige_label: Label = null
var _prestige_dim: Control = null
var _prestige_popup: Control = null
var _prestige_confirm_label: Label = null
var _profile_stats: Label = null
# I-1 (T28): предыдущий ник до отправки me() — значение, на которое откатываем
# локальное состояние при серверном отказе.
var _profile_prev_nick := ""
# U25 (re-review #3): «заявка ждёт ответа» — отдельный признак, не пустой prev:
# отказ ПЕРВОГО в жизни ника приходит именно с prev == "", и по одному prev его
# было не отличить от стартового sync me() / онбординга (там откатывать нечего).
var _profile_pending := false
var _log_events: Array = []
var _journal_dim: ColorRect = null
var _journal_popup: CenterContainer = null
var _journal_list: VBoxContainer = null
var _settings_dim: ColorRect = null
var _settings_popup: CenterContainer = null
var _credits_dim: ColorRect = null
var _credits_popup: CenterContainer = null
var _sfx_slider: HSlider = null
var _music_slider: HSlider = null
var _music_toggle: Button = null
var _craftable_dim: ColorRect = null
var _craftable_popup: CenterContainer = null
var _craftable_list: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

# ---------- профиль игрока (ник + аватар) ----------

func _build_profile_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "ProfileDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_profile_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_profile_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(320, 0)
	card.add_child(col)
	var t := g._label("ПРОФИЛЬ АЛХИМИКА", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	_profile_avatar = g._make_avatar(g._online._net_nick, 96)
	_profile_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_profile_avatar)
	_profile_stats = g._label("", 13)
	_profile_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_profile_stats)
	var sub := g._label("Это твоё имя в мире: его видят в ленте первооткрытий и в зале славы. Аватар рисуется из имени.", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	col.add_child(sub)
	_profile_nick = LineEdit.new()
	_profile_nick.custom_minimum_size = Vector2(0, 42)
	_profile_nick.max_length = 24
	_profile_nick.placeholder_text = "Имя алхимика…"
	_profile_nick.add_theme_font_size_override("font_size", 16)
	col.add_child(_profile_nick)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)
	var ok := g._small_button("Сохранить", Vector2(140, 46), 1)
	ok.pressed.connect(_save_profile)
	btns.add_child(ok)
	var cancel := g._small_button("Отмена", Vector2(120, 46))
	cancel.pressed.connect(_close_profile)
	btns.add_child(cancel)

func _open_profile() -> void:
	_profile_nick.text = g._online._net_nick
	_profile_avatar.setup(g._online._net_nick, 96)
	_profile_stats.text = "Веществ %d/%d · Рецептов %d/%d\nДостижения %d/%d · Комплекты %d/4\nЗолото мудрецов %d · Дружба ур. %d\nМировых открытий: %d\nТитул: %s" % [
		g._engine.inventory.size(), g.ITEMS.size(), g._engine.known_recipes.size(), g.RECIPES.size(),
		g._progress_ui._ach_done.size(), Game.ACHIEVEMENTS.size(), g._progress_ui._set_done.size(),
		g._engine.sage_gold, g._spirit._companion_level_for(g._spirit._companion_affinity), g._progress_ui._ach_world_first,
		g._retention._circle_rank_title(g._retention._circle_rank_level())]
	_profile_stats.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_profile_dim.visible = true
	_profile_popup.visible = true
	Sfx.click()

func _close_profile() -> void:
	_profile_dim.visible = false
	_profile_popup.visible = false
	Sfx.click()

func _clean_player_nick(raw: String) -> String:
	# та же нормализация, что на сервере: буквы/цифры/пробел/дефис, 2..24
	var re_bad := RegEx.new()
	re_bad.compile("[^A-Za-zА-Яа-яЁё0-9 _-]")
	var filtered := re_bad.sub(raw, "", true)
	var re_sp := RegEx.new()
	re_sp.compile("\\s+")
	filtered = re_sp.sub(filtered, " ", true).strip_edges()
	if filtered.length() < 2 or filtered.length() > 24:
		return ""
	return filtered

func _save_profile() -> void:
	var filtered := _clean_player_nick(_profile_nick.text)
	if filtered == "":
		g._online._set_status("Имя должно быть 2–24 символа (буквы, цифры, пробел, дефис).")
		return
	# I-1 (T28): «Имя сохранено» печатается только в ok-ветке _on_net_me_result —
	# сервер принимает ник не всегда (400 «Ник уже занят»), и прежний мгновенный
	# успех врал игроку при отказе. Здесь — только нейтральная метка отправки;
	# кейс-мутант «t28 nick save prints no premature success» (краснеет, если
	# вернуть успех в этот метод).
	_profile_prev_nick = g._online._net_nick
	_profile_pending = true
	g._online._net_nick = filtered
	g._saves._save_game()
	g._me_avatar.setup(g._online._net_nick, 24)
	_profile_avatar.setup(g._online._net_nick, 96)
	# метка отправки — ДО Net.me: при пустом base_url очередь сливается
	# offline-результатом синхронно внутри этого вызова, и статус отказа,
	# выставленный обработчиком, не затирается меткой «Отправляю имя…»
	g._online._set_status("Отправляю имя…")
	Net.me(g._online._net_nick, g._online._device_id)
	_close_profile()
	g._online._rebuild_world_grid()

func _on_net_me_result(result: Dictionary) -> void:
	var was_pending := _profile_pending
	var prev := _profile_prev_nick
	_profile_pending = false
	_profile_prev_nick = ""
	if result.get("ok", false) == true:
		var nick := g._clean_str(result.get("nick", ""))
		if nick != "" and nick != g._online._net_nick:
			g._online._net_nick = nick
			if g._me_avatar != null:
				g._me_avatar.setup(g._online._net_nick, 24)
			g._saves._save_game()
		# успех объявляем только своей смене (U25: по флагу заявки, а не по
		# непустому prev — иначе отказ/успех ПЕРВОГО в жизни ника не доходил до
		# игрока): стартовый sync me() (main.gd) и онбординг-ник (spirit.gd)
		# приходят сюда без заявки
		if was_pending:
			g._online._set_status("Имя сохранено: %s. Его видят все алхимики!" % g._online._net_nick)
		# γ: счётчик гостей и недельный подарок приходят вместе с профилем. Отдельного
		# запроса не заводим; офлайн сюда не попадаем вовсе, поэтому поля читаются с
		# дефолтами 0 и [] — подарок просто не начислится без серверного числа.
		g._home._on_house_profile(int(result.get("house_visits_week", 0)),
			result.get("house_visitors", []))
		return
	# Отказ/офлайн, пришедший НЕ в ответ на заявку игрока — молча игнорируем
	# (поведение до T28): откатывать на чужую отправку нечего.
	if not was_pending:
		return
	# I-1 (T28): ветка отказа. Мутация «удалить ветку отказа (оставить только
	# if ok, успех — как в BASE — печатать в _save_profile)» красит кейс
	# «t28 rejected nick rolls back»: статус остаётся успехным и ник не откатан.
	if result.get("offline", false) == true:
		g._online._set_status("Сервер не ответил, имя не принято.")
	else:
		var detail := String(result.get("detail", ""))
		if detail != "":
			g._online._set_status("Имя не принято: " + detail)
		else:
			g._online._set_status("Имя не принято.")
	g._online._net_nick = prev
	if g._me_avatar != null:
		g._me_avatar.setup(g._online._net_nick, 24)
	if _profile_avatar != null:
		_profile_avatar.setup(g._online._net_nick, 96)
	# U25 (re-review #3): поле диалога возвращаем тоже. Пока заявка в полёте,
	# игрок успевает открыть профиль (_open_profile печатает в поле текущий
	# _net_nick = ужеRejected), и без этой строки отказ повесил бы непринятое
	# имя в открытой форме. Различник — тот же кейс сюиты (третий конъюнкт).
	if _profile_nick != null:
		_profile_nick.text = prev
	g._saves._save_game()


# ---------- что варить сейчас ----------

func _craftable_pairs(limit: int = 5) -> Array:
	var out: Array = []
	for r in g.RECIPES:
		if out.size() >= limit:
			break
		var a := String(r["a"])
		var b := String(r["b"])
		if int(g._engine.inventory.get(a, 0)) < 1 or int(g._engine.inventory.get(b, 0)) < 1:
			continue
		if g._engine.known_recipes.has(g._pair_key(a, b)):
			continue
		out.append({"a": a, "b": b, "out": String(r["out"])})
	return out

func _build_craftable_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "CraftableDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_craftable_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_craftable_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(360, 0)
	card.add_child(col)
	var t := g._label("ЧТО ВАРИТЬ СЕЙЧАС?", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var sub := g._label("Пары из твоих запасов, которые ты ещё не пробовал. Тап — и они встанут в котёл.", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_craftable_list = VBoxContainer.new()
	_craftable_list.add_theme_constant_override("separation", 6)
	_craftable_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_craftable_list)
	var credits_btn := g._small_button("О игре / Credits", Vector2(0, 40))
	credits_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	credits_btn.pressed.connect(_open_credits)
	col.add_child(credits_btn)
	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_craftable_dim.visible = false
		_craftable_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _open_craftable() -> void:
	_rebuild_craftable_rows()
	_craftable_dim.visible = true
	_craftable_popup.visible = true
	Sfx.click()

func _rebuild_craftable_rows() -> void:
	for child in _craftable_list.get_children():
		_craftable_list.remove_child(child)
		child.queue_free()
	var pairs := _craftable_pairs()
	if pairs.is_empty():
		var none := g._label("Все доступные пары уже опробованы.\nОткрой новые вещества в Эксперименте или добудь их из источников.", 13)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		_craftable_list.add_child(none)
		return
	for p in pairs:
		var a := String(p["a"])
		var b := String(p["b"])
		var btn := Button.new()
		btn.text = "%s + %s → ?" % [g._online._item_name(a), g._online._item_name(b)]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.add_theme_font_size_override("font_size", 15)
		if g._font_semi != null:
			btn.add_theme_font_override("font", g._font_semi)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.11, 0.16, 0.9)
		sb.set_corner_radius_all(14)
		sb.border_color = Color(0.35, 0.55, 0.5, 0.5)
		sb.set_border_width_all(1)
		var sb_h: StyleBoxFlat = sb.duplicate()
		sb_h.bg_color = Color(0.13, 0.18, 0.25, 1)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("pressed", sb_h)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(0.8, 0.95, 0.86))
		btn.pressed.connect(_try_craftable_pair.bind(a, b))
		_craftable_list.add_child(btn)

func _try_craftable_pair(a: String, b: String) -> void:
	_craftable_dim.visible = false
	_craftable_popup.visible = false
	if not g._online._has_ingredients(a, b):
		g._engine.status_text = "Не хватает ингредиентов: %s + %s." % [g._online._item_name(a), g._online._item_name(b)]
		Sfx.error()
		g._engine._refresh()
		return
	g._engine.selected = [a, b]
	g._engine._refresh()
	g._engine.status_text = "Попробуй: %s + %s — жми «ВАРИТЬ»." % [g._online._item_name(a), g._online._item_name(b)]
	Sfx.click()

# ---------- настройки ----------

func _build_settings_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "SettingsDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_settings_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_settings_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(330, 0)
	card.add_child(col)
	var t := g._label("НАСТРОЙКИ", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	_music_toggle = g._small_button("Музыка: вкл", Vector2(0, 42))
	_music_toggle.pressed.connect(func() -> void:
		var on := Sfx.toggle_music()
		_music_toggle.text = "Музыка: вкл" if on else "Музыка: выкл"
		g._saves._save_game())
	col.add_child(_music_toggle)
	col.add_child(g._label("Громкость эффектов", 13))
	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.05
	_sfx_slider.value = Sfx.sfx_volume
	_sfx_slider.value_changed.connect(func(v: float) -> void:
		Sfx.set_sfx_volume(v)
		g._saves._save_game())
	col.add_child(_sfx_slider)
	col.add_child(g._label("Громкость музыки", 13))
	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.05
	_music_slider.value = Sfx.music_volume
	_music_slider.value_changed.connect(func(v: float) -> void:
		Sfx.set_music_volume(v)
		g._saves._save_game())
	col.add_child(_music_slider)
	var hint := g._label("Настройки сохраняются автоматически.", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
	col.add_child(hint)
	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_settings_dim.visible = false
		_settings_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _open_settings() -> void:
	_music_toggle.text = "Музыка: вкл" if Sfx.music_on else "Музыка: выкл"
	_sfx_slider.value = Sfx.sfx_volume
	_music_slider.value = Sfx.music_volume
	_settings_dim.visible = true
	_settings_popup.visible = true
	Sfx.click()

# ---------- О игре / Credits (заглушка) ----------

func _build_credits_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "CreditsDim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 30
	dim.visible = false
	g.add_child(dim)
	_credits_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 31
	center.visible = false
	g.add_child(center)
	_credits_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(340, 0)
	card.add_child(col)
	var ttl := g._label("О ИГРЕ / CREDITS", 20)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ttl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(ttl)
	# Заглушка: централизованное место про шрифты/тему, чтобы не забыть.
	# Дальше — дизайн (портрет авторов, лицензии, ссылки).
	var fonts_line := "Шрифты: Manrope (UI), Divagon (названия), Manasco (лор)"
	var fl := g._label(fonts_line, 12)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	col.add_child(fl)
	var ver := g._label("Версия: MVP", 12)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	col.add_child(ver)
	# Превью шрифтов: Divagon на названии, Manasco на лоре.
	var prev1 := g._label("Алхимический Сигил", 18)
	prev1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if g._font_display != null:
		prev1.add_theme_font_override("font", g._font_display)
	col.add_child(prev1)
	var prev2 := g._label("Лор: зелье, сплавленное из огня и тени…", 12)
	prev2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prev2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if g._font_lore != null:
		prev2.add_theme_font_override("font", g._font_lore)
	col.add_child(prev2)
	var close := g._small_button("Закрыть", Vector2(140, 42))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_credits_dim.visible = false
		_credits_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _open_credits() -> void:
	if _credits_dim == null:
		_build_credits_popup()
	_credits_dim.visible = true
	_credits_popup.visible = true
	Sfx.click()

# ---------- журнал событий ----------

func _log_event(text: String) -> void:
	_log_events.push_front({"t": Time.get_datetime_string_from_system(false).substr(11, 5), "text": text})
	if _log_events.size() > 40:
		_log_events.resize(40)

func _build_journal_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "JournalDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_journal_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_journal_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(370, 0)
	card.add_child(col)
	var t := g._label("ЖУРНАЛ АЛХИМИКА", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_journal_list = VBoxContainer.new()
	_journal_list.add_theme_constant_override("separation", 5)
	_journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_journal_list)
	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_journal_dim.visible = false
		_journal_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _open_journal() -> void:
	_rebuild_journal_rows()
	_journal_dim.visible = true
	_journal_popup.visible = true
	Sfx.click()

func _rebuild_journal_rows() -> void:
	for child in _journal_list.get_children():
		_journal_list.remove_child(child)
		child.queue_free()
	if _log_events.is_empty():
		var none := g._label("Пока пусто — сделай первую варку!", 13)
		none.add_theme_color_override("font_color", Color(0.6, 0.66, 0.72))
		_journal_list.add_child(none)
		return
	for e in _log_events:
		var d := e as Dictionary
		var lbl := g._label("%s · %s" % [String(d.get("t", "")), String(d.get("text", ""))], 13)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_journal_list.add_child(lbl)

# ---------- R4: см. game/progress.gd (2238-2521) ----------

# ---------- улучшения (попап) ----------

func _build_upgrade_popup() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_up_dim = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_up_popup = center

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(330, 0)
	card.add_child(col)

	var t := g._label("УЛУЧШЕНИЯ", 21)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var hint := g._label("Покупается за эфир и действует вечно. Излишек над капом попадает в резерв и тратится здесь.", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_up_rows = VBoxContainer.new()
	_up_rows.add_theme_constant_override("separation", 8)
	_up_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_up_rows)

	_prestige_btn = g._small_button("⚗ Перегонка", Vector2(0, 46), 2)
	_prestige_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prestige_btn.pressed.connect(_open_prestige_confirm)
	col.add_child(_prestige_btn)
	_prestige_label = g._label("", 12)
	_prestige_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_prestige_label)

	var close := g._small_button("Закрыть", Vector2(150, 44))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		_up_dim.visible = false
		_up_popup.visible = false
		Sfx.click())
	col.add_child(close)

func _build_prestige_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "PrestigeDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_prestige_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
	center.visible = false
	g.add_child(center)
	_prestige_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(320, 0)
	card.add_child(col)
	var t := g._label("ПЕРЕГОНКА", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	col.add_child(t)
	_prestige_confirm_label = g._label("", 13)
	_prestige_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_prestige_confirm_label)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)
	var ok := g._small_button("Перегнать", Vector2(140, 46), 2)
	ok.pressed.connect(_do_prestige)
	btns.add_child(ok)
	var cancel := g._small_button("Отмена", Vector2(120, 46))
	cancel.pressed.connect(func() -> void:
		_prestige_dim.visible = false
		_prestige_popup.visible = false
		Sfx.click())
	btns.add_child(cancel)

func _open_upgrades() -> void:
	_rebuild_up_rows()
	_refresh_prestige_ui()
	_up_dim.visible = true
	_up_popup.visible = true
	Sfx.click()

func _prestige_gain() -> int:
	if g._engine.inventory.size() < Game.PRESTIGE_MIN:
		return 0
	return int(floor(float(g._engine.inventory.size() - Game.PRESTIGE_MIN) / 5.0)) + 1

func _refresh_prestige_ui() -> void:
	if _prestige_btn == null:
		return
	var gain := _prestige_gain()
	if gain <= 0:
		_prestige_btn.disabled = true
		_prestige_label.text = "«Перегонка» откроется на %d веществах (сейчас %d)." % [Game.PRESTIGE_MIN, g._engine.inventory.size()]
		_prestige_label.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
		return
	_prestige_btn.disabled = false
	_prestige_label.text = "Сброс → +%d Золота мудрецов (сейчас %d). Регенерация ×%.2f, кап +%d." % [
		gain, g._engine.sage_gold, g._engine._sage_multiplier(), 40 * g._engine.sage_gold]
	_prestige_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))

func _open_prestige_confirm() -> void:
	# U9 (T12): под престижем спит корутина варки/производства и может висеть
	# эксперимент — сброс до их завершения недопустим, показываем причину отказа.
	if g._engine.brewing or g._engine._auto or g._engine._experiment_pending_pair.size() == 2:
		g._online._set_status("Перегонка недоступна: идёт варка, производство или ждёт ответа эксперимент. Дождись завершения.")
		Sfx.error()
		return
	var gain := _prestige_gain()
	if gain <= 0:
		return
	_prestige_confirm_label.text = "Котёл перегонит лабораторию в чистое золото мудрецов.\n\nТеряешь: вещества, рецепты, улучшения и текущий эфир.\nСохраняешь: резерв, архивные печати, достижения, комплекты, дружбу Светика, имя.\n\nПолучишь: +%d Золота мудрецов (навсегда)." % gain
	_prestige_dim.visible = true
	_prestige_popup.visible = true
	Sfx.click()

func _do_prestige() -> void:
	var gain := _prestige_gain()
	if gain <= 0:
		return
	g._engine.sage_gold += gain
	g._engine.inventory.clear()
	for b in Game.BASE_IDS:
		g._engine.inventory[b] = 3
	g._engine.known_recipes.clear()
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	g._engine.known_recipes[g._pair_key("earth", "fire")] = true
	g._engine.upgrades.clear()
	g._engine._craft_job.clear()
	g._engine._blueprints.clear()
	g._engine.ether = Game.START_ETHER
	g._engine.attempts = 0
	g._engine.successes = 0
	g._engine.selected.clear()
	g._engine.brewing = false
	# U9 (T12): сонные корутины варки/верстака/автоплана видят смену поколения
	# и молча выходят без коммита; bookkeeping эксперимента не переживает сброс.
	g._engine.brew_epoch += 1
	g._engine._experiment_pending_pair.clear()
	# U11 (T14): престиж аннулирует и pending-записи мир-запросов в полёте.
	g._online._pending_requests.clear()
	g._engine._source_taps = 0
	g._engine.spring_on = false
	g._engine.spring_source = "water"
	g._pages._bench_target = ""
	g._pages._bench_on = false
	g._guild._quests_done.clear()
	g._guild._quest_brew.clear()
	g._guild._quest_tier.clear()
	g._guild._quest_challenge = 0
	g._guild._order_done.clear()
	g._engine._layer_cache.clear()
	g._engine._cost_cache.clear()
	_prestige_dim.visible = false
	_prestige_popup.visible = false
	g._saves._save_game()
	g._engine._refresh()
	g._pages._ensure_modes()
	g._spirit._companion_react("prestige", str(gain))
	g._online._set_status("ПЕРЕГОНКА: +%d Золота мудрецов! Теперь у тебя %d." % [gain, g._engine.sage_gold])
	_log_event("Перегонка: +%d Золота мудрецов (всего %d)" % [gain, g._engine.sage_gold])
	Sfx.legendary()

func _rebuild_up_rows() -> void:
	if _up_rows == null:
		return
	for child in _up_rows.get_children():
		_up_rows.remove_child(child)
		child.queue_free()
	for u in Game.UPGRADES:
		_up_rows.add_child(_up_row(u))
	_up_rows.add_child(_mastery_row())

func _mastery_row() -> Button:
	var cost := g._engine._mastery_cost()
	var b := g._small_button("✦ Архивная печать · ранг %d\n%d ⚡ из эфира или резерва\n%s" % [g._engine.mastery_rank, cost, _mastery_next_benefit(g._engine.mastery_rank)], Vector2(0, 62), 1)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = g._engine._available_ether() < cost
	b.pressed.connect(g._engine._buy_mastery)
	return b

func _mastery_next_benefit(rank: int) -> String:
	# A2: печать продаёт время и параллелизм — строка обязана называть
	# ближайший реальный порог, а не абстрактную «силу».
	var nxt := rank + 1
	if Game.MASTERY_STAGE_RANKS.has(nxt):
		return "Ранг %d: этап автоварки %d → %d операций." % [nxt, g._engine._stage_ops(), g._engine._stage_ops() + 1]
	if nxt == Game.MASTERY_RETORT_SLOT_RANK:
		return "Ранг %d: четвёртый сосуд реторты." % nxt
	if nxt == 1:
		return "Ранг %d: новый титул в архиве, выгода — со 2-го." % nxt
	return "Ранг %d: реторта зреет на %d %% быстрее." % [nxt, int(round(Game.MASTERY_RETORT_SPEED * 100.0))]

func _up_row(u: Dictionary) -> Button:
	var id := String(u["id"])
	var lvl := g._engine._up_lvl(id)
	var mx := int(u["max"])
	var unlocked := g._engine._up_unlocked(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.9)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.3, 0.4, 0.5, 0.35)
	sb.set_border_width_all(1)
	var sb_h: StyleBoxFlat = sb.duplicate()
	sb_h.bg_color = Color(0.13, 0.18, 0.25, 1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var key_item := String(u.get("unlock", ""))
	if key_item != "":
		hb.add_child(g._engine._mini_orb(key_item, 42))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(120, 0)
	hb.add_child(col)
	var nm := g._label("%s · ур. %d/%d" % [String(u["name"]), lvl, mx], 16)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var ds := g._label(String(u["desc"]), 12)
	ds.add_theme_color_override("font_color", Color(0.62, 0.68, 0.74))
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ds)
	var st := g._label("", 13)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(st)
	if not unlocked:
		st.text = "Откроется вместе с «%s»" % g._online._item_name(key_item)
		st.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		b.disabled = true
		nm.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	elif lvl >= mx:
		st.text = "максимум"
		st.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	else:
		var cost := g._engine._up_cost(id)
		st.text = "Стоимость: %d ⚡" % cost
		st.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9) if g._engine._available_ether() >= cost else Color(0.75, 0.6, 0.55))
		b.pressed.connect(g._engine._buy_upgrade.bind(id))
	return b
