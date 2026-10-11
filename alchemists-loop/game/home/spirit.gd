extends RefCounted
class_name Spirit
# Дух-компаньон Светик (R9): диалоги, реакции, дружба, уровни, имя игрока.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _companion = null
var _companion_met := false
var _companion_unlocked := false
var _spirit_name := "Светик"
var _player_name := ""
var _companion_idle_clock := 0.0
var _companion_dim: ColorRect = null
var _companion_dlg: Control = null
var _companion_dlg_title: Label = null
var _companion_dlg_text: Label = null
var _companion_dlg_name: LineEdit = null
var _companion_dlg_name_row: HBoxContainer = null
var _companion_dlg_aff: Label = null
var _companion_affinity := 0
var _companion_level := 1

func _init(game: Game) -> void:
	g = game

# ================= дух-компаньон =================

func _build_companion() -> void:
	_companion = (load("res://game/home/companion.gd") as GDScript).new()
	_companion.name = "Companion"
	_companion.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# компактный маскот в правом верхнем углу (конец панели вкладок) — контент не трогаем
	_companion.offset_left = -72.0
	_companion.offset_right = -8.0
	# Отдельное место между эфиром и вкладками: Светик не попадает
	# под навигацию и не закрывает кнопки поля.
	_companion.offset_top = 100.0
	_companion.offset_bottom = 164.0
	_companion.z_index = 3
	_companion.tapped.connect(_on_companion_tapped)
	g.add_child(_companion)
	_companion.visible = false

func _build_companion_dialog() -> void:
	_companion_dim = ColorRect.new()
	_companion_dim.name = "CompanionDim"
	_companion_dim.color = Color(0, 0, 0, 0.6)
	_companion_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_companion_dim.z_index = 8
	_companion_dim.visible = false
	g.add_child(_companion_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 9
	center.visible = false
	g.add_child(center)
	_companion_dlg = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(300, 0)
	card.add_child(col)
	var room_tex := g._ui_texture("res://game/spirits/room.png")
	if room_tex != null:
		var room := TextureRect.new()
		room.texture = room_tex
		room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		room.custom_minimum_size = Vector2(0, 118)
		room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(room)
	_companion_dlg_title = g._label(_spirit_name, 22)
	_companion_dlg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_companion_dlg_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	col.add_child(_companion_dlg_title)
	_companion_dlg_text = g._label("", 15)
	_companion_dlg_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_companion_dlg_text)
	_companion_dlg_aff = g._label("", 12)
	_companion_dlg_aff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_companion_dlg_aff.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
	col.add_child(_companion_dlg_aff)
	_companion_dlg_name_row = HBoxContainer.new()
	_companion_dlg_name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_companion_dlg_name_row.add_theme_constant_override("separation", 8)
	col.add_child(_companion_dlg_name_row)
	_companion_dlg_name = LineEdit.new()
	_companion_dlg_name.placeholder_text = "Твоё имя, алхимик…"
	_companion_dlg_name.custom_minimum_size = Vector2(170, 42)
	_companion_dlg_name.add_theme_font_size_override("font_size", 15)
	_companion_dlg_name_row.add_child(_companion_dlg_name)
	var ok_name := g._small_button("Познакомиться", Vector2(0, 42), 2)
	ok_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_name.pressed.connect(_companion_on_name_ok)
	_companion_dlg_name_row.add_child(ok_name)
	_companion_dlg_name_row.visible = false
	var hint_b := g._small_button("Подсказка Светика · %d ⚡" % Game.HINT_COST, Vector2(0, 44), 2)
	hint_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_b.tooltip_text = "Светик отметит полезные вещества в окне выбора"
	hint_b.pressed.connect(_companion_hint)
	col.add_child(hint_b)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	# В окне остаётся одно основное действие — платная подсказка;
	# разговор является вторичной кнопкой.
	var chat_b := g._small_button("Поболтать", Vector2(0, 44), 0)
	chat_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_b.pressed.connect(_companion_chat)
	actions.add_child(chat_b)
	var close_b := g._small_button("Закрыть", Vector2(0, 44), 0)
	close_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_b.pressed.connect(_companion_close_dialog)
	actions.add_child(close_b)

func _refresh_companion_visible() -> void:
	if _companion != null:
		var on_lab := g._tabs_ref == null or g._tabs_ref.current_tab == Game.TAB_EXPERIMENT or g._tabs_ref.current_tab == Game.TAB_LAB
		_companion.visible = on_lab and _companion_unlocked
		# У верхней шапки нет свободного места для всплывающего облачка:
		# текст Светика живёт в его окне общения и не закрывает навигацию.
		_companion.set_bubble_allowed(false)
		if not _companion.visible:
			_companion.set_shake(false)
			_companion.set_process(false)


func _companion_unlock() -> void:
	if _companion_unlocked:
		return
	_companion_unlocked = true
	_refresh_companion_visible()
	g._saves._save_game()
	g._hub._log_event("Светик пробудился из первой искры!")
	g._engine.status_text = "Искра вспыхнула — и в ней проснулся Светик!"
	_companion_hello()


func _companion_hello() -> void:
	_refresh_companion_visible()
	if not _companion_unlocked:
		return
	var on_lab := g._tabs_ref == null or g._tabs_ref.current_tab == Game.TAB_EXPERIMENT or g._tabs_ref.current_tab == Game.TAB_LAB
	if not on_lab:
		return
	if g._demo_harness._demo:
		_companion.say("Привет! Я — %s. Давай сварим что-нибудь!" % _spirit_name, "idle")
		return
	if not _companion_met:
		_companion.say("О! Наконец-то. Я — Светик, что не гаснет в твоём котле.", "idle")
		_companion_open_dialog("А тебя как звать, алхимик?", true)
	else:
		var rl := g._retort._retort_hello_line()
		if rl != "":
			_companion.say(rl, "happy")
		else:
			var suffix := (", " + _player_name) if _player_name != "" else ""
			_companion.say("С возвращением%s! Котёл соскучился." % suffix, "happy")

func _on_companion_tapped() -> void:
	if _companion_met:
		_companion_open_dialog(_companion_line("chat", ""), false)
	else:
		_companion_open_dialog("А тебя как звать, алхимик?", true)

func _companion_affinity_line() -> String:
	var lv := _companion_level_for(_companion_affinity)
	var next := 0
	if lv == 1:
		next = 10
	elif lv == 2:
		next = 30
	elif lv == 3:
		next = 60
	if next > 0:
		return "Дружба: ур. %d · %d очков · до ур. %d ещё %d" % [lv, _companion_affinity, lv + 1, next - _companion_affinity]
	return "Дружба: ур. %d · %d очков — лучшие друзья!" % [lv, _companion_affinity]

func _companion_open_dialog(text: String, ask_name: bool) -> void:
	if _companion_dlg == null or _companion_dim == null:
		return
	_companion_dlg_text.text = text
	_companion_dlg_name_row.visible = ask_name
	if ask_name:
		_companion_dlg_name.text = ""
	_companion_dlg_title.text = _spirit_name
	if _companion_dlg_aff != null:
		_companion_dlg_aff.text = _companion_affinity_line()
	_companion_dim.visible = true
	_companion_dlg.visible = true
	if _companion != null:
		_companion.z_index = 10

func _companion_close_dialog() -> void:
	if _companion_dim != null:
		_companion_dim.visible = false
	if _companion_dlg != null:
		_companion_dlg.visible = false
	if _companion != null:
		_companion.z_index = 3
	Sfx.click()

func _companion_on_name_ok() -> void:
	var pname := _companion_dlg_name.text.strip_edges()
	if pname == "":
		pname = "Алхимик"
	_companion_set_name(pname)
	_companion_dlg_name_row.visible = false
	_companion_dlg_text.text = "Рад знакомству, %s! Я — %s. Теперь котёл у нас общий." % [_player_name, _spirit_name]
	_companion.say(_companion_dlg_text.text, "happy")
	Sfx.legendary()

func _companion_set_name(pname: String) -> bool:
	_player_name = pname
	# то же имя пишем в профиль (ник в мире), если оно валидно
	var nn := g._hub._clean_player_nick(pname)
	if nn != "":
		var prev_nick := g._online._net_nick
		g._online._net_nick = nn
		if g._me_avatar != null:
			g._me_avatar.setup(g._online._net_nick, 24)
		if g._hub._profile_avatar != null:
			g._hub._profile_avatar.setup(g._online._net_nick, 96)
		if g._online._net_enabled:
			# U25 (re-review, Critical #1): сервер принимает ник не всегда (400
			# «Ник уже занят» — и проверка занятости, и IntegrityError-гонка в
			# set_me), поэтому онбординг идёт через тот же контракт заявки, что и
			# диалог профиля: hub._on_net_me_result при отказе откатывает на
			# prev_nick и печатает причину, при успехе принимает серверный
			# канонический ник. Без флага ответ уходил в молчание (там prev ==
			# "" — защита стартового sync me()), и мир продолжал показывать
			# чужой ник.
			g._hub._profile_prev_nick = prev_nick
			g._hub._profile_pending = true
			Net.me(g._online._net_nick, g._online._device_id)
	var names := ["Светик"]
	_spirit_name = String(names[randi() % names.size()])
	_companion_met = true
	_companion_affinity = maxi(_companion_affinity, 3)
	if _companion != null:
		_companion_apply_level()
	if _companion_dlg_title != null:
		_companion_dlg_title.text = _spirit_name
	g._saves._save_game()
	return true

func _companion_hint() -> void:
	if g._pages == null:
		return
	var bought := g._pages._hint()
	if bought and _companion_dlg_text != null:
		_companion_dlg_text.text = "Я отметил нужные вещества. Загляни в окно выбора, алхимик."


func _companion_chat() -> void:
	_companion_dlg_text.text = _companion_line("chat", "")
	_companion.say(_companion_dlg_text.text, "idle")

func _companion_react_discovery(item_id: String) -> void:
	var r := g._engine._rarity_of(item_id)
	if int(r["tier"]) >= 4:
		_companion_react("legendary", g._online._item_name(item_id))
	elif int(r["tier"]) >= 3:
		_companion_react("epic", g._online._item_name(item_id))
	else:
		_companion_react("success_new", g._online._item_name(item_id))

func _companion_react(kind: String, arg: String) -> void:
	if _companion == null or not _companion_unlocked:
		return
	_companion_idle_clock = 0.0
	var line := _companion_line(kind, arg)
	var skey := _companion_sprite(kind)
	if _companion.visible and line != "":
		_companion.say(line, _companion_mood(kind))
		_companion.set_sprite(skey, 4.0)

func _companion_sprite(kind: String) -> String:
	match kind:
		"challenge_win":
			return "charged"
		"success_new", "named":
			return "laugh"
		"epic":
			return "laugh"
		"legendary":
			return "charged"
		"milestone":
			return "content"
		"quest_done":
			return "laugh"
		"achievement":
			return "content"
		"set_done":
			return "charged"
		"order_done":
			return "content"
		"offline":
			return "content"
		"prestige":
			return "charged"
		"success_known", "hint":
			return "content"
		"fail":
			return "sad"
		"poor", "nohint":
			return "sad_soft"
		"world_first":
			return "charged"
		"chat":
			return "curious"
		"idle":
			return "neutral2"
		_:
			return "idle"

func _companion_mood(kind: String) -> String:
	match kind:
		"challenge_win", "success_new", "world_first", "named":
			return "amazed"
		"epic", "legendary":
			return "amazed"
		"milestone":
			return "happy"
		"quest_done":
			return "amazed"
		"achievement":
			return "happy"
		"set_done":
			return "amazed"
		"order_done":
			return "happy"
		"offline":
			return "happy"
		"prestige":
			return "amazed"
		"success_known", "hint":
			return "happy"
		"fail", "poor", "nohint":
			return "sad"
		_:
			return "idle"

func _companion_line(kind: String, arg: String) -> String:
	var arr: Array = []
	match kind:
		"idle":
			arr = [
				"Котёл скучает. А скучающий котёл — грустный котёл.",
				"Помни: источники внизу — добывай их почаще.",
				"Туман — не конец. Это намёк, что путь другой.",
				"Слышал, где-то в мире варят что-то новое…",
			]
		"success_new":
			arr = [
				"Ого, «%s»! Смотри, как искрится." % arg,
				"«%s» — новенькое в книге. Горжусь!" % arg,
				"Тише… «%s». Мир станет чуть интереснее." % arg,
			]
		"success_known":
			arr = [
				"«%s» мы уже знаем. Котёл доволен." % arg,
				"Опять «%s»? Надёжное вещество." % arg,
			]
		"fail":
			arr = [
				"Туман, бывает. Даже у лучших.",
				"Не вышло. Подмешай воду — она всё смягчает.",
				"Эх. Попробуй другую пару — котёл подскажет.",
			]
		"world_first":
			arr = [
				"Тише… слышишь? Мир тебя запомнил. «%s» — твоё, первое во всех петлях!" % arg,
				"ПЕРВООТКРЫТИЕ «%s»! Твоё имя теперь в истории!" % arg,
			]
		"hint":
			arr = [
				"Держи ниточку: %s." % arg,
				"Шёпот котла: %s." % arg,
				"Только между нами: %s." % arg,
			]
		"poor":
			arr = [
				"Я не буду раскрывать рецепт бесплатно. Попробуй Эксперимент.",
				"Сначала найди пару сам — так открытие останется твоим.",
			]
		"nohint":
			arr = [
				"Подсказывать нечего — сначала открой новые вещества.",
			]
		"challenge_win":
			arr = [
				"ЕЖЕДНЕВНАЯ ЦЕЛЬ «%s» выполнена! Держи награду." % arg,
				"Цель дня «%s» закрыта. Котёл доволен!" % arg,
			]
		"epic":
			arr = [
				"«%s» — ЭПИЧЕСКОЕ вещество! Такое не каждый день рождается." % arg,
				"Ого, «%s»! Глубина награждает щедро." % arg,
			]
		"legendary":
			arr = [
				"«%s» — ЛЕГЕНДАРНОЕ! Сам туман расступился перед тобой." % arg,
				"Легенда в твоём котле: «%s»! Награда — королевская." % arg,
			]
		"milestone":
			arr = [
				"%s веществ в атласе! Ты растёшь на глазах." % arg,
				"Веха: %s! Держи награду — заслужил." % arg,
				"Атлас полнится: уже %s веществ." % arg,
			]
		"quest_done":
			arr = [
				"Задание «%s» готово! Возьми награду — заслужил." % arg,
				"«%s» выполнено! Светик искрится от радости." % arg,
				"Ещё один шаг позади: «%s»." % arg,
			]
		"achievement":
			arr = [
				"Достижение «%s»! Котёл гордится тобой." % arg,
				"«%s» — запишем в летопись лаборатории." % arg,
			]
		"set_done":
			arr = [
				"Комплект «%s» собран! Стихия подчинилась тебе." % arg,
				"«%s» — вся стихия в твоей книге. Впечатляет!" % arg,
			]
		"order_done":
			arr = [
				"Заказ гильдии на «%s» готов. Золото течёт!" % arg,
				"«%s» для гильдии — сварено. Отличная работа." % arg,
			]
		"offline":
			arr = [
				"Ты вернулся! Котёл всё это время копил эфир: %s ⚡." % arg,
				"С возвращением! Пока тебя не было — +%s ⚡." % arg,
			]
		"prestige":
			arr = [
				"Перегонка! +%s золота мудрецов. Начнём с чистого котла!" % arg,
				"Мудрецы приняли твой дар: +%s золота. Путь снова открыт." % arg,
			]
		"chat":
			arr = [
				"Я живу в каждой твоей искре.",
				"Алхимия — это спор с туманом. Пока выигрываем.",
				"Мир большой. Один ты — уже целая история.",
				"Сваришь огонь с водой? Классика!",
				"Знаешь, что самое трудное в алхимии? Терпение.",
				"Каждое вещество хранит секрет. Нужно только слушать.",
				"Котёл помнит всё. Даже то, что ты забыл.",
				"Иногда туман — это просто туман. А иногда — подсказка.",
				"Ты когда-нибудь думал, почему искры разные?",
				"Мне нравится, как ты смешаешь неожиданные вещи.",
				"Алхимики древности верили: в каждом веществе — душа.",
				"Светик — это я. А ты — кто?",
				"Котёл булькает — значит, всё идёт правильно.",
				"Не бойся ошибаться. Ошибки — тоже открытия.",
				"Ты замечал, как некоторые вещества притягиваются?",
				"В природе нет случайностей. Только скрытые связи.",
				"Иногда нужно просто подождать. Котёл знает лучше.",
				"Алхимия — это не магия. Это внимание к деталям.",
				"Каждый день — новый рецепт. Буквально.",
				"Ты когда-нибудь варил что-то просто ради любопытства?",
				"Мир меняется от каждого твоего действия. Даже малого.",
				"Огонь и вода — вечный танец. Не надоедает смотреть.",
				"Земля терпелива. Вода настойчива. Огонь нетерпелив. Воздух свободен.",
				"Знаешь, почему алхимики носили мантии? Чтобы не отвлекаться.",
				"Иногда лучший рецепт — тот, который ты ещё не пробовал.",
				"Котёл не судит. Он просто варит.",
				"Ты замечал, как пахнут некоторые вещества? Незабываемо.",
				"Алхимия учит: всё связано со всем.",
				"Иногда туман рассеивается сам. Нужно просто ждать.",
				"Каждое вещество хочет быть найденным. Помоги ему.",
				"Ты — часть этого мира. И мир часть тебя.",
				"Знаешь, что общего у всех великих алхимиков? Любопытство.",
				"Не торопись. Хорошие вещи требуют времени.",
				"Котёл — это зеркало. Что вложишь, то и получишь.",
				"Иногда нужно отступить, чтобы увидеть картину целиком.",
				"Алхимия — это диалог с природой. Слушай ответы.",
				"Ты когда-нибудь думал, почему некоторые пары работают?",
				"В каждом веществе скрыта история. Раскрой её.",
				"Мир полон сюрпризов. Особенно в котле.",
				"Не бойся экспериментировать. Худшее — туман.",
				"Иногда простой рецепт оказывается самым мудрым.",
				"Ты растёшь с каждым открытием. Я вижу.",
				"Алхимики говорят: путь важнее цели.",
				"Котёл учит терпению. И смирению. И снова терпению.",
				"Знаешь, почему вода смягчает огонь? Потому что мудра.",
				"Каждое вещество имеет характер. Найди подход.",
				"Иногда лучший совет — просто попробовать.",
				"Ты когда-нибудь варил в одиночестве? Тишина помогает.",
				"Мир алхимии бесконечен. Даже если кажется иначе.",
				"Не все тайны раскрываются сразу. Некоторые — позже.",
				"Алхимия — это искусство видеть невидимое.",
				"Котёл знает больше, чем говорит.",
				"Иногда нужно просто довериться процессу.",
				"Ты замечал, как меняется свет в котле?",
				"Каждый алхимик оставляет свой след. Ты — не исключение.",
				"Знаешь, что самое ценное в алхимии? Опыт.",
				"Не торопи котёл. Он работает в своём ритме.",
				"Иногда туман — это просто передышка.",
				"Ты когда-нибудь думал, почему алхимия так затягивает?",
				"Мир меняется, когда ты меняешься. Буквально.",
				"Алхимия учит: нет плохих веществ, есть плохие сочетания.",
				"Котёл — лучший учитель. Строгий, но справедливый.",
				"Иногда нужно остановиться и просто наблюдать.",
				"Ты растёшь. Я рад за тебя.",
				"Знаешь, почему алхимики ценят тишину? В ней слышнее.",
				"Каждое открытие — это вопрос, на который ты ответил.",
				"Не бойся тумана. Он часть пути.",
				"Иногда лучший рецепт — интуиция.",
				"Ты когда-нибудь чувствовал, как котёл отзывается?",
				"Мир алхимии живёт по своим законам. Уважай их.",
				"Алхимия — это не только вещества. Это мышление.",
				"Котёл не прощает спешки. Но прощает ошибки.",
				"Иногда нужно просто быть рядом. Котёл это чувствует.",
				"Ты замечал, как некоторые вещества поют?",
				"Каждый день в котле — новый урок.",
				"Знаешь, что объединяет всех алхимиков? Упорство.",
				"Не все секреты раскрываются. Некоторые охраняются.",
				"Иногда лучший совет — молчать и слушать котёл.",
				"Ты когда-нибудь думал, почему искры имеют цвет?",
				"Мир алхимии полон чудес. Нужно только смотреть.",
				"Алхимия учит: всё имеет значение. Даже мелочи.",
				"Котёл — это мост между мирами. Ты — хранитель.",
				"Иногда нужно отпустить, чтобы получить.",
				"Ты растёшь с каждой варкой. Это видно.",
				"Знаешь, почему вода так важна? Она помнит всё.",
				"Каждое вещество хочет рассказать свою историю.",
				"Не торопись с выводами. Котёл не любит спешку.",
				"Иногда туман — это подарок. Он учит терпению.",
				"Ты когда-нибудь чувствовал связь с веществом?",
				"Мир алхимии бесконечен в своей глубине.",
				"Алхимия — это путь. И ты уже на нём.",
				"Котёл знает, когда нужно подождать.",
				"Иногда лучший рецепт — тот, который пришёл сам.",
				"Ты замечал, как меняется котёл с каждым днём?",
				"Знаешь, что самое трудное? Начать. Но ты уже начал.",
				"Каждое открытие приближает тебя к истине.",
				"Не бойся экспериментировать. Туман — не конец.",
				"Иногда нужно просто быть. Котёл это ценит.",
				"Ты — часть великой традиции. Горжусь тобой.",
			]
	if arr.is_empty():
		return ""
	return String(arr[randi() % arr.size()])


func _companion_level_for(aff: int) -> int:
	if aff >= 60:
		return 4
	if aff >= 30:
		return 3
	if aff >= 10:
		return 2
	return 1


func _companion_apply_level() -> void:
	var lv := _companion_level_for(_companion_affinity)
	_companion_level = lv
	if _companion != null:
		_companion.set_base("idle")


func _companion_gain(points: int) -> void:
	if not _companion_unlocked:
		return
	_companion_affinity += points
	var new_lv := _companion_level_for(_companion_affinity)
	if new_lv > _companion_level:
		_companion_level = new_lv
		if _companion != null:
			_companion.set_base("idle")
			_companion.set_sprite("charged", 4.0)
			_companion.say("Мы стали ближе! Дружба — уровень %d." % new_lv, "amazed")
			Sfx.legendary()
		g._engine._grant_ether(20 * new_lv, "companion_level")
		g._saves._save_game()
	g._guild._quest_on_state()
